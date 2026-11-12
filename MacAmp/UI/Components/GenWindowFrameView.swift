import Cocoa

/// Winamp's general-purpose window frame, drawn from the skin's GEN.BMP: the frame of the Media Library
/// (and later Video / Minibrowser). Title bar with the skin's own letters, close button, side borders,
/// bottom bar with the resize grip. The window's content goes in `contentView`.
public class GenWindowFrameView: WinampControlView {
    /// Frame thickness: title bar, left and right borders, bottom bar
    public static let insets = NSEdgeInsets(top: 20, left: 11, bottom: 14, right: 8)
    /// Winamp resizes these windows in steps of 25 × 29 from a 275 × 116 minimum
    public static let minimumSize = NSSize(width: 275, height: 116)
    public static let resizeStep = NSSize(width: 25, height: 29)

    public var title: String { didSet { needsDisplay = true } }
    public let contentView: NSView
    public var onClose: (() -> Void)?
    public var onResized: ((NSSize) -> Void)?
    var isFrameHidden = false {
        didSet {
            needsLayout = true
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var closePressed = false
    /// Frame thickness of this kind of window (VIDEO.BMP / MB.BMP have a taller bottom bar)
    public var frameInsets: NSEdgeInsets { GenWindowFrameView.insets }

    public init(title: String, content: NSView) {
        self.title = title
        self.contentView = content
        super.init(frame: NSRect(origin: .zero, size: GenWindowFrameView.minimumSize))
        addSubview(content)
        skinCursorName = "NORMAL"
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The corners and side ends move with the size: redraw everything, not just the newly exposed strip
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    public override func layout() {
        super.layout()
        if isFrameHidden {
            contentView.frame = bounds
            return
        }
        let i = frameInsets
        contentView.frame = NSRect(x: i.left, y: i.top, width: max(0, bounds.width - i.left - i.right),
                                   height: max(0, bounds.height - i.top - i.bottom))
        if contentView is ScaledHostingContent { contentView.needsLayout = true }
    }

    // MARK: Sprites (GEN.BMP layout, verified on the base skin)

    private static func gen(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGImage? {
        SkinManager.shared.image(for: SpriteSlice("GEN", "GEN", x, y, w, h))
    }

    /// Title pieces: 0 left corner, 1 left end, 2 center fill, 3 right end, 4 side fill, 5 right corner (with close)
    private func titlePiece(_ index: Int, active: Bool) -> CGImage? {
        GenWindowFrameView.gen(CGFloat(index) * 26, active ? 0 : 21, 25, 20)
    }

    var closeRect: NSRect { NSRect(x: bounds.width - 11, y: 3, width: 9, height: 9) }
    var resizeGripRect: NSRect { NSRect(x: bounds.width - 20, y: bounds.height - 20, width: 20, height: 20) }

    public override func draw(_ dirtyRect: NSRect) {
        guard !isFrameHidden, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        let w = bounds.width, h = bounds.height
        let active = drawsActiveTitleBar

        // Title bar: [corner][side fill...][left end][title...][right end][side fill...][corner]
        let titleWidth = max(25, ceil(titleTextWidth() / 25) * 25)
        let titleStart = max(50, round((w - titleWidth) / 2 / 25) * 25) // keep the pieces on Winamp's 25 px grid
        tile(ctx, titlePiece(4, active: active), from: 25, to: titleStart - 25, y: 0, tileWidth: 25, height: 20)
        draw(ctx, titlePiece(1, active: active), x: titleStart - 25, y: 0, w: 25, h: 20)
        tile(ctx, titlePiece(2, active: active), from: titleStart, to: titleStart + titleWidth, y: 0, tileWidth: 25, height: 20)
        draw(ctx, titlePiece(3, active: active), x: titleStart + titleWidth, y: 0, w: 25, h: 20)
        tile(ctx, titlePiece(4, active: active), from: titleStart + titleWidth + 25, to: w - 25, y: 0, tileWidth: 25, height: 20)
        draw(ctx, titlePiece(0, active: active), x: 0, y: 0, w: 25, h: 20)
        draw(ctx, titlePiece(5, active: active), x: w - 25, y: 0, w: 25, h: 20)
        drawTitleText(ctx, active: active, centeredIn: NSRect(x: titleStart, y: 0, width: titleWidth, height: 20))
        if closePressed { draw(ctx, GenWindowFrameView.gen(148, 42, 9, 9), x: closeRect.minX, y: closeRect.minY, w: 9, h: 9) }

        // Sides: 29 px tiles, then a 24 px piece that meets the bottom bar
        let sideBottom = h - 14 - 24
        vtile(ctx, GenWindowFrameView.gen(127, 42, 11, 29), x: 0, from: 20, to: sideBottom, width: 11)
        vtile(ctx, GenWindowFrameView.gen(139, 42, 8, 29), x: w - 8, from: 20, to: sideBottom, width: 8)
        draw(ctx, GenWindowFrameView.gen(158, 42, 11, 24), x: 0, y: sideBottom, w: 11, h: 24)
        draw(ctx, GenWindowFrameView.gen(170, 42, 8, 24), x: w - 8, y: sideBottom, w: 8, h: 24)

        // Bottom bar: left corner, fill, right corner (with the resize grip)
        tile(ctx, GenWindowFrameView.gen(127, 72, 25, 14), from: 125, to: w - 125, y: h - 14, tileWidth: 25, height: 14)
        draw(ctx, GenWindowFrameView.gen(0, 42, 125, 14), x: 0, y: h - 14, w: min(125, w / 2), h: 14, cropFromLeft: true)
        draw(ctx, GenWindowFrameView.gen(0, 57, 125, 14), x: max(w / 2, w - 125), y: h - 14, w: min(125, w / 2), h: 14, cropFromLeft: false)
    }

    // MARK: Title letters (GEN.BMP: active at y 88, inactive at y 96, 7 px; cyan inside the strips is transparent)

    private func titleTextWidth() -> CGFloat {
        let letters = GenWindowFrameView.letterRanges()
        return title.uppercased().reduce(0) { width, ch in
            guard let i = GenWindowFrameView.alphabet.firstIndex(of: ch).map({ GenWindowFrameView.alphabet.distance(from: GenWindowFrameView.alphabet.startIndex, to: $0) }),
                  letters.indices.contains(i) else { return width + 5 }
            return width + CGFloat(letters[i].count)
        }
    }

    private static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    /// Letter columns in GEN.BMP, measured on the skin: the border row above the letters has a background
    /// pixel between every two letters.
    static func letterRanges() -> [ClosedRange<Int>] {
        guard let sheet = SkinManager.shared.sheet("GEN"),
              sheet.height > 96 else { return [] }
        let rep = NSBitmapImageRep(cgImage: sheet)
        guard let background = rep.colorAt(x: 0, y: 88) else { return [] }
        var ranges: [ClosedRange<Int>] = []
        var start: Int?
        for x in 0..<rep.pixelsWide {
            let isGap = rep.colorAt(x: x, y: 88) == background
            if !isGap, start == nil { start = x }
            if isGap, let s = start { ranges.append(s...(x - 1)); start = nil }
            if ranges.count == 26 { break }
        }
        return ranges
    }

    private func drawTitleText(_ ctx: CGContext, active: Bool, centeredIn area: NSRect) {
        let letters = GenWindowFrameView.letterRanges()
        var x = round(area.midX - titleTextWidth() / 2)
        let rowY: CGFloat = active ? 88 : 96
        let rowHeight: CGFloat = 7 // both rows are 7 px; the row below each is the delimiter
        for ch in title.uppercased() {
            guard let i = GenWindowFrameView.alphabet.firstIndex(of: ch).map({ GenWindowFrameView.alphabet.distance(from: GenWindowFrameView.alphabet.startIndex, to: $0) }),
                  letters.indices.contains(i) else { x += 5; continue }
            let range = letters[i]
            if let glyph = GenWindowFrameView.gen(CGFloat(range.lowerBound), rowY, CGFloat(range.count), rowHeight) {
                // The strip's background colour (cyan in the base skin) shows the title bar through
                let transparent = glyph.copy(maskingColorComponents: [0, 2, 196, 200, 253, 255]) ?? glyph
                // Rows 4...10: level with the title bar's stripes, inside its 2...11 text band
                draw(ctx, transparent, x: x, y: 4, w: CGFloat(range.count), h: rowHeight)
            }
            x += CGFloat(range.count)
        }
    }

    // MARK: Drawing helpers (flipped view; partial tiles are cropped, not squeezed)

    func draw(_ ctx: CGContext, _ image: CGImage?, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, cropFromLeft: Bool? = nil) {
        guard let image, w > 0, h > 0 else { return }
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.clip(to: ctx.pixelAligned(CGRect(x: x, y: y, width: w, height: h)))
        let full = CGFloat(image.width)
        let originX = (cropFromLeft == false) ? x + w - full : x
        ctx.drawSkinImage(image, in: CGRect(x: originX, y: y, width: full, height: CGFloat(image.height)))
        ctx.restoreGState()
    }

    func tile(_ ctx: CGContext, _ image: CGImage?, from start: CGFloat, to end: CGFloat, y: CGFloat, tileWidth: CGFloat, height: CGFloat) {
        var x = start
        while x < end {
            draw(ctx, image, x: x, y: y, w: min(tileWidth, end - x), h: height)
            x += tileWidth
        }
    }

    func vtile(_ ctx: CGContext, _ image: CGImage?, x: CGFloat, from start: CGFloat, to end: CGFloat, width: CGFloat) {
        var y = start
        while y < end {
            draw(ctx, image, x: x, y: y, w: width, h: min(29, end - y))
            y += 29
        }
    }

    // MARK: Mouse: title drags, close button, resize grip

    public override func skinCursorZones() -> [(rect: NSRect, name: String)] {
        guard !isFrameHidden else { return [] }
        // The close button last: it lies inside the title bar and showed the title's move cursor
        return [(NSRect(x: 0, y: 0, width: bounds.width, height: 20), "TITLEBAR"), (resizeGripRect, "PSIZE"), (closeRect, "CLOSE")]
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard !isFrameHidden, let win = window else { return }
        if closeRect.insetBy(dx: -2, dy: -2).contains(point) {
            trackCloseButton(in: win)
        } else if resizeGripRect.contains(point) {
            trackResize(from: event, in: win)
        } else if point.y <= 20 {
            if let dockable = win as? WinampWindow {
                dockable.startWindowDrag(with: event)
                trackWindowDrag(with: event, in: dockable)
            } else {
                win.performDrag(with: event)
            }
        }
    }

    private func trackCloseButton(in win: NSWindow) {
        closePressed = true
        needsDisplay = true
        while let event = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let inside = closeRect.insetBy(dx: -2, dy: -2).contains(convert(event.locationInWindow, from: nil))
            if closePressed != inside { closePressed = inside; needsDisplay = true }
            if event.type == .leftMouseUp {
                closePressed = false
                needsDisplay = true
                if inside { onClose?() }
                return
            }
        }
    }

    /// Resize from the bottom-right grip, snapped to Winamp's 25 × 29 steps; the top-left corner stays put.
    private func trackResize(from start: NSEvent, in win: NSWindow) {
        let startMouse = win.convertPoint(toScreen: start.locationInWindow)
        let startFrame = win.frame
        let scale = PersistenceManager.shared.state.interfaceScale.multiplier
        let startSize = bounds.size
        while let event = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let mouse = win.convertPoint(toScreen: event.locationInWindow)
            let logicalSize = GenWindowFrameView.snappedSize(NSSize(width: startSize.width + (mouse.x - startMouse.x) / scale,
                                                                    height: startSize.height + (startMouse.y - mouse.y) / scale))
            let size = WindowLayoutManager.scaled(logicalSize)
            if size != win.frame.size {
                win.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - size.height, width: size.width, height: size.height), display: true)
                win.updateContentScale(scale, logicalSize: logicalSize)
                onResized?(size)
            }
            if event.type == .leftMouseUp { return }
        }
    }

    public static func snappedSize(_ size: NSSize) -> NSSize {
        let w = max(minimumSize.width, minimumSize.width + ((size.width - minimumSize.width) / resizeStep.width).rounded() * resizeStep.width)
        let h = max(minimumSize.height, minimumSize.height + ((size.height - minimumSize.height) / resizeStep.height).rounded() * resizeStep.height)
        return NSSize(width: w, height: h)
    }
}
