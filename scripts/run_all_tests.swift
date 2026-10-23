import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
@testable import MacAmp

/// Test groups run on the main thread, where the app's UI and coordinator live.
func testGroup(_ name: String, _ block: @MainActor () throws -> Void) {
    print("\n📦 Test Suite: \(name)")
    do {
        try MainActor.assumeIsolated { try block() }
        print("  ✅ All tests in '\(name)' passed successfully.")
    } catch {
        print("  ❌ Test suite '\(name)' FAILED: \(error)")
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("    ❌ Assertion Failed: \(message) [\(file):\(line)]")
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        print("    ❌ Assertion Failed: Expected [\(expected)], got [\(actual)]. \(message) [\(file):\(line)]")
        exit(1)
    }
}

// Safety: tests write session.json / playlist.json via PersistenceManager. Refuse to run against the real home.
guard let testHome = ProcessInfo.processInfo.environment["MACAMP_TEST_HOME"],
      NSHomeDirectory() == testHome else {
    print("❌ Refusing to run: start the tests via ./build.sh test (isolated CFFIXED_USER_HOME), not directly.")
    exit(2)
}

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("⚡ MacAmp Test Runner — Phase 2 Verification Suite")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

// 1. WindowLayoutManager & Magnetic Snapping Tests
testGroup("WindowLayoutManager & Magnetic Snapping") {
    let wlm = WindowLayoutManager.shared
    assertEqual(wlm.currentScale, 1.0, "Scale factor should default to 1.0")
    
    // Create test mock windows
    let winA = NSWindow(contentRect: NSRect(x: 100, y: 500, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
    let winB = NSWindow(contentRect: NSRect(x: 100, y: 384, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
    let winC = NSWindow(contentRect: NSRect(x: 100, y: 268, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
    
    wlm.register(window: winA, for: .main)
    wlm.register(window: winB, for: .equalizer)
    wlm.register(window: winC, for: .playlist)
    
    // When visible, winA and winB touch vertically (winA.minY == 500, winB.maxY == 500)
    winA.orderFront(nil)
    winB.orderFront(nil)
    winC.orderFront(nil)
    
    wlm.updateAdjacencies()
    let dragOrigins = wlm.startDrag(for: .main)
    assertTrue(dragOrigins.keys.contains(.main), "Group should contain main window")
    assertTrue(dragOrigins.keys.contains(.equalizer), "Group should contain docked equalizer window")
    assertTrue(dragOrigins.keys.contains(.playlist), "Group should contain docked playlist window")
    
    // Now test that hidden windows are NOT included in group or adjacencies
    winB.orderOut(nil)
    wlm.updateAdjacencies()
    let dragWithoutEQ = wlm.startDrag(for: .main)
    assertTrue(!dragWithoutEQ.keys.contains(.equalizer), "Hidden equalizer window must NOT participate in drag group")
    
    // Test applyDrag moving windows with rounded delta
    winB.orderFront(nil)
    let initialMainOrigin = winA.frame.origin
    let origins = wlm.startDrag(for: .main)
    wlm.applyDrag(id: .main, totalDelta: CGPoint(x: 20, y: -20), startOrigins: origins)
    let movedMainOrigin = winA.frame.origin
    assertTrue(movedMainOrigin.x > initialMainOrigin.x, "Main window should move with drag delta")
    
    // Restore window positions
    winA.setFrameOrigin(NSPoint(x: 100, y: 500))
    winB.setFrameOrigin(NSPoint(x: 100, y: 384))
    winC.setFrameOrigin(NSPoint(x: 100, y: 268))
    wlm.updateAdjacencies()
    
    // Test findWindowsBelow
    let below = wlm.findWindowsBelow(id: .main)
    assertTrue(below.contains(.equalizer), "Equalizer should be found below Main window")
    assertTrue(below.contains(.playlist), "Playlist should be found below Equalizer window")
    
    // Test Scaling with Inverted Window Layout: Playlist TOP, Equalizer MIDDLE, Main BOTTOM
    // In 1x: Main at y=100 (height 116 -> maxY=216), EQ at y=216 (maxY=332), Playlist at y=332 (maxY=448)
    winA.setFrame(NSRect(x: 100, y: 100, width: 275, height: 116), display: false)
    winB.setFrame(NSRect(x: 100, y: 216, width: 275, height: 116), display: false)
    winC.setFrame(NSRect(x: 100, y: 332, width: 275, height: 116), display: false)
    winA.orderFront(nil)
    winB.orderFront(nil)
    winC.orderFront(nil)
    wlm.updateAdjacencies()
    
    // Scale 1x -> 2x
    wlm.setScale(2.0)
    assertEqual(wlm.currentScale, 2.0, "Scale factor should be 2.0")
    
    let main2x = winA.frame
    let eq2x = winB.frame
    let pl2x = winC.frame
    assertTrue(abs(eq2x.minY - main2x.maxY) <= 1.0, "At 2x: EQ bottom must touch Main top with 0 gap")
    assertTrue(abs(pl2x.minY - eq2x.maxY) <= 1.0, "At 2x: Playlist bottom must touch EQ top with 0 gap (no gap/flying up)")
    
    // Scale 2x -> 1x
    wlm.setScale(1.0)
    assertEqual(wlm.currentScale, 1.0, "Scale factor should be 1.0")
    
    let main1x = winA.frame
    let eq1x = winB.frame
    let pl1x = winC.frame
    assertTrue(abs(eq1x.minY - main1x.maxY) <= 1.0, "At 1x: EQ bottom must touch Main top with 0 gap")
    assertTrue(abs(pl1x.minY - eq1x.maxY) <= 1.0, "At 1x: Playlist bottom must touch EQ top with 0 gap (no overlap)")
    
    // Test onLayoutChanged callback trigger
    var layoutChangedFired = false
    wlm.onLayoutChanged = {
        layoutChangedFired = true
    }
    wlm.endDrag(for: .main)
    assertTrue(layoutChangedFired, "onLayoutChanged must be triggered when dragging ends")
}

// 2. Window Position & Layout Persistence Tests
testGroup("Window Position & Layout Persistence") {
    let persistence = PersistenceManager.shared
    
    // Simulate user arranging windows in inverted layout: Playlist (top), EQ (middle), Main (bottom)
    let pFrame = NSRect(x: 350, y: 600, width: 275, height: 116)
    let eFrame = NSRect(x: 350, y: 484, width: 275, height: 116)
    let mFrame = NSRect(x: 350, y: 368, width: 275, height: 116)
    
    persistence.state.windowPositions["playlist"] = [Double(pFrame.minX), Double(pFrame.minY), Double(pFrame.width), Double(pFrame.height)]
    persistence.state.windowPositions["equalizer"] = [Double(eFrame.minX), Double(eFrame.minY), Double(eFrame.width), Double(eFrame.height)]
    persistence.state.windowPositions["main"] = [Double(mFrame.minX), Double(mFrame.minY), Double(mFrame.width), Double(mFrame.height)]
    persistence.state.scaleFactor = .x1
    persistence.state.isMainWindowShade = false
    persistence.state.isEqWindowShade = false
    persistence.state.isPlaylistShade = false
    persistence.state.isEqWindowVisible = true
    persistence.state.isPlaylistVisible = true
    persistence.state.isEqAuto = true
    persistence.state.autoGenreEQ = true
    persistence.saveSession()
    
    // Simulate relaunch by reading back the session state
    persistence.loadSession()
    assertTrue(persistence.state.isEqAuto, "isEqAuto must be persisted across sessions")
    assertTrue(persistence.state.autoGenreEQ, "autoGenreEQ must be persisted across sessions")
    let loaded = persistence.state.windowPositions
    assertTrue(loaded["playlist"] != nil, "Playlist position must be persisted")
    assertTrue(loaded["equalizer"] != nil, "Equalizer position must be persisted")
    assertTrue(loaded["main"] != nil, "Main window position must be persisted")
    
    let loadedP = loaded["playlist"]!
    let loadedE = loaded["equalizer"]!
    let loadedM = loaded["main"]!
    
    assertEqual(loadedP[0], 350.0, "Playlist X coordinate restored accurately")
    assertEqual(loadedP[1], 600.0, "Playlist Y coordinate restored accurately (top)")
    assertEqual(loadedE[0], 350.0, "Equalizer X coordinate restored accurately")
    assertEqual(loadedE[1], 484.0, "Equalizer Y coordinate restored accurately (middle)")
    assertEqual(loadedM[0], 350.0, "Main X coordinate restored accurately")
    assertEqual(loadedM[1], 368.0, "Main Y coordinate restored accurately (bottom)")
    
    // Verify vertical order: Playlist > Equalizer > Main
    assertTrue(loadedP[1] > loadedE[1], "Playlist must be positioned above Equalizer")
    assertTrue(loadedE[1] > loadedM[1], "Equalizer must be positioned above Main window")
    
    // Test that adjacency graph correctly identifies docking when windows are restored at these coordinates
    let wlm = WindowLayoutManager.shared
    let winA = NSWindow(contentRect: NSRect(x: loadedM[0], y: loadedM[1], width: loadedM[2], height: loadedM[3]), styleMask: .borderless, backing: .buffered, defer: false)
    let winB = NSWindow(contentRect: NSRect(x: loadedE[0], y: loadedE[1], width: loadedE[2], height: loadedE[3]), styleMask: .borderless, backing: .buffered, defer: false)
    let winC = NSWindow(contentRect: NSRect(x: loadedP[0], y: loadedP[1], width: loadedP[2], height: loadedP[3]), styleMask: .borderless, backing: .buffered, defer: false)
    
    wlm.register(window: winA, for: .main)
    wlm.register(window: winB, for: .equalizer)
    wlm.register(window: winC, for: .playlist)
    winA.orderFront(nil)
    winB.orderFront(nil)
    winC.orderFront(nil)
    wlm.updateAdjacencies()
    
    let group = wlm.findGroup(for: .main)
    assertTrue(group.contains(.main), "Restored group contains Main")
    assertTrue(group.contains(.equalizer), "Restored group contains Equalizer")
    assertTrue(group.contains(.playlist), "Restored group contains Playlist")
}

// 2b. Multi-Monitor Safety & Display Disconnect/Reconnect Tests
testGroup("Multi-Monitor Safety & Display Disconnect/Reconnect") {
    let wlm = WindowLayoutManager.shared
    
    // 1. isRectVisibleOnAnyScreen tests
    let offscreenRect = NSRect(x: 99999, y: 99999, width: 275, height: 116)
    assertTrue(!wlm.isRectVisibleOnAnyScreen(offscreenRect), "Offscreen rect must NOT be reported as visible")
    
    if let screen = NSScreen.main {
        let onscreenRect = NSRect(x: screen.visibleFrame.midX - 100, y: screen.visibleFrame.midY - 50, width: 200, height: 100)
        assertTrue(wlm.isRectVisibleOnAnyScreen(onscreenRect), "Onscreen rect inside visibleFrame must be reported as visible")
    }
    
    // 2. Simulate windows on a disconnected secondary monitor
    let offX: CGFloat = 88000
    let offY: CGFloat = 88000
    let winM = NSWindow(contentRect: NSRect(x: offX, y: offY + 116, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
    let winE = NSWindow(contentRect: NSRect(x: offX, y: offY, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
    
    wlm.register(window: winM, for: .main)
    wlm.register(window: winE, for: .equalizer)
    winM.orderFront(nil)
    winE.orderFront(nil)
    wlm.updateAdjacencies()
    
    // 3. Screen parameters changed (monitor disconnect)
    wlm.handleScreenParametersChanged()
    
    // Verify savedExternalPositions was recorded
    assertTrue(wlm.savedExternalPositions != nil, "savedExternalPositions must be populated when windows were on a disconnected screen")
    assertEqual(wlm.savedExternalPositions?[.main]?.x, offX, "Saved external X matches original offscreen coordinate")
    assertEqual(wlm.savedExternalPositions?[.main]?.y, offY + 116, "Saved external Y matches original offscreen coordinate")
    
    // Verify windows were relocated onto the visible screen
    assertTrue(wlm.isRectVisibleOnAnyScreen(winM.frame), "Main window must now be visible on an active screen")
    assertTrue(wlm.isRectVisibleOnAnyScreen(winE.frame), "Equalizer window must now be visible on an active screen")
    
    // Verify relative docking offset is preserved
    let deltaY = round(winM.frame.minY - winE.frame.maxY)
    assertEqual(deltaY, 0.0, "Docked windows must preserve adjacency on relocation")
    assertEqual(winM.frame.minX, winE.frame.minX, "Docked windows must preserve X alignment on relocation")
    
    // 4. Manual drag should cancel pending external restore
    _ = wlm.startDrag(for: .main)
    assertTrue(wlm.hasUserMovedWindowsSinceRelocation, "User manual drag marks windows as moved")
    assertTrue(wlm.savedExternalPositions == nil, "User manual drag clears saved external positions")
}

// 3. ICY Streaming & Metadata Parsing Tests
testGroup("ICY Streaming & Metadata Parser") {
    let dummyURL = URL(string: "http://streaming.somafm.com:80/groovesalad-128-mp3")!
    let session = ICYStreamSession(url: dummyURL)
    
    var receivedArtist: String?
    var receivedTitle: String?
    var receivedBitrate: Int?
    
    session.onMetadataUpdate = { artist, title, bitrate, _ in
        receivedArtist = artist
        receivedTitle = title
        receivedBitrate = bitrate
    }
    
    // Simulate ICY HTTP headers via testing hook
    let headers: [AnyHashable: Any] = [
        "icy-name": "Groove Salad: a nicely chilled plate of ambient beats",
        "icy-genre": "Ambient",
        "icy-url": "http://somafm.com",
        "icy-br": "128",
        "icy-metaint": "8192"
    ]
    session.feedHeadersForTesting(headers)
    
    assertEqual(session.metaInt, 8192, "ICY metaInt header should be parsed as 8192")
    assertEqual(session.stationName, "Groove Salad: a nicely chilled plate of ambient beats", "Stream name parsed")
    assertEqual(session.genre, "Ambient", "Stream genre parsed")
    assertEqual(session.bitrate, 128, "Bitrate parsed as 128 kbps")
    
    // Simulate audio data chunk + ICY metadata block
    // 8192 bytes of audio data
    let dummyAudio = Data(count: 8192)
    session.feedDataForTesting(dummyAudio)
    
    // Next byte is metadata length byte: 3 (3 * 16 = 48 bytes)
    let metaPayload = "StreamTitle='Carbon Based Lifeforms - MOS 6581';\0\0"
    var metaData = Data()
    let lenByte: UInt8 = UInt8((metaPayload.utf8.count + 15) / 16)
    metaData.append(lenByte)
    metaData.append(metaPayload.data(using: .utf8)!)
    let paddingNeeded = Int(lenByte) * 16 - metaPayload.utf8.count
    if paddingNeeded > 0 {
        metaData.append(Data(count: paddingNeeded))
    }
    
    session.feedDataForTesting(metaData)
    
    // Wait for the async metadata callback (a fixed 0.05 s was flaky on a busy machine)
    _ = spinRunLoop(until: { receivedArtist != nil && receivedTitle != nil }, timeout: 3)
    
    assertEqual(session.currentStreamTitle, "Carbon Based Lifeforms - MOS 6581", "StreamTitle should be extracted")
    assertTrue(receivedArtist != nil, "Artist metadata update received")
    assertTrue(receivedTitle != nil, "Title metadata update received")
    assertEqual(receivedBitrate, 128, "Bitrate metadata update received")
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

// 4. AudioEngine DSP Effects Tests
testGroup("AudioEngine DSP Effects (Pitch, Rate, Reverb)") {
    let engine = AudioEngine.shared
    
    // Semitones to cents conversion
    engine.setPitchSemitones(6.0)
    assertEqual(engine.currentPitchSemitones, 6.0, "Pitch shift: 6 semitones (+600 cents)")
    
    engine.setPitchSemitones(-12.0)
    assertEqual(engine.currentPitchSemitones, -12.0, "Pitch shift: -12 semitones (-1200 cents)")
    
    // Playback rate clamping [0.5 ... 2.0]
    engine.setPlaybackRate(1.5)
    assertEqual(engine.currentPlaybackRate, 1.5, "Playback rate should be 1.5x")
    
    engine.setPlaybackRate(0.2) // below min
    assertEqual(engine.currentPlaybackRate, 0.5, "Playback rate should clamp to min 0.5x")
    
    engine.setPlaybackRate(3.0) // above max
    assertEqual(engine.currentPlaybackRate, 2.0, "Playback rate should clamp to max 2.0x")
    
    // Reverb wet/dry mix [0.0 ... 100.0]
    engine.setReverbMix(45.0)
    assertEqual(engine.currentReverbMix, 45.0, "Reverb mix should be 45%")
    
    engine.setReverbMix(0.0)
    assertEqual(engine.currentReverbMix, 0.0, "Reverb mix should be 0%")
    
    // Factory presets test
    for i in 0..<7 {
        engine.setReverbPreset(index: i)
    }
    
    // Reset DSP
    engine.resetDSP()
    assertEqual(engine.currentPitchSemitones, 0.0, "Reset DSP: Pitch should be 0")
    assertEqual(engine.currentPlaybackRate, 1.0, "Reset DSP: Rate should be 1.0")
    assertEqual(engine.currentReverbMix, 0.0, "Reset DSP: Reverb mix should be 0")
    assertTrue(engine.isDspTimePitchBypassed, "Reset DSP: timePitchNode should be bypassed")
}

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

// 6. Retro Visualizer Studio Mode & Presets Tests
testGroup("Retro Visualizer Studio & Presets") {
    let presets = StudioVisualizerPreset.allCases
    assertEqual(presets.count, 5, "Studio should have exactly 5 retro presets")
    assertEqual(presets[0].title, "Fire Spectrum & Peak Glow", "Preset 0 title matches")
    assertEqual(presets[1].title, "Retro Phosphor CRT Oscilloscope", "Preset 1 title matches")
    assertEqual(presets[2].title, "Neon Cyber City Spectrum", "Preset 2 title matches")
    assertEqual(presets[3].title, "Matrix Digital Rain", "Preset 3 title matches")
    assertEqual(presets[4].title, "Solar Radial Orb", "Preset 4 title matches")
    
    // Dockable Winamp windows: main, equalizer, playlist and the Media Library
    let windowIDs = WindowID.allCases
    assertEqual(windowIDs, [.main, .equalizer, .playlist, .library, .video, .browser], "Dockable windows")
    assertTrue(WindowID.library.keepsOwnSize && WindowID.playlist.keepsOwnSize && !WindowID.main.keepsOwnSize,
               "Playlist and Library keep their size in Double Size mode, like Winamp")
    assertTrue(windowIDs.contains(.main), "WindowID contains .main")
    assertTrue(windowIDs.contains(.equalizer), "WindowID contains .equalizer")
    assertTrue(windowIDs.contains(.playlist), "WindowID contains .playlist")
}

// 7. Playback State & Position Persistence Tests
testGroup("Playback State & Position Persistence") {
    var state = AppState()
    state.lastPlaybackState = .paused
    state.lastPlayedTrackTime = 42.5
    state.lastPlayedTrackIndex = 2
    state.lastPlayedTrackURL = "file:///test/track.mp3"
    
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    let encoded = try encoder.encode(state)
    let decoded = try decoder.decode(AppState.self, from: encoded)
    
    assertEqual(decoded.lastPlaybackState, .paused, "lastPlaybackState should be .paused")
    assertEqual(decoded.lastPlayedTrackTime, 42.5, "lastPlayedTrackTime should match")
    assertEqual(decoded.lastPlayedTrackIndex, 2, "lastPlayedTrackIndex should match")
    assertEqual(decoded.lastPlayedTrackURL, "file:///test/track.mp3", "lastPlayedTrackURL should match")
    
    // Test AudioEngine preparePaused logic (status & currentTime)
    let engine = AudioEngine.shared
    engine.preparePaused(at: 15.0)
    // Note: without a loaded audio file, fileDuration is 0 so clamped time is 0, but status transitions to .paused
    assertEqual(engine.status, .paused, "AudioEngine should be in .paused state after preparePaused")
    
    engine.stop()
    assertEqual(engine.status, .stopped, "AudioEngine should be stopped after stop()")
    assertEqual(engine.currentTime, 0.0, "AudioEngine currentTime should be 0 after stop()")
}

// 8. ClutterBar (O, A, I, D, V) Controls Tests
testGroup("ClutterBar 100% (O, A, I, D, V) Controls") {
    typealias Layout = AppConstants.MainWindow.Layout
    
    // 1. Verify layout geometry
    assertEqual(Layout.clutterBarBg, NSRect(x: 10, y: 22, width: 8, height: 43), "clutterBarBg rect")
    assertEqual(Layout.clutterOptionsButton, NSRect(x: 10, y: 25, width: 8, height: 8), "clutterOptionsButton rect")
    assertEqual(Layout.clutterAlwaysOnTopButton, NSRect(x: 10, y: 33, width: 8, height: 7), "clutterAlwaysOnTopButton rect")
    assertEqual(Layout.clutterFileInfoButton, NSRect(x: 10, y: 40, width: 8, height: 7), "clutterFileInfoButton rect")
    assertEqual(Layout.clutterDoubleSizeButton, NSRect(x: 10, y: 47, width: 8, height: 8), "clutterDoubleSizeButton rect")
    assertEqual(Layout.clutterVisualizerButton, NSRect(x: 10, y: 55, width: 8, height: 7), "clutterVisualizerButton rect")
    
    // 2. Verify MainWindowView subviews & initial states
    let mainView = MainWindowView()
    assertTrue(mainView.clutterOptionsButton != nil, "clutterOptionsButton exists")
    assertTrue(mainView.alwaysOnTopButton != nil, "alwaysOnTopButton exists")
    assertTrue(mainView.clutterFileInfoButton != nil, "clutterFileInfoButton exists")
    assertTrue(mainView.doubleSizeButton != nil, "doubleSizeButton exists")
    assertTrue(mainView.clutterVisualizerButton != nil, "clutterVisualizerButton exists")
    
    // Normal mode: all 5 are visible
    assertTrue(!mainView.clutterOptionsButton.isHidden, "Options visible in normal mode")
    assertTrue(!mainView.alwaysOnTopButton.isHidden, "AlwaysOnTop visible in normal mode")
    assertTrue(!mainView.clutterFileInfoButton.isHidden, "FileInfo visible in normal mode")
    assertTrue(!mainView.doubleSizeButton.isHidden, "DoubleSize visible in normal mode")
    assertTrue(!mainView.clutterVisualizerButton.isHidden, "Visualizer button visible in normal mode")
    
    // Shade mode: all 5 must be hidden
    mainView.isShadeMode = true
    assertTrue(mainView.clutterOptionsButton.isHidden, "Options hidden in shade mode")
    assertTrue(mainView.alwaysOnTopButton.isHidden, "AlwaysOnTop hidden in shade mode")
    assertTrue(mainView.clutterFileInfoButton.isHidden, "FileInfo hidden in shade mode")
    assertTrue(mainView.doubleSizeButton.isHidden, "DoubleSize hidden in shade mode")
    assertTrue(mainView.clutterVisualizerButton.isHidden, "Visualizer button hidden in shade mode")
    
    // 3. Test Visualizer Mode Cycling
    mainView.visualizer.mode = .spectrum
    assertEqual(mainView.visualizer.mode.next, .oscilloscope, "Spectrum -> Oscilloscope")
    assertEqual(VisualizerMode.oscilloscope.next, .off, "Oscilloscope -> Off")
    assertEqual(VisualizerMode.off.next, .spectrum, "Off -> Spectrum")
}

// 9. AudioDeviceManager & Output Hotplugging Tests
testGroup("AudioDeviceManager & Output Hotplugging") {
    let mgr = AudioDeviceManager.shared
    mgr.refreshDevices()
    
    // 1. Devices list & default device detection
    assertTrue(!mgr.availableDevices.isEmpty, "Should find at least 1 output device on macOS")
    assertTrue(mgr.defaultDevice != nil, "Default output device should be detected")
    
    // 2. Transport type mapping
    assertEqual(AudioDeviceTransportType.from(rawTransport: 1651274862), .builtIn, "'bltn' should map to .builtIn")
    assertEqual(AudioDeviceTransportType.from(rawTransport: 1651275109), .bluetooth, "'blue' should map to .bluetooth")
    assertEqual(AudioDeviceTransportType.from(rawTransport: 1651271009), .bluetooth, "'blea' should map to .bluetooth")
    assertEqual(AudioDeviceTransportType.from(rawTransport: 1751412073), .hdmi, "'hdmi' should map to .hdmi")
    assertEqual(AudioDeviceTransportType.from(rawTransport: 1685090932), .hdmi, "'dprt' should map to .hdmi")
    assertEqual(AudioDeviceTransportType.from(rawTransport: 1970496032), .usb, "'usb ' should map to .usb")
    assertEqual(AudioDeviceTransportType.from(rawTransport: 1634300528), .airplay, "'airp' should map to .airplay")
    assertEqual(AudioDeviceTransportType.from(rawTransport: 1986622068), .virtual, "'virt' should map to .virtual")
    
    // 3. Selection & persistence
    mgr.selectDevice(uid: nil)
    assertEqual(mgr.selectedDeviceUID, nil, "System Default selected (nil UID)")
    assertEqual(PersistenceManager.shared.state.selectedAudioOutputDeviceUID, nil, "Persistence reflects System Default")
    assertEqual(mgr.activeDevice?.id, mgr.defaultDevice?.id, "Active device matches default device")
    
    if let first = mgr.availableDevices.first {
        mgr.selectDevice(uid: first.uid)
        assertEqual(mgr.selectedDeviceUID, first.uid, "Selected device UID matches")
        assertEqual(PersistenceManager.shared.state.selectedAudioOutputDeviceUID, first.uid, "Persistence updated with chosen UID")
        assertEqual(mgr.activeDevice?.uid, first.uid, "Active device reflects selected device")
        
        // Reset back to default
        mgr.selectDevice(uid: nil)
        assertEqual(mgr.selectedDeviceUID, nil, "Reset back to nil")
    }
    
    // 4. AudioEngine routing & route change resilience
    let engine = AudioEngine.shared
    let success = engine.setOutputDevice(deviceID: nil)
    assertTrue(success, "AudioEngine setOutputDevice(nil) should succeed")
    
    // Post route change notification to verify resilience
    NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
    assertEqual(engine.status, .stopped, "Engine remains in valid stopped state after route notification")
    
    // 5. Preferences View Model & Tree Item integration
    assertTrue(PrefTreeItem.allCases.contains(.output), "PrefTreeItem should include .output")
    assertEqual(PrefTreeItem.output.parent, .plugins, "Output devices live under Plug-ins ▸ Output")
    
    let vm = PreferencesViewModel()
    vm.selectedTreeItem = .output
    assertTrue(!vm.availableOutputDevices.isEmpty, "PreferencesViewModel should populate available devices")
    vm.selectOutputDevice(uid: nil)
    assertEqual(vm.selectedAudioOutputDeviceUID, nil, "PreferencesViewModel selects System Default")
}


// MARK: - Playback regression helpers
/// Runs async work on the main actor and waits for its result, pumping the run loop meanwhile.
@MainActor
func awaitValue<T>(_ work: @escaping @MainActor () async -> T) -> T {
    var result: T?
    Task { @MainActor in result = await work() }
    _ = spinRunLoop(until: { result != nil }, timeout: 30)
    return result!
}

func spinRunLoop(until condition: () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

func makeTestWAV(named name: String, seconds: Double) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let frames = AVAudioFrameCount(seconds * 44100)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for ch in 0..<Int(format.channelCount) {
        let data = buffer.floatChannelData![ch]
        for i in 0..<Int(frames) { data[i] = 0.001 * sinf(Float(i) * 0.05) } // near-silent tone
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

func loadSync(_ engine: AudioEngine, _ url: URL) throws -> TrackMetadata {
    var result: Result<TrackMetadata, Error>?
    Task { @MainActor in
        do { result = .success(try await engine.load(url: url)) } catch { result = .failure(error) }
    }
    guard spinRunLoop(until: { result != nil }, timeout: 5) else { throw NSError(domain: "test", code: 1) }
    return try result!.get()
}

// 12. Playback regressions: pause/resume auto-advance, track change from pause, stale loads
testGroup("Playback Regressions (Pause/Resume, Track Change, Stale Loads)") {
    let engine = AudioEngine.shared
    let savedFinished = engine.onPlaybackFinished
    defer { engine.onPlaybackFinished = savedFinished; engine.stop() }
    
    // Earlier groups may leave the engine routed to a non-output device; route back to the system default
    AudioDeviceManager.shared.selectDevice(uid: nil)
    engine.setOutputDevice(deviceID: AudioDeviceManager.shared.defaultDevice?.id)
    _ = spinRunLoop(until: { false }, timeout: 0.3)
    
    let shortURL = try makeTestWAV(named: "short.wav", seconds: 0.6)
    let longURL = try makeTestWAV(named: "long.wav", seconds: 6.0)
    
    // Bug 1: after pause -> resume, reaching the end of the track must still fire onPlaybackFinished
    var finishedCount = 0
    engine.onPlaybackFinished = { finishedCount += 1 }
    _ = try loadSync(engine, shortURL)
    engine.play()
    assertEqual(engine.status, .playing, "Engine plays short track")
    _ = spinRunLoop(until: { false }, timeout: 0.15)
    engine.pause()
    assertEqual(engine.status, .paused, "Engine pauses")
    _ = spinRunLoop(until: { false }, timeout: 0.1)
    engine.play()
    assertEqual(engine.status, .playing, "Engine resumes from pause")
    assertTrue(spinRunLoop(until: { finishedCount == 1 }, timeout: 3), "Track end after pause/resume must trigger onPlaybackFinished")
    assertEqual(engine.status, .stopped, "Engine is stopped after the track finished")
    
    // Bug 2: loading a new track while paused must discard the paused segment of the old file
    finishedCount = 0
    _ = try loadSync(engine, longURL)
    engine.play()
    _ = spinRunLoop(until: { false }, timeout: 0.15)
    engine.pause()
    assertEqual(engine.status, .paused, "Long track paused")
    let shortMeta = try loadSync(engine, shortURL)
    assertEqual(engine.status, .stopped, "load() must end the previously paused track")
    assertEqual(engine.currentMetadata?.url, shortURL, "Metadata belongs to the newly loaded track")
    engine.play()
    assertTrue(engine.currentTime < 0.5, "New track starts from the beginning, not from the old paused position")
    // The 0.6s track must finish well before the 6s old track would have
    assertTrue(spinRunLoop(until: { finishedCount == 1 }, timeout: 2.5), "Newly loaded track (not the old paused one) plays and finishes")
    assertTrue(shortMeta.duration < 1.0, "Short track duration is reported")
    
    // Stale concurrent loads: the superseded load must throw CancellationError, the latest one wins
    var firstResult: Result<TrackMetadata, Error>?
    var secondResult: Result<TrackMetadata, Error>?
    Task { @MainActor in
        do { firstResult = .success(try await engine.load(url: longURL)) } catch { firstResult = .failure(error) }
    }
    Task { @MainActor in
        do { secondResult = .success(try await engine.load(url: shortURL)) } catch { secondResult = .failure(error) }
    }
    assertTrue(spinRunLoop(until: { firstResult != nil && secondResult != nil }, timeout: 5), "Both loads complete")
    if case .failure(let err) = firstResult! {
        assertTrue(err is CancellationError, "Superseded load fails with CancellationError, got \(err)")
    } else {
        assertTrue(false, "Superseded load must not succeed")
    }
    assertEqual(engine.currentMetadata?.url, shortURL, "Latest load wins")
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

// 16. Fade-out / fade-in (§4)
testGroup("Audio Fade-Out / Fade-In") {
    let engine = AudioEngine.shared
    let persistence = PersistenceManager.shared
    let savedFade = persistence.state.audioFadeOutDurationMs
    let savedFinished = engine.onPlaybackFinished
    defer {
        persistence.state.audioFadeOutDurationMs = savedFade
        engine.onPlaybackFinished = savedFinished
        engine.stop()
    }
    persistence.state.audioFadeOutDurationMs = 200
    let longURL = try makeTestWAV(named: "fade-long.wav", seconds: 6.0)
    
    _ = try loadSync(engine, longURL)
    engine.play()
    assertTrue(spinRunLoop(until: { engine.fadeGain >= 0.999 }, timeout: 0.5), "Play fades in to full gain quickly (anti-click)")
    _ = spinRunLoop(until: { false }, timeout: 0.3)
    
    engine.pause()
    assertEqual(engine.status, .paused, "Pause takes effect immediately for the UI")
    _ = spinRunLoop(until: { false }, timeout: 0.08)
    assertTrue(engine.fadeGain > 0.05 && engine.fadeGain < 0.999, "Gain is mid-fade 80ms into a 200ms fade-out (got \(engine.fadeGain))")
    assertTrue(spinRunLoop(until: { engine.fadeGain <= 0.0001 }, timeout: 0.5), "Fade-out reaches silence")
    _ = spinRunLoop(until: { false }, timeout: 0.05)
    let pausedAt = engine.currentTime
    _ = spinRunLoop(until: { false }, timeout: 0.3)
    assertEqual(engine.currentTime, pausedAt, "Position is frozen once the fade-out finished")
    
    engine.play()
    assertEqual(engine.status, .playing, "Resume after fade")
    assertTrue(spinRunLoop(until: { engine.fadeGain >= 0.999 }, timeout: 0.5), "Resume fades back in")
    assertTrue(spinRunLoop(until: { engine.currentTime > pausedAt + 0.1 }, timeout: 1.0), "Playback continues from the paused position")
    
    // Pause and resume within the fade window: playback simply continues
    engine.pause()
    _ = spinRunLoop(until: { false }, timeout: 0.05)
    engine.play()
    let t0 = engine.currentTime
    assertTrue(spinRunLoop(until: { engine.currentTime > t0 + 0.2 }, timeout: 1.0), "Resume during fade-out keeps playing")
    
    engine.stop()
    assertEqual(engine.status, .stopped, "Stop takes effect immediately for the UI")
    assertTrue(spinRunLoop(until: { engine.fadeGain <= 0.0001 }, timeout: 0.5), "Stop fades out")
    
    // Track ends during the pause fade-out: resume must advance to the next track instead of hanging
    var finished = 0
    engine.onPlaybackFinished = { finished += 1 }
    let shortURL = try makeTestWAV(named: "fade-short.wav", seconds: 0.5)
    _ = try loadSync(engine, shortURL)
    engine.play()
    _ = spinRunLoop(until: { engine.currentTime >= 0.4 }, timeout: 1.0)
    engine.pause()
    _ = spinRunLoop(until: { false }, timeout: 0.35)
    assertEqual(finished, 0, "No auto-advance while paused")
    engine.play()
    assertTrue(spinRunLoop(until: { finished == 1 }, timeout: 1.0), "Resuming a track that ended during the fade advances to the next one")
    
    // Fade disabled: pause is immediate
    persistence.state.audioFadeOutDurationMs = 0
    _ = try loadSync(engine, longURL)
    engine.play()
    _ = spinRunLoop(until: { false }, timeout: 0.1)
    engine.pause()
    assertTrue(engine.fadeGain <= 0.0001, "With 0 ms fade the pause is immediate")
}

// 17. Resource usage gating (§1)
testGroup("CPU Gating: Visualizer Tap, Marquee Timer, Analyzer") {
    let engine = AudioEngine.shared
    defer { engine.stop(); engine.isAnalysisEnabled = true }
    let url = try makeTestWAV(named: "gating.wav", seconds: 4.0)
    
    engine.isAnalysisEnabled = true
    _ = try loadSync(engine, url)
    assertTrue(!engine.isAnalysisTapInstalled, "No FFT tap while stopped")
    engine.play()
    assertTrue(engine.isAnalysisTapInstalled, "FFT tap installed while playing with the visualizer visible")
    var frames = 0
    engine.onVisualizerFrame = { _ in frames += 1 }
    _ = spinRunLoop(until: { false }, timeout: 0.5)
    assertTrue(frames >= 13 && frames <= 32, "Visualizer runs at ~30-60 fps (got \(frames) frames in 0.5s)")
    engine.isAnalysisEnabled = false
    assertTrue(!engine.isAnalysisTapInstalled, "Hidden/minimized windows remove the FFT tap")
    engine.isAnalysisEnabled = true
    assertTrue(engine.isAnalysisTapInstalled, "Tap returns when the visualizer is visible again")
    engine.pause()
    assertTrue(!engine.isAnalysisTapInstalled, "No FFT tap while paused")
    engine.onVisualizerFrame = nil
    
    // Analyzer: silence is detected without an FFT, and output arrays are reused
    let analyzer = FFTAnalyzer()
    let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let silent = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1024)!
    silent.frameLength = 1024
    var spectrum = [Float](repeating: 1, count: AppConstants.Visualizer.numSpectrumBars)
    var waveform = [Float](repeating: 1, count: AppConstants.Visualizer.numWaveformPoints)
    assertTrue(!analyzer.analyze(buffer: silent, spectrum: &spectrum, waveform: &waveform), "Silent buffer reports no signal")
    assertTrue(spectrum.allSatisfy { $0 == 0 } && waveform.allSatisfy { $0 == 0 }, "Silent buffer zeroes the outputs")
    let tone = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1024)!
    tone.frameLength = 1024
    for c in 0..<2 { for i in 0..<1024 { tone.floatChannelData![c][i] = 0.5 * sinf(Float(i) * 0.3) } }
    let spectrumStorage = spectrum.withUnsafeBufferPointer { $0.baseAddress }
    assertTrue(analyzer.analyze(buffer: tone, spectrum: &spectrum, waveform: &waveform), "Tone reports a signal")
    assertTrue(spectrum.contains { $0 > 0.3 }, "Tone shows up in the spectrum")
    assertTrue(spectrum.withUnsafeBufferPointer { $0.baseAddress } == spectrumStorage, "Spectrum array is updated in place (no reallocation)")
    
    // Marquee: no timer when the text fits, when paused/hidden, or when scrolling is off
    let marquee = MarqueeView()
    marquee.isScrollingActive = true
    marquee.text = "SHORT"
    assertTrue(!marquee.isScrollTimerRunning, "Text that fits never starts the scroll timer")
    marquee.text = "A VERY LONG TRACK TITLE THAT DEFINITELY DOES NOT FIT INTO THE MARQUEE AREA"
    let scrollEnabled = PersistenceManager.shared.state.isMarqueeScrollEnabled
    PersistenceManager.shared.state.isMarqueeScrollEnabled = true
    marquee.updateScrollTimer()
    assertTrue(marquee.isScrollTimerRunning, "Long text scrolls while playing and visible")
    marquee.isScrollingActive = false
    assertTrue(!marquee.isScrollTimerRunning, "Paused / hidden: scroll timer stops")
    marquee.isScrollingActive = true
    PersistenceManager.shared.state.isMarqueeScrollEnabled = false
    marquee.updateScrollTimer()
    assertTrue(!marquee.isScrollTimerRunning, "Scrolling disabled in preferences: no timer")
    PersistenceManager.shared.state.isMarqueeScrollEnabled = scrollEnabled
}

// 18. Internet radio through the engine (§5): ICY demux, decode, EQ path, reconnect
final class TestRadioServer {
    let listener: NWListener
    private(set) var connections = 0
    private let body: Data
    private let queue = DispatchQueue(label: "test.radio")
    var port: UInt16 { listener.port?.rawValue ?? 0 }
    
    init(audio: Data, metaInt: Int, title: String) throws {
        // Interleave ICY metadata after every metaInt audio bytes
        var out = Data()
        var offset = 0
        var first = true
        while offset < audio.count {
            let end = min(audio.count, offset + metaInt)
            out.append(audio[offset..<end])
            offset = end
            if end - (end - metaInt) == metaInt && offset <= audio.count {
                var meta = first ? Data("StreamTitle='\(title)';".utf8) : Data()
                first = false
                let blocks = (meta.count + 15) / 16
                meta.append(Data(count: blocks * 16 - meta.count))
                out.append(UInt8(blocks))
                out.append(meta)
            }
        }
        body = out
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
        listener.start(queue: queue)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.signal() } }
        _ = ready.wait(timeout: .now() + 2)
    }
    
    private func serve(_ conn: NWConnection) {
        connections += 1
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [body, queue] _, _, _, _ in
          // Answer a moment later so the client has pressed Play before the burst ends
          queue.asyncAfter(deadline: .now() + 0.4) {
            let header = "HTTP/1.0 200 OK\r\nContent-Type: audio/aac\r\nicy-metaint: 4096\r\nicy-name: Test Radio\r\nicy-genre: Rock\r\n\r\n"
            conn.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in
                // Drop the connection after the burst, like a flaky server
                conn.cancel()
            })
          }
        }
    }
    
    func stop() { listener.cancel() }
}

func makeTestADTS(seconds: Double) throws -> Data {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("radio.aac")
    try? FileManager.default.removeItem(at: url)
    do {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128000]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * 44100)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        for c in 0..<2 { for i in 0..<Int(frames) { buf.floatChannelData![c][i] = 0.002 * sinf(Float(i) * 0.05) } }
        try file.write(from: buf)
    } // file closed here
    return try Data(contentsOf: url)
}

testGroup("Internet Radio via AVAudioEngine (Decoder, ICY, Reconnect)") {
    // Decoder alone: ADTS AAC bytes in arbitrary chunks -> PCM of the right length
    let adts = try makeTestADTS(seconds: 3.0)
    assertTrue(adts.count > 2_000, "ADTS fixture encoded (\(adts.count) bytes)")
    let decoder = try StreamDecoder(contentType: "audio/aacp")
    var decodedFrames: AVAudioFrameCount = 0
    var format: AVAudioFormat?
    decoder.onFormatReady = { format = $0 }
    decoder.onBuffer = { decodedFrames += $0.frameLength }
    var offset = 0
    while offset < adts.count {
        let end = min(adts.count, offset + 1371) // odd chunk size, like network reads
        try decoder.feed(adts.subdata(in: offset..<end))
        offset = end
    }
    assertEqual(format?.sampleRate, 44100, "Decoder reports stream sample rate")
    assertEqual(format?.channelCount, 2, "Decoder reports stereo")
    let decodedSeconds = Double(decodedFrames) / 44100
    assertTrue(decodedSeconds > 2.7 && decodedSeconds < 3.2, "Decoded ~3s of PCM (got \(decodedSeconds))")
    assertTrue(StreamDecoder.canDecode(contentType: "application/ogg"), "Ogg radio decoded in-engine (EQ, visualizer, proxy)")
    assertTrue(!StreamDecoder.canDecode(contentType: "application/vnd.apple.mpegurl"), "HLS goes to the AVPlayer fallback")
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
    let opusBytes = try Data(contentsOf: fixtures.appendingPathComponent("tone.opus"))
    let opus = try StreamDecoder(contentType: "audio/ogg")
    var opusFrames: AVAudioFrameCount = 0
    opus.onBuffer = { opusFrames += $0.frameLength }
    var at = 0
    while at < opusBytes.count {
        let end = min(opusBytes.count, at + 777)
        try opus.feed(opusBytes.subdata(in: at..<end))
        at = end
    }
    let opusSeconds = Double(opusFrames) / 48000
    assertTrue(opusSeconds > 0.9 && opusSeconds < 1.1, "Ogg Opus stream decodes in-engine (\(opusSeconds)s)")
    let vorbis = try StreamDecoder(contentType: "application/ogg")
    var vorbisRejected = false
    do { try vorbis.feed(try Data(contentsOf: fixtures.appendingPathComponent("tone.ogg"))) } catch { vorbisRejected = true }
    assertTrue(vorbisRejected, "Ogg Vorbis stream is handed to the AVPlayer fallback (AVAudioConverter can't decode it)")
    let junk = try StreamDecoder(contentType: "application/ogg")
    var junkFailed = false
    do {
        for _ in 0..<40 { try junk.feed(Data(repeating: 0x5A, count: 8192)) }
    } catch { junkFailed = true }
    assertTrue(junkFailed, "Undecodable data gives up after the probe limit (then AVPlayer takes over)")
    assertTrue(StreamDecoder.canDecode(contentType: "audio/mpeg"), "MP3 decoded in-engine")
    
    // ICY demux: audio bytes forwarded without metadata blocks
    let icy = ICYStreamSession(url: URL(string: "http://127.0.0.1/")!)
    icy.feedHeadersForTesting(["icy-metaint": "16"])
    var forwarded = Data()
    icy.onAudioData = { forwarded.append($0) }
    var wire = Data(repeating: 0xAA, count: 16)
    wire.append(1); wire.append(Data("StreamTitle='x';".utf8))
    wire.append(Data(repeating: 0xBB, count: 10))
    icy.feedDataForTesting(wire)
    assertEqual(forwarded, Data(repeating: 0xAA, count: 16) + Data(repeating: 0xBB, count: 10), "ICY metadata stripped from the audio byte stream")
    
    // End to end: local ICY server -> engine (EQ/DSP graph) -> tap, then reconnect after the server drops us
    let engine = AudioEngine.shared
    let savedDelay = AudioEngine.reconnectDelay
    AudioEngine.reconnectDelay = 0.3
    var events: [String] = []
    engine.onStreamEvent = { events.append($0) }
    var waveformSeen = false
    engine.onVisualizerFrame = { frame in
        var s = [Float](repeating: 0, count: 19), w = [Float](repeating: 0, count: 76)
        frame.read(spectrum: &s, waveform: &w)
        if w.contains(where: { abs($0) > 0.0001 }) { waveformSeen = true }
    }
    var titles: [String] = []
    let savedMeta = engine.onMetadataUpdate
    engine.onMetadataUpdate = { _, title, _, _ in titles.append(title) }
    defer {
        engine.stop()
        AudioEngine.reconnectDelay = savedDelay
        engine.onStreamEvent = nil
        engine.onVisualizerFrame = nil
        engine.onMetadataUpdate = savedMeta
    }
    
    let server = try TestRadioServer(audio: adts, metaInt: 4096, title: "Кино - Кукушка")
    defer { server.stop() }
    assertTrue(server.port > 0, "Test radio server listening")
    _ = try loadSync(engine, URL(string: "http://127.0.0.1:\(server.port)/stream")!)
    assertTrue(engine.isStreaming, "Engine is in stream mode")
    engine.play()
    assertTrue(spinRunLoop(until: { engine.streamBufferedSeconds > 0.5 }, timeout: 5), "Decoded radio audio is queued on the engine's stream node")
    assertTrue(engine.isStreamDecodedInEngine, "Stream is decoded in-engine (EQ/DSP/visualizer apply), not via AVPlayer")
    assertTrue(spinRunLoop(until: { waveformSeen }, timeout: 3), "Visualizer tap sees the real radio signal")
    assertTrue(spinRunLoop(until: { titles.contains("Кукушка") }, timeout: 3), "ICY StreamTitle parsed (artist/title split)")
    
    // Server dropped the connection after the burst -> reconnect
    assertTrue(spinRunLoop(until: { server.connections >= 2 }, timeout: 6), "Engine reconnects after the server drops the stream (connections: \(server.connections))")
    assertTrue(events.contains { $0.hasPrefix("Reconnecting (1/3)") }, "User sees 'Reconnecting (1/3)...' (events: \(events))")
    assertEqual(engine.status, .playing, "Status stays playing across a reconnect")
    
    // Server gone for good -> 3 attempts, then stop with a message
    server.stop()
    assertTrue(spinRunLoop(until: { engine.status == .stopped }, timeout: 15), "Engine gives up after the reconnect attempts")
    assertTrue(events.contains("Stream lost"), "User sees 'Stream lost' (events: \(events))")
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

// 20. Skin cursors, visualizer options, playback options, playlist MISC
testGroup("Skin Cursors") {
    // Base skin ships 8 .CUR files; they decode with the hotspot from the CUR header
    _ = SkinManager.shared.currentSkin
    SkinManager.shared.resetToBaseSkin()
    let cursors = SkinManager.shared.currentSkin?.cursors ?? [:]
    assertTrue(cursors.count >= 8, "Base skin cursors loaded (\(cursors.keys.sorted()))")
    for name in ["TITLEBAR", "CLOSE", "POSBAR", "VOLBAL", "EQSLID", "EQTITLE", "MAINMENU", "PSIZE"] {
        assertTrue(cursors[name] != nil, "Cursor \(name) present")
    }
    assertEqual(cursors["TITLEBAR"]?.image.size, NSSize(width: 32, height: 32), "Cursor image is 32x32")
    assertTrue(SkinLoader.makeCursor(fromCUR: Data([0, 0, 1, 0, 1, 0] + Array(repeating: 0, count: 30))) == nil, "ICO (type 1) data is not accepted as a cursor")

    // Skins without *.cur files get winamp.exe's built-in cursors (Winamp 2.95 behavior)
    assertEqual(BuiltInCursors.cursors.keys.sorted(), [205, 206, 207, 208, 209, 210], "All 6 built-in cursors decode")
    for cursor in BuiltInCursors.cursors.values {
        assertEqual(cursor.image.size, NSSize(width: 32, height: 32), "Built-in cursor is 32x32")
        assertEqual(cursor.hotSpot, .zero, "Built-in cursor hotspot is the arrow tip")
    }
    let builtIn = BuiltInCursors.complete([:])
    let usedNames = ["CLOSE", "MIN", "WINBUT", "MAINMENU", "POSBAR", "VOLBAL", "SONGNAME", "TITLEBAR", "NORMAL",
                     "WSCLOSE", "WSMIN", "WSWINBUT", "WSPOSBAR", "WSNORMAL", "PCLOSE", "PWINBUT", "PTBAR", "PNORMAL",
                     "PVSCROLL", "PSIZE", "PWSNORM", "PWSSIZE", "EQCLOSE", "EQSLID", "EQTITLE", "EQNORMAL"]
    for name in usedNames {
        assertTrue(builtIn[name] != nil, "Cursor \(name) has a built-in fallback")
    }
    assertTrue(builtIn["PSIZE"] === BuiltInCursors.cursors[210], "PSize.cur falls back to the resize cursor")
    assertTrue(builtIn["EQSLID"] === BuiltInCursors.cursors[209], "EQSlid.cur falls back to the vertical cursor")
    assertTrue(builtIn["WSCLOSE"] === BuiltInCursors.cursors[207], "Windowshade close uses the close cursor")
    let skinClose = NSCursor.pointingHand
    let mixed = BuiltInCursors.complete(["CLOSE": skinClose])
    assertTrue(mixed["CLOSE"] === skinClose, "A skin's own cursor wins over the built-in one")
    assertTrue(mixed["WSCLOSE"] === skinClose, "Windowshade close reuses the skin's Close.cur like Winamp 2.95")
    assertTrue(mixed["TITLEBAR"] === BuiltInCursors.cursors[205], "Missing skin cursors still get built-ins")
    assertTrue(cursors["PVSCROLL"] != nil && cursors["SONGNAME"] != nil, "Loaded skins are completed with built-ins")

    // Cursors follow the mouse in every window, key or not (tracking area on the window's root view)
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: true)
    let hosted = MainWindowView()
    hosted.frame = NSRect(x: 0, y: 0, width: 275, height: 116)
    host.contentView = hosted
    hosted.applySkinCursorNames()
    hosted.updateTrackingAreas()
    assertTrue(hosted.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.mouseMoved) },
               "Root view tracks the mouse even when the window isn't key")
    assertTrue(hosted.closeButton.trackingAreas.isEmpty, "Child controls don't add their own cursor tracking")
    func cursorAt(_ view: NSView, _ local: NSPoint) -> NSCursor? {
        hosted.skinCursor(atWindowPoint: view.convert(local, to: nil))
    }
    let closeFrame = hosted.closeButton.bounds
    assertTrue(cursorAt(hosted.closeButton, NSPoint(x: closeFrame.midX, y: closeFrame.midY)) === cursors["CLOSE"], "Close button shows CLOSE")
    assertTrue(cursorAt(hosted, NSPoint(x: 100, y: 6)) === cursors["TITLEBAR"], "Title bar shows TITLEBAR")
    let seekFrame = hosted.seekSlider.bounds
    assertTrue(cursorAt(hosted.seekSlider, NSPoint(x: seekFrame.midX, y: seekFrame.midY)) === cursors["POSBAR"], "Seek bar shows POSBAR")

    let main = MainWindowView()
    main.applySkinCursorNames()
    assertEqual(main.closeButton.skinCursorName, "CLOSE", "Close button cursor")
    assertEqual(main.seekSlider.skinCursorName, "POSBAR", "Seek bar cursor")
    assertEqual(main.marquee.skinCursorName, "SONGNAME", "Marquee cursor")
    assertEqual(main.skinCursorZones().map(\.name), ["TITLEBAR", "NORMAL"], "Main window zones")
    main.isShadeMode = true
    assertEqual(main.closeButton.skinCursorName, "WSCLOSE", "Windowshade close cursor")
    assertEqual(main.skinCursorZones().map(\.name), ["WSNORMAL"], "Windowshade zone")
    
    let pl = PlaylistWindowView(playlist: PlaylistModel())
    pl.frame = NSRect(x: 0, y: 0, width: 275, height: 232)
    pl.bounds = pl.frame
    let zones = pl.skinCursorZones()
    assertEqual(Set(zones.map(\.name)), ["PTBAR", "PNORMAL", "PVSCROLL", "PSIZE"], "Playlist zones")
    for i in zones.indices { for j in zones.indices where i < j {
        assertTrue(!zones[i].rect.intersects(zones[j].rect), "Playlist cursor zones don't overlap: \(zones[i].name) / \(zones[j].name)")
    }}
}

testGroup("Visualizer Options") {
    let vis = VisualizerView()
    var options = VisualizerOptions()
    options.barFalloff = .moderate
    options.peakFalloff = .slow
    vis.options = options
    vis.mode = .spectrum
    vis.spectrumAmplitudes = Array(repeating: 0.8, count: 19)
    vis.spectrumAmplitudes = Array(repeating: 0.0, count: 19)
    let afterOneFrame = vis.spectrumAmplitudes[0]
    assertTrue(abs(afterOneFrame - (0.8 - VisualizerFalloff.moderate.barStep)) < 0.0001, "Bars fall by the falloff step instead of dropping to zero (got \(afterOneFrame))")
    for _ in 0..<200 { vis.spectrumAmplitudes = Array(repeating: 0.0, count: 19) }
    assertEqual(vis.spectrumAmplitudes[0], 0, "Bars eventually reach zero")
    
    // Options survive a session round-trip and old session files without the field still decode
    var state = AppState()
    state.visualizerOptions.analyzerStyle = .fire
    state.visualizerOptions.bands = .thin
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(AppState.self, from: data)
    assertEqual(decoded.visualizerOptions.analyzerStyle, .fire, "Analyzer style persisted")
    assertEqual(decoded.visualizerOptions.bands, .thin, "Band mode persisted")
    var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    legacy.removeValue(forKey: "visualizerOptionsStorage")
    legacy.removeValue(forKey: "manualPlaylistAdvanceStorage")
    let legacyState = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: legacy))
    assertEqual(legacyState.visualizerOptions, VisualizerOptions(), "Old session.json decodes with default visualizer options")
    assertEqual(legacyState.manualPlaylistAdvance, false, "Old session.json decodes with manual advance off")
    
    // 76 thin bands -> 19 thick bars (max of each group of 4)
    let analyzer = FFTAnalyzer()
    let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let tone = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1024)!
    tone.frameLength = 1024
    for c in 0..<2 { for i in 0..<1024 { tone.floatChannelData![c][i] = 0.5 * sinf(Float(i) * 0.3) } }
    var thin = [Float](repeating: 0, count: 76), wave = [Float](repeating: 0, count: 76)
    assertTrue(analyzer.analyze(buffer: tone, spectrum: &thin, waveform: &wave), "Thin-band analysis")
    assertTrue(thin.filter { $0 > 0.3 }.count < 20, "A pure tone lights only a few of the 76 thin bands")
}

