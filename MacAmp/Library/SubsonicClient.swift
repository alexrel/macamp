import Foundation
import CryptoKit

/// Library ▸ Subsonic: a home music server (Navidrome, Gonic, Airsonic...) over the Subsonic API / OpenSubsonic.
/// Off until a server is set in Preferences ▸ Media Library: no tree node, no requests.
public struct SubsonicArtist: Decodable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public var albumCount: Int?
}

public struct SubsonicAlbum: Decodable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public var artist: String?
    public var year: Int?
    public var songCount: Int?
}

public struct SubsonicSong: Decodable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public var artist: String?
    public var album: String?
    public var track: Int?
    public var discNumber: Int?
    public var duration: Int?
    public var year: Int?
    public var genre: String?
    public var suffix: String?

    /// A playlist entry: `subsonic://song/<id>.<suffix>`, no server or credentials in it
    public var trackItem: TrackItem {
        TrackItem(url: Subsonic.trackURL(id: id, suffix: suffix), title: title, artist: artist ?? "", duration: TimeInterval(duration ?? 0))
    }

    public var libraryItem: MediaLibraryItem {
        var item = MediaLibraryItem(url: trackItem.url, title: title)
        item.artist = artist ?? ""
        item.album = album ?? ""
        item.length = TimeInterval(duration ?? 0)
        item.trackNumber = track ?? 0
        item.genre = genre ?? ""
        item.year = year.map(String.init) ?? ""
        return item
    }
}

/// `"status": "failed"` from the server (it comes with HTTP 200)
public struct SubsonicError: LocalizedError, Equatable {
    public let code: Int
    public let message: String
    public var errorDescription: String? { message.isEmpty ? "Subsonic error \(code)" : message }
    /// The API's codes MacAmp raises itself (subsonic.org/pages/api.jsp)
    static let wrongCredentials = 40
    static let notFound = 70
}

public enum Subsonic {
    static let apiVersion = "1.16.1"
    static let clientName = "MacAmp"
    public static let scheme = "subsonic"
    static let searchLimit = 500

    // MARK: Settings

    public static var server: String { normalized(PersistenceManager.shared.state.subsonicServer) }
    public static var user: String { PersistenceManager.shared.state.subsonicUser.trimmingCharacters(in: .whitespaces) }
    public static var isConfigured: Bool { !server.isEmpty && !user.isEmpty }

