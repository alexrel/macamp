import AppKit
import Accelerate
import CAVS
import os
import UniformTypeIdentifiers

/// What Winamp handed a vis plug-in each frame: 576 spectrum values and 576 waveform samples per channel,
/// and AVS 2.81d's beat detector over the waveform (main.cpp, "Standard" beat detection).
final class AVSVisData {
    static let length = 576
    private static let fftSize = 1024
    private static let log2n = vDSP_Length(10)
    /// Spectrum range: -60 dB ... 0 dB maps to 0 ... 255, as the main window's analyzer
    private static let floorDecibels: Float = -60
    /// AVS: a beat needs the waveform sum above 34/32 of the running peak and above 576 * 16
    private static let beatThreshold = length * 16

    /// `char[2][2][576]`: [0] spectrum (0...255), [1] waveform (signed); [n][0] left, [n][1] right
    private(set) var bytes = [CChar](repeating: 0, count: 2 * 2 * length)
    private var history = [Float](repeating: 0, count: fftSize * 2) // interleaved stereo, newest last
    private let fftSetup: FFTSetup
    private var window = [Float](repeating: 0, count: fftSize)
    private var real = [Float](repeating: 0, count: fftSize / 2)
    private var imag = [Float](repeating: 0, count: fftSize / 2)
    private var magnitudes = [Float](repeating: 0, count: fftSize / 2)
    private var channel = [Float](repeating: 0, count: fftSize)
    private var beatPeak1 = 0, beatPeak2 = 0, beatCount = 0, beatPeak1Peak = 0

    init() {
        fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_destroy_fftsetup(fftSetup) }

    /// Appends interleaved stereo frames (the newest ones are kept).
    func append(_ samples: UnsafePointer<Float>, frames: Int) {
        let kept = min(frames, Self.fftSize)
        let shift = kept * 2
        history.withUnsafeMutableBufferPointer { h in
            let base = h.baseAddress!
            base.update(from: base + shift, count: h.count - shift)
            (base + h.count - shift).update(from: samples + (frames - kept) * 2, count: shift)
        }
    }

    /// Fills `bytes` from the history and returns whether this frame is a beat.
    func analyze() -> Bool {
        let n = Self.length, size = Self.fftSize
        var sums = [0, 0]
        for ch in 0..<2 {
            for i in 0..<n {
                let sample = Int(max(-127, min(127, history[(size - n + i) * 2 + ch] * 127)))
                bytes[(2 + ch) * n + i] = CChar(sample)
                sums[ch] += abs(sample)
            }
            spectrum(channel: ch)
        }
        return detectBeat(level: max(sums[0], sums[1]))
    }

    private func spectrum(channel ch: Int) {
        let size = Self.fftSize, half = size / 2
        for i in 0..<size { channel[i] = history[i * 2 + ch] * window[i] }
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                channel.withUnsafeBytes {
                    vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        // zrip doubles the amplitudes; through the normalised Hann window a full-scale sine reads about 0 dB
        let scale = 6.0 / Float(size * size) / 4
        for k in 0..<Self.length {
            let amplitude = (magnitudes[k * half / Self.length] * scale).squareRoot()
            let decibels = 20 * log10(max(1e-6, amplitude))
            let level = max(0, min(255, (decibels - Self.floorDecibels) / -Self.floorDecibels * 255))
            bytes[ch * Self.length + k] = CChar(bitPattern: UInt8(level))
        }
    }

    /// AVS 2.81d main.cpp render(): the waveform's loudness against a running peak.
    private func detectBeat(level: Int) -> Bool {
        var beat = false
        beatPeak1 = (beatPeak1 * 125 + beatPeak2 * 3) / 128
        beatCount += 1
        if level >= beatPeak1 * 34 / 32 && level > Self.beatThreshold {
            if beatCount > 0 {
                beatCount = 0
                beat = true
            }
            beatPeak1 = (level + beatPeak1Peak) / 2
            beatPeak1Peak = level
        } else if level > beatPeak2 {
            beatPeak2 = level
        } else {
            beatPeak2 = beatPeak2 * 14 / 16
        }
        return beat
    }
}

/// The AVS presets folder, as Winamp's `Plugins\avs`: the bundled presets are copied there once.
enum AVSPresets {
    static let fileExtension = "avs"
    static let contentType = UTType(filenameExtension: fileExtension) ?? .data
    /// The bundled presets from the 2005 source release (BSD), in MacAmp.app/Contents/Resources/AVS
    static let bundledFolderName = "AVS"

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacAmp/AVS", isDirectory: true)
    }

