import Foundation
import CoreGraphics
import AppKit

// MARK: - CGContext Skin Image Drawing & Tiling Extensions
extension CGContext {
    /// Draws a CGImage right-side-up in an isFlipped AppKit NSView.
    ///
    /// Winamp skins are loaded top-to-bottom. Since WinampControlView sets isFlipped = true,
    /// standard CoreGraphics draw(image:) would render images inverted.
    /// This method applies a vertical flip around the target rect to draw pixel-perfect bitmaps right-side-up.
    @inlinable
    public func drawSkinImage(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1.0, y: -1.0)
        draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        restoreGState()
    }
    
    /// Draws a skin slice tiled horizontally across a given range [startX ..< endX] with a fixed tile width.
    /// Used for top and bottom playlist filler sections, windowshade bars, etc.
    public func drawTiledHorizontal(image: CGImage, from startX: CGFloat, to endX: CGFloat, y: CGFloat, width tileWidth: CGFloat, height: CGFloat) {
        var x = startX
        while x < endX {
            let w = min(tileWidth, endX - x)
            drawSkinImage(image, in: NSRect(x: x, y: y, width: w, height: height))
            x += tileWidth
        }
    }
    
    /// Draws a skin slice tiled vertically down a given range [startY ..< endY] with a fixed tile height.
    /// Used for playlist left and right decorative border tiles.
    public func drawTiledVertical(image: CGImage, x: CGFloat, from startY: CGFloat, to endY: CGFloat, width: CGFloat, height tileHeight: CGFloat) {
        var y = startY
        while y < endY {
            let h = min(tileHeight, endY - y)
            drawSkinImage(image, in: NSRect(x: x, y: y, width: width, height: h))
            y += tileHeight
        }
    }
}

// MARK: - NSView Recursive Display Invalidation Extension
extension NSView {
    /// Recursively marks this view and all descendant subviews as needing display.
    /// Essential when changing skins to ensure buttons, sliders, and toggles redraw immediately.
    public func setNeedsDisplayRecursively() {
        self.needsDisplay = true
        self.layer?.setNeedsDisplay()
        for sub in subviews {
            sub.setNeedsDisplayRecursively()
        }
    }
}

// MARK: - Winamp Base Control View
/// Base NSView for all Winamp UI components.
/// - Sets `isFlipped = true` for classic top-to-bottom pixel coordinate system (0,0 is top-left).
/// - Enforces `.nearest` interpolation filter on CALayer for crisp, unblurred pixel art rendering.
/// - Routes right-clicks to main Winamp context menu.
/// - Provides unified modal mouse dragging for window dragging.
open class WinampControlView: NSView {
    open override var isFlipped: Bool { true }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }
    
    private func configureLayer() {
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.layer?.magnificationFilter = .nearest
        self.layer?.minificationFilter = .nearest
        self.layer?.isOpaque = false
    }
    
    /// Winamp 2.95 gives some controls their own right-click menu (transport buttons, seek bar, time, title...)
    public var contextMenuProvider: (() -> NSMenu)?
    
    open override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            PlayerCoordinator.shared.showMainContextMenu(at: NSEvent.mouseLocation)
        }
    }
    
    /// Title bars use their inactive sprites when the window isn't key, unless
    /// Preferences ▸ Display ▸ "Dim titlebars when inactive" is off.
    public var drawsActiveTitleBar: Bool {
        !PersistenceManager.shared.state.dimTitlebars || (NSApp.isActive && (window?.isKeyWindow ?? false))
    }
    
    // MARK: Skin cursors
    
    /// Skin cursor (CUR file stem, e.g. "CLOSE") shown over this whole control. Ignored if the skin has none.
    public var skinCursorName: String? {
        didSet { if oldValue != skinCursorName { refreshSkinCursor() } }
    }
    
    /// Additional cursor zones inside this view (used by window backgrounds for title bars, resize grips...).
    open func skinCursorZones() -> [(rect: NSRect, name: String)] { [] }
    
    /// The window's root view tracks the mouse for all its controls. Cursor rects would only work in the
    /// key window of the active app; Winamp shows skin cursors over every window, active or not.
    private lazy var cursorTracker = SkinCursorTracker(view: self)
    private var cursorTrackingArea: NSTrackingArea?
    
    open override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        cursorTrackingArea = nil
        guard !(superview is WinampControlView) else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: cursorTracker, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area
    }
    
    /// Cursor for a point in window coordinates: the deepest control's zone or own cursor wins, like nested cursor rects.
    public func skinCursor(atWindowPoint point: NSPoint) -> NSCursor? {
        // Preferences ▸ Display ▸ "Use Winamp-styled (skinned) cursors"
        guard PersistenceManager.shared.state.useSkinnedCursors else { return nil }
        let cursors = SkinManager.shared.currentSkin?.cursors ?? [:]
        var view = hitTest(superview?.convert(point, from: nil) ?? point)
        while let current = view {
            if let control = current as? WinampControlView {
                let local = control.convert(point, from: nil)
                if let zone = control.skinCursorZones().last(where: { $0.rect.contains(local) }), let cursor = cursors[zone.name] {
                    return cursor
                }
                if let name = control.skinCursorName, let cursor = cursors[name] {
                    return cursor
                }
            }
            if current === self { break }
            view = current.superview
        }
        return nil
    }
    
    fileprivate func updateSkinCursor(atWindowPoint point: NSPoint) {
        (skinCursor(atWindowPoint: point) ?? .arrow).set()
    }
    
    /// Re-applies the cursor under the mouse (after skin, mode or layout changes).
    private func refreshSkinCursor() {
        var root: NSView = self
        while let parent = root.superview as? WinampControlView { root = parent }
        guard let rootControl = root as? WinampControlView, let window = rootControl.window,
              rootControl.bounds.contains(rootControl.convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return }
        rootControl.updateSkinCursor(atWindowPoint: window.mouseLocationOutsideOfEventStream)
    }
    
    /// Re-applies the cursor for this view and its subviews (after skin or layout changes).
    public func invalidateSkinCursorsRecursively() {
        refreshSkinCursor()
    }
    
    open override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    /// Reusable modal window drag tracking loop.
    /// Used by MainWindow, EqualizerWindow, and PlaylistWindow to handle magnetic window docking and moving.
    public func trackWindowDrag(with initialEvent: NSEvent, in win: WinampWindow) {
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            switch nextEvent.type {
            case .leftMouseDragged:
                win.continueWindowDrag(with: nextEvent)
            case .leftMouseUp:
                keepTracking = false
                win.endWindowDrag(with: nextEvent)
            default:
                break
            }
        }
    }
}

