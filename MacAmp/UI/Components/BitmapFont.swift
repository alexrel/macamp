import Foundation
import CoreGraphics
import AppKit
import Combine

public struct BitmapFont {
    public static let charWidth: CGFloat = AppConstants.Font.charWidth
    public static let charHeight: CGFloat = AppConstants.Font.charHeight
    
    
    // Map character to (row, col) in TEXT.BMP
    private static let charMap: [Character: (row: Int, col: Int)] = {
        var map: [Character: (row: Int, col: Int)] = [:]
        
        // Row 0: a-z, quotes, @, space
        let alphabet = "abcdefghijklmnopqrstuvwxyz"
        for (i, char) in alphabet.enumerated() {
            map[char] = (0, i)
            map[Character(char.uppercased())] = (0, i)
        }
        map["\""] = (0, 26)
        map["@"] = (0, 27)
        map[" "] = (0, 30)
        
        // Row 1: 0-9 and punctuation
        let digits = "0123456789"
        for (i, char) in digits.enumerated() {
            map[char] = (1, i)
        }
        map["…"] = (1, 10)
        map["."] = (1, 11)
        map[":"] = (1, 12)
        map["("] = (1, 13)
        map[")"] = (1, 14)
        map["-"] = (1, 15)
        map["'"] = (1, 16)
        map["!"] = (1, 17)
        map["_"] = (1, 18)
        map["+"] = (1, 19)
        map["\\"] = (1, 20)
        map["/"] = (1, 21)
        map["["] = (1, 22)
        map["]"] = (1, 23)
        map["^"] = (1, 24)
        map["&"] = (1, 25)
        map["%"] = (1, 26)
        map[","] = (1, 27)
        map["="] = (1, 28)
        map["$"] = (1, 29)
        map["#"] = (1, 30)
        
        // Row 2: special chars
        map["?"] = (2, 3)
        map["*"] = (2, 4)
        map["<"] = (1, 22)
        map[">"] = (1, 23)
        map["{"] = (1, 22)
        map["}"] = (1, 23)
        
        // Cyrillic letters that match Latin visually in classic 5x6 bitmap font
        let cyrillicLookalikes: [(Character, Character)] = [
            ("А", "A"), ("а", "A"),
            ("В", "B"), ("в", "B"),
            ("Е", "E"), ("е", "E"),
            ("Ё", "E"), ("ё", "E"),
            ("К", "K"), ("к", "K"),
            ("М", "M"), ("м", "M"),
            ("Н", "H"), ("н", "H"),
            ("О", "O"), ("о", "O"),
            ("Р", "P"), ("р", "P"),
            ("С", "C"), ("с", "C"),
            ("Т", "T"), ("т", "T"),
            ("У", "Y"), ("у", "Y"),
            ("Х", "X"), ("х", "X"),
            ("І", "I"), ("і", "I")
        ]
        for (cyr, lat) in cyrillicLookalikes {
            if let coords = map[lat] {
                map[cyr] = coords
            }
        }
        
        // Digit 3 serves as visual equivalent for Cyrillic З / з in 5x6
        map["З"] = (1, 3)
        map["з"] = (1, 3)
        
        return map
    }()
    
