import Cocoa
import CProjectM
import os

/// Milkdrop presets (.milk) rendered by projectM into an OpenGL 4.1 core context.
/// Presets live in ~/Library/Application Support/MacAmp/Milkdrop (any depth); without any, projectM's idle preset plays.
public final class MilkdropView: NSOpenGLView {
    private static let log = Logger(subsystem: "alexrel.MacAmp", category: "MilkDrop")
    public static var presetsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacAmp/Milkdrop", isDirectory: true)
    }

    static func openPresetsFolder() {
        do {
            try FileManager.default.createDirectory(at: presetsFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(presetsFolder)
        } catch {
            log.error("Could not open the MilkDrop presets folder: \(error.localizedDescription)")
        }
    }

    /// Seconds before the next preset starts by itself
    public var presetDuration: TimeInterval { TimeInterval(PersistenceManager.shared.state.milkdropSeconds) }
    public var shuffle: Bool { PersistenceManager.shared.state.milkdropShuffle }
    public private(set) var presetName = "projectM idle"
    private(set) var initializationFailed = false
    var isOnScreen = false

    private var projectM: projectm_handle?
    private(set) var presets: [URL] = []
    private(set) var currentPresetURL: URL?
    private(set) var failedPresetName: String?
    var onPresetsChanged: (() -> Void)?
    private var scanTask: Task<Void, Never>?
    private var index = -1
    private var presetElapsed: TimeInterval = 0
    private var lastPlayingFrame: TimeInterval?
    private var presetLoadFailed = false

    // Frame counter for the on-screen FPS, and a short grace period so a preset change is visible while paused
    private var framesThisSecond = 0
    private var fpsStart = Date()
    private var measuredFPS = 0
    private var lastDraw = Date.distantPast
    public private(set) var renderUntil = Date().addingTimeInterval(4)

    public var fps: Int { Date().timeIntervalSince(lastDraw) > 1.5 ? 0 : measuredFPS }

    init?(studioFrame frame: NSRect) {
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion4_1Core),
            UInt32(NSOpenGLPFAColorSize), 24, UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADoubleBuffer), UInt32(NSOpenGLPFAAccelerated), 0
        ]
        guard let format = NSOpenGLPixelFormat(attributes: attrs) else {
            Self.log.error("[FIX] MilkDrop could not obtain an OpenGL 4.1 pixel format")
            return nil
        }
        super.init(frame: frame, pixelFormat: format)
        wantsBestResolutionOpenGLSurface = PersistenceManager.shared.state.milkdropRetina
        autoresizingMask = [.width, .height]
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        scanTask?.cancel()
        destroyEngine()
    }

    public override var acceptsFirstResponder: Bool { false }

    public override func prepareOpenGL() {
        super.prepareOpenGL()
        var swapInterval: GLint = 1
        openGLContext?.setValues(&swapInterval, for: .swapInterval)
        guard let handle = projectm_create() else {
            initializationFailed = true
            Self.log.error("[FIX] projectM initialization failed")
            return
        }
        projectM = handle
        projectm_set_fps(handle, 60)
        projectm_set_preset_locked(handle, true) // we rotate presets ourselves
        projectm_set_preset_switch_failed_event_callback(handle, { _, message, context in
            guard let context else { return }
            let view = Unmanaged<MilkdropView>.fromOpaque(context).takeUnretainedValue()
            view.presetLoadFailed = true
            let reason = message.map { String(cString: $0) } ?? "Unknown error"
            MilkdropView.log.error("[FIX] MilkDrop preset failed to load: \(reason)")
        }, Unmanaged.passUnretained(self).toOpaque())
        applySize()
        Self.presetsFolder.path.withCString { path in
            var searchPath: UnsafePointer<CChar>? = path
            projectm_set_texture_search_paths(handle, &searchPath, 1)
        }
        rescanPresets()
        Self.log.debug("[FIX] MilkDrop initialized")
        renderUntil = Date().addingTimeInterval(4)
    }

    private func destroyEngine() {
        guard let handle = projectM else { return }
        openGLContext?.makeCurrentContext()
        projectm_destroy(handle)
        projectM = nil
    }

    /// Call when the window hides: frees the GL resources, the view rebuilds them on the next show
    public func shutdown() {
        scanTask?.cancel()
        destroyEngine()
        clearGLContext()
    }

    private func applySize() {
        guard let projectM else { return }
        // convertToBacking ignores wantsBestResolutionOpenGLSurface: without the check a 1x surface got a 2x render (4x the GPU work, picture cropped)
        let px = wantsBestResolutionOpenGLSurface ? convertToBacking(bounds).size : bounds.size
        projectm_set_window_size(projectM, Int(px.width), Int(px.height))
    }

    public override func reshape() {
        super.reshape()
        openGLContext?.makeCurrentContext()
        applySize()
    }

    func rescanPresets() {
        guard scanTask == nil else { return }
        let folder = Self.presetsFolder
        scanTask = Task { @MainActor [weak self] in
            let scanned = await Task.detached(priority: .userInitiated) {
                Self.findPresets(in: folder)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.scanTask = nil
            self.presets = scanned
            self.index = self.currentPresetURL.flatMap { scanned.firstIndex(of: $0) } ?? -1
            if self.currentPresetURL == nil && !scanned.isEmpty { self.nextPreset(smooth: false) }
            self.onPresetsChanged?()
        }
    }

    nonisolated static func findPresets(in folder: URL) -> [URL] {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                   options: [.skipsHiddenFiles])
        return (files?.compactMap { $0 as? URL } ?? []).filter {
            $0.pathExtension.lowercased() == "milk" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted {
            let order = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    public func nextPreset(smooth: Bool = true, backwards: Bool = false) {
        guard !presets.isEmpty else { return }
        let next: Int
        if shuffle && !backwards && presets.count > 1 {
            let candidate = Int.random(in: 0..<(presets.count - (index >= 0 ? 1 : 0)))
            next = index >= 0 && candidate >= index ? candidate + 1 : candidate
        } else {
            next = index < 0 ? (backwards ? presets.count - 1 : 0) :
                (index + (backwards ? -1 : 1) + presets.count) % presets.count
        }
        selectPreset(at: next, smooth: smooth)
    }

    func selectPreset(at index: Int, smooth: Bool = true) {
        guard let projectM, presets.indices.contains(index) else { return }
        // Loading a preset creates its GL objects in the current context: without this they land nowhere and the next draw crashes
        openGLContext?.makeCurrentContext()
        self.index = index
        presetElapsed = 0
        renderUntil = Date().addingTimeInterval(4)
        let preset = presets[index]
        let name = preset.deletingPathExtension().lastPathComponent
        presetLoadFailed = false
        projectm_load_preset_file(projectM, preset.path, smooth)
        if presetLoadFailed {
            failedPresetName = name
        } else {
            failedPresetName = nil
            presetName = name
            currentPresetURL = preset
        }
    }

    func stopPresetClock() { lastPlayingFrame = nil }

    public override func draw(_ dirtyRect: NSRect) {
        if isOnScreen { renderFrame() }
    }

    /// Called by the Studio's timer directly: waiting for AppKit to ask for a redraw let the picture stall until the mouse moved
    func renderFrame(playing: Bool = false) {
        guard let projectM, let context = openGLContext else { return } // GL is set up by AppKit's first draw of a new view
        context.makeCurrentContext()
        if playing {
            let now = CACurrentMediaTime()
            presetElapsed += now - (lastPlayingFrame ?? now)
            lastPlayingFrame = now
            if presets.count > 1 && presetElapsed >= presetDuration { nextPreset() }
        }
        VisualizerPCMFeed.consume { samples, count in
            let frames = min(count, Int(projectm_pcm_get_max_samples()))
            projectm_pcm_add_float(projectM, samples.advanced(by: (count - frames) * 2), UInt32(frames), PROJECTM_STEREO)
        }
        projectm_opengl_render_frame(projectM)
        context.flushBuffer()
        let now = Date()
        lastDraw = now
        framesThisSecond += 1
        if now.timeIntervalSince(fpsStart) >= 1 {
            measuredFPS = Int((Double(framesThisSecond) / now.timeIntervalSince(fpsStart)).rounded())
            framesThisSecond = 0
            fpsStart = now
        }
    }
}
