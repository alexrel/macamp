import SwiftUI
import AppKit

// MARK: - Preferences Category
public enum PreferencesCategory: String, CaseIterable, Identifiable {
    case titles = "Titles & Display"
    case skins = "Skins"
    case audio = "Audio & Playback"
    case playlist = "Playlist"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .titles: return "textformat"
        case .skins: return "paintpalette"
        case .audio: return "speaker.wave.2"
        case .playlist: return "list.bullet"
        }
    }
}

// MARK: - Preferences View Model
public class PreferencesViewModel: ObservableObject {
    @Published public var selectedCategory: PreferencesCategory = .titles
    
    // Titles & Display State
    @Published public var marqueeFontMode: MarqueeFontMode {
        didSet {
            PersistenceManager.shared.state.marqueeFontMode = marqueeFontMode
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
        }
    }
    
    @Published public var desktopFontFamily: String {
        didSet {
            PersistenceManager.shared.state.desktopFontFamily = desktopFontFamily
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
        }
    }
    
    @Published public var desktopFontSize: Double {
        didSet {
            PersistenceManager.shared.state.desktopFontSize = desktopFontSize
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
        }
    }
    
    @Published public var isMarqueeScrollEnabled: Bool {
        didSet {
            PersistenceManager.shared.state.isMarqueeScrollEnabled = isMarqueeScrollEnabled
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
        }
    }
    
    @Published public var showTrackNumberInTitle: Bool {
        didSet {
            PersistenceManager.shared.state.showTrackNumberInTitle = showTrackNumberInTitle
            PersistenceManager.shared.saveSession()
        }
    }
    
    // Scale State
    @Published public var scaleFactor: ScaleFactor {
        didSet {
            PersistenceManager.shared.state.scaleFactor = scaleFactor
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.setScale(scaleFactor)
        }
    }
    
    // Skins List
    @Published public var installedSkins: [URL] = []
    @Published public var selectedSkinURL: URL?
    
    // Playlist State
    @Published public var playlistZeroPadding: Bool {
        didSet {
            PersistenceManager.shared.state.playlistZeroPadding = playlistZeroPadding
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.plView?.needsDisplay = true
        }
    }
    
    @Published public var playlistShowExtensions: Bool {
        didSet {
            PersistenceManager.shared.state.playlistShowExtensions = playlistShowExtensions
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.plView?.needsDisplay = true
        }
    }
    
    @Published public var authenticShuffle: Bool {
        didSet {
            PersistenceManager.shared.state.authenticShuffle = authenticShuffle
            PersistenceManager.shared.saveSession()
        }
    }
    
    // Audio State
    @Published public var audioFadeOutDurationMs: Double {
        didSet {
            PersistenceManager.shared.state.audioFadeOutDurationMs = audioFadeOutDurationMs
            PersistenceManager.shared.saveSession()
        }
    }
    
    @Published public var autoGenreEQ: Bool {
        didSet {
            PersistenceManager.shared.state.autoGenreEQ = autoGenreEQ
            PersistenceManager.shared.saveSession()
        }
    }
    
    public init() {
        let state = PersistenceManager.shared.state
        self.marqueeFontMode = state.marqueeFontMode
        self.desktopFontFamily = state.desktopFontFamily
        self.desktopFontSize = state.desktopFontSize
        self.isMarqueeScrollEnabled = state.isMarqueeScrollEnabled
        self.showTrackNumberInTitle = state.showTrackNumberInTitle
        self.scaleFactor = state.scaleFactor
        self.playlistZeroPadding = state.playlistZeroPadding
        self.playlistShowExtensions = state.playlistShowExtensions
        self.authenticShuffle = state.authenticShuffle
        self.audioFadeOutDurationMs = state.audioFadeOutDurationMs
        self.autoGenreEQ = state.autoGenreEQ
        
        refreshSkins()
    }
    
    public func refreshSkins() {
        self.installedSkins = SkinManager.shared.installedSkins()
        self.selectedSkinURL = SkinManager.shared.currentSkinURL
    }
    
