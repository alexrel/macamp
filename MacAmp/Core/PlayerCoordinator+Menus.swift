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
    /// Skins ▸ as in 2.95: Skin Browser, <Base Skin>, installed skins, << Get more skins! >>; then MacAmp's file actions.
    public func buildSkinsSubmenu() -> NSMenu {
        let skinsMenu = NSMenu(title: "Skins")
        skinsMenu.autoenablesItems = false
        skinsMenu.addItem(menuItem("Skin Browser...", #selector(handleSkinBrowser), key: "s", mods: [.option]))
        skinsMenu.addItem(.separator())
        skinsMenu.addItem(menuItem("<Base Skin>", #selector(handleResetBaseSkin), checked: skinManager.isBaseSkinActive))
        let installedSkins = skinManager.installedSkins()
        for skinURL in installedSkins {
            let name = skinURL.deletingPathExtension().lastPathComponent
            let isActive = !skinManager.isBaseSkinActive && (skinManager.currentSkinURL?.path == skinURL.path || skinManager.currentSkin?.name == name)
            let item = menuItem(name, #selector(handleSkinSelected(_:)), checked: isActive)
            item.representedObject = skinURL
            skinsMenu.addItem(item)
        }
        skinsMenu.addItem(menuItem("<< Get more skins! >>", #selector(handleGetMoreSkins)))
        
        skinsMenu.addItem(.separator())
        skinsMenu.addItem(menuItem("Load Skin...", #selector(handleLoadSkin)))
        if !installedSkins.isEmpty {
            let deleteMenu = NSMenu(title: "Delete Skin")
            for skinURL in installedSkins {
                let delItem = menuItem(skinURL.deletingPathExtension().lastPathComponent, #selector(handleDeleteSkin(_:)))
                delItem.representedObject = skinURL
                deleteMenu.addItem(delItem)
            }
            skinsMenu.addItem(submenuItem("Delete Skin", deleteMenu))
        }
        skinsMenu.addItem(menuItem("Open Skins Folder", #selector(handleOpenSkinsFolder)))
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
    
    /// One menu item targeting the coordinator (key equivalents are shown like Winamp's; plain letters have no modifier).
    func menuItem(_ title: String, _ action: Selector?, key: String = "", mods: NSEvent.ModifierFlags = [],
                  checked: Bool = false, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        return item
    }
    
    func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
    
    /// Winamp 2.95 main menu (lightning bolt / right click), same order and shortcuts (docs/UI-screens/menu*.png).
    public func buildWinampMenu() -> NSMenu {
        let menu = NSMenu(title: "Winamp Menu")
        menu.autoenablesItems = false
        menu.addItem(menuItem("MacAmp...", #selector(handleAbout)))
        menu.addItem(.separator())
        menu.addItem(submenuItem("Play", buildPlayMenu()))
        menu.addItem(menuItem("View file info", #selector(handleTrackInfo), key: "3", mods: [.option]))
        menu.addItem(submenuItem("Bookmarks", buildBookmarksMenu()))
        menu.addItem(.separator())
        menu.addItem(menuItem("Main Window", #selector(handleToggleMainWindow), key: "w", mods: [.option], checked: mainWindow?.isVisible ?? true))
        menu.addItem(menuItem("Playlist Editor", #selector(handleTogglePlaylist), key: "e", mods: [.option], checked: mainView.plToggle.isOn))
        menu.addItem(menuItem("Equalizer", #selector(handleToggleEqualizer), key: "g", mods: [.option], checked: mainView.eqToggle.isOn))
        menu.addItem(menuItem("Library", #selector(handleToggleLibrary), key: "l", mods: [.option], checked: libraryWindow?.isVisible ?? false))
        menu.addItem(menuItem("Minibrowser", #selector(handleToggleBrowser), key: "t", mods: [.option], checked: browser?.window.isVisible ?? false))
        menu.addItem(menuItem("Video", #selector(handleToggleVideo), key: "v", mods: [.option], checked: video?.window.isVisible ?? false))
        menu.addItem(.separator())
        menu.addItem(submenuItem("Options", buildOptionsMenu()))
        menu.addItem(submenuItem("Playback", buildPlaybackMenu()))
        menu.addItem(submenuItem("Visualization", buildVisualizationPluginMenu()))
        menu.addItem(submenuItem("Skins", buildSkinsSubmenu()))
        menu.addItem(.separator())
        menu.addItem(menuItem("Exit", #selector(handleExit), key: "q", mods: [.command]))
        return menu
    }
    
    func buildPlayMenu() -> NSMenu {
        let menu = NSMenu(title: "Play")
        menu.autoenablesItems = false
        menu.addItem(menuItem("File...", #selector(handlePlayFile), key: "l"))
        menu.addItem(menuItem("Location...", #selector(handlePlayURL), key: "l", mods: [.control]))
        menu.addItem(menuItem("Directory...", #selector(handlePlayDirectory), key: "l", mods: [.shift]))
        menu.addItem(.separator())
        let discs = PlayerCoordinator.mountedAudioCDs()
        if discs.isEmpty {
            menu.addItem(menuItem("Audio CD", nil, enabled: false))
        }
        for disc in discs {
            let item = menuItem("Audio CD \(disc.lastPathComponent)", #selector(handlePlayAudioCD(_:)))
            item.representedObject = disc
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let bookmarks = NSMenu(title: "Bookmark")
        menu.addItem(submenuItem("Bookmark", bookmarks))
        for bookmark in BookmarkStore.shared.items {
            let item = menuItem(bookmark.title, #selector(handleBookmarkSelected(_:)))
            item.representedObject = bookmark.id
            bookmarks.addItem(item)
        }
        if bookmarks.items.isEmpty {
            bookmarks.addItem(menuItem("(no bookmarks)", nil, enabled: false))
        }
        return menu
    }
    
    func buildOptionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Options")
        menu.autoenablesItems = false
        let remaining = mainView.timeDisplay.mode == .remaining
        menu.addItem(menuItem("Preferences...", #selector(handlePreferences), key: "p", mods: [.control]))
        menu.addItem(submenuItem("Skins", buildSkinsSubmenu()))
        menu.addItem(.separator())
        menu.addItem(menuItem("Time elapsed (⌃T toggles)", #selector(handleTimeElapsed), checked: !remaining))
        menu.addItem(menuItem("Time remaining (⌃T toggles)", #selector(handleTimeRemaining), checked: remaining))
        menu.addItem(.separator())
        menu.addItem(menuItem("Always On Top", #selector(handleToggleAlwaysOnTop), key: "a", mods: [.control], checked: persistence.state.isAlwaysOnTop))
        menu.addItem(menuItem("Double Size", #selector(handleToggleDoubleSize), key: "d", mods: [.control], checked: windowManager.currentScale == 2.0))
        menu.addItem(menuItem("EasyMove", #selector(handleToggleEasyMove), key: "e", mods: [.control], checked: persistence.state.easyMove))
        menu.addItem(.separator())
        menu.addItem(menuItem("Repeat", #selector(handleToggleRepeat), key: "r", checked: playlist.isRepeat))
        menu.addItem(menuItem("Shuffle", #selector(handleToggleShuffle), key: "s", checked: playlist.isShuffle))
        // MacAmp addition (separate group, principle 5): pick the output device without opening Preferences
        menu.addItem(.separator())
        menu.addItem(submenuItem("Audio Output", buildAudioOutputSubmenu()))
        return menu
    }
    
    func buildPlaybackMenu() -> NSMenu {
        let menu = NSMenu(title: "Playback")
        menu.autoenablesItems = false
        menu.addItem(menuItem("Previous", #selector(handlePrev), key: "z"))
        menu.addItem(menuItem("Play", #selector(handlePlay), key: "x"))
        menu.addItem(menuItem("Pause", #selector(handlePause), key: "c"))
        menu.addItem(menuItem("Stop", #selector(handleStop), key: "v"))
        menu.addItem(menuItem("Next", #selector(handleNext), key: "b"))
        menu.addItem(.separator())
        menu.addItem(menuItem("Stop w/ fadeout", #selector(handleStopWithFadeout), key: "v", mods: [.shift]))
        menu.addItem(menuItem("Stop after current", #selector(handleToggleStopAfterCurrent), key: "v", mods: [.control], checked: stopAfterCurrent))
        menu.addItem(menuItem("Back 5 seconds", #selector(handleBack5Seconds), key: "\u{F702}"))
        menu.addItem(menuItem("Fwd 5 seconds", #selector(handleForward5Seconds), key: "\u{F703}"))
        menu.addItem(menuItem("Start of list", #selector(handleStartOfList), key: "z", mods: [.control]))
        menu.addItem(menuItem("10 tracks back", #selector(handleTenTracksBack), key: "1", mods: [.numericPad]))
        menu.addItem(menuItem("10 tracks fwd", #selector(handleTenTracksForward), key: "3", mods: [.numericPad]))
        menu.addItem(.separator())
        menu.addItem(menuItem("Jump to time", #selector(handleJumpToTime), key: "j", mods: [.control]))
        menu.addItem(menuItem("Jump to file", #selector(handleJumpToFile), key: "j"))
        return menu
    }
    
    /// Visualization ▸ as in 2.95; the "plug-in" is MacAmp's Retro Visualizer Studio.
    func buildVisualizationPluginMenu() -> NSMenu {
        let menu = NSMenu(title: "Visualization")
        menu.autoenablesItems = false
        menu.addItem(menuItem("Visualization options...", #selector(handleVisualizationOptions), key: "o", mods: [.option]))
        menu.addItem(.separator())
        menu.addItem(menuItem("Start/Stop plug-in", #selector(handleToggleVisualizerStudio), key: "k", mods: [.control, .shift]))
        menu.addItem(menuItem("Configure plug-in...", #selector(handleConfigureVisPlugin), key: "k", mods: [.option]))
        menu.addItem(menuItem("Select plug-in...", #selector(handleSelectVisPlugin), key: "k", mods: [.control]))
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
    
    // MARK: - Winamp 2.95 menu actions
    
    /// ⌥W: show or hide the main window (the others stay).
    @objc public func handleToggleMainWindow() {
        guard let mainWindow else { return }
        if mainWindow.isVisible { mainWindow.orderOut(nil) } else { mainWindow.makeKeyAndOrderFront(nil) }
        updateActivityState()
    }
    
    @objc public func handleTimeElapsed() { setTimeDisplayMode(.elapsed) }
    @objc public func handleTimeRemaining() { setTimeDisplayMode(.remaining) }
    
    /// ⌃T and the clock click: elapsed <-> remaining.
    public func toggleTimeDisplayMode() {
        setTimeDisplayMode(mainView.timeDisplay.mode == .elapsed ? .remaining : .elapsed)
    }
    
    func setTimeDisplayMode(_ mode: TimeDisplayMode) {
        mainView.timeDisplay.mode = mode
        persistence.state.timeDisplayMode = mode
        persistence.scheduleSave()
    }
    
    /// EasyMove: main and equalizer windows drag from anywhere, not only by the title bar.
    @objc public func handleToggleEasyMove() {
        persistence.state.easyMove.toggle()
        persistence.scheduleSave()
        mainView.marquee.showTemporaryMessage(persistence.state.easyMove ? "EasyMove: ON" : "EasyMove: OFF")
    }
    
    @objc public func handleBack5Seconds() {
        audioEngine.seek(to: max(0, audioEngine.currentTime - 5))
    }
    
    @objc public func handleForward5Seconds() {
        guard let duration = audioEngine.currentMetadata?.duration else { return }
        audioEngine.seek(to: min(duration, audioEngine.currentTime + 5))
    }
    
    /// ⌃Z: first track of the playlist.
    @objc public func handleStartOfList() {
        guard let first = playlist.tracks.first else { return }
        loadAndPlay(track: first)
    }
    
    @objc public func handleTenTracksBack() { jumpTracks(by: -10) }
    @objc public func handleTenTracksForward() { jumpTracks(by: 10) }
    
    /// Num 1 / Num 3: ten tracks back or forward in list order, stopping at the ends.
    func jumpTracks(by offset: Int) {
        guard !playlist.tracks.isEmpty else { return }
        let current = playlist.currentIndex ?? 0
        let target = min(playlist.tracks.count - 1, max(0, current + offset))
        loadAndPlay(track: playlist.tracks[target])
    }
    
    @objc public func handleVisualizationOptions() {
        PreferencesWindow.show(treeItem: .visualization)
    }
    
    /// Configure plug-in: its settings live on Preferences ▸ Plug-ins ▸ Visualization (it used to only open the Studio, which did nothing when it was already open).
    @objc public func handleConfigureVisPlugin() {
        PreferencesWindow.show(treeItem: .visPlugin)
    }
    
    /// Select plug-in: Preferences ▸ Plug-ins ▸ Visualization.
    @objc public func handleSelectVisPlugin() {
        PreferencesWindow.show(treeItem: .visPlugin)
    }
    
    @objc public func handleSkinBrowser() {
        PreferencesWindow.show(treeItem: .skins)
    }
    
    /// The classic skins archive (Winamp Skin Museum); downloaded .wsz files open straight into MacAmp.
    @objc public func handleGetMoreSkins() {
        NSWorkspace.shared.open(URL(string: "https://skins.webamp.org")!)
    }
    
    @objc public func handlePlayAudioCD(_ sender: NSMenuItem) {
        guard let disc = sender.representedObject as? URL, let cd = AudioCD(volume: disc) else { return }
        LibraryActions.playCD(cd, tracks: cd.trackItems, enqueue: false)
    }
    
    /// Audio CDs macOS has mounted: volumes with a .TOC.plist (tracks appear as "1 Audio Track.aiff", ...).
    static func mountedAudioCDs() -> [URL] {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent(".TOC.plist").path) }
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
        applyRandomSkinIfNeeded()
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
        stopDiskWriter()
        PluginConversion.cancelAll()
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
