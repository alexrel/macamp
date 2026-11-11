import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func playlistTests() {
    testGroup("Large playlist scrolling and duration totals") {
        let playlist = PlaylistModel()
        let url = URL(fileURLWithPath: "/tmp/macamp-long-playlist.mp3")
        playlist.add(tracks: (0..<5_000).map { TrackItem(url: url, title: "Track \($0)", duration: 60) })
        playlist.selectAll()
        assertEqual(playlist.runningTimeMessage, "83:20:00/83:20:00")
        playlist.updateTrack(at: 0, duration: 120)
        assertEqual(playlist.runningTimeMessage, "83:21:00/83:21:00", "Duration changes invalidate both totals")
        playlist.selectNone()
        assertEqual(playlist.runningTimeMessage, "2:00/83:21:00")
        playlist.currentIndex = 4_999
        assertEqual(playlist.runningTimeMessage, "1:00/83:21:00", "With no selection the current track supplies the first duration")

        let view = PlaylistWindowView(playlist: playlist)
        view.frame.size = NSSize(width: 275, height: 232)
        func wheel(_ units: CGScrollEventUnit, _ delta: Int32) -> NSEvent {
            NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 1,
                                     wheel1: delta, wheel2: 0, wheel3: 0)!)!
        }
        view.scrollWheel(with: wheel(.line, -1))
        assertEqual(view.firstVisibleTrackIndex, 1, "A mouse wheel notch keeps the classic single-row step")
        view.scrollWheel(with: wheel(.pixel, -5))
        assertEqual(view.firstVisibleTrackIndex, 1, "A small trackpad delta accumulates without a row jump")
        view.scrollWheel(with: wheel(.pixel, -35))
        assertEqual(view.firstVisibleTrackIndex, 4, "A faster gesture crosses multiple rows")
        view.scrollToTrack(4_999, centered: false)
        let lastPage = view.firstVisibleTrackIndex
        view.scrollWheel(with: wheel(.pixel, -100))
        assertEqual(view.firstVisibleTrackIndex, lastPage, "The viewport stays clamped at the end")

        // Cost of a scroll step with a full redraw: 5000 tracks against 50, same window size
        func scrollFrame(_ view: PlaylistWindowView, last: Int) -> Double {
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            let frames = 300
            let start = CACurrentMediaTime()
            for i in 0..<frames {
                view.scrollToTrack(i * last / frames, centered: false)
                view.cacheDisplay(in: view.bounds, to: rep)
            }
            return (CACurrentMediaTime() - start) / Double(frames)
        }
        let small = PlaylistModel()
        small.add(tracks: (0..<50).map { TrackItem(url: URL(fileURLWithPath: "/tmp/\($0).mp3"), title: "Track \($0)", duration: 60) })
        let smallView = PlaylistWindowView(playlist: small)
        smallView.frame.size = view.frame.size
        _ = scrollFrame(smallView, last: 49) // warm-up: the first frames pay for font and glyph caches
        let shortList = scrollFrame(smallView, last: 49), longList = scrollFrame(view, last: 4_999)
        print(String(format: "  playlist scroll frame: %.2f ms with 5000 tracks, %.2f ms with 50", longList * 1e3, shortList * 1e3))
        assertTrue(view.firstVisibleTrackIndex > 4_000, "The measured scroll went through the whole list")
        assertTrue(longList < 0.008, "A scroll frame of a 5000-track playlist fits half a 60 Hz frame")
        assertTrue(longList < shortList * 3, "Scroll cost doesn't grow with the playlist length")

        playlist.clear()
        assertEqual(playlist.runningTimeMessage, "0:00/0:00", "Clearing the list resets both durations")
    }

    // 3. PlaylistIO PLS & M3U Parser Tests
    testGroup("PlaylistIO PLS & M3U Parsers") {
        let samplePLS = """
        [playlist]
        NumberOfEntries=2
        File1=http://ice1.somafm.com/groovesalad-128-mp3
        Title1=SomaFM: Groove Salad
        Length1=-1
        File2=http://ice2.somafm.com/dronezone-128-mp3
        Title2=SomaFM: Drone Zone
        Length2=-1
        Version=2
        """

        let plsTracks = PlaylistIO.parsePLS(content: samplePLS, baseURL: URL(string: "http://somafm.com")!)
        assertEqual(plsTracks.count, 2, "PLS parser should extract 2 tracks")
        assertEqual(plsTracks[0].title, "SomaFM: Groove Salad", "First track title matches")
        assertEqual(plsTracks[0].url.absoluteString, "http://ice1.somafm.com/groovesalad-128-mp3", "First stream URL matches")
        assertEqual(plsTracks[1].title, "SomaFM: Drone Zone", "Second track title matches")

        let sampleM3U = """
        #EXTM3U
        #EXTINF:-1,SomaFM: Secret Agent
        http://ice1.somafm.com/secretagent-128-mp3
        #EXTINF:240,Local Audio Track - Test Artist
        /Users/test/Music/song.mp3
        """
        let m3uTracks = PlaylistIO.parseM3U(content: sampleM3U, baseURL: URL(fileURLWithPath: "/Users/test/Music"))
        assertEqual(m3uTracks.count, 2, "M3U parser should extract 2 tracks")
        assertEqual(m3uTracks[0].title, "SomaFM: Secret Agent", "First M3U title matches")
        assertEqual(m3uTracks[0].url.absoluteString, "http://ice1.somafm.com/secretagent-128-mp3", "First M3U URL matches")
    }

    // 13. Shuffle order consistency
    testGroup("Playlist Shuffle Order") {
        func makeTracks(_ n: Int, prefix: String) -> [TrackItem] {
            (0..<n).map { TrackItem(url: URL(fileURLWithPath: "/tmp/\(prefix)\($0).mp3"), title: "\(prefix)\($0)", artist: "T", duration: 60) }
        }
        func playThrough(_ pl: PlaylistModel) -> [UUID] {
            var played: [UUID] = []
            while let t = pl.next() { played.append(t.id); if played.count > 1000 { break } }
            return played
        }

        for _ in 0..<20 {
            // A full pass plays every track exactly once, starting after the current one
            let pl = PlaylistModel()
            pl.add(tracks: makeTracks(12, prefix: "a"))
            pl.isShuffle = true
            let first = pl.currentTrack!.id
            let played = [first] + playThrough(pl)
            assertEqual(played.count, 12, "Shuffle pass length")
            assertEqual(Set(played).count, 12, "Shuffle pass has no repeats")
            assertTrue(pl.next() == nil, "Without repeat the pass ends")
        }

        for _ in 0..<20 {
            // Directly choosing a track (double-click / Jump to File) keeps the pass consistent
            let pl = PlaylistModel()
            pl.add(tracks: makeTracks(10, prefix: "b"))
            pl.isShuffle = true
            var played = [pl.currentTrack!.id]
            played.append(pl.next()!.id)
            played.append(pl.next()!.id)
            let unplayed = (0..<10).filter { !played.contains(pl.tracks[$0].id) }
            let jumpIdx = unplayed.randomElement()!
            let beforeJump = pl.currentTrack!.id
            pl.currentIndex = jumpIdx
            played.append(pl.tracks[jumpIdx].id)
            assertEqual(pl.previous()?.id, beforeJump, "Previous after a jump returns to the track played before it")
            assertEqual(pl.next()?.id, pl.tracks[jumpIdx].id, "Next returns to the jumped-to track")
            played += playThrough(pl)
            assertEqual(played.count, 10, "Pass after a jump still covers each track once")
            assertEqual(Set(played).count, 10, "No repeats after a jump")
        }

        for _ in 0..<20 {
            // Adding and removing tracks mid-pass keeps the remainder valid
            let pl = PlaylistModel()
            pl.add(tracks: makeTracks(8, prefix: "c"))
            pl.isShuffle = true
            var played = [pl.currentTrack!.id]
            played.append(pl.next()!.id)
            let added = makeTracks(4, prefix: "d")
            pl.add(tracks: added)
            let unplayedIdx = (0..<pl.tracks.count).filter { !played.contains(pl.tracks[$0].id) }
            let removeIdx = unplayedIdx.randomElement()!
            let removedID = pl.tracks[removeIdx].id
            pl.remove(at: removeIdx)
            played += playThrough(pl)
            assertTrue(!played.contains(removedID), "Removed track is never played")
            assertEqual(Set(played).count, played.count, "No repeats after add/remove")
            assertEqual(played.count, 11, "Every remaining track (8 + 4 - 1) is played once")
            assertTrue(Set(added.map(\.id)).subtracting([removedID]).isSubset(of: Set(played)), "Tracks added mid-pass are played")
        }

        // Sorting mid-pass must not change which tracks are still pending
        let pl = PlaylistModel()
        pl.add(tracks: makeTracks(9, prefix: "e"))
        pl.isShuffle = true
        var played = [pl.currentTrack!.id, pl.next()!.id, pl.next()!.id]
        pl.reverse()
        played += playThrough(pl)
        assertEqual(Set(played).count, 9, "Reverse mid-pass keeps the shuffle pass intact")
        assertEqual(played.count, 9, "Reverse mid-pass: no repeats")

        // Repeat: a new pass starts with a different track than the one that just ended
        let rp = PlaylistModel()
        rp.add(tracks: makeTracks(5, prefix: "f"))
        rp.isShuffle = true
        rp.isRepeat = true
        var last = rp.currentTrack!.id
        for _ in 0..<4 { last = rp.next()!.id }
        let wrapped = rp.next()!.id
        assertTrue(wrapped != last, "New repeat pass does not immediately replay the last track")
    }

    // 14. CP1251 Cyrillic auto-detection (ID3 / playlists / stream titles)
    testGroup("CP1251 Cyrillic Auto-Detection") {
        func mojibake(_ s: String) -> String {
            String(data: s.data(using: TextEncoding.windows1251)!, encoding: .isoLatin1)!
        }
        for original in ["Кино - Группа крови", "Алиса - Трасса Е-95", "ДДТ - Что такое осень", "Ляпис Трубецкой", "DDT - Осень", "Ёлка - Прованс"] {
            let broken = mojibake(original)
            assertTrue(broken != original, "Fixture is actually broken: \(broken)")
            assertEqual(TextEncoding.repairCyrillic(broken), original, "Repairs mojibake '\(broken)'")
            assertEqual(TextEncoding.repairCyrillic(original), original, "Correct Cyrillic stays unchanged")
        }
        assertEqual(TextEncoding.repairCyrillic("Êèíî"), "Кино", "Spec example: Êèíî -> Кино")
        for western in ["Björk", "Mötley Crüe", "Sigur Rós - Ágætis byrjun", "Beyoncé", "Café del Mar", "Hello World", "", "Motörhead – Ace of Spades"] {
            assertEqual(TextEncoding.repairCyrillic(western), western, "Western text untouched: '\(western)'")
        }

        // Raw bytes: UTF-8, CP1251, and genuine Latin-1
        assertEqual(TextEncoding.decode("Кино".data(using: .utf8)!), "Кино", "UTF-8 bytes decode as UTF-8")
        assertEqual(TextEncoding.decode("Группа крови".data(using: TextEncoding.windows1251)!), "Группа крови", "CP1251 bytes decode as Cyrillic")
        assertEqual(TextEncoding.decode("Björk".data(using: .isoLatin1)!), "Björk", "Latin-1 bytes stay Latin-1 (old ID3v1 behaviour turned this into 'Bjцrk')")

        // M3U written by an old Windows player in CP1251
        let m3u = "#EXTM3U\r\n#EXTINF:240,Кино - Звезда по имени Солнце\r\nhttp://example.com/kino.mp3\r\n"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let m3uURL = dir.appendingPathComponent("cp1251.m3u")
        try m3u.data(using: TextEncoding.windows1251)!.write(to: m3uURL)
        let loaded = awaitValue { await PlaylistIO.loadPlaylist(from: m3uURL) }
        assertEqual(loaded.count, 1, "CP1251 M3U parsed")
        assertEqual(loaded.first?.title, "Кино - Звезда по имени Солнце", "CP1251 M3U title decoded as Cyrillic")
    }

    // 15. Playlist Editor keyboard navigation
    testGroup("Playlist Keyboard Navigation") {
        let pl = PlaylistModel()
        pl.add(tracks: (0..<30).map { TrackItem(url: URL(fileURLWithPath: "/tmp/k\($0).mp3"), title: "k\($0)", artist: "T", duration: 60) })
        pl.currentIndex = 0
        let view = PlaylistWindowView(playlist: pl)
        view.frame = NSRect(x: 0, y: 0, width: 275, height: 116)
        view.bounds = view.frame
        assertTrue(view.acceptsFirstResponder, "Playlist view accepts first responder")
        var played: TrackItem?
        view.onPlayTrack = { played = $0 }
        let K = AppConstants.KeyCodes.self

        view.handlePlaylistKey(keyCode: K.downArrow, characters: "", flags: [])
        assertEqual(pl.selectedIndices, [1], "Down from current track selects next row")
        view.handlePlaylistKey(keyCode: K.downArrow, characters: "", flags: [])
        view.handlePlaylistKey(keyCode: K.upArrow, characters: "", flags: [])
        assertEqual(pl.selectedIndices, [1], "Up moves selection back")
        view.handlePlaylistKey(keyCode: K.downArrow, characters: "", flags: .shift)
        view.handlePlaylistKey(keyCode: K.downArrow, characters: "", flags: .shift)
        assertEqual(pl.selectedIndices, [1, 2, 3], "Shift+Down extends selection from the anchor")
        view.handlePlaylistKey(keyCode: K.upArrow, characters: "", flags: .shift)
        assertEqual(pl.selectedIndices, [1, 2], "Shift+Up shrinks the range back toward the anchor")

        view.handlePlaylistKey(keyCode: K.end, characters: "", flags: [])
        assertEqual(pl.selectedIndices, [29], "End jumps to last track")
        view.handlePlaylistKey(keyCode: K.downArrow, characters: "", flags: [])
        assertEqual(pl.selectedIndices, [29], "Down at the end stays on last track")
        view.handlePlaylistKey(keyCode: K.home, characters: "", flags: [])
        assertEqual(pl.selectedIndices, [0], "Home jumps to first track")
        view.handlePlaylistKey(keyCode: K.end, characters: "", flags: .shift)
        assertEqual(pl.selectedIndices.count, 30, "Shift+End selects through the last track")

        view.handlePlaylistKey(keyCode: K.home, characters: "", flags: [])
        view.handlePlaylistKey(keyCode: K.downArrow, characters: "", flags: [])
        view.handlePlaylistKey(keyCode: K.downArrow, characters: "", flags: [])
        view.handlePlaylistKey(keyCode: K.returnKey, characters: "\r", flags: [])
        assertEqual(played?.title, "k2", "Enter plays the track under the cursor")
        assertEqual(pl.currentIndex, 2, "Enter makes it the current track")

        view.handlePlaylistKey(keyCode: K.deleteKey, characters: "", flags: [])
        assertEqual(pl.tracks.count, 29, "Delete removes the selected track")
        assertTrue(!pl.tracks.contains { $0.title == "k2" }, "The removed track is gone")
        assertEqual(pl.selectedIndices, [2], "After Delete the next track is selected for continued editing")

        view.handlePlaylistKey(keyCode: 0, characters: "a", flags: .command)
        assertEqual(pl.selectedIndices.count, 29, "Cmd+A selects all")
        view.handlePlaylistKey(keyCode: K.home, characters: "", flags: [])
        view.handlePlaylistKey(keyCode: 0, characters: "a", flags: .control)
        assertEqual(pl.selectedIndices.count, 29, "Ctrl+A selects all")

        assertTrue(!view.handlePlaylistKey(keyCode: 6, characters: "z", flags: []), "Unhandled keys (Z = Previous) fall through to global hotkeys")
        assertTrue(!view.handlePlaylistKey(keyCode: 35, characters: "p", flags: .control), "Ctrl+P falls through to global hotkeys")
    }

    // 19. Untagged files: Winamp-style file-name titles, legacy playlist migration, scroll to current track
    testGroup("Untagged File Titles & Playlist Scroll") {
        let dashName = "Перемен! - Виктор Цой - ИИ Кавер [1uCtGWO6cRs]"
        let barName = "Электричка ｜ Виктор Цой ｜ AI Cover [OdT90pIZObQ]"
        let dashURL = try makeTestWAV(named: dashName + ".wav", seconds: 0.2)
        let barURL = try makeTestWAV(named: barName + ".wav", seconds: 0.2)

        for (url, name) in [(dashURL, dashName), (barURL, barName)] {
            let meta = awaitValue { await TrackItem.resolveArtistAndTitle(from: url) }
            assertEqual(meta.artist, "", "No tags: no guessed artist for '\(name)'")
            assertEqual(meta.title, name, "No tags: title is the file name")
            let item = awaitValue { await TrackItem.create(from: url) }
            assertEqual(item.displayName, name, "Playlist shows the plain file name, whatever the separator")
        }
        assertEqual(TrackItem.displayName(artist: "Unknown Artist", title: "X"), "X", "Legacy 'Unknown Artist' is never displayed")
        assertEqual(TrackItem.displayName(artist: "Кино", title: "Кукушка"), "Кино - Кукушка", "Tagged tracks keep 'Artist - Title'")

        // Playlist saved by an older version: guessed split for '-' names, 'Unknown Artist' for '｜' names
        let legacy = PlaylistModel()
        legacy.add(tracks: [
            TrackItem(url: dashURL, title: "Виктор Цой - ИИ Кавер [1uCtGWO6cRs]", artist: "Перемен!", duration: 0.2),
            TrackItem(url: barURL, title: barName, artist: "Unknown Artist", duration: 0.2),
            TrackItem(url: URL(fileURLWithPath: "/tmp/tagged.mp3"), title: "Кукушка", artist: "Кино", duration: 60)
        ])
        var migrated = false
        legacy.migrateLegacyFileNameMetadata { migrated = true }
        assertTrue(spinRunLoop(until: { migrated }, timeout: 5), "Legacy metadata migration completes")
        assertEqual(legacy.tracks[0].artist, "", "Guessed artist removed")
        assertEqual(legacy.tracks[0].title, dashName, "Title restored to the file name")
        assertEqual(legacy.tracks[1].artist, "", "'Unknown Artist' cleared")
        assertEqual(legacy.tracks[2].artist, "Кино", "Real tags are left alone")

        // Paused track deep in the list: the playlist opens scrolled to it
        let pl = PlaylistModel()
        pl.add(tracks: (0..<100).map { TrackItem(url: URL(fileURLWithPath: "/tmp/s\($0).mp3"), title: "s\($0)", artist: "T", duration: 60) })
        let view = PlaylistWindowView(playlist: pl)
        view.frame = NSRect(x: 0, y: 0, width: 275, height: 232)
        view.bounds = view.frame
        assertTrue(view.isTrackVisible(0) && !view.isTrackVisible(60), "Starts at the top")
        view.scrollToTrack(60, centered: true)
        assertTrue(view.isTrackVisible(60), "Current track is visible after restore")
        assertTrue(view.firstVisibleTrackIndex > 50, "...and roughly centered (first visible: \(view.firstVisibleTrackIndex))")
        view.scrollToTrack(99, centered: true)
        assertTrue(view.isTrackVisible(99), "Last track: scroll is clamped but the track is visible")
        view.scrollToTrack(0, centered: false)
        assertEqual(view.firstVisibleTrackIndex, 0, "Minimal scroll back to the first track")
    }

    testGroup("Playlist MISC: Path Sort, PLS Save, HTML Export") {
        let pl = PlaylistModel()
        pl.add(tracks: [
            TrackItem(url: URL(fileURLWithPath: "/Music/B/02.mp3"), title: "z", artist: "", duration: 60),
            TrackItem(url: URL(fileURLWithPath: "/Music/A/10.mp3"), title: "y", artist: "", duration: 60),
            TrackItem(url: URL(fileURLWithPath: "/Music/A/9.mp3"), title: "x", artist: "", duration: 60)
        ])
        pl.currentIndex = 0
        let currentID = pl.currentTrack!.id
        pl.sortByPath()
        assertEqual(pl.tracks.map { $0.url.lastPathComponent }, ["9.mp3", "10.mp3", "02.mp3"], "Path sort is folder-first and numeric-aware")
        assertEqual(pl.currentTrack?.id, currentID, "Current track follows the sort")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tracks = [
            TrackItem(url: URL(fileURLWithPath: "/Music/Кино - Кукушка.mp3"), title: "Кукушка", artist: "Кино", duration: 401),
            TrackItem(url: URL(string: "http://radio.example.com:8000/stream")!, title: "Radio", artist: "Internet Stream", duration: 0)
        ]
        let plsURL = dir.appendingPathComponent("out.pls")
        try PlaylistIO.save(tracks: tracks, to: plsURL)
        let plsText = try String(contentsOf: plsURL, encoding: .utf8)
        assertTrue(plsText.contains("File2=http://radio.example.com:8000/stream"), "Stream keeps its full URL in PLS")
        assertTrue(plsText.contains("NumberOfEntries=2"), "PLS entry count")
        let parsed = PlaylistIO.parsePLS(content: plsText, baseURL: dir)
        assertEqual(parsed.count, 2, "Saved PLS parses back")
        let m3uURL = dir.appendingPathComponent("out.m3u")
        try PlaylistIO.save(tracks: tracks, to: m3uURL)
        assertTrue(try String(contentsOf: m3uURL, encoding: .utf8).contains("\nhttp://radio.example.com:8000/stream\n"), "Stream keeps its full URL in M3U (was saved as a bare path)")

        let html = PlaylistIO.generateHTML(tracks: tracks + [TrackItem(url: URL(fileURLWithPath: "/x.mp3"), title: "<b>&</b>", artist: "", duration: 30)])
        assertTrue(html.contains("Кино - Кукушка (6:41)"), "HTML lists 'Artist - Title (time)'")
        assertTrue(html.contains("&lt;b&gt;&amp;&lt;/b&gt;") && !html.contains("<b>&</b>"), "HTML escapes titles")
        assertTrue(html.contains("<b>3</b> tracks"), "HTML shows the track count")
    }

    testGroup("Playlist Paths: Absolute, Relative, VLC, Windows") {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/paths", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        let music = root.appendingPathComponent("Music/Кино", isDirectory: true)
        let other = root.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: music.appendingPathComponent("mp3"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let song = music.appendingPathComponent("mp3/#1 Группа крови [x].mp3")
        let near = music.appendingPathComponent("Кукушка.mp3")
        let far = other.appendingPathComponent("Far Song.mp3")
        for f in [song, near, far] { FileManager.default.createFile(atPath: f.path, contents: Data()) }
        let base = music
        func resolves(_ entry: String, to expected: URL, _ what: String) {
            let got = PlaylistIO.resolveEntry(entry, baseURL: base)
            assertEqual(got.standardizedFileURL.path, expected.standardizedFileURL.path, what)
        }
        resolves(near.path, to: near, "Absolute path")
        resolves("Кукушка.mp3", to: near, "Relative to the playlist's folder")
        resolves("mp3/#1 Группа крови [x].mp3", to: song, "Relative path in a subfolder")
        resolves("../../Other/Far Song.mp3", to: far, "Relative path with ..")
        resolves("./Кукушка.mp3", to: near, "Relative path with ./")
        resolves("mp3/%231%20%D0%93%D1%80%D1%83%D0%BF%D0%BF%D0%B0%20%D0%BA%D1%80%D0%BE%D0%B2%D0%B8%20%5Bx%5D.mp3", to: song, "VLC-style percent-encoded relative path")
        resolves(song.absoluteString, to: song, "file:// URL")
        resolves("mp3\\#1 Группа крови [x].mp3", to: song, "Windows backslashes")
        assertEqual(PlaylistIO.resolveEntry("http://radio.example.com/stream", baseURL: base).absoluteString, "http://radio.example.com/stream", "Stream URLs stay URLs")
        let home = PlaylistIO.resolveEntry("~/Music/x.mp3", baseURL: base)
        assertTrue(home.path.hasSuffix("/Music/x.mp3") && !home.path.contains("~"), "~ expands to the home folder (\(home.path))")

        // Saving with relative paths: files under the playlist's folder relative, others absolute; round-trips
        let saveTracks = [song, near, far].map { TrackItem(url: $0, title: $0.lastPathComponent) } + [TrackItem(url: URL(string: "http://radio.example.com/stream")!, title: "r")]
        for ext in ["m3u", "pls"] {
            let out = music.appendingPathComponent("relative.\(ext)")
            try PlaylistIO.save(tracks: saveTracks, to: out, relativePaths: true)
            let text = try String(contentsOf: out, encoding: .utf8)
            assertTrue(text.contains("mp3/#1 Группа крови [x].mp3\n") && !text.contains(song.path), "\(ext): file in a subfolder saved relative")
            assertTrue(text.contains(far.standardizedFileURL.path), "\(ext): file outside the folder stays absolute")
            assertTrue(text.contains("http://radio.example.com/stream"), "\(ext): stream URL unchanged")
            let entries = awaitValue { await PlaylistIO.loadEntries(from: out) }
            assertEqual(entries.map { $0.url.standardizedFileURL.path }.prefix(3).map { $0 }, [song, near, far].map { $0.standardizedFileURL.path }, "\(ext): relative playlist loads back")
        }
        try PlaylistIO.save(tracks: saveTracks, to: music.appendingPathComponent("absolute.m3u"))
        assertTrue(try String(contentsOf: music.appendingPathComponent("absolute.m3u"), encoding: .utf8).contains(near.standardizedFileURL.path), "Absolute paths by default")

        // A VLC playlist (the kind that failed to open) loads with every file found
        let m3u = "#EXTM3U\n#EXTINF:123,Группа крови\nmp3/%231%20%D0%93%D1%80%D1%83%D0%BF%D0%BF%D0%B0%20%D0%BA%D1%80%D0%BE%D0%B2%D0%B8%20%5Bx%5D.mp3\n#EXTINF:60,Кукушка\nКукушка.mp3\n"
        let m3uURL = music.appendingPathComponent("vlc.m3u")
        try m3u.write(to: m3uURL, atomically: true, encoding: .utf8)
        let loaded = awaitValue { await PlaylistIO.loadPlaylist(from: m3uURL) }
        assertEqual(loaded.count, 2, "Both entries loaded")
        assertEqual(PlaylistIO.displayTitle("Reggae - Янка [a0VMeWSTyQY].mp3", for: URL(fileURLWithPath: "/x/Reggae.mp3")), "Reggae - Янка [a0VMeWSTyQY]", "VLC's file-name titles lose the extension")
        assertEqual(PlaylistIO.displayTitle("Кино - Звезда", for: URL(fileURLWithPath: "/x/a.mp3")), "Кино - Звезда", "Normal titles untouched")
        assertEqual(PlaylistIO.displayTitle("Live at mp3.com", for: URL(fileURLWithPath: "/x/a.mp3")), "Live at mp3.com", "Only a real '.ext' suffix is removed")
        assertTrue(loaded.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) }, "Every entry points at an existing file")
    }

    testGroup("VLC Playlists: XSPF and M3U8") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/vlc", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("mp3"), withIntermediateDirectories: true)
        let abs = dir.appendingPathComponent("Кино - Звезда.mp3"), rel = dir.appendingPathComponent("mp3/#2 Песня [y].mp3")
        for f in [abs, rel] { FileManager.default.createFile(atPath: f.path, contents: Data()) }
        // As VLC writes it: absolute file:// URI, relative percent-encoded URI, a stream, durations in ms
        let xspf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <playlist xmlns="http://xspf.org/ns/0/" xmlns:vlc="http://www.videolan.org/vlc/playlist/ns/0/" version="1">
        \t<title>Плейлист</title>
        \t<trackList>
        \t\t<track><location>\(abs.absoluteString)</location><title>Звезда</title><creator>Кино</creator><duration>245000</duration>
        \t\t\t<extension application="http://www.videolan.org/vlc/playlist/0"><vlc:id>0</vlc:id></extension></track>
        \t\t<track><location>mp3/%232%20%D0%9F%D0%B5%D1%81%D0%BD%D1%8F%20%5By%5D.mp3</location><duration>60000</duration></track>
        \t\t<track><location>http://radio.example.com:8000/stream</location><title>Radio</title></track>
        \t</trackList>
        </playlist>
        """
        let xspfURL = dir.appendingPathComponent("vlc.xspf")
        try xspf.write(to: xspfURL, atomically: true, encoding: .utf8)
        let items = awaitValue { await PlaylistIO.loadPlaylist(from: xspfURL) }
        assertEqual(items.count, 3, "All three XSPF tracks loaded")
        assertEqual(items[0].url.standardizedFileURL.path, abs.standardizedFileURL.path, "Absolute file:// URI with Cyrillic")
        assertEqual(items[1].url.standardizedFileURL.path, rel.standardizedFileURL.path, "Relative percent-encoded location")
        assertEqual(items[2].url.absoluteString, "http://radio.example.com:8000/stream", "Stream location")
        assertEqual(items[0].duration, 245, "Duration converted from milliseconds")
        assertTrue(AppConstants.Audio.playlistExtensions.isSuperset(of: ["m3u", "m3u8", "pls", "xspf"]), "m3u8 and xspf accepted everywhere playlists are")

        let m3u8URL = dir.appendingPathComponent("vlc.m3u8")
        try "#EXTM3U\n#EXTINF:245,Кино - Звезда\n\(abs.absoluteString)\nmp3/%232%20%D0%9F%D0%B5%D1%81%D0%BD%D1%8F%20%5By%5D.mp3\n".write(to: m3u8URL, atomically: true, encoding: .utf8)
        let m3u8 = awaitValue { await PlaylistIO.loadPlaylist(from: m3u8URL) }
        assertEqual(m3u8.count, 2, "M3U8 entries loaded")
        assertTrue(m3u8.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) }, "M3U8: file:// and relative encoded paths both found")
    }

    testGroup("Drag & Drop into the Playlist") {
        // AppKit must call our handlers (they used to be invisible to it, so drops did nothing)
        for name in ["draggingEntered:", "performDragOperation:"] {
            let sel = NSSelectorFromString(name)
            assertTrue(class_getMethodImplementation(WinampWindow.self, sel) != class_getMethodImplementation(NSWindow.self, sel), "WinampWindow implements \(name)")
            assertTrue(class_getMethodImplementation(PlaylistWindowView.self, sel) != class_getMethodImplementation(NSView.self, sel), "PlaylistWindowView implements \(name)")
        }

        let pl = PlaylistModel()
        pl.add(tracks: (0..<10).map { TrackItem(url: URL(fileURLWithPath: "/tmp/d\($0).mp3"), title: "d\($0)", artist: "T", duration: 60) })
        pl.currentIndex = 5
        let currentID = pl.currentTrack!.id
        let view = PlaylistWindowView(playlist: pl)
        view.frame = NSRect(x: 0, y: 0, width: 275, height: 232)
        view.bounds = view.frame
        var dropped: ([String], Int)?
        view.onFilesDropped = { dropped = ($0, $1) }

        let topH = AppConstants.Playlist.Layout.topBarHeight, rowH = AppConstants.Playlist.trackRowHeight
        assertEqual(view.dropIndex(at: NSPoint(x: 50, y: topH + rowH * 3 + 2)), 3, "Drop near the top edge of row 3 inserts before it")
        assertEqual(view.dropIndex(at: NSPoint(x: 50, y: topH + rowH * 3 + rowH - 2)), 4, "Drop on the lower half inserts after it")
        assertEqual(view.dropIndex(at: NSPoint(x: 50, y: 220)), 10, "Drop below the last track appends")

        let file = URL(fileURLWithPath: "/tmp/dropped.mp3")
        // draggingLocation is in window coordinates (y up); the playlist view is flipped (y down)
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 275, height: 232), styleMask: [.borderless], backing: .buffered, defer: false)
        host.contentView = view
        let drag = FakeDrop(urls: [file], location: view.convert(NSPoint(x: 50, y: topH + rowH * 2 + 2), to: nil))
        assertEqual(view.draggingEntered(drag), .copy, "Finder files are accepted")
        assertTrue(view.performDragOperation(drag), "Drop accepted")
        assertEqual(dropped?.0, [file.path], "Dropped paths passed on")
        assertEqual(dropped?.1, 2, "Insertion position passed on")

        pl.insert(tracks: [TrackItem(url: file, title: "dropped", artist: "", duration: 30)], at: 2)
        assertEqual(pl.tracks[2].title, "dropped", "Inserted at the drop position")
        assertEqual(pl.tracks.count, 11, "Nothing replaced")
        assertEqual(pl.currentTrack?.id, currentID, "Current track is still the same song")
        assertEqual(pl.selectedIndices, [2], "Dropped tracks are selected")
        pl.insert(tracks: [TrackItem(url: file, title: "end", artist: "", duration: 30)], at: 999)
        assertEqual(pl.tracks.last?.title, "end", "Out-of-range position appends")

        let nothing = FakeDrop(urls: [], location: .zero)
        assertEqual(view.draggingEntered(nothing), [], "Non-file drags are refused")
    }

    testGroup("Bookmarks") {
        let store = BookmarkStore.shared
        store.remove(Set(store.items.map(\.id)))
        let song = TrackItem(url: URL(fileURLWithPath: "/tmp/Кино - Кукушка.mp3"), title: "Кукушка", artist: "Кино", duration: 401)
        let radio = TrackItem.entry(url: URL(string: "http://radio.example.com:8000/stream")!, title: "Radio")
        store.add([song, radio, song])
        assertEqual(store.items.map(\.title), ["Кино - Кукушка", "Radio"], "Bookmarks use the playlist title; a file isn't added twice")
        assertEqual(PersistenceManager.shared.state.bookmarks.count, 2, "Bookmarks saved with the session")
        let data = try JSONEncoder().encode(PersistenceManager.shared.state)
        let decoded = try JSONDecoder().decode(AppState.self, from: data)
        assertEqual(decoded.bookmarks.map(\.url), [song.url, radio.url], "Bookmarks round-trip through session.json")
        var edited = store.items[1]
        edited.title = "My Radio"
        store.update(edited)
        assertEqual(store.items[1].title, "My Radio", "Edit bookmark changes the title")

        let coordinator = PlayerCoordinator.shared
        let menu = coordinator.buildBookmarksMenu()
        assertEqual(menu.items.map(\.title), ["Add current as bookmark", "Edit bookmarks...", "", "Кино - Кукушка", "My Radio"], "Bookmarks menu: add, edit, then the list")
        assertEqual(menu.items[0].keyEquivalent, "i", "Add current as bookmark is ⌥I")
        assertEqual(menu.items[0].keyEquivalentModifierMask, [.option], "Add current as bookmark is ⌥I")
        assertEqual(menu.items[1].keyEquivalentModifierMask, [.control, .option], "Edit bookmarks is ⌃⌥I")
        store.remove([store.items[0].id])
        assertEqual(store.items.map(\.title), ["My Radio"], "Remove deletes the bookmark")
        store.remove(Set(store.items.map(\.id)))
        let empty = coordinator.buildBookmarksMenu()
        assertEqual(empty.items.last?.title, "(no bookmarks)", "Empty list shows (no bookmarks) like Winamp")
        assertTrue(empty.items.last?.isEnabled == false, "(no bookmarks) is disabled")
        assertTrue(PrefTreeItem.bookmarks.parent == nil, "Bookmarks is a top-level page, as in 2.95")
    }

    testGroup("CUE Sheets") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/cue/Альбом", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wav = try makeTestWAV(named: "cue-album.wav", seconds: 4.0)
        let album = dir.appendingPathComponent("album.wav")
        try FileManager.default.copyItem(at: wav, to: album)
        try FileManager.default.copyItem(at: wav, to: dir.appendingPathComponent("bonus.wav"))
        // Sheet written for a FLAC rip that sits next to it as .wav; pregap on track 2; a data track
        let cue = """
        REM GENRE Rock
        PERFORMER "Кино"
        TITLE "Группа крови"
        FILE "album.flac" WAVE
          TRACK 01 AUDIO
            TITLE "Группа крови"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Закрой за мной дверь"
            PERFORMER "Виктор Цой"
            INDEX 00 00:01:00
            INDEX 01 00:01:37
          TRACK 03 AUDIO
            TITLE "Последний герой"
            INDEX 01 00:03:00
          TRACK 04 MODE1/2352
            INDEX 01 00:03:50
        """
        let cueURL = dir.appendingPathComponent("album.cue")
        try cue.write(to: cueURL, atomically: true, encoding: .utf8)

        let entries = CueSheet.parse(content: cue, baseURL: dir)
        assertEqual(entries.count, 3, "Audio tracks only (data track skipped)")
        assertEqual(entries.map(\.title), ["Группа крови", "Закрой за мной дверь", "Последний герой"], "Track titles")
        assertEqual(entries.map(\.artist), ["Кино", "Виктор Цой", "Кино"], "Track performer, else the album performer")
        assertEqual(entries[0].url.withoutPlaybackRange.standardizedFileURL, album.standardizedFileURL, "FILE .flac found as the .wav next to the sheet")
        assertTrue(abs((entries[1].url.playbackRange?.start ?? 0) - (1 + 37.0 / 75)) < 0.001, "Starts at INDEX 01 (mm:ss:ff, 75 frames/s)")
        assertTrue(abs(entries[0].duration - (1 + 37.0 / 75)) < 0.001, "Ends where the next track's INDEX 01 starts (pregap stays with the previous track)")
        assertTrue(entries[2].url.playbackRange?.end == nil, "Last track runs to the end of the file")
        assertTrue(entries[0].url != entries[1].url, "Each track has its own URL")

        // UTF-8 with BOM and CRLF line ends (like EAC / foobar sheets); album PERFORMER on the first line
        let bomCue = "PERFORMER \"Enigma\"\r\nFILE \"album.wav\" WAVE\r\n  TRACK 01 AUDIO\r\n    TITLE \"Morphing Thru Time\"\r\n    INDEX 01 01:57:73\r\n"
        let bomEntries = PlaylistIO.parse(data: Data([0xEF, 0xBB, 0xBF]) + Data(bomCue.utf8), ext: "cue", baseURL: dir)
        assertEqual(bomEntries.first?.artist, "Enigma", "BOM doesn't hide the first line")
        assertTrue(abs((bomEntries.first?.url.playbackRange?.start ?? 0) - (117 + 73.0 / 75)) < 0.001, "CRLF sheet parses (01:57:73)")
        let bomM3U = PlaylistIO.parse(data: Data([0xEF, 0xBB, 0xBF]) + Data("#EXTM3U\r\nalbum.wav\r\n".utf8), ext: "m3u", baseURL: dir)
        assertEqual(bomM3U.map(\.url.lastPathComponent), ["album.wav"], "M3U with a BOM: #EXTM3U isn't taken for a file")

        let ranged = album.withPlaybackRange(start: 61.5, end: 120)
        assertTrue(ranged.playbackRange?.start == 61.5 && ranged.playbackRange?.end == 120, "Range round-trips through the URL")
        assertEqual(ranged.withoutPlaybackRange, album, "Range strips back to the file")
        assertTrue(album.playbackRange == nil, "Plain files have no range")
        let saved = try JSONDecoder().decode(TrackItem.self, from: JSONEncoder().encode(entries[1]))
        assertEqual(saved.url, entries[1].url, "The range survives the saved playlist")

        let loaded = awaitValue { await PlaylistIO.loadPlaylist(from: cueURL) }
        assertEqual(loaded.map(\.title), entries.map(\.title), "Loading the sheet keeps its titles (not the file's tags)")
        assertTrue(abs(loaded[2].duration - (4 - 3)) < 0.05, "Open-ended last track gets the rest of the file (\(loaded[2].duration))")

        // Folder add: the sheet's tracks instead of the big file; other files stay
        let scanned = awaitValue { await PlayerCoordinator.scanPaths([dir.path]) }.tracks
        assertEqual(scanned.map(\.title), ["Группа крови", "Закрой за мной дверь", "Последний герой", "bonus"], "Folder: CUE tracks replace album.wav, bonus.wav kept")

        // Playback of one track's range
        let engine = AudioEngine.shared
        let savedFinished = engine.onPlaybackFinished
        defer { engine.onPlaybackFinished = savedFinished; engine.stop() }
        AudioDeviceManager.shared.selectDevice(uid: nil)
        engine.setOutputDevice(deviceID: AudioDeviceManager.shared.defaultDevice?.id)
        var finished = 0
        engine.onPlaybackFinished = { finished += 1 }
        let meta = try loadSync(engine, entries[1].url)
        assertTrue(abs(meta.duration - (3 - (1 + 37.0 / 75))) < 0.01, "Engine reports the track's length, not the file's (\(meta.duration))")
        assertEqual(meta.title, "", "Album-file tags aren't used for a CUE track")
        engine.seek(to: 1.0)
        engine.play()
        _ = spinRunLoop(until: { false }, timeout: 0.15)
        assertTrue(engine.currentTime >= 1.0 && engine.currentTime < 1.4, "Time counts from the track's start (\(engine.currentTime))")
        let began = Date()
        assertTrue(spinRunLoop(until: { finished == 1 }, timeout: 3), "Track ends at its range end")
        assertTrue(Date().timeIntervalSince(began) < 0.9, "Stops at the next track's start, not the end of the file")
    }

    testGroup("Big folders go in at once; one saved-frame format; dialogs measured once") {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("macamp-big-folder-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        // Name order (Album 2 before Album 10), a batch per directory
        for sub in ["Album 2", "Album 10/Disc"] { try fm.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true) }
        for file in ["z.mp3", "b.mp3", "cover.jpg", "Album 10/1.mp3", "Album 10/Disc/9.mp3", "Album 2/1.mp3"] {
            try Data().write(to: dir.appendingPathComponent(file))
        }
        var batches: [[String]] = []
        _ = awaitValue { await PlayerCoordinator.scanPaths([dir.path]) { batch in batches.append(batch.map { $0.url.pathComponents.suffix(from: $0.url.pathComponents.firstIndex(of: dir.lastPathComponent)! + 1).joined(separator: "/") }) } }
        assertEqual(batches, [["Album 2/1.mp3"], ["Album 10/1.mp3"], ["Album 10/Disc/9.mp3"], ["b.mp3", "z.mp3"]],
                    "A folder arrives one directory at a time, in name order, audio files only")
        // Shape of a dropped music share: 19 000 tracks in folders of 13, then every tag arriving
        let share = PlaylistModel()
        share.isShuffle = true
        let shareStart = Date()
        for folder in 0..<1_460 { share.add(tracks: (0..<13).map { TrackItem(url: URL(fileURLWithPath: "/nonexistent/\(folder)/\($0).mp3"), title: "t", duration: 1) }) }
        let added = Date().timeIntervalSince(shareStart)
        let ids = share.tracks.map(\.id)
        let tagStart = Date()
        for id in ids { share.updateTrack(id: id, duration: 200) }
        print(String(format: "  big playlist: %.2f s to add 1460 folders, %.2f s for %d tag updates", added, Date().timeIntervalSince(tagStart), ids.count))

        // Rows on screen are read before the rest of the queue: of two real files, the one in view is read first
        let wav = dir.appendingPathComponent("shown.wav")
        let pcm = AVAudioFile.self
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
            let file = try pcm.init(forWriting: wav, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000)!
            buffer.frameLength = 8_000
            try file.write(from: buffer)
        }
        let queued = PlaylistModel()
        queued.add(tracks: (0..<400).map { TrackItem(url: $0 == 390 || $0 == 100 ? wav : dir.appendingPathComponent("missing\($0).mp3"), title: "t\($0)") })
        queued.prefetchFirst(385..<395)
        _ = spinRunLoop(until: { queued.tracks[390].duration > 0 || queued.tracks[100].duration > 0 }, timeout: 5)
        assertTrue(queued.tracks[390].duration > 0 && queued.tracks[100].duration == 0,
                   "A row scrolled into view gets its length before the rows above it")
        queued.clear()

        let model = PlaylistModel()
        model.add(tracks: (0..<10).map { TrackItem(url: dir.appendingPathComponent("missing\($0).mp3"), title: "t\($0)") })
        model.clear()
        assertEqual(model.tracks.count, 0, "Clearing the list while tags are still being read is safe")

        let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.installScaledDialog(Color.red.frame(width: 320, height: 90))
        assertEqual(window.contentRect(forFrameRect: window.frame).size, NSSize(width: 320, height: 90), "A dialog takes its content's size")

        let coordinator = PlayerCoordinator.shared
        let player = NSWindow(contentRect: NSRect(x: 40, y: 500, width: 826, height: 174), styleMask: [.borderless], backing: .buffered, defer: true)
        player.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 826, height: 174))
        player.updateContentScale(1.5, logicalSize: NSSize(width: 550, height: 116))
        assertEqual(coordinator.savedFrame(of: player) ?? [], [40, 674 - 116, 550, 116], "Saved frame: top-left corner and the size in skin pixels")
    }

    testGroup("Shuffle: launch returns to the last track (2.91)") {
        // What restoreState does: shuffle on first, then the saved playlist, then the saved index
        let pl = PlaylistModel()
        pl.isShuffle = true
        pl.add(tracks: (0..<20).map { TrackItem(url: URL(fileURLWithPath: "/m/\($0).mp3"), title: "T\($0)", duration: 60) })
        pl.currentIndex = 13
        assertEqual(pl.currentTrack?.title, "T13", "The track playing at quit is current again")
        let next = pl.next()
        assertTrue(next != nil && next?.title != "T13", "Next moves on in the shuffle")
        assertEqual(pl.previous()?.title, "T13", "Previous comes back to it")
    }

    testGroup("Shuffle: Previous after picking a track") {
        let pl = PlaylistModel()
        pl.add(tracks: (0..<8).map { TrackItem(url: URL(fileURLWithPath: "/m/\($0).mp3"), title: "T\($0)", duration: 60) })
        pl.isShuffle = true
        let first = pl.next()!, second = pl.next()!, third = pl.next()!
        // Pick an unplayed track, then Previous: back to the one that was playing
        let unplayed = pl.tracks.first { ![first.id, second.id, third.id].contains($0.id) }!
        pl.currentIndex = pl.tracks.firstIndex { $0.id == unplayed.id }
        assertEqual(pl.previous()?.id, third.id, "Previous after picking an unplayed track")
        // Pick a track from the history (played earlier), then Previous: back to the one that was playing
        _ = pl.next() // unplayed again
        pl.currentIndex = pl.tracks.firstIndex { $0.id == first.id }
        assertEqual(pl.previous()?.id, unplayed.id, "Previous after picking an already played track")
    }
}
