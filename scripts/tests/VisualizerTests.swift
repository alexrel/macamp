import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func visualizerTests() {
    // 6. Retro Visualizer Studio Mode & Presets Tests
    testGroup("Retro Visualizer Studio & Presets") {
        let presets = StudioVisualizerPreset.allCases
        assertEqual(presets.count, 7, "Studio has 5 retro presets plus MilkDrop and GOOM")
        assertEqual(presets[0].title, "Fire Spectrum & Peak Glow", "Preset 0 title matches")
        assertEqual(presets[1].title, "Retro Phosphor CRT Oscilloscope", "Preset 1 title matches")
        assertEqual(presets[2].title, "Neon Cyber City Spectrum", "Preset 2 title matches")
        assertEqual(presets[3].title, "Matrix Digital Rain", "Preset 3 title matches")
        assertEqual(presets[4].title, "Solar Radial Orb", "Preset 4 title matches")
        assertEqual(presets[5].title, "Milkdrop (projectM)", "Preset 5 title matches")
        assertEqual(presets[6].title, "What A Goom!", "Preset 6 title matches")

        // Dockable Winamp windows: main, equalizer, playlist and the Media Library
        let windowIDs = WindowID.allCases
        assertEqual(windowIDs, [.main, .equalizer, .playlist, .library, .video, .browser], "Dockable windows")
        assertTrue(WindowID.library.keepsOwnSize && WindowID.playlist.keepsOwnSize && !WindowID.main.keepsOwnSize,
                   "Playlist and Library keep their size in Double Size mode, like Winamp")
        assertTrue(windowIDs.contains(.main), "WindowID contains .main")
        assertTrue(windowIDs.contains(.equalizer), "WindowID contains .equalizer")
        assertTrue(windowIDs.contains(.playlist), "WindowID contains .playlist")
    }

    testGroup("MilkDrop preset catalog and visualizer PCM") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = folder.appendingPathComponent("Pack", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for file in [folder.appendingPathComponent("Preset 10.milk"), nested.appendingPathComponent("Preset 2.MILK"),
                     folder.appendingPathComponent(".hidden.milk"), folder.appendingPathComponent("not-a-preset.txt")] {
            try Data().write(to: file)
        }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("directory.milk"), withIntermediateDirectories: true)
        assertEqual(MilkdropView.findPresets(in: folder).map(\.lastPathComponent), ["Preset 2.MILK", "Preset 10.milk"])

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        audio.frameLength = 2
        audio.floatChannelData![0][0] = 0.1
        audio.floatChannelData![0][1] = 0.2
        audio.floatChannelData![1][0] = 0.3
        audio.floatChannelData![1][1] = 0.4
        VisualizerPCMFeed.setActive(true)
        defer { VisualizerPCMFeed.setActive(false) }
        VisualizerPCMFeed.add(audio)
        var received: [Float] = []
        VisualizerPCMFeed.consume { received = Array(UnsafeBufferPointer(start: $0, count: $1 * 2)) }
        assertEqual(received, [0.1, 0.3, 0.2, 0.4], "Both channels reach the visualizer in frame order")
        VisualizerPCMFeed.consume { _, _ in assertTrue(false, "A snapshot must only be consumed once") }
        VisualizerPCMFeed.add(audio)
        VisualizerPCMFeed.setActive(false)
        VisualizerPCMFeed.add(audio)
        VisualizerPCMFeed.consume { _, _ in assertTrue(false, "An inactive visualizer must not receive PCM") }
    }

    testGroup("Visualizer skin mask keeps the player's corner cutouts") {
        let size = CGSize(width: 800, height: 500)
        assertTrue(RegionParser.parse(text: "").normalMask(fitting: size) == nil, "Rectangular skins need no mask")
        let region = RegionParser.parse(text: """
            [Normal]
            NumPoints=8
            PointList=5,0 270,0 275,5 275,111 270,116 5,116 0,111 0,5
            """)
        guard let mask = region.normalMask(fitting: size) else {
            assertTrue(false, "Expected the skin's outline")
            return
        }
        assertEqual(mask.boundingBox.size, size)
        for corner in [CGPoint(x: 1, y: 1), CGPoint(x: 799, y: 1), CGPoint(x: 1, y: 499), CGPoint(x: 799, y: 499)] {
            assertTrue(!mask.contains(corner), "The 5 px cutout stays transparent")
        }
        assertTrue(mask.contains(CGPoint(x: 6, y: 1)), "The corner does not grow with the window")
        assertTrue(mask.contains(CGPoint(x: 400, y: 499)), "The stretched edge stays opaque")
    }

    testGroup("Visualizer list applies changes to the highlighted row") {
        _ = NSApplication.shared
        let titles = (0..<10_000).map { "Preset \($0)" }
        let list = VisualizerSelectionList(frame: NSRect(x: 0, y: 0, width: 500, height: 300),
                                           titles: titles, selectedRow: 5_000, accessibilityLabel: "Presets")
        var selections: [Int] = []
        list.onSelectionChanged = { selections.append($0) }
        assertEqual(list.selectedRow, 5_000)
        list.moveSelection(by: -1)
        assertEqual(list.selectedRow, 4_999)
        list.moveSelection(by: 10_000)
        assertEqual(list.selectedRow, 9_999)
        list.moveSelection(by: 1)
        assertEqual(selections, [4_999, 9_999], "Selection previews immediately and only once per row change")
        list.reload(titles: titles, selectedRow: 2)
        assertEqual(list.selectedRow, 2)
        assertEqual(selections, [4_999, 9_999], "Opening or refreshing the catalog does not switch presets")
        list.reload(titles: [], selectedRow: nil)
        assertEqual(list.selectedRow, nil)
        list.reload(titles: ["Normal", "Wave"], selectedRow: nil)
        list.moveSelection(by: 1)
        assertEqual(selections, [4_999, 9_999, 0], "The first move selects the first effect when there is no previous choice")
    }

    testGroup("GOOM original engine and preferences") {
        var state = AppState()
        assertTrue(!state.goomPluginSelected, "Older sessions default to Studio")
        assertEqual(state.goomOptions, GoomOptions())
        state.goomOptions.frameRate = 15
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        assertEqual(decoded.goomOptions.frameLimit, 15)

        assertTrue(!macamp_goom_start(0, 240, false), "The engine rejects invalid dimensions")
        assertTrue(macamp_goom_start(320, 240, false), "The original engine starts")
        defer { macamp_goom_stop() }
        let samples = (0..<1024).map { sin(Float($0) / 8) }
        for effect in Int32(1)...8 {
            let rendered = samples.withUnsafeBufferPointer {
                macamp_goom_render($0.baseAddress, 512, effect, 30, "100% stereo", nil)
            }
            assertTrue(rendered != nil, "Original effect \(effect) renders")
        }
        assertTrue(macamp_goom_resize(256, 256, true), "Cube texture dimensions and CinemaScope are supported")
        assertTrue(macamp_goom_render(nil, 0, 0, -1, nil, macamp_goom_credits()) != nil, "Credits render with silent input")
    }

    testGroup("GOOM titles and manual credits") {
        _ = NSApplication.shared
        let previousOptions = PersistenceManager.shared.state.goomOptionsStorage
        PersistenceManager.shared.state.goomOptions = GoomOptions()
        defer { PersistenceManager.shared.state.goomOptionsStorage = previousOptions }
        let goom = GoomView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        for _ in 0..<105 { goom.renderFrame(playing: false, trackTitle: nil) }
        assertTrue(!goom.isShowingCredits, "Silence does not start the credits")
        goom.showCredits()
        goom.renderFrame(playing: false, trackTitle: nil)
        assertTrue(goom.isShowingCredits, "Credits still work on demand")
        goom.hideCredits()

        let title = "Калинов Мост — Вымыты дождём волосы"
        goom.renderFrame(playing: true, trackTitle: title)
        let label = goom.subviews.compactMap { $0 as? NSTextField }.first
        assertEqual(label?.stringValue, title, "The Unicode overlay preserves the original title")
        assertTrue(label?.isHidden == false, "The Unicode title is visible")
        PersistenceManager.shared.state.goomOptions.showTitle = false
        goom.renderFrame(playing: true, trackTitle: title)
        assertTrue(label?.isHidden == true, "The title setting hides the Unicode overlay as well")
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

    testGroup("Visualizer Studio works whatever the main visualizer shows") {
        // One analysis frame: a loud low band and a sine-like waveform
        let frame = VisualizerFrameBuffer()
        let slot = frame.write { spectrum, waveform in
            for i in spectrum.indices { spectrum[i] = i < 8 ? 0.9 : 0.1 }
            for i in waveform.indices { waveform[i] = sin(Float(i) / 4) }
        }
        frame.publish(slot: slot)
        // The main window's visualizer in oscilloscope / off mode doesn't compute bars: the studio can't use it
        let main = VisualizerView(); main.mode = .off
        main.update(from: frame)
        assertTrue(main.spectrumAmplitudes.allSatisfy { $0 == 0 }, "Main visualizer off: no bars (why the studio needs its own feed)")
        // The studio's own feed (always spectrum) has both bars and waveform
        let feed = PlayerCoordinator.shared.studioFeed
        feed.update(from: frame)
        assertTrue(feed.spectrumAmplitudes.first ?? 0 > 0.5, "Studio spectrum from its own feed")
        assertTrue(feed.waveformPoints.contains { abs($0) > 0.5 }, "Studio waveform from its own feed")
        assertEqual(feed.mode, .spectrum, "Feed always analyses the spectrum")
        // Cost per drawn frame (35 a second by default)
        let start = CACurrentMediaTime()
        for _ in 0..<10_000 { feed.update(from: frame) }
        let perFrame = (CACurrentMediaTime() - start) / 10_000
        print(String(format: "  studio feed: %.1f µs per frame, %.3f%% of one core at 35 fps", perFrame * 1e6, perFrame * 35 * 100))
        assertTrue(perFrame < 0.0002, "Studio feed costs under 0.2 ms a frame")
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
}