    // 5x6 pixel art masks for Cyrillic letters (used when font height is 6px, e.g. base-2.91, intec, Winamp 5)
    private static let cyrillicGlyphs6px: [Character: [UInt8]] = {
        var dict: [Character: [UInt8]] = [:]
        let rawGlyphs: [(Character, [UInt8])] = [
            ("Б", [0b11110, 0b10000, 0b11100, 0b10010, 0b10010, 0b11100]),
            ("Г", [0b11110, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000]),
            ("Д", [0b01110, 0b01010, 0b01010, 0b01010, 0b11111, 0b10001]),
            ("Ж", [0b10101, 0b10101, 0b01110, 0b01110, 0b10101, 0b10101]),
            ("И", [0b10010, 0b10010, 0b10110, 0b11010, 0b10010, 0b10010]),
            ("Й", [0b10100, 0b10010, 0b10110, 0b11010, 0b10010, 0b10010]),
            ("Л", [0b00110, 0b01010, 0b01010, 0b01010, 0b01010, 0b10010]),
            ("П", [0b11110, 0b10010, 0b10010, 0b10010, 0b10010, 0b10010]),
            ("Ф", [0b00100, 0b01110, 0b10101, 0b10101, 0b01110, 0b00100]),
            ("Ц", [0b10010, 0b10010, 0b10010, 0b10010, 0b11111, 0b00001]),
            ("Ч", [0b10010, 0b10010, 0b11110, 0b00010, 0b00010, 0b00010]),
            ("Ш", [0b10101, 0b10101, 0b10101, 0b10101, 0b10101, 0b11111]),
            ("Щ", [0b10101, 0b10101, 0b10101, 0b10101, 0b11111, 0b00001]),
            ("Ъ", [0b11000, 0b01000, 0b01110, 0b01010, 0b01010, 0b01110]),
            ("Ы", [0b10010, 0b10010, 0b11101, 0b10110, 0b10110, 0b11101]),
            ("Ь", [0b10000, 0b10000, 0b11100, 0b10010, 0b10010, 0b11100]),
            ("Э", [0b01110, 0b00010, 0b01110, 0b00010, 0b00010, 0b01110]),
            ("Ю", [0b10111, 0b10101, 0b11101, 0b10101, 0b10101, 0b10111]),
            ("Я", [0b01110, 0b10010, 0b01110, 0b00110, 0b01010, 0b10010]),
            ("Ї", [0b10100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100]),
            ("Є", [0b01110, 0b10000, 0b11110, 0b10000, 0b10000, 0b01110]),
            ("Ґ", [0b11110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10000]),
            ("Ў", [0b10100, 0b10010, 0b10010, 0b01100, 0b00100, 0b00100])
        ]
        for (upper, mask) in rawGlyphs {
            dict[upper] = mask
            let lower = Character(String(upper).lowercased())
            dict[lower] = mask
        }
        return dict
    }()
    
    // 5x5 pixel art masks for Cyrillic letters (used when font height is 5px, e.g. reptal, spyamp sepia)
    // Ensures custom letters align with Latin capitals on rows 0..4, leaving row 5 empty.
    private static let cyrillicGlyphs5px: [Character: [UInt8]] = {
        var dict: [Character: [UInt8]] = [:]
        let rawGlyphs: [(Character, [UInt8])] = [
            ("Б", [0b11110, 0b10000, 0b11100, 0b10010, 0b11110, 0b00000]),
            ("Г", [0b11110, 0b10000, 0b10000, 0b10000, 0b10000, 0b00000]),
            ("Д", [0b01110, 0b01010, 0b01010, 0b11111, 0b10001, 0b00000]),
            ("Ж", [0b10101, 0b10101, 0b01110, 0b10101, 0b10101, 0b00000]),
            ("И", [0b10010, 0b10010, 0b10110, 0b11010, 0b10010, 0b00000]),
            ("Й", [0b10100, 0b10010, 0b10110, 0b11010, 0b10010, 0b00000]),
            ("Л", [0b01110, 0b01010, 0b01010, 0b01010, 0b10010, 0b00000]),
            ("П", [0b11110, 0b10010, 0b10010, 0b10010, 0b10010, 0b00000]),
            ("Ф", [0b00100, 0b01110, 0b10101, 0b01110, 0b00100, 0b00000]),
            ("Ц", [0b10010, 0b10010, 0b10010, 0b11110, 0b00011, 0b00000]),
            ("Ч", [0b10010, 0b10010, 0b01110, 0b00010, 0b00010, 0b00000]),
            ("Ш", [0b10101, 0b10101, 0b10101, 0b10101, 0b11111, 0b00000]),
            ("Щ", [0b10101, 0b10101, 0b10101, 0b11110, 0b00011, 0b00000]),
            ("Ъ", [0b11000, 0b01000, 0b01110, 0b01010, 0b01110, 0b00000]),
            ("Ы", [0b10010, 0b10010, 0b11010, 0b10110, 0b11010, 0b00000]),
            ("Ь", [0b10000, 0b10000, 0b11100, 0b10010, 0b11100, 0b00000]),
            ("Э", [0b01110, 0b00010, 0b01110, 0b00010, 0b01110, 0b00000]),
            ("Ю", [0b10110, 0b10101, 0b11101, 0b10101, 0b10110, 0b00000]),
            ("Я", [0b01110, 0b10010, 0b01110, 0b00110, 0b10010, 0b00000]),
            ("Ї", [0b10100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000]),
            ("Є", [0b01110, 0b10000, 0b11110, 0b10000, 0b01110, 0b00000]),
            ("Ґ", [0b11110, 0b10001, 0b10000, 0b10000, 0b10000, 0b00000]),
            ("Ў", [0b10100, 0b10010, 0b10010, 0b01100, 0b00100, 0b00000])
        ]
        for (upper, mask) in rawGlyphs {
            dict[upper] = mask
            let lower = Character(String(upper).lowercased())
            dict[lower] = mask
        }
        return dict
    }()
    
