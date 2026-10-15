import Cocoa
import Foundation

public class EqualizerWindowView: WinampControlView {
    // Titlebar Buttons
    public private(set) var closeButton: SkinButton!
    public private(set) var shadeButton: SkinButton!
    
    // Top Controls
    public private(set) var onToggle: SkinToggle!
    public private(set) var autoToggle: SkinToggle!
    public private(set) var presetsButton: SkinButton!
    
    // Sliders
    public private(set) var preampSlider: SkinSlider!
    public private(set) var bandSliders: [SkinSlider] = []
    
    public var isShadeMode: Bool = false {
        didSet {
            updateLayoutForShadeMode()
            needsDisplay = true
        }
    }
    
    public var onToggleShade: (() -> Void)?
    public var onClose: (() -> Void)?
    
    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.height))
        setupControls()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupControls() {
        // 1. TitleBar Buttons (Close at x: 264, Shade at x: 254)
        closeButton = SkinButton(normal: SpriteCatalog.eqCloseNormal, pressed: SpriteCatalog.eqClosePressed) { [weak self] in
            self?.onClose?()
        }
        closeButton.frame = NSRect(x: 264, y: 3, width: 9, height: 9)
        addSubview(closeButton)
        
        shadeButton = SkinButton(normal: SpriteCatalog.shadeNormal, pressed: SpriteCatalog.shadePressed) { [weak self] in
            self?.onToggleShade?()
        }
        shadeButton.frame = NSRect(x: 254, y: 3, width: 9, height: 9)
        addSubview(shadeButton)
        
        // 2. ON Button & AUTO Button
        onToggle = SkinToggle(
            offNormal: SpriteCatalog.eqOnButtonOff,
            offPressed: SpriteCatalog.eqOnButtonOffPressed,
            onNormal: SpriteCatalog.eqOnButtonOn,
            onPressed: SpriteCatalog.eqOnButtonOnPressed,
            isOn: true
        ) { isOn in
            AudioEngine.shared.setEqEnabled(isOn)
        }
        onToggle.frame = NSRect(x: 14, y: 18, width: 26, height: 12)
        addSubview(onToggle)
        
        autoToggle = SkinToggle(
            offNormal: SpriteCatalog.eqAutoButtonOff,
            offPressed: SpriteCatalog.eqAutoButtonOffPressed,
            onNormal: SpriteCatalog.eqAutoButtonOn,
            onPressed: SpriteCatalog.eqAutoButtonOnPressed,
            isOn: false
        )
        autoToggle.frame = NSRect(x: 40, y: 18, width: 32, height: 12)
        addSubview(autoToggle)
        
        // 3. Presets Button (opens Presets Menu)
        presetsButton = SkinButton(normal: SpriteCatalog.eqPresetsNormal, pressed: SpriteCatalog.eqPresetsPressed) { [weak self] in
            self?.showPresetsMenu()
        }
        presetsButton.frame = NSRect(x: 217, y: 18, width: 44, height: 12)
        addSubview(presetsButton)
        
        // 4. Preamp Slider (vertical at x: 21, y: 38)
        preampSlider = SkinSlider(
            frame: NSRect(x: 21, y: 38, width: 14, height: 63),
            orientation: .vertical,
            minValue: Double(AppConstants.Equalizer.minGainDb),
            maxValue: Double(AppConstants.Equalizer.maxGainDb),
            initialValue: 0.0,
            snapCenter: true,
            snapThreshold: 0.08,
            thumbNormal: SpriteCatalog.eqSliderThumbNormal,
            thumbPressed: SpriteCatalog.eqSliderThumbPressed
        ) { [weak self] val in
            AudioEngine.shared.setPreamp(gainDb: Float(val))
            self?.needsDisplay = true
        }
        addSubview(preampSlider)
        
        // 5. 10 Band Sliders (x: 78, 96, 114, 132, 150, 168, 186, 204, 222, 240)
        let bandXPositions: [CGFloat] = [78, 96, 114, 132, 150, 168, 186, 204, 222, 240]
        for (i, xPos) in bandXPositions.enumerated() {
            let slider = SkinSlider(
                frame: NSRect(x: xPos, y: 38, width: 14, height: 63),
                orientation: .vertical,
                minValue: Double(AppConstants.Equalizer.minGainDb),
                maxValue: Double(AppConstants.Equalizer.maxGainDb),
                initialValue: 0.0,
                snapCenter: true,
                snapThreshold: 0.08,
                thumbNormal: SpriteCatalog.eqSliderThumbNormal,
                thumbPressed: SpriteCatalog.eqSliderThumbPressed
            ) { [weak self] val in
                AudioEngine.shared.setEQBand(index: i, gainDb: Float(val))
                self?.needsDisplay = true
            }
            bandSliders.append(slider)
            addSubview(slider)
        }
    }
    
    private func updateLayoutForShadeMode() {
        let isFull = !isShadeMode
        onToggle.isHidden = !isFull
        autoToggle.isHidden = !isFull
        presetsButton.isHidden = !isFull
        preampSlider.isHidden = !isFull
        for s in bandSliders {
            s.isHidden = !isFull
        }
    }
    
    // MARK: - Presets Menu
    private func showPresetsMenu() {
        let menu = NSMenu(title: "Presets")
        
        // Built-in presets submenu
        let builtInMenu = NSMenu(title: "Preset")
        for preset in EqualizerPresetsManager.shared.builtInPresets {
            let item = NSMenuItem(title: preset.name, action: #selector(handlePresetSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            builtInMenu.addItem(item)
        }
        let builtInItem = NSMenuItem(title: "Load", action: nil, keyEquivalent: "")
        builtInItem.submenu = builtInMenu
        menu.addItem(builtInItem)
        
        // Reset to Flat (0 dB)
        let resetItem = NSMenuItem(title: "Reset (0 dB)", action: #selector(handleResetToFlat), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)
        
        let point = convert(NSPoint(x: presetsButton.frame.minX, y: presetsButton.frame.maxY), to: nil)
        if let window {
            let screenPoint = window.convertToScreen(NSRect(origin: point, size: .zero)).origin
            menu.popUp(positioning: nil, at: screenPoint, in: nil)
        }
    }
    
    @objc private func handlePresetSelected(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? EQPreset else { return }
        applyPreset(preset)
    }
    
    @objc private func handleResetToFlat() {
        applyPreset(EqualizerPresetsManager.flatPreset)
    }
    
    public func applyPreset(_ preset: EQPreset) {
        preampSlider.value = Double(preset.preampDb)
        AudioEngine.shared.setPreamp(gainDb: preset.preampDb)
        
        for (i, slider) in bandSliders.enumerated() {
            if i < preset.bandsDb.count {
                let gain = preset.bandsDb[i]
                slider.value = Double(gain)
                AudioEngine.shared.setEQBand(index: i, gainDb: gain)
            }
        }
        needsDisplay = true
    }
    
    // MARK: - Drawing Background & Spline Curve
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        let isKey = window?.isKeyWindow ?? true
        
        if isShadeMode {
            let slice = isKey ? SpriteCatalog.eqShadeBgSelected : SpriteCatalog.eqShadeBg
            if let img = SkinManager.shared.image(for: slice) {
                context.drawSkinImage(img, in: bounds)
            }
        } else {
            // 1. Draw EQ background
            if let bgImg = SkinManager.shared.image(for: SpriteCatalog.eqWindowBg) {
                context.drawSkinImage(bgImg, in: bounds)
            }
            
            // 2. Draw TitleBar
            let titleSlice = isKey ? SpriteCatalog.eqTitleBarSelected : SpriteCatalog.eqTitleBar
            if let titleImg = SkinManager.shared.image(for: titleSlice) {
                context.drawSkinImage(titleImg, in: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.shadeHeight))
            }
            
            // 3. Draw EQ Graph Box at x: 86, y: 17, w: 113, h: 19
            let graphRect = NSRect(x: 86, y: 17, width: 113, height: 19)
            if let graphBg = SkinManager.shared.image(for: SpriteCatalog.eqGraphBg) {
                context.drawSkinImage(graphBg, in: graphRect)
            }
            
            // Draw EQ spline curve across the 10 bands
            drawEQCurve(in: context, graphRect: graphRect)
        }
    }
    
    private func drawEQCurve(in context: CGContext, graphRect: NSRect) {
        guard onToggle.isOn else { return }
        
        context.saveGState()
        context.clip(to: graphRect)
        
        // Green curve color
        context.setStrokeColor(NSColor(srgbRed: 0.0, green: 1.0, blue: 0.0, alpha: 0.9).cgColor)
        context.setLineWidth(1.0)
        
        let midY = graphRect.midY
        let maxDev = (graphRect.height / 2.0) - 2.0
        
        var points: [CGPoint] = []
        for (i, slider) in bandSliders.enumerated() {
            let x = graphRect.minX + 5.0 + (CGFloat(i) * (graphRect.width - 10.0) / 9.0)
            let norm = CGFloat(slider.normalizedValue) // 0..1 (0.5 is 0dB)
            let y = midY - ((norm - 0.5) * 2.0 * maxDev)
            points.append(CGPoint(x: x, y: y))
        }
        
        if points.count > 1 {
            let path = CGMutablePath()
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            context.addPath(path)
            context.strokePath()
        }
        
        context.restoreGState()
    }
    
    // MARK: - Window Dragging
    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
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
