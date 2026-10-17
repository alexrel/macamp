import Foundation
import CoreGraphics
import AppKit
import Combine

public struct BitmapFont {
    public static let charWidth: CGFloat = AppConstants.Font.charWidth
    public static let charHeight: CGFloat = AppConstants.Font.charHeight
    
    // Sampled skin text color cache
    private static var cachedTextColor: CGColor?
    private static var cachedSheetId: ObjectIdentifier?
    
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
    
    // 5x6 pixel art masks for Cyrillic letters without direct Latin equivalents
    private static let cyrillicGlyphs: [Character: [UInt8]] = {
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
    
    /// Samples the text color from character 'A' in TEXT.BMP of the active skin
    private static func sampleTextColor(from sheet: CGImage) -> CGColor {
        let w = Int(charWidth)
        let h = Int(charHeight)
        
        guard let glyphA = sheet.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)) else {
            return CGColor(red: 0.0, green: 0.886, blue: 0.0, alpha: 1.0)
        }
        
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buffer,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CGColor(red: 0.0, green: 0.886, blue: 0.0, alpha: 1.0)
        }
        
        ctx.draw(glyphA, in: CGRect(x: 0, y: 0, width: w, height: h))
        
        var bestLum: Float = -1
        var bestR: CGFloat = 0
        var bestG: CGFloat = 0.886
        var bestB: CGFloat = 0
        
        for i in 0..<(w * h) {
            let r = CGFloat(buffer[i * 4 + 0]) / 255.0
            let g = CGFloat(buffer[i * 4 + 1]) / 255.0
            let b = CGFloat(buffer[i * 4 + 2]) / 255.0
            let a = CGFloat(buffer[i * 4 + 3]) / 255.0
            let lum = Float(0.299 * r + 0.587 * g + 0.114 * b) * Float(a)
            if lum > bestLum {
                bestLum = lum
                bestR = r
                bestG = g
                bestB = b
            }
        }
        
        if bestLum > 0.05 {
            return CGColor(red: bestR, green: bestG, blue: bestB, alpha: 1.0)
        }
        
        return CGColor(red: 0.0, green: 0.886, blue: 0.0, alpha: 1.0) // default Winamp green
    }
    
    private static func getOrSampleTextColor(from sheet: CGImage) -> CGColor {
        let sheetId = ObjectIdentifier(sheet)
        if let cached = cachedTextColor, cachedSheetId == sheetId {
            return cached
        }
        let sampled = sampleTextColor(from: sheet)
        cachedTextColor = sampled
        cachedSheetId = sheetId
        return sampled
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
        
        // 2. Custom pixel-art Cyrillic glyphs matching skin text color
        if let mask = cyrillicGlyphs[char] {
            let color = getOrSampleTextColor(from: textSheet)
            context.setFillColor(color)
            for y in 0..<6 {
                let row = mask[y]
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
