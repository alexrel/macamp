import Foundation
import CoreGraphics
import AppKit

public struct PlaylistStyle {
    public var normalColor: NSColor = NSColor(srgbRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
    public var currentColor: NSColor = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    public var normalBGColor: NSColor = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    public var selectedBGColor: NSColor = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.78, alpha: 1.0)
    public var fontName: String = "Arial"
    
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
    
    public init(name: String) {
        self.name = name
    }
    
    /// 14x11 transparent thumb placeholder used when a skin bakes slider knobs directly into its 28 frames
    private static let transparentThumb: CGImage? = {
        let width = 14
        let height = 11
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }()
    
    /// Returns the cropped CGImage for a given sprite definition from the skin's sheets.
    public func image(for slice: SpriteSlice) -> CGImage? {
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
        
        return nil
    }
}
