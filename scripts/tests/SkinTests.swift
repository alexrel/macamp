import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func skinTests() {
    testGroup("Skin tiles stay opaque at fractional scale") {
        func bitmap(width: Int, height: Int) -> CGContext {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        let tile = bitmap(width: 25, height: 29)
        tile.setFillColor(CGColor(gray: 0.4, alpha: 1))
        tile.fill(CGRect(x: 0, y: 0, width: 25, height: 29))

        let sprite = tile.makeImage()!
        let gen = GenWindowFrameView(title: "", content: NSView())
        // 3.02: the joint at 25 lands on 75.5, inside a pixel
        for (crop, scale) in [(false, 226.0 / 75), (true, 226.0 / 75), (false, 3.02), (true, 3.02)] {
            let frame = bitmap(width: 226, height: 88)
            frame.clear(CGRect(x: 0, y: 0, width: 226, height: 88))
            frame.setAllowsAntialiasing(true)
            frame.setShouldAntialias(true)
            frame.interpolationQuality = .none
            frame.scaleBy(x: scale, y: 88.0 / 29)
            if crop {
                gen.tile(frame, sprite, from: 0, to: 75, y: 0, tileWidth: 25, height: 29)
            } else {
                frame.drawTiledHorizontal(image: sprite, from: 0, to: 75, y: 0, width: 25, height: 29)
            }

            let pixels = frame.data!.assumingMemoryBound(to: UInt8.self)
            let scanline = pixels.advanced(by: 44 * frame.bytesPerRow)
            assertTrue((1..<225).allSatisfy { scanline[$0 * 4 + 3] == 255 },
                       "Opaque skin slices meet without translucent seams (clipping: \(crop), scale \(scale))")
        }
    }

    // 20. Skin cursors, visualizer options, playback options, playlist MISC
    testGroup("Skin Cursors") {
        // Base skin ships 8 .CUR files; they decode with the hotspot from the CUR header
        _ = SkinManager.shared.currentSkin
        SkinManager.shared.resetToBaseSkin()
        let cursors = SkinManager.shared.currentSkin?.cursors ?? [:]
        assertTrue(cursors.count >= 8, "Base skin cursors loaded (\(cursors.keys.sorted()))")
        for name in ["TITLEBAR", "CLOSE", "POSBAR", "VOLBAL", "EQSLID", "EQTITLE", "MAINMENU", "PSIZE"] {
            assertTrue(cursors[name] != nil, "Cursor \(name) present")
        }
        assertEqual(cursors["TITLEBAR"]?.image.size, NSSize(width: 32, height: 32), "Cursor image is 32x32")
        assertTrue(SkinLoader.makeCursor(fromCUR: Data([0, 0, 1, 0, 1, 0] + Array(repeating: 0, count: 30))) == nil, "ICO (type 1) data is not accepted as a cursor")

        // Skins without *.cur files get winamp.exe's built-in cursors (Winamp 2.95 behavior)
        assertEqual(BuiltInCursors.cursors.keys.sorted(), [205, 206, 207, 208, 209, 210], "All 6 built-in cursors decode")
        for cursor in BuiltInCursors.cursors.values {
            assertEqual(cursor.image.size, NSSize(width: 32, height: 32), "Built-in cursor is 32x32")
            assertEqual(cursor.hotSpot, .zero, "Built-in cursor hotspot is the arrow tip")
        }
        let builtIn = BuiltInCursors.complete([:])
        let usedNames = ["CLOSE", "MIN", "WINBUT", "MAINMENU", "POSBAR", "VOLBAL", "SONGNAME", "TITLEBAR", "NORMAL",
                         "WSCLOSE", "WSMIN", "WSWINBUT", "WSPOSBAR", "WSNORMAL", "PCLOSE", "PWINBUT", "PTBAR", "PNORMAL",
                         "PVSCROLL", "PSIZE", "PWSNORM", "PWSSIZE", "EQCLOSE", "EQSLID", "EQTITLE", "EQNORMAL"]
        for name in usedNames {
            assertTrue(builtIn[name] != nil, "Cursor \(name) has a built-in fallback")
        }
        assertTrue(builtIn["PSIZE"] === BuiltInCursors.cursors[210], "PSize.cur falls back to the resize cursor")
        assertTrue(builtIn["EQSLID"] === BuiltInCursors.cursors[209], "EQSlid.cur falls back to the vertical cursor")
        assertTrue(builtIn["WSCLOSE"] === BuiltInCursors.cursors[207], "Windowshade close uses the close cursor")
        let skinClose = NSCursor.pointingHand
        let mixed = BuiltInCursors.complete(["CLOSE": skinClose])
        assertTrue(mixed["CLOSE"] === skinClose, "A skin's own cursor wins over the built-in one")
        assertTrue(mixed["WSCLOSE"] === skinClose, "Windowshade close reuses the skin's Close.cur like Winamp 2.95")
        assertTrue(mixed["TITLEBAR"] === BuiltInCursors.cursors[205], "Missing skin cursors still get built-ins")
        assertTrue(cursors["PVSCROLL"] != nil && cursors["SONGNAME"] != nil, "Loaded skins are completed with built-ins")

        // Cursors follow the mouse in every window, key or not (tracking area on the window's root view)
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: true)
        let hosted = MainWindowView()
        hosted.frame = NSRect(x: 0, y: 0, width: 275, height: 116)
        host.contentView = hosted
        hosted.applySkinCursorNames()
        hosted.updateTrackingAreas()
        assertTrue(hosted.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.mouseMoved) },
                   "Root view tracks the mouse even when the window isn't key")
        assertTrue(hosted.closeButton.trackingAreas.isEmpty, "Child controls don't add their own cursor tracking")
        func cursorAt(_ view: NSView, _ local: NSPoint) -> NSCursor? {
            hosted.skinCursor(atWindowPoint: view.convert(local, to: nil))
        }
        let closeFrame = hosted.closeButton.bounds
        assertTrue(cursorAt(hosted.closeButton, NSPoint(x: closeFrame.midX, y: closeFrame.midY)) === cursors["CLOSE"], "Close button shows CLOSE")
        assertTrue(cursorAt(hosted, NSPoint(x: 100, y: 6)) === cursors["TITLEBAR"], "Title bar shows TITLEBAR")
        let seekFrame = hosted.seekSlider.bounds
        assertTrue(cursorAt(hosted.seekSlider, NSPoint(x: seekFrame.midX, y: seekFrame.midY)) === cursors["POSBAR"], "Seek bar shows POSBAR")

        let main = MainWindowView()
        main.applySkinCursorNames()
        assertEqual(main.closeButton.skinCursorName, "CLOSE", "Close button cursor")
        assertEqual(main.seekSlider.skinCursorName, "POSBAR", "Seek bar cursor")
        assertEqual(main.marquee.skinCursorName, "SONGNAME", "Marquee cursor")
        assertEqual(main.skinCursorZones().map(\.name), ["TITLEBAR", "NORMAL"], "Main window zones")
        // Library / Video / Minibrowser / Studio frame: the close button inside the title bar has the close cursor, not the title's
        let gen = GenWindowFrameView(title: "", content: NSView())
        let onClose = NSPoint(x: gen.closeRect.midX, y: gen.closeRect.midY)
        assertEqual(gen.skinCursorZones().last { $0.rect.contains(onClose) }?.name, "CLOSE", "Close button zone wins over TITLEBAR")
        assertEqual(gen.skinCursorZones().last { $0.rect.contains(NSPoint(x: 100, y: 10)) }?.name, "TITLEBAR", "The rest of the title bar")
        main.isShadeMode = true
        assertEqual(main.closeButton.skinCursorName, "WSCLOSE", "Windowshade close cursor")
        assertEqual(main.skinCursorZones().map(\.name), ["WSNORMAL"], "Windowshade zone")

        let pl = PlaylistWindowView(playlist: PlaylistModel())
        pl.frame = NSRect(x: 0, y: 0, width: 275, height: 232)
        pl.bounds = pl.frame
        let zones = pl.skinCursorZones()
        assertEqual(Set(zones.map(\.name)), ["PTBAR", "PNORMAL", "PVSCROLL", "PSIZE"], "Playlist zones")
        for i in zones.indices { for j in zones.indices where i < j {
            assertTrue(!zones[i].rect.intersects(zones[j].rect), "Playlist cursor zones don't overlap: \(zones[i].name) / \(zones[j].name)")
        }}
    }

    testGroup("Skin sheets smaller than the standard") {
        // SFCommandSkin.wsz: MAIN.BMP is 275x115, one row short; the main window showed the base skin instead
        func solid(_ width: Int, _ height: Int) -> CGImage {
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return ctx.makeImage()!
        }
        let skin = Skin(name: "short")
        skin.images["MAIN"] = solid(275, 115)
        guard let main = skin.image(for: SpriteCatalog.mainWindowBackground) else { throw NSError(domain: "test", code: 1) }
        assertEqual([main.width, main.height], [275, 116], "The sprite keeps its standard size (no stretching)")
        assertTrue(main.colorSpace?.name == CGColorSpace.sRGB, "...and the colour space of every other skin bitmap")
        let rep = NSBitmapImageRep(cgImage: main)
        func alpha(_ y: Int) -> Int { var p = [Int](repeating: 0, count: 4); rep.getPixel(&p, atX: 10, y: y); return p[3] }
        assertEqual([alpha(0), alpha(114), alpha(115)], [255, 255, 0], "The skin's 115 rows are drawn from the top, the missing row is transparent")
        skin.images["MAIN"] = solid(275, 116)
        assertEqual(skin.image(for: SpriteCatalog.mainWindowBackground)?.height, 116, "A full-size sheet is cut as before")
        assertTrue(skin.image(for: SpriteCatalog.mainShadeBg) == nil, "A sheet the skin lacks still comes from the base skin")

        // The same skin has NUMS_EX.BMP (108x8): Winamp takes the time digits from it, not from NUMBERS.BMP
        let old = Skin(name: "numbers only")
        old.images["NUMBERS"] = solid(99, 13)
        assertEqual(old.image(for: SpriteCatalog.digit(7))?.height, 13, "Without NUMS_EX the digits come from NUMBERS")
        skin.images["NUMBERS"] = solid(99, 13)
        let ex = CGContext(data: nil, width: 108, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ex.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ex.fill(CGRect(x: 0, y: 0, width: 108, height: 8))
        ex.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ex.fill(CGRect(x: 99, y: 0, width: 9, height: 8)) // the minus cell
        skin.images["NUMS_EX"] = ex.makeImage()!
        func pixel(_ slice: SpriteSlice) -> [Int] {
            guard let image = skin.image(for: slice) else { return [0, 0, 0, 0] }
            var p = [Int](repeating: 0, count: 4); NSBitmapImageRep(cgImage: image).getPixel(&p, atX: 0, y: 0); return p
        }
        func isGreen(_ slice: SpriteSlice) -> Bool { let p = pixel(slice); return p.count == 4 && p[1] > 200 && p[0] < 50 } // colour-managed, not exact
        assertTrue(isGreen(SpriteCatalog.digit(7)), "Digits come from NUMS_EX when the skin has it")
        assertTrue(!isGreen(SpriteCatalog.minusSign) && pixel(SpriteCatalog.minusSign)[0] > 200, "The minus comes from NUMS_EX's own minus cell")
        assertTrue(isGreen(SpriteCatalog.noMinusSign), "No minus: the blank cell")
    }

    testGroup("RLE Skin Bitmaps (GEN.BMP rows)") {
        // ImageIO shifted rows after RLE skip codes; MacAmp decodes RLE8 / RLE4 itself
        let wsz = repositoryRoot.appendingPathComponent("MacAmp/Resources/base-2.91.wsz")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/rle", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", "-o", wsz.path, "GEN.BMP", "-d", dir.path]
        try unzip.run(); unzip.waitUntilExit()
        let data = try Data(contentsOf: dir.appendingPathComponent("GEN.BMP"))
        guard let image = BMPDecoder.decodeRLE(data) else { throw NSError(domain: "test", code: 1) }
        assertEqual(image.width, 194, "GEN.BMP width")

        // One colour space for every sheet, however it was decoded: RLE (above), ImageIO, ImageIO + transparent colour.
        // SFCommandSkin.wsz: MAIN.BMP has a cyan patch and came out in device RGB, the digits and the title font in sRGB
        func bmp24(_ pixels: [[UInt8]]) -> Data { // one row, BGR
            var d = Data([0x42, 0x4D]); let row = (pixels.count * 3 + 3) & ~3
            func le(_ v: Int, _ n: Int) { for i in 0..<n { d.append(UInt8((v >> (8 * i)) & 0xFF)) } }
            le(54 + row, 4); le(0, 4); le(54, 4); le(40, 4); le(pixels.count, 4); le(1, 4); le(1, 2); le(24, 2)
            le(0, 4); le(row, 4); le(2835, 4); le(2835, 4); le(0, 4); le(0, 4)
            for p in pixels { d.append(contentsOf: p) }
            d.append(contentsOf: [UInt8](repeating: 0, count: row - pixels.count * 3))
            return d
        }
        let mixed = dir.appendingPathComponent("mixed", isDirectory: true)
        try FileManager.default.createDirectory(at: mixed, withIntermediateDirectories: true)
        let orange: [UInt8] = [0x00, 0x61, 0xC1], magenta: [UInt8] = [0xFF, 0x00, 0xFF]
        try bmp24([orange, magenta, orange, orange]).write(to: mixed.appendingPathComponent("MAIN.BMP"))
        try bmp24([orange, orange, orange, orange]).write(to: mixed.appendingPathComponent("TEXT.BMP"))
        try data.write(to: mixed.appendingPathComponent("GEN.BMP"))
        guard let loaded = SkinLoader.shared.loadSkin(from: mixed) else { throw NSError(domain: "test", code: 2) }
        assertEqual(Set(loaded.images.keys), ["MAIN", "TEXT", "GEN"], "All three sheets load")
        assertTrue(loaded.images.values.allSatisfy { $0.colorSpace?.name == CGColorSpace.sRGB }, "Every sheet is sRGB")
        func first(_ key: String) -> [Int] {
            var p = [Int](repeating: 0, count: 4); NSBitmapImageRep(cgImage: loaded.images[key]!).getPixel(&p, atX: 0, y: 0); return Array(p.prefix(3))
        }
        assertEqual(first("MAIN"), first("TEXT"), "The same orange from a sheet with a transparent colour and from one without")
        var keyed = [Int](repeating: 0, count: 4); NSBitmapImageRep(cgImage: loaded.images["MAIN"]!).getPixel(&keyed, atX: 1, y: 0)
        assertEqual(keyed[3], 0, "Magenta is still transparent")
        let rep = NSBitmapImageRep(cgImage: image)
        func rgb(_ x: Int, _ y: Int) -> [Int] { var p = [Int](repeating: 0, count: 4); rep.getPixel(&p, atX: x, y: y); return Array(p.prefix(3)) }
        let cyan = [0, 198, 255]
        assertTrue(rgb(130, 85) != cyan && rgb(130, 85) != [0, 0, 0], "Bottom fill's last row is at y 85 (\(rgb(130, 85)))")
        assertEqual(rgb(3, 94), [41, 41, 64], "Active letters end at y 94 (frame colour)")
        assertEqual(rgb(3, 102), [41, 41, 64], "Inactive letters end at y 102")
        assertEqual(rgb(3, 95), rgb(193, 0), "Gap row between the letter strips is background")
        assertTrue(BMPDecoder.decodeRLE(Data("not a bitmap".utf8)) == nil, "Non-RLE data goes to ImageIO")
    }
}
