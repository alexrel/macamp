import SwiftUI
import AppKit

public enum AboutTab: String, CaseIterable, Identifiable {
    case winamp = "Winamp"
    case credits = "Credits"
    case shortcuts = "Keyboard shortcuts"
    case history = "Version history"
    
    public var id: String { rawValue }
}

public struct AboutView: View {
    static let bannerSize = CGSize(width: AboutBannerWarp.pointWidth, height: AboutBannerWarp.pointHeight)
    /// The banner plus the frame around the page, and the three lines under it
    static let size = CGSize(width: bannerSize.width + 18, height: bannerSize.height + 92)
    @State private var selectedTab: AboutTab = .winamp
    public var onClose: (() -> Void)?
    
    public init(initialTab: AboutTab = .winamp, onClose: (() -> Void)? = nil) {
        _selectedTab = State(initialValue: initialTab)
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Classic Win32 property sheet
            Win32TabView(tabs: AboutTab.allCases, selectedTab: $selectedTab) {
                switch selectedTab {
                case .winamp:
                    winampTabContent
                case .credits:
                    creditsTabContent
                case .shortcuts:
                    shortcutsTabContent
                case .history:
                    historyTabContent
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, selectedTab == .winamp ? 4 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Show bottom Close button only on information tabs
            if selectedTab != .winamp {
                HStack {
                    Spacer()
                    Win32Button("Close", width: 75, height: 23) {
                        onClose?()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .frame(width: AboutView.size.width, height: AboutView.size.height)
        .background(Win32Colors.dialogBg)
        .onExitCommand {
            onClose?()
        }
    }
    
    // MARK: - Tab 1: Winamp Iconic Llama & Logo
    private var winampTabContent: some View {
        VStack(spacing: 0) {
            // Black Art Banner with extracted classic Nullsoft logo
            AboutBannerView()
                .frame(width: AboutView.bannerSize.width, height: AboutView.bannerSize.height)
            .clipped()
            .padding(.top, 4)
            .frame(maxWidth: .infinity) // the tab's content sits top-left: centre the banner in the page
            
            Spacer(minLength: 4)
            
            VStack(spacing: 3) {
                Text("Copyright © 1997-2003 Nullsoft, Inc.")
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                
                Text("MacAmp v\(AppConstants.App.version) (macOS), based on \(AppConstants.App.basedOn)")
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                
                HStack(spacing: 4) {
                    Text("Visit")
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.text)
                    
                    // 2.95 sent you to winamp.com; MacAmp's updates live on its own page
                    Link("alexrel.com/macamp", destination: AppConstants.App.website)
                        .font(.system(size: 11))
                        .underline()
                    
                    Text("for updates.")
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.text)
                }
            }
            .padding(.bottom, 8)
        }
        .onTapGesture {
            // Clicking the banner or dialog dismisses it, just like classic Winamp
            onClose?()
        }
    }
    
    // MARK: - Tab 2: Authentic Nullsoft & MacAmp Credits
    private var creditsTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("MacAmp \(AppConstants.App.version) for macOS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
                
                Text("Pixel-perfect \(AppConstants.App.basedOn) reproduction on Swift, AppKit & SwiftUI.\nAudio Engine: AVAudioEngine 10-Band EQ & 60fps FFT spectrum/waveform.\nSkin Engine: Classic WSZ/BMP decompilation with dynamic REGION transparency.")
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                    .padding(.bottom, 4)
                
                Divider()
                
                Text("Original Nullsoft Winamp 2.x Team:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Win32Colors.text)
                
                Text("Code: Justin Frankel, Christophe Thibault, Brennan Underwood, Francis Gastellu, Peter Pawlowski\nArt & UI: Steve Gedikian\nIntro voice: JJ McKay (\"Winamp, it really whips the llama's ass!\")\nBaby llama: Allison Saunders\nPCM EQ magic: 4Front Technologies / George Yohng\nMikMod plug-in: Jake Stine\nThe rest O Nullsoft: Tom Pepper, Ryan Geiss, 'Tag' Loomis, Jonathan Ward, Steven Blumenfeld, Chris Amen, Michael 'Mig' Gerard, David Biderman, Simon Gibson, Juman Tang")
                    .font(.system(size: 10))
                    .foregroundColor(Win32Colors.text)

                // The FFmpeg plug-in is LGPL: its notice and where the source is (also inside the plug-in)
                Text("FFmpeg plug-in (in_ffmpeg): FFmpeg by the FFmpeg developers, LGPL v2.1 or later.\nSource: https://ffmpeg.org — built by MacAmp's scripts/build_ffmpeg_plugin.sh, unmodified.")
                    .font(.system(size: 10))
                    .foregroundColor(Win32Colors.text)
                    .textSelection(.enabled)

                // projectM is LGPL and linked dynamically: the library inside the app can be replaced by a build of the same version
                Text("MilkDrop: projectM 4.1.8, copyright © 2003–2009 projectM Team, LGPL 2.1 or later. The license (projectM-LGPL-2.1.txt) and corresponding modified source (projectM-source.tar.gz) are in MacAmp.app/Contents/Resources.")
                    .font(.system(size: 10))
                    .foregroundColor(Win32Colors.text)
                    .textSelection(.enabled)

                Text("What A Goom! v1.99.4 by Jean-Christophe Hoelt (Jeko) and Fred Howell, LGPL. The license (GOOM-LICENSE.txt) and corresponding modified source (GOOM-source.zip) are in MacAmp.app/Contents/Resources.")
                    .font(.system(size: 10))
                    .foregroundColor(Win32Colors.text)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .win32Sunken()
        .padding(6)
    }
    
    // MARK: - Tab 3: Classic Keyboard Shortcuts
    private var shortcutsTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AboutShortcuts.sections, id: \.title) { section in
                    Text("*** \(section.title) ***")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.top, 6)
                    ForEach(section.rows, id: \.action) { row in shortcutRow(row.keys, row.action) }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .win32Sunken()
        .padding(6)
    }
    
    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 11, weight: .bold)) // the monospaced font draws ⌃ as a plain ^
                .frame(width: 110, alignment: .leading)
                .foregroundColor(Win32Colors.selectionBlue)
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
            Spacer()
        }
        .padding(.vertical, 1)
    }
    
    // MARK: - Tab 4: Version History
    private var historyTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(AppConstants.App.basedOn) (Canonical Baseline):")
                    .font(.system(size: 11, weight: .bold))
                Text("* Full classic 275x116 window layout with 275x14 shade mode.\n* 10-band graphic equalizer with preamp and dynamic frequency response curve.\n* Real-time 60fps spectrum analyzer and oscilloscope.\n* Authentic pseudo-random shuffle memory.\n* WSZ/ZIP skin loader with REGION.TXT transparency masking.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Win32Colors.text)
                
                Divider()
                
                Text("MacAmp \(AppConstants.App.version) for macOS:")
                    .font(.system(size: 11, weight: .bold))
                Text("* Built specifically for modern macOS (Apple Silicon & Intel).\n* Pixel-perfect 1x and 2x Retina scale factors.\n* Magnetic window docking with edge-snapping and unified dragging.\n* Integrated ID3v1/ID3v2 MPEG Audio Info editor (⌥3).\n* Winamp Preferences dialog (⌘, / ⌃P).")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Win32Colors.text)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .win32Sunken()
        .padding(6)
    }
}

