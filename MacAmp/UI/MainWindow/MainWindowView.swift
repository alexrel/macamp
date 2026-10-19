import Cocoa
import Foundation

/// Main player window view (275x116 in normal mode, 275x14 in windowshade mode).
/// Hosts transport controls, time display, visualizer, marquee song title, volume/balance/seek sliders,
/// clutterbar buttons, and window toggle buttons.
public class MainWindowView: WinampControlView {
    // MARK: - Sub-components
    public let timeDisplay = TimeDisplayView()
    public let visualizer = VisualizerView()
    public let marquee = MarqueeView()
    
    // MARK: - Sliders
    public private(set) var volumeSlider: SkinSlider!
    public private(set) var balanceSlider: SkinSlider!
    public private(set) var seekSlider: SkinSlider!
    
    // MARK: - Toggles
    public private(set) var eqToggle: SkinToggle!
    public private(set) var plToggle: SkinToggle!
    public private(set) var shuffleToggle: SkinToggle!
    public private(set) var repeatToggle: SkinToggle!
    
    // MARK: - Transport Buttons (CBUTTONS.BMP)
    public private(set) var prevButton: SkinButton!
    public private(set) var playButton: SkinButton!
    public private(set) var pauseButton: SkinButton!
    public private(set) var stopButton: SkinButton!
    public private(set) var nextButton: SkinButton!
    public private(set) var ejectButton: SkinButton!
    
    // MARK: - Titlebar Buttons (TITLEBAR.BMP)
    public private(set) var optionsButton: SkinButton!
    public private(set) var minimizeButton: SkinButton!
    public private(set) var shadeButton: SkinButton!
    public private(set) var closeButton: SkinButton!
    
    // MARK: - ClutterBar Buttons (O, A, I, D, V)
    public private(set) var clutterOptionsButton: ClutterButton!
    public private(set) var alwaysOnTopButton: ClutterButton!
    public private(set) var clutterFileInfoButton: ClutterButton!
    public private(set) var doubleSizeButton: ClutterButton!
    public private(set) var clutterVisualizerButton: ClutterButton!
    
    /// Tracks windowshade mode (collapsed 14px titlebar strip vs full 116px player window)
    public var isShadeMode: Bool = false {
        didSet {
            updateLayoutForShadeMode()
            needsDisplay = true
            for sub in subviews {
                sub.needsDisplay = true
            }
        }
    }
    
