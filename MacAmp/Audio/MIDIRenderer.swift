import AVFoundation
import AudioToolbox
import CryptoKit

/// MIDI playback (Winamp's in_midi): the file is rendered once, offline, with Apple's General MIDI synth
/// (DLSSynth: GM instruments, program changes, drums on channel 10) into a cached CAF, which then plays like
/// any audio file — EQ, visualizer, seeking and crossfade work unchanged.
public enum MIDIRenderer {
    public static let extensions: Set<String> = ["mid", "midi", "rmi", "kar"]

    public static func isMIDI(_ url: URL) -> Bool {
        url.isFileURL && extensions.contains(url.pathExtension.lowercased())
    }

    /// Notes ring on after the last event; keep this much of the release.
    static let tail: TimeInterval = 1.5
    static let sampleRate: Double = 44100

    /// Playing time without rendering: the music plus the release tail (the same length the rendered audio has).
    public static func duration(of url: URL) -> TimeInterval {
        guard let data = try? smfData(from: url) else { return 0 }
        let sequencer = AVAudioSequencer()
        guard (try? sequencer.load(from: data, options: [])) != nil,
              let music = sequencer.tracks.map(\.lengthInSeconds).max(), music > 0 else { return 0 }
        return music + tail
    }

    /// The rendered audio for `url`, rendering it on first use (or after the MIDI file changed).
    public static func renderedFile(for url: URL) async throws -> URL {
        let cached = try cacheURL(for: url)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        try await Task.detached(priority: .userInitiated) { try render(url, to: cached) }.value
        return cached
    }

    static func cacheURL(for url: URL) throws -> URL {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = "\(url.standardizedFileURL.path)|\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\((attributes[.size] as? Int) ?? 0)"
        let name = Insecure.MD5.hash(data: Data(stamp.utf8)).map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacAmp/MIDI", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name + ".caf")
    }

    /// Standard MIDI file bytes; .rmi wraps them in a RIFF "RMID" container ("data" chunk).
    static func smfData(from url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard data.count > 20, data.prefix(4) == Data("RIFF".utf8), data[8..<12] == Data("RMID".utf8) else { return data }
        var offset = 12
        while offset + 8 <= data.count {
            let id = data[offset..<offset + 4]
            let size = Int(data[offset + 4]) | Int(data[offset + 5]) << 8 | Int(data[offset + 6]) << 16 | Int(data[offset + 7]) << 24
            if id == Data("data".utf8) { return data.subdata(in: offset + 8..<min(data.count, offset + 8 + size)) }
            offset += 8 + size + (size & 1)
        }
        return data
    }

    static func render(_ url: URL, to output: URL) throws {
        let engine = AVAudioEngine()
        let synth = AVAudioUnitMIDIInstrument(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice, componentSubType: kAudioUnitSubType_DLSSynth,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        engine.attach(synth)
        engine.connect(synth, to: engine.mainMixerNode, format: nil)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)

        let sequencer = AVAudioSequencer(audioEngine: engine)
        try sequencer.load(from: smfData(from: url), options: [])
        for track in sequencer.tracks { track.destinationAudioUnit = synth }
        let length = (sequencer.tracks.map(\.lengthInSeconds).max() ?? 0) + tail

        try engine.start()
        defer { engine.stop() }
        sequencer.prepareToPlay()
        try sequencer.start()

        // Write to a temporary name first: a half-written cache file must never be picked up
        let partial = output.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        do { // the file closes at the end of this scope, before it is renamed
            let file = try AVAudioFile(forWriting: partial, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
            let total = AVAudioFramePosition(length * sampleRate)
            while engine.manualRenderingSampleTime < total {
                let frames = AVAudioFrameCount(min(4096, total - engine.manualRenderingSampleTime))
                guard try engine.renderOffline(frames, to: buffer) == .success else { break }
                try file.write(from: buffer)
            }
        }
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: partial, to: output)
    }
}
