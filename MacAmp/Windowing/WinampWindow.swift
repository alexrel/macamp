import Cocoa
import Foundation

public class WinampWindow: NSWindow {
    public let windowID: WindowID
    
    public init(windowID: WindowID, contentRect: NSRect) {
        self.windowID = windowID
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovable = false // We handle movement via custom magnetic drag
        self.isReleasedWhenClosed = false
        
        WindowLayoutManager.shared.register(window: self, for: windowID)
    }
    
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    
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
}