    // Callbacks to PlayerCoordinator
    public var onToggleShade: (() -> Void)?
    public var onToggleAlwaysOnTop: (() -> Void)?
    public var onToggleDoubleSize: (() -> Void)?
    public var onOpenOptions: (() -> Void)?
    public var onTrackInfo: (() -> Void)?
    public var onToggleVisualizerMode: (() -> Void)?
    public var onEject: (() -> Void)?
    
    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.height))
        setupControls()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupControls() {
        typealias Layout = AppConstants.MainWindow.Layout
        
        // 1. TitleBar Buttons (Top-right and Top-left)
        optionsButton = SkinButton(normal: SpriteCatalog.optionsNormal, pressed: SpriteCatalog.optionsPressed) { [weak self] in
            self?.onOpenOptions?()
        }
        optionsButton.frame = Layout.optionsButton
        addSubview(optionsButton)
        
        minimizeButton = SkinButton(normal: SpriteCatalog.minimizeNormal, pressed: SpriteCatalog.minimizePressed) {
            PlayerCoordinator.shared.minimizeAll()
        }
        minimizeButton.frame = Layout.minimizeButton
        addSubview(minimizeButton)
        
        shadeButton = SkinButton(normal: SpriteCatalog.shadeNormal, pressed: SpriteCatalog.shadePressed) { [weak self] in
            self?.onToggleShade?()
        }
        shadeButton.frame = Layout.shadeButton
        addSubview(shadeButton)
        
        closeButton = SkinButton(normal: SpriteCatalog.closeNormal, pressed: SpriteCatalog.closePressed) {
            NSApp.terminate(nil)
        }
        closeButton.frame = Layout.closeButton
        addSubview(closeButton)
        
        // 2. ClutterBar Buttons (O = Options Menu, A = Always On Top, I = File Info, D = Double Size 2x Toggle, V = Visualizer Mode Cycle)
        clutterOptionsButton = ClutterButton(activeSlice: SpriteCatalog.clutterOActive) { [weak self] in
            self?.onOpenOptions?()
        }
        clutterOptionsButton.frame = Layout.clutterOptionsButton
        addSubview(clutterOptionsButton)
        
        alwaysOnTopButton = ClutterButton(activeSlice: SpriteCatalog.clutterAActive) { [weak self] in
            self?.onToggleAlwaysOnTop?()
        }
        alwaysOnTopButton.frame = Layout.clutterAlwaysOnTopButton
        alwaysOnTopButton.isSelected = PlayerCoordinator.shared.persistence.state.isAlwaysOnTop
        addSubview(alwaysOnTopButton)
        
        clutterFileInfoButton = ClutterButton(activeSlice: SpriteCatalog.clutterIActive) { [weak self] in
            self?.onTrackInfo?()
        }
        clutterFileInfoButton.frame = Layout.clutterFileInfoButton
        addSubview(clutterFileInfoButton)
        
        doubleSizeButton = ClutterButton(activeSlice: SpriteCatalog.clutterDActive) { [weak self] in
            self?.onToggleDoubleSize?()
        }
        doubleSizeButton.frame = Layout.clutterDoubleSizeButton
        doubleSizeButton.isSelected = (WindowLayoutManager.shared.currentScale == 2.0)
        addSubview(doubleSizeButton)
        
        clutterVisualizerButton = ClutterButton(activeSlice: SpriteCatalog.clutterVActive) { [weak self] in
            self?.onToggleVisualizerMode?()
        }
        clutterVisualizerButton.frame = Layout.clutterVisualizerButton
        addSubview(clutterVisualizerButton)
        
        // 3. Time, Visualizer, Marquee
        timeDisplay.frame = Layout.timeDisplay
        addSubview(timeDisplay)
        
        visualizer.frame = Layout.visualizer
        addSubview(visualizer)
        
        marquee.frame = Layout.marquee
        addSubview(marquee)
        
        // 4. Sliders (Volume, Balance, Seek)
        volumeSlider = SkinSlider(
            frame: Layout.volumeSlider,
            orientation: .horizontal,
            minValue: 0.0,
            maxValue: 1.0,
            initialValue: AppConstants.Audio.defaultVolume,
            trackWidth: Layout.volumeTrackWidth,
            bgFrameProvider: { SpriteCatalog.volumeBg(frame: $0) },
            thumbNormal: SpriteCatalog.volumeThumb,
            thumbPressed: SpriteCatalog.volumeThumbPressed
        ) { val in
            AudioEngine.shared.setVolume(val)
        }
        addSubview(volumeSlider)
        
        balanceSlider = SkinSlider(
            frame: Layout.balanceSlider,
            orientation: .horizontal,
            minValue: -1.0,
            maxValue: 1.0,
            initialValue: AppConstants.Audio.defaultBalance,
            centerOutwardFrames: true,
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
            frame: Layout.seekSlider,
            orientation: .horizontal,
            minValue: 0.0,
            maxValue: 1.0,
            initialValue: 0.0,
            background: SpriteCatalog.posBarBg,
            thumbNormal: SpriteCatalog.posBarThumb,
            thumbPressed: SpriteCatalog.posBarThumbPressed
        )
        seekSlider.isThumbHidden = (AudioEngine.shared.status == .stopped)
        addSubview(seekSlider)
        
        // 5. Window Toggles (EQ, PL)
        eqToggle = SkinToggle(
            offNormal: SpriteCatalog.eqToggleOff,
            offPressed: SpriteCatalog.eqToggleOffPressed,
            onNormal: SpriteCatalog.eqToggleOn,
            onPressed: SpriteCatalog.eqToggleOnPressed,
            isOn: true
        )
        eqToggle.frame = Layout.eqToggle
        addSubview(eqToggle)
        
        plToggle = SkinToggle(
            offNormal: SpriteCatalog.plToggleOff,
            offPressed: SpriteCatalog.plToggleOffPressed,
            onNormal: SpriteCatalog.plToggleOn,
            onPressed: SpriteCatalog.plToggleOnPressed,
            isOn: true
        )
        plToggle.frame = Layout.plToggle
        addSubview(plToggle)
        
        // 6. Transport Buttons
        prevButton = SkinButton(normal: SpriteCatalog.prevNormal, pressed: SpriteCatalog.prevPressed)
        prevButton.frame = Layout.prevButton
        addSubview(prevButton)
        
        playButton = SkinButton(normal: SpriteCatalog.playNormal, pressed: SpriteCatalog.playPressed) {
            AudioEngine.shared.play()
        }
        playButton.frame = Layout.playButton
        addSubview(playButton)
        
        pauseButton = SkinButton(normal: SpriteCatalog.pauseNormal, pressed: SpriteCatalog.pausePressed) {
            AudioEngine.shared.pause()
        }
        pauseButton.frame = Layout.pauseButton
        addSubview(pauseButton)
        
        stopButton = SkinButton(normal: SpriteCatalog.stopNormal, pressed: SpriteCatalog.stopPressed) {
            AudioEngine.shared.stop()
        }
        stopButton.frame = Layout.stopButton
        addSubview(stopButton)
        
        nextButton = SkinButton(normal: SpriteCatalog.nextNormal, pressed: SpriteCatalog.nextPressed)
        nextButton.frame = Layout.nextButton
        addSubview(nextButton)
        
        ejectButton = SkinButton(normal: SpriteCatalog.ejectNormal, pressed: SpriteCatalog.ejectPressed) { [weak self] in
            self?.onEject?()
        }
        ejectButton.frame = Layout.ejectButton
        addSubview(ejectButton)
        
        // 7. Shuffle & Repeat Toggles
        shuffleToggle = SkinToggle(
            offNormal: SpriteCatalog.shuffleOff,
            offPressed: SpriteCatalog.shuffleOffPressed,
            onNormal: SpriteCatalog.shuffleOn,
            onPressed: SpriteCatalog.shuffleOnPressed,
            isOn: false
        )
        shuffleToggle.frame = Layout.shuffleToggle
        addSubview(shuffleToggle)
        
        repeatToggle = SkinToggle(
            offNormal: SpriteCatalog.repeatOff,
            offPressed: SpriteCatalog.repeatOffPressed,
            onNormal: SpriteCatalog.repeatOn,
            onPressed: SpriteCatalog.repeatOnPressed,
            isOn: false
        )
        repeatToggle.frame = Layout.repeatToggle
        addSubview(repeatToggle)
    }
    
    // MARK: - Shade Mode Switching
    private func updateLayoutForShadeMode() {
        typealias Normal = AppConstants.MainWindow.Layout
        typealias Shade = AppConstants.MainWindow.ShadeLayout
        
        if isShadeMode {
            // 1. Hide main body controls
            volumeSlider.isHidden = true
            balanceSlider.isHidden = true
            eqToggle.isHidden = true
            plToggle.isHidden = true
            shuffleToggle.isHidden = true
            repeatToggle.isHidden = true
            marquee.isHidden = true
            clutterOptionsButton.isHidden = true
            alwaysOnTopButton.isHidden = true
            clutterFileInfoButton.isHidden = true
            doubleSizeButton.isHidden = true
            clutterVisualizerButton.isHidden = true
            
            // 2. Switch shade button to unshade sprite
            shadeButton.normalSlice = SpriteCatalog.mainShadeButtonSelected
            shadeButton.pressedSlice = SpriteCatalog.mainShadeButtonSelectedDepressed
            
            // 3. Move visualizer & time display to shade strip
            visualizer.frame = Shade.visualizer
            timeDisplay.frame = Shade.timeDisplay
            
            // 4. Configure mini seek bar
            seekSlider.isHidden = false
            seekSlider.frame = Shade.seekSlider
            seekSlider.isShadePosBar = true
            seekSlider.backgroundSlice = SpriteCatalog.mainShadePosBg
            seekSlider.thumbNormal = SpriteCatalog.mainShadePosThumb
            seekSlider.thumbPressed = SpriteCatalog.mainShadePosThumb
            
            // 5. Reposition mini transport buttons and mark them as shade buttons (transparent background)
            let shadeTransport: [(SkinButton, NSRect)] = [
                (prevButton, Shade.prevButton),
                (playButton, Shade.playButton),
                (pauseButton, Shade.pauseButton),
                (stopButton, Shade.stopButton),
                (nextButton, Shade.nextButton),
                (ejectButton, Shade.ejectButton)
            ]
            for (btn, frame) in shadeTransport {
                btn.frame = frame
                btn.isShadeButton = true
            }
        } else {
            // 1. Restore full layout controls visibility
            volumeSlider.isHidden = false
            balanceSlider.isHidden = false
            eqToggle.isHidden = false
            plToggle.isHidden = false
            shuffleToggle.isHidden = false
            repeatToggle.isHidden = false
            marquee.isHidden = false
            clutterOptionsButton.isHidden = false
            alwaysOnTopButton.isHidden = false
            clutterFileInfoButton.isHidden = false
            doubleSizeButton.isHidden = false
            clutterVisualizerButton.isHidden = false
            
            // 2. Switch shade button back to normal shade sprite
            shadeButton.normalSlice = SpriteCatalog.shadeNormal
            shadeButton.pressedSlice = SpriteCatalog.shadePressed
            
            // 3. Restore full seek bar
            seekSlider.isHidden = false
            seekSlider.frame = Normal.seekSlider
            seekSlider.isShadePosBar = false
            seekSlider.backgroundSlice = SpriteCatalog.posBarBg
            seekSlider.thumbNormal = SpriteCatalog.posBarThumb
            seekSlider.thumbPressed = SpriteCatalog.posBarThumbPressed
            
            // 4. Restore visualizer & time display frames
            visualizer.frame = Normal.visualizer
            timeDisplay.frame = Normal.timeDisplay
            
            // 5. Restore full transport buttons
            let normalTransport: [(SkinButton, NSRect)] = [
                (prevButton, Normal.prevButton),
                (playButton, Normal.playButton),
                (pauseButton, Normal.pauseButton),
                (stopButton, Normal.stopButton),
                (nextButton, Normal.nextButton),
                (ejectButton, Normal.ejectButton)
            ]
            for (btn, frame) in normalTransport {
                btn.frame = frame
                btn.isShadeButton = false
            }
        }
    }
    
    // MARK: - Drawing Background & Static Indicators
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        let isKey = NSApp.isActive && (window?.isKeyWindow ?? false)
        
        if isShadeMode {
            // Draw Windowshade Background (TITLEBAR.BMP)
            let slice = isKey ? SpriteCatalog.mainShadeBgSelected : SpriteCatalog.mainShadeBg
            if let img = SkinManager.shared.image(for: slice) {
                context.drawSkinImage(img, in: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.shadeHeight))
            }
        } else {
            typealias Layout = AppConstants.MainWindow.Layout
            
            // 1. Draw main background (MAIN.BMP 275x116)
            if let bgImg = SkinManager.shared.image(for: SpriteCatalog.mainWindowBackground) {
                context.drawSkinImage(bgImg, in: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.height))
            }
            
            // 2. Draw titlebar (TITLEBAR.BMP 275x14)
            let titleSlice = isKey ? SpriteCatalog.titleBarSelected : SpriteCatalog.titleBarNormal
            if let titleImg = SkinManager.shared.image(for: titleSlice) {
                context.drawSkinImage(titleImg, in: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.shadeHeight))
            }
            
            // 3. Draw ClutterBar background
            if let clutterImg = SkinManager.shared.image(for: SpriteCatalog.clutterBarBg) {
                context.drawSkinImage(clutterImg, in: Layout.clutterBarBg)
            }
            
            // 4. Draw Bitrate & Samplerate text and Mono/Stereo indicator
            if let meta = AudioEngine.shared.currentMetadata {
                BitmapFont.draw(string: String(format: "%3d", meta.bitrate), in: context, at: Layout.bitrate)
                BitmapFont.draw(string: String(format: "%2d", meta.sampleRate), in: context, at: Layout.sampleRate)
                
                let stereoSlice = (meta.audioMode == .stereo) ? SpriteCatalog.stereoOn : SpriteCatalog.stereoOff
                let monoSlice = (meta.audioMode == .mono) ? SpriteCatalog.monoOn : SpriteCatalog.monoOff
                if let stereoImg = SkinManager.shared.image(for: stereoSlice) {
                    context.drawSkinImage(stereoImg, in: Layout.stereoIndicator)
                }
                if let monoImg = SkinManager.shared.image(for: monoSlice) {
                    context.drawSkinImage(monoImg, in: Layout.monoIndicator)
                }
            }
            
            // 5. Draw Playback Status indicator (play/pause/stop symbol and working indicator)
            let currentStatus = AudioEngine.shared.status
            if currentStatus == .playing {
                if let workImg = SkinManager.shared.image(for: SpriteCatalog.indicatorWorking) {
                    context.drawSkinImage(workImg, in: Layout.workingIndicator)
                }
            } else {
                if let blankImg = SkinManager.shared.image(for: SpriteCatalog.indicatorWorkingBlank) {
                    context.drawSkinImage(blankImg, in: Layout.workingIndicator)
                }
            }
            
            let statusSlice: SpriteSlice
            switch currentStatus {
            case .playing: statusSlice = SpriteCatalog.indicatorPlaying
            case .paused: statusSlice = SpriteCatalog.indicatorPaused
            case .stopped: statusSlice = SpriteCatalog.indicatorStopped
            }
            if let indImg = SkinManager.shared.image(for: statusSlice) {
                context.drawSkinImage(indImg, in: Layout.playbackIndicator)
            }
        }
    }
    
    // MARK: - Window Dragging via Background / Titlebar
    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Double-click on titlebar toggles windowshade mode!
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
    
    // MARK: - Context Menu
    public override func menu(for event: NSEvent) -> NSMenu? {
        return PlayerCoordinator.shared.buildWinampMenu()
    }
}
