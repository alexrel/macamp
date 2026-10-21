import Cocoa

/// Manages the macOS Menu Bar Status Item (Tray Icon) with authentic Winamp lightning bolt,
/// current track status, quick playback controls, and window toggles.
@MainActor
public final class StatusBarManager: NSObject, NSMenuDelegate {
    public static let shared = StatusBarManager()
    
    private var statusItem: NSStatusItem?
    private var titleItem: NSMenuItem?
    private var playPauseItem: NSMenuItem?
    
    private override init() {
        super.init()
    }
    
    /// Preferences ▸ Setup ▸ "Show MacAmp in the menu bar"
    public func setVisible(_ visible: Bool) {
        if visible {
            setup()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    public func setup() {
        guard statusItem == nil else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item
        
        if let button = item.button {
            if let image = NSImage(named: "TRAY_ICON") {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else if let appIcon = NSApp.applicationIconImage {
                appIcon.size = NSSize(width: 18, height: 18)
                button.image = appIcon
            }
            button.toolTip = "MacAmp 2.91"
        }
        
        item.menu = buildMenu()
        updateStatus()
    }
    
    public func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "MacAmp Status Menu")
        menu.delegate = self
        
        // 1. Current track title header
        let trackTitle = NSMenuItem(title: "MacAmp 2.91", action: nil, keyEquivalent: "")
        trackTitle.isEnabled = false
        self.titleItem = trackTitle
        menu.addItem(trackTitle)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Play / Pause
        let ppItem = NSMenuItem(title: "Play", action: #selector(handlePlayPause), keyEquivalent: "")
        ppItem.target = self
        self.playPauseItem = ppItem
        menu.addItem(ppItem)
        
        // 3. Stop
        let stopItem = NSMenuItem(title: "Stop", action: #selector(handleStop), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)
        
        // 4. Previous / Next
        let prevItem = NSMenuItem(title: "Previous Track", action: #selector(handlePrev), keyEquivalent: "")
        prevItem.target = self
        menu.addItem(prevItem)
        
        let nextItem = NSMenuItem(title: "Next Track", action: #selector(handleNext), keyEquivalent: "")
        nextItem.target = self
        menu.addItem(nextItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Show/Hide Windows
        let toggleWinItem = NSMenuItem(title: "Bring Winamp to Front", action: #selector(handleToggleWindows), keyEquivalent: "")
        toggleWinItem.target = self
        menu.addItem(toggleWinItem)
        
        // 6. Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(handlePreferences), keyEquivalent: "p")
        prefsItem.keyEquivalentModifierMask = [.control]
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        // 7. About
        let aboutItem = NSMenuItem(title: "About Winamp...", action: #selector(handleAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 8. Quit
        let quitItem = NSMenuItem(title: "Quit MacAmp", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatus()
    }
    
    public func updateStatus() {
        let coord = PlayerCoordinator.shared
        let isPlaying = (coord.audioEngine.status == .playing)
        
        if let track = coord.playlist.currentTrack {
            let name = track.displayName
            let prefix = isPlaying ? "▶ " : "❚❚ "
            let displayName = name.isEmpty ? track.url.lastPathComponent : name
            titleItem?.title = prefix + displayName
            statusItem?.button?.toolTip = "MacAmp: " + displayName
        } else {
            titleItem?.title = "MacAmp 2.91 [Stopped]"
            statusItem?.button?.toolTip = "MacAmp 2.91"
        }
        
        playPauseItem?.title = isPlaying ? "Pause" : "Play"
    }
    
    @objc private func handlePlayPause() {
        PlayerCoordinator.shared.handlePlayPause()
        updateStatus()
    }
    
    @objc private func handleStop() {
        PlayerCoordinator.shared.handleStop()
        updateStatus()
    }
    
    @objc private func handlePrev() {
        PlayerCoordinator.shared.handlePrev()
        updateStatus()
    }
    
    @objc private func handleNext() {
        PlayerCoordinator.shared.handleNext()
        updateStatus()
    }
    
    @objc private func handleToggleWindows() {
        PlayerCoordinator.shared.handleBringAllToFront()
    }
    
    @objc private func handlePreferences() {
        PlayerCoordinator.shared.handlePreferences()
    }
    
    @objc private func handleAbout() {
        PlayerCoordinator.shared.handleAbout()
    }
    
    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