testGroup("Playback Options: Stop After Current, Manual Advance, Fade Stop") {
    typealias C = PlayerCoordinator
    assertEqual(C.actionAfterTrackEnd(stopAfterCurrent: false, manualAdvance: false, isRepeat: false), .advance, "Default: next track")
    assertEqual(C.actionAfterTrackEnd(stopAfterCurrent: true, manualAdvance: false, isRepeat: true), .stop, "Stop after current wins over repeat")
    assertEqual(C.actionAfterTrackEnd(stopAfterCurrent: false, manualAdvance: true, isRepeat: false), .stop, "Manual advance: stop at track end")
    assertEqual(C.actionAfterTrackEnd(stopAfterCurrent: false, manualAdvance: true, isRepeat: true), .replayCurrent, "Manual advance + repeat: replay the track")
    
    // Shift+V: long fade, status changes immediately
    let engine = AudioEngine.shared
    defer { engine.stop() }
    let url = try makeTestWAV(named: "fadestop.wav", seconds: 6.0)
    _ = try loadSync(engine, url)
    engine.play()
    _ = spinRunLoop(until: { engine.fadeGain >= 0.999 }, timeout: 0.5)
    engine.stop(fadeOutDuration: 1.0)
    assertEqual(engine.status, .stopped, "Fade-out stop updates status immediately")
    _ = spinRunLoop(until: { false }, timeout: 0.4)
    assertTrue(engine.fadeGain > 0.2 && engine.fadeGain < 0.95, "Still fading 0.4s into a 1s fade-out (gain \(engine.fadeGain))")
    assertTrue(spinRunLoop(until: { engine.fadeGain <= 0.0001 }, timeout: 1.5), "Fade-out stop reaches silence")
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

// 21. File types: associations, Info.plist, Finder integration
final class FakeLaunchServices: DefaultAppProvider {
    var defaults: [String: URL] = [:]
    var installed: [URL] = []
    var setCalls: [(String, URL)] = []
    func defaultApplication(for type: UTType) -> URL? { defaults[type.identifier] }
    func applications(for type: UTType) -> [URL] { installed }
    func setDefaultApplication(_ app: URL, for type: UTType) async throws {
        setCalls.append((type.identifier, app))
        defaults[type.identifier] = app
    }
}

func runMain(_ work: @escaping @MainActor () async -> Void) {
    var done = false
    Task { @MainActor in await work(); done = true }
    _ = spinRunLoop(until: { done }, timeout: 10)
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

testGroup("Audio Output Device List") {
    AudioDeviceManager.shared.refreshDevices()
    let names = AudioDeviceManager.shared.availableDevices.map(\.name)
    assertTrue(!names.contains { $0.hasPrefix("CADefaultDeviceAggregate") }, "Core Audio private aggregate devices are hidden: \(names)")
}

// 22. Document icon chooser, Setup page settings
final class RecordingInstaller: BundleIconInstaller {
    let real = SystemBundleIconInstaller()
    var registered: [URL] = []
    func install(icon: URL, as target: URL) throws { try real.install(icon: icon, as: target) }
    func resign(bundle: URL) throws { try real.resign(bundle: bundle) }
    func register(bundle: URL) { registered.append(bundle) } // never touch Launch Services in tests
    func verify(bundle: URL) -> Bool { real.verify(bundle: bundle) }
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

// 23. Playlists from other players, drag & drop into the playlist
final class FakeDrop: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard
    let location: NSPoint
    init(urls: [URL], location: NSPoint) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("macamp-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        self.location = location
    }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation { get { .default } set {} }
    var animatesToDestination: Bool { get { false } set {} }
    var numberOfValidItemsForDrop: Int { get { 0 } set {} }
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
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

testGroup("TrueType Title Fits the LCD") {
    let state = PersistenceManager.shared.state
    defer {
        PersistenceManager.shared.state.marqueeFontMode = state.marqueeFontMode
        PersistenceManager.shared.state.desktopFontSize = state.desktopFontSize
        PersistenceManager.shared.state.desktopFontFamily = state.desktopFontFamily
    }
    PersistenceManager.shared.state.marqueeFontMode = .bitmap
    assertEqual(MarqueeView.preferredFrame.height, 6, "Bitmap font keeps the 6 px TEXT.BMP row")
    PersistenceManager.shared.state.marqueeFontMode = .desktop
    assertEqual(MarqueeView.preferredFrame, NSRect(x: 112, y: 24, width: 152, height: 12), "TrueType uses the whole LCD box")
    PersistenceManager.shared.state.desktopFontFamily = "Helvetica"
    let marquee = MarqueeView()
    marquee.fontSettingsChanged()
    for size in [8.0, 10.0, 14.0] {
        PersistenceManager.shared.state.desktopFontSize = size
        let font = marquee.trueTypeFont()
        assertTrue(font.ascender - font.descender <= marquee.bounds.height - 1, "\(Int(size)) pt: whole letters fit (glyph box \(font.ascender - font.descender) in \(marquee.bounds.height))")
    }
    PersistenceManager.shared.state.desktopFontSize = 8
    assertEqual(marquee.trueTypeFont().pointSize, 8, "A size that fits is not shrunk")
}

testGroup("Ogg Vorbis / Opus Playback") {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
    let engine = AudioEngine.shared
    defer { engine.stop() }
    for (file, title, artist) in [("tone.ogg", "Ogg Title", "Ogg Artist"), ("tone.opus", "Opus Title", "Opus Artist")] {
        let url = fixtures.appendingPathComponent(file)
        assertTrue(AppConstants.Audio.supportedExtensions.contains(url.pathExtension), "\(file) is a supported extension")
        let meta = try loadSync(engine, url)
        assertTrue(abs(meta.duration - 1) < 0.1, "\(file) decodes in the engine (EQ/visualizer path), duration \(meta.duration)")
        let item = awaitValue { await TrackItem.create(from: url) }
        assertEqual(item.title, title, "\(file) title tag")
        assertEqual(item.artist, artist, "\(file) artist tag")
    }
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

testGroup("Crossfade Between Tracks") {
    let engine = AudioEngine.shared
    let savedFinished = engine.onPlaybackFinished
    let savedCanCrossfade = engine.canCrossfadeIntoNext
    defer {
        engine.onPlaybackFinished = savedFinished
        engine.canCrossfadeIntoNext = savedCanCrossfade
        engine.crossfadeDuration = 0
        engine.stop()
    }
    AudioDeviceManager.shared.selectDevice(uid: nil)
    engine.setOutputDevice(deviceID: AudioDeviceManager.shared.defaultDevice?.id)
    _ = spinRunLoop(until: { false }, timeout: 0.3)
    let first = try makeTestWAV(named: "xfade-a.wav", seconds: 4.0)
    let second = try makeTestWAV(named: "xfade-b.wav", seconds: 4.0)
    let short = try makeTestWAV(named: "xfade-short.wav", seconds: 1.5)

    engine.crossfadeDuration = 1.0
    var allowNext = true
    engine.canCrossfadeIntoNext = { allowNext }
    var finishedAt: TimeInterval?
    engine.onPlaybackFinished = {
        finishedAt = engine.currentTime
        Task { @MainActor in
            _ = try? await engine.load(url: second)
            engine.play()
        }
    }

    // Starts the next track ~1 s before the end, both audible for a moment, then only the new one
    _ = try loadSync(engine, first)
    engine.seek(to: 2.5)
    engine.play()
    assertTrue(spinRunLoop(until: { engine.isCrossfading && engine.status == .playing }, timeout: 3), "Next track starts under the current one")
    assertTrue((finishedAt ?? 9) > 2.8 && (finishedAt ?? 9) < 3.3, "Hand-off happens ~1 s before the end (at \(finishedAt ?? -1))")
    assertEqual(engine.currentMetadata?.url, second, "The new track is current during the crossfade")
    assertEqual(engine.status, .playing, "Playing during the crossfade")
    assertTrue(engine.currentTime < 1.0, "Time display follows the new track")
    assertTrue(spinRunLoop(until: { !engine.isCrossfading }, timeout: 2.5), "The old track stops after the crossfade")
    assertEqual(engine.status, .playing, "The new track keeps playing")

    // Pause during a crossfade cuts the old track
    finishedAt = nil
    _ = try loadSync(engine, first)
    engine.seek(to: 2.6)
    engine.play()
    assertTrue(spinRunLoop(until: { engine.isCrossfading && engine.status == .playing }, timeout: 3), "Second crossfade starts")
    engine.pause()
    assertTrue(!engine.isCrossfading, "Pause ends the crossfade")
    engine.stop()

    // No next track (end of list, stop-after-current, manual advance): the track plays to its real end
    allowNext = false
    var plainFinished = 0
    engine.onPlaybackFinished = { plainFinished += 1; finishedAt = engine.currentTime }
    _ = try loadSync(engine, first)
    engine.seek(to: 2.5)
    engine.play()
    assertTrue(spinRunLoop(until: { plainFinished == 1 }, timeout: 3), "Track finishes")
    assertTrue(!engine.isCrossfading, "No crossfade without a next track")
    assertEqual(engine.status, .stopped, "Stopped at the real end")

    // Tracks shorter than two crossfades just play out
    allowNext = true
    plainFinished = 0
    _ = try loadSync(engine, short)
    engine.play()
    assertTrue(spinRunLoop(until: { plainFinished == 1 }, timeout: 3), "Short track finishes")
    assertEqual(engine.status, .stopped, "Short track ended normally (no early hand-off)")

    // Playlist look-ahead used to decide
    let list = PlaylistModel()
    list.add(tracks: [TrackItem(url: first, title: "a"), TrackItem(url: second, title: "b")])
    list.currentIndex = 0
    assertTrue(list.hasNext, "Has a next track")
    list.currentIndex = 1
    assertTrue(!list.hasNext, "Last track without Repeat has no next")
    list.isRepeat = true
    assertTrue(list.hasNext, "Repeat wraps around")
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

testGroup("Status Bar Menu Title") {
    let font = [NSAttributedString.Key.font: NSFont.menuFont(ofSize: 0)]
    let long = "▶ Шок видео! Гитара с одной наклейкой! Эксклюзив (нет) 2016 год [cdJzZETdxYY]"
    let cut = StatusBarManager.truncated(long, toWidth: 300)
    assertTrue(cut.hasSuffix("…") && cut.hasPrefix("▶ Шок видео!"), "Long title is cut at the end (\(cut))")
    assertTrue((cut as NSString).size(withAttributes: font).width <= 300, "Cut title fits the width")
    assertEqual(StatusBarManager.truncated("▶ Кино - Кукушка", toWidth: 300), "▶ Кино - Кукушка", "Short title unchanged")
}

testGroup("Output Device: Back to System Default") {
    let engine = AudioEngine.shared
    defer { engine.stop() }
    func unitDevice() -> AudioDeviceID {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioUnitGetProperty(engine.engineOutputUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size)
        return id
    }
    let systemDefault = AudioDeviceManager.systemDefaultOutputDeviceID()
    assertTrue(systemDefault != 0, "Mac has a default output device")
    let wav = try makeTestWAV(named: "device-switch.wav", seconds: 6.0)
    _ = try loadSync(engine, wav)
    engine.play()
    _ = spinRunLoop(until: { false }, timeout: 0.3)
    // Pick a specific device (Built-in), then System Default again: playback must go on
    assertTrue(engine.setOutputDevice(deviceID: systemDefault), "Specific device selected")
    _ = spinRunLoop(until: { false }, timeout: 0.3)
    assertTrue(engine.setOutputDevice(deviceID: nil), "System Default selected")
    assertEqual(unitDevice(), systemDefault, "System Default routes to macOS's current output, not to device 0 (nothing)")
    assertTrue(engine.currentOutputDeviceID == nil, "Engine remembers it follows the system default")
    let before = engine.currentTime
    _ = spinRunLoop(until: { false }, timeout: 0.5)
    assertTrue(engine.isEngineRunning && engine.status == .playing, "Still playing after switching back")
    assertTrue(engine.currentTime > before + 0.3, "Time advances, so audio really plays (\(before) -> \(engine.currentTime))")
}

testGroup("ID3v1 '?' Placeholders") {
    var meta = AudioFileMetadata(url: URL(fileURLWithPath: "/tmp/Дилер.mp3"))
    meta.id3v2.title = "Дилер"
    meta.id3v2.album = "Не в фокусе"
    meta.id3v2.trackNumber = "1/10"
    meta.id3v1.hasTag = true
    meta.id3v1.title = "?????"           // what that file's v1 tag holds
    meta.id3v1.album = "?? ? ??????"
    meta.id3v1.artist = "Dolphin"
    meta.id3v1.year = "1997"
    meta.copyFromID3v1()
    assertEqual(meta.id3v2.title, "Дилер", "'?????' doesn't overwrite the real title")
    assertEqual(meta.id3v2.album, "Не в фокусе", "'?? ? ??????' doesn't overwrite the real album")
    assertEqual(meta.id3v2.artist, "Dolphin", "Real v1 text is still copied")
    assertEqual(meta.id3v2.year, "1997", "Year copied")
    assertEqual(meta.id3v2.trackNumber, "1/10", "Track 0 in v1 keeps the v2 track")
}

testGroup("Winamp 2.95 Menus and Shortcuts") {
    let c = PlayerCoordinator.shared
    if c.mainView == nil { c.start() }
    func titles(_ menu: NSMenu) -> [String] { menu.items.map { $0.isSeparatorItem ? "-" : $0.title } }
    func sub(_ menu: NSMenu, _ title: String) -> NSMenu { menu.items.first { $0.title == title }!.submenu! }
    @MainActor func key(_ chars: String, _ mods: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> Bool {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
        return c.handleKeyDown(event)
    }

    // Order and names as in docs/UI-screens/menu*.png
    let menu = c.buildWinampMenu()
    assertEqual(titles(menu), ["MacAmp...", "-", "Play", "View file info", "Bookmarks", "-", "Main Window", "Playlist Editor", "Equalizer",
                               "Library", "Minibrowser", "Video", "-", "Options", "Playback", "Visualization", "Skins", "-", "Exit"], "Main menu order")
    assertEqual(Array(titles(sub(menu, "Play")).prefix(4)), ["File...", "Location...", "Directory...", "-"], "Play menu")
    assertTrue(titles(sub(menu, "Play")).contains("Bookmark"), "Play ▸ Bookmark")
    assertEqual(titles(sub(menu, "Options")), ["Preferences...", "Skins", "-", "Time elapsed (⌃T toggles)", "Time remaining (⌃T toggles)", "-",
                                               "Always On Top", "Double Size", "EasyMove", "-", "Repeat", "Shuffle", "-", "Audio Output"],
                "Options menu (Audio Output = MacAmp addition at the end)")
    assertEqual(titles(sub(menu, "Playback")), ["Previous", "Play", "Pause", "Stop", "Next", "-", "Stop w/ fadeout", "Stop after current",
                                                "Back 5 seconds", "Fwd 5 seconds", "Start of list", "10 tracks back", "10 tracks fwd", "-",
                                                "Jump to time", "Jump to file"], "Playback menu")
    assertEqual(titles(sub(menu, "Visualization")), ["Visualization options...", "-", "Start/Stop plug-in", "Configure plug-in...", "Select plug-in..."], "Visualization menu")
    let skins = titles(sub(menu, "Skins"))
    assertEqual(Array(skins.prefix(3)), ["Skin Browser...", "-", "<Base Skin>"], "Skins menu starts like 2.95")
    assertTrue(skins.contains("<< Get more skins! >>"), "Get more skins")
    let mainWindowItem = menu.items.first { $0.title == "Main Window" }!
    assertEqual(mainWindowItem.keyEquivalent, "w", "Main Window shows ⌥W")
    assertEqual(mainWindowItem.keyEquivalentModifierMask, [.option], "Main Window shows ⌥W")

    // Shortcuts shown in the menu work with the menu closed
    let mode = c.mainView.timeDisplay.mode
    assertTrue(key("t", [.control]), "⌃T handled")
    assertTrue(c.mainView.timeDisplay.mode != mode, "⌃T toggles elapsed / remaining")
    _ = key("t", [.control])
    let easy = PersistenceManager.shared.state.easyMove
    assertTrue(key("e", [.control]) && PersistenceManager.shared.state.easyMove != easy, "⌃E toggles EasyMove")
    _ = key("e", [.control])
    let eqOn = c.mainView.eqToggle.isOn
    assertTrue(key("g", [.option]) && c.mainView.eqToggle.isOn != eqOn, "⌥G toggles the equalizer")
    _ = key("g", [.option])
    assertTrue(key("w", [.option]) && c.mainWindow.isVisible == false, "⌥W hides the main window")
    assertTrue(key("w", [.option]) && c.mainWindow.isVisible, "⌥W shows it again")

    // Start of list, 10 tracks back / fwd (clamped at the ends)
    let wav = try makeTestWAV(named: "menu-jump.wav", seconds: 3.0)
    let saved = c.playlist.tracks
    defer { c.audioEngine.stop(); c.playlist.clear(); c.playlist.add(tracks: saved) }
    c.playlist.clear()
    c.playlist.add(tracks: (0..<15).map { TrackItem(url: wav, title: "t\($0)", duration: 3) })
    c.playlist.currentIndex = 3
    c.handleTenTracksForward()
    assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 13 }, timeout: 3), "10 tracks fwd: 3 -> 13")
    c.handleTenTracksForward()
    assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 14 }, timeout: 3), "10 tracks fwd stops at the last track")
    c.handleTenTracksBack()
    assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 4 }, timeout: 3), "10 tracks back: 14 -> 4")
    assertTrue(key("z", [.control]), "⌃Z handled")
    assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 0 }, timeout: 3), "⌃Z: start of list")

    // Playlist item menu (docs/UI-screens/playlist item menu.png)
    let pl = c.plView!
    let rowPoint = pl.convert(NSPoint(x: 40, y: AppConstants.Playlist.Layout.topBarHeight + 4), to: nil)
    let click = NSEvent.mouseEvent(with: .rightMouseDown, location: rowPoint, modifierFlags: [], timestamp: 0,
                                   windowNumber: pl.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    let itemMenu = pl.menu(for: click)!
    assertEqual(titles(itemMenu), ["Play item(s)", "-", "Remove item(s)", "Crop files", "-", "File info", "Playlist entry", "Bookmark item(s)"],
                "Playlist item menu order")
    assertEqual(PlayerCoordinator.mountedAudioCDs().filter { !FileManager.default.fileExists(atPath: $0.appendingPathComponent(".TOC.plist").path) }, [],
                "Only volumes with a CD table of contents count as audio CDs")
}

