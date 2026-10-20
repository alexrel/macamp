import SwiftUI
import AppKit

// MARK: - Preferences Category & Tree Items
public enum PreferencesCategory: String, CaseIterable, Identifiable {
    case titles = "Titles & Display"
    case skins = "Skins"
    case audio = "Audio & Playback"
    case playlist = "Playlist"
    
    public var id: String { rawValue }
}

public enum PrefTreeItem: String, CaseIterable, Identifiable {
    case display = "Display"
    case titles = "Titles & Fonts"
    case visualization = "Visualization"
    case hotkeys = "Global Hotkeys"
    case audio = "Playback & Fading"
    case output = "Output Devices"
    case dsp = "DSP / Effects"
    case equalizer = "Equalizer"
    case playlist = "Track Display"
    case skins = "Installed Skins"
    
    public var id: String { rawValue }
    
    public var sectionHeader: String {
        switch self {
        case .display, .titles, .visualization, .hotkeys: return "Options"
        case .audio, .output, .dsp, .equalizer: return "Audio"
        case .playlist: return "Playlist"
        case .skins: return "Skins"
        }
    }
}

// MARK: - Preferences View Model
public class PreferencesViewModel: ObservableObject {
    @Published public var selectedTreeItem: PrefTreeItem = .display
    
    // Window & Display State
    @Published public var isAlwaysOnTop: Bool {
        didSet {
            PersistenceManager.shared.state.isAlwaysOnTop = isAlwaysOnTop
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.setAlwaysOnTop(isAlwaysOnTop)
            MainMenuManager.shared.updateStates()
        }
    }
    
    @Published public var scaleFactor: ScaleFactor {
        didSet {
            PersistenceManager.shared.state.scaleFactor = scaleFactor
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.setScale(scaleFactor)
            MainMenuManager.shared.updateStates()
        }
    }
    
    // Titles & Display State
    @Published public var marqueeFontMode: MarqueeFontMode {
        didSet {
            PersistenceManager.shared.state.marqueeFontMode = marqueeFontMode
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
            PlayerCoordinator.shared.mainView?.marquee.updateScrollTimer()
        }
    }
    
    @Published public var desktopFontFamily: String {
        didSet {
            PersistenceManager.shared.state.desktopFontFamily = desktopFontFamily
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
            PlayerCoordinator.shared.mainView?.marquee.updateScrollTimer()
        }
    }
    
    @Published public var desktopFontSize: Double {
        didSet {
            PersistenceManager.shared.state.desktopFontSize = desktopFontSize
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
            PlayerCoordinator.shared.mainView?.marquee.updateScrollTimer()
        }
    }
    
    @Published public var isMarqueeScrollEnabled: Bool {
        didSet {
            PersistenceManager.shared.state.isMarqueeScrollEnabled = isMarqueeScrollEnabled
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
            PlayerCoordinator.shared.mainView?.marquee.updateScrollTimer()
        }
    }
    
    @Published public var showTrackNumberInTitle: Bool {
        didSet {
            PersistenceManager.shared.state.showTrackNumberInTitle = showTrackNumberInTitle
            PersistenceManager.shared.saveSession()
        }
    }
    
    // Skins List
    @Published public var installedSkins: [URL] = []
    @Published public var selectedSkinURL: URL?
    
    // Playlist State
    @Published public var windowSnapDistance: Int {
        didSet {
            PersistenceManager.shared.state.windowSnapDistance = windowSnapDistance
            PersistenceManager.shared.saveSession()
            WindowLayoutManager.shared.snapThreshold = CGFloat(windowSnapDistance)
        }
    }
    
