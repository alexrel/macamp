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
    
    // Progress tracking timer
    private var playbackTimer: Timer?
    
    private init() {
        setupGraph()
        setupEQ()
    }
    
    deinit {
        currentSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    private func setupGraph() {
        engine.attach(playerNode)
        engine.attach(eqNode)
        
        engine.connect(playerNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: engine.mainMixerNode, format: nil)
        
        // Tap on main mixer node for spectrum & oscilloscope
        let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: AppConstants.Audio.bufferSize, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard self.status == .playing else { return }
            
            let spectrum = self.fftAnalyzer.analyzeSpectrum(buffer: buffer)
            let waveform = self.fftAnalyzer.analyzeWaveform(buffer: buffer)
            
            DispatchQueue.main.async {
                self.onSpectralDataUpdate?(spectrum)
                self.onWaveformDataUpdate?(waveform)
            }
        }
        
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
    
    // MARK: - Track Loading
    public func load(url: URL) async throws -> TrackMetadata {
        if let old = currentSecurityScopedURL {
            old.stopAccessingSecurityScopedResource()
            currentSecurityScopedURL = nil
        }
        if url.isFileURL && url.startAccessingSecurityScopedResource() {
            currentSecurityScopedURL = url
        }
        
        let localURL: URL
        if !url.isFileURL {
            localURL = try await downloadRemoteAudio(from: url)
        } else {
            localURL = url
        }
        
        let file = try AVAudioFile(forReading: localURL)
        self.audioFile = file
        self.sampleRate = file.processingFormat.sampleRate
        
        var duration: TimeInterval = 0
        if file.processingFormat.sampleRate > 0 && file.length > 0 {
            duration = Double(file.length) / file.processingFormat.sampleRate
        }
        
        // Extract metadata and duration asynchronously using unified TrackItem resolver
        let (resolvedDur, artist, title) = await TrackItem.resolveMetadataAsync(from: localURL)
        if resolvedDur > 0 {
            duration = resolvedDur
        }
        
        let finalTitle = (title != localURL.deletingPathExtension().lastPathComponent) ? title : (url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent)
        let finalArtist = (artist != "Unknown Artist") ? artist : (url.isFileURL ? "Unknown Artist" : "Internet Stream")
        
        let channels = file.processingFormat.channelCount
        let channelMode: AudioChannelMode = channels > 1 ? .stereo : .mono
        let approxBitrate = duration > 0 ? Int((Double(file.length * 2 * Int64(channels)) / duration) * 8 / 1000) : 128
        
        self.fileDuration = duration
        self.startFrameOffset = 0
        self.currentTrackTime = 0
        
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
    
    private func downloadRemoteAudio(from url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacAmp_RemoteCache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        var ext = url.pathExtension
        if ext.isEmpty, let suggested = response.suggestedFilename, !URL(fileURLWithPath: suggested).pathExtension.isEmpty {
            ext = URL(fileURLWithPath: suggested).pathExtension
        }
        if ext.isEmpty {
            ext = "mp3"
        }
        
        let targetURL = cacheDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: targetURL)
        try FileManager.default.moveItem(at: tempURL, to: targetURL)
        return targetURL
    }
    
    // MARK: - Playback Control
    public func play() {
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
        currentTrackTime = currentTime
        playbackGeneration += 1
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
        playerNode.stop()
        status = .stopped
        playbackTimer?.invalidate()
        playbackTimer = nil
        startFrameOffset = 0
        currentTrackTime = 0
        onTimeUpdate?(0)
    }
    
    public func seek(to time: TimeInterval) {
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
    
    // MARK: - Volume / Balance
    public func setVolume(_ volume: Double) {
        engine.mainMixerNode.outputVolume = Float(max(0.0, min(1.0, volume)))
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
}
