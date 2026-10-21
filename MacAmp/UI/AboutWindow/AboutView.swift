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
    
    public init(onClose: (() -> Void)? = nil) {
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
                    
                    Link("http://www.winamp.com", destination: URL(string: "https://www.winamp.com")!)
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
                Text("Classic Winamp Keyboard Shortcuts")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.bottom, 4)
                
                Group {
                    shortcutRow("Z", "Previous Track")
                    shortcutRow("X", "Play / Restart")
                    shortcutRow("C", "Pause / Unpause")
                    shortcutRow("V", "Stop Playback")
                    shortcutRow("⇧V / ⌃V", "Stop w/ Fadeout / Stop After Current")
                    shortcutRow("B", "Next Track")
                    shortcutRow("L / ⌘O", "Open Audio File")
                    shortcutRow("⇧L / ⇧⌘O", "Open Audio Folder")
                    shortcutRow("⌘U", "Open Stream URL")
                    shortcutRow("⌘, / ⌃P", "Winamp Preferences")
                    shortcutRow("⌥3", "Track Info / ID3 Tag Editor")
                    shortcutRow("J / ⌃J", "Jump to File / Jump to Time")
                    shortcutRow("⌃D", "Toggle Double Size (1x / 2x)")
                    shortcutRow("⌘T", "Toggle Always On Top")
                    shortcutRow("⌘E", "Toggle Equalizer Window")
                    shortcutRow("⌘P", "Toggle Playlist Window")
                    shortcutRow("R", "Toggle Repeat")
                    shortcutRow("S", "Toggle Shuffle")
                    shortcutRow("⌫", "Remove Selected Track(s)")
                    shortcutRow("⌘⌫ / ⌃⌫", "Crop Selected (keep only selected)")
                    shortcutRow("Space", "Pause / Unpause")
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
                .font(.system(size: 11, weight: .bold, design: .monospaced))
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
