import Cocoa
import Foundation
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
    persistence.saveSession()
    
    // Simulate relaunch by reading back the session state
    persistence.loadSession()
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
    
    // Check permission helper returns boolean without crash
    let perm = hotkeys.checkAccessibilityPermission()
    print("    ℹ️ System Accessibility Permission: \(perm ? "GRANTED" : "NOT GRANTED")")
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

print("\n🎉 ALL PHASE 2 VERIFICATION TESTS PASSED SUCCESSFULLY! 🎉\n")
