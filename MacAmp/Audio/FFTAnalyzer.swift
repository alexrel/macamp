import Foundation
import AVFoundation
import Accelerate
import os

/// The mixer publishes a bounded stereo snapshot. Only the visualizer's render thread calls its engine.
enum VisualizerPCMFeed {
    private static let capacity = Int(AppConstants.Audio.bufferSize)

    private struct Buffer: Sendable {
        var isActive = false
        var frameCount = 0
        var samples = [Float](repeating: 0, count: capacity * 2)
    }

    private static let buffer = OSAllocatedUnfairLock(initialState: Buffer())

    static func setActive(_ active: Bool) {
        buffer.withLock {
            $0.isActive = active
            if !active { $0.frameCount = 0 }
        }
    }

    static func add(_ audio: AVAudioPCMBuffer) {
        guard let channels = audio.floatChannelData else { return }
        buffer.withLockIfAvailableUnchecked { buffer in
            guard buffer.isActive else { return }
            let count = min(Int(audio.frameLength), capacity)
            let stride = audio.stride
            let start = (Int(audio.frameLength) - count) * stride
            let left = channels[0]
            let right = channels[audio.format.channelCount > 1 ? 1 : 0]
            for frame in 0..<count {
                buffer.samples[frame * 2] = left[start + frame * stride]
                buffer.samples[frame * 2 + 1] = right[start + frame * stride]
            }
            buffer.frameCount = count
        }
    }

    static func consume(_ read: (UnsafePointer<Float>, Int) -> Void) {
        buffer.withLockUnchecked { buffer in
            guard buffer.frameCount > 0 else { return }
            buffer.samples.withUnsafeBufferPointer {
                read($0.baseAddress!, buffer.frameCount)
            }
            buffer.frameCount = 0
        }
    }
}

/// Spectrum (19 bars) and oscilloscope (76 points) analysis for the Winamp visualizer.
///
/// All scratch buffers, the Hann window and the bar-to-bin mapping are allocated once, so analysing an
/// audio buffer causes no heap allocations. Not thread-safe: use from a single thread (the mixer tap).
public final class FFTAnalyzer {
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup

    private var mono: [Float]
    private var window: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    /// Half-open FFT bin range for each spectrum bar, per bar count (19 thick / 76 thin), computed once
    private var barBinsByCount: [Int: [Range<Int>]] = [:]

    public init(fftSize: Int = 1024) {
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        mono = [Float](repeating: 0, count: fftSize)
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        real = [Float](repeating: 0, count: fftSize)
        imag = [Float](repeating: 0, count: fftSize)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)