/// Winamp 2.95's shortkeys.txt in Mac notation (⌃ Ctrl, ⌥ Alt, ⇧ Shift, ⌫ Delete, ↩ Enter, Num = keypad, Help = Insert),
/// with MacAmp's own additions (Library, Video). Only keys MacAmp handles are listed.
public enum AboutShortcuts {
    public struct Row { public let keys: String; public let action: String }
    public struct Section { public let title: String; public let rows: [Row] }

    private static func rows(_ pairs: [(String, String)]) -> [Row] { pairs.map { Row(keys: $0.0, action: $0.1) } }

    private static let playback = rows([
        ("X or Num 5", "Play/Restart/Unpause"), ("V", "Stop"), ("⇧V", "Stop with Fadeout"), ("⌃V", "Stop after current track"),
        ("C or Space", "Pause/Unpause"), ("B or Num 6", "Next Track"), ("Z or Num 4", "Previous Track"),
        ("Num 1", "Jump Ten Songs Back"), ("Num 3", "Jump Ten Songs Forward"),
        ("← or Num 7", "Rewind 5 seconds"), ("→ or Num 9", "Fast-forward 5 seconds"),
    ])

    public static let sections: [Section] = [
        Section(title: "Keyboard Shortcuts (in any of MacAmp's windows)", rows: rows([
            ("F1", "About Box"), ("⌃A", "Toggle Always-On-Top"), ("⌃W", "Toggle Windowshade mode"),
            ("⌃D", "Toggle Doublesize Mode"), ("⌃E", "Toggle Easymove"), ("⌃T", "Toggle Time Display Mode"),
            ("⌥W", "Toggle Main Window"), ("⌥E", "Toggle Playlist Editor"), ("⌥G", "Toggle Graphical Equalizer"),
            ("⌥L", "Toggle Library"), ("⌥T", "Toggle Minibrowser"), ("⌥V", "Toggle Video Window"),
            ("⌃Tab", "Cycle through different MacAmp windows"),
            ("⌥S", "Go to Skin selection"), ("⌃P or ⌘,", "Go to Preferences"), ("⌥O", "Go to Built-in Visualization options"),
            ("⌥F", "Jump to Main Menu"), ("⌥K", "Configure current Visualization Plug-In"),
            ("⌃⇧K", "Start/Stop current Visualization Plug-In"), ("⌃K", "Open Visualization Tab of Preferences"),
            ("⌃J", "Jump to time in current track"), ("J or Num .", "Open Jump-to-file Box"),
            ("⌥I / ⌃⌥I", "Add Bookmark / Edit Bookmarks"), ("⌥M", "Minimize MacAmp"),
        ])),
        Section(title: "Main Window Keyboard Shortcuts", rows: rows([
            ("R", "Toggle Repeat"), ("S", "Toggle Shuffle"), ("⌥3", "Current file info box/ID3 editor"),
        ]) + playback + rows([
            ("L or Num 0", "Open/Play File"), ("⌃L or ⌃Num 0", "Open/Play location"), ("⇧L or Help", "Open/Play Directory"),
            ("↑ or Num 8", "Turn Volume Up"), ("↓ or Num 2", "Turn Volume Down"),
        ])),
        Section(title: "Playlist Editor Keyboard Shortcuts", rows: rows([
            ("⌃N", "New (Clear) Playlist"), ("⌃O", "Open (Load) Playlist"), ("⌃S", "Save Playlist"),
            ("⌃E", "Edit Selected Track Filename(s)"), ("⌘A", "Select All"), ("⌃I", "Invert Selection"),
            ("⌫", "Remove Selected Files from Playlist"), ("⌃⌫", "Crop Playlist"), ("⌃⇧⌫", "Clear Playlist"),
            ("⌥↓ / ⌥↑", "Move Selected Files Down / Up"), ("↩", "Play Selected File"),
            ("Home / End", "Jump to Start / End of List"), ("Page Up / Page Down", "Move up / down a page"),
            ("⌥⌫", "Remove dead (non-existent) files"),
            ("⌃⇧1", "Sort Playlist by Title"), ("⌃⇧2", "Sort Playlist by File Name"), ("⌃⇧3", "Sort Playlist by File Path and Name"),
            ("⌃R", "Reverse Playlist"), ("⌃⇧R", "Randomize Playlist"), ("⌃F4", "Close (hide) Playlist Editor"),
        ])),
        Section(title: "Graphical Equalizer Keyboard Shortcuts", rows: rows([
            ("1 - 0", "Increase EQ bands"), ("Q - P", "Decrease EQ bands"), ("`", "Increase EQ Preamp"), ("Tab", "Decrease EQ Preamp"),
            ("N", "Toggle EQ"), ("A", "Toggle EQ Auto-Loading"), ("⌃F4", "Close (hide) Graphical Equalizer"),
        ])),
        Section(title: "Library Keyboard Shortcuts", rows: rows([
            ("↩ / ⇧↩", "Play / Enqueue selection"), ("⌫", "Remove from library"), ("⌘A", "Select all"),
        ])),
        Section(title: "Video Window Keyboard Shortcuts", rows: rows([
            ("⌥↩", "Fullscreen"), ("Esc", "Leave fullscreen"), ("1", "Normal size"), ("`", "Half size"), ("2", "Double size"),
            ("⌃F4", "Close (hide) Video Window"),
        ])),
        Section(title: "Minibrowser Keyboard Shortcuts", rows: rows([
            ("⌥←", "Go Back"), ("⌥→", "Go Forward"), ("⌃O", "Open Internet Location Box"), ("⌃R", "Reload page"),
            ("⌃⌥R", "Update Link List"), ("⌃F4", "Close (hide) Minibrowser"),
        ])),
    ]
}

