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
    
    public var title: String {
        switch self {
        case .fireSpectrum: return "Fire Spectrum & Peak Glow"
        case .phosphorOscilloscope: return "Retro Phosphor CRT Oscilloscope"
        case .neonCyber: return "Neon Cyber City Spectrum"
        case .matrixRain: return "Matrix Digital Rain"
        case .solarOrb: return "Solar Radial Orb"
        case .milkdrop: return "Milkdrop (projectM)"
        case .goom: return "What A Goom!"
        }
    }
}

/// A high-performance 60 FPS retro visualizer canvas with multiple classic AVS-inspired modes,
/// CRT phosphor glow, floor reflections, particle dynamics, and an auto-fading HUD.
public final class RetroVisualizerView: NSView {
    
    // MARK: - Properties
    public var currentPreset: StudioVisualizerPreset = .fireSpectrum {
        didSet {
            if oldValue != currentPreset { closeSelectionList() }
            triggerHUD()
            syncMilkdrop()
            syncGoom()
            updateAnimation()
            onPresetChanged?(currentPreset)
            needsDisplay = true
        }
    }

    // Milkdrop sits on top of the view as a GL subview and exists only while it is the shown preset
    private var milkdropView: MilkdropView?
    private var milkdropLabel: NSTextField?
    private var selectionList: VisualizerSelectionList?
    private var milkdropListedPresets: [URL] = []
    private var milkdropTick = 0
    private var showMilkdropInfo = true // F5 toggles preset name and FPS
    private var isOnScreen = false
    private var isPlaying = false
    private var goomView: GoomView?
    // GOOM's filter IDs are zero-based, while its force-effect commands start at 1.
    private static let goomEffects = [
        (key: kVK_F1, title: "Normal"), (key: kVK_F2, title: "Wave"),
        (key: kVK_F3, title: "Crystal Ball"), (key: kVK_F4, title: "Scrunch"),
        (key: kVK_F5, title: "Amulette"), (key: kVK_F6, title: "Water"),
        (key: kVK_F7, title: "Hypercos I"), (key: kVK_F8, title: "Hypercos II")
    ]

    /// The plate is as wide as its text, cut off (with …) only when the window is narrower
    private func layoutMilkdropLabel() {
        guard let label = milkdropLabel else { return }
        let width = max(0, min(label.intrinsicContentSize.width, bounds.width - 20))
        label.frame = NSRect(x: bounds.width - width - 10, y: bounds.height - 26, width: width, height: 18)
    }

    private func syncMilkdrop(closing: Bool = false) {
        if currentPreset == .milkdrop && !closing {
            guard isOnScreen, milkdropLabel == nil else { return }
            if let view = MilkdropView(studioFrame: bounds) {
                view.isOnScreen = true
                addSubview(view)
                milkdropView = view
                view.onPresetsChanged = { [weak self] in
                    self?.reloadMilkdropPresetList()
                    self?.updateAnimation()
                    self?.updateMilkdropLabel()
                }
            }
            let label = NSTextField(labelWithString: "")
            label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .white
            label.drawsBackground = true
            label.backgroundColor = NSColor.black.withAlphaComponent(0.55)
            label.lineBreakMode = .byTruncatingTail
            label.alignment = .right
            label.autoresizingMask = [.minXMargin, .minYMargin]
            label.isHidden = !showMilkdropInfo
            addSubview(label)
            milkdropLabel = label
            updateMilkdropLabel()
        } else {
            milkdropView?.shutdown()
            milkdropView?.removeFromSuperview()
            milkdropLabel?.removeFromSuperview()
            milkdropView = nil
            milkdropLabel = nil
        }
    }

    private func updateMilkdropLabel() {
        guard let label = milkdropLabel else { return }
        if let failed = milkdropView?.failedPresetName {
            label.stringValue = " Could not load \(failed) "
            label.isHidden = false
        } else if let view = milkdropView, !view.initializationFailed {
            let status = !isPlaying && Date() >= view.renderUntil ? "paused" : (view.fps > 0 ? "\(view.fps) FPS" : "starting")
            label.stringValue = " \(status)  ·  \(view.presetName)  ·  L = presets "
            label.isHidden = !showMilkdropInfo
        } else {
            label.stringValue = " MilkDrop could not start "
        }
        layoutMilkdropLabel()
    }

    public override func layout() {
        super.layout()
        layoutMilkdropLabel()
        layoutSelectionList()
    }

