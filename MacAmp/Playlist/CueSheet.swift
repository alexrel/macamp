import Foundation

/// A track inside a bigger file (CUE sheet), as a media fragment on the file URL: `album.flac#t=123.4,301.2`
/// (seconds; no end = to the end of the file). Every CUE track keeps its own URL, so everything that
/// tells tracks apart by URL (current track, saved session, bookmarks) works unchanged.
public extension URL {
    var playbackRange: (start: TimeInterval, end: TimeInterval?)? {
        guard isFileURL, let fragment, fragment.hasPrefix("t=") else { return nil }
        let parts = fragment.dropFirst(2).split(separator: ",", omittingEmptySubsequences: false)
        guard let start = parts.first.flatMap({ TimeInterval($0) }), start >= 0 else { return nil }
        let end = parts.count > 1 ? TimeInterval(parts[1]) : nil
        return (start, end)
    }

    /// The audio file itself (without a CUE track range).
    var withoutPlaybackRange: URL {
        guard playbackRange != nil, var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.fragment = nil
        return components.url ?? self
    }

    func withPlaybackRange(start: TimeInterval, end: TimeInterval?) -> URL {
        var components = URLComponents(url: withoutPlaybackRange, resolvingAgainstBaseURL: false)
        components?.fragment = "t=" + CueSheet.format(start) + (end.map { "," + CueSheet.format($0) } ?? "")
        return components?.url ?? self
    }
}

/// CUE sheet reader: one entry per TRACK, playing from its INDEX 01 to the next track's INDEX 01
/// in the same FILE (pregaps stay with the previous track, so an album plays without holes).
public enum CueSheet {
    static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }

    /// "mm:ss:ff" with 75 frames per second (CD frames).
    static func seconds(_ time: String) -> TimeInterval? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return TimeInterval(parts[0] * 60 + parts[1]) + TimeInterval(parts[2]) / 75
    }

    /// Entries for a sheet; titles are "Performer - Title" like the rest of the playlist.
    public static func parse(content: String, baseURL: URL) -> [TrackItem] {
        struct Track { var file: URL; var title = ""; var performer = ""; var start: TimeInterval? }
        var albumPerformer = ""
        var file: URL?
        var tracks: [Track] = []
        var current: Track?

        for raw in content.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let (command, rest) = split(line)
            switch command {
            case "FILE":
                if let finished = current { tracks.append(finished); current = nil }
                file = locate(unquote(rest.cueFileName), baseURL: baseURL)
            case "TRACK":
                if let finished = current { tracks.append(finished) }
                // Only audio tracks (a data track on an enhanced CD has nothing to play)
                current = (file != nil && rest.uppercased().hasSuffix("AUDIO")) ? Track(file: file!) : nil
            case "TITLE":
                current?.title = unquote(rest)
            case "PERFORMER":
                if current != nil { current?.performer = unquote(rest) } else { albumPerformer = unquote(rest) }
            case "INDEX":
                let (number, time) = split(rest)
                if number == "01", let start = seconds(time) { current?.start = start }
            default:
                break
            }
        }
        if let finished = current { tracks.append(finished) }

        let playable = tracks.filter { $0.start != nil }
        return playable.enumerated().map { i, track in
            let next = playable.indices.contains(i + 1) ? playable[i + 1] : nil
            let end = next?.file == track.file ? next?.start : nil
            let start = track.start!
            let url = track.file.withPlaybackRange(start: start, end: end)
            let title = track.title.isEmpty ? String(format: "Track %02d", i + 1) : track.title
            let performer = track.performer.isEmpty ? albumPerformer : track.performer
            return TrackItem(url: url, title: title, artist: performer, duration: end.map { $0 - start } ?? 0)
        }
    }

    /// Files a sheet points to (to skip them when the folder is added, so the album isn't listed twice).
    public static func referencedFiles(content: String, baseURL: URL) -> [URL] {
        content.components(separatedBy: .newlines).compactMap { raw in
            let (command, rest) = split(raw.trimmingCharacters(in: .whitespaces))
            return command == "FILE" ? locate(unquote(rest.cueFileName), baseURL: baseURL).standardizedFileURL : nil
        }
    }

    /// The FILE line's file, or the same name with another audio extension: sheets made for a .wav rip
    /// often sit next to the .flac it was converted to.
    static func locate(_ name: String, baseURL: URL) -> URL {
        let url = PlaylistIO.resolveEntry(name, baseURL: baseURL)
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        let stem = url.deletingPathExtension()
        for ext in AppConstants.Audio.supportedExtensions.sorted() {
            let candidate = stem.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    private static func split(_ line: String) -> (String, String) {
        guard let space = line.firstIndex(of: " ") else { return (line.uppercased(), "") }
        return (line[..<space].uppercased(), line[line.index(after: space)...].trimmingCharacters(in: .whitespaces))
    }

    private static func unquote(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\""), let close = text.dropFirst().firstIndex(of: "\"") {
            text = String(text[text.index(after: text.startIndex)..<close])
        }
        return text
    }
}

private extension String {
    /// FILE line value: `"Album Name.flac" WAVE` or `album.flac WAVE` -> the file name (type word dropped)
    var cueFileName: String {
        let text = trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\"") { return text }
        guard let space = text.lastIndex(of: " ") else { return text }
        return String(text[..<space])
    }
}
