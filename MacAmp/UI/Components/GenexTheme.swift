import SwiftUI
import AppKit

/// Colours and art of Winamp's general-purpose windows (Media Library ...), read from the skin's GENEX.BMP
/// exactly as Winamp's wa_dlg.h does: one pixel per colour at (48 + 2i, 0), button art at the top left,
/// scrollbar art below it. Read once per skin.
public struct GenexTheme {
    /// wa_dlg.h WADLG_* order
    public enum Slot: Int, CaseIterable {
        case itemBackground, itemForeground, windowBackground, buttonText, windowText, divider, playlistSelection,
             headerBackground, headerText, headerFrameTop, headerFrameMiddle, headerFrameBottom, headerEmpty,
             scrollbarForeground, scrollbarBackground, scrollbarInverseForeground, scrollbarInverseBackground, scrollbarDeadArea,
             selectionText, selectionBackground, inactiveSelectionText, inactiveSelectionBackground
    }

    /// wa_dlg.h defaults, used when the skin leaves a pixel unset
    static let defaults: [NSColor] = [
        (0, 0, 0), (0, 255, 0), (36, 36, 60), (57, 56, 66), (255, 255, 255), (132, 148, 165), (0, 0, 198),
        (72, 72, 120), (255, 255, 255), (108, 108, 180), (36, 36, 60), (18, 18, 30), (36, 36, 60),
        (36, 36, 60), (36, 36, 60), (121, 130, 150), (78, 88, 110), (36, 36, 60),
        (255, 255, 255), (0, 0, 180), (0, 255, 0), (0, 0, 128),
    ].map { NSColor(srgbRed: CGFloat($0.0) / 255, green: CGFloat($0.1) / 255, blue: CGFloat($0.2) / 255, alpha: 1) }

    public private(set) var colors: [NSColor] = GenexTheme.defaults
    /// Button bitmaps (47 × 15): 4 px edges kept, centre stretched
    public private(set) var button: CGImage?
    public private(set) var buttonPressed: CGImage?

    public func ns(_ slot: Slot) -> NSColor { colors[slot.rawValue] }
    func color(_ slot: Slot) -> Color { Color(nsColor: ns(slot)) }

    public var itemBackground: Color { color(.itemBackground) }
    public var itemForeground: Color { color(.itemForeground) }
    public var windowBackground: Color { color(.windowBackground) }
    public var buttonText: Color { color(.buttonText) }
    public var windowText: Color { color(.windowText) }
    public var divider: Color { color(.divider) }
    public var headerBackground: Color { color(.headerBackground) }
    public var headerText: Color { color(.headerText) }
    public var headerLight: Color { color(.headerFrameTop) }
    public var headerDark: Color { color(.headerFrameBottom) }
    public var selection: Color { color(.selectionBackground) }
    public var selectedText: Color { color(.selectionText) }

