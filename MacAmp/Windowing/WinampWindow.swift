import Cocoa
import Foundation

public class WinampWindow: NSWindow {
    public let windowID: WindowID
    
    public init(windowID: WindowID, contentRect: NSRect) {
        self.windowID = windowID
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovable = false // We handle movement via custom magnetic drag
        self.isReleasedWhenClosed = false
        
        self.registerForDraggedTypes([.fileURL])
        
        WindowLayoutManager.shared.register(window: self, for: windowID)
    }
    
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    
    public override func becomeKey() {
        super.becomeKey()
        PlayerCoordinator.shared.raisePlayerWindows(for: self)
        PlayerCoordinator.shared.updateTitleBarFocus()
    }
    
    public override func resignKey() {
        super.resignKey()
        PlayerCoordinator.shared.updateTitleBarFocus()
    }
    
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if isKeyWindow {
                PlayerCoordinator.shared.raisePlayerWindows(for: self)
            } else {
                makeKey()
            }
        }
        super.sendEvent(event)
    }
    
    // MARK: - Dragging Support
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigins: [WindowID: NSPoint] = [:]
    
    public func startWindowDrag(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigins = WindowLayoutManager.shared.startDrag(for: windowID)
    }
    
    public func continueWindowDrag(with event: NSEvent) {
        let currentMouse = NSEvent.mouseLocation
        let delta = CGPoint(
            x: currentMouse.x - dragStartMouse.x,
            y: currentMouse.y - dragStartMouse.y
        )
        WindowLayoutManager.shared.applyDrag(id: windowID, totalDelta: delta, startOrigins: dragStartOrigins)
    }
    
    public func endWindowDrag(with event: NSEvent) {
        WindowLayoutManager.shared.endDrag(for: windowID)
        dragStartOrigins.removeAll()
    }
    
    // MARK: - Drag & Drop Destination (main and equalizer windows; the playlist view handles its own drops)
    // @objc is required: NSWindow's NSDraggingDestination conformance is inherited, so without it these
    // Swift methods are invisible to AppKit and NSWindow's own (do-nothing) implementation runs instead.
    @objc public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        PlayerCoordinator.droppedFileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }
    
    @objc public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }
    
    @objc public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = PlayerCoordinator.droppedFileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        PlayerCoordinator.shared.handleDroppedFiles(urls.map(\.path))
        return true
    }
    
    // MARK: - Keyboard Shortcuts
    public override func keyDown(with event: NSEvent) {
        if PlayerCoordinator.shared.handleKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}