testGroup("Track Info: Winamp 2.95 Single Screen") {
    // "?" placeholders that broken taggers leave in ID3v1 instead of Cyrillic
    assertTrue(ID3v1Tag.isPlaceholder("?????") && ID3v1Tag.isPlaceholder("?? ? ??????"), "'?' runs are placeholders")
    assertTrue(!ID3v1Tag.isPlaceholder("Dolphin") && !ID3v1Tag.isPlaceholder("") && !ID3v1Tag.isPlaceholder("Why? Because"), "Real text is not")

    // Frame count like Winamp's "56kbit, 205 frames"
    var tech = AudioTechnicalInfo()
    tech.duration = 5.0; tech.sampleRate = 22050; tech.samplesPerFrame = 576 // MPEG 2.0 layer 3
    assertEqual(tech.frameCount, 191, "Frames = length x rate / samples per frame")
    tech.samplesPerFrame = 0
    assertEqual(tech.frameCount, 0, "No MPEG header: no frame count")

    // MP3 shows ID3v1 + MPEG info; other formats only the tag group, and the box fits its content
    var mp3 = AudioFileMetadata(url: URL(fileURLWithPath: "/tmp/x.mp3"))
    mp3.techInfo.isMPEG = true
    let flac = AudioFileMetadata(url: URL(fileURLWithPath: "/tmp/x.flac"))
    func fitting(_ meta: AudioFileMetadata) -> NSSize {
        let host = NSHostingView(rootView: TrackInfoView(viewModel: TrackInfoViewModel(metadata: meta)))
        return host.fittingSize
    }
    let mp3Size = fitting(mp3), flacSize = fitting(flac)
    assertTrue(mp3Size.width >= 600 && mp3Size.height > 380 && mp3Size.height < 520, "MP3 box is compact like 2.95 (\(mp3Size))")
    assertTrue(flacSize.height <= mp3Size.height, "Non-MP3 box has no ID3v1 group (\(flacSize))")

    // The ID3v2 genre arrow shows no text, but its list must still name every genre (was a list of blank rows)
    var genre = "Rock"
    let arrow = Win32ComboBox(selection: Binding(get: { genre }, set: { genre = $0 }),
                              options: ID3Genre.allGenres.map { (value: $0, title: $0) }, width: 20, label: "")
    let list = arrow.buildMenu()
    assertEqual(list.items.count, ID3Genre.allGenres.count, "Every genre listed")
    assertTrue(list.items.allSatisfy { !$0.title.isEmpty }, "No blank rows in the genre list")
    assertEqual(list.items.first { $0.state == .on }?.title, "Rock", "Current genre checked")
}

