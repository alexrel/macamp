import Cocoa
import Foundation
import AVFoundation
import Network
@testable import MacAmp

func testGroup(_ name: String, _ block: () throws -> Void) {
    print("\n📦 Test Suite: \(name)")
    do {
        try block()
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
    
    // Run loop briefly to allow async metadata callback
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    
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
    
    // Test WindowID enum cases: only main, equalizer, playlist
    let windowIDs = WindowID.allCases
    assertEqual(windowIDs.count, 3, "Only 3 main windows should exist in WindowID")
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
    assertEqual(PrefTreeItem.output.sectionHeader, "Audio", "Output sectionHeader must be 'Audio'")
    
    let vm = PreferencesViewModel()
    vm.selectedTreeItem = .output
    assertEqual(vm.selectedCategory, .audio, "Category for .output should be .audio")
    assertTrue(!vm.availableOutputDevices.isEmpty, "PreferencesViewModel should populate available devices")
    vm.selectOutputDevice(uid: nil)
    assertEqual(vm.selectedAudioOutputDeviceUID, nil, "PreferencesViewModel selects System Default")
}


// MARK: - Playback regression helpers
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
    let loaded = PlaylistIO.loadPlaylist(from: m3uURL)
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
    assertTrue(!StreamDecoder.canDecode(contentType: "application/ogg"), "Ogg goes to the AVPlayer fallback")
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
        let meta = TrackItem.resolveArtistAndTitle(from: url)
        assertEqual(meta.artist, "", "No tags: no guessed artist for '\(name)'")
        assertEqual(meta.title, name, "No tags: title is the file name")
        let item = TrackItem.create(from: url)
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

print("\n🎉 ALL PHASE 2 VERIFICATION TESTS PASSED SUCCESSFULLY! 🎉\n")