    private func layoutSelectionList() {
        guard let list = selectionList else { return }
        let height = min(list.contentHeight, floor(bounds.height * 0.72))
        list.frame = NSRect(x: 12, y: bounds.height - 28 - height, width: max(0, bounds.width - 36), height: height)
    }

    @objc private func toggleSelectionList() {
        if selectionList != nil {
            closeSelectionList()
            return
        }
        if let view = goomView {
            let list = VisualizerSelectionList(frame: .zero, titles: Self.goomEffects.map(\.title),
                                               selectedRow: view.lastForcedEffect.map { $0 - 1 },
                                               accessibilityLabel: "GOOM effects")
            list.onSelectionChanged = { [weak view] in view?.forceEffect($0 + 1) }
            showSelectionList(list, above: view)
            return
        }
        guard let view = milkdropView else { return }
        let list = VisualizerSelectionList(frame: .zero, titles: [], selectedRow: nil, accessibilityLabel: "MilkDrop presets")
        list.onSelectionChanged = { [weak self] in self?.applyMilkdropPreset(at: $0) }
        list.onOpenFolder = { MilkdropView.openPresetsFolder() }
        showSelectionList(list, above: view)
        view.stopPresetClock()
        reloadMilkdropPresetList()
        view.rescanPresets()
    }

    private func showSelectionList(_ list: VisualizerSelectionList, above view: NSView) {
        list.onKeyDown = { [weak self] in self?.keyDown(with: $0) }
        addSubview(list, positioned: .above, relativeTo: view)
        selectionList = list
        layoutSelectionList()
        list.focusList()
    }

    private func reloadMilkdropPresetList() {
        guard let list = selectionList, let view = milkdropView else { return }
        let presets = view.presets
        let selectedURL = list.selectedRow.flatMap { milkdropListedPresets.indices.contains($0) ? milkdropListedPresets[$0] : nil }
        let selectedRow = (selectedURL ?? view.currentPresetURL).flatMap { presets.firstIndex(of: $0) }
        milkdropListedPresets = presets
        list.reload(titles: presets.map { $0.deletingPathExtension().lastPathComponent }, selectedRow: selectedRow)
        layoutSelectionList()
        list.focusList()
    }

    private func closeSelectionList() {
        guard let list = selectionList else { return }
        window?.makeFirstResponder(self)
        list.removeFromSuperview()
        selectionList = nil
        milkdropListedPresets = []
    }

    private func applyMilkdropPreset(at row: Int) {
        milkdropView?.selectPreset(at: row, smooth: false)
        updateAnimation()
        updateMilkdropLabel()
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
    private var hudAlpha: CGFloat = 1.0
    private var lastUserActivity: TimeInterval = Date().timeIntervalSince1970
    
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
        isOnScreen = visible
        isPlaying = playing
        syncMilkdrop()
        syncGoom()
        milkdropView?.isOnScreen = visible
        if !visible || !playing { milkdropView?.stopPresetClock() }
        updateAnimation()
    }

    func updateAnimation() {
        let milkdrop = currentPreset == .milkdrop
        let canRenderMilkdrop = milkdropView.map { !$0.initializationFailed } ?? false
        VisualizerPCMFeed.setActive(isOnScreen && isPlaying && (goomView != nil || (milkdrop && canRenderMilkdrop)))
        let previewing = milkdropView.map { Date() < $0.renderUntil } ?? false
        guard isOnScreen && (!milkdrop || (canRenderMilkdrop && (isPlaying || previewing))) else {
            displayTimer?.invalidate()
            displayTimer = nil
            updateMilkdropLabel()
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
        closeSelectionList()
        isOnScreen = false
        syncMilkdrop(closing: true)
        syncGoom(closing: true)
        updateAnimation()
    }
    
    // MARK: - Input & Hotkeys
    public override func mouseMoved(with event: NSEvent) {
        triggerHUD()
    }
    
    // A click switches the preset, a drag moves the window (the window has no title bar to grab)
    private var mouseDownEvent: NSEvent?

    public override func mouseDown(with event: NSEvent) {
        triggerHUD()
        mouseDownEvent = event
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        mouseDownEvent = nil
        window?.performDrag(with: down)
    }

    public override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil else { return }
        mouseDownEvent = nil
        // Milkdrop has its own , / . keys; a stray click must not throw the user out of it
        if currentPreset != .milkdrop && currentPreset != .goom { cyclePreset() }
    }
    
