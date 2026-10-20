import Cocoa

public final class MainMenuManager: NSObject, NSMenuDelegate {
    public static let shared = MainMenuManager()
    
    private var optionsMenu: NSMenu?
    private var playbackMenu: NSMenu?
    private var windowMenu: NSMenu?
    private var skinsSubmenu: NSMenu?
    private var audioOutputSubmenu: NSMenu?
    
    private var alwaysOnTopItem: NSMenuItem?
    private var doubleSizeItem: NSMenuItem?
    private var eqToggleItem: NSMenuItem?
    private var plToggleItem: NSMenuItem?
    private var repeatItem: NSMenuItem?
    private var shuffleItem: NSMenuItem?
    private var stopAfterCurrentItem: NSMenuItem?
    private var manualAdvanceItem: NSMenuItem?
    
    public override init() {
        super.init()
    }
    
    public func setupMenu() {
        let mainMenu = NSMenu()
        let coord = PlayerCoordinator.shared
        
        // 1. Application Menu ("MacAmp")
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "MacAmp")
        
        let aboutItem = NSMenuItem(title: "About MacAmp", action: #selector(PlayerCoordinator.handleAbout), keyEquivalent: "")
        aboutItem.target = coord
        appMenu.addItem(aboutItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(PlayerCoordinator.handlePreferences), keyEquivalent: ",")
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = coord
        appMenu.addItem(prefsItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        let hideItem = NSMenuItem(title: "Hide MacAmp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(hideItem)
        
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        
        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAllItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit MacAmp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)
        
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        
        let openFileItem = NSMenuItem(title: "Open Audio File...", action: #selector(PlayerCoordinator.handlePlayFile), keyEquivalent: "o")
        openFileItem.keyEquivalentModifierMask = [.command]
        openFileItem.target = coord
        fileMenu.addItem(openFileItem)
        
        let openDirItem = NSMenuItem(title: "Open Folder...", action: #selector(PlayerCoordinator.handlePlayDirectory), keyEquivalent: "O")
        openDirItem.keyEquivalentModifierMask = [.command, .shift]
        openDirItem.target = coord
        fileMenu.addItem(openDirItem)
        
        let openURLItem = NSMenuItem(title: "Open Location URL...", action: #selector(PlayerCoordinator.handlePlayURL), keyEquivalent: "u")
        openURLItem.keyEquivalentModifierMask = [.command]
        openURLItem.target = coord
        fileMenu.addItem(openURLItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeItem)
        
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // Standard Edit menu: text fields (Track Info, Jump to File, Preferences) need ⌘C/⌘V/⌘X/⌘A/⌘Z
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // 3. Playback Menu
        let pbMenuItem = NSMenuItem()
        let pbMenu = NSMenu(title: "Playback")
        pbMenu.delegate = self
        self.playbackMenu = pbMenu
        
        let prevItem = NSMenuItem(title: "Previous", action: #selector(PlayerCoordinator.handlePrev), keyEquivalent: "z")
        prevItem.keyEquivalentModifierMask = [] // Winamp single-letter key; ⌘-letters stay free for Edit
        prevItem.target = coord
        pbMenu.addItem(prevItem)
        
        let playItem = NSMenuItem(title: "Play", action: #selector(PlayerCoordinator.handlePlay), keyEquivalent: "x")
        playItem.keyEquivalentModifierMask = [] // Winamp single-letter key; ⌘-letters stay free for Edit
        playItem.target = coord
        pbMenu.addItem(playItem)
        
        let pauseItem = NSMenuItem(title: "Pause", action: #selector(PlayerCoordinator.handlePause), keyEquivalent: "c")
        pauseItem.keyEquivalentModifierMask = [] // Winamp single-letter key; ⌘-letters stay free for Edit
        pauseItem.target = coord
        pbMenu.addItem(pauseItem)
        
        let stopItem = NSMenuItem(title: "Stop", action: #selector(PlayerCoordinator.handleStop), keyEquivalent: "v")
        stopItem.keyEquivalentModifierMask = [] // Winamp single-letter key; ⌘-letters stay free for Edit
        stopItem.target = coord
        pbMenu.addItem(stopItem)
        
        let fadeStopItem = NSMenuItem(title: "Stop w/ fadeout", action: #selector(PlayerCoordinator.handleStopWithFadeout), keyEquivalent: "v")
        fadeStopItem.keyEquivalentModifierMask = [.shift]
        fadeStopItem.target = coord
        pbMenu.addItem(fadeStopItem)
        
        let stopAfterItem = NSMenuItem(title: "Stop after current", action: #selector(PlayerCoordinator.handleToggleStopAfterCurrent), keyEquivalent: "v")
        stopAfterItem.keyEquivalentModifierMask = [.control]
        stopAfterItem.target = coord
        pbMenu.addItem(stopAfterItem)
        self.stopAfterCurrentItem = stopAfterItem
        
        let nextItem = NSMenuItem(title: "Next", action: #selector(PlayerCoordinator.handleNext), keyEquivalent: "b")
        nextItem.keyEquivalentModifierMask = [] // Winamp single-letter key; ⌘-letters stay free for Edit
        nextItem.target = coord
        pbMenu.addItem(nextItem)
        
        pbMenu.addItem(NSMenuItem.separator())
        
        let repItem = NSMenuItem(title: "Repeat", action: #selector(PlayerCoordinator.handleToggleRepeat), keyEquivalent: "r")
        repItem.keyEquivalentModifierMask = [] // Winamp single-letter key; ⌘-letters stay free for Edit
        repItem.target = coord
        pbMenu.addItem(repItem)
        self.repeatItem = repItem
        
        let shufItem = NSMenuItem(title: "Shuffle", action: #selector(PlayerCoordinator.handleToggleShuffle), keyEquivalent: "s")
        shufItem.keyEquivalentModifierMask = [] // Winamp single-letter key; ⌘-letters stay free for Edit
        shufItem.target = coord
        pbMenu.addItem(shufItem)
        self.shuffleItem = shufItem
        
        let manualItem = NSMenuItem(title: "Manual playlist advance", action: #selector(PlayerCoordinator.handleToggleManualAdvance), keyEquivalent: "")
        manualItem.target = coord
        pbMenu.addItem(manualItem)
        self.manualAdvanceItem = manualItem
        
        pbMenu.addItem(NSMenuItem.separator())
        
        let jumpFileItem = NSMenuItem(title: "Jump to File...", action: #selector(PlayerCoordinator.handleJumpToFile), keyEquivalent: "j")
        jumpFileItem.keyEquivalentModifierMask = []
        jumpFileItem.target = coord
        pbMenu.addItem(jumpFileItem)
        
        let jumpTimeItem = NSMenuItem(title: "Jump to Time...", action: #selector(PlayerCoordinator.handleJumpToTime), keyEquivalent: "j")
        jumpTimeItem.keyEquivalentModifierMask = [.control]
        jumpTimeItem.target = coord
        pbMenu.addItem(jumpTimeItem)
        
        pbMenuItem.submenu = pbMenu
        mainMenu.addItem(pbMenuItem)
        
        // 4. Track Menu
        let trackMenuItem = NSMenuItem()
        let trackMenu = NSMenu(title: "Track")
        
        let trackInfoItem = NSMenuItem(title: "Track Info / ID3 Tag Editor...", action: #selector(PlayerCoordinator.handleTrackInfo), keyEquivalent: "3")
        trackInfoItem.keyEquivalentModifierMask = [.option]
        trackInfoItem.target = coord
        trackMenu.addItem(trackInfoItem)
        
        trackMenuItem.submenu = trackMenu
        mainMenu.addItem(trackMenuItem)
        
        // 5. Options Menu
        let optionsMenuItem = NSMenuItem()
        let optsMenu = NSMenu(title: "Options")
        optsMenu.delegate = self
        self.optionsMenu = optsMenu
        
        let optsPrefsItem = NSMenuItem(title: "Preferences...", action: #selector(PlayerCoordinator.handlePreferences), keyEquivalent: "p")
        optsPrefsItem.keyEquivalentModifierMask = [.control]
        optsPrefsItem.target = coord
        optsMenu.addItem(optsPrefsItem)
        
        optsMenu.addItem(NSMenuItem.separator())
        
        let skinsItem = NSMenuItem(title: "Skins", action: nil, keyEquivalent: "")
        let skinsSub = NSMenu(title: "Skins")
        skinsItem.submenu = skinsSub
        self.skinsSubmenu = skinsSub
        optsMenu.addItem(skinsItem)
        
        let outputItem = NSMenuItem(title: "Audio Output", action: nil, keyEquivalent: "")
        let outputSub = NSMenu(title: "Audio Output")
        outputItem.submenu = outputSub
        self.audioOutputSubmenu = outputSub
        optsMenu.addItem(outputItem)
        
        optsMenu.addItem(NSMenuItem.separator())
        
        let aotItem = NSMenuItem(title: "Always On Top", action: #selector(PlayerCoordinator.handleToggleAlwaysOnTop), keyEquivalent: "t")
        aotItem.keyEquivalentModifierMask = [.command]
        aotItem.target = coord
        optsMenu.addItem(aotItem)
        self.alwaysOnTopItem = aotItem
        
        let dblItem = NSMenuItem(title: "Double Size", action: #selector(PlayerCoordinator.handleToggleDoubleSize), keyEquivalent: "d")
        dblItem.keyEquivalentModifierMask = [.control]
        dblItem.target = coord
        optsMenu.addItem(dblItem)
        self.doubleSizeItem = dblItem
        
        optionsMenuItem.submenu = optsMenu
        mainMenu.addItem(optionsMenuItem)
        
        // 6. Window Menu
        let winMenuItem = NSMenuItem()
        let winMenu = NSMenu(title: "Window")
        winMenu.delegate = self
        self.windowMenu = winMenu
        
        let eqItem = NSMenuItem(title: "Equalizer", action: #selector(PlayerCoordinator.handleToggleEqualizer), keyEquivalent: "e")
        eqItem.keyEquivalentModifierMask = [.command]
        eqItem.target = coord
        winMenu.addItem(eqItem)
        self.eqToggleItem = eqItem
        
        let plItem = NSMenuItem(title: "Playlist Editor", action: #selector(PlayerCoordinator.handleTogglePlaylist), keyEquivalent: "p")
        plItem.keyEquivalentModifierMask = [.command]
        plItem.target = coord
        winMenu.addItem(plItem)
        self.plToggleItem = plItem
        
        let visStudioItem = NSMenuItem(title: "Retro Visualizer Studio", action: #selector(PlayerCoordinator.handleToggleVisualizerStudio), keyEquivalent: "k")
        visStudioItem.keyEquivalentModifierMask = [.control, .shift]
        visStudioItem.target = coord
        winMenu.addItem(visStudioItem)
        
        winMenu.addItem(NSMenuItem.separator())
        
        let minItem = NSMenuItem(title: "Minimize All", action: #selector(PlayerCoordinator.handleMinimizeAll), keyEquivalent: "m")
        minItem.keyEquivalentModifierMask = [.command]
        minItem.target = coord
        winMenu.addItem(minItem)
        
        let frontItem = NSMenuItem(title: "Bring All to Front", action: #selector(PlayerCoordinator.handleBringAllToFront), keyEquivalent: "")
        frontItem.target = coord
        winMenu.addItem(frontItem)
        
        winMenuItem.submenu = winMenu
        mainMenu.addItem(winMenuItem)
        NSApp.windowsMenu = winMenu
        
        // 7. Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        
        let helpAboutItem = NSMenuItem(title: "About MacAmp", action: #selector(PlayerCoordinator.handleAbout), keyEquivalent: "")
        helpAboutItem.target = coord
        helpMenu.addItem(helpAboutItem)
        
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu
        
        NSApp.mainMenu = mainMenu
        updateStates()
    }
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        updateStates()
    }
    
    public func updateStates() {
        let coord = PlayerCoordinator.shared
        alwaysOnTopItem?.state = coord.persistence.state.isAlwaysOnTop ? .on : .off
        doubleSizeItem?.state = (WindowLayoutManager.shared.currentScale == 2.0) ? .on : .off
        eqToggleItem?.state = coord.mainView?.eqToggle.isOn == true ? .on : .off
        plToggleItem?.state = coord.mainView?.plToggle.isOn == true ? .on : .off
        repeatItem?.state = coord.playlist.isRepeat ? .on : .off
        shuffleItem?.state = coord.playlist.isShuffle ? .on : .off
        stopAfterCurrentItem?.state = coord.stopAfterCurrent ? .on : .off
        manualAdvanceItem?.state = coord.persistence.state.manualPlaylistAdvance ? .on : .off
        
        // Rebuild dynamic skins menu
        if let skinsMenu = skinsSubmenu {
            skinsMenu.removeAllItems()
            
            let baseSkinItem = NSMenuItem(title: "Winamp Classic (Default)", action: #selector(PlayerCoordinator.handleResetBaseSkin), keyEquivalent: "")
            baseSkinItem.target = coord
            baseSkinItem.state = SkinManager.shared.isBaseSkinActive ? .on : .off
            skinsMenu.addItem(baseSkinItem)
            
            let installedSkins = SkinManager.shared.installedSkins()
            if !installedSkins.isEmpty {
                skinsMenu.addItem(NSMenuItem.separator())
                for skinURL in installedSkins {
                    let name = skinURL.deletingPathExtension().lastPathComponent
                    let item = NSMenuItem(title: name, action: #selector(PlayerCoordinator.handleSkinSelected(_:)), keyEquivalent: "")
                    item.target = coord
                    item.representedObject = skinURL
                    let isActive = (!SkinManager.shared.isBaseSkinActive && (SkinManager.shared.currentSkinURL?.path == skinURL.path || SkinManager.shared.currentSkin?.name == name))
                    item.state = isActive ? .on : .off
                    skinsMenu.addItem(item)
                }
            }
            
            skinsMenu.addItem(NSMenuItem.separator())
            let loadSkinItem = NSMenuItem(title: "Load Skin...", action: #selector(PlayerCoordinator.handleLoadSkin), keyEquivalent: "")
            loadSkinItem.target = coord
            skinsMenu.addItem(loadSkinItem)
            
            let openFolderItem = NSMenuItem(title: "Open Skins Folder", action: #selector(PlayerCoordinator.handleOpenSkinsFolder), keyEquivalent: "")
            openFolderItem.target = coord
            skinsMenu.addItem(openFolderItem)
        }
        
        // Rebuild dynamic audio output menu
        if let outMenu = audioOutputSubmenu {
            outMenu.removeAllItems()
            
            let defaultName = AudioDeviceManager.shared.defaultDevice?.name ?? "System Output"
            let isDefaultActive = (AudioDeviceManager.shared.selectedDeviceUID == nil)
            
            let defItem = NSMenuItem(
                title: "System Default (\(defaultName))",
                action: #selector(PlayerCoordinator.handleSelectDefaultAudioOutput),
                keyEquivalent: ""
            )
            defItem.target = coord
            defItem.state = isDefaultActive ? .on : .off
            outMenu.addItem(defItem)
            
            let devices = AudioDeviceManager.shared.availableDevices
            if !devices.isEmpty {
                outMenu.addItem(NSMenuItem.separator())
                for dev in devices {
                    let isSelected = (AudioDeviceManager.shared.selectedDeviceUID == dev.uid)
                    let item = NSMenuItem(
                        title: dev.displayName,
                        action: #selector(PlayerCoordinator.handleAudioOutputDeviceSelected(_:)),
                        keyEquivalent: ""
                    )
                    item.target = coord
                    item.representedObject = dev.uid
                    item.state = isSelected ? .on : .off
                    outMenu.addItem(item)
                }
            }
            
            outMenu.addItem(NSMenuItem.separator())
            let prefItem = NSMenuItem(
                title: "Audio Preferences...",
                action: #selector(PlayerCoordinator.handleOpenAudioPreferences),
                keyEquivalent: ""
            )
            prefItem.target = coord
            outMenu.addItem(prefItem)
        }
    }
}
