import Foundation
import CoreGraphics
import AppKit

/// Winamp 2.x main-window visualizer: spectrum analyzer (normal / fire / line style, thick or thin bands,
/// falling bars and peaks) or oscilloscope (dot / line / solid), colored from the skin's VISCOLOR.TXT.
public class VisualizerView: WinampControlView {
    public var mode: VisualizerMode = .spectrum {
        didSet { needsDisplay = true }
    }

    public var showPeaks: Bool = PersistenceManager.shared.state.visualizerShowPeaks {
        didSet { needsDisplay = true }
    }

    public var options: VisualizerOptions = PersistenceManager.shared.state.visualizerOptions {
        didSet { needsDisplay = true }
    }

    public var onToggleMode: (() -> Void)?
    /// Right-click menu (built by PlayerCoordinator so it can change modes and persist options)
    public var menuProvider: (() -> NSMenu)?

    private static let thinCount = AppConstants.Visualizer.numThinBands
    private static let thickCount = AppConstants.Visualizer.numSpectrumBars
    private static let thinPerThick = thinCount / thickCount

    // Plain stored arrays (no observers) so per-frame updates write in place without reallocating.
    /// Latest analysis at thin-band resolution
    private var rawBands = [Float](repeating: 0, count: thinCount)
    /// Displayed bar heights after falloff
    private var barLevels = [Float](repeating: 0, count: thinCount)
    private var peakHeights = [Float](repeating: 0, count: thinCount)
    private var waveformStorage = [Float](repeating: 0, count: AppConstants.Visualizer.numWaveformPoints)

    /// 19 thick-band levels (0.0 ... 1.0), e.g. for the Visualizer Studio window
    public var spectrumAmplitudes: [Float] {
        get {
            (0..<VisualizerView.thickCount).map { maxLevel(in: barLevels, group: $0, size: VisualizerView.thinPerThick) }
        }
        set {
            // Legacy 19-band input: spread each value over its 4 thin bands
            for i in 0..<VisualizerView.thinCount {
                let thick = i / VisualizerView.thinPerThick
                rawBands[i] = thick < newValue.count ? newValue[thick] : 0
            }
            applyFalloff()
            needsDisplay = true
        }
    }

    /// 76 waveform sample points (-1.0 ... 1.0)
    public var waveformPoints: [Float] {
        get { waveformStorage }
        set {
            waveformStorage = newValue
            if mode == .oscilloscope {
                needsDisplay = true
            }
        }
    }

    /// Pulls the latest analysis frame from the audio tap. Redraws only when something visible changed
    /// (new amplitudes, bars or peaks still falling), so a steady or silent signal costs no drawing.
    public func update(from frame: VisualizerFrameBuffer) {
        let changed = frame.read(spectrum: &rawBands, waveform: &waveformStorage)
        switch mode {
        case .off:
            return
        case .oscilloscope:
            if changed { needsDisplay = true }
        case .spectrum:
            if applyFalloff() || changed { needsDisplay = true }
        }
    }

    /// Bars drop by the falloff speed instead of jumping down; peaks hold the maximum and sink slower.
    /// Returns true if any level or peak moved.
    @discardableResult
    private func applyFalloff() -> Bool {
        let barStep = options.barFalloff.barStep
        let peakStep = options.peakFalloff.peakStep
        var moved = false
        for i in 0..<VisualizerView.thinCount {
            let level = max(rawBands[i], barLevels[i] - barStep, 0)
            if level != barLevels[i] { barLevels[i] = level; moved = true }
            let peak = level >= peakHeights[i] ? level : max(0, peakHeights[i] - peakStep)
            if peak != peakHeights[i] { peakHeights[i] = peak; moved = true }
        }
        return moved
    }

    public override init(frame frameRect: NSRect = NSRect(x: 24, y: 43, width: CGFloat(AppConstants.Visualizer.width), height: CGFloat(AppConstants.Visualizer.height))) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Empties the display, including peak dots (used when playback pauses/stops and analysis is switched off).
    public func clear() {
        for i in rawBands.indices { rawBands[i] = 0 }
        for i in barLevels.indices { barLevels[i] = 0 }
        for i in peakHeights.indices { peakHeights[i] = 0 }
        for i in waveformStorage.indices { waveformStorage[i] = 0 }
        needsDisplay = true
    }

    private func maxLevel(in values: [Float], group: Int, size: Int) -> Float {
        var result: Float = 0
        let start = group * size
        for i in start..<min(values.count, start + size) where values[i] > result {
            result = values[i]
        }
        return result
    }

