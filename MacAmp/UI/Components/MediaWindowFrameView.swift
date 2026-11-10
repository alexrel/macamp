import Cocoa

/// Frame of the Video and Minibrowser windows, drawn from VIDEO.BMP / MB.BMP (both share one layout, Winamp's
/// draw_vw.cpp): a title bar whose 100 px centre carries the skin's own title, sides, and a 38 px bottom bar with
/// five 15 × 18 buttons and an info line (pledit.txt MbFG / MbBG). Dragging, closing and resizing come from the GEN frame.
public final class MediaWindowFrameView: GenWindowFrameView {
    /// "VIDEO" or "MB"
    public let sheet: String
    /// The black line in the bottom bar: video file name, or the minibrowser's address
    public var info = "" { didSet { if info != oldValue { needsDisplay = true } } }
    /// Bottom-bar button 0...4 clicked
    public var onButton: ((Int) -> Void)?
    private var pressedButton: Int?

    public init(sheet: String, content: NSView) {
        self.sheet = sheet
        super.init(title: "", content: content)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var frameInsets: NSEdgeInsets { NSEdgeInsets(top: 20, left: 11, bottom: 38, right: 8) }

    private func sprite(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGImage? {
        SkinManager.shared.image(for: SpriteSlice(sheet, sheet, x, y, w, h))
    }

    /// Where a button's menu goes: its bottom edge on the button's top, left edges aligned, as in 2.95
    /// (this view is flipped: the menu's top-left corner is the point given)
    func menuOrigin(_ menu: NSMenu, button index: Int) -> NSPoint {
        let r = buttonRect(index)
        let height = convert(NSRect(origin: .zero, size: menu.size), from: nil).height
        return NSPoint(x: r.minX, y: r.minY - height)
    }

    /// Opens a button's menu above it
    public func popUp(_ menu: NSMenu, button index: Int) {
        menu.popUp(positioning: nil, at: menuOrigin(menu, button: index), in: self)
    }

    func buttonRect(_ index: Int) -> NSRect { NSRect(x: 9 + CGFloat(index) * 15, y: bounds.height - 29, width: 15, height: 18) }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        let w = bounds.width, h = bounds.height
        let s: CGFloat = drawsActiveTitleBar ? 0 : 21

        // Title: [corner][fill...][title 100][fill...][corner with close]
        let leftFill = floor((w - 150) / 2)
        draw(ctx, sprite(0, s, 25, 20), x: 0, y: 0, w: 25, h: 20)
        tile(ctx, sprite(127, s, 25, 20), from: 25, to: 25 + leftFill, y: 0, tileWidth: 25, height: 20)
        draw(ctx, sprite(26, s, 100, 20), x: 25 + leftFill, y: 0, w: 100, h: 20)
        tile(ctx, sprite(127, s, 25, 20), from: 125 + leftFill, to: w - 25, y: 0, tileWidth: 25, height: 20)
        draw(ctx, sprite(153, s, 25, 20), x: w - 25, y: 0, w: 25, h: 20)
        if closePressed { draw(ctx, sprite(148, 42, 9, 9), x: closeRect.minX, y: closeRect.minY, w: 9, h: 9) }

        // Sides, then the bottom bar: left part with the buttons, fill, right part with the resize grip
        vtile(ctx, sprite(127, 42, 11, 29), x: 0, from: 20, to: h - 38, width: 11)
        vtile(ctx, sprite(139, 42, 8, 29), x: w - 8, from: 20, to: h - 38, width: 8)
        draw(ctx, sprite(0, 42, 125, 38), x: 0, y: h - 38, w: 125, h: 38)
        tile(ctx, sprite(127, 81, 25, 38), from: 125, to: w - 125, y: h - 38, tileWidth: 25, height: 38)
        draw(ctx, sprite(0, 81, 125, 38), x: w - 125, y: h - 38, w: 125, h: 38)
        if let b = pressedButton {
            let r = buttonRect(b)
            draw(ctx, sprite(158 + CGFloat(b) * 15, 42, 15, 18), x: r.minX, y: r.minY, w: 15, h: 18)
        }

        // Info line (x 92 ... width - 25), in the skin's minibrowser colours
        let style = SkinManager.shared.currentSkin?.playlistStyle ?? PlaylistStyle()
        let line = NSRect(x: 92, y: h - 27, width: max(0, w - 25 - 92), height: 14)
        (style.minibrowserBackground ?? style.normalBGColor).setFill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: style.fontName, size: 10) ?? NSFont.systemFont(ofSize: 10),
            .foregroundColor: style.minibrowserText ?? style.normalColor,
            .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail; return p }(),
        ]
        (info as NSString).draw(with: line.insetBy(dx: 0, dy: 1), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = (0..<5).first(where: { buttonRect($0).contains(point) }), let win = window else {
            super.mouseDown(with: event)
            return
        }
        // Like the close button: pressed while the mouse stays on it, acts on release
        pressedButton = index
        display()
        while let e = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let inside = buttonRect(index).contains(convert(e.locationInWindow, from: nil))
            if (pressedButton != nil) != inside { pressedButton = inside ? index : nil; display() }
            if e.type == .leftMouseUp {
                pressedButton = nil
                needsDisplay = true
                if inside { onButton?(index) }
                return
            }
        }
    }
}