    /// GENEX.BMP sprite (scrollbar arrows and thumbs)
    public static func sprite(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGImage? {
        SkinManager.shared.image(for: SpriteSlice("GENEX", "GENEX", x, y, w, h))
    }

    private static var cache: (sheet: CGImage?, theme: GenexTheme)?

    public static var current: GenexTheme {
        let sheet = SkinManager.shared.sheet("GENEX")
        if let cache, cache.sheet === sheet { return cache.theme }
        let theme = sheet.map(GenexTheme.init(sheet:)) ?? GenexTheme()
        cache = (sheet, theme)
        return theme
    }

    init() {}

    init(sheet: CGImage) {
        let rep = NSBitmapImageRep(cgImage: sheet)
        // Winamp compares RGB only: a pixel equal to (111, 0), cyan or missing means "not set by this skin"
        func rgb(_ x: Int) -> (NSColor, [Int])? {
            guard x < rep.pixelsWide, let c = rep.colorAt(x: x, y: 0)?.usingColorSpace(.sRGB) else { return nil }
            return (c.withAlphaComponent(1), [c.redComponent, c.greenComponent, c.blueComponent].map { Int(round($0 * 255)) })
        }
        let unset = rgb(111)?.1
        func pixel(_ x: Int) -> NSColor? {
            guard let (c, value) = rgb(x), value != unset, value != [0, 198, 255] else { return nil }
            return c
        }
        for slot in Slot.allCases {
            if let c = pixel(48 + slot.rawValue * 2) { colors[slot.rawValue] = c; continue }
            // Older skins: selection bars follow the playlist selection and window text, as in wa_dlg.h
            switch slot {
            case .selectionText, .inactiveSelectionText: colors[slot.rawValue] = colors[Slot.windowText.rawValue]
            case .selectionBackground: colors[slot.rawValue] = colors[Slot.playlistSelection.rawValue]
            case .inactiveSelectionBackground:
                colors[slot.rawValue] = colors[Slot.playlistSelection.rawValue].blended(withFraction: 0.5, of: colors[Slot.windowBackground.rawValue])
                    ?? colors[slot.rawValue]
            default: break
            }
        }
        button = sheet.cropping(to: CGRect(x: 0, y: 0, width: 47, height: 15))
        buttonPressed = sheet.cropping(to: CGRect(x: 0, y: 15, width: 47, height: 15))
    }
}

/// Winamp general-window button (GENEX art): 4 px caps, stretched middle, skin's button text colour.
public struct GenexButton: View {
    let title: String
    let width: CGFloat?
    let action: () -> Void
    @State private var pressed = false
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, width: CGFloat? = nil, action: @escaping () -> Void) {
        self.title = title
        self.width = width
        self.action = action
    }

    public var body: some View {
        let theme = GenexTheme.current
        // Disabled text: halfway between window text and window background (wa_dlg.h)
        let disabled = Color(nsColor: theme.ns(.windowText).blended(withFraction: 0.5, of: theme.ns(.windowBackground)) ?? theme.ns(.windowText))
        Text(title)
            .font(.system(size: 10))
            .foregroundColor(isEnabled ? theme.buttonText : disabled)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .offset(x: pressed ? 1 : 0, y: pressed ? 1 : 0)
            .frame(width: width, height: 15)
            .background(GenexButtonArt(image: pressed ? theme.buttonPressed : theme.button))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if isEnabled { pressed = true } }
                .onEnded { value in
                    pressed = false
                    if isEnabled, abs(value.translation.width) < 30, abs(value.translation.height) < 15 { action() }
                })
    }
}

/// Draws a 47 × 15 GENEX button bitmap at any size: 4 px corners and edges kept, the rest stretched (wa_dlg.h).
struct GenexButtonArt: NSViewRepresentable {
    let image: CGImage?

    func makeNSView(context: Context) -> ArtView { ArtView() }
    func updateNSView(_ view: ArtView, context: Context) {
        view.image = image
        view.needsDisplay = true
    }

    final class ArtView: NSView {
        var image: CGImage?
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            guard let image, let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.drawNinePatch(image, in: bounds, edge: 4)
        }
    }
}

extension CGContext {
    /// Windows-style 9-slice: `edge` px corners copied, edges and centre stretched.
    func drawNinePatch(_ image: CGImage, in rect: CGRect, edge e: CGFloat) {
        interpolationQuality = .none
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let xs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, e, rect.minX, e), (e, iw - 2 * e, rect.minX + e, rect.width - 2 * e), (iw - e, e, rect.maxX - e, e)]
        let ys: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, e, rect.minY, e), (e, ih - 2 * e, rect.minY + e, rect.height - 2 * e), (ih - e, e, rect.maxY - e, e)]
        for x in xs where x.3 > 0 {
            for y in ys where y.3 > 0 {
                if let piece = image.cropping(to: CGRect(x: x.0, y: y.0, width: x.1, height: y.1)) {
                    drawSkinImage(piece, in: CGRect(x: x.2, y: y.2, width: x.3, height: y.3))
                }
            }
        }
    }
}
