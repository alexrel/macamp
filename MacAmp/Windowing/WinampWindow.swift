import Cocoa
import Foundation
import SwiftUI

extension NSWindow {
    func updateContentScale(_ scale: CGFloat, logicalSize: NSSize? = nil) {
        guard let view = contentView else { return }
        view.bounds.size = logicalSize ?? NSSize(width: (view.frame.width / scale).rounded(), height: (view.frame.height / scale).rounded())
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.setNeedsDisplayRecursively()
    }

    func installScaledDialog<Content: View>(_ content: Content, size: NSSize? = nil) {
        let scaled = ScaledHostingContent(content, size: size) // no size: the content's own fitting size
        if scaled.logicalSize.width <= 0 || scaled.logicalSize.height <= 0 { scaled.logicalSize = contentRect(forFrameRect: frame).size }
        scaled.frame.size = scaled.logicalSize
        contentView = scaled
        updateDialogScale(PersistenceManager.shared.state.interfaceScale.multiplier)
    }

    func updateDialogScale(_ requestedScale: CGFloat) {
        guard let content = contentView as? ScaledHostingContent else { return }
        let size = styleMask.contains(.resizable)
            ? NSSize(width: content.bounds.width / content.zoom.value, height: content.bounds.height / content.zoom.value)
            : content.logicalSize
        let visible = (screen ?? NSScreen.main)?.visibleFrame
        let chromeHeight = frame.height - content.frame.height
        let scale = visible.map { min(requestedScale, $0.width / size.width, ($0.height - chromeHeight) / size.height) }
            ?? requestedScale
        guard scale > 0 else { return }
        var rect = frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: size.width * scale, height: size.height * scale)))
        rect.origin = NSPoint(x: frame.minX, y: frame.maxY - rect.height)
        if let visible {
            rect.origin.x = min(max(rect.minX, visible.minX), visible.maxX - rect.width)
            rect.origin.y = min(max(rect.minY, visible.minY), visible.maxY - rect.height)
        }
        setFrame(rect, display: true)
        content.zoom.value = scale
    }
}

final class ScaledHostingContent: NSView {
    fileprivate(set) var logicalSize: NSSize
    fileprivate let zoom: HostingZoom
    private let hosting: NSView
    private let insideScaledFrame: Bool

    init<Content: View>(_ content: Content, size: NSSize? = .zero, insideScaledFrame: Bool = false) {
        self.insideScaledFrame = insideScaledFrame
        let zoom = HostingZoom()
        self.zoom = zoom
        let hosting = CrispHostingView(rootView: ScaledContent(content: content, zoom: zoom))
        hosting.zoom = { [unowned zoom] in zoom.value }
        self.hosting = hosting
        logicalSize = size ?? hosting.fittingSize
        super.init(frame: NSRect(origin: .zero, size: logicalSize))
        hosting.sizingOptions = []
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    override func layout() {
        super.layout()
        guard insideScaledFrame else { return }
        // SwiftUI handles input at window scale even though the skin around it uses logical pixels.
        hosting.frame = bounds
        hosting.bounds.size = convert(bounds, to: nil).size
        let scale = PersistenceManager.shared.state.interfaceScale.multiplier
        if zoom.value != scale { zoom.value = scale }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// SwiftUI draws text and controls at the screen's own resolution and scaleEffect stretches the picture: blurred at 150%
/// and 200%, worst on a non-Retina display. Every layer under the hosting view is redrawn at the enlarged resolution instead.
/// shortcut: re-applied after each layout pass, a layer re-created without one stays soft until the next; scale the
/// content's own sizes and fonts instead of the picture if that shows
private final class CrispHostingView<Content: View>: NSHostingView<Content> {
    var zoom: () -> CGFloat = { 1 }
    /// SwiftUI's private layer for drawn text. shortcut: a private name, text simply stays soft if a macOS release renames it
    private static var textLayerClass: String { "CGDrawingLayer" }

    override func layout() {
        super.layout()
        guard let layer, let backing = window?.backingScaleFactor else { return }
        let scale = backing * zoom()
        func sharpen(_ layer: CALayer) {
            // Only what redraws itself on request: SwiftUI's text layers and AppKit controls. An Image or a Canvas is
            // handed its picture once and went blank when asked (the About banner, the Preferences tree's branches).
            let redraws = String(describing: type(of: layer)) == CrispHostingView.textLayerClass
                || layer.delegate is NSControl || layer.delegate is NSText
            if redraws, layer.contents != nil, layer.contentsScale != scale {
                layer.contentsScale = scale
                layer.setNeedsDisplay()
            }
            layer.sublayers?.forEach(sharpen)
        }
        layer.sublayers?.forEach(sharpen)
    }

    /// Another screen: AppKit puts the layers back to that screen's resolution
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }
}

fileprivate final class HostingZoom: ObservableObject {
    @Published var value: CGFloat = 1
}

private struct ScaledContent<Content: View>: View {
    let content: Content
    @ObservedObject var zoom: HostingZoom

    var body: some View {
        ZoomLayout(zoom: zoom.value) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(zoom.value, anchor: .topLeading)
        }
    }
}

/// Lays the content out in the container's size divided by `zoom` (scaleEffect then fills the container). Unlike a
/// GeometryReader it reports the content's own size, so a dialog is measured through the view that will show it.
private struct ZoomLayout: Layout {
    let zoom: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width.map { $0 / zoom }, height: proposal.height.map { $0 / zoom }))
        return CGSize(width: size.width * zoom, height: size.height * zoom)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width / zoom, height: bounds.height / zoom))
    }
}

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