    /// The API root from what was typed or pasted: "music.local:4533/" → "http://music.local:4533";
    /// a web page of the server ("…/login.view?user=…", Navidrome's "…/app/#/login", "…/rest") → its root.
    /// A path prefix the server is mounted under ("https://host/music") stays.
    static func normalized(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return s }
        if !s.lowercased().hasPrefix("http://"), !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        guard var components = URLComponents(string: s) else { return s }
        components.query = nil
        components.fragment = nil
        var parts = components.path.split(separator: "/").map(String.init)
        if let app = parts.firstIndex(of: "app") { parts.removeSubrange(app...) }
        if parts.last?.lowercased().hasSuffix(".view") == true { parts.removeLast() }
        if parts.last == "rest" { parts.removeLast() }
        components.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
        return components.string ?? s
    }

    /// A password given as hex ("enc:73657361…"), as Subsonic links may carry it
    static let encodedPasswordPrefix = "enc:"

    /// User and password from a pasted link like "…/login.view?user=guest&password=guest" (or u= / p=, "enc:" hex)
    static func credentials(in text: String) -> (user: String, password: String)? {
        guard let items = URLComponents(string: text.trimmingCharacters(in: .whitespaces))?.queryItems else { return nil }
        func value(_ names: [String]) -> String? { items.first { names.contains($0.name) }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        guard let user = value(["user", "u"]), var password = value(["password", "p"]) else { return nil }
        if password.hasPrefix(encodedPasswordPrefix) {
            let hex = Array(password.dropFirst(encodedPasswordPrefix.count))
            let bytes = stride(from: 0, to: hex.count - 1, by: 2).compactMap { UInt8(String(hex[$0...$0 + 1]), radix: 16) }
            password = String(decoding: bytes, as: UTF8.self)
        }
        return (user, password)
    }

    // MARK: Requests

    /// Token auth: md5(password + salt) with a fresh salt; the password itself never goes over the network
    static func token(password: String, salt: String) -> String {
        Insecure.MD5.hash(data: Data((password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func requestURL(_ method: String, _ query: [URLQueryItem] = [], server: String, user: String, password: String,
                           salt: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()) -> URL? {
        guard var components = URLComponents(string: "\(server)/rest/\(method).view") else { return nil }
        components.queryItems = [URLQueryItem(name: "u", value: user), URLQueryItem(name: "t", value: token(password: password, salt: salt)),
                                 URLQueryItem(name: "s", value: salt), URLQueryItem(name: "v", value: apiVersion),
                                 URLQueryItem(name: "c", value: clientName), URLQueryItem(name: "f", value: "json")] + query
        return components.url
    }

    /// The JSON under "subsonic-response" ▸ `key`, or the server's error
    static func payload(_ data: Data, key: String?) throws -> Data {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let body = root["subsonic-response"] as? [String: Any] else {
            throw SubsonicError(code: 0, message: "Not a Subsonic server")
        }
        guard body["status"] as? String == "ok" else {
            let error = body["error"] as? [String: Any]
            throw SubsonicError(code: error?["code"] as? Int ?? 0, message: error?["message"] as? String ?? "")
        }
        guard let key else { return Data() }
        return try JSONSerialization.data(withJSONObject: body[key] ?? [String: Any]())
    }

    static func get(_ method: String, _ query: [URLQueryItem] = [], key: String?,
                    server: String = server, user: String = user, password: String? = nil) async throws -> Data {
        guard !MacAmpNetwork.isOffline else { throw MacAmpNetwork.offlineError }
        guard let password = password ?? savedPassword(server: server, user: user) else {
            throw SubsonicError(code: SubsonicError.wrongCredentials, message: noPasswordMessage)
        }
        guard let url = requestURL(method, query, server: server, user: user, password: password) else {
            throw SubsonicError(code: 0, message: "Bad server address")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MacAmp/\(AppConstants.App.version)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await MacAmpNetwork.session.data(for: request)
        return try payload(data, key: key)
    }

    /// Test connection, with what's typed in Preferences (before it's saved)
    public static func ping(server: String, user: String, password: String) async throws {
        _ = try await get("ping", key: nil, server: normalized(server), user: user.trimmingCharacters(in: .whitespaces), password: password)
    }

    public static func artists() async throws -> [SubsonicArtist] {
        try parseArtists(try await get("getArtists", key: "artists"))
    }

    static func parseArtists(_ data: Data) throws -> [SubsonicArtist] {
        struct Index: Decodable { var artist: [SubsonicArtist]? }
        struct Artists: Decodable { var index: [Index]? }
        return try JSONDecoder().decode(Artists.self, from: data).index?.flatMap { $0.artist ?? [] } ?? []
    }

    public static func albums(artistID: String) async throws -> [SubsonicAlbum] {
        struct Artist: Decodable { var album: [SubsonicAlbum]? }
        let data = try await get("getArtist", [URLQueryItem(name: "id", value: artistID)], key: "artist")
        return try JSONDecoder().decode(Artist.self, from: data).album ?? []
    }

    /// Album tracks in disc / track order
    public static func songs(albumID: String) async throws -> [SubsonicSong] {
        try parseAlbum(try await get("getAlbum", [URLQueryItem(name: "id", value: albumID)], key: "album"))
    }

    static func parseAlbum(_ data: Data) throws -> [SubsonicSong] {
        struct Album: Decodable { var song: [SubsonicSong]? }
        return (try JSONDecoder().decode(Album.self, from: data).song ?? [])
            .sorted { ($0.discNumber ?? 0, $0.track ?? 0) < ($1.discNumber ?? 0, $1.track ?? 0) }
    }

    /// Songs matching the Library search box (search3; artists and albums are left to the panes)
    public static func search(_ text: String) async throws -> [SubsonicSong] {
        try parseSearch(try await get("search3", [URLQueryItem(name: "query", value: text), URLQueryItem(name: "artistCount", value: "0"),
                                                  URLQueryItem(name: "albumCount", value: "0"),
                                                  URLQueryItem(name: "songCount", value: String(searchLimit))], key: "searchResult3"))
    }

    static func parseSearch(_ data: Data) throws -> [SubsonicSong] {
        struct Result: Decodable { var song: [SubsonicSong]? }
        return try JSONDecoder().decode(Result.self, from: data).song ?? []
    }

    // MARK: Tracks

    public static func trackURL(id: String, suffix: String?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "song"
        components.path = "/" + id + (suffix.map { $0.isEmpty ? "" : "." + $0 } ?? "")
        return components.url!
    }

    public static func isTrack(_ url: URL) -> Bool { url.scheme == scheme }

    static func songID(_ url: URL) -> String? {
        guard isTrack(url) else { return nil }
        let name = url.lastPathComponent
        return url.pathExtension.isEmpty ? name : String(name.dropLast(url.pathExtension.count + 1))
    }

    static var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacAmp/Subsonic", isDirectory: true)
    }

    /// The track as a local file: the original (`format=raw`, no transcoding) downloaded once into the cache.
    /// shortcut: playback starts after the whole file arrived, fine on a home network; stream progressively if slow links complain
    public static func localFile(for url: URL) async throws -> URL {
        guard let id = songID(url), !id.isEmpty, let file = cacheFile(for: url) else { throw SubsonicError(code: SubsonicError.notFound, message: "Not a Subsonic track") }
        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return file
        }
        guard isConfigured, let password = savedPassword(server: server, user: user) else {
            throw SubsonicError(code: SubsonicError.wrongCredentials, message: "Subsonic server not set: Preferences ▸ Media Library")
        }
        return try await download(id: id, to: file, server: server, user: user, password: password)
    }

    /// Where the track's download lives in the cache (it may not be there yet)
    static func cacheFile(for url: URL) -> URL? {
        guard let id = songID(url), !id.isEmpty else { return nil }
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let name = id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_" }.joined()
        return cacheFolder.appendingPathComponent(name + "." + ext)
    }

    /// The song's cover from the server: getSong gives its coverArt id, getCoverArt the picture; nil if it has none
    public static func coverArt(for url: URL) async throws -> Data? {
        guard let id = songID(url) else { return nil }
        struct Song: Decodable { var coverArt: String? }
        let song = try JSONDecoder().decode(Song.self, from: try await get("getSong", [URLQueryItem(name: "id", value: id)], key: "song"))
        guard let art = song.coverArt, let password = savedPassword(),
              let source = requestURL("getCoverArt", [URLQueryItem(name: "id", value: art), URLQueryItem(name: "size", value: String(coverArtSize))],
                                      server: server, user: user, password: password) else { return nil }
        var request = URLRequest(url: source)
        request.setValue("MacAmp/\(AppConstants.App.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await MacAmpNetwork.session.data(for: request)
        // An error comes back as JSON instead of the picture
        if let mime = response.mimeType, mime.contains("json") || mime.contains("xml") { _ = try payload(data, key: nil) }
        return data
    }

    /// Pixels asked for: enough for the Album Art window at 200%
    static let coverArtSize = 600

    static func download(id: String, to file: URL, server: String, user: String, password: String) async throws -> URL {
        guard !MacAmpNetwork.isOffline else { throw MacAmpNetwork.offlineError }
        guard let source = requestURL("stream", [URLQueryItem(name: "id", value: id), URLQueryItem(name: "format", value: "raw")],
                                      server: server, user: user, password: password) else {
            throw SubsonicError(code: 0, message: "Bad server address")
        }
        var request = URLRequest(url: source)
        request.setValue("MacAmp/\(AppConstants.App.version)", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await MacAmpNetwork.session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temp) }
        let mime = response.mimeType ?? ""
        // Errors come back as a JSON / XML body instead of audio
        if mime.contains("json") || mime.contains("xml") {
            _ = try payload(try Data(contentsOf: temp), key: nil)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SubsonicError(code: http.statusCode, message: "Server answered HTTP \(http.statusCode)")
        }
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temp, to: file)
        CacheStore.trim(keeping: file)
        return file
    }

    // MARK: Password (LocalSecret: encrypted in the app's defaults, never in session.json)

    private static func passwordKey(server: String, user: String) -> String { "\(passwordDefaultsPrefix)\(user)@\(server)" }
    static let passwordDefaultsPrefix = "SubsonicPassword "

    public static func savedPassword(server: String = server, user: String = user) -> String? {
        LocalSecret.read(passwordKey(server: server, user: user))
    }

    static let noPasswordMessage = "No password: set it in Preferences ▸ Media Library ▸ Subsonic"

    /// Saves the password for this server and user; an empty one removes it
    @discardableResult
    public static func savePassword(_ password: String, server: String, user: String) -> Bool {
        LocalSecret.write(password, for: passwordKey(server: normalized(server), user: user.trimmingCharacters(in: .whitespaces)))
    }
}

/// What the Library shows for the server: whether it's set, and the artist list, fetched once per session
@MainActor
public final class SubsonicLibrary: ObservableObject {
    public static let shared = SubsonicLibrary()
    @Published public private(set) var isConfigured = Subsonic.isConfigured
    @Published public var artists: [SubsonicArtist] = []
    /// Bumped on every Connect / Remove: an open Subsonic page loads again
    @Published public private(set) var generation = 0

    /// After Preferences saved or removed the server
    public func settingsChanged() {
        isConfigured = Subsonic.isConfigured
        artists = []
        generation += 1
        if !isConfigured, LibraryNavigation.shared.node == .subsonic { LibraryNavigation.shared.node = .localMedia }
    }
}
