import Foundation
import CoreGraphics
import AppKit
import ImageIO

public class SkinLoader {
    public static let shared = SkinLoader()
    
    private init() {}
    
    /// Loads a skin from either a .wsz/.zip file or a directory containing skin files.
    public func loadSkin(from url: URL) -> Skin? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return nil
        }
        
        let rootDir: URL
        if isDir.boolValue {
            rootDir = url
        } else {
            // Unpack archive to cache directory
            guard let unpackedDir = unpackArchive(at: url) else {
                return nil
            }
            rootDir = unpackedDir
        }
        
        let skinDir = resolveSkinDirectory(from: rootDir)
        let skinName = url.deletingPathExtension().lastPathComponent
        let skin = Skin(name: skinName)
        
        loadBitmaps(from: skinDir, into: skin)
        loadPlaylistStyle(from: skinDir, into: skin)
        loadVisualizerColors(from: skinDir, into: skin)
        loadRegion(from: skinDir, into: skin)
        loadCursors(from: skinDir, into: skin)
        
        return skin
    }
    
    /// Loads Windows cursor files (*.CUR); like Winamp, every cursor the skin lacks is Winamp's built-in one.
    /// Animated *.ANI cursors are not supported and get the built-in cursor too.
    private func loadCursors(from dir: URL, into skin: Skin) {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension.uppercased() == "CUR" {
            guard let data = try? Data(contentsOf: file), let cursor = SkinLoader.makeCursor(fromCUR: data) else { continue }
            skin.cursors[file.deletingPathExtension().lastPathComponent.uppercased()] = cursor
        }
        skin.cursors = BuiltInCursors.complete(skin.cursors)
    }
    
    /// Decodes a .CUR file (ImageIO reads the bitmap; the hotspot comes from the first ICONDIRENTRY).
    static func makeCursor(fromCUR data: Data) -> NSCursor? {
        guard data.count > 22, data[2] == 2, // ICONDIR.type 2 = cursor
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let hotX = CGFloat(Int(data[10]) | Int(data[11]) << 8)
        let hotY = CGFloat(Int(data[12]) | Int(data[13]) << 8)
        let size = NSSize(width: image.width, height: image.height)
        let hotSpot = NSPoint(x: min(hotX, size.width - 1), y: min(hotY, size.height - 1))
        return NSCursor(image: NSImage(cgImage: image, size: size), hotSpot: hotSpot)
    }
    
    /// Resolves the actual folder containing the skin assets.
    /// Handles archives where assets were packed inside a subdirectory (e.g. intec/Main.bmp).
    private func resolveSkinDirectory(from dir: URL) -> URL {
        let fm = FileManager.default
        let keySheets = Set(["MAIN", "TITLEBAR", "PLEDIT", "EQMAIN"])
        
        // 1. Direct check in dir
        if let directFiles = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let hasDirectSheet = directFiles.contains {
                let stem = $0.deletingPathExtension().lastPathComponent.uppercased()
                let ext = $0.pathExtension.uppercased()
                return keySheets.contains(stem) && (ext == "BMP" || ext == "PNG")
            }
            if hasDirectSheet {
                return dir
            }
        }
        
        // 2. Search subdirectories for MAIN.BMP first
        if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let stem = fileURL.deletingPathExtension().lastPathComponent.uppercased()
                let ext = fileURL.pathExtension.uppercased()
                if stem == "MAIN" && (ext == "BMP" || ext == "PNG") {
                    return fileURL.deletingLastPathComponent()
                }
            }
        }
        
        // 3. Fallback: Search subdirectories for any keySheet
        if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let stem = fileURL.deletingPathExtension().lastPathComponent.uppercased()
                let ext = fileURL.pathExtension.uppercased()
                if keySheets.contains(stem) && (ext == "BMP" || ext == "PNG") {
                    return fileURL.deletingLastPathComponent()
                }
            }
        }
        
        return dir
    }
    
    // MARK: - Archive Extraction
    private func unpackArchive(at url: URL) -> URL? {
        let fileManager = FileManager.default
        let skinName = url.deletingPathExtension().lastPathComponent
        let destDir = fileManager.temporaryDirectory.appendingPathComponent("MacAmp_Skins").appendingPathComponent(skinName)
        
        try? fileManager.removeItem(at: destDir)
        try? fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // 1. Try /usr/bin/unzip first (handles DOS/Windows ZIP read-only folder attributes properly)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", "-o", url.path, "-d", destDir.path]
        
        if (try? unzip.run()) != nil {
            unzip.waitUntilExit()
            if unzip.terminationStatus == 0 {
                ensureReadablePermissions(at: destDir)
                return destDir
            }
        }
        
        // 2. Fallback to /usr/bin/ditto
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", url.path, destDir.path]
        
        do {
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { return nil }
            ensureReadablePermissions(at: destDir)
            return destDir
        } catch {
            print("Failed to extract skin archive: \(error)")
            return nil
        }
    }
    
    /// Ensures all extracted files and folders have read/write/traverse permissions,
    /// fixing DOS/FAT archives where folders lack execute bits (e.g. reptal~1.wsz).
    private func ensureReadablePermissions(at dir: URL) {
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["-R", "u+rwX", dir.path]
        try? chmod.run()
        chmod.waitUntilExit()
    }
    
    // MARK: - Bitmap Loading
    private let recognizedSheets = [
        "MAIN", "TITLEBAR", "CBUTTONS", "VOLUME", "BALANCE", "POSBAR",
        "PLAYPAUS", "NUMBERS", "NUMS_EX", "TEXT", "MONOSTER", "SHUFREP",
        "EQMAIN", "EQ_EX", "PLEDIT", "GEN", "GENEX", "MB", "VIDEO"
    ]
    
    private func loadBitmaps(from dir: URL, into skin: Skin) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        
        for sheetName in recognizedSheets {
            // Match sheetName with .bmp or .png extension (case-insensitive)
            if let fileURL = files.first(where: {
                let stem = $0.deletingPathExtension().lastPathComponent.uppercased()
                let ext = $0.pathExtension.uppercased()
                return stem == sheetName && (ext == "BMP" || ext == "PNG")
            }) {
                if let cgImage = loadCGImage(from: fileURL) {
                    skin.images[sheetName] = cgImage
                }
            }
        }
    }
    
    private func loadCGImage(from url: URL) -> CGImage? {
        // RLE-compressed BMPs: our own decoder (ImageIO shifts rows after skip codes)
        if let data = try? Data(contentsOf: url), let image = BMPDecoder.decodeRLE(data) {
            return processChromaKey(image)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return processChromaKey(image)
    }
    
    /// Converts pure magenta (RGB 255, 0, 255) pixels to transparent (alpha = 0).
    /// Used by classic Winamp 2.x skins for transparent button and display areas.
    private func processChromaKey(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        let colorSpace = Skin.colorSpace
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return image
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var hasChroma = false
        // 32-bit big-endian RGBA: byte 0=R, 1=G, 2=B, 3=A
        for i in stride(from: 0, to: rawData.count, by: 4) {
            let r = rawData[i]
            let g = rawData[i + 1]
            let b = rawData[i + 2]
            
            // Match pure magenta (255, 0, 255) and classic cyan (0, 198, 255 / 0, 255, 255)
            let isMagenta = (r >= 250 && g <= 5 && b >= 250)
            let isCyan = (r <= 10 && (abs(Int(g) - 198) <= 10 || g >= 245) && b >= 245)
            if isMagenta || isCyan {
                rawData[i] = 0
                rawData[i + 1] = 0
                rawData[i + 2] = 0
                rawData[i + 3] = 0
                hasChroma = true
            }
        }
        
        if !hasChroma {
            return image
        }
        
        return context.makeImage() ?? image
    }
    
    // MARK: - REGION.TXT Parsing
    private func loadRegion(from dir: URL, into skin: Skin) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              let fileURL = files.first(where: { $0.lastPathComponent.uppercased() == "REGION.TXT" }),
              let content = (try? String(contentsOf: fileURL, encoding: .isoLatin1)) ?? (try? String(contentsOf: fileURL, encoding: .utf8)) else {
            return
        }
        skin.region = RegionParser.parse(text: content)
    }
    
    // MARK: - PLEDIT.TXT Parsing
    private func loadPlaylistStyle(from dir: URL, into skin: Skin) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              let fileURL = files.first(where: { $0.lastPathComponent.uppercased() == "PLEDIT.TXT" }),
              let content = try? String(contentsOf: fileURL, encoding: .isoLatin1) else {
            return
        }
        
        var style = PlaylistStyle()
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("["), trimmed.contains("=") else { continue }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            
            let key = parts[0].uppercased()
            let val = parts[1]
            
            switch key {
            case "NORMAL":
                if let color = parseHexColor(val) { style.normalColor = color }
            case "CURRENT":
                if let color = parseHexColor(val) { style.currentColor = color }
            case "NORMALBG":
                if let color = parseHexColor(val) { style.normalBGColor = color }
            case "SELECTEDBG":
                if let color = parseHexColor(val) { style.selectedBGColor = color }
            case "MBFG":
                if let color = parseHexColor(val) { style.minibrowserText = color }
            case "MBBG":
                if let color = parseHexColor(val) { style.minibrowserBackground = color }
            case "FONT":
                style.fontName = val
            default:
                break
            }
        }
        
        skin.playlistStyle = style
    }
    
    private func parseHexColor(_ hex: String) -> NSColor? {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if cleanHex.count == 6 {
            var int: UInt64 = 0
            if Scanner(string: cleanHex).scanHexInt64(&int) {
                let r = CGFloat((int >> 16) & 0xFF) / 255.0
                let g = CGFloat((int >> 8) & 0xFF) / 255.0
                let b = CGFloat(int & 0xFF) / 255.0
                return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
            }
        }
        return nil
    }
    
    // MARK: - VISCOLOR.TXT Parsing
    private func loadVisualizerColors(from dir: URL, into skin: Skin) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              let fileURL = files.first(where: { $0.lastPathComponent.uppercased() == "VISCOLOR.TXT" }),
              let content = try? String(contentsOf: fileURL, encoding: .isoLatin1) else {
            return
        }
        
        var parsedColors: [NSColor] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let cleanLine = line.components(separatedBy: "//")[0].trimmingCharacters(in: .whitespaces)
            guard !cleanLine.isEmpty else { continue }
            
            let components = cleanLine.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if components.count >= 3 {
                let r = CGFloat(max(0, min(255, components[0]))) / 255.0
                let g = CGFloat(max(0, min(255, components[1]))) / 255.0
                let b = CGFloat(max(0, min(255, components[2]))) / 255.0
                parsedColors.append(NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0))
            }
        }
        
        if parsedColors.count >= 24 {
            skin.visualizerColors.colors = Array(parsedColors.prefix(24))
        }
    }
}