    /// The bundled presets' submenu, as Winamp kept its presets in `newpicks`
    static let bundledSubfolder = "classic"

    /// Puts the bundled presets into their subfolder once. Copies an earlier MacAmp put in the folder's root are
    /// removed (only files identical to a bundled one).
    static func prepareFolder() {
        let fm = FileManager.default
        let target = folder.appendingPathComponent(bundledSubfolder, isDirectory: true)
        guard !fm.fileExists(atPath: target.path) else { return }
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        guard let bundled = Bundle.main.url(forResource: bundledFolderName, withExtension: nil),
              let files = try? fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension.lowercased() == fileExtension {
            try? fm.copyItem(at: file, to: target.appendingPathComponent(file.lastPathComponent))
            let old = folder.appendingPathComponent(file.lastPathComponent)
            if fm.contentsEqual(atPath: old.path, andPath: file.path) { try? fm.removeItem(at: old) }
        }
    }

    /// Copies chosen `.avs` files, or folders of them (keeping their subfolders), into the presets folder.
    static func importPresets(from urls: [URL]) -> Int {
        prepareFolder()
        let fm = FileManager.default
        var copied = 0
        func copy(_ url: URL, into destination: URL) {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let target = destination.appendingPathComponent(url.lastPathComponent, isDirectory: true)
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                for item in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles])) ?? [] {
                    copy(item, into: target)
                }
            } else if url.pathExtension.lowercased() == fileExtension {
                let target = destination.appendingPathComponent(url.lastPathComponent)
                guard !fm.fileExists(atPath: target.path) else { return }
                if (try? fm.copyItem(at: url, to: target)) != nil { copied += 1 }
            }
        }
        for url in urls { copy(url, into: folder) }
        return copied
    }

    static func importWithPanel() {
        let panel = NSOpenPanel()
        panel.message = "Choose AVS presets (.avs) or folders of them"
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [contentType]
        guard panel.runModal() == .OK else { return }
        let count = importPresets(from: panel.urls)
        Win32Dialog.inform(title: "AVS", message: "\(count) preset\(count == 1 ? "" : "s") imported.")
    }

    struct Folder {
        var url: URL
        var subfolders: [Folder]
        var presets: [URL]
        var allPresets: [URL] { presets + subfolders.flatMap(\.allPresets) }
    }

    /// The folder tree, sorted by name as Windows lists it.
    static func scan(_ url: URL = folder) -> Folder {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        let sorted = items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let folders = sorted.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        return Folder(url: url, subfolders: folders.map { scan($0) }.filter { !$0.allPresets.isEmpty },
                      presets: sorted.filter { $0.pathExtension.lowercased() == fileExtension })
    }
}

/// Advanced Visualization Studio (AVS 2.81d, libavs) in the Studio window, drawn at Winamp's resolution:
/// one AVS pixel per point (larger windows are scaled up in whole steps), nearest-neighbour on screen.
final class AVSView: NSView {
    private static let log = Logger(subsystem: "alexrel.MacAmp", category: "AVS")
    /// The name and version AVS 2.81d shows (plug-in list, editor status line, About AVS)
    static let productName = "Advanced Visualization Studio v2.81d"
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
    /// Winamp rendered full screen at 640×480 by default: wider pictures are rendered at a fraction and scaled up
    static let maxRenderWidth = 640
    /// libavs: width a multiple of 4, height a multiple of 2
    private static let widthStep = 4, heightStep = 2
    /// `avs_render_frame`: a negative time means real time
    private static let realTime: Int64 = -1

    /// AVS 2.6.1 defaults: a cross dissolve of 250 ms × 8 when a preset is picked at random
    static let transitionDuration: CFTimeInterval = 2
    /// How long a status line ("loaded from F1") stays, as Winamp's DDraw status text
    static let statusDuration: CFTimeInterval = 2
    /// Winamp's hotkey slots: PRESET00.APH ... in the AVS folder (F1-F12 are 0-11, 0-9 are 12-21, Shift+0-9 are 22-31)
    static func slotURL(_ slot: Int) -> URL { AVSPresets.folder.appendingPathComponent(String(format: "PRESET%02d.APH", slot)) }

