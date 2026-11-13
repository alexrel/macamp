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

        // Dockable windows: Winamp's, and the Visualizer Studio, docked like Winamp's AVS window
        let windowIDs = WindowID.allCases
        assertEqual(windowIDs, [.main, .equalizer, .playlist, .library, .video, .browser, .studio], "Dockable windows")
        assertTrue(WindowID.studio.keepsOwnSize, "The Studio keeps its size in Double Size mode")
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
        // 0 dB is a full-scale tone and the display spans 60 dB: this half-scale one (-6 dB) stops at 0.9, short of the top
        assertTrue(abs((thin.max() ?? 0) - 0.9) < 0.04, "A -6 dB tone reaches 90% of the height (got \(thin.max() ?? 0))")

        // The tap hears the signal after the volume control: at 10% volume, gain 10 gives the same picture as at full volume
        let quiet = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1024)!
        quiet.frameLength = 1024
        for c in 0..<2 { for i in 0..<1024 { quiet.floatChannelData![c][i] = 0.1 * tone.floatChannelData![c][i] } }
        var quietBands = thin, quietWave = wave
        analyzer.analyze(buffer: quiet, gain: 10, spectrum: &quietBands, waveform: &quietWave)
        assertTrue(zip(wave, quietWave).allSatisfy { abs($0 - $1) < 0.001 }, "Oscilloscope doesn't follow the volume")
        assertTrue(zip(thin, quietBands).allSatisfy { abs($0 - $1) < 0.01 }, "Spectrum doesn't follow the volume")
        assertEqual(VisualizerOptions().scopeStyle, .line, "Oscilloscope draws lines by default, as in Winamp")
    }

    testGroup("Visualizer Studio works whatever the main visualizer shows") {
        // MilkDrop and GOOM get the samples with the volume control undone, like the spectrum and the oscilloscope
        let pcmFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 16)!
        pcm.frameLength = 16
        for c in 0..<2 { for i in 0..<16 { pcm.floatChannelData![c][i] = 0.1 } }
        VisualizerPCMFeed.setActive(true)
        VisualizerPCMFeed.add(pcm, gain: 4)
        var fed: [Float] = []
        VisualizerPCMFeed.consume { samples, count in fed = Array(UnsafeBufferPointer(start: samples, count: count * 2)) }
        VisualizerPCMFeed.setActive(false)
        assertTrue(fed.count == 32 && fed.allSatisfy { abs($0 - 0.4) < 0.0001 }, "PCM for MilkDrop / GOOM is scaled back to full volume")
        // Its window is a plain rectangle like the Library's: no main-window shape stretched over it
        let studioWindow = RetroVisualizerWindow()
        studioWindow.setFrame(NSRect(x: 0, y: 0, width: 400, height: 300), display: false)
        assertTrue(studioWindow.frameView.layer?.mask == nil, "The Studio frame has no skin region mask")

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

    testGroup("Main visualizer background: skin colours while playing, MAIN.BMP when stopped") {
        // SFCommandSkin.wsz draws a logo under the visualizer; Winamp covers it with VISCOLOR 0 and 1 during playback
        let vis = VisualizerView(frame: NSRect(x: 0, y: 0, width: 76, height: 16)) // a plain init() gives an empty frame
        func pixel(_ x: Int, _ y: Int) -> [Int] {
            let rep = vis.bitmapImageRepForCachingDisplay(in: vis.bounds)!
            vis.cacheDisplay(in: vis.bounds, to: rep)
            var p = [Int](repeating: 0, count: 4); let scale = rep.pixelsWide / Int(vis.bounds.width) // a Retina display renders 2 pixels per point
            rep.getPixel(&p, atX: x * scale, y: y * scale); return p
        }
        assertEqual(pixel(1, 0)[3], 0, "Stopped: transparent, the skin's picture shows")
        vis.update(from: VisualizerFrameBuffer()) // a frame of silence, as at the start of a track
        assertEqual(pixel(1, 0)[3], 255, "Playing: the background is filled even with no bars to draw")
        assertTrue(pixel(0, 1) != pixel(1, 1) && pixel(0, 0) == pixel(1, 0), "Dots on odd rows, every other column")

        // Oscilloscope as Winamp / Webamp draw it: silence on row 9 (off-centre) in VISCOLOR 18, full scale is 16 rows
        // either way, so a half-scale sample already reaches the top; colours go by the row
        // Five scope colours told apart by which channels are on: exact values don't survive the offscreen rendering
        let skin = SkinManager.shared.currentSkin!, skinColors = skin.visualizerColors.colors
        defer { skin.visualizerColors.colors = skinColors }
        let channels = [[1, 1, 1], [1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0]] // VISCOLOR 18...22
        for (i, c) in channels.enumerated() {
            skin.visualizerColors.colors[18 + i] = NSColor(srgbRed: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: 1)
        }
        func scopeColor(_ x: Int, _ y: Int) -> Int { 18 + (channels.firstIndex(of: pixel(x, y).prefix(3).map { $0 > 128 ? 1 : 0 }) ?? -18) }
        func lit(_ x: Int) -> [Int] { (0..<Int(vis.bounds.height)).filter { (pixel(x, $0).prefix(3).max() ?? 0) > 128 } } // brighter than the background and its dots
        vis.mode = .oscilloscope
        vis.waveformPoints = (0..<76).map { $0 < 38 ? 0 : -0.5 }
        assertTrue(lit(5) == [9] && scopeColor(5, 9) == 18, "Silence: row 9, VISCOLOR 18 (\(lit(5)), \(scopeColor(5, 9)))")
        assertTrue(lit(60) == [2] && scopeColor(60, 2) == 21, "A half-scale sample is at the top already, VISCOLOR 21 (\(lit(60)), \(scopeColor(60, 2)))")
        vis.waveformPoints = (0..<76).map { Float($0) / 76 * 0.3 } // a gentle slope down
        assertTrue((1..<76).allSatisfy { lit($0).count == 1 }, "One pixel per column on a gentle slope down")
        vis.waveformPoints = Array(repeating: 1, count: 76)
        assertEqual(lit(5), [15], "The loudest sample stays on the last row, not below the display")
        vis.waveformPoints = (0..<76).map { $0 < 38 ? 0 : 0.25 } // a step of 4 rows down
        assertEqual(lit(38), [10, 11, 12, 13], "A step down is joined without the previous point's row")

        // Windowshade strip: one point per column (the first 38), the picture squeezed into 5 rows around row 2
        vis.frame.size = NSSize(width: 38, height: 5)
        vis.waveformPoints = (0..<76).map { $0 < 19 ? 0 : $0 < 38 ? 0.4 : -1 }
        assertEqual([lit(5), lit(30), lit(37)], [[2], [4], [4]], "Silence on row 2, a 40% sample on the bottom row; point 38 and later are not shown")
        vis.frame.size = NSSize(width: 76, height: 16)
        vis.mode = .spectrum

        // Windowshade strip (38x5): the same 3 px bars as the main display, as many as fit, not 19 one-pixel ones
        vis.spectrumAmplitudes = Array(repeating: 1, count: 19)
        vis.frame.size = NSSize(width: 38, height: 5)
        let barColour = pixel(0, 4)
        assertTrue(barColour == pixel(2, 4) && barColour != pixel(3, 4) && barColour == pixel(4, 4), "Bars are 3 px wide with a 1 px gap")
        assertTrue(barColour == pixel(36, 4) && barColour == pixel(37, 4), "The 10th bar is cut by the edge")
        vis.frame.size = NSSize(width: 76, height: 16)

        vis.clear()
        assertEqual(pixel(1, 0)[3], 0, "Stopped again: transparent")
        vis.mode = .off
        vis.update(from: VisualizerFrameBuffer())
        assertEqual(pixel(1, 0)[3], 0, "Visualizer off: nothing is painted")
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