// MARK: - The animated banner

/// The banner of Winamp 2.95's About box: the logo is looked at through a lens whose strength and shape change for 64
/// frames, then it rests for 40. Recovered from winamp.exe (the routine at 0x406fb1); every number below is the original's.
struct AboutBannerWarp {
    /// The banner in points: as wide as the logo and a little taller, so the resting lens leaves black above and below.
    /// (The original's is 452 × 289, 301 × 178 dialog units; MacAmp keeps the dialog compact.)
    static let pointWidth = 392, pointHeight = 218
    /// Pixels a point: the resting lens shrinks the logo about 1.2 times, and at one pixel a point it would drop rows and
    /// columns of it (stripes on a still picture)
    static let density = 2
    static let width = pointWidth * density, height = pointHeight * density
    /// The logo bitmap (resource 109)
    static let sourceWidth = 392, sourceHeight = 192
    /// The original sleeps 50 ms between frames
    static let frameInterval: TimeInterval = 0.05
    /// Frames of one warp cycle, and of the rest before the next one
    static let cycleFrames = 64, restFrames = 40
    /// Fixed-point steps across the picture: 0x113a0 / width and 0x9600 / height, in 1/65536ths
    static let stepX = 0x113a0 / width, stepY = 0x9600 / height
    /// The lens: -435.2 scales the magnification table, 0x100 keeps the centre away from a zero distance
    static let lensScale = -435.2, centreBias = 0x100
    /// Strength grows by 24 a frame to the middle of the cycle and falls back
    static let strengthPerFrame = 3 << 3
    /// Winamp's 256-entry square-root table (0x447678): 16 · √n, rounded down
    static let rootTable: [Int] = (0..<256).map { Int(16 * Double($0).squareRoot()) }

