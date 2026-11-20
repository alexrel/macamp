import Foundation
import CryptoKit

/// MacAmp plug-ins, Winamp's in_*.dll as separate programs: ~/Library/Application Support/MacAmp/Plug-ins/*.macampplugin.
/// MacAmp can't load unsigned code into itself, and a codec that crashes takes only its own process down.
/// One kind so far, "converter": turns a file MacAmp can't read into one it plays as usual. in_ffmpeg brings ffmpeg and
/// ffprobe (MP4 or FLAC out); in_mod brings its own renderer named by MacAmpPluginRenderer (`<tool> <in> <out.wav>`).
enum PluginManager {
    struct Converter {
        let bundle: URL
        let title: String
        let audioExtensions: Set<String>
        let videoExtensions: Set<String>
        /// A plug-in's own tool instead of ffmpeg: prints "progress=<0...1>" lines, writes a WAV
        var renderer: URL?
        /// Formats its ffmpeg can write (MacAmpPluginEncoders: "ogg", "mp3"), for CD Ripping and Disk Writer
        var encoders: Set<String> = []
        var ffmpeg: URL { bundle.appendingPathComponent("Contents/MacOS/ffmpeg") }
        var ffprobe: URL { bundle.appendingPathComponent("Contents/MacOS/ffprobe") }
        var extensions: Set<String> { audioExtensions.union(videoExtensions) }
    }

    /// Formats the FFmpeg plug-in adds: files with these extensions get "install the plug-in" instead of silence
    static let ffmpegFormats: Set<String> = ["mkv", "webm", "avi", "wmv", "asf", "flv", "mpg", "mpeg", "vob", "ts", "m2ts", "mts", "3gp", "ogv",
                                             "wma", "ape", "wv", "tta", "ac3", "dts", "mka", "amr"]
    /// Tracker modules the Module plug-in (in_mod, libopenmpt) adds
    static let moduleFormats: Set<String> = ["mod", "xm", "s3m", "it", "mptm", "mtm", "669", "stm", "ult", "med", "okt", "far",
                                             "amf", "dmf", "psm", "umx"]

