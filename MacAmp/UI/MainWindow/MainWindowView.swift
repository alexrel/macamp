import Cocoa
import Foundation

public class MainWindowView: WinampControlView {
    // Sub-components
    public let timeDisplay = TimeDisplayView()
    public let visualizer = VisualizerView()
    public let marquee = MarqueeView()
    
    // Sliders
    public private(set) var volumeSlider: SkinSlider!
    public private(set) var balanceSlider: SkinSlider!
    public private(set) var seekSlider: SkinSlider!
    
    // Toggles
    public private(set) var eqToggle: SkinToggle!
    public private(set) var plToggle: SkinToggle!
    public private(set) var shuffleToggle: SkinToggle!
    public private(set) var repeatToggle: SkinToggle!
    
    // Transport Buttons
    public private(set) var prevButton: SkinButton!
    public private(set) var playButton: SkinButton!
    public private(set) var pauseButton: SkinButton!
    public private(set) var stopButton: SkinButton!
    public private(set) var nextButton: SkinButton!
    public private(set) var ejectButton: SkinButton!
    
    // Titlebar Buttons
    public private(set) var optionsButton: SkinButton!
    public private(set) var minimizeButton: SkinButton!
    public private(set) var shadeButton: SkinButton!
    public private(set) var closeButton: SkinButton!
    
    // ClutterBar D Button (Double Size toggle)
    public private(set) var doubleSizeButton: SkinButton!
    public private(set) var clutterOptionsButton: SkinButton!
    
    public var isShadeMode: Bool = false {
        didSet {
            updateLayoutForShadeMode()
            needsDisplay = true
        }
    }
    