    @Published public var showNumbersInPlaylist: Bool {
        didSet {
            PersistenceManager.shared.state.showNumbersInPlaylist = showNumbersInPlaylist
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.plView?.needsDisplay = true
        }
    }
    
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
            PersistenceManager.shared.state.isEqAuto = autoGenreEQ
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.eqView?.autoToggle?.isOn = autoGenreEQ
        }
    }
    
    // Visualizer State
    @Published public var visualizerMode: VisualizerMode {
        didSet {
            PersistenceManager.shared.state.visualizerMode = visualizerMode
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.visualizer.mode = visualizerMode
        }
    }
    
    @Published public var visualizerShowPeaks: Bool {
        didSet {
            PersistenceManager.shared.state.visualizerShowPeaks = visualizerShowPeaks
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.visualizer.showPeaks = visualizerShowPeaks
        }
    }
    
    // Hotkeys State
    @Published public var isGlobalHotkeysEnabled: Bool {
        didSet {
            GlobalHotkeysController.shared.isEnabled = isGlobalHotkeysEnabled
        }
    }
    
    // DSP Effects State
    @Published public var isDspEnabled: Bool {
        didSet {
            PersistenceManager.shared.state.isDspEnabled = isDspEnabled
            PersistenceManager.shared.saveSession()
            AudioEngine.shared.setDspEnabled(isDspEnabled)
        }
    }
    
    @Published public var dspPitchSemitones: Double {
        didSet {
            PersistenceManager.shared.state.dspPitchSemitones = dspPitchSemitones
            PersistenceManager.shared.saveSession()
            AudioEngine.shared.setPitchSemitones(dspPitchSemitones)
        }
    }
    
    @Published public var dspPlaybackRate: Double {
        didSet {
            PersistenceManager.shared.state.dspPlaybackRate = dspPlaybackRate
            PersistenceManager.shared.saveSession()
            AudioEngine.shared.setPlaybackRate(dspPlaybackRate)
        }
    }
    
    @Published public var dspReverbMix: Double {
        didSet {
            PersistenceManager.shared.state.dspReverbMix = dspReverbMix
            PersistenceManager.shared.saveSession()
            AudioEngine.shared.setReverbMix(dspReverbMix)
        }
    }
    
    @Published public var dspReverbPreset: Int {
        didSet {
            PersistenceManager.shared.state.dspReverbPreset = dspReverbPreset
            PersistenceManager.shared.saveSession()
            AudioEngine.shared.setReverbPreset(index: dspReverbPreset)
        }
    }
    
    // Audio Output Devices
    @Published public var availableOutputDevices: [AudioOutputDevice] = []
    @Published public var selectedAudioOutputDeviceUID: String? = nil
    
    public init() {
        let state = PersistenceManager.shared.state
        self.isAlwaysOnTop = state.isAlwaysOnTop
        self.scaleFactor = state.scaleFactor
        self.marqueeFontMode = state.marqueeFontMode
        self.desktopFontFamily = state.desktopFontFamily
        self.desktopFontSize = state.desktopFontSize
        self.isMarqueeScrollEnabled = state.isMarqueeScrollEnabled
        self.showTrackNumberInTitle = state.showTrackNumberInTitle
        self.windowSnapDistance = state.windowSnapDistance
        self.showNumbersInPlaylist = state.showNumbersInPlaylist
        self.playlistZeroPadding = state.playlistZeroPadding
        self.playlistShowExtensions = state.playlistShowExtensions
        self.authenticShuffle = state.authenticShuffle
        self.audioFadeOutDurationMs = state.audioFadeOutDurationMs
        self.autoGenreEQ = state.autoGenreEQ
        self.isGlobalHotkeysEnabled = state.isGlobalHotkeysEnabled
        self.isDspEnabled = state.isDspEnabled
        self.dspPitchSemitones = state.dspPitchSemitones
        self.dspPlaybackRate = state.dspPlaybackRate
        self.dspReverbMix = state.dspReverbMix
        self.dspReverbPreset = state.dspReverbPreset
        self.visualizerMode = state.visualizerMode
        self.visualizerShowPeaks = state.visualizerShowPeaks
        
        self.availableOutputDevices = AudioDeviceManager.shared.availableDevices
        self.selectedAudioOutputDeviceUID = AudioDeviceManager.shared.selectedDeviceUID
        
        AudioDeviceManager.shared.onDevicesChanged = { [weak self] devs in
            DispatchQueue.main.async {
                self?.availableOutputDevices = devs
            }
        }
        AudioDeviceManager.shared.onActiveDeviceChanged = { [weak self] _ in
            DispatchQueue.main.async {
                self?.selectedAudioOutputDeviceUID = AudioDeviceManager.shared.selectedDeviceUID
            }
        }
        
        refreshSkins()
    }
    
    public func selectOutputDevice(uid: String?) {
        self.selectedAudioOutputDeviceUID = uid
        AudioDeviceManager.shared.selectDevice(uid: uid)
    }
    
    public func refreshOutputDevices() {
        AudioDeviceManager.shared.refreshDevices()
        self.availableOutputDevices = AudioDeviceManager.shared.availableDevices
        self.selectedAudioOutputDeviceUID = AudioDeviceManager.shared.selectedDeviceUID
    }
    
    public func resetDSP() {
        self.isDspEnabled = false
        self.dspPitchSemitones = 0.0
        self.dspPlaybackRate = 1.0
        self.dspReverbMix = 0.0
        self.dspReverbPreset = 1
        AudioEngine.shared.resetDSP()
    }
    
    public var selectedCategory: PreferencesCategory {
        get {
            switch selectedTreeItem {
            case .display, .titles, .visualization, .hotkeys: return .titles
            case .skins: return .skins
            case .audio, .output, .dsp, .equalizer: return .audio
            case .playlist: return .playlist
            }
        }
        set {
            switch newValue {
            case .titles: selectedTreeItem = .display
            case .skins: selectedTreeItem = .skins
            case .audio: selectedTreeItem = .audio
            case .playlist: selectedTreeItem = .playlist
            }
        }
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
                MainMenuManager.shared.updateStates()
            }
        } else {
            SkinManager.shared.resetToBaseSkin()
            selectedSkinURL = nil
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.refreshAllViews()
            MainMenuManager.shared.updateStates()
        }
    }
    
    public func installSkin() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "wsz")!, .zip]
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
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

