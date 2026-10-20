import Foundation

public enum PlaylistIO {
    
    /// Parses an M3U or PLS file from a URL.
    public static func loadPlaylist(from url: URL) -> [TrackItem] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let content = TextEncoding.decode(data)
        
        let ext = url.pathExtension.lowercased()
        if ext == "pls" {
            return parsePLS(content: content, baseURL: url.deletingLastPathComponent())
        } else {
            return parseM3U(content: content, baseURL: url.deletingLastPathComponent())
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
                // File path or URL
                let trackURL: URL
                if line.contains("://") {
                    trackURL = URL(string: line) ?? URL(fileURLWithPath: line)
                } else if line.hasPrefix("/") {
                    trackURL = URL(fileURLWithPath: line)
                } else {
                    trackURL = baseURL.appendingPathComponent(line)
                }
                
                let title = nextTitle.isEmpty ? trackURL.deletingPathExtension().lastPathComponent : nextTitle
                let item = TrackItem.create(from: trackURL, titleFallback: title, durationFallback: nextDuration)
                items.append(item)
                
                nextTitle = ""
                nextDuration = 0
            }
        }
        return items
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
            let trackURL: URL
            if path.contains("://") {
                trackURL = URL(string: path) ?? URL(fileURLWithPath: path)
            } else if path.hasPrefix("/") {
                trackURL = URL(fileURLWithPath: path)
            } else {
                trackURL = baseURL.appendingPathComponent(path)
            }
            let title = titles[idx] ?? trackURL.deletingPathExtension().lastPathComponent
            let dur = lengths[idx] ?? 0
            items.append(TrackItem.create(from: trackURL, titleFallback: title, durationFallback: dur))
        }
        
        return items
    }
    
    /// Asynchronously loads and parses a remote or local playlist
    public static func loadPlaylistAsync(from url: URL) async -> [TrackItem] {
        if url.isFileURL {
            return loadPlaylist(from: url)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("WinampMPEG/2.91", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return []
        }
        let content = TextEncoding.decode(data)
        let ext = url.pathExtension.lowercased()
        if ext == "pls" || content.lowercased().contains("[playlist]") {
            return parsePLS(content: content, baseURL: url.deletingLastPathComponent())
        } else {
            return parseM3U(content: content, baseURL: url.deletingLastPathComponent())
        }
    }
    
    /// Playlist entry location: file path for local files, full URL for streams
    private static func location(of track: TrackItem) -> String {
        track.url.isFileURL ? track.url.path : track.url.absoluteString
    }
    
    // MARK: - Save M3U
    public static func saveM3U(tracks: [TrackItem], to url: URL) throws {
        var content = "#EXTM3U\n"
        for track in tracks {
            content += "#EXTINF:\(track.duration > 0 ? Int(track.duration) : -1),\(track.displayName)\n"
            content += "\(location(of: track))\n"
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Save PLS
    public static func savePLS(tracks: [TrackItem], to url: URL) throws {
        var content = "[playlist]\n"
        for (i, track) in tracks.enumerated() {
            let n = i + 1
            content += "File\(n)=\(location(of: track))\n"
            content += "Title\(n)=\(track.displayName)\n"
            content += "Length\(n)=\(track.duration > 0 ? Int(track.duration) : -1)\n"
        }
        content += "NumberOfEntries=\(tracks.count)\nVersion=2\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Saves as PLS or M3U depending on the file extension.
    public static func save(tracks: [TrackItem], to url: URL) throws {
        if url.pathExtension.lowercased() == "pls" {
            try savePLS(tracks: tracks, to: url)
        } else {
            try saveM3U(tracks: tracks, to: url)
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
