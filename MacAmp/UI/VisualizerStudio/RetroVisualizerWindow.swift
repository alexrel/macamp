import Cocoa

/// A dedicated fullscreen/standalone window for the Retro Visualizer Studio (AVS style).
public final class RetroVisualizerWindow: NSWindow {
    
    public let studioView: RetroVisualizerView
    
    public init() {
        let initialRect = NSRect(x: 100, y: 100, width: 800, height: 500)
        
        self.studioView = RetroVisualizerView(frame: NSRect(origin: .zero, size: initialRect.size))
        
        super.init(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Winamp Retro Visualizer Studio"
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.backgroundColor = .black
        self.isOpaque = true
        self.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        self.minSize = NSSize(width: 480, height: 320)
        self.contentView = studioView
        
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
    
    public override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        studioView.startAnimation()
        makeFirstResponder(studioView)
    }
    
    public override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        studioView.stopAnimation()
    }
}