testGroup("Preferences Tree as in Winamp 2.95") {
    assertEqual(PrefTreeItem.topLevel.map(\.title), ["Setup", "Options", "Plug-ins", "Skins", "Bookmarks"], "Top-level nodes, each a page")
    assertEqual(PrefTreeItem.setup.children.map(\.title), ["File types", "Agent"], "Setup children")
    assertEqual(PrefTreeItem.options.children.map(\.title), ["Display", "Visualization", "Shuffle", "Video", "Library", "CD Ripping"], "Options children, as in 2.95")
    assertEqual(PrefTreeItem.plugins.children.map(\.title), ["Input", "Output", "Visualization", "DSP/Effect", "General Purpose"], "Plug-ins children")
    // Every page renders
    let vm = PreferencesViewModel()
    for item in PrefTreeItem.allCases {
        vm.selectedTreeItem = item
        let host = NSHostingView(rootView: PreferencesView(viewModel: vm))
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 440)
        host.layoutSubtreeIfNeeded()
        assertTrue(host.fittingSize.width > 0, "\(item.title) page renders")
    }

    // Options ▸ Convert %20 / underscore (titles that are file names)
    let state = PersistenceManager.shared.state
    defer { PersistenceManager.shared.state.convertPercent20 = state.convertPercent20; PersistenceManager.shared.state.convertUnderscore = state.convertUnderscore }
    PersistenceManager.shared.state.convertPercent20 = true
    PersistenceManager.shared.state.convertUnderscore = true
    assertEqual(TrackItem.displayName(artist: "", title: "My_Song%20Live"), "My Song Live", "File-name titles get spaces")
    assertEqual(TrackItem.displayName(artist: "AC_DC", title: "Back_In"), "AC_DC - Back_In", "Tagged titles are left alone")
    PersistenceManager.shared.state.convertUnderscore = false
    assertEqual(TrackItem.displayName(artist: "", title: "My_Song%20Live"), "My_Song Live", "Underscore conversion can be turned off")
}

