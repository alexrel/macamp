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
    
    /// Display ▸ Show MacAmp in (2.95's taskbar = the Dock): without the Dock icon MacAmp is an accessory app,
    /// which also drops it from ⌘Tab and hides its menu bar menus; the windows' own menus still have everything
    public func setDockIconVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Changing the policy deactivates the app; keep the windows in front
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
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
            button.toolTip = "MacAmp \(AppConstants.App.version)"
        }
        
        item.menu = buildMenu()
        updateStatus()
    }
    
    public func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "MacAmp Status Menu")
        menu.delegate = self
        
        // 1. Current track title header
        let trackTitle = NSMenuItem(title: "MacAmp \(AppConstants.App.version)", action: nil, keyEquivalent: "")
        trackTitle.isEnabled = false
        self.titleItem = trackTitle
        trackTitle.view = titleView
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
        let toggleWinItem = NSMenuItem(title: "Bring MacAmp to Front", action: #selector(handleToggleWindows), keyEquivalent: "")
        toggleWinItem.target = self
        menu.addItem(toggleWinItem)
        
        // 6. Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(handlePreferences), keyEquivalent: "p")
        prefsItem.keyEquivalentModifierMask = [.control]
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        // 7. About
        let aboutItem = NSMenuItem(title: "About MacAmp...", action: #selector(handleAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 8. Quit
        let quitItem = NSMenuItem(title: "Quit MacAmp", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    /// Widest the track title may make the menu (about twice the other items)
    static let titleWidth: CGFloat = 300

    /// Cuts `text` with "…" so it fits `width` in the menu font.
    static func truncated(_ text: String, toWidth width: CGFloat) -> String {
        let font = [NSAttributedString.Key.font: NSFont.menuFont(ofSize: 0)]
        guard (text as NSString).size(withAttributes: font).width > width else { return text }
        var cut = text
        while !cut.isEmpty && ((cut + "…") as NSString).size(withAttributes: font).width > width {
            cut.removeLast()
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }
    
    /// Mark in front of the track title in the menu bar and Dock menus
    static func stateMark(playing: Bool) -> String { playing ? "▶ " : "❚❚ " }

    private let titleView = MenuTitleView()
    private var scrollTimer: Timer?
    var isTitleScrolling: Bool { scrollTimer != nil }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        updateStatus()
    }

    /// The title scrolls only while the menu is on screen, and only when it doesn't fit
    public func menuWillOpen(_ menu: NSMenu) {
        titleView.offset = 0
        guard titleView.scrolls else { return }
        let timer = Timer(timeInterval: AppConstants.Marquee.scrollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.titleView.offset += MenuTitleView.step }
        }
        RunLoop.main.add(timer, forMode: .common) // menus track the mouse in their own run loop mode
        scrollTimer = timer
    }

    public func menuDidClose(_ menu: NSMenu) {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    public func updateStatus() {
        let coord = PlayerCoordinator.shared
        let isPlaying = (coord.audioEngine.status == .playing)
        
        if let track = coord.playlist.currentTrack {
            let name = track.displayName
            let prefix = StatusBarManager.stateMark(playing: isPlaying)
            let displayName = name.isEmpty ? track.url.lastPathComponent : name
            // A long name would stretch the whole menu: it scrolls instead, and the tooltip has it in full
            titleItem?.title = prefix + displayName
            titleView.show(prefix: prefix, name: displayName)
            titleView.toolTip = displayName
            statusItem?.button?.toolTip = "MacAmp: " + displayName
        } else {
            titleItem?.title = "MacAmp \(AppConstants.App.version) [Stopped]"
            titleView.show(prefix: "", name: "MacAmp \(AppConstants.App.version) [Stopped]")
            titleView.toolTip = nil
            statusItem?.button?.toolTip = "MacAmp \(AppConstants.App.version)"
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

/// The menu's first line, drawn like a disabled menu item. A name wider than `StatusBarManager.titleWidth` scrolls
/// right to left as in the main window ("name  ***  name"); the play / pause mark stays in place.
final class MenuTitleView: NSView {
    // shortcut: the text inset of a system menu item is not public, 14 pt matches macOS 14-15; measure again if a new macOS moves it
    static let inset: CGFloat = 14
    static let height: CGFloat = 22
    /// Pixels per tick, as the main window's song title moves
    static let step: CGFloat = 2
    /// Between the end of the name and its next round
    static let separator = "  ***  "
    private static let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.disabledControlTextColor]
    private var prefix = "", name = ""
    private var prefixWidth: CGFloat = 0, nameWidth: CGFloat = 0
    private(set) var scrolls = false
    var offset: CGFloat = 0 { didSet { needsDisplay = true } }

    func show(prefix: String, name: String) {
        guard prefix != self.prefix || name != self.name else { return }
        if name != self.name { offset = 0 }
        self.prefix = prefix
        self.name = name
        prefixWidth = (prefix as NSString).size(withAttributes: Self.attributes).width
        nameWidth = (name as NSString).size(withAttributes: Self.attributes).width
        scrolls = prefixWidth + nameWidth > StatusBarManager.titleWidth
        setFrameSize(NSSize(width: min(ceil(prefixWidth + nameWidth), StatusBarManager.titleWidth) + 2 * Self.inset, height: Self.height))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let y = (bounds.height - NSFont.menuFont(ofSize: 0).boundingRectForFont.height) / 2
        (prefix as NSString).draw(at: NSPoint(x: Self.inset, y: y), withAttributes: Self.attributes)
        let left = Self.inset + prefixWidth
        guard scrolls else { return (name as NSString).draw(at: NSPoint(x: left, y: y), withAttributes: Self.attributes) }
        NSRect(x: left, y: 0, width: bounds.width - Self.inset - left, height: bounds.height).clip()
        let loop = (name + Self.separator) as NSString
        let loopWidth = loop.size(withAttributes: Self.attributes).width
        let x = left - offset.truncatingRemainder(dividingBy: loopWidth)
        loop.draw(at: NSPoint(x: x, y: y), withAttributes: Self.attributes)
        loop.draw(at: NSPoint(x: x + loopWidth, y: y), withAttributes: Self.attributes)
    }
}