// MARK: - TreeView Dotted Branch Connector
public struct TreeConnector: View {
    public let isLast: Bool
    
    public init(isLast: Bool) {
        self.isLast = isLast
    }
    
    public var body: some View {
        Canvas { context, size in
            var path = Path()
            // Vertical dotted stem
            path.move(to: CGPoint(x: 6, y: 0))
            path.addLine(to: CGPoint(x: 6, y: isLast ? size.height / 2 : size.height))
            // Horizontal branch
            path.move(to: CGPoint(x: 6, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
            
            context.stroke(path, with: .color(Color(white: 0.65)), style: StrokeStyle(lineWidth: 1, dash: [1, 1]))
        }
        .frame(width: 16, height: 18)
    }
}

// MARK: - Preferences View
public struct PreferencesView: View {
    @ObservedObject public var viewModel: PreferencesViewModel
    public var onClose: (() -> Void)?
    
    private let availableFonts = ["Monaco", "Menlo", "Geneva", "SF Pro Display", "Courier New", "Helvetica"]
    private let availableFontSizes: [Double] = [8, 9, 10, 11, 12, 14]
    
    private let sections: [String] = ["Options", "Audio", "Playlist", "Skins"]
    
    public init(viewModel: PreferencesViewModel, onClose: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Left Column: Classic Win32 TreeView & Close Button
            VStack(alignment: .center, spacing: 6) {
                // White Sunken TreeView Box
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sections, id: \.self) { sec in
                            treeSection(sec)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.white)
                .win32Sunken()
                .frame(width: 165)
                
                // Classic Win32 Close Button
                Win32Button("Close", width: 165, height: 23) {
                    onClose?()
                }
                .padding(.top, 2)
            }
            .frame(width: 165)
            
            // Right Column: Options & Controls in Win32 GroupBoxes
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        switch viewModel.selectedTreeItem {
                        case .display:
                            displaySection
                        case .titles:
                            titlesSection
                        case .visualization:
                            visualizationSection
                        case .hotkeys:
                            hotkeysSection
                        case .audio:
                            audioSection
                        case .output:
                            outputSection
                        case .dsp:
                            dspSection
                        case .equalizer:
                            equalizerSection
                        case .playlist:
                            playlistSection
                        case .skins:
                            skinsSection
                        }
                    }
                    .padding(.trailing, 6)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .frame(width: 560, height: 440)
        .background(Win32Colors.dialogBg)
    }
    