testGroup("Winamp 2.95 Hotkeys: Playlist, Equalizer, Keypad") {
    let c = PlayerCoordinator.shared
    if c.mainView == nil { c.start() }
    let saved = c.playlist.tracks
    defer { c.audioEngine.stop(); c.playlist.clear(); c.playlist.add(tracks: saved) }
    @MainActor func names() -> [String] { c.playlist.tracks.map(\.title) }
    c.playlist.clear()
    c.playlist.add(tracks: ["c", "a", "e", "b", "d"].map { TrackItem(url: URL(fileURLWithPath: "/tmp/\($0).mp3"), title: $0) })

    // ⌥↑ / ⌥↓ move the selection with the current track
    c.playlist.selectedIndices = [1, 2]
    c.playlist.currentIndex = 2
    let pl = c.plView!
    assertTrue(pl.handlePlaylistKey(keyCode: AppConstants.KeyCodes.upArrow, characters: "", flags: [.option]), "⌥↑ handled")
    assertEqual(names(), ["a", "e", "c", "b", "d"], "⌥↑ moves the selected block up")
    assertEqual(c.playlist.selectedIndices, [0, 1], "Selection follows")
    assertEqual(c.playlist.currentTrack?.title, "e", "Current track follows")
    _ = pl.handlePlaylistKey(keyCode: AppConstants.KeyCodes.upArrow, characters: "", flags: [.option])
    assertEqual(names(), ["a", "e", "c", "b", "d"], "Already at the top: nothing moves")
    _ = pl.handlePlaylistKey(keyCode: AppConstants.KeyCodes.downArrow, characters: "", flags: [.option])
    assertEqual(names(), ["c", "a", "e", "b", "d"], "⌥↓ moves it back down")

    // Sorting and order keys
    assertTrue(pl.handlePlaylistKey(keyCode: AppConstants.KeyCodes.digit1, characters: "!", flags: [.control, .shift]), "⌃⇧1 handled")
    assertEqual(names(), ["a", "b", "c", "d", "e"], "⌃⇧1 sorts by title")
    _ = pl.handlePlaylistKey(keyCode: 15, characters: "r", flags: [.control])
    assertEqual(names(), ["e", "d", "c", "b", "a"], "⌃R reverses")
    c.playlist.selectedIndices = [0]
    _ = pl.handlePlaylistKey(keyCode: 34, characters: "i", flags: [.control])
    assertEqual(c.playlist.selectedIndices, [1, 2, 3, 4], "⌃I inverts the selection")

    // Equalizer keys
    let eq = c.eqView!
    let band = eq.bandSliders[0].value, lowBand = eq.bandSliders[9].value, preamp = eq.preampSlider.value
    assertTrue(eq.handleEqualizerKey(characters: "1", keyCode: 18, flags: []), "1 handled in the equalizer")
    assertEqual(eq.bandSliders[0].value, min(12, band + 1), "1 raises the 60 Hz band")
    _ = eq.handleEqualizerKey(characters: "p", keyCode: 35, flags: [])
    assertEqual(eq.bandSliders[9].value, max(-12, lowBand - 1), "P lowers the 16 kHz band")
    _ = eq.handleEqualizerKey(characters: "`", keyCode: 50, flags: [])
    assertEqual(eq.preampSlider.value, min(12, preamp + 1), "` raises the preamp")
    _ = eq.handleEqualizerKey(characters: "\t", keyCode: AppConstants.KeyCodes.tab, flags: [])
    assertEqual(eq.preampSlider.value, preamp, "Tab lowers it again")
    let eqOn = eq.onToggle.isOn
    _ = eq.handleEqualizerKey(characters: "n", keyCode: 45, flags: [])
    assertTrue(eq.onToggle.isOn != eqOn, "N toggles the equalizer")
    _ = eq.handleEqualizerKey(characters: "n", keyCode: 45, flags: [])  // back on
    // Put the curve back as it was
    for (slider, value) in [(eq.bandSliders[0], band), (eq.bandSliders[9], lowBand)] {
        slider.value = value
        slider.onValueChanged?(value)
    }
    assertTrue(!eq.handleEqualizerKey(characters: "x", keyCode: 7, flags: []), "Other keys fall through to playback (X = Play)")

    // Keypad
    let wav = try makeTestWAV(named: "keypad.wav", seconds: 3.0)
    c.playlist.clear()
    c.playlist.add(tracks: (0..<12).map { TrackItem(url: wav, title: "k\($0)", duration: 3) })
    c.playlist.currentIndex = 0
    assertTrue(c.handleWinampGlobalKey(keyCode: AppConstants.KeyCodes.keypad3, flags: [.numericPad]), "Num 3 handled")
    assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 10 }, timeout: 3), "Num 3: ten tracks forward")
    assertTrue(c.handleWinampGlobalKey(keyCode: AppConstants.KeyCodes.keypad6, flags: [.numericPad]), "Num 6 handled")
    assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 11 }, timeout: 3), "Num 6: next track")
    assertTrue(!c.handleWinampGlobalKey(keyCode: 0, flags: []), "Plain A isn't a global key")
}