        for count in [AppConstants.Visualizer.numSpectrumBars, AppConstants.Visualizer.numThinBands] {
            barBinsByCount[count] = FFTAnalyzer.makeBarBins(count: count, halfSize: fftSize / 2)
        }
    }
    
    /// Logarithmic-ish grouping of FFT bins into `count` bars (low frequencies get narrow bars).
    private static func makeBarBins(count: Int, halfSize: Int) -> [Range<Int>] {
        (0..<count).map { bar in
            let lowFreq = pow(Double(bar) / Double(count), 2.0)
            let highFreq = pow(Double(bar + 1) / Double(count), 2.0)
            let lowBin = max(1, min(halfSize - 1, Int(lowFreq * Double(halfSize))))
            let highBin = max(lowBin + 1, min(halfSize, Int(highFreq * Double(halfSize))))
            return lowBin..<highBin
        }
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Analyses `buffer` in place into `spectrum` (19 values, 0...1) and `waveform` (76 values, -1...1).
    /// Returns false (and zeroes both outputs) when the buffer is silent, so callers can skip redraws.
    @discardableResult
    public func analyze(buffer: AVAudioPCMBuffer, spectrum: inout [Float], waveform: inout [Float]) -> Bool {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            zero(&spectrum); zero(&waveform)
            return false
        }
        return analyze(channels: channels, channelCount: Int(buffer.format.channelCount),
                       startFrame: 0, frameCount: Int(buffer.frameLength),
                       spectrum: &spectrum, waveform: &waveform)
    }

    /// Analyses the window `startFrame ..< startFrame + frameCount` of non-interleaved float channels.
    @discardableResult
    public func analyze(channels: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int,
                        startFrame: Int, frameCount: Int,
                        spectrum: inout [Float], waveform: inout [Float]) -> Bool {
        guard frameCount > 0, channelCount > 0 else {
            zero(&spectrum); zero(&waveform)
            return false
        }

        // Silence check — paused-at-zero-volume or digital silence costs no FFT
        var peak: Float = 0
        for ch in 0..<min(channelCount, 2) {
            var chPeak: Float = 0
            vDSP_maxmgv(channels[ch] + startFrame, 1, &chPeak, vDSP_Length(frameCount))
            peak = max(peak, chPeak)
        }
        guard peak > 1e-5 else {
            zero(&spectrum); zero(&waveform)
            return false
        }

        fillWaveform(channels: channels, channelCount: channelCount, startFrame: startFrame, frameCount: frameCount, into: &waveform)

        guard frameCount >= fftSize else {
            zero(&spectrum)
            return true
        }

        // 1. Mono mixdown
        vDSP_vclr(&mono, 1, vDSP_Length(fftSize))
        for ch in 0..<channelCount {
            vDSP_vadd(mono, 1, channels[ch] + startFrame, 1, &mono, 1, vDSP_Length(fftSize))
        }
        var divisor = Float(channelCount)
        vDSP_vsdiv(mono, 1, &divisor, &mono, 1, vDSP_Length(fftSize))

        // 2. Hann window
        vDSP_vmul(mono, 1, window, 1, &real, 1, vDSP_Length(fftSize))
        vDSP_vclr(&imag, 1, vDSP_Length(fftSize))

        // 3. FFT -> magnitudes
        let half = fftSize / 2
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                magnitudes.withUnsafeMutableBufferPointer { magPtr in
                    var complex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_fft_zip(fftSetup, &complex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    vDSP_zvmags(&complex, 1, magPtr.baseAddress!, 1, vDSP_Length(half))
                    var mult = Float(2.0 / Double(fftSize))
                    vDSP_vsmul(magPtr.baseAddress!, 1, &mult, magPtr.baseAddress!, 1, vDSP_Length(half))
                    var n = Int32(half)
                    vvsqrtf(magPtr.baseAddress!, magPtr.baseAddress!, &n)
                }
            }
        }

        // 4. Group into bars (as many as `spectrum` has), -60 dB ... 0 dB -> 0 ... 1
        if barBinsByCount[spectrum.count] == nil {
            barBinsByCount[spectrum.count] = FFTAnalyzer.makeBarBins(count: spectrum.count, halfSize: half)
        }
        for (bar, bins) in barBinsByCount[spectrum.count]!.enumerated() {
            var maxAmp: Float = 0
            for bin in bins where magnitudes[bin] > maxAmp {
                maxAmp = magnitudes[bin]
            }
            let db = 20.0 * log10(max(1e-5, maxAmp))
            spectrum[bar] = max(0.0, min(1.0, (db + 60.0) / 60.0))
        }
        return true
    }

    public var windowSize: Int { fftSize }

    private func fillWaveform(channels: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, startFrame: Int, frameCount: Int, into waveform: inout [Float]) {
        let numPoints = waveform.count
        guard numPoints > 0, frameCount >= numPoints else {
            zero(&waveform)
            return
        }
        let step = frameCount / numPoints
        let left = channels[0] + startFrame
        let right = (channelCount > 1 ? channels[1] : channels[0]) + startFrame
        for i in 0..<numPoints {
            let idx = i * step
            waveform[i] = max(-1.0, min(1.0, (left[idx] + right[idx]) * 0.5))
        }
    }

    private func zero(_ values: inout [Float]) {
        for i in values.indices { values[i] = 0 }
    }

    // MARK: - Convenience (allocating) API

    /// Returns 19 spectral bins (0.0 ... 1.0) scaled for the Winamp spectrum display.
    public func analyzeSpectrum(buffer: AVAudioPCMBuffer) -> [Float] {
        var spectrum = [Float](repeating: 0, count: AppConstants.Visualizer.numSpectrumBars)
        var waveform = [Float](repeating: 0, count: AppConstants.Visualizer.numWaveformPoints)
        analyze(buffer: buffer, spectrum: &spectrum, waveform: &waveform)
        return spectrum
    }

    /// Returns 76 waveform points (-1.0 ... 1.0) for the oscilloscope display.
    public func analyzeWaveform(buffer: AVAudioPCMBuffer) -> [Float] {
        var spectrum = [Float](repeating: 0, count: AppConstants.Visualizer.numSpectrumBars)
        var waveform = [Float](repeating: 0, count: AppConstants.Visualizer.numWaveformPoints)
        analyze(buffer: buffer, spectrum: &spectrum, waveform: &waveform)
        return waveform
    }
}

