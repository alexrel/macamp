import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func audioTests() {
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

    testGroup("Audio Output Device List") {
        AudioDeviceManager.shared.refreshDevices()
        let names = AudioDeviceManager.shared.availableDevices.map(\.name)
        assertTrue(!names.contains { $0.hasPrefix("CADefaultDeviceAggregate") }, "Core Audio private aggregate devices are hidden: \(names)")
    }

    testGroup("Ogg Vorbis / Opus Playback") {
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

    testGroup("Formats: MP2, AU, MIDI") {
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

    testGroup("Real bitrate in the kbps field") {
        let wav = try makeTestWAV(named: "bitrate.wav", seconds: 1.0)
        let pcm = AudioEngine.fileBitrate(wav, duration: 1.0)
        assertTrue(pcm >= 700, "16-bit PCM WAV is not clamped to 320 (\(pcm) kbps)")
        let mp2 = AudioEngine.fileBitrate(fixtures.appendingPathComponent("tone.mp2"), duration: 1.0)
        assertTrue(mp2 > 0 && mp2 <= 384, "MP2 keeps its coded bitrate (\(mp2) kbps)")
        assertEqual(String(String(format: "%3d", 1411).prefix(3)), "141", "Four digits cut to the 3-character field")
        assertEqual(String(String(format: "%3d", 96).prefix(3)), " 96", "Short rates right-aligned")
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

        // CD Ripping ▸ Playlist: M3U / PLS of the whole CD next to the album, relative paths, name from the template
        let flacs = ["01 - La Femme d’argent", "02 - All I Need"].map { out.appendingPathComponent("Air - Moon Safari/\($0).flac") }
        let lists = (try? cd.writeRipPlaylists(flacs, to: out, template: "<Artist> - <Album>/<Artist> - <Album>", m3u: true, extended: true, pls: true)) ?? []
        assertEqual(lists.map(\.lastPathComponent), ["Air - Moon Safari.m3u", "Air - Moon Safari.pls"], "M3U and PLS named by the template")
        let m3u = (try? String(contentsOf: lists[0], encoding: .utf8)) ?? ""
        assertTrue(m3u.hasPrefix("#EXTM3U\n#EXTINF:200,Air - La Femme d’argent\n01 - La Femme d’argent.flac\n"), "Extended M3U with relative paths")
        let reread = awaitValue { await PlaylistIO.loadPlaylist(from: lists[1]) }
        assertEqual(reread.map(\.url.lastPathComponent), flacs.map(\.lastPathComponent), "PLS reads back to the ripped files")
        _ = try? cd.writeRipPlaylists(flacs, to: out, template: "<Artist> - <Album>/<Artist> - <Album>", m3u: true, extended: false, pls: false)
        assertEqual((try? String(contentsOf: lists[0], encoding: .utf8)) ?? "", "01 - La Femme d’argent.flac\n02 - All I Need.flac\n", "Plain M3U: paths only")
        assertEqual((try? cd.writeRipPlaylists(Array(flacs.prefix(1)), to: out, template: "x", m3u: true, extended: true, pls: true))?.count ?? -1, 0, "No playlist for part of a CD")
        assertEqual(cd.ripItems(flacs).map(\.artist), ["Air", "Air feat. Beth Hirsch"], "Library playlist entries keep the disc's names")

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
}
