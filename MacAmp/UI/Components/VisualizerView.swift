import Foundation
import CoreGraphics
import AppKit

public class VisualizerView: WinampControlView {
    public var mode: VisualizerMode = .spectrum {
        didSet { needsDisplay = true }
    }
    
    public var showPeaks: Bool = PersistenceManager.shared.state.visualizerShowPeaks {
        didSet { needsDisplay = true }
    }
    
    public var onToggleMode: (() -> Void)?
    
    /// 19 spectral frequency bins (0.0 ... 1.0)
    public var spectrumAmplitudes: [Float] = Array(repeating: 0.0, count: AppConstants.Visualizer.numSpectrumBars) {
        didSet {
            updatePeaks()
            needsDisplay = true
        }
    }
    
    /// 76 waveform sample points (-1.0 ... 1.0)
    public var waveformPoints: [Float] = Array(repeating: 0.0, count: AppConstants.Visualizer.numWaveformPoints) {
        didSet {
            if mode == .oscilloscope {
                needsDisplay = true
            }
        }
    }
    
    // Peaks falloff for spectrum
    private var peakHeights: [Float] = Array(repeating: 0.0, count: AppConstants.Visualizer.numSpectrumBars)
    
    public override init(frame frameRect: NSRect = NSRect(x: 24, y: 43, width: CGFloat(AppConstants.Visualizer.width), height: CGFloat(AppConstants.Visualizer.height))) {
        super.init(frame: frameRect)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updatePeaks() {
        for i in 0..<min(spectrumAmplitudes.count, peakHeights.count) {
            let current = spectrumAmplitudes[i]
            if current >= peakHeights[i] {
                peakHeights[i] = current
            } else {
                peakHeights[i] = max(0.0, peakHeights[i] - AppConstants.Visualizer.peakFalloffRate)
            }
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        context.saveGState()
        context.clip(to: bounds)
        
        // Clear bounds to transparent so MAIN.BMP's dotted LCD screen texture is visible underneath
        context.clear(bounds)
        
        guard mode != .off else {
            context.restoreGState()
            return
        }
        
        let colors = SkinManager.shared.currentSkin?.visualizerColors.colors ?? VisualizerColors.defaultColors()
        
        // Only draw spectrum bars or oscilloscope line when there is active audio signal
        if mode == .spectrum {
            let hasSignal = spectrumAmplitudes.contains { $0 > 0.001 } || peakHeights.contains { $0 > 0.001 }
            if hasSignal {
                drawSpectrum(in: context, colors: colors)
            }
        } else if mode == .oscilloscope {
            let hasWaveform = waveformPoints.contains { abs($0) > 0.001 }
            if hasWaveform {
                drawOscilloscope(in: context, colors: colors)
            }
        }
        
        context.restoreGState()
    }
    
    private func drawSpectrum(in context: CGContext, colors: [NSColor]) {
        let isCompact = bounds.height <= 8
        let maxBarHeight: CGFloat = isCompact ? bounds.height : 16.0
        let barW: CGFloat = isCompact ? 1.0 : 3.0
        let stepX: CGFloat = isCompact ? 2.0 : 4.0
        let dotColor = colors.count > 1 ? colors[1].cgColor : NSColor.white.cgColor
        
        for i in 0..<AppConstants.Visualizer.numSpectrumBars {
            let amp = i < spectrumAmplitudes.count ? spectrumAmplitudes[i] : 0.0
            let barH = round(CGFloat(amp) * maxBarHeight)
            let x = CGFloat(i) * stepX
            
            // Draw gradient-colored bar from bottom to top
            if barH > 0 {
                for y in 0..<Int(barH) {
                    let py = bounds.height - 1.0 - CGFloat(y)
                    let colorIndex: Int
                    if isCompact {
                        colorIndex = 17 - min(15, Int(round(Double(y) / max(1.0, maxBarHeight - 1.0) * 15.0)))
                    } else {
                        colorIndex = 17 - min(15, y)
                    }
                    let col = colorIndex < colors.count ? colors[colorIndex].cgColor : NSColor.green.cgColor
                    context.setFillColor(col)
                    context.fill(CGRect(x: x, y: py, width: barW, height: 1.0))
                }
            }
            
            // Draw peak dot
            if showPeaks {
                let peakH = round(CGFloat(peakHeights[i]) * maxBarHeight)
                if peakH > 0 {
                    let peakY = max(0, bounds.height - 1.0 - peakH)
                    context.setFillColor(dotColor)
                    context.fill(CGRect(x: x, y: peakY, width: barW, height: 1.0))
                }
            }
        }
    }
    
    private func drawOscilloscope(in context: CGContext, colors: [NSColor]) {
        let oscColor = colors.count > 18 ? colors[18].cgColor : NSColor.green.cgColor
        context.setFillColor(oscColor)
        
        let midY = bounds.height / 2.0
        let halfH = max(1.0, (bounds.height / 2.0) - 1.0)
        let count = Int(bounds.width)
        
        for x in 0..<count {
            let sampleIdx: Int
            if waveformPoints.count > 0 {
                sampleIdx = min(waveformPoints.count - 1, Int(Float(x) / Float(max(1, count)) * Float(waveformPoints.count)))
            } else {
                sampleIdx = 0
            }
            let sample = CGFloat(sampleIdx < waveformPoints.count ? waveformPoints[sampleIdx] : 0)
            let y = round(midY + sample * halfH)
            let clampedY = max(0, min(bounds.height - 1, y))
            context.fill(CGRect(x: CGFloat(x), y: clampedY, width: 1.0, height: 1.0))
        }
    }
    
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    public override func mouseDown(with event: NSEvent) {
        // Intercept mouseDown to prevent dragging MainWindowView
    }
    
    public override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            onToggleMode?()
        }
    }
}
