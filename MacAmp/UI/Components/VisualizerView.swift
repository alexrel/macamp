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
    /// Playing or paused: Winamp then paints its own background over MAIN.BMP
    private var isRunning = false

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
        if mode != .off, !isRunning { isRunning = true; needsDisplay = true }
        switch mode {
        case .off:
            return
        case .oscilloscope:
            if changed { needsDisplay = true }
        case .spectrum:
            if applyFalloff() || changed { needsDisplay = true }
        }
    }

    /// Analysis frames since the last drawn one (Refresh rate below ~43 fps skips some): falloff covers them all,
    /// so bars fall at the same speed at any refresh rate
    public var falloffScale: Float = 1

    /// Bars drop by the falloff speed instead of jumping down; peaks hold the maximum and sink slower.
    /// Returns true if any level or peak moved.
    @discardableResult
    private func applyFalloff() -> Bool {
        let barStep = options.barFalloff.barStep * falloffScale
        let peakStep = options.peakFalloff.peakStep * falloffScale
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

    /// Empties the display, including peak dots (used when playback stops; a paused one keeps its last picture).
    public func clear() {
        for i in rawBands.indices { rawBands[i] = 0 }
        for i in barLevels.indices { barLevels[i] = 0 }
        for i in peakHeights.indices { peakHeights[i] = 0 }
        for i in waveformStorage.indices { waveformStorage[i] = 0 }
        isRunning = false
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

    /// The windowshade mini visualizer
    private var isCompact: Bool { bounds.height <= 8 }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none

        context.saveGState()
        context.clip(to: bounds)

        // Stopped or off: transparent, so the skin's own picture of this area (MAIN.BMP) shows
        context.clear(bounds)

        guard mode != .off else {
            context.restoreGState()
            return
        }

        let colors = SkinManager.shared.currentSkin?.visualizerColors.colors ?? VisualizerColors.defaultColors()

        // Playing or paused: VISCOLOR 0 fills the area and VISCOLOR 1 dots it (odd rows, every other column), as in Winamp.
        // The windowshade strip has no dots.
        if isRunning {
            context.setFillColor(color(colors, 0, fallback: .black))
            context.fill(bounds)
            if !isCompact {
                context.setFillColor(color(colors, 1, fallback: .black))
                for y in stride(from: 1, to: Int(bounds.height), by: 2) {
                    for x in stride(from: 0, to: Int(bounds.width), by: 2) { context.fill(CGRect(x: x, y: y, width: 1, height: 1)) }
                }
            }
        }

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
        let maxBarHeight: CGFloat = isCompact ? bounds.height : 16.0

        // Column layout: thick = 19 bars of 3 px (+1 gap); thin = one bar per pixel column.
        // The 38 px windowshade strip keeps the same bars and shows as many as fit, as Winamp does (9 and a part of the 10th).
        let barCount: Int
        let barW: CGFloat
        let stepX: CGFloat
        switch options.bands {
        case .thick: barCount = VisualizerView.thickCount; barW = 3; stepX = 4
        case .thin: barCount = VisualizerView.thinCount; barW = 1; stepX = 1
        }
        let group = VisualizerView.thinCount / barCount
        let rows = max(1, Int(maxBarHeight))

        /// VISCOLOR 2 (top, red) ... 17 (bottom, green) for a row counted from the bottom
        func analyzerColorIndex(row: Int) -> Int {
            17 - min(15, Int((Double(row) / Double(max(1, rows - 1)) * 15).rounded()))
        }
        let peakColor = color(colors, 23, fallback: .lightGray)

        for bar in 0..<barCount where CGFloat(bar) * stepX < bounds.width {
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
        typealias Scope = AppConstants.Visualizer.Scope
        let rows = Int(bounds.height)
        var last = 0

        // One point per column: the windowshade strip shows the first half of the wave, not a squeezed one
        for x in 0..<min(Int(bounds.width), waveformStorage.count) {
            let level = max(0, min(255, Scope.silenceLevel * (1 + waveformStorage[x])))
            var y = Int((Double(level) / Scope.levelsPerRow).rounded()) - Scope.topRow
            if isCompact {
                y = Int((Double(y + Scope.compactShift) / Double(AppConstants.Visualizer.height) * Double(Scope.compactRows)).rounded()) - Scope.compactCentreRow
            }
            y = max(0, min(rows - 1, y))
            // VISCOLOR 18 near the centre line ... 22 at the bottom edge, by the row; the windowshade strip is all 18
            context.setFillColor(color(colors, 18 + (isCompact ? 0 : Scope.colorOffsetByRowPair[y / 2]), fallback: .green))

            if x == 0 { last = y }
            var (top, bottom) = (y, last)
            last = y
            switch options.scopeStyle {
            case .dot:
                bottom = y
            case .solid:
                let (upper, lower) = isCompact ? (Scope.compactCentreRow, Scope.compactCentreRow) : (Scope.solidUpperRow, Scope.solidLowerRow)
                (top, bottom) = y >= lower ? (lower, y) : (y, upper)
            case .line:
                // Joined to the previous point; going down, the main display skips that point's own row
                if bottom < top {
                    swap(&top, &bottom)
                    if !isCompact { top += 1 }
                }
            }
            // Shifted down, the loudest samples would land below the display: they stop on its last row instead
            let shift = isCompact ? 0 : Scope.pushDown
            top = min(top + shift, rows - 1)
            bottom = min(bottom + shift, rows - 1)
            context.fill(CGRect(x: x, y: top, width: 1, height: bottom - top + 1))
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

/// Preferences ▸ Visualization ▸ Refresh rate: which analysis frames (~43 per second) get drawn. Draws on a schedule
/// of 1/fps, so 35 fps really averages 35 (a plain "skip if too soon" would draw every other frame: ~21).
public struct VisualizerThrottle {
    /// Frames per second the analysis delivers (1024-sample windows at 44.1 kHz)
    public static let analysisRate = 43.0
    private var next: Double = 0
    private var last: Double?

    public init() {}

    /// Whether to draw the frame arriving at `now` (seconds), and how many analysis frames it stands for
    public mutating func shouldDraw(at now: Double, fps: Double) -> (draw: Bool, frames: Float) {
        guard fps < VisualizerThrottle.analysisRate else { last = now; return (true, 1) }
        let interval = 1 / max(1, fps)
        guard now >= next - 0.001 else { return (false, 0) }
        next = max(next + interval, now - interval) // on schedule, without a backlog after a pause
        let frames = last.map { Float(min(10, max(1, (now - $0) * VisualizerThrottle.analysisRate))) } ?? 1 // 10: above the 10 fps gap, below a jump after a pause
        last = now
        return (true, frames)
    }
}

