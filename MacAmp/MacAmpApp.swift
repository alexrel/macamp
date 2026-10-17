import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PlayerCoordinator.shared.start()
        NSApp.activate(ignoringOtherApps: true)
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
}

@main
struct MacAmpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    PlayerCoordinator.shared.showPreferencesWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            
            CommandMenu("Track") {
                Button("Track Info (Alt+3)") {
                    PlayerCoordinator.shared.showTrackInfoWindow()
                }
                .keyboardShortcut("3", modifiers: [.option])
            }
            
            CommandMenu("Options") {
                Button("Preferences (Ctrl+P)") {
                    PlayerCoordinator.shared.showPreferencesWindow()
                }
                .keyboardShortcut("p", modifiers: [.control])
                
                Button("Double Size (Ctrl+D)") {
                    PlayerCoordinator.shared.toggleDoubleSize()
                }
                .keyboardShortcut("d", modifiers: [.control])
                
                Button("Skins...") {
                    PlayerCoordinator.shared.openSkinChooser()
                }
                .keyboardShortcut("s", modifiers: [.option])
            }
        }
    }
}
