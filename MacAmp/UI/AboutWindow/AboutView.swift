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
                .padding(.bottom, 6)
            }
        }
        .frame(width: 410, height: 310)
        .background(Win32Colors.dialogBg)
        .onExitCommand {
            onClose?()
        }
    }
    
    // MARK: - Tab 1: Winamp Iconic Llama & Logo
    private var winampTabContent: some View {
        VStack(spacing: 0) {
            // Black Art Banner with extracted classic Nullsoft logo
            ZStack {
                Color.black
                Image("ABOUT_LOGO")
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 392, height: 192)
            }
            .frame(width: 392, height: 192)
            .clipped()
            .padding(.top, 4)
            
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
