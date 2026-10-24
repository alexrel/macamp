import Foundation

public enum PlaylistIO {
    
    /// Loads an M3U / PLS / XSPF playlist (local file or URL) and reads its tracks' tags.
    public static func loadPlaylist(from url: URL) async -> [TrackItem] {
        await TrackItem.resolveAll(loadEntries(from: url))
    }
    
    /// The playlist's entries as the file lists them, without reading the audio files.
    public static func loadEntries(from url: URL) async -> [TrackItem] {
        let data: Data
        if url.isFileURL {
            guard let local = try? Data(contentsOf: url) else { return [] }
            data = local
        } else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(AppConstants.App.streamUserAgent, forHTTPHeaderField: "User-Agent")
            guard let (remote, _) = try? await MacAmpNetwork.session.data(for: request) else { return [] }
            data = remote
        }
        return parse(data: data, ext: url.pathExtension.lowercased(), baseURL: url.deletingLastPathComponent())
    }
    
    /// Playlist entries with the titles / durations the file gives (no audio files read).
    static func parse(data: Data, ext: String, baseURL: URL) -> [TrackItem] {
        let content = TextEncoding.decode(data)
        if ext == "cue" {
            return CueSheet.parse(content: content, baseURL: baseURL)
        }
        if ext == "xspf" || content.contains("<playlist") && content.contains("xspf.org") {
            return parseXSPF(data: data, baseURL: baseURL)
        } else if ext == "pls" || content.lowercased().contains("[playlist]") {
            return parsePLS(content: content, baseURL: baseURL)
        } else {
            return parseM3U(content: content, baseURL: baseURL)
        }
    }
    
    // MARK: - M3U Parser
    static func parseM3U(content: String, baseURL: URL) -> [TrackItem] {
        var items: [TrackItem] = []
        var nextTitle = ""
        var nextDuration: TimeInterval = 0
        
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            
            if line.hasPrefix("#EXTINF:") {
                let info = String(line.dropFirst(8))
                let parts = info.split(separator: ",", maxSplits: 1)
                if parts.count >= 1, let dur = Double(parts[0].trimmingCharacters(in: .whitespaces)) {
                    nextDuration = max(0, dur)
                }
                if parts.count >= 2 {
                    nextTitle = String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            } else if !line.hasPrefix("#") {
                let trackURL = resolveEntry(line, baseURL: baseURL)
                
                let title = nextTitle.isEmpty ? trackURL.deletingPathExtension().lastPathComponent : displayTitle(nextTitle, for: trackURL)
                let item = TrackItem.entry(url: trackURL, title: title, duration: nextDuration)
                items.append(item)
                
                nextTitle = ""
                nextDuration = 0
            }
        }
        return items
    }
    
    /// VLC writes the file name, extension included, as the #EXTINF title ("Song [id].mp3");
    /// show it like Winamp does, without the extension.
    static func displayTitle(_ title: String, for url: URL) -> String {
        let ext = url.pathExtension
        guard !ext.isEmpty, title.lowercased().hasSuffix("." + ext.lowercased()) else { return title }
        return String(title.dropLast(ext.count + 1))
    }
    
    /// Turns a playlist entry into a URL. Handles what other players write:
    /// absolute and relative paths, `file://` URLs, Windows backslashes, and percent-encoded paths
    /// (e.g. `mp3/%D0%9A%D0%B8%D0%BD%D0%BE.mp3` from yt-dlp / foobar2000 / VLC exports).
    static func resolveEntry(_ rawEntry: String, baseURL: URL) -> URL {
        let entry = rawEntry.trimmingCharacters(in: .whitespaces)
        if entry.lowercased().hasPrefix("file://"), let url = URL(string: entry) {
            return url
        }
        if entry.contains("://") {
            return URL(string: entry) ?? URL(fileURLWithPath: entry)
        }
        let path = entry.replacingOccurrences(of: "\\", with: "/")
        /// Absolute ("/Users/..."), home-relative ("~/Music/...") or relative to the playlist's folder
        /// ("song.mp3", "mp3/song.mp3", "../Other/song.mp3"); "." and ".." are resolved.
        func fileURL(_ p: String) -> URL {
            let url: URL
            if p.hasPrefix("/") {
                url = URL(fileURLWithPath: p)
            } else if p.hasPrefix("~") {
                url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            } else {
                url = baseURL.appendingPathComponent(p)
            }
            return url.standardizedFileURL
        }
        let literal = fileURL(path)
        if !FileManager.default.fileExists(atPath: literal.path),
           path.contains("%"), let decoded = path.removingPercentEncoding {
            let candidate = fileURL(decoded)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return literal
    }
    
    // MARK: - XSPF Parser (VLC's native playlist format)
    /// `<track><location>file:///…</location><title>…</title><creator>…</creator><duration>ms</duration></track>`.
    /// Locations are URIs: absolute `file://`, stream `http://`, or relative to the playlist (percent-encoded).
    static func parseXSPF(data: Data, baseURL: URL) -> [TrackItem] {
        final class Collector: NSObject, XMLParserDelegate {
            struct Entry { var location = "", title = "", creator = "", durationMs: Double = 0 }
            var entries: [Entry] = []
            private var current: Entry?
            private var text = ""
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
                if name == "track" { current = Entry() }
                text = ""
            }
            func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
            func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                switch name {
                case "location": if current?.location.isEmpty == true { current?.location = value }
                case "title": current?.title = value
                case "creator": current?.creator = value
                case "duration": current?.durationMs = Double(value) ?? 0
                case "track":
                    if let entry = current, !entry.location.isEmpty { entries.append(entry) }
                    current = nil
                default: break
                }
                text = ""
            }
        }
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.entries.map { entry in
            let url = resolveEntry(entry.location, baseURL: baseURL)
            let title = entry.title.isEmpty ? url.deletingPathExtension().lastPathComponent
                : (entry.creator.isEmpty ? entry.title : "\(entry.creator) - \(entry.title)")
            return TrackItem.entry(url: url, title: title, duration: entry.durationMs / 1000)
        }
    }
    
    // MARK: - PLS Parser
    static func parsePLS(content: String, baseURL: URL) -> [TrackItem] {
        var items: [TrackItem] = []
        var files: [Int: String] = [:]
        var titles: [Int: String] = [:]
        var lengths: [Int: Double] = [:]
        
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.contains("=") else { continue }
            
            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            
            let key = parts[0].lowercased()
            let val = parts[1]
            
            if key.hasPrefix("file"), let idx = Int(key.dropFirst(4)) {
                files[idx] = val
            } else if key.hasPrefix("title"), let idx = Int(key.dropFirst(5)) {
                titles[idx] = val
            } else if key.hasPrefix("length"), let idx = Int(key.dropFirst(6)), let len = Double(val) {
                lengths[idx] = len
            }
        }
        
        for idx in files.keys.sorted() {
            guard let path = files[idx] else { continue }
            let trackURL = resolveEntry(path, baseURL: baseURL)
            let title = titles[idx] ?? trackURL.deletingPathExtension().lastPathComponent
            let dur = lengths[idx] ?? 0
            items.append(TrackItem.entry(url: trackURL, title: title, duration: dur))
        }
        
        return items
    }
    
    /// Playlist entry location: file path for local files, full URL for streams
    /// With `relativeTo`, files inside the playlist's folder are written relative to it; others stay absolute.
    private static func location(of track: TrackItem, relativeTo folder: URL?) -> String {
        guard track.url.isFileURL else { return track.url.absoluteString }
        let path = track.url.standardizedFileURL.path
        if let folder {
            let prefix = folder.standardizedFileURL.path + "/"
            if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        }
        return path
    }
    
    // MARK: - Save M3U
    public static func saveM3U(tracks: [TrackItem], to url: URL, relativePaths: Bool = false, extended: Bool = true) throws {
        var content = extended ? "#EXTM3U\n" : ""
        for track in tracks {
            if extended { content += "#EXTINF:\(track.duration > 0 ? Int(track.duration) : -1),\(track.displayName)\n" }
            content += "\(location(of: track, relativeTo: relativePaths ? url.deletingLastPathComponent() : nil))\n"
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Save PLS
    public static func savePLS(tracks: [TrackItem], to url: URL, relativePaths: Bool = false) throws {
        var content = "[playlist]\n"
        for (i, track) in tracks.enumerated() {
            let n = i + 1
            content += "File\(n)=\(location(of: track, relativeTo: relativePaths ? url.deletingLastPathComponent() : nil))\n"
            content += "Title\(n)=\(track.displayName)\n"
            content += "Length\(n)=\(track.duration > 0 ? Int(track.duration) : -1)\n"
        }
        content += "NumberOfEntries=\(tracks.count)\nVersion=2\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Saves as PLS or M3U depending on the file extension.
    public static func save(tracks: [TrackItem], to url: URL, relativePaths: Bool = false) throws {
        if url.pathExtension.lowercased() == "pls" {
            try savePLS(tracks: tracks, to: url, relativePaths: relativePaths)
        } else {
            try saveM3U(tracks: tracks, to: url, relativePaths: relativePaths)
        }
    }
    
    // MARK: - HTML Playlist (Winamp MISC ▸ Misc options ▸ Generate HTML playlist)
    public static func generateHTML(tracks: [TrackItem]) -> String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        let known = tracks.filter { $0.duration > 0 }
        let total = known.reduce(0) { $0 + $1.duration }
        let average = known.isEmpty ? 0 : total / Double(known.count)
        var rows = ""
        for (i, track) in tracks.enumerated() {
            let time = track.duration > 0 ? " (\(PlaylistModel.formatTime(track.duration)))" : ""
            rows += "<li><span class=\"n\">\(i + 1).</span> \(escape(track.displayName))\(time)</li>\n"
        }
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>MacAmp Generated PlayList</title>
        <style>
        body { background: #000040; color: #ffffff; font: 13px Arial, Helvetica, sans-serif; margin: 24px; }
        h1 { color: #ffbf32; font-size: 22px; margin: 0 0 4px; }
        .info { color: #409fff; margin-bottom: 16px; }
        .info b { color: #ffbf32; }
        ol { list-style: none; padding: 0; color: #409fff; }
        li { padding: 1px 0; }
        .n { color: #ffbf32; display: inline-block; min-width: 3em; }
        </style></head><body>
        <h1>MacAmp Generated PlayList</h1>
        <div class="info"><b>\(tracks.count)</b> track\(tracks.count == 1 ? "" : "s") in playlist, average track length: <b>\(PlaylistModel.formatTime(average))</b><br>
        Playlist length: <b>\(PlaylistModel.formatTime(total))</b>\(known.count < tracks.count ? " (\(tracks.count - known.count) track(s) of unknown length)" : "")</div>
        <ol>
        \(rows)</ol>
        </body></html>
        """
    }
}