    /// Pixels in the original's row order: bottom row first, as in a Windows bitmap
    private let source: [UInt32]
    private(set) var pixels: [UInt32]
    /// Frame of the cycle (0 = at rest), frames rested, and which half of the rows the last frame drew
    private(set) var phase = 0
    private var rested = 0, field = 0
    private var magnification: [Int] = []

    /// `topDown`: the logo, sourceWidth × sourceHeight pixels, top row first
    init(topDown: [UInt32]) {
        source = AboutBannerWarp.flipped(topDown, width: AboutBannerWarp.sourceWidth)
        pixels = [UInt32](repeating: 0, count: AboutBannerWarp.width * AboutBannerWarp.height)
    }

    /// The current picture, top row first
    var topDown: [UInt32] { AboutBannerWarp.flipped(pixels, width: AboutBannerWarp.width) }

    private static func flipped(_ rows: [UInt32], width: Int) -> [UInt32] {
        stride(from: rows.count / width - 1, through: 0, by: -1).flatMap { rows[($0 * width)..<(($0 + 1) * width)] }
    }

    /// Winamp's integer square root for the distances met here (256 ... 0x3FFFF)
    static func root(_ value: Int) -> Int {
        switch value {
        case 0x10000...: return rootTable[min(255, value >> 10)] << 1
        case 0x4000...: return rootTable[min(255, value >> 8)]
        case 0x1000...: return rootTable[value >> 6] >> 1
        case 0x400...: return rootTable[value >> 4] >> 2
        default: return rootTable[value >> 2] >> 3
        }
    }

    /// Strength of the lens at a frame of the cycle
    static func strength(phase: Int) -> Int { (phase < cycleFrames / 2 ? phase : cycleFrames - phase) * strengthPerFrame }

