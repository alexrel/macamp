import Cocoa
import UniformTypeIdentifiers

extension PlayerCoordinator {
    // MARK: - Always On Top & Window Management
    public func setAlwaysOnTop(_ enabled: Bool) {
        persistence.state.isAlwaysOnTop = enabled
        let level: NSWindow.Level = enabled ? .floating : .normal
        mainWindow?.level = level
        eqWindow?.level = level
        plWindow?.level = level
        for window in [libraryWindow, video?.window, browser?.window] { window?.level = level }
        bringAllWindowsToFront()
        mainView?.alwaysOnTopButton?.isSelected = enabled
    }
    
    @objc public func handleToggleVisualizerStudio() {
        toggleVisualizerStudio()
    }
    
    /// Opens or closes the Visualizer Studio (⌃⇧K); in full screen on another Space it is brought back, not closed
    public func toggleVisualizerStudio() {
        if let studio = visualizerStudioWindow, studio.isVisible, studio.isOnActiveSpace {
            visualizerStudioWindow?.orderOut(nil)
            updateActivityState()
        } else {
            startVisualizerStudio()
        }
    }

    func startVisualizerStudio() {
        if visualizerStudioWindow == nil {
            let studio = RetroVisualizerWindow()
            // Where it was left; the first time, centered
            if persistence.state.windowPositions[AppConstants.Window.studioFrameKey] != nil {
                studio.setFrame(auxWindowRect(AppConstants.Window.studioFrameKey, size: studio.frame.size), display: false)
            }
            visualizerStudioWindow = studio
        }
        guard let win = visualizerStudioWindow else { return }
        // The plug-in selected in Preferences; for the Studio's own row, what it showed last (a built-in or MilkDrop)
        let state = persistence.state
        let last = state.studioPreset.flatMap { $0 == .goom || $0 == .avs ? nil : $0 }
        let preset: StudioVisualizerPreset = state.avsPluginSelected ? .avs : state.goomPluginSelected ? .goom : last ?? state.studioBuiltIn
        if win.studioView.currentPreset != preset { win.studioView.currentPreset = preset }
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        updateActivityState()
    }

    func raisePlayerWindows(for keyWindow: WinampWindow) {
        guard let studio = visualizerStudioWindow, studio.isVisible,
              !studio.styleMask.contains(.fullScreen),
              keyWindow === mainWindow || keyWindow === eqWindow || keyWindow === plWindow else { return }
        for window in [plWindow, eqWindow, mainWindow].compactMap({ $0 })
        where window !== keyWindow && window.isVisible && window.isOnActiveSpace && !window.isMiniaturized {
            window.orderFront(nil)
        }
        keyWindow.orderFront(nil)
    }
    
    /// Brings all currently visible MacAmp windows to the front in proper z-order (Playlist -> Equalizer -> MainWindow)
    /// without allowing secondary windows to drop behind other desktop applications when switching window levels or activating.
    public func bringAllWindowsToFront() {
        if let main = mainWindow, main.isMiniaturized || isDeminiaturizing {
            return
        }
        
        let keyWin = NSApp.keyWindow
        
        if persistence.state.isPlaylistVisible, let pl = plWindow, !pl.isMiniaturized {
            pl.orderFront(nil)
        }
        if persistence.state.isEqWindowVisible, let eq = eqWindow, !eq.isMiniaturized {
            eq.orderFront(nil)
        }
        if let main = mainWindow, !main.isMiniaturized {
            main.orderFront(nil)
        }
        
        windowManager.updateAdjacencies()
        windowManager.clampToScreen()
        
        if let key = keyWin as? WinampWindow {
            key.makeKeyAndOrderFront(nil)
        } else {
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }
    
    /// Minimizes the main player window and immediately hides auxiliary windows so they never linger.
    public func minimizeAll() {
        isDeminiaturizing = false
        eqWindow?.orderOut(nil)
        plWindow?.orderOut(nil)
        mainWindow?.miniaturize(nil)
    }
    
    // MARK: - NSWindowDelegate
    public func windowWillMiniaturize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == mainWindow else { return }
        isDeminiaturizing = false
        eqWindow?.orderOut(nil)
        plWindow?.orderOut(nil)
    }
    