testGroup("Winamp 2.95 Main Window Controls and Small Options") {
    let c = PlayerCoordinator.shared
    if c.mainView == nil { c.start() }
    func items(_ view: WinampControlView) -> [String] {
        (view.contextMenuProvider?().items ?? []).map { $0.attributedTitle?.string ?? $0.title }
    }
    // Right-click menus of the transport buttons, as in 2.95 (strings from winamp.exe)
    assertEqual(items(c.mainView.prevButton), ["Previous\t(Click)", "Start of list\t(⌃Click)", "Rewind 5 seconds\t(⇧Click)"], "Previous button menu")
    assertEqual(items(c.mainView.stopButton), ["Stop\t(Click)", "Stop w/ fadeout\t(⇧Click)", "Stop after current\t(⌃Click)"], "Stop button menu")
    assertEqual(items(c.mainView.nextButton), ["Next\t(Click)", "Fastforward 5 seconds\t(⇧Click)", "End of list\t(⌃Click)"], "Next button menu")
    assertEqual(items(c.mainView.ejectButton), ["Open file...\t(Click)", "Open directory...\t(⇧Click)", "Open location...\t(⌃Click)"], "Eject button menu")
    assertEqual(items(c.mainView.timeDisplay), ["Time elapsed\t(⌃T toggles)", "Time remaining\t(⌃T toggles)"], "Time display menu")
    assertEqual(items(c.mainView.marquee).last, "Autoscroll songname", "Song title menu ends with Autoscroll songname")

    // Tooltips and title dimming switches
    let state = PersistenceManager.shared.state
    defer {
        PersistenceManager.shared.state.mainWindowTooltips = state.mainWindowTooltips
        PersistenceManager.shared.state.dimTitlebars = state.dimTitlebars
        c.applyMainWindowTooltips()
    }
    PersistenceManager.shared.state.mainWindowTooltips = true
    c.applyMainWindowTooltips()
    assertEqual(c.mainView.prevButton.toolTip, "Previous", "Tooltip on")
    PersistenceManager.shared.state.mainWindowTooltips = false
    c.applyMainWindowTooltips()
    assertTrue(c.mainView.prevButton.toolTip == nil, "Tooltips off")
    PersistenceManager.shared.state.dimTitlebars = false
    assertTrue(c.mainView.drawsActiveTitleBar, "No dimming: title bar always drawn active")

    // Shuffle morph rate: same tracks every pass; slow keeps most of the order, fast reshuffles
    let ids = (0..<50).map { _ in UUID() }
    let fast = PlaylistModel.morphedOrder(ids, rate: 1)
    assertEqual(Set(fast), Set(ids), "Fast pass has every track once")
    let slow = PlaylistModel.morphedOrder(ids, rate: 0)
    assertEqual(Set(slow), Set(ids), "Slow pass has every track once")
    let unchanged = zip(slow, ids).filter { $0 == $1 }.count
    assertTrue(unchanged >= 48, "Slow morph: a slight variation (\(unchanged)/50 in place)")

    // End of list (⌃-click Next)
    let wav = try makeTestWAV(named: "endlist.wav", seconds: 3.0)
    let saved = c.playlist.tracks
    defer { c.audioEngine.stop(); c.playlist.clear(); c.playlist.add(tracks: saved) }
    c.playlist.clear()
    c.playlist.add(tracks: (0..<5).map { TrackItem(url: wav, title: "e\($0)", duration: 3) })
    c.playlist.currentIndex = 0
    c.handleEndOfList()
    assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 4 }, timeout: 3), "End of list plays the last track")
}

testGroup("Formats: MP2, AU, MIDI") {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
    let engine = AudioEngine.shared
    defer { engine.stop() }
    AudioDeviceManager.shared.selectDevice(uid: nil)
    engine.setOutputDevice(deviceID: AudioDeviceManager.shared.defaultDevice?.id)
    for file in ["tone.mp2", "tone.au"] {
        let url = fixtures.appendingPathComponent(file)
        assertTrue(AppConstants.Audio.supportedExtensions.contains(url.pathExtension), "\(file) is a supported extension")
        let meta = try loadSync(engine, url)
        assertTrue(abs(meta.duration - 1) < 0.1, "\(file) plays in the engine (\(meta.duration) s)")
    }

    // MIDI: length without rendering; rendered once with the GM synth, then reused
    let mid = fixtures.appendingPathComponent("tune.mid")
    assertTrue(MIDIRenderer.isMIDI(mid), "Recognised as MIDI")
    assertTrue(abs(MIDIRenderer.duration(of: mid) - (2.0 + MIDIRenderer.tail)) < 0.05, "MIDI length from the sequence, release tail included (\(MIDIRenderer.duration(of: mid)))")
    let cached = try MIDIRenderer.cacheURL(for: mid)
    try? FileManager.default.removeItem(at: cached)
    let rendered = awaitValue { (try? await MIDIRenderer.renderedFile(for: mid)) ?? mid }
    assertEqual(rendered, cached, "Rendered into the cache")
    let audio = try AVAudioFile(forReading: rendered)
    let seconds = Double(audio.length) / audio.processingFormat.sampleRate
    assertTrue(abs(seconds - (2.0 + MIDIRenderer.tail)) < 0.1, "Rendered length = music + release tail (\(seconds))")
    let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length))!
    try audio.read(into: buffer)
    let peak = (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(buffer.floatChannelData![0][$1])) }
    assertTrue(peak > 0.05, "The synth produced sound (peak \(peak))")
    let stamp = try FileManager.default.attributesOfItem(atPath: cached.path)[.modificationDate] as? Date
    _ = awaitValue { (try? await MIDIRenderer.renderedFile(for: mid)) ?? mid }
    assertEqual(try FileManager.default.attributesOfItem(atPath: cached.path)[.modificationDate] as? Date, stamp, "Second play reuses the cache")
    let rmi = fixtures.appendingPathComponent("tune.rmi")
    assertEqual(MIDIRenderer.duration(of: rmi), MIDIRenderer.duration(of: mid), "RIFF-wrapped .rmi unwraps to the same music")

    var finished = 0
    let savedFinished = engine.onPlaybackFinished
    defer { engine.onPlaybackFinished = savedFinished }
    engine.onPlaybackFinished = { finished += 1 }
    let meta = try loadSync(engine, mid)
    assertTrue(abs(meta.duration - (2.0 + MIDIRenderer.tail)) < 0.1, "Engine plays the rendered MIDI (\(meta.duration) s)")
    engine.play()
    assertTrue(spinRunLoop(until: { finished == 1 }, timeout: 6), "MIDI plays to the end")
    let item = awaitValue { await TrackItem.create(from: mid) }
    assertTrue(abs(item.duration - meta.duration) < 0.05, "Playlist and time display show the same MIDI length")
}

