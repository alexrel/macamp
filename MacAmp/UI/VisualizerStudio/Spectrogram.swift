import AppKit
import Accelerate

/// Colour schemes of the Studio's spectrogram and waveform, each picked on its own: quiet to loud
enum VisualizerPalette: Int, CaseIterable {
    case classic, fire, skin, midnight, deepOcean, glacier, ultraviolet, emerald, ember, graphite, rose, ivory

    var title: String {
        ["Classic", "Fire", "Skin", "Midnight", "Deep Ocean", "Glacier", "Ultraviolet", "Emerald", "Ember",
         "Graphite", "Rosé", "Ivory"][rawValue]
    }

    private typealias RGB = (Double, Double, Double)

    /// Background and the two ends of a theme's gradient (0-255)
    private var theme: (background: RGB, from: RGB, to: RGB)? {
        switch self {
        case .classic, .fire, .skin: return nil
        case .midnight: return ((10, 10, 14), (139, 92, 246), (94, 207, 230))
        case .deepOcean: return ((8, 14, 28), (59, 100, 230), (94, 207, 230))
        case .glacier: return ((233, 238, 242), (59, 100, 230), (66, 145, 170))
        case .ultraviolet: return ((14, 10, 26), (160, 90, 240), (225, 85, 150))
        case .emerald: return ((8, 18, 14), (80, 180, 130), (94, 207, 230))
        case .ember: return ((22, 11, 9), (235, 125, 50), (220, 80, 70))
        case .graphite: return ((14, 14, 14), (160, 160, 160), (245, 245, 245))
        case .rose: return ((22, 12, 15), (230, 120, 170), (235, 155, 80))
        case .ivory: return ((0, 0, 0), (215, 210, 195), (240, 236, 225))
        }
    }

    /// 256 RGB entries from quiet (the background) to loud
    func colorTable(skin: [NSColor]) -> [UInt8] {
        let stops: [RGB]
        switch self {
        case .classic:
            stops = [(0.02, 0.04, 0.24), (0.06, 0.20, 0.75), (0.15, 0.62, 1.0), (0.30, 0.86, 0.55),
                     (0.95, 0.90, 0.15), (0.95, 0.15, 0.08)]
        case .fire:
            stops = [(0, 0, 0), (0.12, 0, 0), (0.40, 0, 0), (0.85, 0.20, 0), (1, 0.65, 0), (1, 1, 0.85)]
        case .skin:
            // VISCOLOR 0 (background) for the quiet half, then the analyzer's 17 (bottom, green) ... 2 (top, red), as Winamp's bars rise
            stops = (Array(repeating: 0, count: 8) + Array((2...17).reversed())).map { index in
                let color = (skin.indices.contains(index) ? skin[index] : .black).usingColorSpace(.sRGB) ?? .black
                return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
            }
        default:
            let theme = theme!
            func unit(_ c: RGB) -> RGB { (c.0 / 255, c.1 / 255, c.2 / 255) }
            func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t) }
            let background = unit(theme.background)
            // The loudest end leans away from the background: to white on dark themes, to black on Glacier
            let accent: RGB = background.0 + background.1 + background.2 > 1.5 ? (0, 0, 0) : (1, 1, 1)
            stops = [background, background, mix(background, unit(theme.from), 0.5), unit(theme.from), unit(theme.to),
                     mix(unit(theme.to), accent, 0.55)]
        }
        var table: [UInt8] = []
        for level in 0..<256 {
            let position = Double(level) / 255 * Double(stops.count - 1)
            let index = min(stops.count - 2, Int(position))
            let t = position - Double(index)
            let (a, b) = (stops[index], stops[index + 1])
            for (from, to) in [(a.0, b.0), (a.1, b.1), (a.2, b.2)] {
                table.append(UInt8(((from + (to - from) * t) * 255).rounded()))
            }
        }
        return table
    }

    /// The table for this palette with the current skin's VISCOLOR.TXT, rebuilt only when either changes
    final class Cache {
        private var source: (palette: VisualizerPalette, skin: [NSColor])?
        private(set) var table: [UInt8] = []

        /// True when the table was rebuilt
        func update(_ palette: VisualizerPalette) -> Bool {
            let skin = palette == .skin ? SkinManager.shared.currentSkin?.visualizerColors.colors ?? VisualizerColors.defaultColors() : []
            guard source?.palette != palette || source?.skin != skin else { return false }
            source = (palette, skin)
            table = palette.colorTable(skin: skin)
            return true
        }
    }
}

enum ScrollSpeed: Int, CaseIterable {
    case slower, normal, faster
    var title: String { ["Slower", "Normal", "Faster"][rawValue] }
    /// Columns on screen, one a frame: about 17, 8.5 and 4 seconds at 60 FPS
    var columns: Int { [1024, 512, 256][rawValue] }
}