    public func windowDidMiniaturize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == mainWindow else { return }
        isDeminiaturizing = false
        eqWindow?.orderOut(nil)
        plWindow?.orderOut(nil)
    }
    
    public func windowDidDeminiaturize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == mainWindow else { return }
        isDeminiaturizing = false
        bringAllWindowsToFront()
    }
    
    // MARK: - Shade Mode Toggles
    public func toggleMainShade() {
        let newShade = !mainView.isShadeMode
        let newH: CGFloat = newShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        windowManager.handleWindowHeightChange(id: .main, newHeightUnscaled: newH)
        mainView.isShadeMode = newShade
        
        mainView.needsLayout = true
        mainView.layoutSubtreeIfNeeded()
        mainView.needsDisplay = true
        mainView.subviews.forEach { $0.needsDisplay = true }
        
        persistence.state.isMainWindowShade = newShade
        persistence.saveSession()
        updateWindowMasks()
    }
    
    public func toggleEqShade() {
        let newShade = !eqView.isShadeMode
        let newH: CGFloat = newShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        windowManager.handleWindowHeightChange(id: .equalizer, newHeightUnscaled: newH)
        eqView.isShadeMode = newShade
        
        eqView.needsLayout = true
        eqView.layoutSubtreeIfNeeded()
        eqView.needsDisplay = true
        eqView.subviews.forEach { $0.needsDisplay = true }
        
        persistence.state.isEqWindowShade = newShade
        persistence.saveSession()
        updateWindowMasks()
    }
    
    public func togglePlShade() {
        let newShade = !plView.isShadeMode
        let savedHeight = CGFloat(persistence.state.playlistWindowSize.last ?? 0)
        let newH = newShade ? AppConstants.Window.shadeHeight : max(AppConstants.Window.height, savedHeight)
        plView.isShadeMode = newShade
        windowManager.handleWindowHeightChange(id: .playlist, newHeightUnscaled: newH)
    }
    
    // MARK: - Double Size Toggle (1x / 2x)
    public func setScale(_ factor: ScaleFactor) {
        windowManager.setScale(factor.scale)
        mainView?.doubleSizeButton.isSelected = factor == .x2
        persistence.state.scaleFactor = factor
        persistence.saveSession()
        updateWindowMasks()
        MainMenuManager.shared.updateStates()
    }
    
    public func setEqDoubleSizeLinked(_ linked: Bool) {
        persistence.state.eqDoubleSizeLinked = linked
        setScale(persistence.state.scaleFactor)
    }

    public func toggleDoubleSize() {
        setScale(persistence.state.scaleFactor.toggle)
    }

    func setInterfaceScale(_ scale: InterfaceScale) {
        guard persistence.state.interfaceScale != scale else { return }
        persistence.state.interfaceScale = scale
        setScale(persistence.state.scaleFactor)
        visualizerStudioWindow?.updateInterfaceScale()
        NSApp.windows.forEach { $0.updateDialogScale(scale.multiplier) }
    }
    
    // MARK: - Window Masking & Transparency
    /// Applies skin-defined transparency masks from REGION.TXT to MainWindow and EqualizerWindow.
    public func updateWindowMasks() {
        let region = skinManager.currentSkin?.region
        let mainPath = mainView.isShadeMode ? region?.windowShadeMask : region?.normalMask
        let eqPath = eqView.isShadeMode ? region?.equalizerShadeMask : region?.equalizerMask
        
        Self.applyWindowMask(path: mainPath, to: mainView)
        Self.applyWindowMask(path: eqPath, to: eqView)
    }
    
    static func applyWindowMask(path: CGPath?, to view: NSView) {
        guard let path = path else {
            view.layer?.mask = nil
            view.window?.invalidateShadow()
            return
        }
        
        let maskLayer = CAShapeLayer()
        maskLayer.frame = view.bounds
        maskLayer.fillColor = NSColor.black.cgColor
        maskLayer.fillRule = .nonZero
        maskLayer.path = path
        view.layer?.mask = maskLayer
        view.window?.invalidateShadow()
    }
}
