import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func setupTests() {
    // 5. Global Hotkeys Controller Tests
    testGroup("Global Hotkeys Controller") {
        let hotkeys = GlobalHotkeysController.shared
        assertTrue(hotkeys.isEnabled == true || hotkeys.isEnabled == false, "isEnabled is readable")

        // Labels are Mac-style and come from the same list that gets registered
        let rows = hotkeys.displayRows
        assertTrue(rows.contains { $0.action == "Play / Pause" && $0.shortcut == "⌃⌥C  or  ⌃⌥Space" }, "Alternatives joined in one row: \(rows)")
        assertTrue(rows.allSatisfy { !$0.shortcut.contains("Ctrl") && !$0.shortcut.contains("Alt") }, "No Windows-style labels")

        // Carbon hotkeys need no Accessibility permission: registration works in a plain process
        let wasEnabled = hotkeys.isEnabled
        hotkeys.isEnabled = false
        assertEqual(hotkeys.registeredHotkeyCount, 0, "Disabled: nothing registered")
        hotkeys.isEnabled = true
        assertEqual(hotkeys.registeredHotkeyCount + hotkeys.unavailableHotkeys.count, hotkeys.hotkeys.count, "Every hotkey is either registered or reported as taken")
        assertTrue(hotkeys.registeredHotkeyCount > 0, "Hotkeys registered without any permission prompt")
        hotkeys.isEnabled = wasEnabled
    }

    testGroup("File Type Associations") {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/apps", isDirectory: true)
        let vlc = tmp.appendingPathComponent("VLC.app"), music = tmp.appendingPathComponent("Music.app"), macamp = tmp.appendingPathComponent("MacAmp.app")
        for app in [vlc, music, macamp] { try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true) }
        let mp3 = UTType(filenameExtension: "mp3")!.identifier, aiff = UTType(filenameExtension: "aiff")!.identifier
        let fake = FakeLaunchServices()
        fake.defaults = [mp3: vlc, aiff: music]
        fake.installed = [macamp, music, vlc]
        PersistenceManager.shared.state.fileAssociations = []
        PersistenceManager.shared.state.fileAssociationPrevious = [:]

        runMain {
            let manager = FileAssociationManager(provider: fake, appURL: macamp, bundleIdentifier: "test.macamp")
            assertTrue(manager.entries.contains { $0.ext == "mp3" } && manager.entries.contains { $0.ext == "wsz" }, "List covers audio, playlists and skins")
            assertTrue(!manager.entries.contains { $0.ext == "alac" }, "'alac' is not a real file extension and is not listed")
            assertTrue(!manager.isAssociated("mp3"), "mp3 starts with VLC")

            await manager.setAssociated("mp3", true)
            assertEqual(fake.defaults[mp3]?.path, macamp.path, "MacAmp becomes the default app for .mp3")
            assertTrue(manager.isAssociated("mp3"), "List shows mp3 as associated")
            assertEqual(PersistenceManager.shared.state.fileAssociationPrevious[mp3], vlc.path, "Previous handler (VLC) remembered")

            await manager.setAssociated("aif", true)
            assertTrue(manager.isAssociated("aif") && manager.isAssociated("aiff"), "aif and aiff share a type and switch together")
            assertEqual(fake.setCalls.filter { $0.0 == aiff }.count, 1, "Shared type is set only once")

            await manager.setAssociated("mp3", false)
            assertEqual(fake.defaults[mp3]?.path, vlc.path, "Unchecking gives .mp3 back to VLC")
            assertTrue(!manager.isAssociated("mp3"), "mp3 no longer associated")

            // Remembered app was deleted -> any other app that can open the type
            PersistenceManager.shared.state.fileAssociationPrevious[aiff] = "/Applications/Deleted.app"
            await manager.setAssociated("aiff", false)
            assertEqual(fake.defaults[aiff]?.path, music.path, "Falls back to another installed app when the previous one is gone")

            // Register types on start: take mp3 back after another app grabbed it
            await manager.setAssociated("mp3", true)
            fake.defaults[mp3] = vlc
            PersistenceManager.shared.state.registerFileTypesOnStart = false
            await manager.reapplyOnLaunchIfNeeded()
            assertEqual(fake.defaults[mp3]?.path, vlc.path, "No re-registration when the option is off")
            PersistenceManager.shared.state.registerFileTypesOnStart = true
            await manager.reapplyOnLaunchIfNeeded()
            assertEqual(fake.defaults[mp3]?.path, macamp.path, "Re-registered on launch")
        }

        // Old session.json without the new keys still decodes with defaults
        let data = try JSONEncoder().encode(AppState())
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["fileAssociationsStorage", "fileAssociationPreviousStorage", "registerFileTypesOnStartStorage", "enqueueAsDefaultActionStorage"] { legacy.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: legacy))
        assertEqual(old.registerFileTypesOnStart, true, "Register on start defaults to on (Winamp default)")
        assertEqual(old.enqueueAsDefaultAction, false, "Finder opens play by default")
    }

    testGroup("Info.plist: ATS, Document Types, Services") {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let plistURL = root.appendingPathComponent("MacAmp/Info.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
        let ats = plist["NSAppTransportSecurity"] as? [String: Any]
        assertEqual(ats?["NSAllowsArbitraryLoads"] as? Bool, true, "http:// radio allowed (ATS)")
        let docs = plist["CFBundleDocumentTypes"] as! [[String: Any]]
        for doc in docs {
            let icon = doc["CFBundleTypeIconFile"] as? String
            assertTrue(icon != nil, "\(doc["CFBundleTypeName"]!) has an icon")
            assertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("MacAmp/Resources/DocumentIcons/\(icon!).icns").path), "Icon \(icon!).icns exists")
            assertTrue((doc["LSHandlerRank"] as? String) != "Default", "MacAmp never claims types without the user's choice")
        }
        let types = docs.flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] }
        for ext in ["mp3", "m4a", "flac", "wav", "aiff", "m3u", "pls"] {
            let t = UTType(filenameExtension: ext)!
            assertTrue(types.contains { t.conforms(to: UTType($0) ?? .data) }, ".\(ext) is declared as openable")
        }
        let services = (plist["NSServices"] as! [[String: Any]]).compactMap { $0["NSMessage"] as? String }
        assertEqual(services, ["playFiles", "enqueueFiles"], "Finder services: Play / Enqueue in MacAmp")
        // Icons are the original Winamp pixel art at every size
        let icon = NSImage(contentsOf: root.appendingPathComponent("MacAmp/Resources/DocumentIcons/WinampAudioFile.icns"))!
        assertTrue(icon.representations.count >= 8, "Audio file icon has all icns sizes (\(icon.representations.count))")
    }

    testGroup("Document Icon Chooser (File icon / Playlist icon sliders)") {
        let built = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("DerivedData/Build/Products/Debug/MacAmp.app")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/IconTest/MacAmp.app")
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: built, to: copy)
        assertTrue(DocumentIconManager.isLocallySigned(copy), "Local Debug build is ad-hoc signed and writable")
        assertEqual(DocumentIconManager.resourceIDs.count, 10, "Ten original Winamp document icons on the slider")
        for id in DocumentIconManager.resourceIDs {
            assertTrue(FileManager.default.fileExists(atPath: copy.appendingPathComponent("Contents/Resources/Choices/winamp-icon-\(id).icns").path), "Choice #\(id) is in the bundle")
        }
        PersistenceManager.shared.state.documentIconIDs = [:]
        let installer = RecordingInstaller()
        runMain {
            let manager = DocumentIconManager(bundleURL: copy, installer: installer, canModifyBundle: true)
            assertEqual(manager.resourceID(for: .audio), 131, "Default file icon is #131 (page with bolt)")
            assertEqual(manager.resourceID(for: .playlist), 102, "Default playlist icon is #102 (bolt)")
            let mp3Index = DocumentIconManager.resourceIDs.firstIndex(of: 182)!
            await manager.select(mp3Index, for: .audio)
            assertEqual(manager.lastError, nil, "Applying the icon succeeded")
            let applied = try! Data(contentsOf: copy.appendingPathComponent("Contents/Resources/WinampAudioFile.icns"))
            let chosen = try! Data(contentsOf: copy.appendingPathComponent("Contents/Resources/Choices/winamp-icon-182.icns"))
            assertTrue(applied == chosen, "Bundle's audio document icon is now #182")
            assertEqual(PersistenceManager.shared.state.documentIconIDs["audio"], 182, "Choice persisted")
            assertEqual(installer.registered.count, 1, "Re-registered with Launch Services once")

            // A rebuild brings back the default icon: launch re-applies the choice
            try! FileManager.default.copyItem(at: copy.appendingPathComponent("Contents/Resources/Choices/winamp-icon-131.icns"),
                                              to: copy.appendingPathComponent("Contents/Resources/Reset.icns"))
            try! installer.install(icon: copy.appendingPathComponent("Contents/Resources/Reset.icns"), as: copy.appendingPathComponent("Contents/Resources/WinampAudioFile.icns"))
            try! FileManager.default.removeItem(at: copy.appendingPathComponent("Contents/Resources/Reset.icns"))
            try! installer.resign(bundle: copy) // a rebuild produces a freshly signed bundle
            await manager.reapplyOnLaunchIfNeeded()
            assertTrue((try! Data(contentsOf: copy.appendingPathComponent("Contents/Resources/WinampAudioFile.icns"))) == chosen, "Choice restored after a rebuild")

            let locked = DocumentIconManager(bundleURL: copy, installer: installer, canModifyBundle: false)
            await locked.select(4, for: .playlist) // a different icon than the current one
            assertEqual(installer.registered.count, 2, "Non-local builds never modify the bundle")
        }
        // build.sh used to drop a symlink inside the bundle root: codesign refuses to sign such a bundle.
        // The icon change must fail cleanly and leave the old icon and a valid signature behind.
        let stray = copy.appendingPathComponent("MacAmp.app")
        try FileManager.default.createSymbolicLink(atPath: stray.path, withDestinationPath: "build/MacAmp.app")
        runMain {
            let manager = DocumentIconManager(bundleURL: copy, installer: installer, canModifyBundle: true)
            let before = try! Data(contentsOf: copy.appendingPathComponent("Contents/Resources/WinampPlaylist.icns"))
            await manager.select(DocumentIconManager.resourceIDs.firstIndex(of: 179)!, for: .playlist)
            assertTrue(manager.lastError != nil, "Signing failure is reported")
            assertTrue(!(manager.lastError ?? "").contains("/Users/"), "Message is short, without raw codesign paths: \(manager.lastError ?? "")")
            let after = try! Data(contentsOf: copy.appendingPathComponent("Contents/Resources/WinampPlaylist.icns"))
            assertTrue(before == after, "Icon rolled back after the failed re-sign")
            assertEqual(manager.resourceID(for: .playlist), 102, "Slider shows the icon that is really in the bundle")
        }
        try FileManager.default.removeItem(at: stray)

        // Dragging only previews; the bundle changes once, on release
        runMain {
            let manager = DocumentIconManager(bundleURL: copy, installer: installer, canModifyBundle: true)
            let registeredBefore = installer.registered.count
            for index in 0..<5 { manager.preview(index, for: .playlist) }
            assertEqual(installer.registered.count, registeredBefore, "Dragging over five ticks applies nothing yet")
            await manager.commit(for: .playlist)
            assertEqual(installer.registered.count, registeredBefore + 1, "Release applies exactly once")
            assertEqual(PersistenceManager.shared.state.documentIconIDs["playlist"], DocumentIconManager.resourceIDs[4], "Released position saved")
        }
        // A choice saved by an older build (XP composites 1131/1102) falls back to the Winamp default
        PersistenceManager.shared.state.documentIconIDs = ["audio": 1131, "playlist": 1102]
        runMain {
            let manager = DocumentIconManager(bundleURL: copy, installer: installer, canModifyBundle: false)
            assertEqual(manager.resourceID(for: .audio), 131, "Unknown saved icon -> #131")
            assertEqual(manager.resourceID(for: .playlist), 102, "Unknown saved icon -> #102")
        }
        PersistenceManager.shared.state.documentIconIDs = [:]

        // The re-signed bundle is still valid
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", copy.path]
        try verify.run(); verify.waitUntilExit()
        assertEqual(verify.terminationStatus, 0, "codesign --verify passes after the icon change")
        try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
    }

    testGroup("Document Icons Use the 256-Color Frames") {
        // Each .icns's 32 px image must be exactly the 256-color source frame, not the 16-color one
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("MacAmp/Resources/DocumentIcons")
        func pixels(_ image: CGImage) -> [UInt8] {
            let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: 32 * 32 * 4))
        }
        for id in DocumentIconManager.resourceIDs {
            let png = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(dir.appendingPathComponent("Source/winamp-icon-\(id).png") as CFURL, nil)!, 0, nil)!
            let icnsSource = CGImageSourceCreateWithURL(dir.appendingPathComponent("Choices/winamp-icon-\(id).icns") as CFURL, nil)!
            let frame32 = (0..<CGImageSourceGetCount(icnsSource)).compactMap { CGImageSourceCreateImageAtIndex(icnsSource, $0, nil) }.first { $0.width == 32 }!
            let a = pixels(png), b = pixels(frame32)
            let diff = zip(a, b).filter { abs(Int($0) - Int($1)) > 2 }.count
            assertTrue(diff == 0, "Icon #\(id): 32 px frame matches the 256-color source (\(diff) channel values differ)")
        }
    }

    testGroup("Icon Slider: Press, Drag, Release") {
        // Real mouse events through AppKit's tracking loop (the slider used to move one tick per click only)
        let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let slider = Win32VerticalTickSliderView(frame: NSRect(x: 10, y: 10, width: 28, height: 64))
        slider.count = 10
        slider.position = 1
        var changes: [Int] = []
        var commits = 0
        slider.onChange = { changes.append($0) }
        slider.onCommit = { commits += 1 }
        win.contentView!.addSubview(slider)
        win.orderFrontRegardless()
        let frame = slider.convert(slider.bounds, to: nil)
        func ev(_ type: NSEvent.EventType, _ yFromTop: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: frame.minX + 8, y: frame.maxY - yFromTop), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        for y in stride(from: 14.0, through: 58.0, by: 4.0) { NSApp.postEvent(ev(.leftMouseDragged, CGFloat(y)), atStart: false) }
        NSApp.postEvent(ev(.leftMouseUp, 58), atStart: false)
        win.sendEvent(ev(.leftMouseDown, 11))
        assertEqual(slider.position, 9, "Press-and-drag moves the thumb all the way down")
        assertTrue(changes.count >= 5, "Thumb follows the mouse through the ticks (\(changes))")
        assertEqual(commits, 1, "One commit, on release")
        slider.isEnabled = false
        NSApp.postEvent(ev(.leftMouseUp, 5), atStart: false)
        win.sendEvent(ev(.leftMouseDown, 5))
        assertEqual(slider.position, 9, "Disabled slider ignores the mouse")
        win.orderOut(nil)
    }

    testGroup("Setup: Check for New Versions") {
        assertTrue(UpdateChecker.isNewer("0.9", than: "0.8") && UpdateChecker.isNewer("0.10", than: "0.9") && UpdateChecker.isNewer("1.0", than: "0.10"), "Newer by number, not by text")
        assertTrue(UpdateChecker.isNewer("0.8.1", than: "0.8"), "A fix release is newer")
        assertTrue(!UpdateChecker.isNewer("0.8", than: "0.8") && !UpdateChecker.isNewer("0.8", than: "0.9") && !UpdateChecker.isNewer("0.8", than: "0.8.0"), "Same or older is not")
        func reply(_ link: String) -> Data {
            try! JSONSerialization.data(withJSONObject: ["tag_name": "v0.9", "body": "Fixes\r\nand more", "assets": [
                ["browser_download_url": "https://github.com/alexrel/macamp/releases/download/v0.9/MacAmp-0.9.zip"],
                ["browser_download_url": link]]])
        }
        let release = UpdateChecker.parse(reply("https://github.com/alexrel/macamp/releases/download/v0.9/MacAmp-0.9.dmg"))
        assertEqual(release?.version, "0.9", "Version from the tag")
        assertEqual(release?.notes, "Fixes\nand more", "Release notes")
        assertEqual(release?.dmg.lastPathComponent, "MacAmp-0.9.dmg", "The disk image, not the zip")
        assertTrue(UpdateChecker.parse(reply("https://example.com/alexrel/macamp/releases/download/v0.9/MacAmp-0.9.dmg")) == nil, "A file from elsewhere is not offered")
        assertTrue(UpdateChecker.parse(Data("{\"message\":\"Not Found\"}".utf8)) == nil, "No release, no offer")
        let now = Date()
        assertTrue(UpdateChecker.isDue(last: nil, now: now) && UpdateChecker.isDue(last: now.addingTimeInterval(-90_000), now: now), "Never checked or a day ago: check")
        assertTrue(!UpdateChecker.isDue(last: now.addingTimeInterval(-3_600), now: now), "Checked an hour ago: don't")
        assertTrue(AppState().checkForUpdates, "On by default, as in Winamp")

        // The download lands at the target, over an older copy, and reports its progress
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-update-source.dmg")
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-update-target.dmg")
        try Data(repeating: 7, count: 300_000).write(to: source)
        try Data("old".utf8).write(to: target)
        var percents: [Int] = []
        var finished = false
        Task { @MainActor in
            try? await UpdateChecker.download(source, to: target) { percents.append($0) }
            finished = true
        }
        _ = spinRunLoop(until: { finished && percents.last == 100 }, timeout: 5)
        assertEqual((try? Data(contentsOf: target))?.count, 300_000, "Downloaded file replaces the old one")
        assertEqual(percents.last, 100, "Progress reaches 100% (\(percents))")
    }

    testGroup("Setup: Internet Settings") {
        assertTrue(MacAmpNetwork.parseProxy("") == nil, "Blank proxy = none")
        assertTrue(MacAmpNetwork.parseProxy("proxy.example.com:8080")! == ("proxy.example.com", 8080), "server:port")
        assertTrue(MacAmpNetwork.parseProxy("http://10.0.0.1:3128/")! == ("10.0.0.1", 3128), "Tolerates http:// and trailing slash")
        assertTrue(MacAmpNetwork.parseProxy("host:99999") == nil, "Invalid port rejected")
        PersistenceManager.shared.state.httpProxy = "proxy.example.com:8080"
        let dict = MacAmpNetwork.configuration().connectionProxyDictionary
        assertEqual(dict?["HTTPProxy"] as? String, "proxy.example.com", "Proxy host applied to stream sessions")
        assertEqual(dict?["HTTPPort"] as? Int, 8080, "Proxy port applied")
        PersistenceManager.shared.state.httpProxy = ""
        assertTrue(MacAmpNetwork.configuration().connectionProxyDictionary == nil, "No proxy -> system settings")

        PersistenceManager.shared.state.networkOffline = true
        defer { PersistenceManager.shared.state.networkOffline = false }
        var thrown: Error?
        Task { @MainActor in
            do { _ = try await AudioEngine.shared.load(url: URL(string: "http://radio.example.com/stream")!) } catch { thrown = error }
        }
        _ = spinRunLoop(until: { thrown != nil }, timeout: 5)
        assertEqual((thrown as? URLError)?.code, .notConnectedToInternet, "Offline mode refuses to open streams")
    }

    testGroup("Test runs are silent") {
        assertTrue(AudioEngine.isTestRun, "Runner sets MACAMP_TEST_HOME")
        let engine = AudioEngine.shared
        defer { engine.stop() }
        _ = try loadSync(engine, try makeTestWAV(named: "silent.wav", seconds: 0.5))
        engine.play()
        var gain: AudioUnitParameterValue = 1
        if let unit = engine.engineOutputUnit { AudioUnitGetParameter(unit, kHALOutputParam_Volume, kAudioUnitScope_Global, 0, &gain) }
        assertEqual(gain, 0, "Output unit muted while tests play")
        assertTrue(engine.volume > 0, "Player volume itself untouched")
    }

    testGroup("Settings from older versions still load") {
        // A session.json saved before any of this release's settings existed: every new setting must be optional,
        // or the whole file fails to decode and MacAmp would start (and then save) with default settings
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as! [String: Any]
        for key in old.keys where key.hasSuffix("Storage") || ["skinsDirectoryPath"].contains(key) { old.removeValue(forKey: key) }
        old["isShuffle"] = true
        let decoded = try? JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: old))
        assertTrue(decoded != nil, "A session without the new settings decodes")
        assertEqual(decoded?.isShuffle, true, "and keeps the user's settings")
        assertEqual(decoded?.interfaceScale, .standard, "Older sessions open at 100%")
        // Settings that must be present in every session.json: frozen at 1.0. A new setting needs the
        // `...Storage: T?` pattern, or old sessions stop loading (this list then no longer matches)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as! [String: Any]
        let required = Set(encoded.keys.filter { !$0.hasSuffix("Storage") && $0 != "skinsDirectoryPath" })
        let frozen: Set<String> = ["audioFadeOutDurationMs", "authenticShuffle", "autoGenreEQ", "balance", "desktopFontFamily", "desktopFontSize",
            "dspPitchSemitones", "dspPlaybackRate", "dspReverbMix", "dspReverbPreset", "eqBandsDb", "isAlwaysOnTop", "isDspEnabled", "isEqAuto",
            "isEqEnabled", "isEqWindowShade", "isEqWindowVisible", "isGlobalHotkeysEnabled", "isMainWindowShade", "isMarqueeScrollEnabled",
            "isPlaylistShade", "isPlaylistVisible", "isRepeat", "isShuffle", "lastPlaybackState", "lastPlayedTrackTime", "marqueeFontMode",
            "playlistShowExtensions", "playlistWindowSize", "playlistZeroPadding", "preampDb", "scaleFactor", "showNumbersInPlaylist",
            "showTrackNumberInTitle", "timeDisplayMode", "visualizerMode", "visualizerShowPeaks", "volume", "windowPositions", "windowSnapDistance"]
        assertEqual(required.subtracting(frozen).sorted(), [], "New settings are optional (`...Storage: T?`)")
        // And a session with only those keys loads
        let minimal = encoded.filter { frozen.contains($0.key) }
        assertTrue((try? JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: minimal))) != nil, "A 1.0 session.json loads")
    }

    testGroup("File types: Associate with audio CDs") {
        assertTrue(!AppState().playInsertedAudioCDs, "Off by default: inserting a CD doesn't start MacAmp playback")
        // A volume that isn't an audio CD is ignored even with the option on
        let before = PlayerCoordinator.shared.playlist.tracks.count
        PersistenceManager.shared.state.playInsertedAudioCDs = true
        PlayerCoordinator.shared.audioCDMounted(FileManager.default.temporaryDirectory)
        PersistenceManager.shared.state.playInsertedAudioCDs = false
        assertEqual(PlayerCoordinator.shared.playlist.tracks.count, before, "Data volumes don't touch the playlist")
    }
}