    public func selectSkin(url: URL?) {
        if let url = url {
            if SkinManager.shared.loadSkin(from: url) {
                selectedSkinURL = url
                PersistenceManager.shared.state.activeSkinPath = url.path
                PersistenceManager.shared.saveSession()
                PlayerCoordinator.shared.refreshAllViews()
            }
        } else {
            SkinManager.shared.resetToBaseSkin()
            selectedSkinURL = nil
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.refreshAllViews()
        }
    }
    
    public func installSkin() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "wsz")!, .zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.message = "Select a Winamp Classic Skin (.wsz or .zip)"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let installedURL = SkinManager.shared.installSkin(from: url) {
                refreshSkins()
                selectSkin(url: installedURL)
            }
        }
    }
    
    public func openSkinsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: SkinManager.shared.skinsDirectory.path)
    }
}

// MARK: - Preferences View
public struct PreferencesView: View {
    @ObservedObject public var viewModel: PreferencesViewModel
    public var onClose: (() -> Void)?
    
    private let winampGray = Color(red: 0.88, green: 0.86, blue: 0.83)
    private let availableFonts = ["Monaco", "Menlo", "Geneva", "SF Pro Display", "Courier New", "Helvetica"]
    private let availableFontSizes: [Double] = [8, 9, 10, 11, 12, 14]
    
