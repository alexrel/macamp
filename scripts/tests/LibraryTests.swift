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
}
