import Cocoa

/// A dedicated fullscreen/standalone window for the Retro Visualizer Studio (AVS style).
public final class RetroVisualizerWindow: WinampWindow, NSWindowDelegate {
    static let studioMinimumSize = NSSize(width: 480, height: 320)
    private static let initialSize = NSSize(width: 800, height: 500)
    
    public let studioView: RetroVisualizerView
    let frameView: GenWindowFrameView
    private let skinManager = SkinManager.shared
    private var interfaceScale: CGFloat = 1
    private var windowedSize = initialSize
    
    public init() {
        let initialRect = NSRect(origin: NSPoint(x: 100, y: 100), size: Self.initialSize)
        
        let studio = RetroVisualizerView(frame: NSRect(origin: .zero, size: initialRect.size))
        studioView = studio
        frameView = GenWindowFrameView(title: "Visualizer Studio", content: studio)
        
        // A WinampWindow: magnetic docking with the player windows and the screen edges
        super.init(windowID: .studio, contentRect: initialRect)
        styleMask.insert(.resizable) // native full screen
        self.title = "Winamp Retro Visualizer Studio"
        self.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        self.contentView = frameView
        self.delegate = self
        updateInterfaceScale()
        frameView.onClose = { [weak self] in self?.orderOut(nil) }
        studioView.onPresetChanged = { [weak self] preset in
            switch preset {
            case .milkdrop: self?.frameView.title = "MilkDrop"
            case .goom: self?.frameView.title = "What A Goom"
            case .avs: self?.frameView.title = "AVS"
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

    func updateInterfaceScale() {
        let scale = PersistenceManager.shared.state.interfaceScale.multiplier
        interfaceScale = scale
        let visible = (screen ?? NSScreen.main)?.visibleFrame
        contentMinSize = NSSize(width: min(Self.studioMinimumSize.width * scale, visible?.width ?? .infinity),
                                height: min(Self.studioMinimumSize.height * scale, visible?.height ?? .infinity))
        if !frameView.isFrameHidden, !styleMask.contains(.fullScreen) {
            let preferred = windowedSize
            let size = NSSize(width: min((preferred.width * scale).rounded(), visible?.width ?? .infinity),
                              height: min((preferred.height * scale).rounded(), visible?.height ?? .infinity))
            var origin = NSPoint(x: frame.minX, y: frame.maxY - size.height)
            if let visible {
                origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
                origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
            }
            let newFrame = NSRect(origin: origin, size: size)
            if newFrame != frame { setFrame(newFrame, display: true) }
            // setFrame ran windowDidResize, which recorded the screen-clamped size: keep the size the user chose,
            // so a smaller scale brings it back
            windowedSize = preferred
        }
        updateContentScale(scale)
    }

    // No REGION.TXT shape here: it describes the main window and the equalizer only, and stretched over this frame
    // it cut holes in it (SFCommandSkin.wsz). The Library, Video and Minibrowser windows are plain rectangles too.
    private func showFrame(_ show: Bool) {
        frameView.isFrameHidden = !show
    }

    public func windowDidResize(_ notification: Notification) {
        updateContentScale(interfaceScale)
        if !frameView.isFrameHidden { windowedSize = frameView.bounds.size }
    }
    // In full screen it is no window to dock to: the others would snap to the screen's edges through it
    public func windowWillEnterFullScreen(_ notification: Notification) {
        WindowLayoutManager.shared.unregister(id: .studio)
        showFrame(false)
    }
    public func windowDidExitFullScreen(_ notification: Notification) {
        WindowLayoutManager.shared.register(window: self, for: .studio)
        showFrame(true)
        updateInterfaceScale()
    }
    public func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        WindowLayoutManager.shared.register(window: self, for: .studio)
        showFrame(true)
    }
    
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