    // MARK: - Drawing

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

        if mode == .spectrum {
            if barLevels.contains(where: { $0 > 0.001 }) || peakHeights.contains(where: { $0 > 0.001 }) {
                drawSpectrum(in: context, colors: colors)
            }
        } else if mode == .oscilloscope {
            if waveformStorage.contains(where: { abs($0) > 0.001 }) {
                drawOscilloscope(in: context, colors: colors)
            }
        }

        context.restoreGState()
    }

    private func color(_ colors: [NSColor], _ index: Int, fallback: NSColor) -> CGColor {
        (index < colors.count ? colors[index] : fallback).cgColor
    }

    private func drawSpectrum(in context: CGContext, colors: [NSColor]) {
        let isCompact = bounds.height <= 8 // windowshade mini visualizer
        let maxBarHeight: CGFloat = isCompact ? bounds.height : 16.0

        // Column layout: thick = 19 bars of 3 px (+1 gap); thin = one bar per pixel column
        let barCount: Int
        let barW: CGFloat
        let stepX: CGFloat
        switch (options.bands, isCompact) {
        case (.thick, false): barCount = VisualizerView.thickCount; barW = 3; stepX = 4
        case (.thick, true): barCount = VisualizerView.thickCount; barW = 1; stepX = 2
        case (.thin, false): barCount = VisualizerView.thinCount; barW = 1; stepX = 1
        case (.thin, true): barCount = VisualizerView.thinCount / 2; barW = 1; stepX = 1
        }
        let group = VisualizerView.thinCount / barCount
        let rows = max(1, Int(maxBarHeight))

        /// VISCOLOR 2 (top, red) ... 17 (bottom, green) for a row counted from the bottom
        func analyzerColorIndex(row: Int) -> Int {
            17 - min(15, Int((Double(row) / Double(max(1, rows - 1)) * 15).rounded()))
        }
        let peakColor = color(colors, 23, fallback: .lightGray)

        for bar in 0..<barCount {
            let level = maxLevel(in: barLevels, group: bar, size: group)
            let barH = Int((CGFloat(level) * maxBarHeight).rounded())
            let x = CGFloat(bar) * stepX

            for y in 0..<barH {
                let index: Int
                switch options.analyzerStyle {
                case .normal: index = analyzerColorIndex(row: y)                          // gradient fixed to the screen
                case .fire: index = analyzerColorIndex(row: rows - barH + y)              // gradient rides on the bar top
                case .line: index = analyzerColorIndex(row: barH - 1)                     // whole bar in its top color
                }
                context.setFillColor(color(colors, index, fallback: .green))
                context.fill(CGRect(x: x, y: bounds.height - 1 - CGFloat(y), width: barW, height: 1))
            }

            if showPeaks {
                let peak = maxLevel(in: peakHeights, group: bar, size: group)
                let peakH = (CGFloat(peak) * maxBarHeight).rounded()
                if peakH > 0 {
                    context.setFillColor(peakColor)
                    context.fill(CGRect(x: x, y: max(0, bounds.height - 1 - peakH), width: barW, height: 1))
                }
            }
        }
    }

    private func drawOscilloscope(in context: CGContext, colors: [NSColor]) {
        let midY = (bounds.height / 2).rounded(.down)
        let halfH = max(1.0, bounds.height / 2.0 - 1.0)
        let columns = Int(bounds.width)
        var previousY: CGFloat?

        for x in 0..<columns {
            let sampleIdx = min(waveformStorage.count - 1, Int(Float(x) / Float(max(1, columns)) * Float(waveformStorage.count)))
            let sample = CGFloat(waveformStorage[max(0, sampleIdx)])
            let y = max(0, min(bounds.height - 1, (midY + sample * halfH).rounded()))

            // VISCOLOR 18 (brightest) ... 22: louder samples are brighter
            let colorIndex = 22 - min(4, Int(abs(sample) * 5))
            context.setFillColor(color(colors, colorIndex, fallback: .green))

            let (top, bottom): (CGFloat, CGFloat)
            switch options.scopeStyle {
            case .dot:
                (top, bottom) = (y, y)
            case .line:
                let prev = previousY ?? y
                (top, bottom) = (min(prev, y), max(prev, y))
            case .solid:
                (top, bottom) = (min(midY, y), max(midY, y))
            }
            context.fill(CGRect(x: CGFloat(x), y: top, width: 1, height: bottom - top + 1))
            previousY = y
        }
    }

    // MARK: - Mouse

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

    /// Winamp: right-clicking the visualizer opens the Visualization options menu
    public override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
