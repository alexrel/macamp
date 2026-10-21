import Foundation
import AVFoundation
import AudioToolbox

/// Decodes a compressed network audio byte stream (MP3 / AAC-ADTS, as served by SHOUTcast and Icecast)
/// into PCM buffers that can be scheduled on an `AVAudioPlayerNode`, so internet radio runs through the
/// same AVAudioEngine graph (EQ, DSP, spectrum tap) as local files.
///
/// Not thread-safe: call `feed(_:)` from a single serial queue. Callbacks fire synchronously on that queue.
public final class StreamDecoder {
    public enum DecoderError: Error {
        case openFailed(OSStatus)
        case parseFailed(OSStatus)
        case unsupportedFormat
    }

    /// Fired once, when the stream format is known and before the first buffer.
    public var onFormatReady: ((AVAudioFormat) -> Void)?
    public var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    public private(set) var outputFormat: AVAudioFormat?

    private var streamID: AudioFileStreamID?
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var framesPerPacket: UInt32 = 1152
    private var maxPacketSize: UInt32 = 0
    private var parseError: OSStatus = noErr

    /// - Parameter contentType: HTTP Content-Type, used as a parser hint (nil lets the parser sniff).
    public init(contentType: String?) throws {
        let hint = StreamDecoder.fileTypeHint(for: contentType)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var id: AudioFileStreamID?
        let status = AudioFileStreamOpen(context, streamPropertyListener, streamPacketsCallback, hint, &id)
        guard status == noErr, let id else { throw DecoderError.openFailed(status) }
        streamID = id
    }

    deinit {
        if let streamID { AudioFileStreamClose(streamID) }
    }

    /// Returns false for HLS playlists, which AudioFileStream can't parse. Ogg Opus decodes on current macOS;
    /// Ogg Vorbis parses but AVAudioConverter outputs no audio for it (only Apple's file reader decodes it),
    /// so `feed` throws once a Vorbis or unknown format shows up and the engine falls back to AVPlayer.
    public static func canDecode(contentType: String?) -> Bool {
        guard let type = contentType?.lowercased() else { return true }
        return !type.contains("mpegurl")
    }
    
    /// 'vorb' (no public constant in AudioToolbox)
    static let vorbisFormatID: AudioFormatID = 0x766F_7262
    
    /// Bytes fed without a recognized format before giving up (a format the parser doesn't know).
    static let formatProbeLimit = 256 * 1024
    private var bytesBeforeFormat = 0
    private var hasFormat = false

    static func fileTypeHint(for contentType: String?) -> AudioFileTypeID {
        let type = contentType?.lowercased() ?? ""
        if type.contains("aac") { return kAudioFileAAC_ADTSType }
        if type.contains("mpeg") || type.contains("mp3") { return kAudioFileMP3Type }
        return 0
    }

    public func feed(_ data: Data) throws {
        guard let streamID, !data.isEmpty else { return }
        let status = data.withUnsafeBytes { raw in
            AudioFileStreamParseBytes(streamID, UInt32(raw.count), raw.baseAddress, [])
        }
        if status != noErr { throw DecoderError.parseFailed(status) }
        if !hasFormat {
            bytesBeforeFormat += data.count
            if bytesBeforeFormat > StreamDecoder.formatProbeLimit { throw DecoderError.unsupportedFormat }
        }
        if parseError != noErr {
            let err = parseError
            parseError = noErr
            throw err == kAudioFormatUnsupportedDataFormatError ? DecoderError.unsupportedFormat : DecoderError.parseFailed(err)
        }
    }

    // MARK: - AudioFileStream callbacks

