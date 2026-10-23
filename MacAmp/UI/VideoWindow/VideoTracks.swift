import AVFoundation
import CryptoKit

/// Audio tracks and subtitles of a video (Video window ▼ ▸ Audio track / Subtitles).
/// The engine plays the file's first audio track; picking another one plays it from a copy of just that track
/// (taken out without re-encoding), so the EQ, visualizer and seeking stay as they are.
enum VideoTracks {
    struct AudioTrack: Equatable {
        let id: CMPersistentTrackID
        let title: String
    }

    /// The video's audio tracks, titled like "Russian (AAC, 2 ch)"
    static func audioTracks(of url: URL) async -> [AudioTrack] {
        let tracks = (try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio)) ?? []
        var result: [AudioTrack] = []
        for (i, track) in tracks.enumerated() {
            let tag = (try? await track.load(.extendedLanguageTag)) ?? nil
            let code = (try? await track.load(.languageCode)) ?? nil
            let language = (tag ?? code).flatMap { $0 == "und" ? nil : $0 }
            let name = language.flatMap { Locale.current.localizedString(forLanguageCode: $0)?.capitalized } ?? "Track \(i + 1)"
            var details: [String] = []
            if let format = (try? await track.load(.formatDescriptions))?.first {
                details.append(codecName(CMFormatDescriptionGetMediaSubType(format)))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee, asbd.mChannelsPerFrame > 0 {
                    details.append("\(asbd.mChannelsPerFrame) ch")
                }
            }
            result.append(AudioTrack(id: track.trackID, title: details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"))
        }
        return result
    }

    static func codecName(_ code: FourCharCode) -> String {
        switch code {
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: return "AAC"
        case kAudioFormatAC3: return "AC3"
        case kAudioFormatEnhancedAC3: return "E-AC3"
        case kAudioFormatOpus: return "Opus"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatLinearPCM: return "PCM"
        default: return VideoController.fourCC(code)
        }
    }

    // MARK: Chosen track per video (read by the engine off the main thread)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var chosen: [URL: URL] = [:]

    /// The audio file the engine plays for this video, when a track other than the first was picked
    static func audioOverride(for video: URL) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return chosen[video.standardizedFileURL]
    }

    static func setOverride(_ audio: URL?, for video: URL) {
        lock.lock(); defer { lock.unlock() }
        chosen[video.standardizedFileURL] = audio
    }

    /// One audio track of the video as its own .m4a (cached): copied as is, or AAC when .m4a can't hold the codec
    static func extract(_ trackID: CMPersistentTrackID, from video: URL) async throws -> URL {
        let modified = (try? video.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = Insecure.MD5.hash(data: Data("\(video.path)|\(modified)|\(trackID)".utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacAmp/AudioTracks", isDirectory: true)
        let output = folder.appendingPathComponent(key + ".m4a")
        if FileManager.default.fileExists(atPath: output.path) { return output }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let asset = AVURLAsset(url: video)
        guard let source = try await asset.loadTrack(withTrackID: trackID) else { throw CocoaError(.fileReadCorruptFile) }
        let composition = AVMutableComposition()
        guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try target.insertTimeRange(try await source.load(.timeRange), of: source, at: .zero)
        let partial = output.deletingPathExtension().appendingPathExtension("partial.m4a")
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetAppleM4A] {
            try? FileManager.default.removeItem(at: partial)
            guard let export = AVAssetExportSession(asset: composition, presetName: preset) else { continue }
            export.outputURL = partial
            export.outputFileType = .m4a
            await export.export()
            if export.status == .completed {
                try FileManager.default.moveItem(at: partial, to: output)
                return output
            }
        }
        throw CocoaError(.fileWriteUnknown)
    }
}

/// One subtitle: text shown from `start` to `end` (seconds)
struct SubtitleCue: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

/// SubRip (.srt) subtitles next to a video: "Film.srt", "Film.ru.srt", "Film.eng.srt"
enum SRT {
    static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = time(parts[0]), let end = time(parts[1]) else { continue }
            // Tags (<i>, <font ...>) and ASS overrides ({\an8}) are dropped: the overlay draws plain text
            let body = lines[(timing + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\{\\\\[^}]*\\}", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { cues.append(SubtitleCue(start: start, end: end, text: body)) }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// "00:01:02,345" (or with a dot) → 62.345
    static func time(_ text: String) -> TimeInterval? {
        let fields = text.trimmingCharacters(in: .whitespaces).split(whereSeparator: { ":,.".contains($0) }).compactMap { Double($0) }
        guard fields.count == 4 else { return nil }
        return fields[0] * 3600 + fields[1] * 60 + fields[2] + fields[3] / 1000
    }

    static func text(at time: TimeInterval, in cues: [SubtitleCue]) -> String? {
        cues.last { $0.start <= time && time < $0.end }?.text
    }

    /// .srt files beside the video, with the language in the name if there is one
    static func files(for video: URL) -> [(title: String, language: String?, url: URL)] {
        let base = video.deletingPathExtension().lastPathComponent.lowercased()
        let siblings = (try? FileManager.default.contentsOfDirectory(at: video.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        return siblings.filter { $0.pathExtension.lowercased() == "srt" }.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.lowercased() == base || name.lowercased().hasPrefix(base + ".") else { return nil }
            let tag = name.count > base.count ? String(name.dropFirst(base.count + 1)) : nil
            let language = tag.flatMap { Locale.current.localizedString(forLanguageCode: $0) != nil ? $0 : nil }
            let title = language.flatMap { Locale.current.localizedString(forLanguageCode: $0)?.capitalized } ?? tag ?? "Subtitles"
            return (title + " (.srt)", language, url)
        }.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// UTF-8, else Windows-1251 (Russian subtitles), else Latin-1
    static func load(_ url: URL) -> [SubtitleCue] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return parse(text)
    }
}
