import Cocoa

/// A dedicated fullscreen/standalone window for the Retro Visualizer Studio (AVS style).
public final class RetroVisualizerWindow: NSWindow, NSWindowDelegate {
    static let studioMinimumSize = NSSize(width: 480, height: 320)
    
    public let studioView: RetroVisualizerView
    let frameView: GenWindowFrameView
    private let skinManager = SkinManager.shared
    
    public init() {
        let initialRect = NSRect(x: 100, y: 100, width: 800, height: 500)
        
        let studio = RetroVisualizerView(frame: NSRect(origin: .zero, size: initialRect.size))
        studioView = studio
        frameView = GenWindowFrameView(title: "Visualizer Studio", content: studio)
        
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // The coordinator retains the window between uses.
        self.isReleasedWhenClosed = false
        self.title = "Winamp Retro Visualizer Studio"
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        self.contentMinSize = Self.studioMinimumSize
        self.contentView = frameView
        self.delegate = self
        updateSkinMask()
        frameView.onClose = { [weak self] in self?.orderOut(nil) }
        studioView.onPresetChanged = { [weak self] preset in
            switch preset {
            case .milkdrop: self?.frameView.title = "MilkDrop"
            case .goom: self?.frameView.title = "What A Goom"
            default: self?.frameView.title = "Visualizer Studio"
            }
            if let title = self?.frameView.title { self?.title = title }
        }
        
        // Window Actions
        studioView.onExit = { [weak self] in
            if self?.styleMask.contains(.fullScreen) == true {
                self?.toggleFullScreen(nil)
            } else {
                self?.orderOut(nil)
            }
        }
        
        studioView.onToggleFullScreen = { [weak self] in
            self?.toggleFullScreen(nil)
        }
        
        center()
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    func updateSkinMask() {
        let region = skinManager.currentSkin?.region
        let path = frameView.isFrameHidden ? nil : region?.normalMask(fitting: frameView.bounds.size)
        PlayerCoordinator.applyWindowMask(path: path, to: frameView)
    }

    private func showFrame(_ show: Bool) {
        frameView.isFrameHidden = !show
        updateSkinMask()
    }

    public func windowDidResize(_ notification: Notification) { updateSkinMask() }
    public func windowWillEnterFullScreen(_ notification: Notification) { showFrame(false) }
    public func windowDidExitFullScreen(_ notification: Notification) { showFrame(true) }
    public func windowDidFailToEnterFullScreen(_ window: NSWindow) { showFrame(true) }
    
    public func updateSpectrum(_ spectrum: [Float]) {
        // Expand 19 or 32 bands to 64 interpolated bands for smooth rendering
        if spectrum.count == 64 {
            studioView.spectrum = spectrum
            return
        }
        
        guard !spectrum.isEmpty else { return }
        var interpolated = [Float](repeating: 0.0, count: 64)
        let ratio = Float(spectrum.count - 1) / 63.0
        
        for i in 0..<64 {
            let srcPos = Float(i) * ratio
            let idx = Int(srcPos)
            let frac = srcPos - Float(idx)
            let v1 = spectrum[idx]
            let v2 = (idx + 1 < spectrum.count) ? spectrum[idx + 1] : v1
            interpolated[i] = v1 + (v2 - v1) * frac
        }
        studioView.spectrum = interpolated
    }
    
    public func updateWaveform(_ wave: [Float]) {
        studioView.waveform = wave
    }
    
    // Every show / hide goes through here (makeKeyAndOrderFront skips orderFront: after a close the Studio stayed black and deaf to keys)
    public override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        if place == .out {
            studioView.closeVisualization()
        } else {
            makeFirstResponder(studioView)
        }
    }
}
