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
        for crop in [false, true] {
            let frame = bitmap(width: 226, height: 88)
            frame.clear(CGRect(x: 0, y: 0, width: 226, height: 88))
            frame.setAllowsAntialiasing(true)
            frame.setShouldAntialias(true)
            frame.interpolationQuality = .none
            frame.scaleBy(x: 226.0 / 75, y: 88.0 / 29)
            if crop {
                gen.tile(frame, sprite, from: 0, to: 75, y: 0, tileWidth: 25, height: 29)
            } else {
                frame.drawTiledHorizontal(image: sprite, from: 0, to: 75, y: 0, width: 25, height: 29)
            }

            let pixels = frame.data!.assumingMemoryBound(to: UInt8.self)
            let scanline = pixels.advanced(by: 44 * frame.bytesPerRow)
            assertTrue((1..<225).allSatisfy { scanline[$0 * 4 + 3] == 255 },
                       "Opaque skin slices meet without translucent seams (clipping: \(crop))")
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
