import Foundation

public enum PlaylistIO {
    
    /// Parses an M3U or PLS file from a URL.
    public static func loadPlaylist(from url: URL) -> [TrackItem] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .isoLatin1) else {
            return []
        }
        
        let ext = url.pathExtension.lowercased()
        if ext == "pls" {
            return parsePLS(content: content, baseURL: url.deletingLastPathComponent())
        } else {
            return parseM3U(content: content, baseURL: url.deletingLastPathComponent())
        }
    }
    
    // MARK: - M3U Parser
    private static func parseM3U(content: String, baseURL: URL) -> [TrackItem] {
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
                // File path
                let trackURL: URL
                if line.hasPrefix("/") || line.contains("://") {
                    trackURL = URL(fileURLWithPath: line)
                } else {
                    trackURL = baseURL.appendingPathComponent(line)
                }
                
                let title = nextTitle.isEmpty ? trackURL.deletingPathExtension().lastPathComponent : nextTitle
                let item = TrackItem(url: trackURL, title: title, duration: nextDuration)
                items.append(item)
                
                nextTitle = ""
                nextDuration = 0
            }
        }
        return items
    }
    
    // MARK: - PLS Parser
    private static func parsePLS(content: String, baseURL: URL) -> [TrackItem] {
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
            let trackURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : baseURL.appendingPathComponent(path)
            let title = titles[idx] ?? trackURL.deletingPathExtension().lastPathComponent
            let dur = lengths[idx] ?? 0
            items.append(TrackItem(url: trackURL, title: title, duration: dur))
        }
        
        return items
    }
    
    // MARK: - Save M3U
    public static func saveM3U(tracks: [TrackItem], to url: URL) throws {
        var content = "#EXTM3U\n"
        for track in tracks {
            content += "#EXTINF:\(Int(track.duration)),\(track.artist) - \(track.title)\n"
            content += "\(track.url.path)\n"
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
