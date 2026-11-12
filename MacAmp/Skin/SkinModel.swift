import Foundation
import CoreGraphics
import AppKit

public struct PlaylistStyle {
    public var normalColor: NSColor = NSColor(srgbRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
    public var currentColor: NSColor = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    public var normalBGColor: NSColor = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    public var selectedBGColor: NSColor = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.78, alpha: 1.0)
    public var fontName: String = "Arial"
    /// Video / Minibrowser info line (pledit.txt MbFG / MbBG); playlist colours when the skin has none
    public var minibrowserText: NSColor?
    public var minibrowserBackground: NSColor?
    
    public init() {}
}

public struct VisualizerColors {
    /// 24 color palette from VISCOLOR.TXT
    public var colors: [NSColor] = VisualizerColors.defaultColors()
    
    public init() {}
    
    public static func defaultColors() -> [NSColor] {
        // Standard Winamp default 24-color palette
        let hexList: [(CGFloat, CGFloat, CGFloat)] = [
            (0, 0, 0),        // 0: background
            (24, 33, 41),     // 1: dots / peaks
            (239, 49, 16),    // 2: top of spec (red)
            (206, 41, 16),    // 3
            (214, 90, 0),     // 4 (orange)
            (214, 102, 0),    // 5
            (214, 115, 0),    // 6
            (198, 123, 8),    // 7
            (222, 165, 24),   // 8 (yellow)
            (214, 181, 33),   // 9
            (189, 222, 41),   // 10
            (148, 222, 33),   // 11
            (41, 206, 16),    // 12 (green)
            (50, 190, 16),    // 13
            (57, 181, 16),    // 14
            (49, 156, 8),     // 15
            (41, 148, 0),     // 16
            (24, 132, 8),     // 17: bottom of spec
            (255, 255, 255),  // 18: osc 1
            (214, 214, 222),  // 19: osc 2
            (181, 189, 189),  // 20: osc 3
            (160, 170, 175),  // 21: osc 4
            (148, 156, 165),  // 22: osc 5
            (150, 150, 150)   // 23: osc peak
        ]
        return hexList.map { NSColor(srgbRed: $0.0/255.0, green: $0.1/255.0, blue: $0.2/255.0, alpha: 1.0) }
    }
}

public class Skin {
    public let name: String
    public var images: [String: CGImage] = [:]
    public var playlistStyle: PlaylistStyle = PlaylistStyle()
    public var visualizerColors: VisualizerColors = VisualizerColors()
    public var region: SkinRegion?
    /// Skin cursors (*.CUR), keyed by upper-case file stem: "TITLEBAR", "POSBAR", "PSIZE", ...
    public var cursors: [String: NSCursor] = [:]
    
    public init(name: String) {
        self.name = name
    }
    
    /// Every skin bitmap is kept in sRGB, whichever way it was decoded: sheets in different colour spaces show the same
    /// RGB value as two different colours (the main window against the time digits and the title on a wide-gamut display)
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// 14x11 transparent thumb placeholder used when a skin bakes slider knobs directly into its 28 frames
    private static let transparentThumb: CGImage? = {
        let width = 14
        let height = 11
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: Skin.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }()
    
    /// Returns the cropped CGImage for a given sprite definition from the skin's sheets.
    public func image(for slice: SpriteSlice) -> CGImage? {
        var slice = slice
        // Like Winamp, a skin with NUMS_EX.BMP takes the time digits from it: same digit cells, a minus cell of its own
        if slice.sheet == "NUMBERS", images["NUMS_EX"] != nil {
            slice = SpriteCatalog.numsEx[slice.name]
                ?? SpriteSlice(slice.name, "NUMS_EX", slice.rect.minX, slice.rect.minY, slice.rect.width, slice.rect.height)
        }
        let sheetKey = slice.sheet.uppercased()
        
        // 1. Direct slice from sheet if present and within bounds
        if let sheet = images[sheetKey] {
            var crop = slice.rect
            // In skins where BALANCE.BMP was cropped to 38px width (e.g. reptal~1), the 38px frames start at x = 0 instead of standard x = 9.
            if sheetKey == "BALANCE", slice.name.hasPrefix("BAL_BG"), sheet.width < 47 {
                crop.origin.x = 0
            }
            if crop.minX >= 0, crop.minY >= 0,
               crop.maxX <= CGFloat(sheet.width),
               crop.maxY <= CGFloat(sheet.height) {
                return sheet.cropping(to: crop)
            }
        }
        
        // 2. Thumb suppression rule:
        // In skins where VOLUME.BMP or BALANCE.BMP is ~420px high (height < 430),
        // the author baked the slider thumb directly into the 28 animated background frames.
        // There is no thumb sprite at y=422. Returning a transparent thumb prevents falling back
        // to baseSkin and overlaying the default silver Winamp knob on top of custom theme sliders.
        if slice.name.hasPrefix("VOL_THUMB") {
            if let volSheet = images["VOLUME"], volSheet.height < 430 {
                return Skin.transparentThumb
            }
        }
        if slice.name.hasPrefix("BAL_THUMB") {
            if let balSheet = images["BALANCE"] ?? images["VOLUME"], balSheet.height < 430 {
                return Skin.transparentThumb
            }
        }
        
        // 3. Authentic Winamp fallback: When BALANCE.BMP is missing, fall back to VOLUME.BMP in the same skin.
        // Balance frame at x = 9, width = 38 is perfectly centered in VOLUME.BMP (68px wide).
        // Balance thumb at x = 15/0, y = 422 is identical to volume thumb coordinates.
        if sheetKey == "BALANCE", let volSheet = images["VOLUME"] {
            let crop = slice.rect
            if crop.minX >= 0, crop.minY >= 0,
               crop.maxX <= CGFloat(volSheet.width),
               crop.maxY <= CGFloat(volSheet.height) {
                return volSheet.cropping(to: crop)
            }
        }
        
        // 4. A sheet smaller than the standard (MAIN.BMP 115 rows high, POSBAR.BMP 9): Winamp draws the part that is
        // there. The missing part stays transparent rather than showing the base skin through a custom one.
        if let sheet = images[sheetKey] {
            let part = slice.rect.intersection(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
            if !part.isEmpty, let piece = sheet.cropping(to: part),
               let ctx = CGContext(data: nil, width: Int(slice.rect.width), height: Int(slice.rect.height), bitsPerComponent: 8,
                                   bytesPerRow: 0, space: Skin.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                // CGContext counts rows from the bottom, the sheet from the top
                ctx.draw(piece, in: CGRect(x: part.minX - slice.rect.minX, y: slice.rect.maxY - part.maxY,
                                           width: part.width, height: part.height))
                return ctx.makeImage()
            }
        }
        
        return nil
    }
}