    // MARK: - Left TreeView Component
    @ViewBuilder
    private func treeSection(_ sectionName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            HStack(spacing: 4) {
                Text(sectionName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Win32Colors.text)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            
            // Items in Section
            let items = PrefTreeItem.allCases.filter { $0.sectionHeader == sectionName }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isLast = (index == items.count - 1)
                let isSelected = (viewModel.selectedTreeItem == item)
                Button(action: {
                    viewModel.selectedTreeItem = item
                }) {
                    HStack(spacing: 2) {
                        TreeConnector(isLast: isLast)
                        
                        Text(item.rawValue)
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? .white : Win32Colors.text)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(isSelected ? Win32Colors.selectionHighlight : Color.clear)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
    
    // MARK: - Section 1: Display
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Display options") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Always On Top (shortcut: ⌘T / Ctrl+T)", isOn: $viewModel.isAlwaysOnTop)
                    Win32Checkbox("Smoothly scroll song title when it exceeds display width", isOn: $viewModel.isMarqueeScrollEnabled)
                    
                    HStack(spacing: 6) {
                        Win32Checkbox("Snap Winamp windows at", isOn: .init(
                            get: { viewModel.windowSnapDistance > 0 },
                            set: { viewModel.windowSnapDistance = $0 ? 10 : 0 }
                        ))
                        Win32NumberField(value: $viewModel.windowSnapDistance, width: 28)
                        Text("pixels")
                            .font(.system(size: 11))
                            .foregroundColor(Win32Colors.text)
                    }
                    
                    Win32Checkbox("Use bitmap font for main title display (classic skin font)", isOn: .init(
                        get: { viewModel.marqueeFontMode == .bitmap },
                        set: { viewModel.marqueeFontMode = $0 ? .bitmap : .desktop }
                    ))
                    
                    Win32Checkbox("Show track numbers in Playlist", isOn: $viewModel.showNumbersInPlaylist)
                    Win32Checkbox("Zero-pad numbers in Playlist (e.g. '01.')", isOn: $viewModel.playlistZeroPadding)
                    Win32Checkbox("Show file extensions in Playlist", isOn: $viewModel.playlistShowExtensions)
                }
            }
            
            Win32GroupBox("Window size / Display scale") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32RadioButton("Normal size (1x: 275 × 116 px)", isSelected: viewModel.scaleFactor == .x1) {
                        viewModel.scaleFactor = .x1
                    }
                    
