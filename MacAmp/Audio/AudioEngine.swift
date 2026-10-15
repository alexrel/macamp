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
    private var fileDuration: TimeInterval = 0
    private var sampleRate: Double = 44100
    private var startFrameOffset: AVAudioFramePosition = 0
    
    public private(set) var status: PlayerStatus = .stopped
    public private(set) var currentMetadata: TrackMetadata?
    
    // Callbacks
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
    
    private func setupGraph() {
        engine.attach(playerNode)
        engine.attach(eqNode)
        
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
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
        let file = try AVAudioFile(forReading: url)
        self.audioFile = file
        self.sampleRate = file.processingFormat.sampleRate
        self.fileDuration = Double(file.length) / sampleRate
        self.startFrameOffset = 0
        
        // Extract metadata (ID3 / AVAsset)
        let asset = AVURLAsset(url: url)
        let duration = Double(file.length) / sampleRate
        
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        
        if let metadata = try? await asset.load(.metadata) {
            for item in metadata {
                if let commonKey = item.commonKey?.rawValue {
                    if commonKey == "title", let str = try? await item.load(.stringValue) {
                        title = str
                    } else if commonKey == "artist", let str = try? await item.load(.stringValue) {
                        artist = str
                    }
                }
            }
        }
        
        let channels = file.processingFormat.channelCount
        let channelMode: AudioChannelMode = channels > 1 ? .stereo : .mono
        let approxBitrate = Int((Double(file.length * 2 * Int64(channels)) / duration) * 8 / 1000)
        
        let meta = TrackMetadata(
            url: url,
            title: title,
            artist: artist,
            duration: duration,
            bitrate: max(128, min(320, approxBitrate)),
            sampleRate: Int(sampleRate / 1000),
            audioMode: channelMode
        )
        self.currentMetadata = meta
        return meta
    }
    
    // MARK: - Playback Control
    public func play() {
        guard let file = audioFile else { return }
        
        if status == .paused {
            playerNode.play()
            status = .playing
            startTimer()
            return
        }
        
        playerNode.stop()
        if !engine.isRunning {
            try? engine.start()
        }
        
        playerNode.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackCompletion()
            }
        }
        
        playerNode.play()
        status = .playing
        startTimer()
    }
    
    public func pause() {
        guard status == .playing else { return }
        playerNode.pause()
        status = .paused
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    public func stop() {
        playerNode.stop()
        status = .stopped
        playbackTimer?.invalidate()
        playbackTimer = nil
        startFrameOffset = 0
        onTimeUpdate?(0)
    }
    
    public func seek(to time: TimeInterval) {
        guard let file = audioFile else { return }
        let targetFrame = AVAudioFramePosition(max(0, min(time, fileDuration)) * sampleRate)
        let frameCount = AVAudioFrameCount(max(0, file.length - targetFrame))
        guard frameCount > 0 else { return }
        
        let wasPlaying = (status == .playing)
        playerNode.stop()
        startFrameOffset = targetFrame
        
        playerNode.scheduleSegment(file, startingFrame: targetFrame, frameCount: frameCount, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackCompletion()
            }
        }
        
        if wasPlaying {
            playerNode.play()
            status = .playing
            startTimer()
        }
        
        onTimeUpdate?(time)
    }
    
    private func handlePlaybackCompletion() {
        if status == .playing {
            stop()
            onPlaybackFinished?()
        }
    }
    
    private func startTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.status == .playing else { return }
            guard let nodeTime = self.playerNode.lastRenderTime,
                  let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
            
            let currentSec = Double(self.startFrameOffset + playerTime.sampleTime) / self.sampleRate
            self.onTimeUpdate?(max(0, min(currentSec, self.fileDuration)))
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