/// The Studio's spectrogram: 20 Hz - 20 kHz on a log scale bottom to top, time scrolling right to left,
/// one column a frame while music plays. The picture is an 8-bit indexed bitmap, so a colour change recolours
/// the whole history at once.
final class Spectrogram {
    static let rows = 256
    static let minFrequency = 20.0
    static let maxFrequency = 20_000.0
    /// Frequencies labelled on the left edge
    static let gridFrequencies: [(hz: Double, title: String)] = [(100, "100"), (1000, "1k"), (10_000, "10k")]
    private static let log2n = 12 // 4096 points: ~11 Hz a bin at 44.1 kHz, enough for the bass rows
    private static let fftSize = 1 << log2n
    private static let floorDB: Float = -90
    private static let ceilingDB: Float = -18
    private static let rgb = CGColorSpaceCreateDeviceRGB()

    private let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2))!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
    private var history = [Float](repeating: 0, count: fftSize)
    private var windowed = [Float](repeating: 0, count: fftSize)
    private var real = [Float](repeating: 0, count: fftSize / 2)
    private var imag = [Float](repeating: 0, count: fftSize / 2)
    private var power = [Float](repeating: 0, count: fftSize / 2)
    private var decibels = [Float](repeating: 0, count: fftSize / 2)
    private var column = [UInt8](repeating: 0, count: rows)
    private var hasNewSamples = false
    private var rowBins: [Range<Int>] = []
    private var binsSampleRate = 0.0
    private var cells: [UInt8]
    private(set) var columns: Int
    private var colorSpace: CGColorSpace?
    private let palettes = VisualizerPalette.Cache()

    init(speed: ScrollSpeed) {
        columns = speed.columns
        cells = [UInt8](repeating: 0, count: speed.columns * Self.rows)
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    /// A new speed starts a clean picture of the new width
    func setSpeed(_ speed: ScrollSpeed) {
        guard speed.columns != columns else { return }
        columns = speed.columns
        cells = [UInt8](repeating: 0, count: columns * Self.rows)
    }

    /// Height in the picture (0 bottom ... 1 top) of a frequency
    static func position(of hz: Double) -> Double {
        log(hz / minFrequency) / log(maxFrequency / minFrequency)
    }

    /// Takes the newest PCM and, while playing, scrolls in one column
    func advance(playing: Bool) {
        guard playing else { return }
        VisualizerPCMFeed.consume { samples, count in
            let fresh = min(count, Self.fftSize)
            history.withUnsafeMutableBufferPointer { history in
                let base = history.baseAddress!
                base.update(from: base + fresh, count: Self.fftSize - fresh)
                let source = samples + (count - fresh) * 2
                for frame in 0..<fresh {
                    base[Self.fftSize - fresh + frame] = (source[frame * 2] + source[frame * 2 + 1]) * 0.5
                }
            }
            hasNewSamples = true
        }
        // shortcut: the feed keeps only the last tap buffer, so a busy frame may skip audio; a ring in the feed would fix it
        if hasNewSamples {
            hasNewSamples = false
            analyze(sampleRate: VisualizerPCMFeed.sampleRate)
        }
        cells.withUnsafeMutableBufferPointer { cells in
            let base = cells.baseAddress!
            // One shift of the whole bitmap moves every row left; the last column is written below
            base.update(from: base + 1, count: cells.count - 1)
            for row in 0..<Self.rows { base[row * columns + columns - 1] = column[row] }
        }
    }

    private func analyze(sampleRate: Double) {
        if sampleRate != binsSampleRate {
            binsSampleRate = sampleRate
            rowBins = Self.makeRowBins(sampleRate: sampleRate)
        }
        vDSP.multiply(history, window, result: &windowed)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imag.withUnsafeMutableBufferPointer { imagBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                windowed.withUnsafeBytes {
                    vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(Self.fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(Self.log2n), FFTDirection(FFT_FORWARD))
                split.imagp[0] = 0 // packed Nyquist, not part of the DC bin
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(Self.fftSize / 2))
            }
        }
        // 0 dB is a full-scale sine: zrip doubles the DFT and the Hann window halves it, so |out| = N/2
        let fullScale = Float(Self.fftSize / 2)
        vDSP.convert(power: power, toDecibels: &decibels, zeroReference: fullScale * fullScale)
        let scale = 255 / (Self.ceilingDB - Self.floorDB)
        for (row, bins) in rowBins.enumerated() {
            let db = bins.isEmpty ? Self.floorDB : decibels[bins].max() ?? Self.floorDB
            column[row] = UInt8(min(255, max(0, (db - Self.floorDB) * scale)))
        }
    }

    /// FFT bins of each picture row (row 0 is the top, 20 kHz), at least one so the bass rows aren't empty
    static func makeRowBins(sampleRate: Double) -> [Range<Int>] {
        let binHz = sampleRate / Double(fftSize)
        let lastBin = fftSize / 2
        return (0..<rows).map { row in
            let fromBottom = Double(rows - 1 - row)
            let low = minFrequency * pow(maxFrequency / minFrequency, fromBottom / Double(rows))
            let high = minFrequency * pow(maxFrequency / minFrequency, (fromBottom + 1) / Double(rows))
            let lowBin = min(lastBin, max(1, Int(low / binHz)))
            let highBin = min(lastBin, max(lowBin + 1, Int((high / binHz).rounded(.up))))
            return lowBin..<highBin
        }
    }

    func image(palette: VisualizerPalette) -> CGImage? {
        if palettes.update(palette) || colorSpace == nil {
            var table = palettes.table
            colorSpace = CGColorSpace(indexedBaseSpace: Self.rgb, last: 255, colorTable: &table)
        }
        guard let colorSpace, let provider = CGDataProvider(data: Data(cells) as CFData) else { return nil }
        return CGImage(width: columns, height: Self.rows, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: columns,
                       space: colorSpace, bitmapInfo: [], provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The Studio's scrolling waveform: one column for every 256 samples (the feed's envelope), released at the audio's
/// own pace so it scrolls smoothly, drawn as one outline
final class ScrollingWaveform {
    /// Most columns waiting to be shown: older ones are dropped to keep the picture near the sound
    private static let maxDelay = 0.25
    private var lows: [Float]
    private var highs: [Float]
    private var pending: [Float] = []
    private var credit = 0.0
    private var lastAdvance: CFTimeInterval?
    private let palettes = VisualizerPalette.Cache()
    private var gradient: CGGradient?
    private var background: CGColor?

    /// Columns on screen: twice the spectrogram's, about 12, 6 and 3 seconds at 44.1 kHz
    private static func columns(for speed: ScrollSpeed) -> Int { speed.columns * 2 }

    init(speed: ScrollSpeed) {
        lows = [Float](repeating: 0, count: Self.columns(for: speed))
        highs = lows
    }

    var columns: Int { lows.count }

    func setSpeed(_ speed: ScrollSpeed) {
        guard Self.columns(for: speed) != columns else { return }
        lows = [Float](repeating: 0, count: Self.columns(for: speed))
        highs = lows
    }

    func advance(playing: Bool) {
        let now = CACurrentMediaTime()
        let elapsed = lastAdvance.map { now - $0 } ?? 0
        lastAdvance = playing ? now : nil
        guard playing else { return }
        VisualizerPCMFeed.consumeEnvelope { pending.append(contentsOf: $0) }
        let rate = VisualizerPCMFeed.sampleRate / Double(VisualizerPCMFeed.envelopeBlock)
        let maxPending = Int(rate * Self.maxDelay) * 2
        if pending.count > maxPending { pending.removeFirst(pending.count - maxPending) }
        // The tap delivers audio in bursts; columns leave at a steady rate, a burst's worth behind
        let waiting = pending.count / 2
        credit = min(credit + elapsed * rate, Double(waiting) + 1)
        let count = min(Int(credit), waiting, columns)
        guard count > 0 else { return }
        credit -= Double(count)
        lows.removeFirst(count)
        highs.removeFirst(count)
        for index in 0..<count {
            lows.append(max(-1, min(0, pending[index * 2])))
            highs.append(min(1, max(0, pending[index * 2 + 1])))
        }
        pending.removeFirst(count * 2)
    }

    func draw(in context: CGContext, rect: CGRect, palette: VisualizerPalette) {
        if palettes.update(palette) || gradient == nil {
            let table = palettes.table
            func color(_ level: Int) -> CGColor {
                CGColor(srgbRed: CGFloat(table[level * 3]) / 255, green: CGFloat(table[level * 3 + 1]) / 255,
                        blue: CGFloat(table[level * 3 + 2]) / 255, alpha: 1)
            }
            // Loud edges in the palette's loud colours, the body in its middle ones; the background is entry 0
            gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [color(255), color(170), color(170), color(255)] as CFArray,
                                  locations: [0, 0.4, 0.6, 1])
            background = color(0)
        }
        if let background {
            context.setFillColor(background)
            context.fill(rect)
        }
        let step = rect.width / CGFloat(max(1, columns - 1))
        let half = rect.height * 0.45
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + CGFloat(highs[0]) * half))
        for column in 1..<columns {
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(column) * step, y: rect.midY + CGFloat(highs[column]) * half))
        }
        for column in (0..<columns).reversed() {
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(column) * step, y: rect.midY + CGFloat(lows[column]) * half))
        }
        path.closeSubpath()
        guard let gradient else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.midY + half),
                                   end: CGPoint(x: rect.midX, y: rect.midY - half), options: [])
        context.restoreGState()
    }
}
