import Foundation
import AVFoundation
import Accelerate

public class FFTAnalyzer {
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    
    public init(fftSize: Int = 1024) {
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    /// Returns 19 spectral bins (0.0 ... 1.0) scaled for the Winamp spectrum display.
    public func analyzeSpectrum(buffer: AVAudioPCMBuffer) -> [Float] {
        let channelCount = Int(buffer.format.channelCount)
        guard let floatChannelData = buffer.floatChannelData else {
            return Array(repeating: 0.0, count: AppConstants.Visualizer.numSpectrumBars)
        }
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= fftSize else {
            return Array(repeating: 0.0, count: AppConstants.Visualizer.numSpectrumBars)
        }
        
        // 1. Mono mixdown
        var averagedData = [Float](repeating: 0.0, count: fftSize)
        for channel in 0..<channelCount {
            vDSP_vadd(averagedData, 1, floatChannelData[channel], 1, &averagedData, 1, vDSP_Length(fftSize))
        }
        var divisor = Float(channelCount)
        vDSP_vsdiv(averagedData, 1, &divisor, &averagedData, 1, vDSP_Length(fftSize))
        
        // 2. Hann window
        var real = [Float](repeating: 0.0, count: fftSize)
        var window = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(averagedData, 1, window, 1, &real, 1, vDSP_Length(fftSize))
        
        // 3. FFT
        var imag = [Float](repeating: 0.0, count: fftSize)
        var magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
        
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var complexBuffer = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &complexBuffer, 1, log2n, FFTDirection(kFFTDirection_Forward))
                
                var magSq = [Float](repeating: 0.0, count: fftSize / 2)
                vDSP_zvmags(&complexBuffer, 1, &magSq, 1, vDSP_Length(fftSize / 2))
                
                var mult: Float = 2.0 / Float(fftSize)
                vDSP_vsmul(magSq, 1, &mult, &magnitudes, 1, vDSP_Length(fftSize / 2))
                vvsqrtf(&magnitudes, magnitudes, [Int32(fftSize / 2)])
            }
        }
        
        // 4. Group FFT bins into 19 logarithmic bars
        let numBars = AppConstants.Visualizer.numSpectrumBars
        var bars = [Float](repeating: 0.0, count: numBars)
        let halfSize = fftSize / 2
        
        for bar in 0..<numBars {
            let lowFreq = pow(Double(bar) / Double(numBars), 2.0)
            let highFreq = pow(Double(bar + 1) / Double(numBars), 2.0)
            
            let lowBin = max(1, min(halfSize - 1, Int(lowFreq * Double(halfSize))))
            let highBin = max(lowBin + 1, min(halfSize, Int(highFreq * Double(halfSize))))
            
            var maxAmp: Float = 0.0
            for bin in lowBin..<highBin {
                if magnitudes[bin] > maxAmp {
                    maxAmp = magnitudes[bin]
                }
            }
            
            // Apply logarithmic dynamic range compression
            let db = 20.0 * log10(max(1e-5, maxAmp))
            // Map -60 dB ... 0 dB to 0.0 ... 1.0
            let normalized = max(0.0, min(1.0, Float((db + 60.0) / 60.0)))
            bars[bar] = normalized
        }
        
        return bars
    }
    
    /// Returns 76 waveform points (-1.0 ... 1.0) for the oscilloscope display.
    public func analyzeWaveform(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let floatChannelData = buffer.floatChannelData else {
            return Array(repeating: 0.0, count: AppConstants.Visualizer.numWaveformPoints)
        }
        let frameCount = Int(buffer.frameLength)
        let numPoints = AppConstants.Visualizer.numWaveformPoints
        guard frameCount >= numPoints else {
            return Array(repeating: 0.0, count: numPoints)
        }
        
        let step = frameCount / numPoints
        var points = [Float](repeating: 0.0, count: numPoints)
        
        for i in 0..<numPoints {
            let sampleIdx = i * step
            let left = floatChannelData[0][sampleIdx]
            let right = buffer.format.channelCount > 1 ? floatChannelData[1][sampleIdx] : left
            points[i] = max(-1.0, min(1.0, (left + right) * 0.5))
        }
        
        return points
    }
}