    private(set) var handle: AVS_Handle
    private let visData = AVSVisData()
    /// AVS's own frame: libavs keeps drawing on it (feedback effects read the last frame), so never change it here
    private var pixels: [UInt32] = []
    /// What is shown while a transition mixes two frames
    private var blended: [UInt32] = []
    /// The preset being dissolved away and its own frame
    private var outgoing: (handle: AVS_Handle, pixels: [UInt32], start: CFTimeInterval)?
    private let statusLabel = NSTextField(labelWithString: "")
    private var statusUntil: CFTimeInterval = 0
    /// F: the frame rate in the status line
    var showsFPS = false
    private(set) var renderSize = (width: 0, height: 0)
    private(set) var presetURL: URL?
    /// When the shown preset was loaded: random switching counts from here
    private(set) var loadedAt = CACurrentMediaTime()
    private(set) var fps: Double = 0
    private var frameCount = 0
    private var measurementStart = CACurrentMediaTime()
    private var displayActivity: NSObjectProtocol?
    /// The engine reads the preset folder (pictures, SVP files) from here
    private let basePath = AVSPresets.folder.path

    var presetName: String { presetURL?.deletingPathExtension().lastPathComponent ?? "" }

    init?(studioFrame frame: NSRect) {
        AVSPresets.prepareFolder()
        handle = avs_init(basePath, AVS_AUDIO_EXTERNAL, AVS_BEAT_EXTERNAL)
        guard handle != 0 else {
            Self.log.error("avs_init failed: \(String(cString: avs_error_str(0)), privacy: .public)")
            return nil
        }
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        setAccessibilityLabel("Advanced Visualization Studio")
        statusLabel.font = .systemFont(ofSize: 11, weight: .bold)
        statusLabel.textColor = .white
        statusLabel.shadow = { let shadow = NSShadow(); shadow.shadowColor = .black; shadow.shadowOffset = NSSize(width: 1, height: -1); return shadow }()
        statusLabel.isHidden = true
        addSubview(statusLabel)
    }

    override func layout() {
        super.layout()
        statusLabel.frame = NSRect(x: 4, y: bounds.height - 18, width: max(0, bounds.width - 8), height: 16)
    }

