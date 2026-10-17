import Cocoa
import Foundation
import UniformTypeIdentifiers

/// Equalizer window view (275x116 in normal mode, 275x14 in windowshade mode).
/// Hosts 10 parametric frequency band sliders, preamp slider, EQ on/auto toggles,
/// presets popup menu, dynamic cubic spline frequency response curve, and shade volume/balance sliders.
public class EqualizerWindowView: WinampControlView {
    // MARK: - Titlebar Buttons
    public private(set) var closeButton: SkinButton!
    public private(set) var shadeButton: SkinButton!
    
    // MARK: - Top Controls
    public private(set) var onToggle: SkinToggle!
    public private(set) var autoToggle: SkinToggle!
    public private(set) var presetsButton: SkinButton!
    
    /// 19 gradient line colors for EQ graph (y=0: +12dB (red) down to y=18: -12dB (dark green))
    public static let eqLineColors: [NSColor] = [
        NSColor(srgbRed: 211/255.0, green: 34/255.0, blue: 27/255.0, alpha: 1.0),   // y=0:  +12dB (red)
        NSColor(srgbRed: 239/255.0, green: 82/255.0, blue: 33/255.0, alpha: 1.0),   // y=1
        NSColor(srgbRed: 239/255.0, green: 123/255.0, blue: 33/255.0, alpha: 1.0),  // y=2
        NSColor(srgbRed: 224/255.0, green: 146/255.0, blue: 40/255.0, alpha: 1.0),  // y=3
        NSColor(srgbRed: 224/255.0, green: 146/255.0, blue: 40/255.0, alpha: 1.0),  // y=4
        NSColor(srgbRed: 224/255.0, green: 146/255.0, blue: 40/255.0, alpha: 1.0),  // y=5
        NSColor(srgbRed: 224/255.0, green: 178/255.0, blue: 40/255.0, alpha: 1.0),  // y=6
        NSColor(srgbRed: 239/255.0, green: 220/255.0, blue: 49/255.0, alpha: 1.0),  // y=7:  0dB (yellow/gold)
        NSColor(srgbRed: 239/255.0, green: 220/255.0, blue: 49/255.0, alpha: 1.0),  // y=8:  0dB
        NSColor(srgbRed: 239/255.0, green: 220/255.0, blue: 49/255.0, alpha: 1.0),  // y=9:  0dB
        NSColor(srgbRed: 210/255.0, green: 235/255.0, blue: 53/255.0, alpha: 1.0),  // y=10
        NSColor(srgbRed: 210/255.0, green: 235/255.0, blue: 53/255.0, alpha: 1.0),  // y=11
        NSColor(srgbRed: 164/255.0, green: 226/255.0, blue: 56/255.0, alpha: 1.0),  // y=12: -3dB (yellow-green)
        NSColor(srgbRed: 164/255.0, green: 226/255.0, blue: 56/255.0, alpha: 1.0),  // y=13
        NSColor(srgbRed: 137/255.0, green: 226/255.0, blue: 48/255.0, alpha: 1.0),  // y=14
        NSColor(srgbRed: 113/255.0, green: 205/255.0, blue: 52/255.0, alpha: 1.0),  // y=15
        NSColor(srgbRed: 90/255.0, green: 176/255.0, blue: 44/255.0, alpha: 1.0),   // y=16
        NSColor(srgbRed: 42/255.0, green: 154/255.0, blue: 22/255.0, alpha: 1.0),   // y=17: -12dB (dark green)
        NSColor(srgbRed: 42/255.0, green: 154/255.0, blue: 22/255.0, alpha: 1.0)    // y=18: -12dB
    ]
    
    // MARK: - Sliders
    public private(set) var preampSlider: SkinSlider!
    public private(set) var bandSliders: [SkinSlider] = []
    public private(set) var eqShadeVolumeSlider: SkinSlider!
    public private(set) var eqShadeBalanceSlider: SkinSlider!
    
