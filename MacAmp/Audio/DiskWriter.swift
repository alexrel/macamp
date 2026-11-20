import AVFoundation

/// Winamp's Disk Writer output (out_disk): instead of the speakers, playback goes into audio files.
/// MacAmp writes them with the encoders macOS has: WAV, AIFF, FLAC, Apple Lossless, AAC; with the FFmpeg plug-in also
/// Ogg Vorbis (what 2.95 ripped to) and MP3.
public enum DiskWriterFormat: String, CaseIterable, Codable {
    case wav, aiff, flac, alac, aac, ogg, mp3

    public var title: String {
        switch self {
        case .wav: return "WAV (PCM)"
        case .aiff: return "AIFF (PCM)"
        case .flac: return "FLAC (lossless)"
        case .alac: return "Apple Lossless (.m4a)"
        case .aac: return "AAC (.m4a)"
        case .ogg: return "Ogg Vorbis"
        case .mp3: return "MP3"
        }
    }

    /// Encoded by the FFmpeg plug-in's ffmpeg (macOS has no encoder for them)
    var needsEncoderPlugin: Bool { self == .ogg || self == .mp3 }

    /// What Preferences offers: macOS's own formats, plus Ogg Vorbis and MP3 while a plug-in that encodes them is installed
    public static var available: [DiskWriterFormat] {
        allCases.filter { !$0.needsEncoderPlugin || PluginManager.encoder(for: $0.fileExtension) != nil }
    }

    /// Lossy formats take a bitrate (CD Ripping ▸ Encoder ▸ Bitrate)
    public var hasBitrate: Bool { self == .aac || needsEncoderPlugin }

    var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .flac: return "flac"
        case .alac, .aac: return "m4a"
        case .ogg: return "ogg"
        case .mp3: return "mp3"
        }
    }

    /// Bitrate choices (kbps) for AAC, Ogg Vorbis and MP3 in CD Ripping ▸ Encoder; Disk Writer uses 256
    public static let aacBitrates = [128, 160, 192, 256, 320]

    func settings(sampleRate: Double, channels: AVAudioChannelCount, aacKbps: Int = 256) -> [String: Any] {
        var settings: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels]
        switch self {
        case .wav, .aiff, .ogg, .mp3: // Ogg / MP3: a WAV first, the plug-in encodes it
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = self == .aiff
        case .flac:
            settings[AVFormatIDKey] = kAudioFormatFLAC
            settings[AVEncoderBitDepthHintKey] = 16
        case .alac:
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVEncoderBitDepthHintKey] = 16
        case .aac:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = aacKbps * 1000
        }
        return settings
    }
}

public enum DiskWriter {
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("MacAmp Disk Writer")
    }

    /// Writes one playlist entry (a file, a CUE track or a MIDI file) into `folder` as `name.ext` and returns it.
    /// Cancelling the calling task stops the write between chunks and leaves no partial file.
    /// `name` (CD ripping) may hold subfolders: "Artist - Album/01 - Title".
    public static func write(_ track: TrackItem, to folder: URL, name: String? = nil, format: DiskWriterFormat, aacKbps: Int = 256) async throws -> URL {
        let source = track.url.withoutPlaybackRange
        let audioURL = MIDIRenderer.isMIDI(source) ? try await MIDIRenderer.renderedFile(for: source) : source
        // Disk Writer never overwrites ("Name (2)"); a CD rip's own name means the same track, so ripping again replaces it
        let output = name.map { folder.appendingPathComponent($0).appendingPathExtension(format.fileExtension) }
            ?? uniqueURL(in: folder, name: fileName(for: track), ext: format.fileExtension)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let range = track.url.playbackRange
        guard format.needsEncoderPlugin else {
            let job = Task.detached(priority: .userInitiated) {
                try convert(audioURL, range: range, to: output, format: format, aacKbps: aacKbps) { Task.isCancelled }
            }
            try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
            return output
        }
        // Ogg Vorbis / MP3: a WAV in the temporary folder, then the plug-in's ffmpeg encodes it next to where it belongs
        guard let encoder = PluginManager.encoder(for: format.fileExtension) else {
            throw PluginConversion.PluginError(message: "\(format.title) needs the FFmpeg plug-in (Preferences ▸ Plug-ins ▸ Input)")
        }
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("MacAmp-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        let job = Task.detached(priority: .userInitiated) {
            try convert(audioURL, range: range, to: wav, format: .wav) { Task.isCancelled }
        }
        try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        try await PluginConversion.encode(wav, to: output, codec: format == .ogg ? "libvorbis" : "libmp3lame", kbps: aacKbps, with: encoder)
        return output
    }

    static func convert(_ input: URL, range: (start: TimeInterval, end: TimeInterval?)?, to output: URL,
                        format: DiskWriterFormat, aacKbps: Int = 256, isCancelled: () -> Bool) throws {
        let source = try AVAudioFile(forReading: input)
        let pcm = source.processingFormat
        let first = AVAudioFramePosition((range?.start ?? 0) * pcm.sampleRate)
        let last = range?.end.map { min(source.length, AVAudioFramePosition($0 * pcm.sampleRate)) } ?? source.length
        source.framePosition = min(first, source.length)
        let partial = output.deletingPathExtension().appendingPathExtension("partial." + output.pathExtension)
        do { // closed at the end of this scope, before the rename
            let target = try AVAudioFile(forWriting: partial, settings: format.settings(sampleRate: pcm.sampleRate, channels: pcm.channelCount, aacKbps: aacKbps),
                                         commonFormat: pcm.commonFormat, interleaved: pcm.isInterleaved)
            let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 32768)!
            while source.framePosition < last {
                if isCancelled() { throw CancellationError() }
                let frames = AVAudioFrameCount(min(32768, last - source.framePosition))
                try source.read(into: buffer, frameCount: frames)
                guard buffer.frameLength > 0 else { break }
                try target.write(from: buffer)
            }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        if FileManager.default.fileExists(atPath: output.path) {
            _ = try FileManager.default.replaceItemAt(output, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: output)
        }
    }

    /// "Artist - Title" (or the file name), without characters Finder can't show.
    static func fileName(for track: TrackItem) -> String {
        let name = track.displayName.isEmpty ? track.url.deletingPathExtension().lastPathComponent : track.displayName
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Track" : cleaned
    }

    /// Never overwrites: "Name.wav", "Name (2).wav", ...
    static func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        var url = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) (\(n))").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