    /// The plug-in a format needs, for "install the ... plug-in" when it's missing
    static func missingPlugin(for ext: String) -> String? {
        ffmpegFormats.contains(ext) ? "FFmpeg" : moduleFormats.contains(ext) ? "Module" : nil
    }

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
        PluginConversion.forgetInfo()
    }

    private static let kindKey = "MacAmpPluginKind", titleKey = "MacAmpPluginTitle"

    /// The bundle's Info.plist when it is a MacAmp plug-in of this kind
    private static func info(_ bundle: URL, kind: String) -> [String: Any]? {
        guard let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              info[kindKey] as? String == kind else { return nil }
        return info
    }

    private static func title(_ info: [String: Any], _ bundle: URL) -> String {
        info[titleKey] as? String ?? bundle.deletingPathExtension().lastPathComponent
    }

    static func read(_ bundle: URL) -> Converter? {
        guard let info = info(bundle, kind: "converter") else { return nil }
        // A tool name only, never a path out of the bundle
        let renderer = (info["MacAmpPluginRenderer"] as? String).flatMap { $0.isEmpty || $0.contains("/") ? nil : $0 }
            .map { bundle.appendingPathComponent("Contents/MacOS/\($0)") }
        let converter = Converter(bundle: bundle, title: title(info, bundle),
                                  audioExtensions: Set((info["MacAmpPluginAudioExtensions"] as? [String] ?? []).map { $0.lowercased() }),
                                  videoExtensions: Set((info["MacAmpPluginVideoExtensions"] as? [String] ?? []).map { $0.lowercased() }),
                                  renderer: renderer,
                                  encoders: Set((info["MacAmpPluginEncoders"] as? [String] ?? []).map { $0.lowercased() }))
        let tools = renderer.map { [$0] } ?? [converter.ffmpeg, converter.ffprobe]
        guard tools.allSatisfy({ FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
        return converter
    }

    /// Kinds "avs-presets" and "milkdrop-presets": a pack of presets (Contents/Resources/<folder>/…), installed into
    /// that visualizer's preset folder. Returns its title, whether it is MilkDrop's, and the folders it brings.
    static func presetPack(_ bundle: URL) -> (title: String, milkdrop: Bool, folders: [URL])? {
        let milkdrop = info(bundle, kind: "milkdrop-presets")
        guard let info = milkdrop ?? info(bundle, kind: "avs-presets") else { return nil }
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? []
        return (title(info, bundle), milkdrop != nil, folders)
    }

    /// Copies preset files with this extension, or folders of them (keeping their subfolders), into `folder`;
    /// presets already there stay as they are. Returns how many were copied.
    nonisolated static func copyPresets(_ urls: [URL], extension ext: String, into folder: URL) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var copied = 0
        func copy(_ url: URL, into destination: URL) {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let target = destination.appendingPathComponent(url.lastPathComponent, isDirectory: true)
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                for item in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles])) ?? [] {
                    copy(item, into: target)
                }
            } else if url.pathExtension.lowercased() == ext {
                let target = destination.appendingPathComponent(url.lastPathComponent)
                guard !fm.fileExists(atPath: target.path) else { return }
                if (try? fm.copyItem(at: url, to: target)) != nil { copied += 1 }
            }
        }
        for url in urls { copy(url, into: folder) }
        return copied
    }

    static var extensions: Set<String> { converters.reduce(into: Set<String>()) { $0.formUnion($1.extensions) } }
    static var videoExtensions: Set<String> { converters.reduce(into: Set<String>()) { $0.formUnion($1.videoExtensions) } }

    /// The installed plug-in whose ffmpeg writes this format ("ogg", "mp3")
    static func encoder(for ext: String) -> Converter? {
        converters.first { $0.renderer == nil && $0.encoders.contains(ext) }
    }

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
        return ["mp4", "flac", "wav"].map { cacheFolder.appendingPathComponent("\(key).\($0)") }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    struct Stream: Decodable {
        let index: Int
        let codec_type: String?
        let codec_name: String?
        let height: Int?
        let disposition: [String: Int]?
    }
    struct Probe: Decodable {
        struct Format: Decodable { let duration: String?; let tags: [String: String]? }
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
        if let renderer = converter.renderer { return try await render(url, with: renderer) }
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

    /// CD Ripping / Disk Writer to Ogg Vorbis or MP3: the plug-in's ffmpeg encodes a WAV (no partial file is left on error
    /// or cancel; an existing file of the same name is replaced, as a re-rip should)
    static func encode(_ wav: URL, to output: URL, codec: String, kbps: Int, with encoder: PluginManager.Converter) async throws {
        let partial = output.deletingPathExtension().appendingPathExtension("partial.\(output.pathExtension)")
        try? FileManager.default.removeItem(at: partial)
        do {
            _ = try await run(encoder.ffmpeg, ["-nostdin", "-y", "-v", "error", "-i", wav.path, "-c:a", codec, "-b:a", "\(kbps)k", partial.path])
            if FileManager.default.fileExists(atPath: output.path) {
                _ = try FileManager.default.replaceItemAt(output, withItemAt: partial)
            } else {
                try FileManager.default.moveItem(at: partial, to: output)
            }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// Tags into an Ogg / MP3 file with the plug-in's ffmpeg: the audio is copied, not encoded again
    static func retag(_ url: URL, tags: [String: String], with encoder: PluginManager.Converter) async throws {
        let partial = url.deletingPathExtension().appendingPathExtension("tagging.\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: partial) }
        let metadata = tags.sorted { $0.key < $1.key }.flatMap { ["-metadata", "\($0.key)=\($0.value)"] }
        _ = try await run(encoder.ffmpeg, ["-nostdin", "-y", "-v", "error", "-i", url.path, "-map", "0", "-c", "copy"] + metadata + [partial.path])
        _ = try FileManager.default.replaceItemAt(url, withItemAt: partial)
    }

    /// Length and tags of a file only a plug-in reads, without converting it: for the playlist before it plays
    struct Info: Sendable, Equatable {
        let duration: TimeInterval
        let artist: String
        let title: String
    }

    /// Asked once per file (a playlist reads length and tags separately, often at the same time). A plug-in without
    /// this (an older in_mod) answers nil and the playlist keeps the file name and 0:00 until the file plays.
    static func info(for url: URL) async -> Info? {
        guard let converter = PluginManager.converter(for: url) else { return nil }
        return await infoCache.task(for: cacheKey(url)) { await readInfo(url, with: converter) }.value
    }

    static func forgetInfo() { infoCache.clear() }

    private static func readInfo(_ url: URL, with converter: PluginManager.Converter) async -> Info? {
        if let renderer = converter.renderer {
            // "--info" first: an older renderer then fails on it as a file name instead of writing over `url`
            guard let data = try? await run(renderer, ["--info", url.path]) else { return nil }
            var fields: [String: String] = [:]
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                fields[String(line[..<eq])] = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            }
            guard let duration = fields["duration"].flatMap(Double.init) else { return nil }
            return Info(duration: duration, artist: fields["artist"] ?? "", title: fields["title"] ?? "")
        }
        guard let probe = try? await probe(url, with: converter) else { return nil }
        // Tag names vary by format (title, TITLE, Title)
        let tags = Dictionary((probe.format?.tags ?? [:]).map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        return Info(duration: probe.duration, artist: tags["artist"] ?? "", title: tags["title"] ?? "")
    }

    private static let infoCache = InfoCache()

    private final class InfoCache: @unchecked Sendable {
        private let lock = NSLock()
        private var tasks: [String: Task<Info?, Never>] = [:]
        func task(for key: String, _ make: @escaping @Sendable () async -> Info?) -> Task<Info?, Never> {
            lock.lock(); defer { lock.unlock() }
            if let task = tasks[key] { return task }
            let task = Task { await make() }
            tasks[key] = task
            return task
        }
        func clear() { lock.lock(); tasks = [:]; lock.unlock() }
    }

    /// What a renderer prints before each progress fraction (scripts/in_mod/openmpt-render.c)
    static let rendererProgress = "progress="

    /// A plug-in's own renderer (in_mod): `<tool> <input> <output.wav>`, progress as "progress=<0...1>" lines.
    /// shortcut: WAV, 10 MB a minute, where FLAC would be half; fine for modules of a few minutes, revisit if people
    /// render hour-long ones
    static func render(_ url: URL, with tool: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        let output = cacheFolder.appendingPathComponent("\(cacheKey(url)).wav")
        let partial = output.deletingPathExtension().appendingPathExtension("partial.wav")
        try? FileManager.default.removeItem(at: partial)
        do {
            _ = try await run(tool, [url.path, partial.path]) { line in
                guard line.hasPrefix(rendererProgress), let fraction = Double(line.dropFirst(rendererProgress.count)) else { return }
                Task { @MainActor in onProgress?(url, min(1, max(0, fraction))) }
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