    /// A line of text over the picture for a moment, as AVS's status text.
    func showStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.isHidden = false
        statusUntil = CACurrentMediaTime() + Self.statusDuration
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let displayActivity { ProcessInfo.processInfo.endActivity(displayActivity) }
        if let outgoing { avs_free(outgoing.handle) }
        avs_free(handle)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setVisible(_ visible: Bool) {
        if visible && displayActivity == nil {
            displayActivity = ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled,
                                                                    reason: "AVS visualization is visible")
        } else if !visible, let displayActivity {
            ProcessInfo.processInfo.endActivity(displayActivity)
            self.displayActivity = nil
        }
    }

    /// Loads a binary `.avs` preset (Winamp's format, 0.1 or 0.2); with `transition` the old one dissolves into it.
    @discardableResult
    func load(_ url: URL, transition: Bool = false) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        let target = transition && !pixels.isEmpty ? avs_init(basePath, AVS_AUDIO_EXTERNAL, AVS_BEAT_EXTERNAL) : handle
        guard target != 0 else { return false }
        let ok = data.withUnsafeBytes { avs_preset_set_legacy(target, $0.bindMemory(to: UInt8.self).baseAddress, data.count) }
        guard ok else {
            Self.log.error("Could not load \(url.lastPathComponent, privacy: .public): \(String(cString: avs_error_str(target)), privacy: .public)")
            if target != handle { avs_free(target) }
            return false
        }
        if target != handle {
            if let outgoing { avs_free(outgoing.handle) }
            outgoing = (handle, pixels, CACurrentMediaTime())
            handle = target
        }
        if url.pathExtension.lowercased() == AVSPresets.fileExtension { presetURL = url }
        loadedAt = CACurrentMediaTime()
        return true
    }

    /// Saves the current preset in Winamp's binary format.
    @discardableResult
    func save(to url: URL) -> Bool {
        avs_preset_save_legacy(handle, url.path)
    }

    /// Clears the preset (Preset ▸ New).
    func loadEmpty() {
        _ = avs_preset_set(handle, "{}")
        presetURL = nil
    }

    /// F's status line, as AVS's: frame rate and render resolution
    static func fpsText(_ fps: Double, _ size: (width: Int, height: Int)) -> String {
        String(format: "%.1f FPS @ %dx%d", fps, size.width, size.height)
    }

    /// The render resolution for a view of this many points.
    static func renderSize(for size: NSSize) -> (width: Int, height: Int) {
        let width = max(Int(size.width), widthStep), height = max(Int(size.height), heightStep)
        let divisor = (width + maxRenderWidth - 1) / maxRenderWidth
        return (max(widthStep, width / divisor / widthStep * widthStep), max(heightStep, height / divisor / heightStep * heightStep))
    }

    /// Renders one frame. Without playback the picture stays as it was (MacAmp's visualizers freeze on pause).
    func renderFrame(playing: Bool) {
        guard playing else { return }
        var fresh = false
        VisualizerPCMFeed.consume { samples, count in
            visData.append(samples, frames: count)
            fresh = true
        }
        let beat = fresh && visData.analyze()
        _ = visData.bytes.withUnsafeBufferPointer { avs_audio_set_legacy(handle, $0.baseAddress) }

        let size = Self.renderSize(for: bounds.size)
        if size != renderSize {
            renderSize = size
            pixels = [UInt32](repeating: 0, count: size.width * size.height)
        }
        let ok = pixels.withUnsafeMutableBytes {
            avs_render_frame(handle, $0.baseAddress, size.width, size.height, Self.realTime, beat, AVS_PIXEL_RGB0_8)
        }
        guard ok else { return }
        let shown = dissolveOutgoing(beat: beat, size: size) ? blended : pixels
        if showsFPS {
            statusLabel.stringValue = Self.fpsText(fps, size)
            statusLabel.isHidden = false
        } else if !statusLabel.isHidden && CACurrentMediaTime() > statusUntil {
            statusLabel.isHidden = true
        }
        // RGB0 little-endian = BGRx in memory: 32-bit little-endian, alpha byte skipped
        let data = shown.withUnsafeBytes { Data($0) }
        if let provider = CGDataProvider(data: data as CFData),
           let image = CGImage(width: size.width, height: size.height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: size.width * 4, space: Self.colorSpace,
                               bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)],
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            layer?.contents = image
        }
        frameCount += 1
        let now = CACurrentMediaTime()
        if now - measurementStart >= 1 {
            fps = Double(frameCount) / (now - measurementStart)
            measurementStart = now
            frameCount = 0
        }
    }

    /// Cross dissolve (AVS's transition 1): the old preset keeps rendering underneath until it has faded out.
    private func dissolveOutgoing(beat: Bool, size: (width: Int, height: Int)) -> Bool {
        guard var old = outgoing else { return false }
        let progress = (CACurrentMediaTime() - old.start) / Self.transitionDuration
        guard progress < 1 else {
            avs_free(old.handle)
            outgoing = nil
            return false
        }
        if old.pixels.count != pixels.count { old.pixels = [UInt32](repeating: 0, count: pixels.count) }
        _ = visData.bytes.withUnsafeBufferPointer { avs_audio_set_legacy(old.handle, $0.baseAddress) }
        _ = old.pixels.withUnsafeMutableBytes {
            avs_render_frame(old.handle, $0.baseAddress, size.width, size.height, Self.realTime, beat, AVS_PIXEL_RGB0_8)
        }
        let mix = UInt32(progress * 256)
        if blended.count != pixels.count { blended = pixels }
        for i in pixels.indices {
            let a = old.pixels[i], b = pixels[i]
            let rb = (((a & 0xFF00FF) * (256 - mix) + (b & 0xFF00FF) * mix) >> 8) & 0xFF00FF
            let g = (((a & 0x00FF00) * (256 - mix) + (b & 0x00FF00) * mix) >> 8) & 0x00FF00
            blended[i] = rb | g
        }
        outgoing = old
        return true
    }
}
