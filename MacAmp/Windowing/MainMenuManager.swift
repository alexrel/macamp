import Cocoa

public final class MainMenuManager: NSObject, NSMenuDelegate {
    public static let shared = MainMenuManager()
    
    private var optionsMenu: NSMenu?
    private var playbackMenu: NSMenu?
    private var windowMenu: NSMenu?
    private var skinsSubmenu: NSMenu?
    
    private var alwaysOnTopItem: NSMenuItem?
    private var doubleSizeItem: NSMenuItem?
    private var eqToggleItem: NSMenuItem?
    private var plToggleItem: NSMenuItem?
    private var mbToggleItem: NSMenuItem?
    private var repeatItem: NSMenuItem?
    private var shuffleItem: NSMenuItem?
    
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
        
        // 3. Playback Menu
        let pbMenuItem = NSMenuItem()
        let pbMenu = NSMenu(title: "Playback")
        pbMenu.delegate = self
        self.playbackMenu = pbMenu
        
        let prevItem = NSMenuItem(title: "Previous", action: #selector(PlayerCoordinator.handlePrev), keyEquivalent: "z")
        prevItem.target = coord
        pbMenu.addItem(prevItem)
        
        let playItem = NSMenuItem(title: "Play", action: #selector(PlayerCoordinator.handlePlay), keyEquivalent: "x")
        playItem.target = coord
        pbMenu.addItem(playItem)
        
        let pauseItem = NSMenuItem(title: "Pause", action: #selector(PlayerCoordinator.handlePause), keyEquivalent: "c")
        pauseItem.target = coord
        pbMenu.addItem(pauseItem)
        
        let stopItem = NSMenuItem(title: "Stop", action: #selector(PlayerCoordinator.handleStop), keyEquivalent: "v")
        stopItem.target = coord
        pbMenu.addItem(stopItem)
        
        let nextItem = NSMenuItem(title: "Next", action: #selector(PlayerCoordinator.handleNext), keyEquivalent: "b")
        nextItem.target = coord
        pbMenu.addItem(nextItem)
        
        pbMenu.addItem(NSMenuItem.separator())
        
        let repItem = NSMenuItem(title: "Repeat", action: #selector(PlayerCoordinator.handleToggleRepeat), keyEquivalent: "r")
        repItem.target = coord
        pbMenu.addItem(repItem)
        self.repeatItem = repItem
        
        let shufItem = NSMenuItem(title: "Shuffle", action: #selector(PlayerCoordinator.handleToggleShuffle), keyEquivalent: "s")
        shufItem.target = coord
        pbMenu.addItem(shufItem)
        self.shuffleItem = shufItem
        
        pbMenu.addItem(NSMenuItem.separator())
        
        let jumpFileItem = NSMenuItem(title: "Jump to File... (J)", action: #selector(PlayerCoordinator.handleJumpToFile), keyEquivalent: "j")
        jumpFileItem.keyEquivalentModifierMask = []
        jumpFileItem.target = coord
        pbMenu.addItem(jumpFileItem)
        
        let jumpTimeItem = NSMenuItem(title: "Jump to Time... (Ctrl+J)", action: #selector(PlayerCoordinator.handleJumpToTime), keyEquivalent: "j")
        jumpTimeItem.keyEquivalentModifierMask = [.control]
        jumpTimeItem.target = coord
        pbMenu.addItem(jumpTimeItem)
        
        pbMenuItem.submenu = pbMenu
        mainMenu.addItem(pbMenuItem)
        
        // 4. Track Menu
        let trackMenuItem = NSMenuItem()
        let trackMenu = NSMenu(title: "Track")
        
        let trackInfoItem = NSMenuItem(title: "Track Info / ID3 Tag Editor... (Alt+3)", action: #selector(PlayerCoordinator.handleTrackInfo), keyEquivalent: "3")
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
        
        let optsPrefsItem = NSMenuItem(title: "Preferences... (Ctrl+P)", action: #selector(PlayerCoordinator.handlePreferences), keyEquivalent: "p")
        optsPrefsItem.keyEquivalentModifierMask = [.control]
        optsPrefsItem.target = coord
        optsMenu.addItem(optsPrefsItem)
        
        optsMenu.addItem(NSMenuItem.separator())
        
        let skinsItem = NSMenuItem(title: "Skins", action: nil, keyEquivalent: "")
        let skinsSub = NSMenu(title: "Skins")
        skinsItem.submenu = skinsSub
        self.skinsSubmenu = skinsSub
        optsMenu.addItem(skinsItem)
        
        optsMenu.addItem(NSMenuItem.separator())
        
        let aotItem = NSMenuItem(title: "Always On Top", action: #selector(PlayerCoordinator.handleToggleAlwaysOnTop), keyEquivalent: "t")
        aotItem.keyEquivalentModifierMask = [.command]
        aotItem.target = coord
        optsMenu.addItem(aotItem)
        self.alwaysOnTopItem = aotItem
        
        let dblItem = NSMenuItem(title: "Double Size (Ctrl+D)", action: #selector(PlayerCoordinator.handleToggleDoubleSize), keyEquivalent: "d")
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
        
        let mbItem = NSMenuItem(title: "Minibrowser", action: #selector(PlayerCoordinator.handleToggleMinibrowser), keyEquivalent: "t")
        mbItem.keyEquivalentModifierMask = [.option]
        mbItem.target = coord
        winMenu.addItem(mbItem)
        self.mbToggleItem = mbItem
        
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
        mbToggleItem?.state = coord.persistence.state.isMinibrowserVisible ? .on : .off
        repeatItem?.state = coord.playlist.isRepeat ? .on : .off
        shuffleItem?.state = coord.playlist.isShuffle ? .on : .off
        
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
    }
}