    public init(viewModel: PreferencesViewModel, onClose: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Navigation Sidebar
            VStack(alignment: .leading, spacing: 2) {
                Text("Preferences")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                
                ForEach(PreferencesCategory.allCases) { category in
                    Button(action: {
                        viewModel.selectedCategory = category
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .font(.system(size: 11))
                                .frame(width: 16)
                            Text(category.rawValue)
                                .font(.system(size: 11))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.selectedCategory == category
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Divider()
                
                Button(action: { onClose?() }) {
                    Text("Close")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                }
                .padding(10)
            }
            .frame(width: 160)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Right Category Details
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.selectedCategory.rawValue)
                    .font(.system(size: 13, weight: .bold))
                
                Divider()
                
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        switch viewModel.selectedCategory {
                        case .titles:
                            titlesAndDisplaySection
                        case .skins:
                            skinsSection
                        case .audio:
                            audioSection
                        case .playlist:
                            playlistSection
                        }
                    }
                    .padding(.trailing, 8)
                }
                
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(winampGray)
        }
        .frame(width: 580, height: 460)
    }
    
    // MARK: - Section: Titles & Display
    private var titlesAndDisplaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Mode selector
            GroupBox(label: Text("Marquee Song Title Font").font(.system(size: 11, weight: .bold)).padding(.leading, 8)) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $viewModel.marqueeFontMode) {
                        Text("Bitmap Font (Classic Winamp pixel font from TEXT.BMP)").tag(MarqueeFontMode.bitmap)
                        Text("Desktop Font (TrueType system font)").tag(MarqueeFontMode.desktop)
                    }
                    .pickerStyle(.radioGroup)
                    .font(.system(size: 11))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Desktop Font Settings
            if viewModel.marqueeFontMode == .desktop {
                GroupBox(label: Text("Desktop Font Settings").font(.system(size: 11, weight: .bold)).padding(.leading, 8)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Font Family:")
                                .font(.system(size: 11))
                                .frame(width: 80, alignment: .trailing)
                            
                            Picker("", selection: $viewModel.desktopFontFamily) {
                                ForEach(availableFonts, id: \.self) { f in
                                    Text(f).tag(f)
                                }
                            }
                            .frame(width: 140)
                        }
                        
                        HStack(spacing: 12) {
                            Text("Font Size:")
                                .font(.system(size: 11))
                                .frame(width: 80, alignment: .trailing)
                            
                            Picker("", selection: $viewModel.desktopFontSize) {
                                ForEach(availableFontSizes, id: \.self) { sz in
                                    Text("\(Int(sz)) pt").tag(sz)
                                }
                            }
                            .frame(width: 100)
                        }
                        
                        Text("Note: Font color is automatically inherited from the active skin's text color palette.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Behavior & Formatting
            GroupBox(label: Text("Title Behavior").font(.system(size: 11, weight: .bold)).padding(.leading, 8)) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Smoothly scroll song title when it exceeds display width", isOn: $viewModel.isMarqueeScrollEnabled)
                        .font(.system(size: 11))
                    
                    Toggle("Show track numbers in title formatting (e.g. '1. Artist - Title')", isOn: $viewModel.showTrackNumberInTitle)
                        .font(.system(size: 11))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Section: Skins
    private var skinsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Text("Installed Classic Skins").font(.system(size: 11, weight: .bold)).padding(.leading, 8)) {
                VStack(alignment: .leading, spacing: 8) {
                    // Skin selection list
                    VStack(alignment: .leading, spacing: 4) {
                        // Base skin option
                        Button(action: { viewModel.selectSkin(url: nil) }) {
                            HStack {
                                Image(systemName: viewModel.selectedSkinURL == nil ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(viewModel.selectedSkinURL == nil ? .accentColor : .secondary)
                                Text("Classic Winamp 2.91 (Base Skin)")
                                    .font(.system(size: 11, weight: viewModel.selectedSkinURL == nil ? .bold : .regular))
                                Spacer()
                                Text("[Bundled]")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(viewModel.selectedSkinURL == nil ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        
                        ForEach(viewModel.installedSkins, id: \.self) { skinURL in
                            let isSelected = viewModel.selectedSkinURL?.path == skinURL.path
                            Button(action: { viewModel.selectSkin(url: skinURL) }) {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isSelected ? .accentColor : .secondary)
                                    Text(skinURL.deletingPathExtension().lastPathComponent)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                    Spacer()
                                    Text(skinURL.pathExtension.uppercased())
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxHeight: 140)
                    
                    Divider()
                    
                    HStack(spacing: 10) {
                        Button("Install Skin...") {
                            viewModel.installSkin()
                        }
                        .font(.system(size: 11))
                        
                        Button("Open Skins Folder") {
                            viewModel.openSkinsFolder()
                        }
                        .font(.system(size: 11))
                        
                        Spacer()
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Text("Display Scale").font(.system(size: 11, weight: .bold)).padding(.leading, 8)) {
                HStack(spacing: 12) {
                    Text("Scale Factor:")
                        .font(.system(size: 11))
                    
                    Picker("", selection: $viewModel.scaleFactor) {
                        Text("1x (Original 275×116)").tag(ScaleFactor.x1)
                        Text("2x (Double Size 550×232)").tag(ScaleFactor.x2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Section: Audio & Playback
    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Text("Fading & Transitions").font(.system(size: 11, weight: .bold)).padding(.leading, 8)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fade out on Pause/Stop:")
                            .font(.system(size: 11))
                        Spacer()
                        Text("\(Int(viewModel.audioFadeOutDurationMs)) ms")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    Slider(value: $viewModel.audioFadeOutDurationMs, in: 0...2000, step: 50)
                    
                    Text("Smoothly reduces audio volume before pausing or stopping to avoid pops or clicks.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Text("Equalizer Preferences").font(.system(size: 11, weight: .bold)).padding(.leading, 8)) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-load EQ preset based on track's ID3 Genre", isOn: $viewModel.autoGenreEQ)
                        .font(.system(size: 11))
                    
                    Text("When a track starts playing, automatically applies matching EQ curve (Rock, Pop, Jazz, Metal, etc.).")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Section: Playlist
    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Text("Track Item Display").font(.system(size: 11, weight: .bold)).padding(.leading, 8)) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Zero-pad track numbers in playlist (e.g. '01.' instead of '1.')", isOn: $viewModel.playlistZeroPadding)
                        .font(.system(size: 11))
                    
                    Toggle("Show file extensions in playlist if title is missing (.mp3, .flac)", isOn: $viewModel.playlistShowExtensions)
                        .font(.system(size: 11))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GroupBox(label: Text("Playback Shuffle Engine").font(.system(size: 11, weight: .bold)).padding(.leading, 8)) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Authentic Winamp pseudo-random shuffle (remembers played tracks without repeats)", isOn: $viewModel.authenticShuffle)
                        .font(.system(size: 11))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