    public var onToggleShade: (() -> Void)?
    public var onToggleDoubleSize: (() -> Void)?
    public var onOpenOptions: (() -> Void)?
    public var onEject: (() -> Void)?
    
    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.height))
        setupControls()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupControls() {
        // 1. TitleBar Buttons (y: 3)
        optionsButton = SkinButton(normal: SpriteCatalog.optionsNormal, pressed: SpriteCatalog.optionsPressed) { [weak self] in
            self?.onOpenOptions?()
        }
        optionsButton.frame = NSRect(x: 6, y: 3, width: 9, height: 9)
        addSubview(optionsButton)
        
        minimizeButton = SkinButton(normal: SpriteCatalog.minimizeNormal, pressed: SpriteCatalog.minimizePressed) { [weak self] in
            self?.window?.miniaturize(nil)
        }
        minimizeButton.frame = NSRect(x: 244, y: 3, width: 9, height: 9)
        addSubview(minimizeButton)
        
        shadeButton = SkinButton(normal: SpriteCatalog.shadeNormal, pressed: SpriteCatalog.shadePressed) { [weak self] in
            self?.onToggleShade?()
        }
        shadeButton.frame = NSRect(x: 254, y: 3, width: 9, height: 9)
        addSubview(shadeButton)
        
        closeButton = SkinButton(normal: SpriteCatalog.closeNormal, pressed: SpriteCatalog.closePressed) {
            NSApp.terminate(nil)
        }
        closeButton.frame = NSRect(x: 264, y: 3, width: 9, height: 9)
        addSubview(closeButton)
        
        // 2. ClutterBar Buttons
        clutterOptionsButton = SkinButton(normal: SpriteCatalog.clutterOActive, pressed: SpriteCatalog.clutterOActive) { [weak self] in
            self?.onOpenOptions?()
        }
        clutterOptionsButton.frame = NSRect(x: 10, y: 25, width: 8, height: 8)
        addSubview(clutterOptionsButton)
        
        doubleSizeButton = SkinButton(normal: SpriteCatalog.clutterDActive, pressed: SpriteCatalog.clutterDActive) { [weak self] in
            self?.onToggleDoubleSize?()
        }
        doubleSizeButton.frame = NSRect(x: 10, y: 47, width: 8, height: 8)
        addSubview(doubleSizeButton)
        
        // 3. Time, Visualizer, Marquee
        timeDisplay.frame = NSRect(x: 39, y: 26, width: 59, height: 13)
        addSubview(timeDisplay)
        
        visualizer.frame = NSRect(x: 24, y: 43, width: CGFloat(AppConstants.Visualizer.width), height: CGFloat(AppConstants.Visualizer.height))
        addSubview(visualizer)
        
        marquee.frame = NSRect(x: 112, y: 27, width: 152, height: 6)
        addSubview(marquee)
        
        // 4. Sliders
        volumeSlider = SkinSlider(
            frame: NSRect(x: 107, y: 57, width: 68, height: 13),
            orientation: .horizontal,
            minValue: 0.0,
            maxValue: 1.0,
            initialValue: AppConstants.Audio.defaultVolume,
            bgFrameProvider: { SpriteCatalog.volumeBg(frame: $0) },
            thumbNormal: SpriteCatalog.volumeThumb,
            thumbPressed: SpriteCatalog.volumeThumbPressed
        ) { val in
            AudioEngine.shared.setVolume(val)
        }
        addSubview(volumeSlider)
        
        balanceSlider = SkinSlider(
            frame: NSRect(x: 177, y: 57, width: 38, height: 13),
            orientation: .horizontal,
            minValue: -1.0,
            maxValue: 1.0,
            initialValue: AppConstants.Audio.defaultBalance,
            snapCenter: true,
            snapThreshold: 0.1,
            bgFrameProvider: { SpriteCatalog.balanceBg(frame: $0) },
            thumbNormal: SpriteCatalog.balanceThumb,
            thumbPressed: SpriteCatalog.balanceThumbPressed
        ) { val in
            AudioEngine.shared.setBalance(val)
        }
        addSubview(balanceSlider)
        
        seekSlider = SkinSlider(
            frame: NSRect(x: 16, y: 72, width: 248, height: 10),
            orientation: .horizontal,
            minValue: 0.0,
            maxValue: 1.0,
            initialValue: 0.0,
            background: SpriteCatalog.posBarBg,
            thumbNormal: SpriteCatalog.posBarThumb,
            thumbPressed: SpriteCatalog.posBarThumbPressed
        ) { val in
            if let meta = AudioEngine.shared.currentMetadata, meta.duration > 0 {
                AudioEngine.shared.seek(to: val * meta.duration)
            }
        }
        addSubview(seekSlider)
        
        // 5. Window Toggles (EQ, PL)
        eqToggle = SkinToggle(
            offNormal: SpriteCatalog.eqToggleOff,
            offPressed: SpriteCatalog.eqToggleOffPressed,
            onNormal: SpriteCatalog.eqToggleOn,
            onPressed: SpriteCatalog.eqToggleOnPressed,
            isOn: true
        )
        eqToggle.frame = NSRect(x: 219, y: 58, width: 23, height: 12)
        addSubview(eqToggle)
        
        plToggle = SkinToggle(
            offNormal: SpriteCatalog.plToggleOff,
            offPressed: SpriteCatalog.plToggleOffPressed,
            onNormal: SpriteCatalog.plToggleOn,
            onPressed: SpriteCatalog.plToggleOnPressed,
            isOn: true
        )
        plToggle.frame = NSRect(x: 242, y: 58, width: 23, height: 12)
        addSubview(plToggle)
        
        // 6. Transport Buttons
        prevButton = SkinButton(normal: SpriteCatalog.prevNormal, pressed: SpriteCatalog.prevPressed)
        prevButton.frame = NSRect(x: 16, y: 88, width: 23, height: 18)
        addSubview(prevButton)
        
        playButton = SkinButton(normal: SpriteCatalog.playNormal, pressed: SpriteCatalog.playPressed) {
            AudioEngine.shared.play()
        }
        playButton.frame = NSRect(x: 39, y: 88, width: 23, height: 18)
        addSubview(playButton)
        
        pauseButton = SkinButton(normal: SpriteCatalog.pauseNormal, pressed: SpriteCatalog.pausePressed) {
            AudioEngine.shared.pause()
        }
        pauseButton.frame = NSRect(x: 62, y: 88, width: 23, height: 18)
        addSubview(pauseButton)
        
        stopButton = SkinButton(normal: SpriteCatalog.stopNormal, pressed: SpriteCatalog.stopPressed) {
            AudioEngine.shared.stop()
        }
        stopButton.frame = NSRect(x: 85, y: 88, width: 23, height: 18)
        addSubview(stopButton)
        
        nextButton = SkinButton(normal: SpriteCatalog.nextNormal, pressed: SpriteCatalog.nextPressed)
        nextButton.frame = NSRect(x: 108, y: 88, width: 22, height: 18)
        addSubview(nextButton)
        
        ejectButton = SkinButton(normal: SpriteCatalog.ejectNormal, pressed: SpriteCatalog.ejectPressed) { [weak self] in
            self?.onEject?()
        }
        ejectButton.frame = NSRect(x: 136, y: 89, width: 22, height: 16)
        addSubview(ejectButton)
        
        // 7. Shuffle & Repeat
        shuffleToggle = SkinToggle(
            offNormal: SpriteCatalog.shuffleOff,
            offPressed: SpriteCatalog.shuffleOffPressed,
            onNormal: SpriteCatalog.shuffleOn,
            onPressed: SpriteCatalog.shuffleOnPressed,
            isOn: false
        )
        shuffleToggle.frame = NSRect(x: 164, y: 89, width: 47, height: 15)
        addSubview(shuffleToggle)
        
        repeatToggle = SkinToggle(
            offNormal: SpriteCatalog.repeatOff,
            offPressed: SpriteCatalog.repeatOffPressed,
            onNormal: SpriteCatalog.repeatOn,
            onPressed: SpriteCatalog.repeatOnPressed,
            isOn: false
        )
        repeatToggle.frame = NSRect(x: 210, y: 89, width: 28, height: 15)
        addSubview(repeatToggle)
    }
    
    private func updateLayoutForShadeMode() {
        if isShadeMode {
            // Hide main body controls
            volumeSlider.isHidden = true
            balanceSlider.isHidden = true
            seekSlider.isHidden = true
            eqToggle.isHidden = true
            plToggle.isHidden = true
            shuffleToggle.isHidden = true
            repeatToggle.isHidden = true
            marquee.isHidden = true
            clutterOptionsButton.isHidden = true
            doubleSizeButton.isHidden = true
            
            // Move visualizer to shade header (x: 79, y: 5)
            visualizer.frame = NSRect(x: 79, y: 5, width: CGFloat(AppConstants.Visualizer.width), height: 8)
            timeDisplay.frame = NSRect(x: 127, y: 4, width: 35, height: 6)
            
            // Reposition mini transport buttons (top: 2, left: 169..215)
            prevButton.frame = NSRect(x: 169, y: 2, width: 7, height: 10)
            playButton.frame = NSRect(x: 176, y: 2, width: 10, height: 10)
            pauseButton.frame = NSRect(x: 186, y: 2, width: 9, height: 10)
            stopButton.frame = NSRect(x: 195, y: 2, width: 9, height: 10)
            nextButton.frame = NSRect(x: 204, y: 2, width: 10, height: 10)
            ejectButton.frame = NSRect(x: 215, y: 2, width: 10, height: 10)
        } else {
            // Restore full layout
            volumeSlider.isHidden = false
            balanceSlider.isHidden = false
            seekSlider.isHidden = false
            eqToggle.isHidden = false
            plToggle.isHidden = false
            shuffleToggle.isHidden = false
            repeatToggle.isHidden = false
            marquee.isHidden = false
            clutterOptionsButton.isHidden = false
            doubleSizeButton.isHidden = false
            
            visualizer.frame = NSRect(x: 24, y: 43, width: CGFloat(AppConstants.Visualizer.width), height: CGFloat(AppConstants.Visualizer.height))
            timeDisplay.frame = NSRect(x: 39, y: 26, width: 59, height: 13)
            
            prevButton.frame = NSRect(x: 16, y: 88, width: 23, height: 18)
            playButton.frame = NSRect(x: 39, y: 88, width: 23, height: 18)
            pauseButton.frame = NSRect(x: 62, y: 88, width: 23, height: 18)
            stopButton.frame = NSRect(x: 85, y: 88, width: 23, height: 18)
            nextButton.frame = NSRect(x: 108, y: 88, width: 22, height: 18)
            ejectButton.frame = NSRect(x: 136, y: 89, width: 22, height: 16)
        }
    }
    
    // MARK: - Drawing Background
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        let isKey = window?.isKeyWindow ?? true
        
        if isShadeMode {
            let slice = isKey ? SpriteCatalog.mainShadeBgSelected : SpriteCatalog.mainShadeBg
            if let img = SkinManager.shared.image(for: slice) {
                context.drawSkinImage(img, in: bounds)
            }
        } else {
            // 1. Draw main background
            if let bgImg = SkinManager.shared.image(for: SpriteCatalog.mainWindowBackground) {
                context.drawSkinImage(bgImg, in: bounds)
            }
            
            // 2. Draw titlebar
            let titleSlice = isKey ? SpriteCatalog.titleBarSelected : SpriteCatalog.titleBarNormal
            if let titleImg = SkinManager.shared.image(for: titleSlice) {
                context.drawSkinImage(titleImg, in: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.shadeHeight))
            }
            
            // 3. Draw ClutterBar background (x: 10, y: 22)
            if let clutterImg = SkinManager.shared.image(for: SpriteCatalog.clutterBarBg) {
                context.drawSkinImage(clutterImg, in: NSRect(x: 10, y: 22, width: 8, height: 43))
            }
            
            // 4. Draw Bitrate & Samplerate (KBPS at x: 111, y: 43; KHZ at x: 156, y: 43)
            if let meta = AudioEngine.shared.currentMetadata {
                BitmapFont.draw(string: String(format: "%3d", meta.bitrate), in: context, at: CGPoint(x: 111, y: 43))
                BitmapFont.draw(string: String(format: "%2d", meta.sampleRate), in: context, at: CGPoint(x: 156, y: 43))
                
                // Mono/Stereo indicator (x: 212, y: 41)
                let stereoSlice = (meta.audioMode == .stereo) ? SpriteCatalog.stereoOn : SpriteCatalog.stereoOff
                let monoSlice = (meta.audioMode == .mono) ? SpriteCatalog.monoOn : SpriteCatalog.monoOff
                if let stereoImg = SkinManager.shared.image(for: stereoSlice) {
                    context.drawSkinImage(stereoImg, in: NSRect(x: 239, y: 41, width: 29, height: 12))
                }
                if let monoImg = SkinManager.shared.image(for: monoSlice) {
                    context.drawSkinImage(monoImg, in: NSRect(x: 212, y: 41, width: 27, height: 12))
                }
            }
            
            // 5. Draw Playback Status indicator (x: 26, y: 28)
            let statusSlice: SpriteSlice
            switch AudioEngine.shared.status {
            case .playing: statusSlice = SpriteCatalog.indicatorPlaying
            case .paused: statusSlice = SpriteCatalog.indicatorPaused
            case .stopped: statusSlice = SpriteCatalog.indicatorStopped
            }
            if let indImg = SkinManager.shared.image(for: statusSlice) {
                context.drawSkinImage(indImg, in: NSRect(x: 26, y: 28, width: 9, height: 9))
            }
        }
    }
    
    // MARK: - Window Dragging via Background / Titlebar
    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Double-click on titlebar toggles shade mode!
            let local = convert(event.locationInWindow, from: nil)
            if local.y <= AppConstants.Window.shadeHeight {
                onToggleShade?()
                return
            }
        }
        
        guard let win = self.window as? WinampWindow else { return }
        win.startWindowDrag(with: event)
        trackWindowDrag(with: event, in: win)
    }
    
    private func trackWindowDrag(with initialEvent: NSEvent, in win: WinampWindow) {
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            switch nextEvent.type {
            case .leftMouseDragged:
                win.continueWindowDrag(with: nextEvent)
            case .leftMouseUp:
                keepTracking = false
                win.endWindowDrag(with: nextEvent)
            default:
                break
            }
        }
    }
}
