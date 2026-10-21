import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuManager.shared.setupMenu()
        StatusBarManager.shared.setVisible(PersistenceManager.shared.state.showMenuBarIcon)
        MediaKeyController.shared.setup()
        GlobalHotkeysController.shared.setup()
        PlayerCoordinator.shared.start()
        // Finder ▸ Services ▸ "Play in MacAmp" / "Enqueue in MacAmp"
        NSApp.servicesProvider = FinderServicesProvider.shared
        NSUpdateDynamicServices()
        Task { @MainActor in
            await FileAssociationManager.shared.reapplyOnLaunchIfNeeded()
            // A rebuild restores the default document icons; put the chosen ones back
            await DocumentIconManager.shared.reapplyOnLaunchIfNeeded()
        }
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.async {
            MainMenuManager.shared.setupMenu()
            StatusBarManager.shared.updateStatus()
        }
    }
    
    @objc func openPreferences(_ sender: Any?) {
        PlayerCoordinator.shared.showPreferencesWindow()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        PlayerCoordinator.shared.saveState()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let main = PlayerCoordinator.shared.mainWindow, main.isMiniaturized {
            PlayerCoordinator.shared.isDeminiaturizing = true
            main.deminiaturize(nil)
        } else {
            PlayerCoordinator.shared.bringAllWindowsToFront()
        }
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        if let main = PlayerCoordinator.shared.mainWindow, !main.isMiniaturized, !PlayerCoordinator.shared.isDeminiaturizing {
            PlayerCoordinator.shared.bringAllWindowsToFront()
        }
    }
    
    /// Files opened from Finder (double-click, Open With, dropped on the Dock icon).
    /// Must be the URL-based variant: with the SwiftUI App lifecycle, AppKit delivers opened files through
    /// `application(_:open:)`, which SwiftUI forwards to this delegate; `application(_:openFiles:)` is never called.
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL).map(\.path)
        guard !files.isEmpty else { return }
        // Play (or enqueue, per Preferences ▸ Setup ▸ File types)
        PlayerCoordinator.shared.openFromFinder(files)
    }
    
    // MARK: - macOS Dock Menu
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Dock Menu")
        let coord = PlayerCoordinator.shared
        let isPlaying = (coord.audioEngine.status == .playing)
        
        // Track Title Header
        let titleItem: NSMenuItem
        if let track = coord.playlist.currentTrack {
            let name = track.displayName
            let prefix = isPlaying ? "▶ " : "❚❚ "
            let displayName = name.isEmpty ? track.url.lastPathComponent : name
            titleItem = NSMenuItem(title: prefix + displayName, action: nil, keyEquivalent: "")
        } else {
            titleItem = NSMenuItem(title: "MacAmp 2.91 [Stopped]", action: nil, keyEquivalent: "")
        }
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // Play / Pause
        let ppItem = NSMenuItem(title: isPlaying ? "Pause" : "Play", action: #selector(handleDockPlayPause), keyEquivalent: "")
        ppItem.target = self
        menu.addItem(ppItem)
        
        // Stop
        let stopItem = NSMenuItem(title: "Stop", action: #selector(handleDockStop), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)
        
        // Next
        let nextItem = NSMenuItem(title: "Next Track", action: #selector(handleDockNext), keyEquivalent: "")
        nextItem.target = self
        menu.addItem(nextItem)
        
        // Previous
        let prevItem = NSMenuItem(title: "Previous Track", action: #selector(handleDockPrev), keyEquivalent: "")
        prevItem.target = self
        menu.addItem(prevItem)
        
        return menu
    }
    
    @objc private func handleDockPlayPause() {
        PlayerCoordinator.shared.handlePlayPause()
    }
    
    @objc private func handleDockStop() {
        PlayerCoordinator.shared.handleStop()
    }
    
    @objc private func handleDockNext() {
        PlayerCoordinator.shared.handleNext()
    }
    
    @objc private func handleDockPrev() {
        PlayerCoordinator.shared.handlePrev()
    }
}

@main
struct MacAmpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Handles the NSServices declared in Info.plist (Winamp's "Play in Winamp" / "Enqueue in Winamp").
final class FinderServicesProvider: NSObject {
    static let shared = FinderServicesProvider()

    @objc func playFiles(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        open(pboard, enqueue: false)
    }

    @objc func enqueueFiles(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        open(pboard, enqueue: true)
    }

    private func open(_ pboard: NSPasteboard, enqueue: Bool) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        PlayerCoordinator.shared.openFromFinder(urls.map(\.path), enqueue: enqueue)
    }
}