    public override func keyDown(with event: NSEvent) {
        triggerHUD()
        if (currentPreset == .milkdrop || currentPreset == .goom) && handleSelectionListKey(event) { return }
        if currentPreset == .goom && handleGoomKey(event) { return }
        
        switch event.keyCode {
        case 53: // Esc -> Exit
            onExit?()
        case 3: // 'F' -> Toggle Fullscreen
            onToggleFullScreen?()
        case 49, 48: // Space / Tab -> next Studio visualization (everywhere, so Milkdrop can be left the same way)
            cyclePreset()
        // Milkdrop presets on , / . (physical keys, so б / ю on a Russian layout); letters stay the player's hotkeys
        case 43 where currentPreset == .milkdrop: // ',' -> previous Milkdrop preset
            milkdropView?.nextPreset(backwards: true)
            updateAnimation()
        case 47 where currentPreset == .milkdrop: // '.' -> next Milkdrop preset
            milkdropView?.nextPreset()
            updateAnimation()
        case 96 where currentPreset == .milkdrop: // F5 -> show / hide preset name and FPS
            showMilkdropInfo.toggle()
            milkdropLabel?.isHidden = !showMilkdropInfo
            updateMilkdropLabel()
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

    private func handleSelectionListKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return false }
        let key = Int(event.keyCode)
        if key == kVK_ANSI_L {
            if !event.isARepeat { toggleSelectionList() }
            return true
        }
        guard let list = selectionList else { return false }
        switch key {
        case kVK_UpArrow, kVK_ANSI_Comma: list.moveSelection(by: -1)
        case kVK_DownArrow, kVK_ANSI_Period: list.moveSelection(by: 1)
        case kVK_PageUp: list.moveSelection(by: -10)
        case kVK_PageDown: list.moveSelection(by: 10)
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape: closeSelectionList()
        default: return false
        }
        return true
    }

    private func handleGoomKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = Int(event.keyCode)
        if modifiers == [.option] && (key == kVK_Return || key == kVK_ANSI_KeypadEnter) {
            onToggleFullScreen?()
            return true
        }
        guard modifiers.isEmpty else { return PlayerCoordinator.shared.handleKeyDown(event) }
        if let effect = Self.goomEffects.firstIndex(where: { $0.key == key }) {
            goomView?.forceEffect(effect + 1)
            return true
        }
        switch key {
        case kVK_Space: goomView?.showCredits()
        case kVK_ANSI_M: goomView?.toggleCube()
        case kVK_Escape where goomView?.isShowingCredits == true: goomView?.hideCredits()
        case kVK_ANSI_KeypadPlus where goomView?.isCube == true: goomView?.moveCamera(by: -1)
        case kVK_ANSI_KeypadMinus where goomView?.isCube == true: goomView?.moveCamera(by: 1)
        case kVK_ANSI_F, kVK_Escape, kVK_Tab: return false
        default: return PlayerCoordinator.shared.handleKeyDown(event)
        }
        return true
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        guard currentPreset == .milkdrop || currentPreset == .goom else { return super.menu(for: event) }
        let menu = NSMenu()
        let selectionTitle = currentPreset == .milkdrop ? "Load Preset…" : "Choose Effect…"
        let selection = NSMenuItem(title: selectionTitle, action: #selector(toggleSelectionList), keyEquivalent: "")
        selection.target = self
        menu.addItem(selection)
        if currentPreset == .milkdrop {
            let fullScreen = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
            fullScreen.target = window
            menu.addItem(fullScreen)
            return menu
        }
        for factor in [1, 2, 4] {
            let item = NSMenuItem(title: "Zoom \(factor)×", action: #selector(zoomGoom(_:)), keyEquivalent: "")
            item.target = self
            item.tag = factor
            menu.addItem(item)
        }
        return menu
    }

    @objc private func zoomGoom(_ item: NSMenuItem) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let options = PersistenceManager.shared.state.goomOptions
        let width = goomView?.isCube == true ? GoomView.cubeTextureSize : options.renderWidth
        let height = goomView?.isCube == true ? GoomView.cubeTextureSize : options.renderHeight
        let insets = GenWindowFrameView.insets
        window.setContentSize(NSSize(width: CGFloat(width * item.tag) + insets.left + insets.right,
                                     height: CGFloat(height * item.tag) + insets.top + insets.bottom))
    }
    
