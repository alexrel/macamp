import Foundation
import CoreGraphics
import AppKit

public struct BitmapFont {
    public static let charWidth: CGFloat = 5
    public static let charHeight: CGFloat = 6
    
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
        
        return map
    }()
    
    /// Draws a string using the classic TEXT.BMP bitmap font into the provided CGContext.
    public static func draw(string: String, in context: CGContext, at origin: CGPoint) {
        guard let textSheet = SkinManager.shared.sheet("TEXT") else { return }
        
        var currentX = origin.x
        for char in string {
            let (row, col) = charMap[char] ?? (0, 30) // fallback to space
            let srcRect = CGRect(
                x: CGFloat(col) * charWidth,
                y: CGFloat(row) * charHeight,
                width: charWidth,
                height: charHeight
            )
            
            if let glyph = textSheet.cropping(to: srcRect) {
                let destRect = CGRect(x: currentX, y: origin.y, width: charWidth, height: charHeight)
                context.drawSkinImage(glyph, in: destRect)
            }
            
            currentX += charWidth
        }
    }
}
