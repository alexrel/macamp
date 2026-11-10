import Cocoa
import SwiftUI

public class PreferencesWindow: NSWindow {
    public static var sharedController: PreferencesWindowController?
    
    /// ⌃P / ⌘,: the window as it was, or the Setup page the first time.
    public static func show() {
        show(treeItem: sharedController?.selectedTreeItem ?? .setup)
    }
    
    public static func show(treeItem: PrefTreeItem) {
        if let existing = sharedController {
            existing.selectTreeItem(treeItem)
            if let win = existing.window {
                let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
                win.level = (playerLevel == .floating) ? .modalPanel : .floating
                win.makeKeyAndOrderFront(nil)
                win.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let controller = PreferencesWindowController(initialTreeItem: treeItem)
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
    
    public init(initialTreeItem: PrefTreeItem = .setup) {
        let vm = PreferencesViewModel()
        vm.selectedTreeItem = initialTreeItem
        self.viewModel = vm
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacAmp Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        
        // Ensure Preferences window stays above player windows
        let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
        window.level = (playerLevel == .floating) ? .modalPanel : .floating
        window.hidesOnDeactivate = false
        
        super.init(window: window)
        window.delegate = self
        
        let content = PreferencesView(viewModel: vm, onClose: { [weak self] in
            self?.close()
        })
        window.installScaledDialog(content, size: NSSize(width: 560, height: 440))
        window.center()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var selectedTreeItem: PrefTreeItem { viewModel.selectedTreeItem }
    
    public func selectTreeItem(_ item: PrefTreeItem) {
        viewModel.selectedTreeItem = item
        viewModel.refreshSkins()
    }
    
    public func windowWillClose(_ notification: Notification) {
        PreferencesWindow.sharedController = nil
    }
}
