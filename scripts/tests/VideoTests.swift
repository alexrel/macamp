import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func videoTests() {
    testGroup("Video: audio tracks and subtitles (1.1)") {
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
}
