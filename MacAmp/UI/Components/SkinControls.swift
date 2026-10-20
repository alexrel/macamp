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
    
    open override func rightMouseDown(with event: NSEvent) {
        PlayerCoordinator.shared.showMainContextMenu(at: NSEvent.mouseLocation)
    }
    
    // MARK: Skin cursors
    
    /// Skin cursor (CUR file stem, e.g. "CLOSE") shown over this whole control. Ignored if the skin has none.
    public var skinCursorName: String? {
        didSet { if oldValue != skinCursorName { window?.invalidateCursorRects(for: self) } }
    }
    
    /// Additional cursor zones inside this view (used by window backgrounds for title bars, resize grips...).
    open func skinCursorZones() -> [(rect: NSRect, name: String)] { [] }
    
    open override func resetCursorRects() {
        super.resetCursorRects()
        let cursors = SkinManager.shared.currentSkin?.cursors ?? [:]
        guard !cursors.isEmpty else { return }
        if let name = skinCursorName, let cursor = cursors[name] {
            addCursorRect(bounds, cursor: cursor)
        }
        // Later rects win where they overlap, so zones refine the whole-view cursor
        for zone in skinCursorZones() {
            if let cursor = cursors[zone.name] {
                addCursorRect(zone.rect, cursor: cursor)
            }
        }
    }
    
    /// Re-applies cursor rects for this view and all subviews (after skin or layout changes).
    public func invalidateSkinCursorsRecursively() {
        window?.invalidateCursorRects(for: self)
        for case let sub as WinampControlView in subviews {
            sub.invalidateSkinCursorsRecursively()
        }
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
