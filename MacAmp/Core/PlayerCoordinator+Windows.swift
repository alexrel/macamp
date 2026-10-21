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
        bringAllWindowsToFront()
        mainView?.alwaysOnTopButton?.isSelected = enabled
    }
    
    @objc public func handleToggleVisualizerStudio() {
        toggleVisualizerStudio()
    }
    
    /// Opens or closes the Fullscreen Retro Visualizer Studio window (Ctrl+Shift+K)
    public func toggleVisualizerStudio() {
        if visualizerStudioWindow == nil {
            visualizerStudioWindow = RetroVisualizerWindow()
        }
        guard let win = visualizerStudioWindow else { return }
        
        if win.isVisible {
            win.orderOut(nil)
        } else {
            win.makeKeyAndOrderFront(nil)
        }
        updateActivityState()
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
        let newH: CGFloat = newShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        windowManager.handleWindowHeightChange(id: .playlist, newHeightUnscaled: newH)
        plView.isShadeMode = newShade
        
        plView.needsLayout = true
        plView.layoutSubtreeIfNeeded()
        plView.needsDisplay = true
        plView.subviews.forEach { $0.needsDisplay = true }
        
        persistence.state.isPlaylistShade = newShade
        persistence.saveSession()
    }
    
    // MARK: - Double Size Toggle (1x / 2x)
    public func setScale(_ factor: ScaleFactor) {
        let newScale: CGFloat = (factor == .x2) ? 2.0 : 1.0
        windowManager.setScale(newScale)
        mainView?.doubleSizeButton.isSelected = (newScale == 2.0)
        persistence.state.scaleFactor = factor
        persistence.saveSession()
        updateWindowMasks()
        MainMenuManager.shared.updateStates()
    }
    
    public func toggleDoubleSize() {
        let newScale: CGFloat = (windowManager.currentScale == 1.0) ? 2.0 : 1.0
        windowManager.setScale(newScale)
        mainView.doubleSizeButton.isSelected = (newScale == 2.0)
        persistence.state.scaleFactor = (newScale == 2.0) ? .x2 : .x1
        persistence.saveSession()
        updateWindowMasks()
        MainMenuManager.shared.updateStates()
    }
    
    // MARK: - Window Masking & Transparency
    /// Applies skin-defined transparency masks from REGION.TXT to MainWindow and EqualizerWindow.
    public func updateWindowMasks() {
        let region = skinManager.currentSkin?.region
        let mainPath = mainView.isShadeMode ? region?.windowShadeMask : region?.normalMask
        let eqPath = eqView.isShadeMode ? region?.equalizerShadeMask : region?.equalizerMask
        
        applyWindowMask(path: mainPath, to: mainView)
        applyWindowMask(path: eqPath, to: eqView)
    }
    
    func applyWindowMask(path: CGPath?, to view: NSView) {
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
