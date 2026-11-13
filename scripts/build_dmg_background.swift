// Draws the background of MacAmp's DMG window: a pixel arrow from the app icon to the Applications link and a
// hint line under them, as a 1x+2x TIFF. ./build.sh dmg runs it and passes the layout, so it lives in one place.
//
//   swift scripts/build_dmg_background.swift <out.tiff> <width> <height> <arrow center x> <arrow center y> <hint y> <hint>
//
// Coordinates are Finder window points from the top left, like the icon positions in build.sh.
import Cocoa

let args = CommandLine.arguments
precondition(args.count == 8, "usage: build_dmg_background.swift <out.tiff> <width> <height> <arrow x> <arrow y> <hint y> <hint>")
let output = args[1]
let (width, height, arrowX, arrowY, hintY) = (Int(args[2])!, Int(args[3])!, Int(args[4])!, Int(args[5])!, Int(args[6])!)
let hint = args[7]

let background = NSColor(srgbRed: 0.94, green: 0.94, blue: 0.94, alpha: 1)
let ink = NSColor(srgbRed: 0.33, green: 0.33, blue: 0.33, alpha: 1)
let arrowColor = NSColor(srgbRed: 0.62, green: 0.62, blue: 0.62, alpha: 1)
// Winamp 2.95's dialogs are Tahoma; macOS ships it in Supplemental fonts
let hintFont = NSFont(name: "Tahoma", size: 13) ?? NSFont.systemFont(ofSize: 13)
// Arrow in cells of `cell` points, drawn without smoothing so it stays pixel art at both scales
let (cell, shaftCells, headCells, shaftHalf) = (4, 8, 5, 1)

func draw(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height) // 72 dpi at 1x, 144 dpi at 2x; the context below draws in points
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.translateBy(x: 0, y: CGFloat(height)) // top-left origin, as Finder counts
    context.cgContext.scaleBy(x: 1, y: -1)

    background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    context.shouldAntialias = false
    arrowColor.setFill()
    let columns = shaftCells + headCells
    let left = arrowX - columns * cell / 2, top = arrowY - (headCells - 1) * cell - cell / 2
    for column in 0..<columns {
        let half = column < shaftCells ? shaftHalf : headCells - 1 - (column - shaftCells)
        for row in (headCells - 1 - half)...(headCells - 1 + half) {
            NSRect(x: left + column * cell, y: top + row * cell, width: cell, height: cell).fill()
        }
    }
    context.shouldAntialias = true

    let flipped = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    NSGraphicsContext.current = flipped
    let text = NSAttributedString(string: hint, attributes: [.font: hintFont, .foregroundColor: ink])
    let size = text.size()
    text.draw(at: NSPoint(x: (CGFloat(width) - size.width) / 2, y: CGFloat(hintY) - size.height / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// One TIFF with both representations, each sized in points, so Finder picks the 2x one on Retina
let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [draw(scale: 1), draw(scale: 2)], using: .lzw, factor: 0)!
try! tiff.write(to: URL(fileURLWithPath: output))