                    Win32RadioButton("Double size (2x: 550 × 232 px, shortcut: Ctrl+D)", isSelected: viewModel.scaleFactor == .x2) {
                        viewModel.scaleFactor = .x2
                    }
                }
            }
        }
    }
    
    // MARK: - Section 2: Titles & Fonts
    private var titlesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Marquee Song Title Font") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32RadioButton("Use skin bitmap font (classic pixel font from TEXT.BMP)", isSelected: viewModel.marqueeFontMode == .bitmap) {
                        viewModel.marqueeFontMode = .bitmap
                    }
                    
                    Win32RadioButton("Use desktop system font (TrueType)", isSelected: viewModel.marqueeFontMode == .desktop) {
                        viewModel.marqueeFontMode = .desktop
                    }
                }
            }
            
            if viewModel.marqueeFontMode == .desktop {
                Win32GroupBox("Desktop Font Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Font Family:")
                                .font(.system(size: 11))
                                .frame(width: 80, alignment: .trailing)
                            
                            Picker("", selection: $viewModel.desktopFontFamily) {
                                ForEach(availableFonts, id: \.self) { f in
                                    Text(f).tag(f)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        
                        HStack(spacing: 8) {
                            Text("Font Size:")
                                .font(.system(size: 11))
                                .frame(width: 80, alignment: .trailing)
                            
                            Picker("", selection: $viewModel.desktopFontSize) {
                                ForEach(availableFontSizes, id: \.self) { sz in
                                    Text("\(Int(sz)) pt").tag(sz)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                        
                        Text("Color is automatically inherited from the active skin's text palette.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }
            }
        }
    }
    
    // MARK: - Section: Visualization
    private var visualizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Visualization Mode") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32RadioButton("Spectrum Analyzer (60 fps FFT frequency bands)", isSelected: viewModel.visualizerMode == .spectrum) {
                        viewModel.visualizerMode = .spectrum
                    }
                    
                    Win32RadioButton("Oscilloscope (real-time audio waveform)", isSelected: viewModel.visualizerMode == .oscilloscope) {
                        viewModel.visualizerMode = .oscilloscope
                    }
                    
                    Win32RadioButton("Off (no visualizer)", isSelected: viewModel.visualizerMode == .off) {
                        viewModel.visualizerMode = .off
                    }
                }
            }
            
            Win32GroupBox("Spectrum Analyzer Options") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Show peak markers", isOn: $viewModel.visualizerShowPeaks)
                    
                    Text("Draws falling peak dots above each frequency bar in spectrum mode.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.leading, 18)
                }
            }
        }
    }
    
    // MARK: - Section: Global Hotkeys
    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Global Hotkeys") {
                VStack(alignment: .leading, spacing: 8) {
                    Win32Checkbox("Enable Global Hotkeys", isOn: $viewModel.isGlobalHotkeysEnabled)
                    
                    Text("Control playback from any application when MacAmp is in background:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        hotkeyRow("Play", "Ctrl + Alt + X")
                        hotkeyRow("Play / Pause", "Ctrl + Alt + C  or  Space")
                        hotkeyRow("Stop", "Ctrl + Alt + V")
                        hotkeyRow("Previous Track", "Ctrl + Alt + Z  or  ←")
                        hotkeyRow("Next Track", "Ctrl + Alt + B  or  →")
                        hotkeyRow("Volume Up", "Ctrl + Alt + ↑")
                        hotkeyRow("Volume Down", "Ctrl + Alt + ↓")
                        hotkeyRow("Toggle Mute", "Ctrl + Alt + M")
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .modifier(Win32SunkenBorder())
                }
            }
            
            Win32GroupBox("Media Keys & Permissions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Hardware media keys (F7, F8, F9, AirPods & Touch Bar) work globally.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Accessibility Status:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Win32Colors.text)
                        
                        if GlobalHotkeysController.shared.isAccessibilityTrusted {
                            Text("Granted ✓")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        } else {
                            Text("Permission needed for background Ctrl+Alt keys")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Win32Button("Grant Access...", width: 105, height: 21) {
                                GlobalHotkeysController.shared.requestAccessibilityPermission()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func hotkeyRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Win32Colors.text)
        }
    }
    
    // MARK: - Section 3: Audio Fading
    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Fading & Transitions") {
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
            }
        }
    }
    
    // MARK: - Section: Audio Output Devices
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Audio Output Device") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select where MacAmp routes sound (Bluetooth, HDMI, USB DAC, or Built-in):")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // System Default option
                        let isDefaultSelected = (viewModel.selectedAudioOutputDeviceUID == nil)
                        let defaultName = AudioDeviceManager.shared.defaultDevice?.name ?? "Internal Speakers"
                        let defaultTransport = AudioDeviceManager.shared.defaultDevice?.transportType.rawValue ?? "Built-in"
                        
                        Win32RadioButton("System Default (Follow macOS Sound Settings)", isSelected: isDefaultSelected) {
                            viewModel.selectOutputDevice(uid: nil)
                        }
                        
                        Text("  Currently active: [\(defaultTransport)] \(defaultName)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.leading, 18)
                        
                        Divider().padding(.vertical, 2)
                        
                        // Specific hardware devices
                        ForEach(viewModel.availableOutputDevices) { device in
                            let isSelected = (viewModel.selectedAudioOutputDeviceUID == device.uid)
                            HStack(spacing: 6) {
                                Win32RadioButton(device.displayName, isSelected: isSelected) {
                                    viewModel.selectOutputDevice(uid: device.uid)
                                }
                                if device.isDefault {
                                    Text("(macOS Default)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .modifier(Win32SunkenBorder())
                    
                    HStack {
                        Spacer()
                        Win32Button("Refresh Devices", width: 120, height: 22) {
                            viewModel.refreshOutputDevices()
                        }
                    }
                }
            }
            
            // Active Device Details
            if let active = AudioDeviceManager.shared.activeDevice {
                Win32GroupBox("Active Output Device Details") {
                    VStack(alignment: .leading, spacing: 5) {
                        detailRow("Device Name:", active.name)
                        detailRow("Transport:", active.transportType.rawValue)
                        detailRow("Channels:", "\(active.channelCount) channels")
                        detailRow("Sample Rate:", "\(Int(active.sampleRate)) Hz")
                        detailRow("Status:", "Connected & Ready")
                    }
                    .padding(6)
                }
            }
        }
    }
    
    private func detailRow(_ label: String, _ val: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Win32Colors.text)
                .frame(width: 90, alignment: .leading)
            Text(val)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Section: DSP Effects
    private var dspSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Digital Signal Processing (DSP)") {
                VStack(alignment: .leading, spacing: 8) {
                    Win32Checkbox("Enable DSP Audio Effects", isOn: $viewModel.isDspEnabled)
                    
                    HStack {
                        Spacer()
                        Win32Button("Reset DSP to Default", width: 140, height: 21) {
                            viewModel.resetDSP()
                        }
                    }
                }
            }
            
            Win32GroupBox("Pitch & Speed (TimePitch)") {
                VStack(alignment: .leading, spacing: 10) {
                    // Pitch Shift
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Pitch Shift:")
                                .font(.system(size: 11))
                                .foregroundColor(Win32Colors.text)
                            Spacer()
                            let semi = Int(round(viewModel.dspPitchSemitones))
                            Text(semi == 0 ? "Normal (0 semitones)" : (semi > 0 ? "+\(semi) semitones" : "\(semi) semitones"))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Win32Colors.text)
                        }
                        
                        Slider(value: $viewModel.dspPitchSemitones, in: -12.0...12.0, step: 1.0)
                    }
                    
                    // Tempo / Playback Rate
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Playback Speed / Tempo:")
                                .font(.system(size: 11))
                                .foregroundColor(Win32Colors.text)
                            Spacer()
                            Text(String(format: "%.2fx", viewModel.dspPlaybackRate))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Win32Colors.text)
                        }
                        
                        Slider(value: $viewModel.dspPlaybackRate, in: 0.5...2.0, step: 0.05)
                    }
                }
            }
            
            Win32GroupBox("Reverb & Spatial Acoustics") {
                VStack(alignment: .leading, spacing: 10) {
                    // Reverb Mix
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Reverb Wet / Dry Blend:")
                                .font(.system(size: 11))
                                .foregroundColor(Win32Colors.text)
                            Spacer()
                            Text("\(Int(viewModel.dspReverbMix))%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Win32Colors.text)
                        }
                        
                        Slider(value: $viewModel.dspReverbMix, in: 0.0...100.0, step: 1.0)
                    }
                    
                    // Reverb Presets
                    Text("Acoustic Preset:")
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.text)
                    
                    let reverbPresets = [
                        "Small Room",
                        "Medium Room",
                        "Large Room",
                        "Medium Hall",
                        "Large Hall",
                        "Plate Reverb",
                        "Cathedral"
                    ]
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<reverbPresets.count, id: \.self) { idx in
                            Win32RadioButton(reverbPresets[idx], isSelected: viewModel.dspReverbPreset == idx) {
                                viewModel.dspReverbPreset = idx
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Section 4: Equalizer
    private var equalizerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Equalizer Preferences") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Auto-load EQ preset based on track's ID3 Genre", isOn: $viewModel.autoGenreEQ)
                    
                    Text("When a track starts playing, automatically applies matching EQ curve (Rock, Pop, Jazz, Metal, etc.).")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.leading, 18)
                }
            }
        }
    }
    
    // MARK: - Section 5: Playlist
    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Track Item Display") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Zero-pad track numbers in playlist (e.g. '01.' instead of '1.')", isOn: $viewModel.playlistZeroPadding)
                    Win32Checkbox("Show file extensions in playlist if title is missing (.mp3, .flac)", isOn: $viewModel.playlistShowExtensions)
                }
            }
            
            Win32GroupBox("Playback Shuffle Engine") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Authentic Winamp pseudo-random shuffle (remembers played tracks without repeats)", isOn: $viewModel.authenticShuffle)
                }
            }
        }
    }
    
    // MARK: - Section 6: Skins
    private var skinsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Installed Classic Skins") {
                VStack(alignment: .leading, spacing: 8) {
                    // White sunken list box
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            // Base skin
                            let isBaseSelected = (viewModel.selectedSkinURL == nil)
                            Button(action: { viewModel.selectSkin(url: nil) }) {
                                HStack {
                                    Text(isBaseSelected ? "●" : "○")
                                        .font(.system(size: 9))
                                    Text("Classic Winamp 2.91 (Base Skin)")
                                        .font(.system(size: 11, weight: isBaseSelected ? .bold : .regular))
                                    Spacer()
                                    Text("[Bundled]")
                                        .font(.system(size: 9))
                                        .foregroundColor(isBaseSelected ? .white.opacity(0.8) : .secondary)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .foregroundColor(isBaseSelected ? .white : Win32Colors.text)
                                .background(isBaseSelected ? Win32Colors.selectionHighlight : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            
                            // Installed skins
                            ForEach(viewModel.installedSkins, id: \.self) { skinURL in
                                let isSelected = (viewModel.selectedSkinURL?.path == skinURL.path)
                                Button(action: { viewModel.selectSkin(url: skinURL) }) {
                                    HStack {
                                        Text(isSelected ? "●" : "○")
                                            .font(.system(size: 9))
                                        Text(skinURL.deletingPathExtension().lastPathComponent)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                        Spacer()
                                        Text(skinURL.pathExtension.uppercased())
                                            .font(.system(size: 9))
                                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .foregroundColor(isSelected ? .white : Win32Colors.text)
                                    .background(isSelected ? Win32Colors.selectionHighlight : Color.clear)
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                            }
                        }
                    }
                    .frame(height: 140)
                    .background(Color.white)
                    .win32Sunken()
                    
                    HStack(spacing: 8) {
                        Win32Button("Install Skin...", width: 100, height: 23) {
                            viewModel.installSkin()
                        }
                        
                        Win32Button("Open Skins Folder", width: 130, height: 23) {
                            viewModel.openSkinsFolder()
                        }
                        
                        Spacer()
                    }
                }
            }
        }
    }
}
