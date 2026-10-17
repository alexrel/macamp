import Cocoa
import SwiftUI

public class JumpToTimeWindow: NSWindow {
    public static var sharedController: JumpToTimeWindowController?
    public weak var actionHandler: JumpToTimeViewModel?
    
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == AppConstants.KeyCodes.escape {
                self.close()
                return
            }
            if event.keyCode == AppConstants.KeyCodes.returnKey {
                actionHandler?.performJump()
                return
            }
        }
        super.sendEvent(event)
    }
    
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
        
        let controller = JumpToTimeWindowController()
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

public class JumpToTimeWindowController: NSWindowController, NSWindowDelegate {
    private var viewModel: JumpToTimeViewModel
    
    public init() {
        let vm = JumpToTimeViewModel()
        self.viewModel = vm
        
        let window = JumpToTimeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 175),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jump to time"
        window.isReleasedWhenClosed = false
        window.center()
        
        // Ensure Jump to Time window stays on top of player windows
        let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
        window.level = (playerLevel == .floating) ? .modalPanel : .floating
        window.hidesOnDeactivate = false
        window.actionHandler = vm
        
        super.init(window: window)
        window.delegate = self
        
        vm.onClose = { [weak self] in
            self?.close()
        }
        
        let hostingView = NSHostingView(rootView: JumpToTimeView(viewModel: vm, onClose: { [weak self] in
            self?.close()
        }))
        window.contentView = hostingView
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func windowWillClose(_ notification: Notification) {
        JumpToTimeWindow.sharedController = nil
    }
}
