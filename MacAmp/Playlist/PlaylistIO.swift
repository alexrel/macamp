import Foundation

public enum PlaylistIO {
    
    /// Parses an M3U or PLS file from a URL.
    public static func loadPlaylist(from url: URL) -> [TrackItem] {
        guard let content = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
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
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }
        let ext = url.pathExtension.lowercased()
        if ext == "pls" || content.lowercased().contains("[playlist]") {
            return parsePLS(content: content, baseURL: url.deletingLastPathComponent())
        } else {
            return parseM3U(content: content, baseURL: url.deletingLastPathComponent())
        }
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