    public func cyclePreset() {
        let nextRaw = (currentPreset.rawValue + 1) % StudioVisualizerPreset.allCases.count
        currentPreset = StudioVisualizerPreset(rawValue: nextRaw) ?? .fireSpectrum
    }
    
    private func triggerHUD() {
        lastUserActivity = Date().timeIntervalSince1970
        hudAlpha = 1.0
        needsDisplay = true
    }
    
    // MARK: - Update Tick
    private func renderTick() {
        if let goomView {
            let trackTitle = isPlaying ? PlayerCoordinator.shared.playlist.currentTrack?.displayName : nil
            goomView.renderFrame(playing: isPlaying, trackTitle: trackTitle)
            return
        }
        if currentPreset == .milkdrop, let milkdropView {
            guard !milkdropView.initializationFailed && (isPlaying || Date() < milkdropView.renderUntil) else {
                updateAnimation()
                return
            }
            milkdropView.renderFrame(playing: isPlaying && selectionList == nil)
            milkdropTick += 1
            if milkdropTick % 30 == 0, showMilkdropInfo { updateMilkdropLabel() }
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
        
        // HUD fade out after 3.5 seconds
        let idleTime = now - lastUserActivity
        if idleTime > 3.0 {
            let fade = CGFloat(max(0.0, 1.0 - (idleTime - 3.0) * 1.5))
            hudAlpha = fade
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
        case .milkdrop, .goom:
            return
        }
        
        // CRT Scanline Overlay
        drawCRTScanlines(in: context, width: w, height: h)
        
        // HUD Overlay
        if hudAlpha > 0.01 {
            drawHUD(in: context, width: w, height: h, alpha: hudAlpha)
        }
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
    
    // MARK: - HUD Overlay
    private func drawHUD(in context: CGContext, width w: CGFloat, height h: CGFloat, alpha: CGFloat) {
        let coord = PlayerCoordinator.shared
        let track = coord.playlist.currentTrack
        let status = coord.audioEngine.status
        let time = coord.audioEngine.currentTime
        let total = track?.duration ?? 0
        let statusStr = (status == .playing) ? "PLAYING" : ((status == .paused) ? "PAUSED" : "STOPPED")
        
        let titleStr = track?.title ?? "Winamp Studio"
        let artistStr = track?.artist ?? "MacAmp \(AppConstants.App.version)"
        
        let curM = Int(time) / 60
        let curS = Int(time) % 60
        let timeStr: String
        if total > 0 {
            let totM = Int(total) / 60
            let totS = Int(total) % 60
            timeStr = String(format: "%02d:%02d / %02d:%02d", curM, curS, totM, totS)
        } else {
            timeStr = String(format: "%02d:%02d (LIVE)", curM, curS)
        }
        
        // Top-Right: Preset info & FPS
        let presetStr = "PRESET [\(currentPreset.rawValue + 1)/\(StudioVisualizerPreset.allCases.count)]: \(currentPreset.title.uppercased())  •  \(currentFPS) FPS"
        let topAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(white: 0.9, alpha: alpha)
        ]
        let topSize = (presetStr as NSString).size(withAttributes: topAttrs)
        (presetStr as NSString).draw(at: CGPoint(x: w - topSize.width - 24, y: h - topSize.height - 20), withAttributes: topAttrs)
        
        // Bottom-Left: Track Title & Transport Status
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor(white: 1.0, alpha: alpha)
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(white: 0.75, alpha: alpha)
        ]
        let helpAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor(white: 0.5, alpha: alpha)
        ]
        
        (artistStr as NSString).draw(at: CGPoint(x: 28, y: 72), withAttributes: subAttrs)
        (titleStr as NSString).draw(at: CGPoint(x: 28, y: 48), withAttributes: titleAttrs)
        let subLine = "[\(statusStr)]  \(timeStr)  •  MacAmp AVS Studio"
        (subLine as NSString).draw(at: CGPoint(x: 28, y: 30), withAttributes: subAttrs)
        
        let helpLine = "[Space / Click]: Change Preset   |   [F]: Fullscreen   |   [Esc]: Exit   |   [←/→]: Tracks   |   [↑/↓]: Volume"
        (helpLine as NSString).draw(at: CGPoint(x: 28, y: 12), withAttributes: helpAttrs)
    }
}