    /// Draws the next frame: one half of the rows (odd or even), like the original
    mutating func step() {
        let width = AboutBannerWarp.width, height = AboutBannerWarp.height
        let halfWidth = width / 2, halfHeight = height / 2
        let radius = Double((width * width + height * height) / 4).squareRoot()

        // Magnification by distance from the centre. The exponent swings with the phase; a strength above the lens
        // value turns the sign over, and the absolute value shows the picture inside out.
        var exponent = sin(Double(phase) * .pi / Double(AboutBannerWarp.cycleFrames / 2)) + 1
        if exponent < 1 { exponent = (exponent + 1) * 0.5 }
        let strength = AboutBannerWarp.strength(phase: phase)
        magnification = (0..<Int(radius)).map { distance in
            let lens = pow(sin(Double(distance) / (radius - 1)), exponent) * radius * AboutBannerWarp.lensScale / Double(distance + 1)
            return abs(-strength - Int(lens))
        }

        if phase == 0 {
            rested += 1
            if rested > AboutBannerWarp.restFrames { phase = 1 }
        } else {
            rested = 0
            phase = (phase + 1) % AboutBannerWarp.cycleFrames
        }

        // A line of the original is `density` rows here, so the interlace stripes keep the original's thickness
        let line = AboutBannerWarp.density
        var row = field * line
        field = field == 0 ? 1 : 0
        // Each row is drawn from its own place: taking it from the next line swaps line pairs, a comb on every edge at rest
        while row < height {
            for sub in 0..<line where row + sub < height { draw(row: row + sub, dy: row + sub - halfHeight) }
            row += 2 * line
        }
    }

    private mutating func draw(row: Int, dy: Int) {
        let width = AboutBannerWarp.width, halfWidth = width / 2
        var distanceSquared = dy * dy + halfWidth * (halfWidth + 1) + AboutBannerWarp.centreBias
        var increment = -width
        var fx = -halfWidth * AboutBannerWarp.stepX
        let fy = dy * AboutBannerWarp.stepY
        for x in 0..<width {
            // The original reads a little past its table at the corners; the last entry stands in
            let scale = magnification[min(magnification.count - 1, AboutBannerWarp.root(distanceSquared))]
            distanceSquared += increment
            increment += 2
            let sx = min(AboutBannerWarp.sourceWidth - 1, max(0, scale * fx / 0x10000 + AboutBannerWarp.sourceWidth / 2))
            let sy = min(AboutBannerWarp.sourceHeight - 1, max(0, fy * scale / 0x10000 + AboutBannerWarp.sourceHeight / 2))
            fx += AboutBannerWarp.stepX
            pixels[row * width + x] = source[sy * AboutBannerWarp.sourceWidth + sx]
        }
    }
}

/// Runs the banner only while it is on screen
final class AboutBannerModel: ObservableObject {
    /// Where the logo comes from (tests have no asset catalogue)
    static var logo: () -> CGImage? = { NSImage(named: "ABOUT_LOGO")?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    @Published var image: CGImage?
    private var warp: AboutBannerWarp?
    private var timer: Timer?

    private static func context(_ data: UnsafeMutableRawPointer?, width: Int, height: Int) -> CGContext? {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: Skin.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    func start() {
        guard timer == nil else { return }
        if warp == nil, let logo = AboutBannerModel.logo() {
            let width = AboutBannerWarp.sourceWidth, height = AboutBannerWarp.sourceHeight
            var topDown = [UInt32](repeating: 0, count: width * height)
            topDown.withUnsafeMutableBytes { bytes in
                AboutBannerModel.context(bytes.baseAddress, width: width, height: height)?
                    .draw(logo, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            warp = AboutBannerWarp(topDown: topDown)
            // Both halves of the rows before the first picture is shown
            warp?.step()
        }
        tick()
        let timer = Timer(timeInterval: AboutBannerWarp.frameInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard warp != nil else { return }
        warp?.step()
        var topDown = warp?.topDown ?? []
        image = topDown.withUnsafeMutableBytes {
            AboutBannerModel.context($0.baseAddress, width: AboutBannerWarp.width, height: AboutBannerWarp.height)?.makeImage()
        }
    }
}

struct AboutBannerView: View {
    @StateObject private var model = AboutBannerModel()

    var body: some View {
        // The black backdrop is always there: an empty Group has nothing for onAppear to fire on, and the banner never started
        ZStack {
            Color.black
            if let image = model.image {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
