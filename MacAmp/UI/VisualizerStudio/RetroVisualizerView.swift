import Cocoa
import CoreGraphics
import Carbon.HIToolbox

/// Visualizer presets available in Retro Visualizer Studio
public enum StudioVisualizerPreset: Int, CaseIterable {
    case fireSpectrum = 0
    case phosphorOscilloscope = 1
    case neonCyber = 2
    case matrixRain = 3
    case solarOrb = 4
    case milkdrop = 5
    case goom = 6
    case avs = 7
    case spectrogram = 8
    case waveform = 9

    /// MacAmp's own visualizations: one entry of the Studio, picked from the right-click menu
    static let builtIns = allCases.filter(\.isBuiltIn)
    var isBuiltIn: Bool { ![.milkdrop, .goom, .avs].contains(self) }
    
    public var title: String {
        switch self {
        case .fireSpectrum: return "Fire Spectrum & Peak Glow"
        case .phosphorOscilloscope: return "Retro Phosphor CRT Oscilloscope"
        case .neonCyber: return "Neon Cyber City Spectrum"
        case .matrixRain: return "Matrix Digital Rain"
        case .solarOrb: return "Solar Radial Orb"
        case .milkdrop: return "Milkdrop (projectM)"
        case .goom: return "What A Goom!"
        case .avs: return "Advanced Visualization Studio"
        case .spectrogram: return "Spectrogram"
        case .waveform: return "Waveform"
        }
    }
}

/// A high-performance 60 FPS retro visualizer canvas with multiple classic AVS-inspired modes,
/// CRT phosphor glow, floor reflections, particle dynamics, and an auto-fading HUD.
public final class RetroVisualizerView: NSView {
    
    // MARK: - Properties
    public var currentPreset: StudioVisualizerPreset = .fireSpectrum {
        didSet {
            rememberPreset()
            triggerHUD()
            syncMilkdrop()
            syncGoom()
            syncAVS()
            updateAnimation()
            onPresetChanged?(currentPreset)
            needsDisplay = true
        }
    }

    // Milkdrop sits on top of the view as a GL subview and exists only while it is the shown preset
    private var milkdropView: MilkdropView?
    private var milkdropStarted = false
    /// The hints over every visualizer, shown on a switch or a mouse move, then faded away together:
    /// "60 FPS · name" at the top right, the track and the keys at the bottom left
    private let hud = PassThroughView()
    private let infoLabel = NSTextField(labelWithString: "")
    private let trackLabel = NSTextField(labelWithString: "")
    private var infoName = ""
    private var infoFadeOut: DispatchWorkItem?
    private var infoTick = 0
    private static let infoShownFor: TimeInterval = 3
    private static let infoFadeDuration: TimeInterval = 0.8
    private(set) var isOnScreen = false
    private lazy var spectrogram = Spectrogram(speed: PersistenceManager.shared.state.scrollSpeed)
    private lazy var scrollingWaveform = ScrollingWaveform(speed: PersistenceManager.shared.state.scrollSpeed)
    /// The scrolling built-ins, each with its own colors
    private var isScrolling: Bool { currentPreset == .spectrogram || currentPreset == .waveform }
    private(set) var isPlaying = false
    private var goomView: GoomView?
    var avsView: AVSView?
    // GOOM's filter IDs are zero-based, while its force-effect commands start at 1.
    private static let goomEffects = [
        (key: kVK_F1, title: "Normal"), (key: kVK_F2, title: "Wave"),
        (key: kVK_F3, title: "Crystal Ball"), (key: kVK_F4, title: "Scrunch"),
        (key: kVK_F5, title: "Amulette"), (key: kVK_F6, title: "Water"),
        (key: kVK_F7, title: "Hypercos I"), (key: kVK_F8, title: "Hypercos II")
    ]

    /// The plate is as wide as its text, cut off (with …) only when the window is narrower
    private func layoutInfo() {
        hud.frame = bounds
        let width = max(0, min(infoLabel.intrinsicContentSize.width, bounds.width - 20))
        infoLabel.frame = NSRect(x: bounds.width - width - 10, y: bounds.height - 26, width: width, height: 18)
        let track = trackLabel.intrinsicContentSize
        trackLabel.frame = NSRect(x: 10, y: 10, width: max(0, min(track.width, bounds.width - 20)), height: track.height)
    }

    private static let sharedKeyHints = "Right-click presets · , . prev/next · Space next plug-in · F full screen · Esc close"
    /// The keys of the shown kind of visualizer
    private var keyHints: String {
        switch currentPreset {
        case .goom: return "\(Self.sharedKeyHints) · F1–F8 effect · M cube"
        case .avs: return "\(Self.sharedKeyHints) · R random switching · T name"
        default: return Self.sharedKeyHints
        }
    }

