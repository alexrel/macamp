import Foundation
import CryptoKit

/// MacAmp plug-ins, Winamp's in_*.dll as separate programs: ~/Library/Application Support/MacAmp/Plug-ins/*.macampplugin.
/// MacAmp can't load unsigned code into itself, and a codec that crashes takes only its own process down.
/// One kind so far, "converter" (in_ffmpeg): turns a file MacAmp can't read into MP4 or FLAC it plays as usual.
enum PluginManager {
    struct Converter {
        let bundle: URL
        let title: String
        let audioExtensions: Set<String>
        let videoExtensions: Set<String>
        var ffmpeg: URL { bundle.appendingPathComponent("Contents/MacOS/ffmpeg") }
        var ffprobe: URL { bundle.appendingPathComponent("Contents/MacOS/ffprobe") }
        var extensions: Set<String> { audioExtensions.union(videoExtensions) }
    }

    /// Formats the FFmpeg plug-in adds: files with these extensions get "install the plug-in" instead of silence
    static let ffmpegFormats: Set<String> = ["mkv", "webm", "avi", "wmv", "asf", "flv", "mpg", "mpeg", "vob", "ts", "m2ts", "mts", "3gp", "ogv",
                                             "wma", "ape", "wv", "tta", "ac3", "dts", "mka", "amr"]

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacAmp/Plug-ins", isDirectory: true)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Converter]?

    /// Installed converters (read once, again after an install)
    static var converters: [Converter] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let found = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "macampplugin" }
            .compactMap(read)
        cache = found
        return found
    }

    static func reload() {
        lock.lock(); cache = nil; lock.unlock()
    }

    static func read(_ bundle: URL) -> Converter? {
        guard let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              info["MacAmpPluginKind"] as? String == "converter" else { return nil }
        let converter = Converter(bundle: bundle, title: info["MacAmpPluginTitle"] as? String ?? bundle.deletingPathExtension().lastPathComponent,
                                  audioExtensions: Set((info["MacAmpPluginAudioExtensions"] as? [String] ?? []).map { $0.lowercased() }),
                                  videoExtensions: Set((info["MacAmpPluginVideoExtensions"] as? [String] ?? []).map { $0.lowercased() }))
        guard FileManager.default.isExecutableFile(atPath: converter.ffmpeg.path),
              FileManager.default.isExecutableFile(atPath: converter.ffprobe.path) else { return nil }
        return converter
    }

    static var extensions: Set<String> { converters.reduce(into: Set<String>()) { $0.formUnion($1.extensions) } }
    static var videoExtensions: Set<String> { converters.reduce(into: Set<String>()) { $0.formUnion($1.videoExtensions) } }

    static func converter(for url: URL) -> Converter? {
        guard url.isFileURL else { return nil }
        let ext = url.pathExtension.lowercased()
        return converters.first { $0.extensions.contains(ext) }
    }

    /// Copies a plug-in into the Plug-ins folder (replacing an older copy) and clears the "downloaded from the
    /// internet" mark so macOS lets MacAmp run its programs. Called only after the user confirms.
    static func install(_ bundle: URL) throws -> Converter {
        guard read(bundle) != nil else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(bundle.lastPathComponent)
        if bundle.standardizedFileURL != target.standardizedFileURL {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: bundle, to: target)
        }
        let paths = [target.path] + (FileManager.default.enumerator(atPath: target.path)?.compactMap { $0 as? String }.map { target.appendingPathComponent($0).path } ?? [])
        for path in paths { removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW) }
        reload()
        guard let installed = read(target) else { throw CocoaError(.fileReadCorruptFile) }
        return installed
    }
}