testGroup("Disk Writer (out_disk)") {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/diskwriter", isDirectory: true)
    try? FileManager.default.removeItem(at: folder)
    let wav = try makeTestWAV(named: "dw-source.wav", seconds: 2.0)
    func length(_ url: URL) throws -> Double {
        let f = try AVAudioFile(forReading: url)
        return Double(f.length) / f.processingFormat.sampleRate
    }
    for format in DiskWriterFormat.allCases {
        let out = awaitValue { try? await DiskWriter.write(TrackItem(url: wav, title: "Song", artist: "Band"), to: folder, format: format) }
        assertTrue(out?.lastPathComponent.hasPrefix("Band - Song") == true, "\(format): named Artist - Title (\(out?.lastPathComponent ?? "-"))")
        assertEqual(out?.pathExtension, format.fileExtension, "\(format): extension")
        let seconds = out.flatMap { try? length($0) } ?? 0
        assertTrue(abs(seconds - 2.0) < 0.1, "\(format): readable, 2 s long (\(seconds))")
    }
    let names = (try FileManager.default.contentsOfDirectory(atPath: folder.path)).sorted()
    assertTrue(names.contains("Band - Song (2).m4a"), "Never overwrites: second .m4a gets (2) (\(names))")
    assertTrue(!names.contains { $0.contains("partial") }, "No partial files left")

    // A CUE track writes only its range; MIDI writes the rendered music
    let cueTrack = TrackItem(url: wav.withPlaybackRange(start: 0.5, end: 1.5), title: "Middle")
    let cueOut = awaitValue { try? await DiskWriter.write(cueTrack, to: folder, format: .wav) }
    assertTrue(abs(((try? length(cueOut!)) ?? 0) - 1.0) < 0.02, "CUE track: just its 1 s range")
    let midOut = awaitValue { try? await DiskWriter.write(TrackItem(url: fixtures.appendingPathComponent("tune.mid"), title: "Tune"), to: folder, format: .flac) }
    assertTrue(abs(((try? length(midOut!)) ?? 0) - (2.0 + MIDIRenderer.tail)) < 0.1, "MIDI written from its rendering")

    // Play with the Disk Writer as output writes the playlist from the selected track on, no sound
    let c = PlayerCoordinator.shared
    if c.mainView == nil { c.start() }
    let state = PersistenceManager.shared.state
    let saved = c.playlist.tracks
    defer {
        PersistenceManager.shared.state.diskWriterEnabled = state.diskWriterEnabled
        PersistenceManager.shared.state.diskWriterFolderStorage = state.diskWriterFolderStorage
        c.playlist.clear(); c.playlist.add(tracks: saved)
    }
    let runFolder = folder.appendingPathComponent("run")
    PersistenceManager.shared.state.diskWriterEnabled = true
    PersistenceManager.shared.state.diskWriterFolder = runFolder
    PersistenceManager.shared.state.diskWriterFormat = .wav
    c.playlist.clear()
    c.playlist.add(tracks: ["One", "Two", "Three"].map { TrackItem(url: wav, title: $0) })
    c.loadAndPlay(track: c.playlist.tracks[1])
    assertTrue(spinRunLoop(until: { c.diskWriterTask == nil && (try? FileManager.default.contentsOfDirectory(atPath: runFolder.path).count) == 2 }, timeout: 10),
               "Play wrote Two and Three (from the selected track to the end)")
    assertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: runFolder.path)), ["Two.wav", "Three.wav"], "Files named after the tracks")
    assertEqual(c.audioEngine.status, .stopped, "Nothing played through the speakers")
}

testGroup("RLE Skin Bitmaps (GEN.BMP rows)") {
    // ImageIO shifted rows after RLE skip codes; MacAmp decodes RLE8 / RLE4 itself
    let wsz = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MacAmp/Resources/base-2.91.wsz")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/rle", isDirectory: true)
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzip.arguments = ["-q", "-o", wsz.path, "GEN.BMP", "-d", dir.path]
    try unzip.run(); unzip.waitUntilExit()
    let data = try Data(contentsOf: dir.appendingPathComponent("GEN.BMP"))
    guard let image = BMPDecoder.decodeRLE(data) else { throw NSError(domain: "test", code: 1) }
    assertEqual(image.width, 194, "GEN.BMP width")
    let rep = NSBitmapImageRep(cgImage: image)
    func rgb(_ x: Int, _ y: Int) -> [Int] { var p = [Int](repeating: 0, count: 4); rep.getPixel(&p, atX: x, y: y); return Array(p.prefix(3)) }
    let cyan = [0, 198, 255]
    assertTrue(rgb(130, 85) != cyan && rgb(130, 85) != [0, 0, 0], "Bottom fill's last row is at y 85 (\(rgb(130, 85)))")
    assertEqual(rgb(3, 94), [41, 41, 64], "Active letters end at y 94 (frame colour)")
    assertEqual(rgb(3, 102), [41, 41, 64], "Inactive letters end at y 102")
    assertEqual(rgb(3, 95), rgb(193, 0), "Gap row between the letter strips is background")
    assertTrue(BMPDecoder.decodeRLE(Data("not a bitmap".utf8)) == nil, "Non-RLE data goes to ImageIO")
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

testGroup("Video: audio tracks and subtitles (1.1)") {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
    let dual = fixtures.appendingPathComponent("dual-audio.mp4")
    let tracks = awaitValue { await VideoTracks.audioTracks(of: dual) }
    assertEqual(tracks.map(\.title), ["Russian (AAC, 2 ch)", "English (AAC, 2 ch)"], "Audio tracks listed with language and format")

    // The second track taken out on its own is the 880 Hz one (the first is 440 Hz)
    func frequency(_ url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = buffer.floatChannelData![0]
        var crossings = 0
        for i in 1..<Int(buffer.frameLength) where (samples[i - 1] < 0) != (samples[i] < 0) { crossings += 1 }
        return Double(crossings) / 2 / (Double(buffer.frameLength) / file.processingFormat.sampleRate)
    }
    let english = awaitValue { try? await VideoTracks.extract(tracks[1].id, from: dual) }
    assertTrue(english != nil, "Track extracted")
    if let english { assertTrue(abs(try frequency(english) - 880) < 30, "Extracted track is the English one (\(try frequency(english)) Hz)") }
    assertTrue(abs(try frequency(dual) - 440) < 30, "The engine's default is the first track")
    VideoTracks.setOverride(english, for: dual)
    assertEqual(VideoTracks.audioOverride(for: dual), english, "Engine plays the chosen track")
    VideoTracks.setOverride(nil, for: dual)

    // SRT: Windows line ends, tags, two-line cues, Windows-1251
    let srt = "1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Привет</i>\r\n{\\an8}мир\r\n\r\n2\r\n00:00:03.000 --> 00:00:04,000\r\nПока\r\n"
    let cues = SRT.parse(srt)
    assertEqual(cues, [SubtitleCue(start: 1, end: 2.5, text: "Привет\nмир"), SubtitleCue(start: 3, end: 4, text: "Пока")], "SRT parsed")
    assertEqual(SRT.text(at: 2.0, in: cues), "Привет\nмир", "Cue at a time")
    assertTrue(SRT.text(at: 2.7, in: cues) == nil, "Nothing between cues")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/srt-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let film = folder.appendingPathComponent("Film.mp4")
    try FileManager.default.copyItem(at: dual, to: film)
    try srt.data(using: .windowsCP1251)!.write(to: folder.appendingPathComponent("Film.ru.srt"))
    try "1\n00:00:00,500 --> 00:00:01,500\nHello\n".write(to: folder.appendingPathComponent("Film.srt"), atomically: true, encoding: .utf8)
    try "x".write(to: folder.appendingPathComponent("Other.srt"), atomically: true, encoding: .utf8)
    let files = SRT.files(for: film)
    assertEqual(files.map(\.title), ["Russian (.srt)", "Subtitles (.srt)"], "Subtitles next to the video, by name")
    assertEqual(SRT.load(files[0].url).first?.text, "Привет\nмир", "Windows-1251 subtitles read")

    // In the window: tracks and subtitle choices, embedded subtitles shown as text, the language remembered
    PersistenceManager.shared.state.videoAutoOpen = false
    PersistenceManager.shared.state.videoSubtitleLanguage = nil
    let video = VideoController(rect: NSRect(x: 0, y: 0, width: 275, height: 232))
    video.trackLoaded(film)
    _ = spinRunLoop(until: { MainActor.assumeIsolated { !video.subtitleChoices.isEmpty } }, timeout: 5)
    assertEqual(video.audioTracks.count, 2, "Window knows both audio tracks")
    assertEqual(video.subtitleChoices.map(\.title), ["Russian", "Russian (.srt)", "Subtitles (.srt)"], "Embedded and .srt subtitles offered")
    assertTrue(video.currentSubtitle == nil, "Subtitles off by default")
    video.selectSubtitle(video.subtitleChoices[0])
    video.player.play()
    _ = spinRunLoop(until: { MainActor.assumeIsolated { video.subtitleText != nil } }, timeout: 3)
    video.player.pause()
    assertTrue(["Привет", "Мир"].contains(video.subtitleText ?? ""), "Embedded subtitle shown as text (\(video.subtitleText ?? "none"))")
    assertEqual(PersistenceManager.shared.state.videoSubtitleLanguage.map { VideoController.sameLanguage($0, "ru") }, true, "Language remembered")
    let next = VideoController(rect: NSRect(x: 0, y: 0, width: 275, height: 232))
    next.trackLoaded(film)
    _ = spinRunLoop(until: { MainActor.assumeIsolated { next.currentSubtitle != nil } }, timeout: 5)
    assertTrue(VideoController.sameLanguage(next.currentSubtitle?.language, "ru"), "Next video starts with the same language")
    PersistenceManager.shared.state.videoSubtitleLanguage = nil
    PersistenceManager.shared.state.videoAutoOpen = true
    assertTrue(VideoController.sameLanguage("rus", "ru-RU") && !VideoController.sameLanguage("en", "ru"), "Language codes compared loosely")
}

testGroup("Video and Minibrowser windows") {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
    let clip = fixtures.appendingPathComponent("clip.mp4")
    assertTrue(VideoController.isVideo(clip) && !VideoController.isVideo(fixtures.appendingPathComponent("tone.mp2")), "Video by extension")
    assertTrue(AppConstants.Audio.supportedExtensions.contains("mp4"), "MP4 is playable")
    // The engine plays the movie's sound (so EQ, visualizer and seeking work as for any track)
    let engine = AudioEngine.shared
    defer { engine.stop() }
    let meta = try loadSync(engine, clip)
    assertTrue(abs(meta.duration - 2) < 0.1, "Movie sound loads in the engine (\(meta.duration) s)")

    // Window sizes: video + frame (11 + 8, 20 + 38), never below 275 × 116
    let insets = NSEdgeInsets(top: 20, left: 11, bottom: 38, right: 8)
    let video = CGSize(width: 320, height: 240)
    assertEqual(VideoController.windowSize(video: video, zoom: .normal, insets: insets).size, NSSize(width: 339, height: 298), "Normal size")
    assertEqual(VideoController.windowSize(video: video, zoom: .double, insets: insets).size, NSSize(width: 659, height: 538), "Double size")
    assertEqual(VideoController.windowSize(video: video, zoom: .half, insets: insets).size, NSSize(width: 275, height: 178), "Half size keeps the minimum width")
    // 1080p on a 1440 × 806 screen: shrunk keeping 16:9, not cut to the screen's shape
    let hd = VideoController.windowSize(video: CGSize(width: 1920, height: 1080), zoom: .normal, insets: insets, screen: NSSize(width: 1440, height: 806))
    let picture = CGSize(width: hd.size.width - 19, height: hd.size.height - 58)
    assertTrue(hd.size.width <= 1440 && hd.size.height <= 806, "Fits the screen")
    assertTrue(abs(picture.width / picture.height - 16.0 / 9) < 0.01, "Keeps the video's proportions (\(picture))")
    assertEqual(Int((hd.scale * 100).rounded()), 69, "Real scale shown (69%)")
    assertEqual(VideoController.windowSize(video: CGSize(width: 1920, height: 1080), zoom: .half, insets: insets, screen: NSSize(width: 1440, height: 806)).size,
                NSSize(width: 979, height: 598), "Half size of 1080p fits as is")

    // A loaded video file gives the window its picture and size
    PersistenceManager.shared.state.videoAutoOpen = false
    let controller = VideoController(rect: NSRect(x: 0, y: 0, width: 275, height: 232))
    controller.trackLoaded(clip)
    _ = spinRunLoop(until: { controller.naturalSize != nil }, timeout: 5)
    assertEqual(controller.naturalSize, CGSize(width: 160, height: 120), "Video size read from the file")
    assertTrue(controller.frameView.info.hasPrefix("clip"), "Info line names the video")
    assertEqual(VideoController.fourCC(kCMVideoCodecType_H264), "avc1", "Codec names for the info line")
    assertEqual(VideoController.fourCC(kCMVideoCodecType_VP9), "vp09", "VP9 (YouTube) named")
    controller.trackLoaded(fixtures.appendingPathComponent("tone.mp2"))
    assertTrue(controller.naturalSize == nil && controller.player.currentItem == nil, "An audio track clears the picture")
    PersistenceManager.shared.state.videoAutoOpen = true

    // Both frames come from the skin (the loader has to read VIDEO.BMP and MB.BMP)
    SkinManager.shared.resetToBaseSkin()
    assertTrue(SkinManager.shared.sheet("VIDEO") != nil && SkinManager.shared.sheet("MB") != nil, "VIDEO.BMP and MB.BMP loaded")
    // Frame: five 15 px buttons in the bottom bar
    let frame = MediaWindowFrameView(sheet: "VIDEO", content: NSView())
    frame.frame = NSRect(x: 0, y: 0, width: 275, height: 232)
    assertEqual(frame.buttonRect(0), NSRect(x: 9, y: 203, width: 15, height: 18), "First button")
    assertEqual(frame.buttonRect(4).minX, 69, "Menu button")
    // The ▼ menu opens upward from its button: its bottom edge on the button's top, left edges aligned
    let menu = NSMenu(); menu.addItem(withTitle: "Fullscreen", action: nil, keyEquivalent: "")
    let origin = frame.menuOrigin(menu, button: 4)
    assertEqual(origin, NSPoint(x: 69, y: 203 - menu.size.height), "Menu sits on top of the ▼ button")

    // Minibrowser
    assertEqual(BrowserController.address(from: "skins.webamp.org")?.absoluteString, "https://skins.webamp.org", "Typed address gets https")
    assertEqual(BrowserController.address(from: "http://example.com/a")?.absoluteString, "http://example.com/a", "Full address kept")
    assertTrue(BrowserController.isMedia(URL(string: "https://example.com/stream.mp3")!), "Audio link plays in MacAmp")
    assertTrue(BrowserController.isMedia(URL(string: "http://example.com/radio.pls")!), "Playlist link plays in MacAmp")
    assertTrue(!BrowserController.isMedia(URL(string: "https://example.com/page.html")!), "Pages stay in the browser")
    assertTrue(BrowserController.startPage.contains("radio-browser.info") && BrowserController.startPage.contains("skins.webamp.org"), "Start page links")

    // Back returns to the start page (it has its own address, macamp://start)
    let browser = BrowserController(rect: NSRect(x: 0, y: 0, width: 350, height: 348))
    @MainActor func settle() { _ = spinRunLoop(until: { MainActor.assumeIsolated { !browser.webView.isLoading } }, timeout: 10); _ = spinRunLoop(until: { false }, timeout: 0.3) }
    settle()
    assertEqual(browser.webView.url, BrowserController.startURL, "Start page loads at macamp://start")
    browser.webView.load(URLRequest(url: URL(string: "data:text/html,<p>elsewhere</p>")!))
    settle()
    assertTrue(browser.webView.canGoBack, "History has the start page")
    browser.webView.goBack()
    settle()
    assertEqual(browser.webView.url, BrowserController.startURL, "Back reaches the start page")
    assertEqual(browser.frameView.info, "MacAmp Minibrowser", "Info line on the start page")
    let html = awaitValue { (try? await browser.webView.evaluateJavaScript("document.body.innerText")) as? String ?? "" }
    assertTrue(html.contains("Welcome to the Minibrowser"), "Start page content is back")
    // A page's own player (a radio site's play button) hands the stream to MacAmp
    var handed: URL?
    browser.onMedia = { handed = $0 }
    browser.webView.loadHTMLString("<audio src='http://radio.example/stream.mp3'></audio>", baseURL: nil)
    settle()
    // The play event a click on the page's player fires (a script can't start audio: WebKit wants a real click)
    _ = awaitValue { _ = try? await browser.webView.evaluateJavaScript("document.querySelector('audio').dispatchEvent(new Event('play')); 1"); return 1 }
    _ = spinRunLoop(until: { handed != nil }, timeout: 5)
    assertEqual(handed?.absoluteString, "http://radio.example/stream.mp3", "Page audio goes to the player")
    let paused = awaitValue { (try? await browser.webView.evaluateJavaScript("document.querySelector('audio').paused")) as? Bool ?? false }
    assertTrue(paused, "The page itself stays silent")
    var blob: URL?
    browser.onMedia = { blob = $0 }
    _ = awaitValue { _ = try? await browser.webView.evaluateJavaScript("var a = document.querySelector('audio'); a.src = 'blob:https://youtube.example/1'; a.dispatchEvent(new Event('play')); 1"); return 1 }
    _ = spinRunLoop(until: { false }, timeout: 0.3)
    assertTrue(blob == nil, "Streams a page builds itself (blob:) stay in the page")
    assertTrue(BrowserController.startPage.contains("macamp://radio"), "Start page radio link opens the Library")
    assertTrue(BrowserController.isInterruption(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)), "-999 is not shown as an error")
    assertTrue(!BrowserController.isInterruption(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)), "Real errors are")
}

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

    // Base skin leaves the list selection colours unset: they follow the playlist selection, as in wa_dlg.h
    SkinManager.shared.resetToBaseSkin()
    let theme = GenexTheme.current
    assertEqual(theme.ns(.selectionBackground), theme.ns(.playlistSelection), "Selection bar falls back to the playlist selection")
    assertEqual(theme.ns(.selectionText), theme.ns(.windowText), "Selection text falls back to window text")
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

