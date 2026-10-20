import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuManager.shared.setupMenu()
        StatusBarManager.shared.setup()
        MediaKeyController.shared.setup()
        GlobalHotkeysController.shared.setup()
        PlayerCoordinator.shared.start()
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
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for file in filenames {
            let url = URL(fileURLWithPath: file)
            let ext = url.pathExtension.lowercased()
            if ext == "wsz" || ext == "zip" {
                if let installed = SkinManager.shared.installSkin(from: url) {
                    PersistenceManager.shared.state.activeSkinPath = installed.path
                    PersistenceManager.shared.saveSession()
                }
            } else if ext == "m3u" || ext == "pls" {
                let tracks = PlaylistIO.loadPlaylist(from: url)
                PlayerCoordinator.shared.playlist.add(tracks: tracks)
            } else {
                let track = TrackItem.create(from: url)
                PlayerCoordinator.shared.playlist.add(track: track)
            }
        }
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
