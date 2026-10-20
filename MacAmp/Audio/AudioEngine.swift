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

public class AudioEngine {
    public static let shared = AudioEngine()
    
    // AVFoundation Engine
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 10)
    private let timePitchNode = AVAudioUnitTimePitch()
    private let reverbNode = AVAudioUnitReverb()
    
    // Analysis
    private let fftAnalyzer = FFTAnalyzer(fftSize: 1024)
    
    // Playback state
    private var audioFile: AVAudioFile?
    private var currentSecurityScopedURL: URL?
    private var fileDuration: TimeInterval = 0
    private var sampleRate: Double = 44100
    private var startFrameOffset: AVAudioFramePosition = 0
    private var currentTrackTime: TimeInterval = 0
    private var playbackGeneration: Int = 0
    /// Incremented on every load(); lets a superseded concurrent load bail out after its await.
    private var loadGeneration: Int = 0
    
    public private(set) var status: PlayerStatus = .stopped {
        didSet {
            if oldValue != status {
                onStatusUpdate?(status)
            }
        }
    }
    public private(set) var currentMetadata: TrackMetadata?
    
    // Callbacks
    public var onStatusUpdate: ((PlayerStatus) -> Void)?
    public var onTimeUpdate: ((TimeInterval) -> Void)?
    public var onPlaybackFinished: (() -> Void)?
    public var onSpectralDataUpdate: (([Float]) -> Void)?
    public var onWaveformDataUpdate: (([Float]) -> Void)?
    public var onMetadataUpdate: ((_ artist: String, _ title: String, _ bitrate: Int?, _ sampleRate: Int?) -> Void)?
    
    // Streaming state
    private var streamPlayer: AVPlayer?
    public private(set) var icySession: ICYStreamSession?
    public var isStreaming: Bool { streamPlayer != nil }
    private var streamElapsed: TimeInterval = 0
    
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
        
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("AudioEngine: Failed to restart AVAudioEngine after route change: \(error)")
            }
        }
        
        if wasPlaying {
            if isStreaming {
                streamPlayer?.play()
                startStreamTimer()
            } else if audioFile != nil {
                seek(to: savedTime)
                playerNode.play()
                startTimer()
            }
        }
    }
    
    public func reinstallMixerTap() {
        if isTapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        
        let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        guard tapFormat.sampleRate > 0 && tapFormat.channelCount > 0 else { return }
        
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: AppConstants.Audio.bufferSize, format: tapFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard self.status == .playing else { return }
            
            let spectrum = self.fftAnalyzer.analyzeSpectrum(buffer: buffer)
            let waveform = self.fftAnalyzer.analyzeWaveform(buffer: buffer)
            
            DispatchQueue.main.async {
                self.onSpectralDataUpdate?(spectrum)
                self.onWaveformDataUpdate?(waveform)
            }
        }
        isTapInstalled = true
    }
    
    private func setupGraph() {
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(timePitchNode)
        engine.attach(reverbNode)
        
        engine.connect(playerNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: timePitchNode, format: nil)
        engine.connect(timePitchNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: nil)
        
        // Tap on main mixer node for spectrum & oscilloscope
        reinstallMixerTap()
        
        do {
            try engine.start()
        } catch {
            print("AudioEngine: Failed to start AVAudioEngine: \(error)")
        }
    }
    
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
        timePitchNode.bypass = false
        
        reverbNode.loadFactoryPreset(.mediumRoom)
        reverbNode.wetDryMix = 0.0
        reverbNode.bypass = true
    }
    
    // MARK: - Track Loading
    public func load(url: URL) async throws -> TrackMetadata {
        loadGeneration += 1
        let loadToken = loadGeneration
        
        // Loading a new track always ends the previous one; otherwise a paused segment of the
        // old file would be resumed by play() instead of the new track.
        playbackGeneration += 1
        playerNode.stop()
        streamPlayer?.pause()
        playbackTimer?.invalidate()
        playbackTimer = nil
        startFrameOffset = 0
        currentTrackTime = 0
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
            playerNode.stop()
            audioFile = nil
            streamPlayer?.pause()
            streamPlayer = nil
            icySession?.stop()
            icySession = nil
            
            // Resolve direct stream endpoint if URL is a .pls or .m3u
            let streamURL = await ICYStreamSession.resolveStreamURL(from: url)
            guard loadToken == loadGeneration else { throw CancellationError() }
            
            let playerItem = AVPlayerItem(url: streamURL)
            let player = AVPlayer(playerItem: playerItem)
            player.volume = Float(engine.mainMixerNode.outputVolume)
            self.streamPlayer = player
            
            let session = ICYStreamSession(url: streamURL)
            self.icySession = session
            self.streamElapsed = 0
            self.fileDuration = 0
            self.currentTrackTime = 0
            
            session.onMetadataUpdate = { [weak self] artist, title, bitrate, sampleRate in
                guard let self = self else { return }
                self.updateCurrentMetadata(title: title, artist: artist, bitrate: bitrate, sampleRate: sampleRate)
                self.onMetadataUpdate?(artist, title, bitrate, sampleRate)
            }
            
            session.onSpectralData = { [weak self] spectrum in
                guard let self = self, self.status == .playing else { return }
                self.onSpectralDataUpdate?(spectrum)
            }
            
            session.onWaveformData = { [weak self] waveform in
                guard let self = self, self.status == .playing else { return }
                self.onWaveformDataUpdate?(waveform)
            }
            
            session.start()
            
            let fallbackTitle = streamURL.lastPathComponent.isEmpty ? (streamURL.host ?? "Internet Radio") : streamURL.lastPathComponent
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
        streamPlayer?.pause()
        streamPlayer = nil
        icySession?.stop()
        icySession = nil
        
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
        
        let finalTitle = (title != localURL.deletingPathExtension().lastPathComponent) ? title : (url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent)
        let finalArtist = (artist != "Unknown Artist") ? artist : (url.isFileURL ? "Unknown Artist" : "Internet Stream")
        
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
    
    // MARK: - Playback Control
    public func play() {
        if isStreaming, let sp = streamPlayer {
            sp.play()
            status = .playing
            startStreamTimer()
            return
        }
        
        guard let file = audioFile else { return }
        
        // If resuming from pause, seamlessly unpause playerNode and timer
        if status == .paused {
            if !engine.isRunning {
                try? engine.start()
            }
            playerNode.play()
            status = .playing
            startTimer()
            return
        }
        
        playbackGeneration += 1
        let gen = playbackGeneration
        
        playerNode.stop()
        if !engine.isRunning {
            try? engine.start()
        }
        
        let totalFrames = (file.length > 0) ? file.length : AVAudioFramePosition(fileDuration * sampleRate)
        let startFrame = AVAudioFramePosition(max(0, min(currentTrackTime, fileDuration)) * sampleRate)
        let frameCount = AVAudioFrameCount(max(0, totalFrames - startFrame))
        guard frameCount > 0 else {
            handlePlaybackCompletion()
            return
        }
        
        startFrameOffset = startFrame
        
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.playbackGeneration == gen else { return }
                self.handlePlaybackCompletion()
            }
        }
        
        playerNode.play()
        status = .playing
        startTimer()
    }
    
    public func pause() {
        guard status == .playing else { return }
        if isStreaming, let sp = streamPlayer {
            sp.pause()
            status = .paused
            playbackTimer?.invalidate()
            playbackTimer = nil
            onTimeUpdate?(streamElapsed)
            return
        }
        
        // Keep playbackGeneration unchanged: the scheduled segment stays valid across pause/resume,
        // and its completion handler must still advance to the next track.
        currentTrackTime = currentTime
        playerNode.pause()
        status = .paused
        playbackTimer?.invalidate()
        playbackTimer = nil
        onTimeUpdate?(currentTrackTime)
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
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return currentTrackTime
        }
        let calculated = Double(startFrameOffset + playerTime.sampleTime) / sampleRate
        return max(0, min(calculated, fileDuration))
    }
    
    public var volume: Double {
        Double(engine.mainMixerNode.outputVolume)
    }
    
    public func stop() {
        playbackGeneration += 1
        if isStreaming {
            streamPlayer?.pause()
            streamPlayer = nil
            icySession?.stop()
            icySession = nil
            streamElapsed = 0
            status = .stopped
            playbackTimer?.invalidate()
            playbackTimer = nil
            onTimeUpdate?(0)
            return
        }
        
        playerNode.stop()
        status = .stopped
        playbackTimer?.invalidate()
        playbackTimer = nil
        startFrameOffset = 0
        currentTrackTime = 0
        onTimeUpdate?(0)
    }
    
    public func seek(to time: TimeInterval) {
        guard !isStreaming else { return }
        guard let file = audioFile else { return }
        let clampedTime = max(0, min(time, fileDuration))
        currentTrackTime = clampedTime
        
        playbackGeneration += 1
        let gen = playbackGeneration
        playerNode.stop()
        
        let totalFrames = (file.length > 0) ? file.length : AVAudioFramePosition(fileDuration * sampleRate)
        let targetFrame = AVAudioFramePosition(clampedTime * sampleRate)
        let frameCount = AVAudioFrameCount(max(0, totalFrames - targetFrame))
        startFrameOffset = targetFrame
        
        if frameCount > 0 {
            playerNode.scheduleSegment(file, startingFrame: targetFrame, frameCount: frameCount, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, self.playbackGeneration == gen else { return }
                    self.handlePlaybackCompletion()
                }
            }
        }
        
        if status == .playing {
            if frameCount > 0 {
                playerNode.play()
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
        playerNode.stop()
        
        if let file = audioFile {
            let totalFrames = (file.length > 0) ? file.length : AVAudioFramePosition(fileDuration * sampleRate)
            let targetFrame = AVAudioFramePosition(clampedTime * sampleRate)
            let frameCount = AVAudioFrameCount(max(0, totalFrames - targetFrame))
            startFrameOffset = targetFrame
            
            if frameCount > 0 {
                playerNode.scheduleSegment(file, startingFrame: targetFrame, frameCount: frameCount, at: nil) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self, self.playbackGeneration == gen else { return }
                        self.handlePlaybackCompletion()
                    }
                }
            }
        }
        
        status = .paused
        playbackTimer?.invalidate()
        playbackTimer = nil
        onTimeUpdate?(clampedTime)
    }
    
    private func handlePlaybackCompletion() {
        if status == .playing {
            stop()
            onPlaybackFinished?()
        }
    }
    
    private func startTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.status == .playing else { return }
            let cur = self.currentTime
            self.currentTrackTime = cur
            self.onTimeUpdate?(cur)
        }
    }
    
    private func startStreamTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.status == .playing else { return }
            self.streamElapsed += 0.25
            self.onTimeUpdate?(self.streamElapsed)
        }
    }
    
    // MARK: - Volume / Balance
    public func setVolume(_ volume: Double) {
        let v = Float(max(0.0, min(1.0, volume)))
        engine.mainMixerNode.outputVolume = v
        streamPlayer?.volume = v
    }
    
    public func setBalance(_ balance: Double) {
        engine.mainMixerNode.pan = Float(max(-1.0, min(1.0, balance)))
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
        timePitchNode.bypass = !enabled
        reverbNode.bypass = !enabled || (reverbNode.wetDryMix <= 0.001)
    }
    
    public func setPitchSemitones(_ semitones: Double) {
        timePitchNode.pitch = Float(semitones * 100.0) // 1 semitone = 100 cents
    }
    
    public func setPlaybackRate(_ rate: Double) {
        timePitchNode.rate = Float(max(0.5, min(2.0, rate)))
    }
    
    public func setReverbMix(_ percent: Double) {
        let mix = Float(max(0.0, min(100.0, percent)))
        reverbNode.wetDryMix = mix
        reverbNode.bypass = (mix <= 0.001)
    }
    
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
        
        if !engine.isRunning {
            try? engine.start()
        }
        
        if wasPlaying {
            if isStreaming {
                streamPlayer?.play()
                startStreamTimer()
            } else if audioFile != nil {
                seek(to: savedTime)
                playerNode.play()
                startTimer()
            }
        }
        
        return true
    }
}