// MARK: - SkinButton
/// Push button supporting normal and pressed bitmap sprite slices.
/// When `isShadeButton` is true (in shade mode), the icon is already pre-baked into TITLEBAR.BMP background,
/// so it renders a semi-transparent press highlight on click instead of drawing over the icon.
public class SkinButton: WinampControlView {
    public var normalSlice: SpriteSlice?
    public var pressedSlice: SpriteSlice?
    public var action: (() -> Void)?
    
    public private(set) var isPressed = false {
        didSet {
            if oldValue != isPressed {
                needsDisplay = true
            }
        }
    }
    
    public var isShadeButton: Bool = false {
        didSet { needsDisplay = true }
    }
    
    public init(normal: SpriteSlice? = nil, pressed: SpriteSlice? = nil, action: (() -> Void)? = nil) {
        self.normalSlice = normal
        self.pressedSlice = pressed
        self.action = action
        let w = normal?.rect.width ?? pressed?.rect.width ?? 0
        let h = normal?.rect.height ?? pressed?.rect.height ?? 0
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        if isShadeButton {
            // In shade mode and playlist bottom bar, icons are already pre-drawn in the skin background bitmap.
            // Authentic Winamp 2.x does not draw any translucent overlay rectangle on click.
            return
        }
        
        let slice = isPressed ? (pressedSlice ?? normalSlice) : normalSlice
        if let s = slice, let image = SkinManager.shared.image(for: s) {
            context.drawSkinImage(image, in: bounds)
        }
    }
    
    /// Set: the action runs on press and the drag that follows goes here (playlist menus: press, drag to an item, release)
    public var dragAfterPress: ((NSEvent) -> Void)?

    public override func mouseDown(with event: NSEvent) {
        isPressed = true
        guard let dragAfterPress, let window else { return trackMouse(with: event) }
        action?()
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            dragAfterPress(next)
            if next.type == .leftMouseUp { break }
        }
        isPressed = false
    }
    
    private func trackMouse(with initialEvent: NSEvent) {
        guard let window = self.window else { return }
        
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            
            let localPoint = convert(nextEvent.locationInWindow, from: nil)
            let isInside = bounds.contains(localPoint)
            
            switch nextEvent.type {
            case .leftMouseDragged:
                self.isPressed = isInside
            case .leftMouseUp:
                keepTracking = false
                self.isPressed = false
                if isInside {
                    action?()
                }
            default:
                break
            }
        }
    }
}

