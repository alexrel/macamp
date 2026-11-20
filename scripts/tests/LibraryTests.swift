import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func libraryTests() {
    testGroup("Media Library: Skinned Lists (gen_ml)") {
        typealias Item = SkinnedListController.Item
        let items = [("All (3)", "3"), ("Zemfira", "10"), ("air", "9"), ("Кино", "4:58"), ("Air", "10:01")].enumerated().map {
            Item(id: AnyHashable($0.offset), values: [$0.element.0, $0.element.1], url: nil)
        }
        func order(_ column: Int?, _ ascending: Bool, pinned: Bool = false) -> [String] {
            SkinnedListController.sorted(items, column: column, ascending: ascending, pinsFirstRow: pinned).map { $0.values[0] }
        }
        assertEqual(order(nil, true), ["All (3)", "Zemfira", "air", "Кино", "Air"], "No sort column: order given")
        assertEqual(order(0, true, pinned: true), ["All (3)", "air", "Air", "Zemfira", "Кино"], "\"All\" row stays on top; ties keep their order")
        assertEqual(order(0, false, pinned: true).first, "All (3)", "Pinned row on top when descending too")
        assertEqual(SkinnedListController.sorted(Array(items.dropFirst()), column: 1, ascending: true, pinsFirstRow: false).map { $0.values[1] },
                    ["4:58", "9", "10", "10:01"], "Numbers and times compare as numbers")

        // Header clicks: same column reverses, another column keeps the direction (ml_local)
        let c = SkinnedListController(columns: [.init(title: "A", width: 50, alignment: .left), .init(title: "B", width: 50, alignment: .left)],
                                      autosave: "Test.\(UUID().uuidString)", defaultSort: "A")
        assertEqual(c.sortColumn, 0, "Default sort column")
        c.clickedHeader(0)
        assertTrue(c.sortColumn == 0 && !c.ascending, "Same column: reversed")
        c.clickedHeader(1)
        assertTrue(c.sortColumn == 1 && !c.ascending, "Other column: keeps the direction")

        // Prefs ▸ Library ▸ Column resizing, when the list gets 100 px wider
        assertEqual(SkinnedListController.resized([100, 50, 50], from: 200, to: 300, mode: 0, sorted: 1), [100, 50, 50], "Normal: columns keep their widths")
        assertEqual(SkinnedListController.resized([100, 50, 50], from: 200, to: 300, mode: 1, sorted: 1), [100, 150, 50], "Selected column only: sorted column takes it")
        assertEqual(SkinnedListController.resized([100, 50, 50], from: 200, to: 100, mode: 1, sorted: nil), [100, 50, 16], "No sort: last column, never under 16 px")
        assertEqual(SkinnedListController.resized([100, 50, 50], from: 200, to: 300, mode: 2, sorted: 1), [150, 75, 75], "Proportional: all scale")

        // Base skin leaves the list selection colours unset: they follow the playlist selection, as in wa_dlg.h
        SkinManager.shared.resetToBaseSkin()
        let theme = GenexTheme.current
        assertEqual(theme.ns(.selectionBackground), theme.ns(.playlistSelection), "Selection bar falls back to the playlist selection")
        assertEqual(theme.ns(.selectionText), theme.ns(.windowText), "Selection text falls back to window text")
    }

    testGroup("Library preferences (2.95 General / Internet Radio)") {
        let state = AppState()
        assertTrue(!state.libraryRememberSearch && state.libraryPlayWholePlaylist && !state.libraryPlayWholeQuery, "2.95 defaults (General)")
        assertTrue(state.libraryOnLightningBolt && state.libraryTVButtonOpensVideo, "Bolt and TV button open the Library")
        assertEqual(state.radioRefreshHours, 1, "Radio list refreshes hourly")
        assertEqual(MainWindowView.lightningBolt, NSRect(x: 253, y: 91, width: 13, height: 15), "Lightning bolt hit area")
        // Station list cache: fresh, too old, "Never"
        let json = #"[{"stationuuid":"u1","name":"Cached FM","url_resolved":"http://example.com/s","tags":"rock","bitrate":128,"clickcount":5,"codec":"MP3"}]"#
        let stations = try JSONDecoder().decode([RadioStation].self, from: Data(json.utf8))
        RadioDirectory.cache(stations, search: "", genre: "rock", bandwidth: .any, limit: 500)
        assertEqual(RadioDirectory.cachedStations(search: "", genre: "rock", bandwidth: .any, limit: 500, maxAgeHours: 1)?.first?.name, "Cached FM", "Fresh cache used")
        let file = RadioDirectory.cacheURL(search: "", genre: "rock", bandwidth: .any, limit: 500)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * 3600)], ofItemAtPath: file.path)
        assertTrue(RadioDirectory.cachedStations(search: "", genre: "rock", bandwidth: .any, limit: 500, maxAgeHours: 1) == nil, "Hourly: a 2 h old list is fetched again")
        assertTrue(RadioDirectory.cachedStations(search: "", genre: "rock", bandwidth: .any, limit: 500, maxAgeHours: 24) != nil, "Daily: still good")
        assertTrue(RadioDirectory.cachedStations(search: "", genre: "rock", bandwidth: .any, limit: 500, maxAgeHours: 0) != nil, "Never: any age")
        assertTrue(RadioDirectory.cachedStations(search: "", genre: "jazz", bandwidth: .any, limit: 500, maxAgeHours: 0) == nil, "Each filter has its own list")
    }

    testGroup("Media Library: Window, Radio, Prefs") {
        var item = MediaLibraryItem(url: URL(fileURLWithPath: "/Music/a.mp3"), title: "A")
        item.length = 3725
        assertEqual(LibraryActions.summary([item]), "1 item [1:02:05]", "Status line: one item, h:mm:ss")
        item.length = 65
        assertEqual(LibraryActions.summary([item, item]), "2 items [2:10]", "Status line: m:ss")
        assertEqual(LibraryActions.summary([]), "0 items [0:00]", "Status line: empty")
        // Radio Browser JSON (fields MacAmp reads)
        let json = #"[{"stationuuid":"u1","name":"Radio Paradise","url_resolved":"https://stream.radioparadise.com/mp3-192","tags":"eclectic, rock","bitrate":192,"clickcount":1500,"codec":"MP3","extra":1}]"#
        let stations = try JSONDecoder().decode([RadioStation].self, from: Data(json.utf8))
        assertEqual(stations.first?.genre, "eclectic", "Station genre: first tag")
        assertEqual(stations.first?.streamURL?.host, "stream.radioparadise.com", "Station stream URL")
        assertEqual(RadioDirectory.Bandwidth.broadband.query.first?.value, "128", "Bandwidth ≥ 128 kbps")
        assertTrue(RadioDirectory.Bandwidth.any.query.isEmpty, "Bandwidth Any: no filter")
        // Preferences ▸ Options ▸ Media Library, Window menu, ⌥L, size behaviour
        assertEqual(PrefTreeItem.library.parent, .options, "Media Library page under Options")
        assertTrue(WindowID.library.keepsOwnSize, "Library keeps its size at 2x")
        let state = AppState()
        assertEqual(state.libraryMaxStreams, 500, "Radio: 500 stations by default")
        assertTrue(!state.libraryDoubleClickEnqueues && !state.isLibraryVisible, "Double-click plays; library hidden by default")
    }

    testGroup("Media Library: Queries, Scanning, Search") {
        func item(_ artist: String, _ title: String, length: Double = 200, video: Bool = false, path: String = "/Music/x.mp3") -> MediaLibraryItem {
            var i = MediaLibraryItem(url: URL(fileURLWithPath: path), title: title)
            i.artist = artist; i.length = length; i.isVideo = video
            return i
        }
        let air = item("Air", "La Femme d'Argent", length: 430, path: "/Music/Air/01.mp3")
        let airShort = item("Air", "Sexy Boy", length: 298, path: "/Music/Air/02.mp3")
        let clip = item("Massive Attack", "Teardrop", length: 330, video: true, path: "/Volumes/Video/teardrop.mp4")
        let all = [air, airShort, clip]
        func run(_ q: String) throws -> [String] { let query = try LibraryQuery.parse(q); return all.filter(query.matches).map(\.title) }
        // Winamp's own examples (Add view dialog)
        assertEqual(try run("type = 0"), ["La Femme d'Argent", "Sexy Boy"], "type = 0: audio")
        assertEqual(try run("type = 1"), ["Teardrop"], "type = 1: video")
        assertEqual(try run("type = 0 & artist = \"air\" & length > 360"), ["La Femme d'Argent"], "Audio by Air longer than 360 s")
        assertEqual(try run("filename BEGINS /Volumes"), ["Teardrop"], "filename BEGINS")
        assertEqual(try run("title HAS boy | artist LIKE \"mass*\""), ["Sexy Boy", "Teardrop"], "HAS, LIKE with *, OR")
        assertEqual(try run("!(artist = air)"), ["Teardrop"], "NOT and parentheses")
        assertEqual(try run(""), ["La Femme d'Argent", "Sexy Boy", "Teardrop"], "Empty query: everything")
        assertTrue((try? LibraryQuery.parse("colour = red")) == nil, "Unknown field rejected")
        assertTrue((try? LibraryQuery.parse("artist = \"air")) == nil, "Unterminated quote rejected")
        assertEqual(MediaLibrary.filter(all, search: "air sexy").map(\.title), ["Sexy Boy"], "Search: every word must match")

        // Scanning a folder, compact, persistence
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/library", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let src = try makeTestWAV(named: "lib-src.wav", seconds: 1.0)
        for name in ["a.wav", "sub/b.wav", "notes.txt"] { try FileManager.default.copyItem(at: src, to: dir.appendingPathComponent(name)) }
        let store = dir.deletingLastPathComponent().appendingPathComponent("library-test.json")
        try? FileManager.default.removeItem(at: store)
        let library = MediaLibrary(storeURL: store)
        awaitValue { await library.addDirectory(dir) }
        assertEqual(library.items.map { $0.url.lastPathComponent }.sorted(), ["a.wav", "b.wav"], "Scan finds audio files in subfolders, skips others")
        assertTrue(library.items.allSatisfy { abs($0.length - 1) < 0.1 }, "Lengths read")
        assertEqual(library.views.map(\.name), ["Audio", "Video"], "Default views: Local Media ▸ Audio / Video")
        library.createPlaylist(named: "Mix", tracks: [library.items[0].track])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("a.wav"))
        assertEqual(library.compact(), 1, "Compact removes the missing file")
        let reloaded = MediaLibrary(storeURL: store)
        assertEqual(reloaded.items.map { $0.url.lastPathComponent }, ["b.wav"], "Library saved and reloaded")
        assertEqual(reloaded.playlists.map(\.name), ["Mix"], "Playlists saved")
        assertEqual(reloaded.folders.map(\.lastPathComponent), ["library"], "Folders remembered for rescans")
    }

    testGroup("Subsonic: token, responses, subsonic:// tracks") {
        // Token example from the Subsonic API docs
        assertEqual(Subsonic.token(password: "sesame", salt: "c19b2d"), "26719a1196d2a940705a59634eb18eab", "md5(password + salt)")
        let url = Subsonic.requestURL("ping", server: "http://music.local:4533", user: "admin", password: "sesame", salt: "c19b2d")!.absoluteString
        assertTrue(url.hasPrefix("http://music.local:4533/rest/ping.view?") && url.contains("t=26719a1196d2a940705a59634eb18eab") && url.contains("s=c19b2d"),
                   "Request carries user, token and salt (\(url))")
        assertTrue(!url.contains("sesame") && !url.contains("p="), "The password itself is never in the URL")
        assertEqual(Subsonic.normalized(" music.local:4533/ "), "http://music.local:4533", "Server address: scheme added, slash dropped")
        assertEqual(Subsonic.normalized("https://nd.example.org"), "https://nd.example.org", "https kept")
        assertEqual(Subsonic.normalized("http://demo.subsonic.org/login.view?user=guest&password=guest"), "http://demo.subsonic.org", "A web page of the server: its root")
        assertEqual(Subsonic.normalized("https://demo.navidrome.org/app/#/login"), "https://demo.navidrome.org", "Navidrome's web app address: its root")
        assertEqual(Subsonic.normalized("https://host.example/music/rest/"), "https://host.example/music", "A path prefix stays, /rest goes")
        assertTrue(Subsonic.credentials(in: "http://demo.subsonic.org/login.view?user=guest&password=secret")! == ("guest", "secret"), "User and password from a pasted link")
        assertTrue(Subsonic.savePassword("sesame", server: "http://music.local:4533/", user: " admin"), "Password saved")
        assertEqual(Subsonic.savedPassword(server: "http://music.local:4533", user: "admin"), "sesame", "Read back for the same server and user")
        let stored = UserDefaults.standard.data(forKey: Subsonic.passwordDefaultsPrefix + "admin@http://music.local:4533") ?? Data()
        assertTrue(!stored.isEmpty && stored.range(of: Data("sesame".utf8)) == nil, "Stored encrypted, not as plain text")
        Subsonic.savePassword("", server: "http://music.local:4533", user: "admin")
        assertTrue(Subsonic.savedPassword(server: "http://music.local:4533", user: "admin") == nil, "An empty password removes it")
        assertTrue(Subsonic.credentials(in: "http://h/rest/ping.view?u=bob&p=enc:736563726574")! == ("bob", "secret"), "u= / p=enc: hex")
        assertTrue(Subsonic.credentials(in: "http://music.local:4533") == nil, "A plain address has none")

        // Saved server answers (OpenSubsonic examples; Cyrillic; empty results come without the array)
        let artists = Data("""
        {"subsonic-response":{"status":"ok","version":"1.16.1","artists":{"ignoredArticles":"The","index":[
          {"name":"A","artist":[{"id":"5","name":"Antígona","albumCount":1}]},
          {"name":"К","artist":[{"id":"9","name":"Кино","albumCount":3}]}]}}}
        """.utf8)
        assertEqual(try Subsonic.parseArtists(Subsonic.payload(artists, key: "artists")).map(\.name), ["Antígona", "Кино"], "getArtists: every index flattened")
        let empty = Data(#"{"subsonic-response":{"status":"ok","version":"1.16.1","artists":{"ignoredArticles":"The"}}}"#.utf8)
        assertEqual(try Subsonic.parseArtists(Subsonic.payload(empty, key: "artists")).count, 0, "Empty collection")
        let album = Data("""
        {"subsonic-response":{"status":"ok","version":"1.16.1","album":{"id":"6","name":"Группа крови","song":[
          {"id":"79","title":"Закрой за мной дверь","artist":"Кино","album":"Группа крови","track":2,"discNumber":1,"duration":254,"suffix":"flac"},
          {"id":"78","title":"Группа крови","artist":"Кино","album":"Группа крови","track":1,"discNumber":1,"duration":286,"suffix":"mp3","year":1988}]}}}
        """.utf8)
        let songs = try Subsonic.parseAlbum(Subsonic.payload(album, key: "album"))
        assertEqual(songs.map(\.title), ["Группа крови", "Закрой за мной дверь"], "getAlbum: tracks in album order")
        assertEqual(songs[0].trackItem.duration, 286, "Length straight from the server")
        assertEqual(songs[0].trackItem.artist, "Кино", "Artist straight from the server")
        assertEqual(songs[0].libraryItem.year, "1988", "Year for the list")
        let none = Data(#"{"subsonic-response":{"status":"ok","version":"1.16.1","searchResult3":{}}}"#.utf8)
        assertEqual(try Subsonic.parseSearch(Subsonic.payload(none, key: "searchResult3")).count, 0, "search3 with nothing found")
        let failed = Data(#"{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":40,"message":"Wrong username or password"}}}"#.utf8)
        do {
            _ = try Subsonic.payload(failed, key: "artists")
            assertTrue(false, "A failed answer throws")
        } catch let error as SubsonicError {
            assertEqual(error, SubsonicError(code: 40, message: "Wrong username or password"), "Failed status (HTTP 200) becomes the server's error")
        }
        assertTrue((try? Subsonic.payload(Data("<html>".utf8), key: nil)) == nil, "Not a Subsonic server")

        // Playlist entries: subsonic://song/<id>.<suffix>, nothing secret, saved and read back
        let track = songs[1].trackItem
        assertEqual(track.url.absoluteString, "subsonic://song/79.flac", "Track URL has only the song id and type")
        assertEqual(Subsonic.songID(track.url), "79", "Song id read back")
        let saved = String(data: try JSONEncoder().encode([track]), encoding: .utf8)!
        assertTrue(!saved.contains("t=") && !saved.contains("music.local"), "playlist.json holds no server or token")
        assertEqual(try JSONDecoder().decode([TrackItem].self, from: Data(saved.utf8)).first?.url, track.url, "Entry read back from playlist.json")
        assertEqual(TrackItem.entry(url: track.url).artist, "", "A Subsonic entry isn't an Internet Stream")
        assertEqual(PlaylistIO.resolveEntry("subsonic://song/79.flac", baseURL: URL(fileURLWithPath: "/tmp/")), track.url, "And comes back from an M3U line")

        // Download through a local server: stream with format=raw, an error answer, then the cache
        let wav = try Data(contentsOf: try makeTestWAV(named: "subsonic-src.wav", seconds: 0.5))
        let server = try TestHTTPServer { path in
            if path.contains("/rest/stream.view") && path.contains("id=78") && path.contains("format=raw") { return ("audio/wav", wav) }
            return ("application/json", Data(#"{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":70,"message":"Song not found"}}}"#.utf8))
        }
        defer { server.stop() }
        let base = "http://127.0.0.1:\(server.port)"
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/subsonic", isDirectory: true)
        try? FileManager.default.removeItem(at: cache)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let got = awaitValue { try? await Subsonic.download(id: "78", to: cache.appendingPathComponent("78.wav"), server: base, user: "u", password: "p") }
        assertEqual(got.flatMap { try? Data(contentsOf: $0) }, wav, "stream: the original file downloaded")
        let missing = awaitValue { () -> String in
            do { _ = try await Subsonic.download(id: "1", to: cache.appendingPathComponent("1.mp3"), server: base, user: "u", password: "p"); return "" }
            catch { return error.localizedDescription }
        }
        assertEqual(missing, "Song not found", "An error body instead of audio is reported, not saved")
        assertTrue(!FileManager.default.fileExists(atPath: cache.appendingPathComponent("1.mp3").path), "Nothing cached for it")
        let cached = Subsonic.cacheFolder.appendingPathComponent("cached1.wav")
        try FileManager.default.createDirectory(at: Subsonic.cacheFolder, withIntermediateDirectories: true)
        try wav.write(to: cached)
        let local = awaitValue { try? await Subsonic.localFile(for: Subsonic.trackURL(id: "cached1", suffix: "wav")) }
        assertEqual(local?.standardizedFileURL, cached.standardizedFileURL, "A cached track plays without the network")
        let engine = AudioEngine.shared
        assertTrue(abs((try loadSync(engine, Subsonic.trackURL(id: "cached1", suffix: "wav"))).duration - 0.5) < 0.05, "The engine plays a subsonic:// track as a file (seekable, with length)")
        engine.stop()
        try? FileManager.default.removeItem(at: cached)

        // Cache cap: the oldest files go, the one just played stays
        let prune = cache.appendingPathComponent("prune", isDirectory: true)
        try FileManager.default.createDirectory(at: prune, withIntermediateDirectories: true)
        for (i, age) in [300.0, 200, 100].enumerated() {
            let f = prune.appendingPathComponent("c\(i).bin")
            try Data(count: 1000).write(to: f)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: f.path)
        }
        Subsonic.pruneCache(keeping: prune.appendingPathComponent("c0.bin"), limit: 1500, folder: prune)
        let left = try FileManager.default.contentsOfDirectory(atPath: prune.path).sorted()
        assertEqual(left, ["c0.bin", "c2.bin"], "Over the limit: older files removed, the newest and the playing one kept")
    }
}

/// A tiny HTTP/1.0 server for client tests: answers each request by its path
final class TestHTTPServer {
    let listener: NWListener
    private let queue = DispatchQueue(label: "test.http")
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(answer: @escaping (String) -> (String, Data)) throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [queue] conn in
            conn.start(queue: queue)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let line = String(data: data ?? Data(), encoding: .utf8)?.components(separatedBy: "\r\n").first ?? ""
                let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let (type, body) = answer(path)
                let header = "HTTP/1.0 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n\r\n"
                conn.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.signal() } }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 2)
    }

    func stop() { listener.cancel() }
}
