import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PlayerCoordinator.shared.start()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        PlayerCoordinator.shared.saveState()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        for (_, window) in WindowLayoutManager.shared.windows {
            window.deminiaturize(nil)
            window.orderFront(nil)
        }
        return true
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for file in filenames {
            let url = URL(fileURLWithPath: file)
            let ext = url.pathExtension.lowercased()
            if ext == "wsz" || ext == "zip" {
                SkinManager.shared.loadSkin(from: url)
            } else if ext == "m3u" || ext == "pls" {
                let tracks = PlaylistIO.loadPlaylist(from: url)
                PlayerCoordinator.shared.playlist.add(tracks: tracks)
            } else {
                let track = TrackItem(url: url, title: url.deletingPathExtension().lastPathComponent)
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
    }
}
