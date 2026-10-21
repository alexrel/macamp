import Cocoa
import UniformTypeIdentifiers

extension PlayerCoordinator {
    // MARK: - Visualization Options
    
    public func setVisualizerMode(_ mode: VisualizerMode) {
        mainView.visualizer.mode = mode
        persistence.state.visualizerMode = mode
        persistence.scheduleSave()
        updateActivityState()
    }
    
    public func setVisualizerShowPeaks(_ show: Bool) {
        mainView.visualizer.showPeaks = show
        persistence.state.visualizerShowPeaks = show
        persistence.scheduleSave()
    }
    
    public func updateVisualizerOptions(_ change: (inout VisualizerOptions) -> Void) {
        var options = persistence.state.visualizerOptions
        change(&options)
        persistence.state.visualizerOptions = options
        mainView.visualizer.options = options
        persistence.scheduleSave()
    }
    
    /// Winamp 2.x "Visualization" menu: right-click on the visualizer and Options ▸ Visualization.
    public func buildVisualizationMenu() -> NSMenu {
        let menu = NSMenu(title: "Visualization")
        let vis = mainView.visualizer
        let options = vis.options
        
        func item(_ title: String, checked: Bool, _ action: @escaping () -> Void) -> NSMenuItem {
            let menuItem = Win32ClosureMenuItem(title: title, handler: action)
            menuItem.state = checked ? .on : .off
            return menuItem
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            items.forEach { sub.addItem($0) }
            parent.submenu = sub
            return parent
        }
        
        menu.addItem(item("Spectrum analyzer", checked: vis.mode == .spectrum) { [weak self] in self?.setVisualizerMode(.spectrum) })
        menu.addItem(item("Oscilloscope", checked: vis.mode == .oscilloscope) { [weak self] in self?.setVisualizerMode(.oscilloscope) })
        menu.addItem(item("Off", checked: vis.mode == .off) { [weak self] in self?.setVisualizerMode(.off) })
        menu.addItem(.separator())
        
        var analyzerItems: [NSMenuItem] = AnalyzerStyle.allCases.map { style in
            item(style.title, checked: options.analyzerStyle == style) { [weak self] in self?.updateVisualizerOptions { $0.analyzerStyle = style } }
        }
        analyzerItems.append(.separator())
        analyzerItems.append(item("Peaks", checked: vis.showPeaks) { [weak self] in self?.setVisualizerShowPeaks(!vis.showPeaks) })
        analyzerItems.append(.separator())
        analyzerItems += AnalyzerBands.allCases.reversed().map { bands in
            item(bands.title, checked: options.bands == bands) { [weak self] in self?.updateVisualizerOptions { $0.bands = bands } }
        }
        menu.addItem(submenu("Analyzer options", analyzerItems))
        
        menu.addItem(submenu("Oscilloscope options", ScopeStyle.allCases.map { style in
            item(style.title, checked: options.scopeStyle == style) { [weak self] in self?.updateVisualizerOptions { $0.scopeStyle = style } }
        }))
        menu.addItem(submenu("Analyzer falloff", VisualizerFalloff.allCases.map { speed in
            item(speed.title, checked: options.barFalloff == speed) { [weak self] in self?.updateVisualizerOptions { $0.barFalloff = speed } }
        }))
        menu.addItem(submenu("Peaks falloff", VisualizerFalloff.allCases.map { speed in
            item(speed.title, checked: options.peakFalloff == speed) { [weak self] in self?.updateVisualizerOptions { $0.peakFalloff = speed } }
        }))
        menu.addItem(.separator())
        let studio = item("Visualizer Studio...", checked: visualizerStudioWindow?.isVisible == true) { [weak self] in self?.toggleVisualizerStudio() }
        studio.keyEquivalent = "k"
        studio.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(studio)
        return menu
    }
    
