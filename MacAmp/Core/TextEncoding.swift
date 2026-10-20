import Foundation

/// Detects and repairs Windows-1251 (CP1251) Cyrillic text that was decoded as ISO-8859-1 (Latin-1).
///
/// Legacy MP3 tags, M3U/PLS playlists and SHOUTcast titles often carry CP1251 bytes without a BOM.
/// Decoded as Latin-1 they turn into mojibake: "Кино" -> "Êèíî".
public enum TextEncoding {
    public static let windows1251 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue))
    )

    /// Repairs a string that looks like CP1251 bytes mis-decoded as Latin-1. Returns the input unchanged otherwise.
    public static func repairCyrillic(_ string: String) -> String {
        guard looksLikeCyrillicMojibake(string),
              let bytes = string.data(using: .isoLatin1),
              let decoded = String(data: bytes, encoding: windows1251),
              isMostlyCyrillic(decoded) else {
            return string
        }
        return decoded
    }

    /// Decodes raw text bytes of unknown encoding: UTF-8 if valid, else CP1251 when the bytes look Cyrillic, else Latin-1.
    public static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let latin1 = String(data: data, encoding: .isoLatin1) ?? ""
        return repairCyrillic(latin1)
    }

    /// Mojibake signature, judged per word so ASCII parts (URLs, "#EXTINF", English words) don't dilute it:
    /// a CP1251 word decoded as Latin-1 consists mostly of U+00C0...U+00FF characters ("Êèíî"), while Western
    /// words carry only an occasional accent ("Björk", "Sigur Rós"). Any character above U+00FF rules it out,
    /// because such a string cannot have come from a Latin-1 decode.
    static func looksLikeCyrillicMojibake(_ string: String) -> Bool {
        var mojibakeWords = 0
        var accentedWords = 0
        var wordLength = 0
        var wordSupplement = 0
        
        func endWord() {
            if wordSupplement > 0 {
                if wordSupplement * 2 >= wordLength { mojibakeWords += 1 } else { accentedWords += 1 }
            }
            wordLength = 0
            wordSupplement = 0
        }
        
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0xC0...0xFF: // includes 0xD7/0xF7, which are 'Ч'/'ч' in CP1251
                wordLength += 1
                wordSupplement += 1
            case 0x41...0x5A, 0x61...0x7A:
                wordLength += 1
            case 0x100...:
                return false
            default:
                endWord()
            }
        }
        endWord()
        return mojibakeWords > 0 && mojibakeWords >= accentedWords
    }

    static func isMostlyCyrillic(_ string: String) -> Bool {
        var cyrillic = 0
        var otherLetters = 0
        for scalar in string.unicodeScalars where CharacterSet.letters.contains(scalar) {
            if (0x0400...0x04FF).contains(scalar.value) {
                cyrillic += 1
            } else if scalar.value > 0x7F {
                otherLetters += 1
            }
        }
        return cyrillic > 0 && cyrillic >= otherLetters * 4
    }
}