    private struct TextColorProfile {
        let rowColors: [CGColor]
        let spaceGlyph: CGImage?
        let is5PixelFont: Bool
    }
    
    private static var cachedProfile: TextColorProfile?
    private static var cachedSheetId: ObjectIdentifier?
    
    /// Samples text styling directly from TEXT.BMP of the active skin.
    ///
    /// Authentic Winamp 2.x skins vary wildly: some are green on black, some are white on dark blue,
    /// some are dark brown on tan sepia, and some (like reptal) feature a distinct vertical amber color gradient
    /// across rows 0..4.
    ///
    /// By scanning letter 'I' (row 0, col 8) for the maximum contrast stroke pixel on each scanline alongside
    /// the space glyph (row 0, col 30), we capture the exact stroke color and gradient profile.
    /// In addition, detecting whether row 5 has text pixels enables automatic adaptation between 5px and 6px fonts.
    private static func sampleTextColorProfile(from sheet: CGImage) -> TextColorProfile {
        let w = Int(charWidth)
        let h = Int(charHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let spaceRect = CGRect(x: 30 * w, y: 0, width: w, height: h)
        let spaceGlyph = sheet.cropping(to: spaceRect)
        
        // 1. Sample background color from space glyph (col 30: x = 150..154, y = 0..5)
        var bgR: CGFloat = 0
        var bgG: CGFloat = 0
        var bgB: CGFloat = 0
        var spaceBuffer = [UInt8](repeating: 0, count: w * h * 4)
        if let spaceGlyph = spaceGlyph,
           let spaceCtx = CGContext(
               data: &spaceBuffer,
               width: w,
               height: h,
               bitsPerComponent: 8,
               bytesPerRow: w * 4,
               space: colorSpace,
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            spaceCtx.draw(spaceGlyph, in: CGRect(x: 0, y: 0, width: w, height: h))
            // Center of space glyph (x=2, y=2)
            let centerIdx = (2 * w + 2) * 4
            bgR = CGFloat(spaceBuffer[centerIdx + 0]) / 255.0
            bgG = CGFloat(spaceBuffer[centerIdx + 1]) / 255.0
            bgB = CGFloat(spaceBuffer[centerIdx + 2]) / 255.0
        }
        
        // 2. Sample letter 'I' at col 8 (x = 40..44, y = 0..5)
        let defaultWinampGreen = CGColor(red: 0.0, green: 0.886, blue: 0.0, alpha: 1.0)
        let rectI = CGRect(x: 8 * w, y: 0, width: w, height: h)
        guard let glyphI = sheet.cropping(to: rectI) else {
            return TextColorProfile(rowColors: Array(repeating: defaultWinampGreen, count: 6), spaceGlyph: spaceGlyph, is5PixelFont: false)
        }
        
        var iBuffer = [UInt8](repeating: 0, count: w * h * 4)
        guard let iCtx = CGContext(
            data: &iBuffer,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return TextColorProfile(rowColors: Array(repeating: defaultWinampGreen, count: 6), spaceGlyph: spaceGlyph, is5PixelFont: false)
        }
        
        iCtx.draw(glyphI, in: CGRect(x: 0, y: 0, width: w, height: h))
        
        var sampledRows = [CGColor?](repeating: nil, count: 6)
        for y in 0..<6 {
            var bestDistSq: CGFloat = -1
            var bestColor: CGColor?
            for x in 0..<5 {
                let offset = (y * w + x) * 4
                let r = CGFloat(iBuffer[offset + 0]) / 255.0
                let g = CGFloat(iBuffer[offset + 1]) / 255.0
                let b = CGFloat(iBuffer[offset + 2]) / 255.0
                let a = CGFloat(iBuffer[offset + 3]) / 255.0
                guard a > 0.1 else { continue }
                
                let dr = r - bgR
                let dg = g - bgG
                let db = b - bgB
                let distSq = dr * dr + dg * dg + db * db
                if distSq > bestDistSq {
                    bestDistSq = distSq
                    bestColor = CGColor(red: r, green: g, blue: b, alpha: 1.0)
                }
            }
            if bestDistSq > 0.005 {
                sampledRows[y] = bestColor
            }
        }
        
        // If row 5 has no stroke pixel differing from background, this skin uses a 5-pixel font (y=0..4)
        let is5PixelFont = (sampledRows[5] == nil)
        
        // Find solid reference color (row 2 or 3 is the vertical stem center)
        let refColor = sampledRows[2] ?? sampledRows[3] ?? sampledRows[1] ?? defaultWinampGreen
        
        // Populate any blank scanlines (e.g. y=5 or y=0)
        var finalRows = [CGColor]()
        for y in 0..<6 {
            if let c = sampledRows[y] {
                finalRows.append(c)
            } else if y == 5 {
                finalRows.append(sampledRows[4] ?? refColor)
            } else if y == 0 {
                finalRows.append(sampledRows[1] ?? refColor)
            } else {
                finalRows.append(refColor)
            }
        }
        
        return TextColorProfile(rowColors: finalRows, spaceGlyph: spaceGlyph, is5PixelFont: is5PixelFont)
    }
    
    private static func getTextColorProfile(from sheet: CGImage) -> TextColorProfile {
        let sheetId = ObjectIdentifier(sheet)
        if let cached = cachedProfile, cachedSheetId == sheetId {
            return cached
        }
        let profile = sampleTextColorProfile(from: sheet)
        cachedProfile = profile
        cachedSheetId = sheetId
        return profile
    }
    
    /// Draws a single glyph character using TEXT.BMP font with Cyrillic pixel-art fallback
    public static func drawGlyph(char: Character, in context: CGContext, at origin: CGPoint) {
        guard let textSheet = SkinManager.shared.sheet("TEXT") else { return }
        
        // 1. Direct match in TEXT.BMP (Latin, digits, lookalike Cyrillic)
        if let (row, col) = charMap[char] {
            let srcRect = CGRect(
                x: CGFloat(col) * charWidth,
                y: CGFloat(row) * charHeight,
                width: charWidth,
                height: charHeight
            )
            if let glyph = textSheet.cropping(to: srcRect) {
                let destRect = CGRect(x: origin.x, y: origin.y, width: charWidth, height: charHeight)
                context.drawSkinImage(glyph, in: destRect)
            }
            return
        }
        
        // 2. Custom pixel-art Cyrillic glyphs matching skin text color & gradient from letter 'I'
        let profile = getTextColorProfile(from: textSheet)
        let glyphMap = profile.is5PixelFont ? cyrillicGlyphs5px : cyrillicGlyphs6px
        if let mask = glyphMap[char] {
            let destRect = CGRect(x: origin.x, y: origin.y, width: charWidth, height: charHeight)
            
            // 2a. Draw authentic space background beneath custom glyph so skin background doesn't shine through
            if let spaceGlyph = profile.spaceGlyph {
                context.drawSkinImage(spaceGlyph, in: destRect)
            }
            
            // 2b. Draw custom foreground pixels using per-row stroke colors from letter 'I'
            for y in 0..<6 {
                let row = mask[y]
                guard row != 0 else { continue }
                context.setFillColor(profile.rowColors[y])
                for x in 0..<5 {
                    if (row & (1 << (4 - x))) != 0 {
                        context.fill(CGRect(x: origin.x + CGFloat(x), y: origin.y + CGFloat(y), width: 1, height: 1))
                    }
                }
            }
            return
        }
        
        // 3. Fallback to space
        let (row, col) = (0, 30)
        let srcRect = CGRect(
            x: CGFloat(col) * charWidth,
            y: CGFloat(row) * charHeight,
            width: charWidth,
            height: charHeight
        )
        if let glyph = textSheet.cropping(to: srcRect) {
            let destRect = CGRect(x: origin.x, y: origin.y, width: charWidth, height: charHeight)
            context.drawSkinImage(glyph, in: destRect)
        }
    }
    
    /// Draws a string using the classic TEXT.BMP bitmap font into the provided CGContext.
    public static func draw(string: String, in context: CGContext, at origin: CGPoint) {
        var currentX = origin.x
        for char in string {
            drawGlyph(char: char, in: context, at: CGPoint(x: currentX, y: origin.y))
            currentX += charWidth
        }
    }
    
    /// Fills the given width with authentic space glyphs from TEXT.BMP.
    /// In Winamp/Webamp, the marquee background is always covered with space glyphs.
    public static func drawSpaceBackground(in context: CGContext, width: CGFloat, height: CGFloat = charHeight) {
        guard let textSheet = SkinManager.shared.sheet("TEXT") else { return }
        let spaceRect = CGRect(x: 30.0 * charWidth, y: 0, width: charWidth, height: charHeight)
        guard let spaceGlyph = textSheet.cropping(to: spaceRect) else { return }
        
        var x: CGFloat = 0
        while x < width {
            context.drawSkinImage(spaceGlyph, in: CGRect(x: x, y: 0, width: charWidth, height: height))
            x += charWidth
        }
    }
    
    /// Draws mini time display digits without painting over the baked-in skin colon.
    /// In Winamp 2.x, TITLEBAR.BMP and PLEDIT.BMP already contain the green colon separator.
    /// Digits: m1 at origin.x+7, m2 at origin.x+12, s1 at origin.x+20, s2 at origin.x+25.
    /// The 3px gap (origin.x+17..19) allows the background colon to shine through steadily without jumping.
    public static func drawMiniTime(
        minutes: Int,
        seconds: Int,
        isNegative: Bool = false,
        status: PlayerStatus,
        isBlinkVisible: Bool,
        in context: CGContext,
        at origin: CGPoint
    ) {
        guard status != .stopped else { return }
        
        // Minus sign at offset 1
        if isNegative {
            if isBlinkVisible || status != .paused {
                drawGlyph(char: "-", in: context, at: CGPoint(x: origin.x + AppConstants.TimeDisplay.MiniOffsets.minusX, y: origin.y))
            }
        }
        
        // When paused and blink is off, do not draw digits - let the background colon show steadily!
        if status == .paused && !isBlinkVisible {
            return
        }
        
        let m1 = Character(String((minutes / 10) % 10))
        let m2 = Character(String(minutes % 10))
        let s1 = Character(String((seconds / 10) % 10))
        let s2 = Character(String(seconds % 10))
        
        drawGlyph(char: m1, in: context, at: CGPoint(x: origin.x + AppConstants.TimeDisplay.MiniOffsets.minuteTensX, y: origin.y))
        drawGlyph(char: m2, in: context, at: CGPoint(x: origin.x + AppConstants.TimeDisplay.MiniOffsets.minuteOnesX, y: origin.y))
        // Background colon at origin.x+17..19 shines through without jumping
        drawGlyph(char: s1, in: context, at: CGPoint(x: origin.x + AppConstants.TimeDisplay.MiniOffsets.secondTensX, y: origin.y))
        drawGlyph(char: s2, in: context, at: CGPoint(x: origin.x + AppConstants.TimeDisplay.MiniOffsets.secondOnesX, y: origin.y))
    }
}
