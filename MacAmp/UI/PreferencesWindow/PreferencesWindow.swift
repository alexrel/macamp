import Cocoa
import SwiftUI

public class PreferencesWindow: NSWindow {
    public static var sharedController: PreferencesWindowController?

    /// A plug-in's Configure / About window: Preferences waits for it, as a Win32 owner waits for its dialog.
    /// A click or a key on Preferences brings it back instead (one such window at a time, never a pile of them).
    private(set) var pluginDialog: NSWindow?

    override public func sendEvent(_ event: NSEvent) {
        if let dialog = pluginDialog, dialog.isVisible,
           [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown].contains(event.type) {
            NSSound.beep()
            dialog.makeKeyAndOrderFront(nil)
            return
        }
        super.sendEvent(event)
    }

    /// Focus that lands on Preferences some other way (its title bar, ⌘-Tab, the Dock) goes on to the open dialog
    override public func becomeKey() {
        super.becomeKey()
        if let dialog = pluginDialog, dialog.isVisible { DispatchQueue.main.async { dialog.makeKeyAndOrderFront(nil) } }
    }

    /// Opens `content` as the plug-in dialog `title`, centred over Preferences. Preferences stays put while it's open;
    /// the dialog itself can be moved anywhere
    func showPluginDialog<Content: View>(title: String, _ content: Content) {
        pluginDialog?.close()
        let dialog = PluginDialogWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        dialog.title = title
        dialog.isReleasedWhenClosed = false
        dialog.installScaledDialog(content)
        dialog.fitTitle()
        dialog.level = level
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? frame
        let size = dialog.frame.size
        dialog.setFrameOrigin(NSPoint(x: min(max(frame.midX - size.width / 2, visible.minX), visible.maxX - size.width),
                                      y: min(max(frame.midY - size.height / 2, visible.minY), visible.maxY - size.height)))
        addChildWindow(dialog, ordered: .above) // stays above Preferences and hides with it
        isMovable = false // a child follows its parent: Preferences waits, as it does for clicks and keys
        pluginDialog = dialog
        dialog.onClose = { [weak self, weak dialog] in
            guard let self, let dialog, self.pluginDialog === dialog else { return }
            self.removeChildWindow(dialog)
            self.isMovable = true
            self.pluginDialog = nil
            self.makeKeyAndOrderFront(nil)
        }
        dialog.makeKeyAndOrderFront(nil)
    }

    func closePluginDialog() { pluginDialog?.close() }

    
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
        
        let window = PreferencesWindow(
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

    public func configureVisPlugin() { PreferencesView.configureVisPlugin(viewModel: viewModel) }
    
    public func selectTreeItem(_ item: PrefTreeItem) {
        viewModel.selectedTreeItem = item
        viewModel.refreshSkins()
    }
    
    public func windowWillClose(_ notification: Notification) {
        PreferencesWindow.sharedController = nil
    }
}

/// Esc closes it, as Cancel / Close in a Win32 dialog
private final class PluginDialogWindow: NSWindow {
    var onClose: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { close() }
    override func close() {
        super.close()
        onClose?()
        onClose = nil
    }

    /// macOS keeps the place of the hidden minimise and zoom buttons, so a long title was cut short with room to spare:
    /// a title that doesn't fit centred starts right after the close button instead, as on a Win32 caption
    func fitTitle() {
        guard let close = standardWindowButton(.closeButton), let bar = close.superview,
              let zoom = standardWindowButton(.zoomButton) else { return }
        let font = NSFont.titleBarFont(ofSize: 0)
        let width = (title as NSString).size(withAttributes: [.font: font]).width
        guard width / 2 > frame.width / 2 - zoom.frame.maxX - Self.titleGap else { return }
        let label = NSTextField(labelWithString: title)
        label.font = font
        label.textColor = .windowFrameTextColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: close.frame.maxX + Self.titleGap),
            label.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -Self.titleGap),
            label.centerYAnchor.constraint(equalTo: close.centerYAnchor),
        ])
        titleVisibility = .hidden
        titleLabel = label
    }

    private static let titleGap: CGFloat = 8
    private var titleLabel: NSTextField?
    // Dimmed like the system title when the dialog isn't the key window
    override func becomeKey() { super.becomeKey(); titleLabel?.textColor = .windowFrameTextColor }
    override func resignKey() { super.resignKey(); titleLabel?.textColor = .disabledControlTextColor }
}
