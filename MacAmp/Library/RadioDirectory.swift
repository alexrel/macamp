import Foundation

/// Library ▸ Internet Radio. Winamp 2.95 listed SHOUTcast stations; that directory is gone, so MacAmp uses
/// Radio Browser (radio-browser.info: free, no key). Requests honour Preferences ▸ Setup (offline, proxy).
public struct RadioStation: Codable, Identifiable, Hashable {
    public var id: String { stationuuid }
    public let stationuuid: String
    public let name: String
    public let url_resolved: String
    public let tags: String
    public let bitrate: Int
    public let clickcount: Int
    public let codec: String

    /// First tag, as the station's genre
    public var genre: String { tags.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "" }
    public var streamURL: URL? { URL(string: url_resolved) }
}

public enum RadioDirectory {
    /// Winamp's Bandwidth filter
    public enum Bandwidth: String, CaseIterable {
        case any = "Any", broadband = "≥ 128 kbps", medium = "≥ 64 kbps", low = "< 64 kbps"
        var query: [URLQueryItem] {
            switch self {
            case .any: return []
            case .broadband: return [URLQueryItem(name: "bitrateMin", value: "128")]
            case .medium: return [URLQueryItem(name: "bitrateMin", value: "64")]
            case .low: return [URLQueryItem(name: "bitrateMax", value: "63")]
            }
        }
    }

    static let server = "https://all.api.radio-browser.info"

    /// Most popular stations matching the search text, genre and bandwidth (Library prefs: max streams to fetch).
    public static func stations(search: String = "", genre: String = "", bandwidth: Bandwidth = .any, limit: Int = 500) async throws -> [RadioStation] {
        var items = [URLQueryItem(name: "hidebroken", value: "true"), URLQueryItem(name: "order", value: "clickcount"),
                     URLQueryItem(name: "reverse", value: "true"), URLQueryItem(name: "limit", value: String(limit))]
        if !search.isEmpty { items.append(URLQueryItem(name: "name", value: search)) }
        if !genre.isEmpty { items.append(URLQueryItem(name: "tag", value: genre)); items.append(URLQueryItem(name: "tagExact", value: "true")) }
        items += bandwidth.query
        return try await get("/json/stations/search", items)
    }

    /// The most used genres, for the Genre box.
    public static func genres(limit: Int = 60) async throws -> [String] {
        struct Tag: Codable { let name: String; let stationcount: Int }
        let tags: [Tag] = try await get("/json/tags", [URLQueryItem(name: "order", value: "stationcount"),
                                                         URLQueryItem(name: "reverse", value: "true"),
                                                         URLQueryItem(name: "limit", value: String(limit)),
                                                         URLQueryItem(name: "hidebroken", value: "true")])
        return tags.map(\.name).filter { !$0.isEmpty }
    }

    /// Station lists are cached (Caches/MacAmp/Radio) and fetched again when older than the Library
    /// preference allows (Hourly / Daily / Weekly / Never)
    static var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacAmp/Radio", isDirectory: true)
    }

    static func cacheURL(search: String, genre: String, bandwidth: Bandwidth, limit: Int) -> URL {
        let key = "\(search)|\(genre)|\(bandwidth.rawValue)|\(limit)"
        let name = key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return cacheFolder.appendingPathComponent(String(name.prefix(120)) + ".json")
    }

    /// The cached list if it's younger than `maxAgeHours` (0: any age)
    public static func cachedStations(search: String, genre: String, bandwidth: Bandwidth, limit: Int, maxAgeHours: Int) -> [RadioStation]? {
        let url = cacheURL(search: search, genre: genre, bandwidth: bandwidth, limit: limit)
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              maxAgeHours == 0 || Date().timeIntervalSince(date) < Double(maxAgeHours) * 3600,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([RadioStation].self, from: data)
    }

    public static func cache(_ stations: [RadioStation], search: String, genre: String, bandwidth: Bandwidth, limit: Int) {
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(stations).write(to: cacheURL(search: search, genre: genre, bandwidth: bandwidth, limit: limit))
    }

    static func get<T: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> T {
        guard !MacAmpNetwork.isOffline else { throw MacAmpNetwork.offlineError }
        var components = URLComponents(string: server + path)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("MacAmp/\(AppConstants.App.version)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await MacAmpNetwork.session.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
