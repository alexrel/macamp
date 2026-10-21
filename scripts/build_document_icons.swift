// Builds MacAmp's document icons (Preferences ▸ Setup ▸ File types) from the original Winamp 2.95 icons.
//
//   swiftc scripts/build_document_icons.swift -o /tmp/build_document_icons && /tmp/build_document_icons
//
// Input:  MacAmp/Resources/DocumentIcons/Source/winamp-icon-<ID>.png — the 256-color 32 px frame of each
//         RT_GROUP_ICON in winamp.exe 2.95 (decoded to RGBA). Use these, not the .ico files: ImageIO returns
//         the frames of a multi-frame .ico in its own order and easily hands out the 16-color one instead.
// Output: Choices/winamp-icon-<ID>.icns for every source, plus WinampAudioFile.icns (#131),
//         WinampPlaylist.icns (#102) and WinampSkin.icns (#164) as the Info.plist defaults.
import Cocoa

let root = FileManager.default.currentDirectoryPath
let dir = "\(root)/MacAmp/Resources/DocumentIcons"
let sources = try! FileManager.default.contentsOfDirectory(atPath: "\(dir)/Source").filter { $0.hasSuffix(".png") }.sorted()

func context(_ px: Int) -> CGContext {
    CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func makeIcns(from image: CGImage, to icns: String) {
    let set = NSTemporaryDirectory() + UUID().uuidString + ".iconset"
    try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    func png(_ px: Int, _ name: String) {
        let c = context(px)
        // Shrinking (16 px) is smoothed; enlarging keeps the pixel art crisp
        c.interpolationQuality = px < image.width ? .high : .none
        c.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
        try! NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "\(set)/\(name).png"))
    }
    for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
        png(pt * scale, scale == 1 ? "icon_\(pt)x\(pt)" : "icon_\(pt)x\(pt)@2x")
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", set, "-o", icns]
    try! iconutil.run(); iconutil.waitUntilExit()
    precondition(iconutil.terminationStatus == 0, "iconutil failed for \(icns)")
    try? FileManager.default.removeItem(atPath: set)
}

for file in sources {
    let source = CGImageSourceCreateWithData(try! Data(contentsOf: URL(fileURLWithPath: "\(dir)/Source/\(file)")) as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    makeIcns(from: image, to: "\(dir)/Choices/\(file.replacingOccurrences(of: ".png", with: ".icns"))")
}
for (id, target) in [(131, "WinampAudioFile"), (102, "WinampPlaylist"), (164, "WinampSkin")] {
    try? FileManager.default.removeItem(atPath: "\(dir)/\(target).icns")
    try! FileManager.default.copyItem(atPath: "\(dir)/Choices/winamp-icon-\(id).icns", toPath: "\(dir)/\(target).icns")
}
print("Built \(sources.count) document icons in \(dir)")
