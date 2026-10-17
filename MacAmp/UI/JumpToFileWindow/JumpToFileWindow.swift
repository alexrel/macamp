import Cocoa
import SwiftUI

public class JumpToFileWindow: NSWindow {
    public static var sharedController: JumpToFileWindowController?
    public weak var keyDelegate: JumpToFileKeyDelegate?
    
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == AppConstants.KeyCodes.escape {
                self.close()
                return
            }
            if event.keyCode == AppConstants.KeyCodes.upArrow {
                keyDelegate?.moveSelectionUp()
                return
            }
            if event.keyCode == AppConstants.KeyCodes.downArrow {
                keyDelegate?.moveSelectionDown()
                return
            }
            if event.keyCode == AppConstants.KeyCodes.returnKey {
                if event.modifierFlags.contains(.shift) {
                    keyDelegate?.performEnqueue()
                } else {
                    keyDelegate?.performJump()
                }
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
        
        let controller = JumpToFileWindowController()
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

public class JumpToFileWindowController: NSWindowController, NSWindowDelegate {
    private var viewModel: JumpToFileViewModel
    
    public init() {
        let vm = JumpToFileViewModel()
        self.viewModel = vm
        
        let window = JumpToFileWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jump to file"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 260)
        window.center()
        
        // Ensure Jump to File window stays on top of player windows
        let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
        window.level = (playerLevel == .floating) ? .modalPanel : .floating
        window.hidesOnDeactivate = false
        window.keyDelegate = vm
        
        super.init(window: window)
        window.delegate = self
        
        vm.onClose = { [weak self] in
            self?.close()
        }
        
        let hostingView = NSHostingView(rootView: JumpToFileView(viewModel: vm, onClose: { [weak self] in
            self?.close()
        }))
        window.contentView = hostingView
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func windowWillClose(_ notification: Notification) {
        JumpToFileWindow.sharedController = nil
    }
}
