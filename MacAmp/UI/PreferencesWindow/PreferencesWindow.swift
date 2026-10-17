import Cocoa
import SwiftUI

public class PreferencesWindow: NSWindow {
    public static var sharedController: PreferencesWindowController?
    
    public static func show(category: PreferencesCategory = .titles) {
        if let existing = sharedController {
            existing.selectCategory(category)
            if let win = existing.window {
                let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
                win.level = (playerLevel == .floating) ? .modalPanel : .floating
                win.makeKeyAndOrderFront(nil)
                win.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let controller = PreferencesWindowController(initialCategory: category)
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

public class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private var viewModel: PreferencesViewModel
    
    public init(initialCategory: PreferencesCategory = .titles) {
        let vm = PreferencesViewModel()
        vm.selectedCategory = initialCategory
        self.viewModel = vm
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Winamp Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        
        // Ensure Preferences window stays above player windows
        let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
        window.level = (playerLevel == .floating) ? .modalPanel : .floating
        window.hidesOnDeactivate = false
        
        super.init(window: window)
        window.delegate = self
        
        let hostingView = NSHostingView(rootView: PreferencesView(viewModel: vm, onClose: { [weak self] in
            self?.close()
        }))
        window.contentView = hostingView
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func selectCategory(_ category: PreferencesCategory) {
        viewModel.selectedCategory = category
        viewModel.refreshSkins()
    }
    
    public func windowWillClose(_ notification: Notification) {
        PreferencesWindow.sharedController = nil
    }
}