/// Visualizer frames shared between the audio tap thread and the main thread.
///
/// AVAudioEngine delivers tap buffers of ~100 ms regardless of the requested size, i.e. only ~10 per second.
/// The tap therefore analyses each buffer in 1024-frame windows into consecutive slots of this ring and
/// schedules one main-thread delivery per window, spaced by the window duration (~43 fps at 44.1 kHz).
/// All slots are allocated once and updated in place.
public final class VisualizerFrameBuffer {
    public static let slotCount = 16

    private let lock = NSLock()
    private var spectrumSlots: [[Float]]
    private var waveformSlots: [[Float]]
    private var nextSlot = 0
    private var publishedSlot = 0

    public init() {
        // Thin-band resolution (76); thick bars are derived from it by the view
        spectrumSlots = Array(repeating: [Float](repeating: 0, count: AppConstants.Visualizer.numThinBands), count: VisualizerFrameBuffer.slotCount)
        waveformSlots = Array(repeating: [Float](repeating: 0, count: AppConstants.Visualizer.numWaveformPoints), count: VisualizerFrameBuffer.slotCount)
    }

    /// Tap thread: fill the next slot in place and return its index for a later `publish(slot:)`.
    func write(_ body: (inout [Float], inout [Float]) -> Void) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let slot = nextSlot
        nextSlot = (nextSlot + 1) % VisualizerFrameBuffer.slotCount
        body(&spectrumSlots[slot], &waveformSlots[slot])
        return slot
    }

    /// Main thread: make `slot` the frame returned by `read`.
    func publish(slot: Int) {
        lock.lock()
        publishedSlot = slot
        lock.unlock()
    }

    /// Main thread: copy the published frame into the caller's arrays (no allocation when sizes match).
    /// Returns true if anything changed.
    @discardableResult
    public func read(spectrum outSpectrum: inout [Float], waveform outWaveform: inout [Float]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var changed = false
        changed = VisualizerFrameBuffer.copy(spectrumSlots[publishedSlot], into: &outSpectrum) || changed
        changed = VisualizerFrameBuffer.copy(waveformSlots[publishedSlot], into: &outWaveform) || changed
        return changed
    }

    /// Zeroes the published frame (used on pause/stop).
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        for i in spectrumSlots[publishedSlot].indices { spectrumSlots[publishedSlot][i] = 0 }
        for i in waveformSlots[publishedSlot].indices { waveformSlots[publishedSlot][i] = 0 }
    }

    private static func copy(_ source: [Float], into target: inout [Float]) -> Bool {
        if target.count != source.count {
            target = source
            return true
        }
        var changed = false
        for i in source.indices where target[i] != source[i] {
            target[i] = source[i]
            changed = true
        }
        return changed
    }
}