    fileprivate func handleProperty(_ streamID: AudioFileStreamID, _ propertyID: AudioFileStreamPropertyID) {
        guard propertyID == kAudioFileStreamProperty_ReadyToProducePackets else { return }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(streamID, kAudioFileStreamProperty_DataFormat, &size, &asbd) == noErr,
              asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0,
              asbd.mFormatID != StreamDecoder.vorbisFormatID,
              let input = AVAudioFormat(streamDescription: &asbd) else {
            parseError = kAudioFormatUnsupportedDataFormatError
            return
        }

        var cookieSize: UInt32 = 0
        var writable: DarwinBoolean = false
        if AudioFileStreamGetPropertyInfo(streamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable) == noErr, cookieSize > 0 {
            var cookie = Data(count: Int(cookieSize))
            let status = cookie.withUnsafeMutableBytes { AudioFileStreamGetProperty(streamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, $0.baseAddress!) }
            if status == noErr { input.magicCookie = cookie }
        }

        var upperBound: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioFileStreamGetProperty(streamID, kAudioFileStreamProperty_PacketSizeUpperBound, &size, &upperBound) == noErr {
            maxPacketSize = upperBound
        }
        framesPerPacket = asbd.mFramesPerPacket > 0 ? asbd.mFramesPerPacket : 1152

        let channels = AVAudioChannelCount(min(2, max(1, asbd.mChannelsPerFrame)))
        guard let output = AVAudioFormat(standardFormatWithSampleRate: asbd.mSampleRate, channels: channels),
              let converter = AVAudioConverter(from: input, to: output) else {
            parseError = kAudioFormatUnsupportedDataFormatError
            return
        }
        self.inputFormat = input
        self.outputFormat = output
        self.converter = converter
        hasFormat = true
        onFormatReady?(output)
    }

    fileprivate func handlePackets(_ byteCount: UInt32, _ packetCount: UInt32, _ bytes: UnsafeRawPointer,
                                   _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard let inputFormat, let converter, let outputFormat, packetCount > 0, let descriptions else { return }

        var largestPacket = maxPacketSize
        for i in 0..<Int(packetCount) {
            largestPacket = max(largestPacket, descriptions[i].mDataByteSize)
        }
        let compressed = AVAudioCompressedBuffer(format: inputFormat, packetCapacity: AVAudioPacketCount(packetCount), maximumPacketSize: Int(max(1, largestPacket)))
        guard let targetDescriptions = compressed.packetDescriptions else { return }
        // Copy packet payloads back to back. The source block also contains per-packet framing
        // (ADTS headers, MP3 side gaps) that the descriptions skip via mStartOffset.
        var written: Int64 = 0
        for i in 0..<Int(packetCount) {
            let source = descriptions[i]
            let size = Int(source.mDataByteSize)
            guard source.mStartOffset >= 0, Int(source.mStartOffset) + size <= Int(byteCount),
                  Int(written) + size <= compressed.byteCapacity else { return }
            (compressed.data + Int(written)).copyMemory(from: bytes + Int(source.mStartOffset), byteCount: size)
            targetDescriptions[i] = AudioStreamPacketDescription(mStartOffset: written,
                                                                 mVariableFramesInPacket: source.mVariableFramesInPacket,
                                                                 mDataByteSize: source.mDataByteSize)
            written += Int64(size)
        }
        compressed.byteLength = UInt32(written)
        compressed.packetCount = AVAudioPacketCount(packetCount)

        let capacity = AVAudioFrameCount(packetCount * framesPerPacket)
        var supplied = false
        // One convert() call may return only part of the decoded audio (status .haveData = "more output
        // pending"), so keep draining until the converter asks for more input.
        while true {
            guard let pcm = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            var error: NSError?
            let status = converter.convert(to: pcm, error: &error) { _, inputStatus in
                if supplied {
                    // Keep the converter's state (decoder priming) for the next network chunk
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return compressed
            }
            if status == .error { return }
            if pcm.frameLength > 0 {
                onBuffer?(pcm)
            }
            if status != .haveData || pcm.frameLength == 0 { return }
        }
    }
}

private func streamPropertyListener(_ context: UnsafeMutableRawPointer, _ streamID: AudioFileStreamID,
                                    _ propertyID: AudioFileStreamPropertyID,
                                    _ flags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>) {
    Unmanaged<StreamDecoder>.fromOpaque(context).takeUnretainedValue().handleProperty(streamID, propertyID)
}

private func streamPacketsCallback(_ context: UnsafeMutableRawPointer, _ byteCount: UInt32, _ packetCount: UInt32,
                                   _ bytes: UnsafeRawPointer, _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
    Unmanaged<StreamDecoder>.fromOpaque(context).takeUnretainedValue().handlePackets(byteCount, packetCount, bytes, descriptions)
}