testGroup("Real bitrate in the kbps field") {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")
    let wav = try makeTestWAV(named: "bitrate.wav", seconds: 1.0)
    let pcm = AudioEngine.fileBitrate(wav, duration: 1.0)
    assertTrue(pcm >= 700, "16-bit PCM WAV is not clamped to 320 (\(pcm) kbps)")
    let mp2 = AudioEngine.fileBitrate(fixtures.appendingPathComponent("tone.mp2"), duration: 1.0)
    assertTrue(mp2 > 0 && mp2 <= 384, "MP2 keeps its coded bitrate (\(mp2) kbps)")
    assertEqual(String(String(format: "%3d", 1411).prefix(3)), "141", "Four digits cut to the 3-character field")
    assertEqual(String(String(format: "%3d", 96).prefix(3)), " 96", "Short rates right-aligned")
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

testGroup("File types: Associate with audio CDs") {
    assertTrue(!AppState().playInsertedAudioCDs, "Off by default: inserting a CD doesn't start MacAmp playback")
    // A volume that isn't an audio CD is ignored even with the option on
    let before = PlayerCoordinator.shared.playlist.tracks.count
    PersistenceManager.shared.state.playInsertedAudioCDs = true
    PlayerCoordinator.shared.audioCDMounted(FileManager.default.temporaryDirectory)
    PersistenceManager.shared.state.playInsertedAudioCDs = false
    assertEqual(PlayerCoordinator.shared.playlist.tracks.count, before, "Data volumes don't touch the playlist")
}

testGroup("Visualization refresh rate") {
    // Analysis frames every 1/43 s for 10 s, drawn at the chosen rate on average
    for fps in [35.0, 20.0, 10.0] {
        var throttle = VisualizerThrottle()
        var drawn = 0
        var frames: Float = 0
        for i in 0..<430 {
            let (draw, n) = throttle.shouldDraw(at: Double(i) / 43, fps: fps)
            if draw { drawn += 1; frames += n }
        }
        assertTrue(abs(Double(drawn) / 10 - fps) <= 1.5, "\(Int(fps)) fps chosen, \(Double(drawn) / 10) drawn")
        assertTrue(abs(frames - 430) < 20, "Falloff still covers every analysis frame (\(frames))")
    }
    var full = VisualizerThrottle()
    assertTrue((0..<43).allSatisfy { full.shouldDraw(at: Double($0) / 43, fps: 43).draw }, "At the analysis rate every frame draws")
    assertEqual(AppState().visualizerFPS, 35, "2.95 default")
}

testGroup("Preferences ▸ Skins (2.95 page)") {
    assertTrue(SkinManager.skinDescription(of: nil).contains("base skin"), "Base skin described")
    // A skin archive with its author's readme and a config .txt
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/skins-\(UUID().uuidString)", isDirectory: true)
    let src = dir.appendingPathComponent("src", isDirectory: true)
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try "Cool Skin v1.0 by Someone".write(to: src.appendingPathComponent("README.TXT"), atomically: true, encoding: .utf8)
    try "[Text]\nNormal=#00FF00".write(to: src.appendingPathComponent("pledit.txt"), atomically: true, encoding: .utf8)
    let skin = dir.appendingPathComponent("Cool.wsz")
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = src
    zip.arguments = ["-q", skin.path, "README.TXT", "pledit.txt"]
    try zip.run(); zip.waitUntilExit()
    assertEqual(SkinManager.skinDescription(of: skin), "Cool Skin v1.0 by Someone", "Description is the skin's readme, not its config")
    // "Set skins directory...": the list comes from that folder
    let previous = PersistenceManager.shared.state.skinsDirectoryPath
    PersistenceManager.shared.state.skinsDirectoryPath = dir.path
    assertEqual(SkinManager.shared.installedSkins().map(\.lastPathComponent), ["Cool.wsz"], "Skins listed from the chosen folder")
    PersistenceManager.shared.state.skinsDirectoryPath = previous
}

testGroup("About: Keyboard shortcuts tab") {
    let all = AboutShortcuts.sections.flatMap(\.rows)
    assertEqual(AboutShortcuts.sections.count, 7, "2.95 sections plus Library and Video")
    for keys in ["⌥L", "⌥T", "⌥V", "⌃Tab", "F1", "⌥3"] { assertTrue(all.contains { $0.keys == keys || $0.keys.hasPrefix(keys + " ") }, "\(keys) listed") }
    assertTrue(!all.contains { $0.keys.contains("Ctrl") || $0.keys.contains("Alt+") }, "Mac notation only")
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

testGroup("Audio CD: Disc ID, MusicBrainz, Ripping") {
    // Real MusicBrainz disc (Air - Moon Safari)
    let offsets = [150, 32344, 54804, 75002, 91984, 111389, 123113, 141227, 157807, 183275]
    assertEqual(AudioCD.discID(first: 1, last: 10, leadout: 197363, offsets: offsets), "0x8vKwUf5D5BZmJpUrvw.hB02js-", "MusicBrainz Disc ID")

    // .TOC.plist: LBA starts (track 1 at 0) get the 150-sector lead-in; the data track of an enhanced CD is left out
    let plist: [String: Any] = ["Sessions": [
        ["Session Number": 1, "First Track": 1, "Last Track": 2, "Leadout Block": 30000,
         "Track Array": [["Point": 1, "Start Block": 0, "Data": false], ["Point": 2, "Start Block": 15000, "Data": false]]],
        ["Session Number": 2, "First Track": 3, "Last Track": 3, "Leadout Block": 90000,
         "Track Array": [["Point": 3, "Start Block": 41400, "Data": true]]]]]
    let toc = AudioCD.parseTOC(plist)
    assertEqual(toc?.offsets ?? [], [150, 15150], "Offsets with lead-in")
    assertEqual(toc?.leadout ?? 0, 30150, "Lead-out of the audio session")
    assertEqual(toc?.last ?? 0, 2, "Data track left out")

    // A fake disc folder: two tracks plus the TOC
    let disc = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/FakeCD", isDirectory: true)
    try? FileManager.default.removeItem(at: disc)
    try FileManager.default.createDirectory(at: disc, withIntermediateDirectories: true)
    let src = try makeTestWAV(named: "cd-src.wav", seconds: 1.0)
    for n in 1...2 { try FileManager.default.copyItem(at: src, to: disc.appendingPathComponent("\(n) Audio Track.wav")) }
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: disc.appendingPathComponent(".TOC.plist"))
    guard var cd = AudioCD(volume: disc) else { assertTrue(false, "Fake CD readable"); return }
    assertEqual(cd.tracks.map(\.title), ["Track 1", "Track 2"], "Untitled tracks")
    assertEqual(cd.tracks.first?.length ?? 0, 200, "Track length from the TOC (15000 / 75)")

    // MusicBrainz answer (trimmed): the medium with this disc's ID, track artists with join phrases
    let mb = """
    {"releases":[{"title":"Moon Safari","date":"1998-01-19","artist-credit":[{"name":"Air","joinphrase":""}],
      "media":[{"discs":[{"id":"\(cd.discID)"}],"tracks":[
        {"position":1,"title":"La Femme d’argent","artist-credit":[{"name":"Air","joinphrase":""}]},
        {"position":2,"title":"All I Need","artist-credit":[{"name":"Air","joinphrase":" feat. "},{"name":"Beth Hirsch","joinphrase":""}]}]}]}]}
    """
    cd = cd.applying(musicBrainz: Data(mb.utf8))
    assertEqual([cd.artist, cd.album, cd.year], ["Air", "Moon Safari", "1998"], "Album from MusicBrainz")
    assertEqual(cd.tracks.map(\.title), ["La Femme d’argent", "All I Need"], "Track names")
    assertEqual(cd.tracks.last?.artist, "Air feat. Beth Hirsch", "Track artist with join phrase")
    assertEqual(cd.applying(musicBrainz: Data("{}".utf8)).album, "Moon Safari", "Unknown answer keeps what we have")

    // Naming template
    assertEqual(cd.ripName(for: cd.tracks[0], template: "<Artist> - <Album>/<#> - <Title>"), "Air - Moon Safari/01 - La Femme d’argent", "Default template")
    var odd = cd; odd.album = "AC/DC: Live"
    assertEqual(odd.ripName(for: cd.tracks[0], template: "<album>/<#>"), "AC-DC- Live/01", "Slashes and colons in names never make folders")

    // Rip to FLAC and Apple Lossless, with tags read back
    let out = disc.deletingLastPathComponent().appendingPathComponent("Ripped", isDirectory: true)
    try? FileManager.default.removeItem(at: out)
    for format in [DiskWriterFormat.flac, .alac] {
        let files = awaitValue { (try? await cd.rip([1, 2], to: out, template: "<Artist> - <Album>/<#> - <Title>", format: format, writeTags: true) { _, _ in })?.written ?? [] }
        assertEqual(files.map(\.lastPathComponent), ["01 - La Femme d’argent", "02 - All I Need"].map { $0 + "." + format.fileExtension }, "\(format) files")
        assertEqual(files.first?.deletingLastPathComponent().lastPathComponent, "Air - Moon Safari", "\(format) album folder")
        guard let file = files.last else { continue }
        assertTrue((try? AVAudioFile(forReading: file).length) ?? 0 > 40000, "\(format) still decodes after tagging")
        let meta = awaitValue { await AudioMetadataService.shared.readMetadata(from: file) }
        assertEqual([meta.id3v2.artist, meta.id3v2.title, meta.id3v2.album], ["Air feat. Beth Hirsch", "All I Need", "Moon Safari"], "\(format) tags")
        if format == .flac { assertEqual([meta.id3v2.year, meta.id3v2.trackNumber], ["1998", "2/2"], "FLAC year and track number read back") }
    }
    assertEqual(PrefTreeItem.cdRipping.parent, .options, "CD Ripping page under Options")

    // A track that can't be read is skipped, the rest of the disc is ripped
    var damaged = cd
    damaged.tracks[0] = AudioCD.Track(number: 1, url: disc.appendingPathComponent("missing.aiff"), title: "Gone", artist: "Air", length: 200)
    let partial = awaitValue { try? await damaged.rip([1, 2], to: out, template: "x/<#>", format: .wav, writeTags: false) { _, _ in } }
    assertEqual(partial?.written.map(\.lastPathComponent) ?? [], ["02.wav"], "Readable tracks still ripped")
    assertEqual(partial?.failed ?? [], [1], "Unreadable track reported")
    // Ripping the same track again replaces the file instead of adding "(2)" copies
    let again = awaitValue { try? await damaged.rip([2], to: out, template: "x/<#>", format: .wav, writeTags: false) { _, _ in } }
    assertEqual(again?.written.map(\.lastPathComponent) ?? [], ["02.wav"], "Re-rip keeps the name")
    let ripped = (try? FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("x").path)) ?? []
    assertEqual(ripped.sorted(), ["02.wav"], "No duplicate or partial files left")
    // While a disc is ripped, its tracks don't play
    AudioCD.ripping.insert(disc.standardizedFileURL.path)
    assertTrue(AudioCD.isRipping(cd.tracks[0].url), "Disc marked as ripping")
    AudioCD.ripping.removeAll()
    assertTrue(!AudioCD.isRipping(cd.tracks[0].url), "Disc free again")

    // Playing an untagged CD track keeps its MusicBrainz name; tagged files still show their tags
    let cdURL = URL(fileURLWithPath: "/Volumes/Moon Safari/1 Audio Track.aiff")
    let entry = TrackItem(url: cdURL, title: "La Femme d’argent", artist: "Air", duration: 200)
    func meta(_ title: String, _ artist: String) -> TrackMetadata {
        TrackMetadata(url: cdURL, title: title, artist: artist, duration: 200, bitrate: 1411, sampleRate: 44100, audioMode: .stereo)
    }
    let c = PlayerCoordinator.shared
    assertEqual(c.trackTags(meta("1 Audio Track", ""), for: entry).title, "La Femme d’argent", "Untagged file keeps the entry's name")
    assertEqual(c.trackTags(meta("Sexy Boy", "Air"), for: entry).title, "Sexy Boy", "Tags still win")
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

print("\n🎉 ALL PHASE 2 VERIFICATION TESTS PASSED SUCCESSFULLY! 🎉\n")