/// Converting a file once with a converter plug-in (Caches/MacAmp/Converted), then playing the result:
/// audio → FLAC (lossless); video → MP4, its streams copied when macOS decodes them, else H.264 (the Mac's
/// hardware encoder) / AAC; text subtitles → mov_text. All audio tracks and subtitles come along.
enum PluginConversion {
    static var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacAmp/Converted", isDirectory: true)
    }
    /// shortcut: a fixed 4 GB cache, oldest files go first; make it a preference if people keep many films
    static let cacheLimit: Int64 = 4 << 30

    /// Progress (0...1) of a running conversion, for the marquee and the video window
    @MainActor static var onProgress: ((URL, Double) -> Void)?

    static func needsConversion(_ url: URL) -> Bool { PluginManager.converter(for: url) != nil }

    static func cacheKey(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let stamp = "\(url.standardizedFileURL.path)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)"
        return Insecure.MD5.hash(data: Data(stamp.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The converted file if it's in the cache already
    static func cachedOutput(for url: URL) -> URL? {
        let key = cacheKey(url)
        return ["mp4", "flac"].map { cacheFolder.appendingPathComponent("\(key).\($0)") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    struct Stream: Decodable {
        let index: Int
        let codec_type: String?
        let codec_name: String?
        let height: Int?
        let disposition: [String: Int]?
    }
    struct Probe: Decodable {
        struct Format: Decodable { let duration: String? }
        let streams: [Stream]
        let format: Format?
        var duration: Double { Double(format?.duration ?? "") ?? 0 }
        /// Real picture streams (not album art in an audio file)
        var video: [Stream] { streams.filter { $0.codec_type == "video" && $0.disposition?["attached_pic"] != 1 } }
        var audio: [Stream] { streams.filter { $0.codec_type == "audio" } }
        var textSubtitles: [Stream] { streams.filter { $0.codec_type == "subtitle" && PluginConversion.textSubtitles.contains($0.codec_name ?? "") } }
    }

    /// Codecs an MP4 carries that macOS plays as they are
    static let copyVideo: Set<String> = ["h264", "hevc", "vp9", "av1"]
    static let copyAudio: Set<String> = ["aac", "mp3", "ac3", "eac3", "alac"]
    static let textSubtitles: Set<String> = ["subrip", "srt", "ass", "ssa", "webvtt", "mov_text", "text"]

    /// The ffmpeg arguments for one file (input, output and progress added by `convert`)
    static func arguments(for probe: Probe) -> (args: [String], ext: String) {
        guard let video = probe.video.first else {
            return (["-map", "0:a:0", "-vn", "-sn", "-c:a", "flac", "-map_metadata", "0"], "flac")
        }
        var args = ["-map", "0:\(video.index)"]
        if copyVideo.contains(video.codec_name ?? "") {
            args += ["-c:v", "copy"] + (video.codec_name == "hevc" ? ["-tag:v", "hvc1"] : [])
        } else {
            let height = video.height ?? 0
            let rate = height >= 1000 ? "8M" : height >= 700 ? "5M" : "2500k"
            args += ["-c:v", "h264_videotoolbox", "-b:v", rate, "-pix_fmt", "yuv420p"]
        }
        for (i, stream) in probe.audio.enumerated() {
            args += ["-map", "0:\(stream.index)"]
            args += copyAudio.contains(stream.codec_name ?? "") ? ["-c:a:\(i)", "copy"] : ["-c:a:\(i)", "aac", "-b:a:\(i)", "192k"]
        }
        for stream in probe.textSubtitles { args += ["-map", "0:\(stream.index)"] }
        if !probe.textSubtitles.isEmpty { args += ["-c:s", "mov_text"] }
        return (args + ["-map_metadata", "0"], "mp4")
    }

    static func probe(_ url: URL, with converter: PluginManager.Converter) async throws -> Probe {
        let data = try await run(converter.ffprobe, ["-v", "error", "-print_format", "json", "-show_streams", "-show_format", url.path])
        return try JSONDecoder().decode(Probe.self, from: data)
    }

    /// Converts once (cached); cancelling the task stops ffmpeg and leaves no partial file
    static func convert(_ url: URL) async throws -> URL {
        if let cached = cachedOutput(for: url) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cached.path) // recently used
            return cached
        }
        guard let converter = PluginManager.converter(for: url) else { throw CocoaError(.fileReadUnsupportedScheme) }
        let probe = try await probe(url, with: converter)
        let (args, ext) = arguments(for: probe)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        let output = cacheFolder.appendingPathComponent("\(cacheKey(url)).\(ext)")
        let partial = output.deletingPathExtension().appendingPathExtension("partial.\(ext)")
        try? FileManager.default.removeItem(at: partial)
        let duration = probe.duration
        do {
            _ = try await run(converter.ffmpeg, ["-nostdin", "-y", "-v", "error", "-i", url.path] + args
                              + ["-progress", "pipe:1", "-nostats", partial.path]) { line in
                // "out_time_us=12345678" every half second
                guard duration > 0, line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) else { return }
                let fraction = min(1, max(0, us / 1_000_000 / duration))
                Task { @MainActor in onProgress?(url, fraction) }
            }
            try FileManager.default.moveItem(at: partial, to: output)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        trimCache(keeping: output)
        return output
    }

    /// Oldest conversions go first once the folder passes the limit
    static func trimCache(keeping current: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = ((try? FileManager.default.contentsOfDirectory(at: cacheFolder, includingPropertiesForKeys: keys)) ?? [])
            .compactMap { url -> (URL, Date, Int64)? in
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                return (url, v.contentModificationDate ?? .distantPast, Int64(v.fileSize ?? 0))
            }
            .sorted { $0.1 < $1.1 }
        var total = files.reduce(Int64(0)) { $0 + $1.2 }
        for (url, _, size) in files where total > cacheLimit && url != current {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }

    struct PluginError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Runs a plug-in program; stdout comes back (or line by line to `onLine`), stderr becomes the error message
    static func run(_ tool: URL, _ arguments: [String], onLine: (@Sendable (String) -> Void)? = nil) async throws -> Data {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let collected = LockedData()
        running.insert(process)
        defer { running.remove(process) }
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            collected.append(chunk)
            if let onLine, let text = String(data: chunk, encoding: .utf8) { text.split(separator: "\n").forEach { onLine(String($0)) } }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                process.terminationHandler = { p in
                    out.fileHandleForReading.readabilityHandler = nil
                    collected.append(out.fileHandleForReading.readDataToEndOfFile())
                    let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if p.terminationReason == .uncaughtSignal { continuation.resume(throwing: CancellationError()) }
                    else if p.terminationStatus != 0 { continuation.resume(throwing: PluginError(message: message.isEmpty ? "\(tool.lastPathComponent) failed" : message)) }
                    else { continuation.resume(returning: collected.data) }
                }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            process.terminate()
        }
    }

    /// Plug-in programs at work, so Stop can end a conversion
    private static let running = RunningProcesses()

    /// Stop pressed during "Converting for playback": end it (nothing is cached, no partial file stays)
    static func cancelAll() { running.terminateAll() }

    private final class RunningProcesses: @unchecked Sendable {
        private let lock = NSLock()
        private var processes: [ObjectIdentifier: Process] = [:]
        func insert(_ p: Process) { lock.lock(); processes[ObjectIdentifier(p)] = p; lock.unlock() }
        func remove(_ p: Process) { lock.lock(); processes[ObjectIdentifier(p)] = nil; lock.unlock() }
        func terminateAll() { lock.lock(); let all = Array(processes.values); lock.unlock(); all.forEach { $0.terminate() } }
    }

    private final class LockedData: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        func append(_ chunk: Data) { lock.lock(); storage.append(chunk); lock.unlock() }
        var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
    }
}
