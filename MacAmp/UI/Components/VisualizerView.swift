import Foundation
import CoreGraphics
import AppKit

public class VisualizerView: WinampControlView {
    public var mode: VisualizerMode = .spectrum {
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
        
        let colors = SkinManager.shared.currentSkin?.visualizerColors.colors ?? VisualizerColors.defaultColors()
        
        // Background (black / color 0)
        let bgColor = colors.first ?? NSColor.black
        context.setFillColor(bgColor.cgColor)
        context.fill(bounds)
        
        guard mode != .off else { return }
        
        if mode == .spectrum {
            drawSpectrum(in: context, colors: colors)
        } else if mode == .oscilloscope {
            drawOscilloscope(in: context, colors: colors)
        }
    }
    
    private func drawSpectrum(in context: CGContext, colors: [NSColor]) {
        let maxBarHeight: CGFloat = 16.0
        let barW: CGFloat = 3.0
        let dotColor = colors.count > 1 ? colors[1].cgColor : NSColor.white.cgColor
        
        for i in 0..<AppConstants.Visualizer.numSpectrumBars {
            let amp = i < spectrumAmplitudes.count ? spectrumAmplitudes[i] : 0.0
            let barH = round(CGFloat(amp) * maxBarHeight)
            let x = CGFloat(i * 4)
            
            // Draw gradient-colored bar from bottom to top
            if barH > 0 {
                for y in 0..<Int(barH) {
                    let py = bounds.height - 1.0 - CGFloat(y)
                    // Map y to color index: 17 (bottom) to 2 (top)
                    let colorIndex = 17 - min(15, y)
                    let col = colorIndex < colors.count ? colors[colorIndex].cgColor : NSColor.green.cgColor
                    context.setFillColor(col)
                    context.fill(CGRect(x: x, y: py, width: barW, height: 1.0))
                }
            }
            
            // Draw peak dot
            let peakH = round(CGFloat(peakHeights[i]) * maxBarHeight)
            if peakH > 0 {
                let peakY = max(0, bounds.height - 1.0 - peakH)
                context.setFillColor(dotColor)
                context.fill(CGRect(x: x, y: peakY, width: barW, height: 1.0))
            }
        }
    }
    
    private func drawOscilloscope(in context: CGContext, colors: [NSColor]) {
        let oscColor = colors.count > 18 ? colors[18].cgColor : NSColor.green.cgColor
        context.setFillColor(oscColor)
        
        let midY = bounds.height / 2.0
        let halfH = (bounds.height / 2.0) - 1.0
        
        for x in 0..<min(Int(bounds.width), waveformPoints.count) {
            let sample = CGFloat(waveformPoints[x])
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