    /// Artist, title, transport and time, then the keys
    private var trackText: NSAttributedString {
        let player = PlayerCoordinator.shared
        let track = player.playlist.currentTrack
        let engine = player.audioEngine
        let status = engine.status == .playing ? "PLAYING" : engine.status == .paused ? "PAUSED" : "STOPPED"
        func clock(_ seconds: TimeInterval) -> String { String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
        let total = track?.duration ?? 0
        let time = total > 0 ? "\(clock(engine.currentTime)) / \(clock(total))" : "\(clock(engine.currentTime)) (LIVE)"
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString()
        for (line, font, white) in [
            (track.map(\.artist) ?? "MacAmp \(AppConstants.App.version)", NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), 0.75),
            (track?.title ?? "Visualizer Studio", NSFont.systemFont(ofSize: 18, weight: .bold), 1),
            ("\(status)  \(time)", NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), 0.75),
            (keyHints, NSFont.systemFont(ofSize: 10), 0.55)
        ] where !line.isEmpty {
            text.append(NSAttributedString(string: (text.length == 0 ? " " : "\n ") + line + " ", attributes: [
                .font: font, .foregroundColor: NSColor(white: white, alpha: 1), .paragraphStyle: paragraph
            ]))
        }
        return text
    }

    /// What the line says for the shown visualizer; an error stays up instead of fading
    private var infoContent: (fps: Int, name: String, error: Bool) {
        switch currentPreset {
        case .milkdrop:
            guard let view = milkdropView, !view.initializationFailed else { return (0, "MilkDrop could not start", true) }
            if let failed = view.failedPresetName { return (0, "Could not load \(failed)", true) }
            return (view.fps, view.presetName, false)
        case .goom: return (Int(goomView?.fps ?? 0), StudioVisualizerPreset.goom.title, false)
        case .avs: return (Int((avsView?.fps ?? 0).rounded()), avsView?.presetName ?? StudioVisualizerPreset.avs.title, false)
        default: return (currentFPS, currentPreset.title, false)
        }
    }

    /// Refreshes the line; it comes up when asked to or when the name changed (MilkDrop's and AVS's own switching)
    private func updateInfo(show: Bool = false) {
        let info = infoContent
        // MilkDrop keeps drawing a moment after a preset change while paused (its preview)
        let previewing = currentPreset == .milkdrop && milkdropView.map { Date() < $0.renderUntil } == true
        let stopped = PlayerCoordinator.shared.audioEngine.status == .stopped
        let status = !isPlaying && !previewing ? (stopped ? "stopped" : "paused") : info.fps > 0 ? "\(info.fps) FPS" : "starting"
        infoLabel.stringValue = info.error ? " \(info.name) " : " \(status)  ·  \(info.name) "
        trackLabel.attributedStringValue = trackText
        layoutInfo()
        let renamed = info.name != infoName
        infoName = info.name
        guard show || renamed || info.error else { return }
        infoFadeOut?.cancel()
        hud.alphaValue = 1
        guard !info.error else { return }
        let fadeOut = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.infoFadeDuration
                self?.hud.animator().alphaValue = 0
            }
        }
        infoFadeOut = fadeOut
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.infoShownFor, execute: fadeOut)
    }

    /// The line stays above MilkDrop, GOOM and AVS, which come and go as subviews
    public override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview !== hud, hud.superview === self { addSubview(hud, positioned: .above, relativeTo: nil) }
    }

    private func syncMilkdrop(closing: Bool = false) {
        if currentPreset == .milkdrop && !closing {
            guard isOnScreen, !milkdropStarted else { return }
            milkdropStarted = true
            if let view = MilkdropView(studioFrame: bounds) {
                view.isOnScreen = true
                addSubview(view)
                milkdropView = view
                view.onPresetsChanged = { [weak self] in
                    self?.updateAnimation()
                    self?.updateInfo()
                }
            }
            updateInfo()
        } else {
            milkdropView?.shutdown()
            milkdropView?.removeFromSuperview()
            milkdropView = nil
            milkdropStarted = false
        }
    }

    public override func layout() {
        super.layout()
        layoutInfo()
    }

    private func applyMilkdropPreset(at row: Int) {
        milkdropView?.selectPreset(at: row, smooth: false)
        updateAnimation()
        updateInfo()
    }

    private func syncGoom(closing: Bool = false) {
        if currentPreset == .goom && !closing {
            if let goomView {
                goomView.setVisible(isOnScreen)
                return
            }
            guard isOnScreen else { return }
            let view = GoomView(frame: bounds)
            addSubview(view)
            view.setVisible(true)
            goomView = view
            let insets = GenWindowFrameView.insets
            window?.contentMinSize = NSSize(width: CGFloat(GoomOptions.widths.lowerBound) + insets.left + insets.right,
                                           height: CGFloat(GoomOptions.heights.lowerBound) + insets.top + insets.bottom)
        } else if let view = goomView {
            view.removeFromSuperview()
            goomView = nil
            window?.contentMinSize = RetroVisualizerWindow.studioMinimumSize
        }
    }
    
    // Audio Data
    public var spectrum: [Float] = Array(repeating: 0.0, count: 64)
    public var waveform: [Float] = Array(repeating: 0.0, count: 128)
    
    // Peak tracking
    private var peakHeights: [Float] = Array(repeating: 0.0, count: 64)
    private var peakVelocity: [Float] = Array(repeating: 0.0, count: 64)
    
    // Display link / Animation Timer
    private var displayTimer: Timer?
    private var lastFrameTime: TimeInterval = Date().timeIntervalSince1970
    private var fpsCounter: Int = 0
    private var currentFPS: Int = 60
    private var fpsTimer: TimeInterval = 0
    
    // Matrix Rain State
    private struct MatrixDrop {
        var x: CGFloat
        var y: CGFloat
        var speed: CGFloat
        var chars: [Character]
    }
    private var matrixDrops: [MatrixDrop] = []
    
    // Solar Orb Particles
    private struct SolarParticle {
        var angle: CGFloat
        var distance: CGFloat
        var speed: CGFloat
        var size: CGFloat
        var alpha: CGFloat
    }
    private var solarParticles: [SolarParticle] = []
    
    // HUD overlay state
    
    // Actions
    public var onExit: (() -> Void)?
    public var onToggleFullScreen: (() -> Void)?
    var onPresetChanged: ((StudioVisualizerPreset) -> Void)?
    
    // MARK: - Lifecycle
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setupTrackingArea()
        infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        infoLabel.textColor = .white
        infoLabel.lineBreakMode = .byTruncatingTail
        infoLabel.alignment = .right
        for label in [infoLabel, trackLabel] {
            label.drawsBackground = true
            label.backgroundColor = NSColor.black.withAlphaComponent(0.55)
            hud.addSubview(label)
        }
        trackLabel.maximumNumberOfLines = 4
        hud.alphaValue = 0
        addSubview(hud)
        initMatrixDrops()
        initSolarParticles()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        displayTimer?.invalidate()
    }
    
    public override var acceptsFirstResponder: Bool { true }
    
    private func setupTrackingArea() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
    
    func setActivity(visible: Bool, playing: Bool) {
        let opened = visible && !isOnScreen
        isOnScreen = visible
        isPlaying = playing
        syncMilkdrop()
        syncGoom()
        syncAVS()
        milkdropView?.isOnScreen = visible
        if !visible || !playing { milkdropView?.stopPresetClock() }
        updateAnimation()
        updateInfo(show: opened)
    }

    func updateAnimation() {
        let milkdrop = currentPreset == .milkdrop
        let canRenderMilkdrop = milkdropView.map { !$0.initializationFailed } ?? false
        VisualizerPCMFeed.setActive(isOnScreen && isPlaying && (goomView != nil || avsView != nil || isScrolling || (milkdrop && canRenderMilkdrop)))
        let previewing = milkdropView.map { Date() < $0.renderUntil } ?? false
        // AVS freezes on pause, as the other visualizers: no frames, no CPU
        guard isOnScreen && (!milkdrop || (canRenderMilkdrop && (isPlaying || previewing))) && (avsView == nil || isPlaying) else {
            displayTimer?.invalidate()
            displayTimer = nil
            updateInfo()
            return
        }
        let goomLimit = currentPreset == .goom ? PersistenceManager.shared.state.goomOptions.frameLimit : 60
        let fps = goomLimit == 0 ? window?.screen?.maximumFramesPerSecond ?? 60 : goomLimit
        let interval = 1.0 / Double(max(1, fps))
        guard displayTimer?.timeInterval != interval else { return }
        displayTimer?.invalidate()
        lastFrameTime = Date().timeIntervalSince1970
        // .common: the default mode pauses while another window is being dragged (event tracking), and the picture froze
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.renderTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }
    
    func closeVisualization() {
        isOnScreen = false
        syncMilkdrop(closing: true)
        syncGoom(closing: true)
        syncAVS(closing: true)
        updateAnimation()
    }
    
    // MARK: - Input & Hotkeys
    public override func mouseMoved(with event: NSEvent) {
        triggerHUD()
    }
    
    // A drag moves the window (the window has no title bar to grab)
    private var mouseDownEvent: NSEvent?
    /// The window being moved by this drag, with the same magnetic docking as its frame's title bar
    private var draggedWindow: WinampWindow?

    public override func mouseDown(with event: NSEvent) {
        triggerHUD()
        mouseDownEvent = event
    }

    public override func mouseDragged(with event: NSEvent) {
        if let down = mouseDownEvent {
            mouseDownEvent = nil
            if let win = window as? WinampWindow, !win.styleMask.contains(.fullScreen) {
                draggedWindow = win
                win.startWindowDrag(with: down)
            }
        }
        draggedWindow?.continueWindowDrag(with: event)
    }

    public override func mouseUp(with event: NSEvent) {
        if let win = draggedWindow {
            draggedWindow = nil
            win.endWindowDrag(with: event)
            return
        }
        // A click does nothing, as in the plug-ins: presets come from the right-click menu
        mouseDownEvent = nil
    }
    
    public override func keyDown(with event: NSEvent) {
        triggerHUD()
        // The same keys in all four: F or ⌥Return full screen, Space / Tab the next of the four, , . the previous / next
        // preset (physical keys, so б / ю on a Russian layout), Esc close
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = Int(event.keyCode)
        if (modifiers.isEmpty && key == kVK_ANSI_F)
            || (modifiers == [.option] && (key == kVK_Return || key == kVK_ANSI_KeypadEnter)) {
            onToggleFullScreen?()
            return
        }
        if modifiers.isEmpty {
            switch key {
            case kVK_Space, kVK_Tab: cyclePreset(); return
            case kVK_ANSI_Comma: stepPreset(by: -1); return
            case kVK_ANSI_Period: stepPreset(by: 1); return
            case kVK_Escape: onExit?(); return
            default: break
            }
        }
        if currentPreset == .goom && handleGoomKey(event) { return }
        if currentPreset == .avs && handleAVSKey(event) { return }

        switch event.keyCode {
        case 8: // 'C' -> Toggle Play / Pause
            PlayerCoordinator.shared.handlePlayPause()
        case 123: // Left Arrow -> Prev Track
            PlayerCoordinator.shared.handlePrev()
        case 124: // Right Arrow -> Next Track
            PlayerCoordinator.shared.handleNext()
        case 126: // Up Arrow -> Volume Up
            PlayerCoordinator.shared.increaseVolume()
        case 125: // Down Arrow -> Volume Down
            PlayerCoordinator.shared.decreaseVolume()
        default:
            super.keyDown(with: event)
        }
    }

    /// , . in whichever is shown: the built-ins, MilkDrop's presets, GOOM's effects, AVS's presets
    private func stepPreset(by step: Int) {
        switch currentPreset {
        case .milkdrop:
            milkdropView?.nextPreset(backwards: step < 0)
            updateAnimation()
            updateInfo()
        case .goom:
            let count = Self.goomEffects.count
            let current = goomView?.lastForcedEffect.map { $0 - 1 } ?? (step > 0 ? -1 : 0)
            goomView?.forceEffect(((current + step) % count + count) % count + 1)
        case .avs:
            stepAVSPreset(by: step)
        default:
            let builtIns = StudioVisualizerPreset.builtIns
            guard let index = builtIns.firstIndex(of: currentPreset) else { return }
            currentPreset = builtIns[((index + step) % builtIns.count + builtIns.count) % builtIns.count]
        }
    }

    private func handleGoomKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = Int(event.keyCode)
        guard modifiers.isEmpty else { return PlayerCoordinator.shared.handleKeyDown(event) }
        if let effect = Self.goomEffects.firstIndex(where: { $0.key == key }) {
            goomView?.forceEffect(effect + 1)
            return true
        }
        switch key {
        case kVK_ANSI_M: goomView?.toggleCube()
        case kVK_ANSI_KeypadPlus where goomView?.isCube == true: goomView?.moveCamera(by: -1)
        case kVK_ANSI_KeypadMinus where goomView?.isCube == true: goomView?.moveCamera(by: 1)
        default: return PlayerCoordinator.shared.handleKeyDown(event)
        }
        return true
    }

    /// One layout for all four, AVS's: the window's commands, then the presets (MilkDrop's and AVS's folders),
    /// then the shown one's settings. L stays the player's Open file everywhere
    public override func menu(for event: NSEvent) -> NSMenu? {
        if currentPreset == .avs, avsView != nil { return avsMenu() }
        let menu = NSMenu()
        menu.autoenablesItems = false // "Fullscreen" as AVS titles it, not AppKit's "Enter Full Screen"
        let fullScreen = NSMenuItem(title: "Fullscreen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
        fullScreen.target = window
        menu.addItem(fullScreen)
        menu.addItem(.separator())
        if currentPreset == .milkdrop {
            // Where AVS has its editor: a search over all the presets, too many to scroll through
            let find = NSMenuItem(title: "Find Preset…", action: #selector(findMilkdropPreset), keyEquivalent: "")
            find.target = self
            find.isEnabled = milkdropView?.presets.isEmpty == false
            menu.insertItem(find, at: 1)
            addMilkdropPresetItems(in: MilkdropView.presetsFolder, to: menu)
            milkdropView?.rescanPresets() // presets dropped into the folder show up next time
            return menu
        }
        let presets = NSMenu()
        let presetsItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        presetsItem.submenu = presets
        menu.addItem(presetsItem)
        if currentPreset.isBuiltIn {
            for (index, preset) in StudioVisualizerPreset.builtIns.enumerated() {
                addChoice(preset.title, tag: index, checked: preset == currentPreset, action: #selector(chooseBuiltIn(_:)), to: presets)
            }
            if isScrolling { addScrollingItems(to: menu) }
            return menu
        }
        for (index, effect) in Self.goomEffects.enumerated() {
            addChoice(effect.title, tag: index + 1, checked: goomView?.lastForcedEffect == index + 1,
                      action: #selector(chooseGoomEffect(_:)), to: presets)
        }
        menu.addItem(.separator())
        for factor in [1, 2, 4] {
            let item = NSMenuItem(title: "Zoom \(factor)×", action: #selector(zoomGoom(_:)), keyEquivalent: "")
            item.target = self
            item.tag = factor
            menu.addItem(item)
        }
        return menu
    }

    /// MilkDrop's presets by folder, as AVS lists its own; a folder fills when it opens, so thousands cost nothing up front
    private func addMilkdropPresetItems(in folder: URL, to menu: NSMenu) {
        guard let view = milkdropView else { return }
        let (subfolders, presets) = Self.folderContents(of: folder, in: view.presets)
        for name in subfolders {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: folder.appendingPathComponent(name, isDirectory: true).path)
            submenu.delegate = self
            item.submenu = submenu
            menu.addItem(item)
        }
        for preset in presets {
            let item = NSMenuItem(title: preset.deletingPathExtension().lastPathComponent,
                                  action: #selector(chooseMilkdropPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.state = preset == view.currentPresetURL ? .on : .off
            menu.addItem(item)
        }
    }

    /// The folders (sorted as Finder sorts them) and presets right inside `folder`, out of the scanned preset list
    static func folderContents(of folder: URL, in presets: [URL]) -> (subfolders: [String], presets: [URL]) {
        let folderPath = folder.pathComponents
        var subfolders: [String] = []
        var inside: [URL] = []
        for preset in presets {
            let path = preset.pathComponents
            guard path.count > folderPath.count, Array(path.prefix(folderPath.count)) == folderPath else { continue }
            if path.count == folderPath.count + 1 {
                inside.append(preset)
            } else if !subfolders.contains(path[folderPath.count]) {
                subfolders.append(path[folderPath.count])
            }
        }
        return (subfolders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, inside)
    }

    @objc private func findMilkdropPreset() {
        guard let view = milkdropView else { return }
        let presets = view.presets // a rescan may finish while the dialog is open
        let root = MilkdropView.presetsFolder.pathComponents.count
        let names = presets.map { $0.deletingPathExtension().pathComponents.dropFirst(root).joined(separator: "/") }
        guard let chosen = Win32Dialog.find(title: "Find preset", prompt: "Search for preset:", items: names,
                                            current: view.currentPresetURL.flatMap { presets.firstIndex(of: $0) }),
              let index = view.presets.firstIndex(of: presets[chosen]) else { return }
        applyMilkdropPreset(at: index)
    }

    @objc private func chooseMilkdropPreset(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL, let index = milkdropView?.presets.firstIndex(of: url) else { return }
        applyMilkdropPreset(at: index)
    }

    private func addChoice(_ title: String, tag: Int, checked: Bool, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    @objc private func chooseBuiltIn(_ item: NSMenuItem) { currentPreset = StudioVisualizerPreset.builtIns[item.tag] }
    @objc private func chooseGoomEffect(_ item: NSMenuItem) { goomView?.forceEffect(item.tag) }

    @objc private func zoomGoom(_ item: NSMenuItem) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let options = PersistenceManager.shared.state.goomOptions
        let width = goomView?.isCube == true ? GoomView.cubeTextureSize : options.renderWidth
        let height = goomView?.isCube == true ? GoomView.cubeTextureSize : options.renderHeight
        let insets = GenWindowFrameView.insets
        let scale = PersistenceManager.shared.state.interfaceScale.multiplier
        window.setContentSize(NSSize(width: (CGFloat(width * item.tag) + insets.left + insets.right) * scale,
                                     height: (CGFloat(height * item.tag) + insets.top + insets.bottom) * scale))
    }
    
    /// Space: the built-ins (back to the one last shown), MilkDrop, GOOM, AVS
    public func cyclePreset() {
        switch currentPreset {
        case .milkdrop: currentPreset = .goom
        case .goom: currentPreset = .avs
        case .avs: currentPreset = PersistenceManager.shared.state.studioBuiltIn
        default: currentPreset = .milkdrop
        }
    }

    /// Colors of the shown one (the spectrogram and the waveform keep their own) and the shared scroll speed
    /// What is shown is the selected vis plug-in, as Preferences ▸ Visualization lists them, and the Studio opens on it again
    private func rememberPreset() {
        var state = PersistenceManager.shared.state
        state.studioPreset = currentPreset
        if currentPreset.isBuiltIn { state.studioBuiltIn = currentPreset }
        state.goomPluginSelected = currentPreset == .goom
        state.avsPluginSelected = currentPreset == .avs
        PersistenceManager.shared.state = state
        PersistenceManager.shared.scheduleSave()
    }

    private func addScrollingItems(to menu: NSMenu) {
        let state = PersistenceManager.shared.state
        let current = currentPreset == .spectrogram ? state.spectrogramPalette : state.waveformPalette
        let colors = NSMenu()
        for palette in VisualizerPalette.allCases {
            let item = NSMenuItem(title: palette.title, action: #selector(chooseScrollingPalette(_:)), keyEquivalent: "")
            item.target = self
            item.tag = palette.rawValue
            item.state = palette == current ? .on : .off
            colors.addItem(item)
        }
        let colorsItem = NSMenuItem(title: "Colors", action: nil, keyEquivalent: "")
        colorsItem.submenu = colors
        menu.addItem(.separator())
        menu.addItem(colorsItem)
        menu.addItem(.separator())
        for speed in ScrollSpeed.allCases {
            let item = NSMenuItem(title: speed.title, action: #selector(chooseScrollSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.tag = speed.rawValue
            item.state = speed == state.scrollSpeed ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func chooseScrollingPalette(_ item: NSMenuItem) {
        let palette = VisualizerPalette(rawValue: item.tag) ?? .classic
        if currentPreset == .spectrogram {
            PersistenceManager.shared.state.spectrogramPalette = palette
        } else {
            PersistenceManager.shared.state.waveformPalette = palette
        }
        PersistenceManager.shared.scheduleSave()
        needsDisplay = true
    }

    @objc private func chooseScrollSpeed(_ item: NSMenuItem) {
        let speed = ScrollSpeed(rawValue: item.tag) ?? .normal
        PersistenceManager.shared.state.scrollSpeed = speed
        PersistenceManager.shared.scheduleSave()
        spectrogram.setSpeed(speed)
        scrollingWaveform.setSpeed(speed)
        needsDisplay = true
    }
    
    private func triggerHUD() {
        updateInfo(show: true)
        needsDisplay = true
    }
    
    // MARK: - Update Tick
    private func renderTick() {
        infoTick += 1
        if infoTick % 30 == 0 { updateInfo() }
        if let avsView {
            avsView.renderFrame(playing: isPlaying)
            if isPlaying { switchAVSPresetIfDue() }
            return
        }
        if let goomView {
            goomView.renderFrame(playing: isPlaying)
            return
        }
        if currentPreset == .milkdrop, let milkdropView {
            guard !milkdropView.initializationFailed && (isPlaying || Date() < milkdropView.renderUntil) else {
                updateAnimation()
                return
            }
            milkdropView.renderFrame(playing: isPlaying)
            return
        }
        let now = Date().timeIntervalSince1970
        let delta = now - lastFrameTime
        lastFrameTime = now
        
        // FPS calculation
        fpsCounter += 1
        fpsTimer += delta
        if fpsTimer >= 1.0 {
            currentFPS = fpsCounter
            fpsCounter = 0
            fpsTimer = 0
        }
        
        // Update peak physics
        for i in 0..<min(spectrum.count, peakHeights.count) {
            let val = spectrum[i]
            if val >= peakHeights[i] {
                peakHeights[i] = val
                peakVelocity[i] = 0.0
            } else {
                peakVelocity[i] += 0.003 // Gravity
                peakHeights[i] = max(0.0, peakHeights[i] - peakVelocity[i])
            }
        }
        
        // Update matrix rain
        let h = bounds.height
        for i in 0..<matrixDrops.count {
            matrixDrops[i].y -= matrixDrops[i].speed
            if matrixDrops[i].y < -200 {
                matrixDrops[i].y = h + CGFloat.random(in: 20...100)
                matrixDrops[i].speed = CGFloat.random(in: 4...12)
            }
        }
        
        if currentPreset == .spectrogram { spectrogram.advance(playing: isPlaying) }
        if currentPreset == .waveform { scrollingWaveform.advance(playing: isPlaying) }

        // Update solar orb particles
        for i in 0..<solarParticles.count {
            solarParticles[i].angle += solarParticles[i].speed * 0.015
        }
        
        needsDisplay = true
    }
    
    // MARK: - Drawing Engine
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: bounds)
        let w = bounds.width
        let h = bounds.height
        
        // Background
        context.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1.0))
        context.fill(bounds)
        
        // Render Active Preset
        switch currentPreset {
        case .fireSpectrum:
            drawFireSpectrum(in: context, width: w, height: h)
        case .phosphorOscilloscope:
            drawPhosphorOscilloscope(in: context, width: w, height: h)
        case .neonCyber:
            drawNeonCyber(in: context, width: w, height: h)
        case .matrixRain:
            drawMatrixRain(in: context, width: w, height: h)
        case .solarOrb:
            drawSolarOrb(in: context, width: w, height: h)
        case .spectrogram:
            drawSpectrogram(in: context, width: w, height: h)
        case .waveform:
            scrollingWaveform.draw(in: context, rect: bounds, palette: PersistenceManager.shared.state.waveformPalette)
        case .milkdrop, .goom, .avs:
            return
        }
        
        // CRT Scanline Overlay
        if !isScrolling { drawCRTScanlines(in: context, width: w, height: h) }

    }
    
    // MARK: - Preset 0: Fire Spectrum & Peaks
    private func drawFireSpectrum(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let barCount = min(64, spectrum.count)
        let spacing: CGFloat = 3.0
        let totalSpacing = spacing * CGFloat(barCount + 1)
        let barWidth = max(2.0, (w - totalSpacing) / CGFloat(barCount))
        let maxBarHeight = h * 0.65
        let baseY = h * 0.22
        
        // Floor Mirror Horizon
        context.setStrokeColor(CGColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.4))
        context.setLineWidth(1.0)
        context.strokeLineSegments(between: [CGPoint(x: 0, y: baseY), CGPoint(x: w, y: baseY)])
        
        for i in 0..<barCount {
            let amp = CGFloat(spectrum[i])
            let barH = max(2.0, amp * maxBarHeight)
            let x = spacing + CGFloat(i) * (barWidth + spacing)
            
            // Draw Main Vertical Bar (Gradient from bottom red to yellow to top white)
            let barRect = CGRect(x: x, y: baseY, width: barWidth, height: barH)
            drawVerticalGradientBar(in: context, rect: barRect, amp: amp)
            
            // Floor Reflection (Faded downwards)
            let mirrorH = barH * 0.4
            let mirrorRect = CGRect(x: x, y: baseY - mirrorH, width: barWidth, height: mirrorH)
            context.saveGState()
            context.setAlpha(0.25)
            drawVerticalGradientBar(in: context, rect: mirrorRect, amp: amp, isMirrored: true)
            context.restoreGState()
            
            // Peak Dot
            let peakH = CGFloat(peakHeights[i]) * maxBarHeight
            let peakY = baseY + peakH + 3.0
            context.setFillColor(CGColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 0.9))
            context.fill(CGRect(x: x, y: peakY, width: barWidth, height: 3.0))
        }
    }
    
    private func drawVerticalGradientBar(in context: CGContext, rect: CGRect, amp: CGFloat, isMirrored: Bool = false) {
        let colors = [
            CGColor(red: 0.85, green: 0.05, blue: 0.0, alpha: 1.0),   // Red
            CGColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),    // Orange
            CGColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1.0),    // Yellow
            CGColor(red: 1.0, green: 1.0, blue: 0.95, alpha: 1.0)    // White tip
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: (isMirrored ? colors.reversed() : colors) as CFArray, locations: [0.0, 0.4, 0.8, 1.0])!
        
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: isMirrored ? rect.maxY : rect.minY),
            end: CGPoint(x: rect.midX, y: isMirrored ? rect.minY : rect.maxY),
            options: []
        )
        context.restoreGState()
    }
    
    // MARK: - Preset 1: Phosphor CRT Oscilloscope
    private func drawPhosphorOscilloscope(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let count = waveform.count
        guard count > 1 else { return }
        
        let midY = h * 0.5
        let ampScale = h * 0.35
        let stepX = w / CGFloat(count - 1)
        
        // Multi-pass glow:
        // Pass 1: Wide Phosphor Halo (Blurry green/cyan)
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.0, green: 0.8, blue: 0.5, alpha: 0.15))
        context.setLineWidth(14.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawWaveformPath(in: context, count: count, midY: midY, ampScale: ampScale, stepX: stepX)
        context.strokePath()
        context.restoreGState()
        
        // Pass 2: Medium Neon Glow
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.1, green: 0.95, blue: 0.6, alpha: 0.45))
        context.setLineWidth(5.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawWaveformPath(in: context, count: count, midY: midY, ampScale: ampScale, stepX: stepX)
        context.strokePath()
        context.restoreGState()
        
        // Pass 3: Brilliant Electron Beam Core
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.85, green: 1.0, blue: 0.9, alpha: 1.0))
        context.setLineWidth(1.8)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawWaveformPath(in: context, count: count, midY: midY, ampScale: ampScale, stepX: stepX)
        context.strokePath()
        context.restoreGState()
    }
    
    private func drawWaveformPath(in context: CGContext, count: Int, midY: CGFloat, ampScale: CGFloat, stepX: CGFloat) {
        context.beginPath()
        for i in 0..<count {
            let sample = CGFloat(waveform[i])
            let pt = CGPoint(x: CGFloat(i) * stepX, y: midY + sample * ampScale)
            if i == 0 {
                context.move(to: pt)
            } else {
                context.addLine(to: pt)
            }
        }
    }
    
    // MARK: - Preset 2: Neon Cyber City
    private func drawNeonCyber(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let barCount = min(48, spectrum.count)
        let midX = w * 0.5
        let midY = h * 0.5
        let barW = max(3.0, (w * 0.45) / CGFloat(barCount))
        let maxLen = h * 0.4
        
        for i in 0..<barCount {
            let amp = CGFloat(spectrum[i])
            let len = max(4.0, amp * maxLen)
            let offset = CGFloat(i) * (barW + 2.0)
            
            // Right Side: Neon Cyan
            let rX = midX + 6.0 + offset
            let rectR = CGRect(x: rX, y: midY - len * 0.5, width: barW, height: len)
            context.setFillColor(CGColor(red: 0.0, green: 0.88, blue: 1.0, alpha: 0.85))
            context.fill(rectR)
            
            // Left Side: Neon Magenta / Violet
            let lX = midX - 6.0 - offset - barW
            let rectL = CGRect(x: lX, y: midY - len * 0.5, width: barW, height: len)
            context.setFillColor(CGColor(red: 0.95, green: 0.1, blue: 0.85, alpha: 0.85))
            context.fill(rectL)
        }
    }
    
    // MARK: - Preset 3: Matrix Digital Rain
    private func initMatrixDrops() {
        matrixDrops.removeAll()
        let chars = Array("0123456789ABCDEF!@#$%&*+-=<>WINAMP")
        let cols = 50
        for i in 0..<cols {
            let colChars = (0..<15).map { _ in chars.randomElement()! }
            let drop = MatrixDrop(
                x: CGFloat(i) * 28.0 + 10.0,
                y: CGFloat.random(in: 100...900),
                speed: CGFloat.random(in: 4...10),
                chars: colChars
            )
            matrixDrops.append(drop)
        }
    }
    
    private func drawMatrixRain(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        let bassAmp = CGFloat(spectrum.prefix(6).reduce(0, +) / 6.0)
        
        for (idx, drop) in matrixDrops.enumerated() {
            let specIdx = min(spectrum.count - 1, idx % spectrum.count)
            let colEnergy = CGFloat(spectrum[specIdx])
            
            for (charIdx, char) in drop.chars.enumerated() {
                let charY = drop.y - CGFloat(charIdx * 18)
                guard charY > -20 && charY < h + 20 else { continue }
                
                let isHead = (charIdx == 0)
                let alpha = isHead ? 1.0 : max(0.1, 0.9 - CGFloat(charIdx) * 0.06)
                let glowBoost = 1.0 + (colEnergy + bassAmp) * 0.5
                
                let textColor = isHead
                    ? NSColor(red: 0.85, green: 1.0, blue: 0.85, alpha: alpha)
                    : NSColor(red: 0.05 * glowBoost, green: 0.9 * glowBoost, blue: 0.2 * glowBoost, alpha: alpha)
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor
                ]
                
                let str = String(char) as NSString
                str.draw(at: CGPoint(x: drop.x, y: charY), withAttributes: attrs)
            }
        }
    }
    
    // MARK: - Preset 4: Solar Radial Orb
    private func initSolarParticles() {
        solarParticles.removeAll()
        for _ in 0..<60 {
            let p = SolarParticle(
                angle: CGFloat.random(in: 0...(CGFloat.pi * 2)),
                distance: CGFloat.random(in: 120...320),
                speed: CGFloat.random(in: 0.5...2.0),
                size: CGFloat.random(in: 2...5),
                alpha: CGFloat.random(in: 0.3...0.8)
            )
            solarParticles.append(p)
        }
    }
    
    private func drawSolarOrb(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let center = CGPoint(x: w * 0.5, y: h * 0.5)
        let bassAmp = CGFloat(spectrum.prefix(4).reduce(0, +) / 4.0)
        let baseRadius: CGFloat = 80.0 + bassAmp * 45.0
        
        // 1. Center Glowing Core
        context.saveGState()
        let coreColor = CGColor(red: 1.0, green: 0.6 + bassAmp * 0.3, blue: 0.1, alpha: 0.8)
        context.setFillColor(coreColor)
        context.fillEllipse(in: CGRect(x: center.x - baseRadius, y: center.y - baseRadius, width: baseRadius * 2, height: baseRadius * 2))
        context.restoreGState()
        
        // 2. 360-degree Radial Spikes
        let rayCount = 48
        let angleStep = (CGFloat.pi * 2) / CGFloat(rayCount)
        context.saveGState()
        context.setLineWidth(3.0)
        context.setLineCap(.round)
        
        for i in 0..<rayCount {
            let angle = CGFloat(i) * angleStep
            let specIdx = min(spectrum.count - 1, i % spectrum.count)
            let amp = CGFloat(spectrum[specIdx])
            let rayLen = baseRadius + 15.0 + amp * 160.0
            
            let startX = center.x + cos(angle) * (baseRadius + 5.0)
            let startY = center.y + sin(angle) * (baseRadius + 5.0)
            let endX = center.x + cos(angle) * rayLen
            let endY = center.y + sin(angle) * rayLen
            
            context.setStrokeColor(CGColor(red: 1.0, green: 0.3 + amp * 0.7, blue: 0.1, alpha: 0.75))
            context.strokeLineSegments(between: [CGPoint(x: startX, y: startY), CGPoint(x: endX, y: endY)])
        }
        context.restoreGState()
        
        // 3. Orbiting Particles
        for p in solarParticles {
            let px = center.x + cos(p.angle) * p.distance
            let py = center.y + sin(p.angle) * p.distance
            context.setFillColor(CGColor(red: 1.0, green: 0.9, blue: 0.4, alpha: p.alpha))
            context.fillEllipse(in: CGRect(x: px - p.size * 0.5, y: py - p.size * 0.5, width: p.size, height: p.size))
        }
    }
    
    // MARK: - Spectrogram
    private func drawSpectrogram(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        if let image = spectrogram.image(palette: PersistenceManager.shared.state.spectrogramPalette) {
            context.interpolationQuality = .medium
            context.draw(image, in: bounds)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.7)
        ]
        for grid in Spectrogram.gridFrequencies {
            let y = h * CGFloat(Spectrogram.position(of: grid.hz))
            (grid.title as NSString).draw(at: CGPoint(x: 8, y: y - 6), withAttributes: attrs)
        }
    }

    // MARK: - CRT Scanlines
    private func drawCRTScanlines(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.12))
        context.setLineWidth(1.0)
        
        var y: CGFloat = 0
        while y < h {
            context.strokeLineSegments(between: [CGPoint(x: 0, y: y), CGPoint(x: w, y: y)])
            y += 3.0
        }
        context.restoreGState()
    }
}

/// The hints' layer: it never takes the clicks and drags meant for the visualizer under it
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension RetroVisualizerView: NSMenuDelegate {
    /// A MilkDrop folder's submenu, its path as the title, filled the first time it opens
    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.items.isEmpty else { return }
        addMilkdropPresetItems(in: URL(fileURLWithPath: menu.title, isDirectory: true), to: menu)
    }
}