// MARK: - ClutterButton
/// Special button for the ClutterBar strip (O, A, I, D, V) located left of the visualizer.
/// In classic Winamp, only O (Options menu) and D (Double size toggle) are active.
/// When unselected, the background is drawn by the ClutterBar strip;
/// when active/selected/pressed, the active sprite slice is overlaid.
public class ClutterButton: WinampControlView {
    public var activeSlice: SpriteSlice
    public var isSelected: Bool = false {
        didSet {
            if oldValue != isSelected {
                needsDisplay = true
            }
        }
    }
    public var action: (() -> Void)?
    
    public private(set) var isPressed = false {
        didSet {
            if oldValue != isPressed {
                needsDisplay = true
            }
        }
    }
    
    public init(activeSlice: SpriteSlice, action: (() -> Void)? = nil) {
        self.activeSlice = activeSlice
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: activeSlice.rect.width, height: activeSlice.rect.height))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        if isSelected || isPressed {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.interpolationQuality = .none
            if let img = SkinManager.shared.image(for: activeSlice) {
                context.drawSkinImage(img, in: bounds)
            }
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        isPressed = true
        trackMouse(with: event)
    }
    
    private func trackMouse(with initialEvent: NSEvent) {
        guard let window = self.window else { return }
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            let localPoint = convert(nextEvent.locationInWindow, from: nil)
            let isInside = bounds.contains(localPoint)
            switch nextEvent.type {
            case .leftMouseDragged:
                self.isPressed = isInside
            case .leftMouseUp:
                keepTracking = false
                self.isPressed = false
                if isInside {
                    action?()
                }
            default:
                break
            }
        }
    }
}

// MARK: - SkinToggle
/// Two-state toggle button with separate normal/pressed sprites for both ON and OFF states.
/// Used for EQ on/off, Playlist window toggle, Shuffle, Repeat, and Equalizer ON/AUTO switches.
public class SkinToggle: WinampControlView {
    public var offNormal: SpriteSlice
    public var offPressed: SpriteSlice
    public var onNormal: SpriteSlice
    public var onPressed: SpriteSlice
    
    public var isOn: Bool = false {
        didSet {
            if oldValue != isOn {
                needsDisplay = true
                onChanged?(isOn)
            }
        }
    }
    
    public var onChanged: ((Bool) -> Void)?
    
    private var isTrackingPressed = false {
        didSet {
            if oldValue != isTrackingPressed {
                needsDisplay = true
            }
        }
    }
    
    public init(
        offNormal: SpriteSlice,
        offPressed: SpriteSlice,
        onNormal: SpriteSlice,
        onPressed: SpriteSlice,
        isOn: Bool = false,
        onChanged: ((Bool) -> Void)? = nil
    ) {
        self.offNormal = offNormal
        self.offPressed = offPressed
        self.onNormal = onNormal
        self.onPressed = onPressed
        self.isOn = isOn
        self.onChanged = onChanged
        super.init(frame: NSRect(x: 0, y: 0, width: offNormal.rect.width, height: offNormal.rect.height))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        let slice: SpriteSlice
        if isOn {
            slice = isTrackingPressed ? onPressed : onNormal
        } else {
            slice = isTrackingPressed ? offPressed : offNormal
        }
        
        if let image = SkinManager.shared.image(for: slice) {
            context.drawSkinImage(image, in: bounds)
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        isTrackingPressed = true
        trackMouse(with: event)
    }
    
    private func trackMouse(with initialEvent: NSEvent) {
        guard let window = self.window else { return }
        
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            
            let localPoint = convert(nextEvent.locationInWindow, from: nil)
            let isInside = bounds.contains(localPoint)
            
            switch nextEvent.type {
            case .leftMouseDragged:
                self.isTrackingPressed = isInside
            case .leftMouseUp:
                keepTracking = false
                self.isTrackingPressed = false
                if isInside {
                    self.isOn.toggle()
                }
            default:
                break
            }
        }
    }
}

/// Receives the root view's mouse-tracking events (a separate owner, so views keep their own mouseMoved).
private final class SkinCursorTracker: NSResponder {
    private weak var view: WinampControlView?
    
    init(view: WinampControlView) {
        self.view = view
        super.init()
    }
    
    required init?(coder: NSCoder) { nil }
    
    override func mouseEntered(with event: NSEvent) { view?.updateSkinCursor(atWindowPoint: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { view?.updateSkinCursor(atWindowPoint: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}
