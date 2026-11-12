import Cocoa
import SwiftUI

public class AboutWindow: NSWindow {
    public static var sharedController: AboutWindowController?
    
    public static func show() {
        if let existing = sharedController {
            if let win = existing.window {
                let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
                win.level = (playerLevel == .floating) ? .modalPanel : .floating
                win.makeKeyAndOrderFront(nil)
                win.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let controller = AboutWindowController()
        sharedController = controller
        controller.showWindow(nil)
        if let win = controller.window {
            let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
            win.level = (playerLevel == .floating) ? .modalPanel : .floating
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

public class AboutWindowController: NSWindowController, NSWindowDelegate {
    public init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AboutView.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Winamp"
        window.isReleasedWhenClosed = false
        window.center()
        
        let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
        window.level = (playerLevel == .floating) ? .modalPanel : .floating
        window.hidesOnDeactivate = false
        
        super.init(window: window)
        window.delegate = self
        
        let content = AboutView(onClose: { [weak self] in
            self?.close()
        })
        window.installScaledDialog(content, size: AboutView.size)
        window.center()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func windowWillClose(_ notification: Notification) {
        AboutWindow.sharedController = nil
    }
}