    // MARK: - Context Menu
    public func buildSkinsSubmenu() -> NSMenu {
        let skinsMenu = NSMenu(title: "Skins")
        let baseSkinItem = NSMenuItem(title: "Winamp Classic (Default)", action: #selector(handleResetBaseSkin), keyEquivalent: "")
        baseSkinItem.target = self
        baseSkinItem.state = skinManager.isBaseSkinActive ? .on : .off
        skinsMenu.addItem(baseSkinItem)
        
        let installedSkins = skinManager.installedSkins()
        if !installedSkins.isEmpty {
            skinsMenu.addItem(NSMenuItem.separator())
            for skinURL in installedSkins {
                let name = skinURL.deletingPathExtension().lastPathComponent
                let item = NSMenuItem(title: name, action: #selector(handleSkinSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = skinURL
                let isActive = (!skinManager.isBaseSkinActive && (skinManager.currentSkinURL?.path == skinURL.path || skinManager.currentSkin?.name == name))
                item.state = isActive ? .on : .off
                skinsMenu.addItem(item)
            }
        }
        
        skinsMenu.addItem(NSMenuItem.separator())
        
        let loadSkinItem = NSMenuItem(title: "Load Skin...", action: #selector(handleLoadSkin), keyEquivalent: "")
        loadSkinItem.target = self
        skinsMenu.addItem(loadSkinItem)
        
        if !installedSkins.isEmpty {
            let deleteMenu = NSMenu(title: "Delete Skin")
            for skinURL in installedSkins {
                let name = skinURL.deletingPathExtension().lastPathComponent
                let delItem = NSMenuItem(title: name, action: #selector(handleDeleteSkin(_:)), keyEquivalent: "")
                delItem.target = self
                delItem.representedObject = skinURL
                deleteMenu.addItem(delItem)
            }
            let deleteSkinItem = NSMenuItem(title: "Delete Skin", action: nil, keyEquivalent: "")
            deleteSkinItem.submenu = deleteMenu
            skinsMenu.addItem(deleteSkinItem)
        }
        
        let openFolderItem = NSMenuItem(title: "Open Skins Folder", action: #selector(handleOpenSkinsFolder), keyEquivalent: "")
        openFolderItem.target = self
        skinsMenu.addItem(openFolderItem)
        
        return skinsMenu
    }
    
    public func buildAudioOutputSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Audio Output")
        
        let defaultName = AudioDeviceManager.shared.defaultDevice?.name ?? "System Output"
        let isDefaultActive = (AudioDeviceManager.shared.selectedDeviceUID == nil)
        
        let defItem = NSMenuItem(
            title: "System Default (\(defaultName))",
            action: #selector(handleSelectDefaultAudioOutput),
            keyEquivalent: ""
        )
        defItem.target = self
        defItem.state = isDefaultActive ? .on : .off
        menu.addItem(defItem)
        
        let devices = AudioDeviceManager.shared.availableDevices
        if !devices.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for dev in devices {
                let isSelected = (AudioDeviceManager.shared.selectedDeviceUID == dev.uid)
                let item = NSMenuItem(
                    title: dev.displayName,
                    action: #selector(handleAudioOutputDeviceSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = dev.uid
                item.state = isSelected ? .on : .off
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        let prefItem = NSMenuItem(
            title: "Audio Preferences...",
            action: #selector(handleOpenAudioPreferences),
            keyEquivalent: ""
        )
        prefItem.target = self
        menu.addItem(prefItem)
        
        return menu
    }
    
    @objc public func handleAudioOutputDeviceSelected(_ sender: NSMenuItem) {
        if let uid = sender.representedObject as? String {
            AudioDeviceManager.shared.selectDevice(uid: uid)
        }
    }
    
    @objc public func handleSelectDefaultAudioOutput() {
        AudioDeviceManager.shared.selectDevice(uid: nil)
    }
    
    @objc public func handleOpenAudioPreferences() {
        PreferencesWindow.show(treeItem: .output)
    }
    
    public func buildWinampMenu() -> NSMenu {
        let menu = NSMenu(title: "Winamp Menu")
        
        // 1. About
        let aboutItem = NSMenuItem(title: "MacAmp...", action: #selector(handleAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        // 2. Track Info / ID3 Tag Editor
        let infoItem = NSMenuItem(title: "View file info...", action: #selector(handleTrackInfo), keyEquivalent: "3")
        infoItem.keyEquivalentModifierMask = [.option]
        infoItem.target = self
        menu.addItem(infoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Play submenu
        let playMenu = NSMenu(title: "Play")
        let playFileItem = NSMenuItem(title: "File...", action: #selector(handlePlayFile), keyEquivalent: "l")
        playFileItem.target = self
        playMenu.addItem(playFileItem)
        
        let playDirItem = NSMenuItem(title: "Directory...", action: #selector(handlePlayDirectory), keyEquivalent: "L")
        playDirItem.target = self
        playMenu.addItem(playDirItem)
        
        let playURLItem = NSMenuItem(title: "URL...", action: #selector(handlePlayURL), keyEquivalent: "u")
        playURLItem.target = self
        playMenu.addItem(playURLItem)
        playMenu.addItem(NSMenuItem.separator())
        
        let jumpFileItem = NSMenuItem(title: "Jump to file...", action: #selector(handleJumpToFile), keyEquivalent: "j")
        jumpFileItem.target = self
        playMenu.addItem(jumpFileItem)
        
        let playMenuItem = NSMenuItem(title: "Play", action: nil, keyEquivalent: "")
        playMenuItem.submenu = playMenu
        menu.addItem(playMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // 4. Windows toggles
        let eqItem = NSMenuItem(title: "Equalizer", action: #selector(handleToggleEqualizer), keyEquivalent: "")
        eqItem.target = self
        eqItem.state = mainView.eqToggle.isOn ? .on : .off
        menu.addItem(eqItem)
        
        let plItem = NSMenuItem(title: "Playlist", action: #selector(handleTogglePlaylist), keyEquivalent: "")
        plItem.target = self
        plItem.state = mainView.plToggle.isOn ? .on : .off
        menu.addItem(plItem)
        menu.addItem(NSMenuItem.separator())
        
        // 5. Options submenu
        let optionsMenu = NSMenu(title: "Options")
        
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(handlePreferences), keyEquivalent: "p")
        prefsItem.keyEquivalentModifierMask = [.control]
        prefsItem.target = self
        optionsMenu.addItem(prefsItem)
        optionsMenu.addItem(NSMenuItem.separator())
        
        let visItem = NSMenuItem(title: "Visualization", action: nil, keyEquivalent: "")
        visItem.submenu = buildVisualizationMenu()
        optionsMenu.addItem(visItem)
        optionsMenu.addItem(NSMenuItem.separator())
        
        let skinsSubmenu = buildSkinsSubmenu()
        let skinsSubItem = NSMenuItem(title: "Skins", action: nil, keyEquivalent: "")
        skinsSubItem.submenu = skinsSubmenu
        optionsMenu.addItem(skinsSubItem)
        
        let outputSubmenu = buildAudioOutputSubmenu()
        let outputSubItem = NSMenuItem(title: "Audio Output", action: nil, keyEquivalent: "")
        outputSubItem.submenu = outputSubmenu
        optionsMenu.addItem(outputSubItem)
        optionsMenu.addItem(NSMenuItem.separator())
        
        let topItem = NSMenuItem(title: "Always On Top", action: #selector(handleToggleAlwaysOnTop), keyEquivalent: "")
        topItem.target = self
        topItem.state = persistence.state.isAlwaysOnTop ? .on : .off
        optionsMenu.addItem(topItem)
        
        let dblItem = NSMenuItem(title: "Double Size", action: #selector(handleToggleDoubleSize), keyEquivalent: "d")
        dblItem.keyEquivalentModifierMask = [.control]
        dblItem.target = self
        dblItem.state = (windowManager.currentScale == 2.0) ? .on : .off
        optionsMenu.addItem(dblItem)
        
        let optMenuItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        optMenuItem.submenu = optionsMenu
        menu.addItem(optMenuItem)
        
        // 6. Skins at root menu
        let rootSkinsItem = NSMenuItem(title: "Skins", action: nil, keyEquivalent: "")
        rootSkinsItem.submenu = buildSkinsSubmenu()
        menu.addItem(rootSkinsItem)
        
        // 7. Playback submenu
        let pbMenu = NSMenu(title: "Playback")
        let prevItem = NSMenuItem(title: "Previous", action: #selector(handlePrev), keyEquivalent: "z")
        prevItem.keyEquivalentModifierMask = [] // Winamp: plain letter
        prevItem.target = self
        pbMenu.addItem(prevItem)
        
        let playItem = NSMenuItem(title: "Play", action: #selector(handlePlay), keyEquivalent: "x")
        playItem.keyEquivalentModifierMask = [] // Winamp: plain letter
        playItem.target = self
        pbMenu.addItem(playItem)
        
        let pauseItem = NSMenuItem(title: "Pause", action: #selector(handlePause), keyEquivalent: "c")
        pauseItem.keyEquivalentModifierMask = [] // Winamp: plain letter
        pauseItem.target = self
        pbMenu.addItem(pauseItem)
        
        let stopItem = NSMenuItem(title: "Stop", action: #selector(handleStop), keyEquivalent: "v")
        stopItem.keyEquivalentModifierMask = [] // Winamp: plain letter
        stopItem.target = self
        pbMenu.addItem(stopItem)
        
        let fadeStopItem = NSMenuItem(title: "Stop w/ fadeout", action: #selector(handleStopWithFadeout), keyEquivalent: "v")
        fadeStopItem.keyEquivalentModifierMask = [.shift]
        fadeStopItem.target = self
        pbMenu.addItem(fadeStopItem)
        
        let stopAfterItem = NSMenuItem(title: "Stop after current", action: #selector(handleToggleStopAfterCurrent), keyEquivalent: "v")
        stopAfterItem.keyEquivalentModifierMask = [.control]
        stopAfterItem.state = stopAfterCurrent ? .on : .off
        stopAfterItem.target = self
        pbMenu.addItem(stopAfterItem)
        
        let nextItem = NSMenuItem(title: "Next", action: #selector(handleNext), keyEquivalent: "b")
        nextItem.keyEquivalentModifierMask = [] // Winamp: plain letter
        nextItem.target = self
        pbMenu.addItem(nextItem)
        pbMenu.addItem(NSMenuItem.separator())
        
        let repItem = NSMenuItem(title: "Repeat", action: #selector(handleToggleRepeat), keyEquivalent: "r")
        repItem.keyEquivalentModifierMask = [] // Winamp: plain letter
        repItem.target = self
        repItem.state = playlist.isRepeat ? .on : .off
        pbMenu.addItem(repItem)
        
        let shufItem = NSMenuItem(title: "Shuffle", action: #selector(handleToggleShuffle), keyEquivalent: "s")
        shufItem.keyEquivalentModifierMask = [] // Winamp: plain letter
        shufItem.target = self
        shufItem.state = playlist.isShuffle ? .on : .off
        pbMenu.addItem(shufItem)
        
        let manualItem = NSMenuItem(title: "Manual playlist advance", action: #selector(handleToggleManualAdvance), keyEquivalent: "")
        manualItem.state = persistence.state.manualPlaylistAdvance ? .on : .off
        manualItem.target = self
        pbMenu.addItem(manualItem)
        pbMenu.addItem(NSMenuItem.separator())
        
        let jumpTimeItem = NSMenuItem(title: "Jump to time...", action: #selector(handleJumpToTime), keyEquivalent: "j")
        jumpTimeItem.keyEquivalentModifierMask = [.control]
        jumpTimeItem.target = self
        pbMenu.addItem(jumpTimeItem)
        
        let pbMenuItem = NSMenuItem(title: "Playback", action: nil, keyEquivalent: "")
        pbMenuItem.submenu = pbMenu
        menu.addItem(pbMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // 8. Exit
        let exitItem = NSMenuItem(title: "Exit", action: #selector(handleExit), keyEquivalent: "q")
        exitItem.target = self
        menu.addItem(exitItem)
        
        return menu
    }
    
    public func showMainContextMenu(at screenPoint: NSPoint? = nil, in view: NSView? = nil) {
        let menu = buildWinampMenu()
        let targetPt = screenPoint ?? NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: targetPt, in: view)
    }
    
    // MARK: - Menu Actions
    @objc public func handleJumpToFile() {
        showJumpToFileWindow()
    }
    
    @objc public func handleJumpToTime() {
        showJumpToTimeWindow()
    }
    
    @objc public func handlePreferences() {
        showPreferencesWindow()
    }
    
    @objc public func handleTrackInfo() {
        showTrackInfoWindow()
    }
    
    @objc public func handleMinimizeAll() {
        minimizeAll()
    }
    
    @objc public func handleBringAllToFront() {
        bringAllWindowsToFront()
    }
    
    @objc public func handleAbout() {
        AboutWindow.show()
    }
    
    @objc public func handlePlayFile() {
        openFileDialog()
    }
    
    @objc public func handlePlayDirectory() {
        openDirectoryDialog()
    }
    
    @objc public func handlePlayURL() {
        openURLDialog()
    }
    
    @objc public func handleToggleEqualizer() {
        mainView.eqToggle.isOn.toggle()
        mainView.eqToggle.onChanged?(mainView.eqToggle.isOn)
    }
    
    @objc public func handleTogglePlaylist() {
        mainView.plToggle.isOn.toggle()
        mainView.plToggle.onChanged?(mainView.plToggle.isOn)
    }
    
    @objc public func handleResetBaseSkin() {
        skinManager.resetToBaseSkin()
    }
    
    @objc public func handleLoadSkin() {
        openSkinChooser()
    }
    
    @objc public func handleSkinSelected(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if skinManager.loadSkin(from: url) {
            persistence.state.activeSkinPath = url.path
            persistence.saveSession()
        }
    }
    
    @objc public func handleDeleteSkin(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let skinName = url.deletingPathExtension().lastPathComponent
        
        if Win32Dialog.confirm(title: "Delete Skin",
                               message: "Are you sure you want to delete the skin \"\(skinName)\"?",
                               confirmTitle: "Delete") {
            skinManager.deleteSkin(at: url)
        }
    }
    
    @objc public func handleOpenSkinsFolder() {
        let dir = skinManager.skinsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
    
    @objc public func handleToggleAlwaysOnTop() {
        setAlwaysOnTop(!persistence.state.isAlwaysOnTop)
    }
    
    @objc public func handleToggleDoubleSize() {
        toggleDoubleSize()
    }
    
    @objc public func handlePrev() {
        playPrevious()
    }
    
    @objc public func handlePlay() {
        if audioEngine.status == .paused {
            audioEngine.play()
            MediaKeyController.shared.updateNowPlayingInfo()
            StatusBarManager.shared.updateStatus()
        } else if audioEngine.status == .playing {
            audioEngine.seek(to: 0)
            MediaKeyController.shared.updateNowPlayingInfo()
        } else if let track = playlist.currentTrack ?? playlist.tracks.first {
            loadAndPlay(track: track)
        }
    }
    
    @objc public func handlePause() {
        audioEngine.togglePause()
        MediaKeyController.shared.updateNowPlayingInfo()
        StatusBarManager.shared.updateStatus()
    }
    
    @objc public func handlePlayPause() {
        if audioEngine.status == .playing {
            audioEngine.togglePause()
        } else {
            handlePlay()
        }
        MediaKeyController.shared.updateNowPlayingInfo()
        StatusBarManager.shared.updateStatus()
    }
    
    public func seek(to time: TimeInterval) {
        audioEngine.seek(to: time)
        persistence.state.lastPlayedTrackTime = time
        persistence.scheduleSave()
        MediaKeyController.shared.updateNowPlayingInfo()
    }
    
    @objc public func handleStop() {
        audioEngine.stop()
        persistence.state.lastPlaybackState = .stopped
        persistence.state.lastPlayedTrackTime = 0.0
        persistence.saveSession()
        mainView.timeDisplay.status = .stopped
        mainView.seekSlider.isThumbHidden = true
        mainView.seekSlider.value = 0.0
        mainView.visualizer.clear()
        mainView.needsDisplay = true
        MediaKeyController.shared.updateNowPlayingInfo()
        StatusBarManager.shared.updateStatus()
    }
    
    @objc public func handleNext() {
        playNext()
    }
    
    
    @objc public func increaseVolume(by delta: Double = 0.05) {
        let newVol = min(1.0, audioEngine.volume + delta)
        audioEngine.setVolume(newVol)
        mainView.volumeSlider.value = newVol
        persistence.state.volume = newVol
        mainView.marquee.showTemporaryMessage("Volume: \(Int(newVol * 100))%")
        mainView.needsDisplay = true
    }
    
    @objc public func decreaseVolume(by delta: Double = 0.05) {
        let newVol = max(0.0, audioEngine.volume - delta)
        audioEngine.setVolume(newVol)
        mainView.volumeSlider.value = newVol
        persistence.state.volume = newVol
        mainView.marquee.showTemporaryMessage("Volume: \(Int(newVol * 100))%")
        mainView.needsDisplay = true
    }
    
    @objc public func toggleMute() {
        if audioEngine.volume > 0.001 {
            preMuteVolume = audioEngine.volume
            audioEngine.setVolume(0.0)
            mainView.volumeSlider.value = 0.0
            persistence.state.volume = 0.0
            mainView.marquee.showTemporaryMessage("Mute: ON")
        } else {
            let restored = (preMuteVolume > 0.001) ? preMuteVolume : 0.5
            audioEngine.setVolume(restored)
            mainView.volumeSlider.value = restored
            persistence.state.volume = restored
            mainView.marquee.showTemporaryMessage("Volume: \(Int(restored * 100))%")
        }
        mainView.needsDisplay = true
    }
    
    @objc public func handleToggleRepeat() {
        let newR = !playlist.isRepeat
        playlist.isRepeat = newR
        mainView.repeatToggle.isOn = newR
        persistence.state.isRepeat = newR
    }
    
    @objc public func handleToggleShuffle() {
        let newS = !playlist.isShuffle
        playlist.isShuffle = newS
        mainView.shuffleToggle.isOn = newS
        persistence.state.isShuffle = newS
    }
    
    @objc public func handleExit() {
        NSApp.terminate(nil)
    }
}
