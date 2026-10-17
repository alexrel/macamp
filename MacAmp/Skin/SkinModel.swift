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
    
    /// Returns the cropped CGImage for a given sprite definition from the skin's sheets.
    public func image(for slice: SpriteSlice) -> CGImage? {
        guard let sheet = images[slice.sheet.uppercased()] else {
            return nil
        }
        
        let crop = slice.rect
        guard crop.minX >= 0, crop.minY >= 0,
              crop.maxX <= CGFloat(sheet.width),
              crop.maxY <= CGFloat(sheet.height) else {
            return nil
        }
        
        return sheet.cropping(to: crop)
    }
}
