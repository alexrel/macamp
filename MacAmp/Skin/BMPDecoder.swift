import CoreGraphics
import Foundation

/// Decoder for run-length encoded BMPs (BI_RLE8 / BI_RLE4), common in classic Winamp skins.
/// ImageIO misplaces rows after the "delta" and "end of line" escapes those files use to skip unused
/// areas (in the base skin's GEN.BMP the letters and bottom bar came out shifted), so MacAmp decodes
/// these itself. Uncompressed BMPs still go through ImageIO.
enum BMPDecoder {
    /// Returns nil for anything that isn't an RLE BMP (the caller then uses ImageIO).
    static func decodeRLE(_ data: Data) -> CGImage? {
        let bytes = [UInt8](data)
        guard bytes.count > 54, bytes[0] == 0x42, bytes[1] == 0x4D else { return nil } // "BM"
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        func i32(_ o: Int) -> Int { Int(Int32(bitPattern: UInt32(u32(o)))) }
        let pixelOffset = u32(10)
        let headerSize = u32(14)
        let width = i32(18)
        let rawHeight = i32(22)
        let bpp = u16(28)
        let compression = u32(30)
        guard (compression == 1 && bpp == 8) || (compression == 2 && bpp == 4),
              width > 0, rawHeight != 0, width < 8192, abs(rawHeight) < 8192 else { return nil }
        let height = abs(rawHeight)
        let topDown = rawHeight < 0
        let colors = u32(46) == 0 ? 1 << bpp : min(u32(46), 256)
        let paletteStart = 14 + headerSize
        guard paletteStart + colors * 4 <= bytes.count, pixelOffset < bytes.count else { return nil }
        let palette: [(UInt8, UInt8, UInt8)] = (0..<colors).map {
            let o = paletteStart + $0 * 4
            return (bytes[o + 2], bytes[o + 1], bytes[o]) // stored as B, G, R, 0
        }

        // Palette indices, top row first; skipped pixels keep index 0
        var indices = [UInt8](repeating: 0, count: width * height)
        var x = 0, row = 0 // row counted from the bottom of the image (BMP order)
        func put(_ index: UInt8) {
            if x < width, row < height {
                let y = topDown ? row : height - 1 - row
                indices[y * width + x] = index
            }
            x += 1
        }
        var p = pixelOffset
        while p + 1 < bytes.count {
            let count = Int(bytes[p]), value = bytes[p + 1]
            p += 2
            if count > 0 { // encoded run: `count` pixels of `value`
                for i in 0..<count {
                    put(compression == 1 ? value : (i % 2 == 0 ? value >> 4 : value & 0x0F))
                }
                continue
            }
            switch value {
            case 0: x = 0; row += 1                       // end of line
            case 1: p = bytes.count                       // end of bitmap
            case 2:                                       // delta: skip right / up
                guard p + 1 < bytes.count else { p = bytes.count; break }
                x += Int(bytes[p]); row += Int(bytes[p + 1])
                p += 2
            default:                                      // absolute run of `value` pixels, padded to 16 bits
                let n = Int(value)
                let byteCount = compression == 1 ? n : (n + 1) / 2
                guard p + byteCount <= bytes.count else { p = bytes.count; break }
                for i in 0..<n {
                    if compression == 1 {
                        put(bytes[p + i])
                    } else {
                        let b = bytes[p + i / 2]
                        put(i % 2 == 0 ? b >> 4 : b & 0x0F)
                    }
                }
                p += byteCount + (byteCount & 1)
            }
        }

        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for (i, index) in indices.enumerated() {
            let c = Int(index) < palette.count ? palette[Int(index)] : (0, 0, 0)
            rgba[i * 4] = c.0; rgba[i * 4 + 1] = c.1; rgba[i * 4 + 2] = c.2
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: Skin.colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