    public var isShadeMode: Bool = false {
        didSet {
            updateLayoutForShadeMode()
            needsDisplay = true
            for sub in subviews {
                sub.needsDisplay = true
            }
        }
    }
    
    public var onToggleShade: (() -> Void)?
    public var onClose: (() -> Void)?
    public var onBandAdjusted: ((_ name: String, _ gainDb: Float) -> Void)?
    
    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.height))
        setupControls()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupControls() {
        typealias Layout = AppConstants.Equalizer.Layout
        
        // 1. TitleBar Buttons (Close at x: 264, Shade at x: 254)
        closeButton = SkinButton(normal: SpriteCatalog.eqCloseNormal, pressed: SpriteCatalog.eqClosePressed) { [weak self] in
            self?.onClose?()
        }
        closeButton.frame = Layout.closeButton
        addSubview(closeButton)
        
        shadeButton = SkinButton(normal: SpriteCatalog.shadeNormal, pressed: SpriteCatalog.shadePressed) { [weak self] in
            self?.onToggleShade?()
        }
        shadeButton.frame = Layout.shadeButton
        addSubview(shadeButton)
        
        // 2. ON Button & AUTO Button (EQ bypass and auto-preset toggles)
        onToggle = SkinToggle(
            offNormal: SpriteCatalog.eqOnButtonOff,
            offPressed: SpriteCatalog.eqOnButtonOffPressed,
            onNormal: SpriteCatalog.eqOnButtonOn,
            onPressed: SpriteCatalog.eqOnButtonOnPressed,
            isOn: true
        ) { [weak self] isOn in
            AudioEngine.shared.setEqEnabled(isOn)
            self?.needsDisplay = true
        }
        onToggle.frame = Layout.onToggle
        addSubview(onToggle)
        
        autoToggle = SkinToggle(
            offNormal: SpriteCatalog.eqAutoButtonOff,
            offPressed: SpriteCatalog.eqAutoButtonOffPressed,
            onNormal: SpriteCatalog.eqAutoButtonOn,
            onPressed: SpriteCatalog.eqAutoButtonOnPressed,
            isOn: false
        )
        autoToggle.frame = Layout.autoToggle
        addSubview(autoToggle)
        
        // 3. Presets Button (opens Presets Menu)
        presetsButton = SkinButton(normal: SpriteCatalog.eqPresetsNormal, pressed: SpriteCatalog.eqPresetsPressed) { [weak self] in
            self?.showPresetsMenu()
        }
        presetsButton.frame = Layout.presetsButton
        addSubview(presetsButton)
        
        // 4. Preamp Slider (vertical at x: 21, y: 38, range -12dB ... +12dB)
        preampSlider = SkinSlider(
            frame: Layout.preampSlider,
            orientation: .vertical,
            minValue: Double(AppConstants.Equalizer.minGainDb),
            maxValue: Double(AppConstants.Equalizer.maxGainDb),
            initialValue: Double(AppConstants.Equalizer.zeroGainDb),
            snapCenter: true,
            snapThreshold: 0.08,
            bgFrameProvider: { SpriteCatalog.eqSliderBg(frame: $0) },
            thumbNormal: SpriteCatalog.eqSliderThumbNormal,
            thumbPressed: SpriteCatalog.eqSliderThumbPressed
        ) { [weak self] val in
            AudioEngine.shared.setPreamp(gainDb: Float(val))
            self?.onBandAdjusted?("PREAMP", Float(val))
            self?.needsDisplay = true
        }
        addSubview(preampSlider)
        
        // 5. 10 Frequency Band Sliders (60Hz, 170Hz, ..., 16kHz)
        let bandNames = ["60Hz", "170Hz", "310Hz", "600Hz", "1KHz", "3KHz", "6KHz", "12KHz", "14KHz", "16KHz"]
        for (i, xPos) in Layout.bandXPositions.enumerated() {
            let bandName = (i < bandNames.count) ? bandNames[i] : "\(AppConstants.Equalizer.bandFrequencies[i])Hz"
            let slider = SkinSlider(
                frame: NSRect(x: xPos, y: Layout.bandY, width: Layout.bandWidth, height: Layout.bandHeight),
                orientation: .vertical,
                minValue: Double(AppConstants.Equalizer.minGainDb),
                maxValue: Double(AppConstants.Equalizer.maxGainDb),
                initialValue: Double(AppConstants.Equalizer.zeroGainDb),
                snapCenter: true,
                snapThreshold: 0.08,
                bgFrameProvider: { SpriteCatalog.eqSliderBg(frame: $0) },
                thumbNormal: SpriteCatalog.eqSliderThumbNormal,
                thumbPressed: SpriteCatalog.eqSliderThumbPressed
            ) { [weak self] val in
                AudioEngine.shared.setEQBand(index: i, gainDb: Float(val))
                self?.onBandAdjusted?(bandName, Float(val))
                self?.needsDisplay = true
            }
            bandSliders.append(slider)
            addSubview(slider)
        }
        
        // 6. EQ Shade Sliders (Mini volume at x: 61 and balance at x: 164)
        eqShadeVolumeSlider = SkinSlider(
            frame: Layout.shadeVolumeSlider,
            orientation: .horizontal,
            minValue: 0.0,
            maxValue: 1.0,
            initialValue: AppConstants.Audio.defaultVolume,
            thumbNormal: SpriteCatalog.eqShadeVolThumb,
            thumbPressed: SpriteCatalog.eqShadeVolThumb
        ) { val in
            AudioEngine.shared.setVolume(val)
            PlayerCoordinator.shared.mainView.volumeSlider.value = val
            PlayerCoordinator.shared.persistence.state.volume = val
            let percent = Int(round(val * 100.0))
            PlayerCoordinator.shared.mainView.marquee.showTemporaryMessage("Volume: \(percent)%")
        }
        eqShadeVolumeSlider.isHidden = true
        addSubview(eqShadeVolumeSlider)
        
        eqShadeBalanceSlider = SkinSlider(
            frame: Layout.shadeBalanceSlider,
            orientation: .horizontal,
            minValue: -1.0,
            maxValue: 1.0,
            initialValue: AppConstants.Audio.defaultBalance,
            snapCenter: true,
            snapThreshold: 0.1,
            thumbNormal: SpriteCatalog.eqShadeBalThumb,
            thumbPressed: SpriteCatalog.eqShadeBalThumb
        ) { val in
            AudioEngine.shared.setBalance(val)
            PlayerCoordinator.shared.mainView.balanceSlider.value = val
            PlayerCoordinator.shared.persistence.state.balance = val
            let percent = Int(round(abs(val) * 100.0))
            let msg: String
            if percent == 0 {
                msg = "Balance: Center"
            } else if val < 0 {
                msg = "Balance: \(percent)% left"
            } else {
                msg = "Balance: \(percent)% right"
            }
            PlayerCoordinator.shared.mainView.marquee.showTemporaryMessage(msg)
        }
        eqShadeBalanceSlider.isHidden = true
        addSubview(eqShadeBalanceSlider)
    }
    
    // MARK: - Shade Mode Switching
    private func updateLayoutForShadeMode() {
        let isFull = !isShadeMode
        onToggle.isHidden = !isFull
        autoToggle.isHidden = !isFull
        presetsButton.isHidden = !isFull
        preampSlider.isHidden = !isFull
        for s in bandSliders {
            s.isHidden = !isFull
        }
        
        eqShadeVolumeSlider.isHidden = isFull
        eqShadeBalanceSlider.isHidden = isFull
        if !isFull {
            eqShadeVolumeSlider.value = AudioEngine.shared.volume
            eqShadeBalanceSlider.value = PlayerCoordinator.shared.mainView.balanceSlider.value
        }
    }
    
    // MARK: - Presets Menu
    private func showPresetsMenu() {
        let menu = NSMenu(title: "Presets")
        menu.autoenablesItems = false
        
        // 1. Load submenu
        let loadMenu = NSMenu(title: "Load")
        loadMenu.autoenablesItems = false
        
        // Built-in presets
        for preset in EqualizerPresetsManager.shared.builtInPresets {
            let item = NSMenuItem(title: preset.name, action: #selector(handlePresetSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            loadMenu.addItem(item)
        }
        
        // User presets (if any)
        let userPresets = EqualizerPresetsManager.shared.userPresets
        if !userPresets.isEmpty {
            loadMenu.addItem(NSMenuItem.separator())
            let userHeader = NSMenuItem(title: "User Presets", action: nil, keyEquivalent: "")
            userHeader.isEnabled = false
            loadMenu.addItem(userHeader)
            for preset in userPresets {
                let item = NSMenuItem(title: preset.name, action: #selector(handlePresetSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset
                loadMenu.addItem(item)
            }
        }
        
        // Separator and "From Eqf..."
        loadMenu.addItem(NSMenuItem.separator())
        let fromEqfItem = NSMenuItem(title: "From Eqf...", action: #selector(handleLoadEqf), keyEquivalent: "")
        fromEqfItem.target = self
        loadMenu.addItem(fromEqfItem)
        
        let loadItem = NSMenuItem(title: "Load", action: nil, keyEquivalent: "")
        loadItem.submenu = loadMenu
        menu.addItem(loadItem)
        
        // 2. Save submenu
        let saveMenu = NSMenu(title: "Save")
        saveMenu.autoenablesItems = false
        
        let savePresetItem = NSMenuItem(title: "Save Preset...", action: #selector(handleSavePreset), keyEquivalent: "")
        savePresetItem.target = self
        saveMenu.addItem(savePresetItem)
        
        let saveEqfItem = NSMenuItem(title: "To Eqf...", action: #selector(handleSaveEqf), keyEquivalent: "")
        saveEqfItem.target = self
        saveMenu.addItem(saveEqfItem)
        
        let saveItem = NSMenuItem(title: "Save", action: nil, keyEquivalent: "")
        saveItem.submenu = saveMenu
        menu.addItem(saveItem)
        
        // Separator & Reset (0 dB)
        menu.addItem(NSMenuItem.separator())
        let resetItem = NSMenuItem(title: "Reset (0 dB)", action: #selector(handleResetToFlat), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)
        
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: presetsButton.bounds.height), in: presetsButton)
    }
    
    @objc private func handlePresetSelected(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? EQPreset else { return }
        applyPreset(preset)
    }
    
    @objc private func handleResetToFlat() {
        applyPreset(EqualizerPresetsManager.flatPreset)
    }
    
    @objc private func handleSavePreset() {
        let alert = NSAlert()
        alert.messageText = "Save EQ Preset"
        alert.informativeText = "Enter a name for the new equalizer preset:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = "Custom Preset"
        alert.accessoryView = input
        
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let preset = currentEQPreset(named: name)
            EqualizerPresetsManager.shared.saveUserPreset(preset)
        }
    }
    
    @objc private func handleSaveEqf() {
        let panel = NSSavePanel()
        panel.title = "Save Equalizer Preset (.eqf)"
        if let eqfType = UTType(filenameExtension: "eqf") {
            panel.allowedContentTypes = [eqfType]
        }
        panel.nameFieldStringValue = "winamp.eqf"
        if panel.runModal() == .OK, let url = panel.url {
            let name = url.deletingPathExtension().lastPathComponent
            let preset = currentEQPreset(named: name)
            try? EqualizerPresetsManager.shared.saveEQF(presets: [preset], to: url)
        }
    }
    
    @objc private func handleLoadEqf() {
        let panel = NSOpenPanel()
        panel.title = "Load Equalizer Preset (.eqf)"
        if let eqfType = UTType(filenameExtension: "eqf") {
            panel.allowedContentTypes = [eqfType]
        }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let presets = EqualizerPresetsManager.shared.loadEQF(from: url)
            if let first = presets.first {
                applyPreset(first)
            }
        }
    }
    
    public func currentEQPreset(named name: String = "Current") -> EQPreset {
        let p = Float(preampSlider.value)
        let bands = bandSliders.map { Float($0.value) }
        return EQPreset(name: name, preampDb: p, bandsDb: bands)
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
            // Draw EQ shade strip background (EQ_EX.BMP 275x14)
            let slice = isKey ? SpriteCatalog.eqShadeBgSelected : SpriteCatalog.eqShadeBg
            if let img = SkinManager.shared.image(for: slice) {
                context.drawSkinImage(img, in: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.shadeHeight))
            }
        } else {
            // 1. Draw EQ main background (EQMAIN.BMP 275x116)
            if let bgImg = SkinManager.shared.image(for: SpriteCatalog.eqWindowBg) {
                context.drawSkinImage(bgImg, in: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.height))
            }
            
            // 2. Draw TitleBar (EQMAIN.BMP 275x14)
            let titleSlice = isKey ? SpriteCatalog.eqTitleBarSelected : SpriteCatalog.eqTitleBar
            if let titleImg = SkinManager.shared.image(for: titleSlice) {
                context.drawSkinImage(titleImg, in: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.shadeHeight))
            }
            
            // 3. Draw EQ Graph Box at x: 86, y: 17, w: 113, h: 19
            let graphRect = AppConstants.Equalizer.Layout.graphRect
            if let graphBg = SkinManager.shared.image(for: SpriteCatalog.eqGraphBg) {
                context.drawSkinImage(graphBg, in: graphRect)
            }
            
            // Draw EQ spline curve across the 10 bands
            drawEQCurve(in: context, graphRect: graphRect)
        }
    }
    
    /// Computes and renders a smooth cubic spline curve connecting the 10 EQ band values inside the graph box.
    private func drawEQCurve(in context: CGContext, graphRect: NSRect) {
        guard onToggle.isOn else { return }
        
        context.saveGState()
        context.clip(to: graphRect)
        
        // 1. Draw Preamp Line across the graph (113x1)
        // preamp value: -12dB ... +12dB. 0dB is centered at y = 9.
        let preampNorm = preampSlider.normalizedValue // 0.0 (-12dB) ... 1.0 (+12dB)
        let preampY = Int(round((1.0 - preampNorm) * 18.0)) // 0 (top, +12dB) ... 18 (bottom, -12dB)
        if let preampImg = SkinManager.shared.image(for: SpriteCatalog.eqPreampLine) {
            context.drawSkinImage(preampImg, in: NSRect(x: graphRect.minX, y: graphRect.minY + CGFloat(preampY), width: graphRect.width, height: 1))
        }
        
        // 2. Draw 10-band cubic spline curve
        // Knots: x = i * 12 (0, 12, 24, ..., 108), y = (1.0 - norm) * 18.0
        let xs: [Double] = (0..<10).map { Double($0 * 12) }
        let ys: [Double] = bandSliders.map { (1.0 - $0.normalizedValue) * 18.0 }
        
        let allYs = CubicSpline.compute(xs: xs, ys: ys)
        
        let paddingLeft = graphRect.minX + 2.0
        let maxX = min(Int(xs.last ?? 108), allYs.count - 1)
        
        var lastY = ys.first ?? 9.0
        for x in 0...maxX {
            let curY = max(0.0, min(18.0, allYs[x]))
            let yTop = min(curY, lastY)
            let height = 1.0 + abs(lastY - curY)
            
            // Map height to line color
            let colorIdx = max(0, min(18, Int(round(curY))))
            let strokeColor = (colorIdx < EqualizerWindowView.eqLineColors.count) ? EqualizerWindowView.eqLineColors[colorIdx] : NSColor(srgbRed: 0.94, green: 0.86, blue: 0.19, alpha: 1.0)
            
            context.setFillColor(strokeColor.cgColor)
            context.fill(CGRect(x: paddingLeft + CGFloat(x), y: graphRect.minY + CGFloat(yTop), width: 1.0, height: CGFloat(height)))
            
            lastY = curY
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
}
