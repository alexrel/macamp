import Foundation
import AVFoundation

public struct TrackMetadata: Equatable {
    public let url: URL
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    public let bitrate: Int
    public let sampleRate: Int
    public let audioMode: AudioChannelMode

    public init(url: URL, title: String, artist: String, duration: TimeInterval, bitrate: Int, sampleRate: Int, audioMode: AudioChannelMode) {
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.audioMode = audioMode
    }
}

/// Playback engine. Graph:
///
///     playerNode (files)  ─┐
///                          ├─ sourceMixer (fade gain + balance) ─ EQ ─ TimePitch ─ Reverb ─ mainMixer (volume) ─ output
///     streamNode (radio)  ─┘                                                                    └─ tap: spectrum / oscilloscope
///
/// Internet radio is decoded by `StreamDecoder` and played through the same graph, so EQ, DSP and the
/// visualizer work for streams too. Formats the decoder cannot handle (Ogg, HLS) fall back to `AVPlayer`.
///
/// Main-thread confined, except for the mixer tap and the stream decoding queue.
public class AudioEngine {
    public static let shared = AudioEngine()

    // AVFoundation Engine
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let streamNode = AVAudioPlayerNode()
    private let sourceMixer = AVAudioMixerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 10)
    private let timePitchNode = AVAudioUnitTimePitch()
    private let reverbNode = AVAudioUnitReverb()

    // Analysis
    private let fftAnalyzer = FFTAnalyzer(fftSize: 1024)
    public let visualizerFrame = VisualizerFrameBuffer()

    // Playback state (local files)
    private var audioFile: AVAudioFile?
    private var currentSecurityScopedURL: URL?
    private var fileDuration: TimeInterval = 0
    private var sampleRate: Double = 44100
    private var startFrameOffset: AVAudioFramePosition = 0
    private var currentTrackTime: TimeInterval = 0
    /// Invalidates completion handlers of segments scheduled before a stop/seek/new track.
    private var playbackGeneration: Int = 0
    /// Incremented on every load(); lets a superseded concurrent load bail out after its await.
    private var loadGeneration: Int = 0
    /// The scheduled segment finished while a pause fade-out was in progress; resume must advance instead.
    private var finishedWhilePaused = false

    public private(set) var status: PlayerStatus = .stopped {
        didSet {
            if oldValue != status {
                updateAnalysisTap()
                onStatusUpdate?(status)
            }
        }
    }
    public private(set) var currentMetadata: TrackMetadata?

    // Callbacks
    public var onStatusUpdate: ((PlayerStatus) -> Void)?
    public var onTimeUpdate: ((TimeInterval) -> Void)?
    public var onPlaybackFinished: (() -> Void)?
    /// Main thread, one per 1024-frame analysis window (~43 fps at 44.1 kHz); nothing while silent.
    /// Read the frame with `frame.read(spectrum:waveform:)`.
    public var onVisualizerFrame: ((VisualizerFrameBuffer) -> Void)?
    public var onMetadataUpdate: ((_ artist: String, _ title: String, _ bitrate: Int?, _ sampleRate: Int?) -> Void)?
    /// Short user-facing stream status messages ("Buffering...", "Reconnecting (1/3)...", "Stream lost").
    public var onStreamEvent: ((String) -> Void)?

    /// When false (visualizer off, windows hidden/minimized) the spectrum tap is removed entirely.
    public var isAnalysisEnabled: Bool = true {
        didSet { if oldValue != isAnalysisEnabled { updateAnalysisTap() } }
    }

    // Streaming state
    public private(set) var icySession: ICYStreamSession?
    private var streamURL: URL?
    /// AVPlayer fallback for formats StreamDecoder can't decode (no EQ/DSP/visualizer there).
    private var streamPlayer: AVPlayer?
    public var isStreaming: Bool { streamURL != nil }
    /// True when the current stream is decoded in-engine (EQ/DSP/visualizer apply); false for the AVPlayer fallback.
    public var isStreamDecodedInEngine: Bool { isStreaming && streamPlayer == nil }
    private var streamElapsed: TimeInterval = 0
    /// Bumped whenever the network session is replaced; drops deliveries from an old session.
    private var streamSessionToken: Int = 0
    /// Bumped whenever streamNode is stopped; drops completion handlers of its old buffers.
    private var streamNodeToken: Int = 0
    private var streamFormat: AVAudioFormat?
    /// Seconds of decoded audio scheduled on streamNode and not yet played back.
    public private(set) var streamBufferedSeconds: Double = 0
    private var isStreamNodeStarted = false
    /// Paused/interrupted stream: the next play() opens a fresh connection (live radio can't resume).
    private var streamNeedsRestart = false
    private var reconnectAttempts = 0
    private var reconnectWorkItem: DispatchWorkItem?
    public static let streamPrebufferSeconds: Double = 0.75
    public static let maxReconnectAttempts = 3
    public static var reconnectDelay: TimeInterval = 2.0

    // Fades
    private var fadeTimer: Timer?
    private var fadeToken: Int = 0
    private var fadeCompletion: ((Bool) -> Void)?
    private static let fadeInDuration: TimeInterval = 0.03

    // Progress tracking timer
    private var playbackTimer: Timer?
    private var isTapInstalled: Bool = false
    public private(set) var currentOutputDeviceID: AudioDeviceID? = nil

    private init() {
        setupGraph()
        setupEQ()
        setupDSP()
        setupNotifications()

        // Restore custom output device if saved in persistence
        if let savedUID = PersistenceManager.shared.state.selectedAudioOutputDeviceUID,
           let found = AudioDeviceManager.shared.availableDevices.first(where: { $0.uid == savedUID }) {
            setOutputDevice(deviceID: found.id)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        currentSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        print("AudioEngine: Received AVAudioEngineConfigurationChangeNotification (Hardware route / device change)")

        let wasPlaying = (status == .playing)
        let savedTime = currentTime

        // Refresh available audio devices in manager
        AudioDeviceManager.shared.refreshDevices()

        // Re-apply targeted device if configured, or default
        if let targetID = AudioDeviceManager.shared.activeOutputDeviceID(), let audioUnit = engine.outputNode.audioUnit {
            var devID = targetID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            currentOutputDeviceID = devID
        }

        reinstallMixerTap()

        if wasPlaying {
            ensureEngineRunning()
            resumeAfterRouteChange(at: savedTime)
        }
    }

    /// The engine drops scheduled buffers on a route change; restart whatever was playing.
    private func resumeAfterRouteChange(at savedTime: TimeInterval) {
        if isStreaming {
            if let sp = streamPlayer {
                sp.play()
            } else {
                resetStreamNode()
                startStreamSession()
            }
            startStreamTimer()
        } else if audioFile != nil {
            // seek() reschedules from savedTime and restarts the node because status is .playing
            seek(to: savedTime)
        }
    }

    // MARK: - Visualizer Tap

    public func reinstallMixerTap() {
        if isTapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        updateAnalysisTap()
    }

    /// Installs the tap only while something is playing and the visualizer needs data: 0% CPU otherwise.
    private func updateAnalysisTap() {
        let wanted = isAnalysisEnabled && status == .playing
        if wanted && !isTapInstalled {
            let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            guard tapFormat.sampleRate > 0 && tapFormat.channelCount > 0 else { return }
            let frame = visualizerFrame
            let analyzer = fftAnalyzer
            var silentWindows = 0 // tap thread only
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: AppConstants.Audio.bufferSize, format: tapFormat) { [weak self] buffer, _ in
                guard let channels = buffer.floatChannelData else { return }
                let window = analyzer.windowSize
                let frameCount = Int(buffer.frameLength)
                let windows = max(1, min(VisualizerFrameBuffer.slotCount / 2, frameCount / window))
                let windowDuration = Double(window) / buffer.format.sampleRate
                for w in 0..<windows {
                    var hasSignal = false
                    let slot = frame.write { spectrum, waveform in
                        hasSignal = analyzer.analyze(channels: channels, channelCount: Int(buffer.format.channelCount),
                                                     startFrame: w * window, frameCount: min(window, frameCount - w * window),
                                                     spectrum: &spectrum, waveform: &waveform)
                    }
                    // Keep delivering ~2 s of silence so falling bars and peaks can finish,
                    // then skip main-thread wakeups entirely until the signal returns
                    silentWindows = hasSignal ? 0 : silentWindows + 1
                    if silentWindows > 90 { continue }
                    // Spread the windows over the buffer's duration so the display moves with the audio
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(w) * windowDuration) {
                        frame.publish(slot: slot)
                        guard let self else { return }
                        self.onVisualizerFrame?(frame)
                    }
                }
            }
            isTapInstalled = true
        } else if !wanted && isTapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            isTapInstalled = false
            visualizerFrame.clear()
            // One final (zeroed) frame so the display empties instead of freezing
            onVisualizerFrame?(visualizerFrame)
        }
    }

    public var isAnalysisTapInstalled: Bool { isTapInstalled }

    private func setupGraph() {
        engine.attach(playerNode)
        engine.attach(streamNode)
        engine.attach(sourceMixer)
        engine.attach(eqNode)
        engine.attach(timePitchNode)
        engine.attach(reverbNode)

        engine.connect(playerNode, to: sourceMixer, fromBus: 0, toBus: 0, format: nil)
        // streamNode is connected to bus 1 once the stream's decoded format is known
        engine.connect(sourceMixer, to: eqNode, format: nil)
        // EQ -> [TimePitch] -> [Reverb] -> mainMixer: DSP nodes are wired in only while active (see rewireDSPChain)
        engine.connect(eqNode, to: engine.mainMixerNode, format: nil)

        // Started on first play, paused again when idle: a running engine renders silence through
        // EQ/TimePitch/Reverb non-stop (~5% CPU on Apple Silicon) even with nothing playing.
        engine.prepare()
    }
    
    @discardableResult
    private func ensureEngineRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            print("AudioEngine: Failed to start AVAudioEngine: \(error)")
            return false
        }
    }
    
    /// Pauses the audio I/O while nothing is audible, so a paused/stopped player uses 0% CPU.
    private func idleEngineIfQuiet() {
        guard status != .playing, engine.isRunning else { return }
        engine.pause()
    }
    
    public var isEngineRunning: Bool { engine.isRunning }

    private func setupEQ() {
        let freqs = AppConstants.Equalizer.bandFrequencies
        for (i, freq) in freqs.enumerated() {
            let band = eqNode.bands[i]
            band.frequency = Float(freq)
            band.filterType = .parametric
            band.bandwidth = 1.0
            band.gain = 0.0
            band.bypass = false
        }
        eqNode.globalGain = 0.0
        eqNode.bypass = false
    }

    private func setupDSP() {
        timePitchNode.pitch = 0.0
        timePitchNode.rate = 1.0
        reverbNode.loadFactoryPreset(.mediumRoom)
        reverbNode.wetDryMix = 0.0
        updateDSPBypass()
    }
    
    /// DSP "Enable" switch from Preferences
    private var isDspEnabled = false
    
    /// DSP nodes currently wired into the graph
    private var wiredTimePitch = false
    private var wiredReverb = false
    
    /// TimePitch and Reverb are only in the signal path when enabled and actually doing something.
    /// A bypassed AVAudioUnitReverb still costs ~2% CPU on an M1, so inactive nodes are unplugged entirely.
    private func updateDSPBypass() {
        let neutralTimePitch = abs(timePitchNode.pitch) < 0.5 && abs(timePitchNode.rate - 1.0) < 0.001
        timePitchNode.bypass = !isDspEnabled || neutralTimePitch
        reverbNode.bypass = !isDspEnabled || reverbNode.wetDryMix <= 0.001
        rewireDSPChain(timePitch: !timePitchNode.bypass, reverb: !reverbNode.bypass)
    }
    
    private func rewireDSPChain(timePitch: Bool, reverb: Bool) {
        guard timePitch != wiredTimePitch || reverb != wiredReverb else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeOutput(timePitchNode)
        engine.disconnectNodeOutput(reverbNode)
        var chain: [AVAudioNode] = [eqNode]
        if timePitch { chain.append(timePitchNode) }
        if reverb { chain.append(reverbNode) }
        chain.append(engine.mainMixerNode)
        for i in 0..<(chain.count - 1) {
            engine.connect(chain[i], to: chain[i + 1], format: nil)
        }
        wiredTimePitch = timePitch
        wiredReverb = reverb
        if wasRunning { ensureEngineRunning() }
    }
    
    /// Applies persisted DSP settings (called once at startup).
    public func applyDSP(enabled: Bool, pitchSemitones: Double, rate: Double, reverbMix: Double, reverbPreset: Int) {
        setReverbPreset(index: reverbPreset)
        timePitchNode.pitch = Float(pitchSemitones * 100.0)
        timePitchNode.rate = Float(max(0.5, min(2.0, rate)))
        reverbNode.wetDryMix = Float(max(0.0, min(100.0, reverbMix)))
        isDspEnabled = enabled
        updateDSPBypass()
    }

    // MARK: - Fades

    private var fadeOutDuration: TimeInterval {
        max(0, PersistenceManager.shared.state.audioFadeOutDurationMs) / 1000.0
    }

    /// Current source gain used for fades (exposed for tests).
    public var fadeGain: Float { sourceMixer.outputVolume }

    /// Ramps the source gain (independent of the user's volume). A newer fade supersedes an older one,
    /// whose completion is then called with `false`.
    private func fade(to target: Float, duration: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        let superseded = fadeCompletion
        fadeCompletion = nil
        fadeToken += 1
        superseded?(false)

        guard duration > 0.001 else {
            sourceMixer.outputVolume = target
            completion?(true)
            return
        }

        let token = fadeToken
        let start = sourceMixer.outputVolume
        let begin = Date()
        fadeCompletion = completion
        let timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] timer in
            guard let self, self.fadeToken == token else {
                timer.invalidate()
                return
            }
            let progress = min(1.0, Date().timeIntervalSince(begin) / duration)
            // Smoothstep: no slope discontinuity at either end, so no audible "corner"
            let eased = Float(progress * progress * (3 - 2 * progress))
            self.sourceMixer.outputVolume = start + (target - start) * eased
            if progress >= 1.0 {
                timer.invalidate()
                self.fadeTimer = nil
                let done = self.fadeCompletion
                self.fadeCompletion = nil
                done?(true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    /// Short anti-click fade-in from silence when starting a source.
    private func fadeInFromSilence() {
        sourceMixer.outputVolume = 0
        fade(to: 1.0, duration: AudioEngine.fadeInDuration)
    }

    private func fadeOutAsync(duration: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            fade(to: 0, duration: duration) { _ in continuation.resume() }
        }
    }

    // MARK: - Track Loading
    @MainActor
    public func load(url: URL) async throws -> TrackMetadata {
        loadGeneration += 1
        let loadToken = loadGeneration

        // Track change: quick fade so the old track doesn't end with a click
        if status == .playing && fadeOutDuration > 0 {
            await fadeOutAsync(duration: min(0.08, fadeOutDuration))
            guard loadToken == loadGeneration else { throw CancellationError() }
        }

        // Loading a new track always ends the previous one; otherwise a paused segment of the
        // old file would be resumed by play() instead of the new track.
        teardownCurrentSource()
        if status != .stopped {
            status = .stopped
        }

        if let old = currentSecurityScopedURL {
            old.stopAccessingSecurityScopedResource()
            currentSecurityScopedURL = nil
        }
        if url.isFileURL && url.startAccessingSecurityScopedResource() {
            currentSecurityScopedURL = url
        }

        // Remote Audio / SHOUTcast / Icecast stream handling
        if !url.isFileURL {
            // Resolve direct stream endpoint if URL is a .pls or .m3u
            let resolvedURL = await ICYStreamSession.resolveStreamURL(from: url)
            guard loadToken == loadGeneration else { throw CancellationError() }

            self.streamURL = resolvedURL
            self.streamElapsed = 0
            self.fileDuration = 0
            self.currentTrackTime = 0
            self.reconnectAttempts = 0
            startStreamSession()

            let fallbackTitle = resolvedURL.lastPathComponent.isEmpty ? (resolvedURL.host ?? "Internet Radio") : resolvedURL.lastPathComponent
            let meta = TrackMetadata(
                url: url,
                title: fallbackTitle,
                artist: "Internet Stream",
                duration: 0,
                bitrate: 128,
                sampleRate: 44,
                audioMode: .stereo
            )
            self.currentMetadata = meta
            return meta
        }

        // Local audio file
        let localURL = url
        let file = try AVAudioFile(forReading: localURL)

        var duration: TimeInterval = 0
        if file.processingFormat.sampleRate > 0 && file.length > 0 {
            duration = Double(file.length) / file.processingFormat.sampleRate
        }

        // Extract metadata and duration asynchronously using unified TrackItem resolver
        let (resolvedDur, artist, title) = await TrackItem.resolveMetadataAsync(from: localURL)
        guard loadToken == loadGeneration else { throw CancellationError() }
        if resolvedDur > 0 {
            duration = resolvedDur
        }

        self.audioFile = file
        self.sampleRate = file.processingFormat.sampleRate

        // Untagged file: empty artist, title = file name (same as the playlist shows it)
        let finalTitle = title
        let finalArtist = artist

        let channels = file.processingFormat.channelCount
        let channelMode: AudioChannelMode = channels > 1 ? .stereo : .mono
        let approxBitrate = duration > 0 ? Int((Double(file.length * 2 * Int64(channels)) / duration) * 8 / 1000) : 128

        self.fileDuration = duration

        let meta = TrackMetadata(
            url: url,
            title: finalTitle,
            artist: finalArtist,
            duration: duration,
            bitrate: max(128, min(320, approxBitrate)),
            sampleRate: Int(sampleRate / 1000),
            audioMode: channelMode
        )
        self.currentMetadata = meta
        return meta
    }

    /// Stops and forgets the current file or stream source (no status change, no fade).
    private func teardownCurrentSource() {
        playbackGeneration += 1
        finishedWhilePaused = false
        playerNode.stop()
        audioFile = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        startFrameOffset = 0
        currentTrackTime = 0
        teardownStream()
    }

    public func updateCurrentMetadata(title: String, artist: String, bitrate: Int? = nil, sampleRate: Int? = nil) {
        guard let old = currentMetadata else { return }
        currentMetadata = TrackMetadata(
            url: old.url,
            title: title,
            artist: artist,
            duration: old.duration,
            bitrate: bitrate ?? old.bitrate,
            sampleRate: sampleRate ?? old.sampleRate,
            audioMode: old.audioMode
        )
    }

    // MARK: - Internet Radio

    /// Opens (or re-opens) the network connection for `streamURL` and starts feeding the decoder.
    private func startStreamSession() {
        guard let url = streamURL else { return }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        icySession?.stop()
        streamSessionToken += 1
        let token = streamSessionToken
        streamNeedsRestart = false

        let session = ICYStreamSession(url: url)
        icySession = session

        session.onMetadataUpdate = { [weak self] artist, title, bitrate, sampleRate in
            guard let self, self.streamSessionToken == token else { return }
            self.updateCurrentMetadata(title: title, artist: artist, bitrate: bitrate, sampleRate: sampleRate)
            self.onMetadataUpdate?(artist, title, bitrate, sampleRate)
        }

        if streamPlayer == nil {
            // Decoder lives on the session's serial delegate queue
            final class DecoderBox { var decoder: StreamDecoder?; var failed = false }
            let box = DecoderBox()
            session.onAudioData = { [weak self, weak session] data in
                guard !box.failed else { return }
                if box.decoder == nil {
                    let contentType = session?.contentType
                    guard StreamDecoder.canDecode(contentType: contentType),
                          let decoder = try? StreamDecoder(contentType: contentType) else {
                        box.failed = true
                        DispatchQueue.main.async { self?.fallBackToAVPlayer(token: token) }
                        return
                    }
                    decoder.onFormatReady = { format in
                        DispatchQueue.main.async { self?.connectStreamNode(format: format, token: token) }
                    }
                    decoder.onBuffer = { buffer in
                        DispatchQueue.main.async { self?.scheduleStreamBuffer(buffer, token: token) }
                    }
                    box.decoder = decoder
                }
                do {
                    try box.decoder?.feed(data)
                } catch {
                    box.failed = true
                    DispatchQueue.main.async { self?.fallBackToAVPlayer(token: token) }
                }
            }
        }

        session.onFinished = { [weak self] error in
            DispatchQueue.main.async { self?.handleStreamFinished(error: error, token: token) }
        }
        session.start()

        if streamPlayer == nil && status == .playing {
            onStreamEvent?("Buffering...")
        }
    }

    private func connectStreamNode(format: AVAudioFormat, token: Int) {
        guard token == streamSessionToken else { return }
        if streamFormat != format {
            // A different format can't be appended to buffers already queued on the node
            resetStreamNode()
            engine.disconnectNodeOutput(streamNode)
            engine.connect(streamNode, to: sourceMixer, fromBus: 0, toBus: 1, format: format)
            streamFormat = format
        }
    }

    private func scheduleStreamBuffer(_ buffer: AVAudioPCMBuffer, token: Int) {
        guard token == streamSessionToken, streamFormat == buffer.format else { return }
        reconnectAttempts = 0
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        let nodeToken = streamNodeToken
        streamBufferedSeconds += seconds
        streamNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.streamNodeToken == nodeToken else { return }
                self.streamBufferedSeconds = max(0, self.streamBufferedSeconds - seconds)
            }
        }
        startStreamNodeIfReady()
    }

    private func startStreamNodeIfReady() {
        guard status == .playing, !isStreamNodeStarted, streamBufferedSeconds >= AudioEngine.streamPrebufferSeconds else { return }
        ensureEngineRunning()
        streamNode.play()
        isStreamNodeStarted = true
        fadeInFromSilence()
    }

    /// Drops everything queued on streamNode.
    private func resetStreamNode() {
        streamNodeToken += 1
        streamNode.stop()
        streamBufferedSeconds = 0
        isStreamNodeStarted = false
    }

    private func teardownStream() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        streamSessionToken += 1
        icySession?.stop()
        icySession = nil
        streamPlayer?.pause()
        streamPlayer = nil
        resetStreamNode()
        streamURL = nil
        streamElapsed = 0
        streamNeedsRestart = false
    }

    private func handleStreamFinished(error: Error?, token: Int) {
        guard token == streamSessionToken, isStreaming else { return }
        guard status == .playing else {
            // Connection ended before Play (between load() and play()) or while paused: reconnect on play()
            streamNeedsRestart = true
            return
        }

        guard reconnectAttempts < AudioEngine.maxReconnectAttempts else {
            print("AudioEngine: stream lost after \(reconnectAttempts) reconnect attempts: \(String(describing: error))")
            onStreamEvent?("Stream lost")
            stopInternal(fade: false)
            return
        }
        reconnectAttempts += 1
        onStreamEvent?("Reconnecting (\(reconnectAttempts)/\(AudioEngine.maxReconnectAttempts))...")
        // Buffered audio keeps playing while we wait; the new session appends to the same node
        let work = DispatchWorkItem { [weak self] in
            guard let self, token == self.streamSessionToken, self.status == .playing else { return }
            self.startStreamSession()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AudioEngine.reconnectDelay, execute: work)
    }

    /// Ogg/Opus/HLS and other formats AudioFileStream can't parse: play via AVPlayer (bypasses EQ/DSP/visualizer).
    private func fallBackToAVPlayer(token: Int) {
        guard token == streamSessionToken, let url = streamURL, streamPlayer == nil else { return }
        print("AudioEngine: stream format not decodable in-engine, falling back to AVPlayer for \(url)")
        resetStreamNode()
        // Keep the ICY session for metadata only
        icySession?.onAudioData = nil
        let player = AVPlayer(url: url)
        player.volume = engine.mainMixerNode.outputVolume
        streamPlayer = player
        if status == .playing {
            player.play()
        }
    }

    // MARK: - Playback Control
    public func play() {
        if isStreaming {
            if status == .playing { return }
            status = .playing
            startStreamTimer()
            if let sp = streamPlayer {
                sp.play()
            } else if streamNeedsRestart || icySession == nil {
                resetStreamNode()
                startStreamSession()
            } else {
                startStreamNodeIfReady()
            }
            return
        }

        guard let file = audioFile else { return }

        // Resuming from pause: unpause the node (or, if the pause fade is still running, just cancel it)
        if status == .paused {
            ensureEngineRunning()
            status = .playing
            if finishedWhilePaused {
                finishedWhilePaused = false
                handlePlaybackCompletion()
                return
            }
            playerNode.play()
            fade(to: 1.0, duration: AudioEngine.fadeInDuration)
            startTimer()
            return
        }

        playbackGeneration += 1
        let gen = playbackGeneration
        finishedWhilePaused = false

        playerNode.stop()
        ensureEngineRunning()

        let totalFrames = (file.length > 0) ? file.length : AVAudioFramePosition(fileDuration * sampleRate)
        let startFrame = AVAudioFramePosition(max(0, min(currentTrackTime, fileDuration)) * sampleRate)
        let frameCount = AVAudioFrameCount(max(0, totalFrames - startFrame))
        guard frameCount > 0 else {
            handlePlaybackCompletion()
            return
        }

        startFrameOffset = startFrame
        scheduleFileSegment(file, from: startFrame, frames: frameCount, generation: gen)

        sourceMixer.outputVolume = 0
        playerNode.play()
        status = .playing
        fade(to: 1.0, duration: AudioEngine.fadeInDuration)
        startTimer()
    }

    private func scheduleFileSegment(_ file: AVAudioFile, from startFrame: AVAudioFramePosition, frames: AVAudioFrameCount, generation gen: Int) {
        // .dataPlayedBack: fire when the audio has actually been heard, not merely read from disk
        // (otherwise short files "finish" immediately and long ones lose their tail).
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.playbackGeneration == gen else { return }
                self.handlePlaybackCompletion()
            }
        }
    }

    public func pause() {
        guard status == .playing else { return }
        let duration = fadeOutDuration

        if isStreaming {
            status = .paused
            playbackTimer?.invalidate()
            playbackTimer = nil
            onTimeUpdate?(streamElapsed)
            let sessionToken = streamSessionToken
            fade(to: 0, duration: duration) { [weak self] finished in
                guard let self, finished, self.status == .paused, self.streamSessionToken == sessionToken else { return }
                // Live radio can't be resumed from where it stopped: drop the connection and reconnect on play()
                if let sp = self.streamPlayer {
                    sp.pause()
                } else {
                    self.streamSessionToken += 1
                    self.icySession?.stop()
                    self.resetStreamNode()
                    self.streamNeedsRestart = true
                }
                self.idleEngineIfQuiet()
            }
            return
        }

        // Keep playbackGeneration unchanged: the scheduled segment stays valid across pause/resume,
        // and its completion handler must still advance to the next track.
        let gen = playbackGeneration
        currentTrackTime = currentTime
        status = .paused
        playbackTimer?.invalidate()
        playbackTimer = nil
        onTimeUpdate?(currentTrackTime)

        fade(to: 0, duration: duration) { [weak self] finished in
            guard let self, finished, self.status == .paused, self.playbackGeneration == gen else { return }
            // The node kept playing during the fade; remember where it really stopped
            self.currentTrackTime = self.nodePlaybackTime() ?? self.currentTrackTime
            self.playerNode.pause()
            self.onTimeUpdate?(self.currentTrackTime)
            self.idleEngineIfQuiet()
        }
    }

    public func togglePause() {
        if status == .playing {
            pause()
        } else if status == .paused {
            play()
        }
    }

    public var currentTime: TimeInterval {
        if isStreaming {
            return streamElapsed
        }
        if status == .paused {
            return currentTrackTime
        }
        guard status == .playing else { return 0 }
        return nodePlaybackTime() ?? currentTrackTime
    }

    /// Position of the file player node, in seconds of the file's timeline.
    private func nodePlaybackTime() -> TimeInterval? {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else {
            return nil
        }
        // playerTime counts in the node's output rate, which can differ from the file's rate (44.1k file on a 48k device)
        let played = Double(playerTime.sampleTime) / playerTime.sampleRate
        let calculated = Double(startFrameOffset) / sampleRate + played
        return max(0, min(calculated, fileDuration))
    }

    public var volume: Double {
        Double(engine.mainMixerNode.outputVolume)
    }

    public func stop() {
        stopInternal(fade: true)
    }

    /// Winamp "Stop w/ fadeout" (Shift+V): stops with a long fade instead of the short anti-click one.
    public func stop(fadeOutDuration: TimeInterval) {
        stopInternal(fade: true, duration: fadeOutDuration)
    }

    /// - Parameter fade: fade out before silencing the node (user Stop), or cut immediately (track ended, errors).
    /// - Parameter duration: fade length; defaults to the "Fade out on Pause/Stop" preference.
    private func stopInternal(fade shouldFade: Bool, duration: TimeInterval? = nil) {
        let wasPlaying = (status == .playing)
        playbackGeneration += 1
        let gen = playbackGeneration
        finishedWhilePaused = false
        playbackTimer?.invalidate()
        playbackTimer = nil

        let fadeDuration = (shouldFade && wasPlaying) ? (duration ?? fadeOutDuration) : 0

        if isStreaming {
            let nodeToken = streamNodeToken
            // Network and state go away now; the already-queued audio fades out on its own
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            streamSessionToken += 1
            icySession?.stop()
            icySession = nil
            let player = streamPlayer
            streamPlayer = nil
            streamURL = nil
            streamElapsed = 0
            streamNeedsRestart = false
            status = .stopped
            onTimeUpdate?(0)
            fade(to: 0, duration: fadeDuration) { [weak self] _ in
                player?.pause()
                guard let self, self.streamNodeToken == nodeToken else { return }
                self.resetStreamNode()
                self.idleEngineIfQuiet()
            }
            return
        }

        status = .stopped
        startFrameOffset = 0
        currentTrackTime = 0
        onTimeUpdate?(0)

        fade(to: 0, duration: fadeDuration) { [weak self] _ in
            // Skip if play()/seek()/load() already took over the node
            guard let self, self.playbackGeneration == gen else { return }
            self.playerNode.stop()
            self.idleEngineIfQuiet()
        }
    }

    public func seek(to time: TimeInterval) {
        guard !isStreaming else { return }
        guard let file = audioFile else { return }
        let clampedTime = max(0, min(time, fileDuration))
        currentTrackTime = clampedTime

        playbackGeneration += 1
        let gen = playbackGeneration
        finishedWhilePaused = false
        playerNode.stop()

        let totalFrames = (file.length > 0) ? file.length : AVAudioFramePosition(fileDuration * sampleRate)
        let targetFrame = AVAudioFramePosition(clampedTime * sampleRate)
        let frameCount = AVAudioFrameCount(max(0, totalFrames - targetFrame))
        startFrameOffset = targetFrame

        if frameCount > 0 {
            scheduleFileSegment(file, from: targetFrame, frames: frameCount, generation: gen)
        }

        if status == .playing {
            if frameCount > 0 {
                ensureEngineRunning()
                playerNode.play()
                fade(to: 1.0, duration: AudioEngine.fadeInDuration)
                startTimer()
            } else {
                handlePlaybackCompletion()
            }
        }

        onTimeUpdate?(clampedTime)
    }

    /// Primes the audio engine in a paused state at a specific timestamp without audible playback.
    /// Used for restoring playback session state across application restarts.
    public func preparePaused(at time: TimeInterval) {
        guard !isStreaming else { return }
        let clampedTime = max(0, min(time, fileDuration > 0 ? fileDuration : time))
        currentTrackTime = clampedTime

        playbackGeneration += 1
        let gen = playbackGeneration
        finishedWhilePaused = false
        playerNode.stop()

        if let file = audioFile {
            let totalFrames = (file.length > 0) ? file.length : AVAudioFramePosition(fileDuration * sampleRate)
            let targetFrame = AVAudioFramePosition(clampedTime * sampleRate)
            let frameCount = AVAudioFrameCount(max(0, totalFrames - targetFrame))
            startFrameOffset = targetFrame

            if frameCount > 0 {
                scheduleFileSegment(file, from: targetFrame, frames: frameCount, generation: gen)
            }
        }

        sourceMixer.outputVolume = 0
        status = .paused
        playbackTimer?.invalidate()
        playbackTimer = nil
        onTimeUpdate?(clampedTime)
        idleEngineIfQuiet()
    }

    private func handlePlaybackCompletion() {
        if status == .playing {
            stopInternal(fade: false)
            onPlaybackFinished?()
        } else if status == .paused {
            // Track reached its end during the pause fade-out; advance when the user resumes
            finishedWhilePaused = true
        }
    }

    private func startTimer() {
        playbackTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.status == .playing else { return }
            let cur = self.currentTime
            self.currentTrackTime = cur
            self.onTimeUpdate?(cur)
        }
        timer.tolerance = 0.02 // lets macOS coalesce wakeups
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func startStreamTimer() {
        playbackTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.status == .playing else { return }
            self.streamElapsed += 0.25
            self.onTimeUpdate?(self.streamElapsed)
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    // MARK: - Volume / Balance
    public func setVolume(_ volume: Double) {
        let v = Float(max(0.0, min(1.0, volume)))
        engine.mainMixerNode.outputVolume = v
        streamPlayer?.volume = v
    }

    /// Balance is applied on sourceMixer: AVAudioMixing.pan has no effect on mainMixerNode,
    /// whose output goes to the output node rather than into a mixer.
    public func setBalance(_ balance: Double) {
        sourceMixer.pan = Float(max(-1.0, min(1.0, balance)))
    }

    public var balance: Double {
        Double(sourceMixer.pan)
    }

    // MARK: - Equalizer
    public func setEqEnabled(_ enabled: Bool) {
        eqNode.bypass = !enabled
    }

    public func setPreamp(gainDb: Float) {
        eqNode.globalGain = gainDb
    }

    public func setEQBand(index: Int, gainDb: Float) {
        guard index >= 0, index < eqNode.bands.count else { return }
        eqNode.bands[index].gain = gainDb
    }

    // MARK: - DSP Effects (Pitch, Rate, Reverb)
    public func setDspEnabled(_ enabled: Bool) {
        isDspEnabled = enabled
        updateDSPBypass()
    }

    public func setPitchSemitones(_ semitones: Double) {
        timePitchNode.pitch = Float(semitones * 100.0) // 1 semitone = 100 cents
        updateDSPBypass()
    }

    public func setPlaybackRate(_ rate: Double) {
        timePitchNode.rate = Float(max(0.5, min(2.0, rate)))
        updateDSPBypass()
    }

    public func setReverbMix(_ percent: Double) {
        let mix = Float(max(0.0, min(100.0, percent)))
        reverbNode.wetDryMix = mix
        updateDSPBypass()
    }
    
    public var isDspTimePitchActive: Bool { !timePitchNode.bypass }
    public var isDspReverbActive: Bool { !reverbNode.bypass }

    public func setReverbPreset(index: Int) {
        let presets: [AVAudioUnitReverbPreset] = [
            .smallRoom,
            .mediumRoom,
            .largeRoom,
            .mediumHall,
            .largeHall,
            .plate,
            .cathedral
        ]
        if index >= 0 && index < presets.count {
            reverbNode.loadFactoryPreset(presets[index])
        }
    }

    public func resetDSP() {
        setPitchSemitones(0)
        setPlaybackRate(1.0)
        setReverbMix(0)
        setReverbPreset(index: 1)
        setDspEnabled(false)
    }

    public var currentPitchSemitones: Double {
        Double(timePitchNode.pitch / 100.0)
    }
    public var currentPlaybackRate: Double {
        Double(timePitchNode.rate)
    }
    public var currentReverbMix: Double {
        Double(reverbNode.wetDryMix)
    }
    public var isDspTimePitchBypassed: Bool {
        timePitchNode.bypass
    }

    // MARK: - Output Device Selection & Routing
    @discardableResult
    public func setOutputDevice(deviceID: AudioDeviceID?) -> Bool {
        guard let audioUnit = engine.outputNode.audioUnit else { return false }
        var devID: AudioDeviceID = deviceID ?? 0
        let err = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard err == noErr else {
            print("AudioEngine: AudioUnitSetProperty failed for device \(devID), status: \(err)")
            return false
        }

        currentOutputDeviceID = (devID == 0) ? nil : devID

        let wasPlaying = (status == .playing)
        let savedTime = currentTime

        reinstallMixerTap()

        if wasPlaying {
            ensureEngineRunning()
            resumeAfterRouteChange(at: savedTime)
        }

        return true
    }
}
