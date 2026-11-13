import SwiftUI
import CGoom
import AppKit

// MARK: - Preferences tree (Winamp 2.95: docs/UI-screens/pref-*.png)
/// Every node is a page, top-level ones included (Setup, Options, Plug-ins, Skins, Bookmarks), as in 2.95.
/// Video, Library and CD Ripping join Options when those features exist.
public enum PrefTreeItem: String, CaseIterable, Identifiable {
    case setup, fileTypes, agent
    case options, display, visualization, shuffle, video, library, cdRipping
    case plugins, input, output, visPlugin, dsp, general
    case skins, bookmarks
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .setup: return "Setup"
        case .fileTypes: return "File types"
        case .agent: return "Agent"
        case .options: return "Options"
        case .display: return "Display"
        case .visualization, .visPlugin: return "Visualization"
        case .shuffle: return "Shuffle"
        case .video: return "Video"
        case .library: return "Library"
        case .cdRipping: return "CD Ripping"
        case .plugins: return "Plug-ins"
        case .input: return "Input"
        case .output: return "Output"
        case .dsp: return "DSP/Effect"
        case .general: return "General Purpose"
        case .skins: return "Skins"
        case .bookmarks: return "Bookmarks"
        }
    }
    
    /// The node this page hangs under; nil for top-level nodes.
    public var parent: PrefTreeItem? {
        switch self {
        case .fileTypes, .agent: return .setup
        case .display, .visualization, .shuffle, .video, .library, .cdRipping: return .options
        case .input, .output, .visPlugin, .dsp, .general: return .plugins
        default: return nil
        }
    }
    
    public static var topLevel: [PrefTreeItem] { allCases.filter { $0.parent == nil } }
    public var children: [PrefTreeItem] { PrefTreeItem.allCases.filter { $0.parent == self } }
}

// MARK: - Preferences View Model
@MainActor
public class PreferencesViewModel: ObservableObject {
    @Published public var selectedTreeItem: PrefTreeItem = .setup
    
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
        didSet { PlayerCoordinator.shared.setScale(scaleFactor) }
    }
    @Published var interfaceScale: InterfaceScale {
        didSet { PlayerCoordinator.shared.setInterfaceScale(interfaceScale) }
    }
    
    // Titles & Display State
    @Published public var marqueeFontMode: MarqueeFontMode {
        didSet {
            PersistenceManager.shared.state.marqueeFontMode = marqueeFontMode
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
            PlayerCoordinator.shared.mainView?.marquee.fontSettingsChanged()
        }
    }
    
    @Published public var desktopFontFamily: String {
        didSet {
            PersistenceManager.shared.state.desktopFontFamily = desktopFontFamily
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
            PlayerCoordinator.shared.mainView?.marquee.fontSettingsChanged()
        }
    }
    
    @Published public var desktopFontSize: Double {
        didSet {
            PersistenceManager.shared.state.desktopFontSize = desktopFontSize
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
            PlayerCoordinator.shared.mainView?.marquee.fontSettingsChanged()
        }
    }
    
    @Published public var isMarqueeScrollEnabled: Bool {
        didSet {
            PersistenceManager.shared.state.isMarqueeScrollEnabled = isMarqueeScrollEnabled
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.marquee.needsDisplay = true
            PlayerCoordinator.shared.mainView?.marquee.fontSettingsChanged()
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
    
    @Published public var savePlaylistRelativePaths: Bool {
        didSet {
            PersistenceManager.shared.state.savePlaylistRelativePaths = savePlaylistRelativePaths
            PersistenceManager.shared.saveSession()
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
    @Published public var crossfadeSeconds: Double {
        didSet {
            PersistenceManager.shared.state.crossfadeSeconds = crossfadeSeconds
            PersistenceManager.shared.scheduleSave()
            AudioEngine.shared.crossfadeDuration = crossfadeSeconds
        }
    }
    
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
            if PlayerCoordinator.shared.mainView != nil {
                PlayerCoordinator.shared.setVisualizerMode(visualizerMode) // also re-gates the FFT tap
            }
        }
    }
    
    @Published public var visualizerShowPeaks: Bool {
        didSet {
            PersistenceManager.shared.state.visualizerShowPeaks = visualizerShowPeaks
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.visualizer.showPeaks = visualizerShowPeaks
        }
    }
    
    @Published public var manualPlaylistAdvance: Bool {
        didSet {
            PersistenceManager.shared.state.manualPlaylistAdvance = manualPlaylistAdvance
            PersistenceManager.shared.saveSession()
            MainMenuManager.shared.updateStates()
        }
    }
    
    @Published public var visualizerOptions: VisualizerOptions {
        didSet {
            PersistenceManager.shared.state.visualizerOptions = visualizerOptions
            PersistenceManager.shared.saveSession()
            PlayerCoordinator.shared.mainView?.visualizer.options = visualizerOptions
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
        self.interfaceScale = state.interfaceScale
        self.marqueeFontMode = state.marqueeFontMode
        self.desktopFontFamily = state.desktopFontFamily
        self.desktopFontSize = state.desktopFontSize
        self.isMarqueeScrollEnabled = state.isMarqueeScrollEnabled
        self.showTrackNumberInTitle = state.showTrackNumberInTitle
        self.windowSnapDistance = state.windowSnapDistance
        self.showNumbersInPlaylist = state.showNumbersInPlaylist
        self.playlistZeroPadding = state.playlistZeroPadding
        self.playlistShowExtensions = state.playlistShowExtensions
        self.savePlaylistRelativePaths = state.savePlaylistRelativePaths
        self.authenticShuffle = state.authenticShuffle
        self.audioFadeOutDurationMs = state.audioFadeOutDurationMs
        self.crossfadeSeconds = state.crossfadeSeconds
        self.autoGenreEQ = state.autoGenreEQ
        self.isGlobalHotkeysEnabled = state.isGlobalHotkeysEnabled
        self.isDspEnabled = state.isDspEnabled
        self.dspPitchSemitones = state.dspPitchSemitones
        self.dspPlaybackRate = state.dspPlaybackRate
        self.dspReverbMix = state.dspReverbMix
        self.dspReverbPreset = state.dspReverbPreset
        self.visualizerMode = state.visualizerMode
        self.visualizerShowPeaks = state.visualizerShowPeaks
        self.visualizerOptions = state.visualizerOptions
        self.manualPlaylistAdvance = state.manualPlaylistAdvance
        
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
    
    /// Skins ▸ "Set skins directory...": list (and install) skins from another folder
    public func chooseSkinsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = SkinManager.shared.skinsDirectory
        panel.message = "Choose the folder MacAmp lists skins from"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        PersistenceManager.shared.state.skinsDirectoryPath = url.path
        PersistenceManager.shared.saveSession()
        refreshSkins()
    }
}

// MARK: - TreeView Dotted Branch Connector
public struct TreeConnector: View {
    public let isLast: Bool
    /// The dotted branches' grey (also the AVS editor's tree)
    public static let lineColor = Color(white: 0.65)
    public var color = lineColor
    public var height: CGFloat = 18
    
    public init(isLast: Bool, color: Color = lineColor, height: CGFloat = 18) {
        self.isLast = isLast
        self.color = color
        self.height = height
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
            
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [1, 1]))
        }
        .frame(width: 16, height: height)
    }
}

// MARK: - Preferences View
public struct PreferencesView: View {
    @ObservedObject public var viewModel: PreferencesViewModel
    @ObservedObject private var hotkeysController = GlobalHotkeysController.shared
    public var onClose: (() -> Void)?
    
    private let availableFonts = ["Monaco", "Menlo", "Geneva", "SF Pro Display", "Courier New", "Helvetica"]
    private let availableFontSizes: [Double] = [8, 9, 10, 11, 12, 14]
    
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
                        ForEach(PrefTreeItem.topLevel) { item in
                            treeRow(item, isLast: false, indented: false)
                            let children = item.children
                            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                                treeRow(child, isLast: index == children.count - 1, indented: true)
                            }
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
                        case .setup: SetupSection()
                        case .fileTypes: FileTypesSection()
                        case .agent: AgentSection()
                        case .options: optionsSection
                        case .display: displaySection
                        case .visualization: visualizationSection
                        case .shuffle: shuffleSection
                        case .video: videoSection
                        case .library: librarySection
                        case .cdRipping: cdRippingSection
                        case .plugins: pluginsSection
                        case .input: inputSection
                        case .output: outputPluginSection
                        case .visPlugin:
                            VStack(alignment: .leading, spacing: 10) {
                                visPluginSection
                                if PersistenceManager.shared.state.avsPluginSelected {
                                    avsSection
                                } else if PersistenceManager.shared.state.goomPluginSelected {
                                    goomSection
                                } else {
                                    milkdropSection
                                }
                            }
                        case .dsp: dspPluginSection
                        case .general: generalSection
                        case .skins: skinsSection
                        case .bookmarks: BookmarksSection()
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
    /// One tree node; every node is a page (Winamp 2.95 tree: plain text, dotted branches for children).
    private func treeRow(_ item: PrefTreeItem, isLast: Bool, indented: Bool) -> some View {
        let isSelected = viewModel.selectedTreeItem == item
        return Button(action: { viewModel.selectedTreeItem = item }) {
            HStack(spacing: 2) {
                if indented { TreeConnector(isLast: isLast) }
                Text(item.title)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white : Win32Colors.text)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(isSelected ? Win32Colors.selectionHighlight : Color.clear)
                Spacer()
            }
            .padding(.horizontal, indented ? 2 : 4)
            .padding(.vertical, indented ? 0 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
    
    /// A setting stored in AppState, redrawing the page when it changes.
    private func setting<Value>(_ keyPath: WritableKeyPath<AppState, Value>, onChange: ((Value) -> Void)? = nil) -> Binding<Value> {
        Binding(
            get: { PersistenceManager.shared.state[keyPath: keyPath] },
            set: { value in
                viewModel.objectWillChange.send()
                PersistenceManager.shared.state[keyPath: keyPath] = value
                PersistenceManager.shared.scheduleSave()
                onChange?(value)
            }
        )
    }
    
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    // MARK: - Options ▸ Display (docs/UI-screens/pref-options-display.png)
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Display options") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Always show Clutterbar", isOn: setting(\.alwaysShowClutterbar) { _ in
                        PlayerCoordinator.shared.mainView?.updateClutterbar()
                    })
                    Win32Checkbox("Display tooltips in MacAmp's main window", isOn: setting(\.mainWindowTooltips) { _ in
                        PlayerCoordinator.shared.applyMainWindowTooltips()
                    })
                    Win32Checkbox("Use Winamp-styled (skinned) cursors", isOn: setting(\.useSkinnedCursors) { _ in
                        PlayerCoordinator.shared.refreshAllViews()
                    })
                    Win32Checkbox("Dim titlebars when inactive", isOn: setting(\.dimTitlebars) { _ in
                        PlayerCoordinator.shared.refreshAllViews()
                    })
                    HStack(spacing: 6) {
                        Win32Checkbox("Snap Winamp windows at", isOn: .init(
                            get: { viewModel.windowSnapDistance > 0 },
                            set: { viewModel.windowSnapDistance = $0 ? 10 : 0 }
                        ))
                        .fixedSize() // inline "at [10] pixels", as in 2.95
                        Win32NumberField(value: $viewModel.windowSnapDistance, width: 28)
                        Text("pixels").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                        Spacer()
                    }
                    Win32Checkbox("Use bitmap font for main title display", isOn: .init(
                        get: { viewModel.marqueeFontMode == .bitmap },
                        set: { viewModel.marqueeFontMode = $0 ? .bitmap : .desktop }
                    ))
                    Win32Checkbox("Show numbers in Playlist", isOn: $viewModel.showNumbersInPlaylist)
                    HStack(spacing: 6) {
                        Text("Playlist font size").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                        Win32NumberField(value: Binding(
                            get: { PersistenceManager.shared.state.playlistFontSize },
                            set: {
                                setLibrary(\.playlistFontSize, $0)
                                PlayerCoordinator.shared.plView?.needsDisplay = true
                            }), width: 28)
                    }
                }
            }
            
            Win32GroupBox("Show MacAmp in:") {
                VStack(alignment: .leading, spacing: 4) {
                    // (Dock, menu bar), 2.95's Taskbar only / System tray only / Taskbar and system tray / None
                    ForEach([("Dock only", true, false), ("Menu bar only", false, true), ("Dock and menu bar", true, true), ("None", false, false)], id: \.0) { title, dock, menuBar in
                        Win32RadioButton(title, isSelected: PersistenceManager.shared.state.showDockIcon == dock && PersistenceManager.shared.state.showMenuBarIcon == menuBar) {
                            setLibrary(\.showDockIcon, dock)
                            setLibrary(\.showMenuBarIcon, menuBar)
                            StatusBarManager.shared.setVisible(menuBar)
                            StatusBarManager.shared.setDockIconVisible(dock)
                        }
                    }
                    note("Without the Dock icon MacAmp isn't in ⌘Tab and its menu bar menus are hidden; right-click a MacAmp window for the menu.")
                }
            }

            // MacAmp additions (principle 5: a separate group below the classic options)
            Win32GroupBox("MacAmp") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Always On Top (⌃A)", isOn: $viewModel.isAlwaysOnTop)
                    Win32Checkbox("Scroll the song title when it is wider than the display", isOn: $viewModel.isMarqueeScrollEnabled)
                    Win32Checkbox("Zero-pad numbers in Playlist (e.g. '01.')", isOn: $viewModel.playlistZeroPadding)
                    Win32Checkbox("Show file extensions in Playlist", isOn: $viewModel.playlistShowExtensions)
                    HStack(spacing: 12) {
                        Win32RadioButton("Normal size", isSelected: viewModel.scaleFactor == .x1) { viewModel.scaleFactor = .x1 }
                        Win32RadioButton("Double size (⌃D)", isSelected: viewModel.scaleFactor == .x2) { viewModel.scaleFactor = .x2 }
                    }
                    if viewModel.marqueeFontMode == .desktop {
                        HStack(spacing: 6) {
                            Text("Title font:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                            Win32ComboBox(selection: $viewModel.desktopFontFamily,
                                          options: availableFonts.map { (value: $0, title: $0) }, width: 140)
                            Win32ComboBox(selection: $viewModel.desktopFontSize,
                                          options: availableFontSizes.map { (value: $0, title: "\(Int($0)) pt") }, width: 64)
                        }
                    }
                }
            }
            Win32GroupBox("Interface scale") {
                HStack(spacing: 12) {
                    ForEach(InterfaceScale.allCases, id: \.rawValue) { scale in
                        Win32RadioButton("\(scale.rawValue)%", isSelected: viewModel.interfaceScale == scale) { viewModel.interfaceScale = scale }
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
                    Win32RadioButton("Spectrum analyzer", isSelected: viewModel.visualizerMode == .spectrum) {
                        viewModel.visualizerMode = .spectrum
                    }
                    
                    Win32RadioButton("Oscilloscope", isSelected: viewModel.visualizerMode == .oscilloscope) {
                        viewModel.visualizerMode = .oscilloscope
                    }
                    
                    Win32RadioButton("Off", isSelected: viewModel.visualizerMode == .off) {
                        viewModel.visualizerMode = .off
                    }
                    HStack(spacing: 6) {
                        Text("Refresh rate:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                        Win32Slider(value: Binding(
                            get: { PersistenceManager.shared.state.visualizerFPS },
                            set: { value in
                                viewModel.objectWillChange.send()
                                PersistenceManager.shared.state.visualizerFPS = value
                                PersistenceManager.shared.scheduleSave()
                            }), in: 10...40, step: 5)
                            .frame(width: 140)
                        Text("\(Int(PersistenceManager.shared.state.visualizerFPS))fps")
                            .font(.system(size: 11)).foregroundColor(Win32Colors.text)
                    }
                }
            }
            
            Win32GroupBox("Analyzer Options") {
                VStack(alignment: .leading, spacing: 6) {
                    visOptionRow("Style:", Win32ComboBox(selection: $viewModel.visualizerOptions.analyzerStyle,
                                                         options: AnalyzerStyle.allCases.map { (value: $0, title: $0.title) }, width: 130))
                    visOptionRow("Bands:", Win32ComboBox(selection: $viewModel.visualizerOptions.bands,
                                                         options: AnalyzerBands.allCases.map { (value: $0, title: $0.title) }, width: 130))
                    visOptionRow("Bar falloff:", Win32ComboBox(selection: $viewModel.visualizerOptions.barFalloff,
                                                               options: VisualizerFalloff.allCases.map { (value: $0, title: $0.title) }, width: 130))
                    visOptionRow("Peak falloff:", Win32ComboBox(selection: $viewModel.visualizerOptions.peakFalloff,
                                                                options: VisualizerFalloff.allCases.map { (value: $0, title: $0.title) }, width: 130))
                    Win32Checkbox("Show peaks", isOn: $viewModel.visualizerShowPeaks)
                }
            }
            
            Win32GroupBox("Oscilloscope Options") {
                visOptionRow("Style:", Win32ComboBox(selection: $viewModel.visualizerOptions.scopeStyle,
                                                     options: ScopeStyle.allCases.map { (value: $0, title: $0.title) }, width: 130))
            }
            
            Text("Tip: right-click the visualizer in the main window for the same options.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    private func visOptionRow<Control: View>(_ label: String, _ control: Control) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
                .frame(width: 80, alignment: .trailing)
            control
            Spacer()
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
                        ForEach(hotkeysController.displayRows, id: \.action) { row in
                            hotkeyRow(row.action, row.shortcut)
                        }
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .modifier(Win32SunkenBorder())
                    
                    if viewModel.isGlobalHotkeysEnabled && !hotkeysController.unavailableHotkeys.isEmpty {
                        Text("Already used by another application: \(hotkeysController.unavailableHotkeys.joined(separator: ", "))")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Win32GroupBox("Media Keys") {
                Text("Hardware media keys (F7, F8, F9), AirPods and headphone controls work globally. No special permissions are required.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .font(.system(size: 12, weight: .medium)) // system font draws ⌃ ⌥ like the macOS menus
                .foregroundColor(Win32Colors.text)
        }
    }
    
    // MARK: - Options (docs/UI-screens/pref-options.png)
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Options") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Convert %20 to space in titles", isOn: setting(\.convertPercent20) { _ in
                        PlayerCoordinator.shared.refreshAllViews()
                    })
                    Win32Checkbox("Convert underscore to space in titles", isOn: setting(\.convertUnderscore) { _ in
                        PlayerCoordinator.shared.refreshAllViews()
                    })
                    Win32Checkbox("Sort files on load", isOn: setting(\.sortFilesOnLoad))
                    Win32Checkbox("Single-click playlist buttons (old-school)", isOn: setting(\.playlistSingleClickButtons) { _ in
                        PlayerCoordinator.shared.plView?.applyMenuButtonMode()
                    })
                    Win32Checkbox("Equalizer doublesize linked", isOn: Binding(
                        get: { PersistenceManager.shared.state.eqDoubleSizeLinked },
                        set: { viewModel.objectWillChange.send(); PlayerCoordinator.shared.setEqDoubleSizeLinked($0) }))
                    Win32Checkbox("Manual playlist advance (i.e. no automatic)", isOn: Binding(
                        get: { viewModel.manualPlaylistAdvance },
                        set: { viewModel.manualPlaylistAdvance = $0 }
                    ))
                }
            }
            
            // MacAmp additions
            Win32GroupBox("MacAmp: playback") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Fade out on Pause/Stop:").font(.system(size: 11))
                        Spacer()
                        Text("\(Int(viewModel.audioFadeOutDurationMs)) ms").font(.system(size: 11, design: .monospaced))
                    }
                    Win32Slider(value: $viewModel.audioFadeOutDurationMs, in: 0...2000, step: 50)
                    HStack {
                        Text("Crossfade between tracks:").font(.system(size: 11))
                        Spacer()
                        Text(viewModel.crossfadeSeconds > 0 ? "\(Int(viewModel.crossfadeSeconds)) s" : "Off")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    Win32Slider(value: $viewModel.crossfadeSeconds, in: 0...10, step: 1)
                    note("Crossfade: files only; not with Stop after current, Manual advance or inside a CUE album.")
                }
            }
            
            Win32GroupBox("MacAmp: playlists and equalizer") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Save playlists with paths relative to the playlist file", isOn: $viewModel.savePlaylistRelativePaths)
                    Win32Checkbox("Auto-load EQ preset by the track's genre", isOn: $viewModel.autoGenreEQ)
                }
            }
        }
    }
    
    // MARK: - Options ▸ Shuffle
    private var shuffleSection: some View {
        Win32GroupBox("Shuffle options") {
            VStack(alignment: .leading, spacing: 8) {
                Win32GroupBox("Shuffle morph rate") {
                    VStack(alignment: .leading, spacing: 4) {
                        Win32Slider(value: Binding(
                            get: { PersistenceManager.shared.state.shuffleMorphRate },
                            set: { value in
                                viewModel.objectWillChange.send()
                                PersistenceManager.shared.state.shuffleMorphRate = value
                                PersistenceManager.shared.scheduleSave()
                            }
                        ), in: 0...1, step: 0.05)
                        HStack {
                            Text("Slow").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                            Spacer()
                            Text("Fast").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                        }
                        note("The shuffle morph rate controls how new songs are picked when in shuffle mode. In slow morph mode, a slight variation of the same playlist is played each time through, whereas on fast shuffle mode major changes happen each time through.\nThe default is very close to 'Fast'.")
                    }
                }
                Win32Checkbox("Play every track once before repeating", isOn: $viewModel.authenticShuffle)
            }
        }
    }
    
    // MARK: - Video (docs/UI-screens/pref-options-video.png)
    private var videoSection: some View {
        Win32GroupBox("Video options") {
            VStack(alignment: .leading, spacing: 6) {
                Win32Checkbox("Maintain video aspect ratio", isOn: setting(\.videoKeepAspect) { _ in PlayerCoordinator.shared.video?.applyOptions() })
                Win32Checkbox("Auto open video window", isOn: setting(\.videoAutoOpen))
                Win32Checkbox("Auto resize video window to video dimensions", isOn: setting(\.videoAutoResize))
                Win32Checkbox("Auto close video window after playing", isOn: setting(\.videoAutoClose))
                Win32Checkbox("Remove fullscreen on stop", isOn: setting(\.videoRemoveFullscreenOnStop))
                Win32Checkbox("Disable screensaver when in fullscreen mode", isOn: setting(\.videoDisableScreensaver))
                Win32Checkbox("Stop playback on video window close", isOn: setting(\.videoStopOnClose))
                note("MacAmp plays MP4, M4V and MOV with the decoders macOS has; the sound goes through the equalizer and visualization like any track.")
            }
        }
    }
    
    // MARK: - CD Ripping (Library ▸ Devices ▸ CD ▸ Extract)
    private var cdRippingSection: some View {
        let state = PersistenceManager.shared.state
        return VStack(alignment: .leading, spacing: 8) {
            Win32GroupBox("Output File") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Folder:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                        Text(state.cdRipFolder.path)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                            .background(Color.white)
                            .win32Sunken()
                        Win32Button("Browse...", width: 76) {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.canCreateDirectories = true
                            panel.directoryURL = state.cdRipFolder
                            if panel.runModal() == .OK, let url = panel.url {
                                viewModel.objectWillChange.send()
                                PersistenceManager.shared.state.cdRipFolder = url
                                PersistenceManager.shared.scheduleSave()
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Naming:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                        Win32TextField(text: Binding(
                            get: { PersistenceManager.shared.state.cdRipTemplate },
                            set: { value in
                                viewModel.objectWillChange.send()
                                PersistenceManager.shared.state.cdRipTemplate = value
                                PersistenceManager.shared.scheduleSave()
                            }))
                    }
                    note("<Artist> <Album> <Title> <Year> <#> (track number); / makes a folder.")
                }
            }
            Win32GroupBox("Encoder") {
                HStack(spacing: 6) {
                    Text("Format:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                    Win32ComboBox(selection: Binding(
                        get: { PersistenceManager.shared.state.cdRipFormat },
                        set: { format in
                            viewModel.objectWillChange.send()
                            PersistenceManager.shared.state.cdRipFormat = format
                            PersistenceManager.shared.scheduleSave()
                        }), options: DiskWriterFormat.allCases.map { (value: $0, title: $0.title) }, width: 190)
                    if state.cdRipFormat == .aac {
                        Text("Bitrate:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                        Win32ComboBox(selection: Binding(
                            get: { PersistenceManager.shared.state.cdRipAACKbps },
                            set: { setLibrary(\.cdRipAACKbps, $0) }), options: DiskWriterFormat.aacBitrates.map { (value: $0, title: "\($0) kbps") }, width: 80)
                    }
                    Spacer()
                }
            }
            Win32GroupBox("Tags / Library") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Write tags (FLAC, M4A), with the comment \"Extracted by MacAmp\"", isOn: setting(\.cdRipWriteTags))
                    Win32Checkbox("Add ripped files to the Media Library", isOn: setting(\.cdRipAddToLibrary))
                    note("Track names come from MusicBrainz (CDDB is gone). To rip: Media Library (⌥L) ▸ Devices ▸ CD ▸ Extract; playing a CD doesn't rip it.")
                }
            }
            Win32GroupBox("Playlist") {
                VStack(alignment: .leading, spacing: 6) {
                    note("(Playlists will only be generated when an entire CD is extracted)")
                    Win32Checkbox("Generate M3U playlist of extracted tracks", isOn: setting(\.cdRipM3U))
                    Win32Checkbox("Use extended M3U playlist format", isOn: setting(\.cdRipExtendedM3U))
                        .padding(.leading, 16)
                        .disabled(!state.cdRipM3U)
                    Win32Checkbox("Generate PLS playlist of extracted tracks", isOn: setting(\.cdRipPLS))
                    HStack(spacing: 6) {
                        Text("Filename format:").font(.system(size: 11)).foregroundColor(Win32Colors.text).fixedSize()
                        Win32TextField(text: Binding(
                            get: { PersistenceManager.shared.state.cdRipPlaylistTemplate },
                            set: { setLibrary(\.cdRipPlaylistTemplate, $0) }))
                    }
                    Win32Checkbox("Create playlist of extracted tracks in library", isOn: setting(\.cdRipLibraryPlaylist))
                }
            }
        }
    }
    
    // MARK: - Media Library (Library ▸ Library preferences...)
    private var librarySection: some View {
        Win32TabView(tabs: LibraryPrefsTab.allCases, selectedTab: $libraryTab) {
            if libraryTab == .general { libraryGeneralTab } else { libraryRadioTab }
        }
    }

    private var libraryGeneralTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Action on doubleclick/enter:").font(.system(size: 11)).foregroundColor(Win32Colors.text).fixedSize()
                Win32RadioButton("Play", isSelected: !PersistenceManager.shared.state.libraryDoubleClickEnqueues) { setLibrary(\.libraryDoubleClickEnqueues, false) }
                    .fixedSize()
                Win32RadioButton("Enqueue", isSelected: PersistenceManager.shared.state.libraryDoubleClickEnqueues) { setLibrary(\.libraryDoubleClickEnqueues, true) }
                    .fixedSize()
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 8) {
                Text("Column resizing:").font(.system(size: 11)).foregroundColor(Win32Colors.text).fixedSize()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([("Normal", 0), ("Selected column only", 1), ("Proportional", 2)], id: \.1) { title, mode in
                        Win32RadioButton(title, isSelected: PersistenceManager.shared.state.libraryColumnResizing == mode) { setLibrary(\.libraryColumnResizing, mode) }
                    }
                }
            }
            Win32Checkbox("Remember search filters", isOn: setting(\.libraryRememberSearch))
            Win32Checkbox("Play entire playlist on playlist item doubleclick", isOn: setting(\.libraryPlayWholePlaylist))
            Win32Checkbox("Play entire query on single query item doubleclick", isOn: setting(\.libraryPlayWholeQuery))
            Win32Checkbox("Open library on main window lightning bolt click", isOn: setting(\.libraryOnLightningBolt))
            Win32Checkbox("Open library to Video view on video/TV button click", isOn: setting(\.libraryTVButtonOpensVideo))
            // MacAmp's own (principle: new things in their own group at the bottom)
            Win32GroupBox("Library folders") {
                VStack(alignment: .leading, spacing: 6) {
                    Win32Checkbox("Rescan library folders at startup", isOn: setting(\.libraryRescanOnStart))
                    HStack(spacing: 6) {
                        Win32Button("Add directory to library...", width: nil) { LibraryActions.addDirectory() }
                        Win32Button("Rescan now", width: nil) { Task { await MediaLibrary.shared.rescan() } }
                    }
                    note("Folders: " + (MediaLibrary.shared.folders.isEmpty ? "none" : MediaLibrary.shared.folders.map(\.path).joined(separator: ", ")))
                }
            }
        }
        .padding(8)
    }

    private var libraryRadioTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Max. streams to fetch:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                Win32NumberField(value: Binding(
                    get: { PersistenceManager.shared.state.libraryMaxStreams },
                    set: { setLibrary(\.libraryMaxStreams, min(10_000, max(10, $0))) }), width: 50)
            }
            HStack(alignment: .top, spacing: 8) {
                Text("Automatic refresh frequency:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([("Hourly", 1), ("Daily", 24), ("Weekly", 168), ("Never", 0)], id: \.1) { title, hours in
                        Win32RadioButton(title, isSelected: PersistenceManager.shared.state.radioRefreshHours == hours) { setLibrary(\.radioRefreshHours, hours) }
                    }
                }
            }
            note("Stations come from radio-browser.info (the SHOUTcast directory 2.95 used is gone).")
        }
        .padding(8)
    }

    private func setLibrary<V>(_ keyPath: WritableKeyPath<AppState, V>, _ value: V) {
        viewModel.objectWillChange.send()
        PersistenceManager.shared.state[keyPath: keyPath] = value
        PersistenceManager.shared.scheduleSave()
    }
    
    // MARK: - Plug-ins (docs/UI-screens/pref-plugins*.png). MacAmp's plug-ins are built in.
    private var pluginsSection: some View {
        Win32GroupBox("Plug-in settings") {
            VStack(alignment: .leading, spacing: 6) {
                Win32Checkbox("Auto execute visualization plug-in on play", isOn: setting(\.autoStartVisPlugin))
                note("MacAmp's plug-ins are built in: decoders (Input), audio output, the visualizer studio, effects (DSP) and global hotkeys. Each has its page below.")
            }
        }
    }
    
    private static let inputPlugins: [(name: String, formats: String)] = [
        ("MacAmp MPEG Audio Decoder \(AppConstants.App.version) [in_mp3]", "MP3, MP2, MP1, AAC; SHOUTcast / Icecast streams"),
        ("MacAmp Lossless Decoder \(AppConstants.App.version) [in_flac]", "FLAC, ALAC, WAV, AIFF, AU, SND"),
        ("MacAmp Ogg Decoder \(AppConstants.App.version) [in_vorbis]", "Ogg Vorbis, Opus"),
        ("MacAmp CUE Sheet Reader \(AppConstants.App.version) [in_cue]", "CUE: one album file split into tracks"),
        ("MacAmp MIDI Player \(AppConstants.App.version) [in_midi]", "MID, MIDI, RMI, KAR — played with the macOS General MIDI synth"),
    ]
    @State private var selectedInput = 0
    @State private var skinDescription = ""
    @State private var libraryTab = LibraryPrefsTab.general
    
    private var inputSection: some View {
        // Built-in decoders, then installed plug-ins (Plug-ins folder)
        let plugins = PluginManager.converters.map { (name: $0.title, formats: $0.extensions.sorted().map { $0.uppercased() }.joined(separator: ", ") + " (converted once for playback)") }
        let all = PreferencesView.inputPlugins + plugins
        return Win32GroupBox("Input plug-ins") {
            VStack(alignment: .leading, spacing: 6) {
                PluginListBox(rows: all.map(\.name), selection: $selectedInput)
                note("Formats: " + all[min(selectedInput, all.count - 1)].formats)
                HStack(spacing: 8) {
                    if plugins.isEmpty { note("MKV, WebM, AVI, WMV, WMA, APE, WavPack and more: install the FFmpeg plug-in.") }
                    Spacer()
                    Button("Get plug-ins") { NSWorkspace.shared.open(AppConstants.App.pluginsPage) }
                        .buttonStyle(.link).font(.system(size: 11))
                }
            }
        }
    }
    
    private var outputPluginSection: some View {
        let state = PersistenceManager.shared.state
        return VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("Output plug-ins (current plug-in is selected)") {
                PluginListBox(rows: ["MacAmp Core Audio output \(AppConstants.App.version) [out_coreaudio]",
                                     "MacAmp Disk Writer \(AppConstants.App.version) [out_disk]"],
                              selection: Binding(
                                get: { state.diskWriterEnabled ? 1 : 0 },
                                set: { index in
                                    viewModel.objectWillChange.send()
                                    PersistenceManager.shared.state.diskWriterEnabled = index == 1
                                    PersistenceManager.shared.scheduleSave()
                                }), height: 40)
            }
            if state.diskWriterEnabled {
                Win32GroupBox("Disk Writer") {
                    VStack(alignment: .leading, spacing: 8) {
                        note("Play writes the playlist, from the selected track to the end, into audio files instead of playing it. Stop cancels.")
                        HStack(spacing: 6) {
                            Text("Folder:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                            Text(state.diskWriterFolder.path)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                                .background(Color.white)
                                .win32Sunken()
                            Win32Button("Browse...", width: 76) { chooseDiskWriterFolder() }
                        }
                        HStack(spacing: 6) {
                            Text("Format:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                            Win32ComboBox(selection: Binding(
                                get: { PersistenceManager.shared.state.diskWriterFormat },
                                set: { format in
                                    viewModel.objectWillChange.send()
                                    PersistenceManager.shared.state.diskWriterFormat = format
                                    PersistenceManager.shared.scheduleSave()
                                }), options: DiskWriterFormat.allCases.map { (value: $0, title: $0.title) }, width: 190)
                            Spacer()
                        }
                    }
                }
            } else {
                outputSection
            }
        }
    }
    
    private func chooseDiskWriterFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = PersistenceManager.shared.state.diskWriterFolder
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.objectWillChange.send()
            PersistenceManager.shared.state.diskWriterFolder = url
            PersistenceManager.shared.scheduleSave()
        }
    }
    
    private var visPluginSection: some View {
        Win32GroupBox("Visualization plug-ins") {
            VStack(alignment: .leading, spacing: 8) {
                let goom = setting(\.goomPluginSelected)
                let avs = setting(\.avsPluginSelected)
                PluginListBox(rows: ["MacAmp Retro Visualizer Studio \(AppConstants.App.version) [vis_studio]", "What A Goom! v1.99.4",
                                     "\(AVSView.productName) [vis_avs]"],
                              selection: Binding(get: { avs.wrappedValue ? 2 : goom.wrappedValue ? 1 : 0 },
                                                 set: { goom.wrappedValue = $0 == 1; avs.wrappedValue = $0 == 2 }))
                HStack(spacing: 6) {
                    Win32Button("Start", width: 70) {
                        PlayerCoordinator.shared.startVisualizerStudio()
                    }
                    Win32Button("Stop", width: 70) {
                        if PlayerCoordinator.shared.visualizerStudioWindow?.isVisible == true { PlayerCoordinator.shared.toggleVisualizerStudio() }
                    }
                    Win32Button("Configure", width: 80) { PlayerCoordinator.shared.handleConfigureVisPlugin() }
                }
            }
        }
    }

    /// Modern, so it sits in its own group at the bottom of the page (not in Winamp 2.95)
    private var milkdropSection: some View {
        Win32GroupBox("Milkdrop (modern)") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Use Tab to switch Studio modes. In MilkDrop, L opens presets. Use ↑ / ↓, scroll or click to load the highlighted preset immediately. , / . switch presets directly and F5 shows FPS.")
                    .font(.system(size: 11)).foregroundColor(Win32Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Win32Button("Open presets folder", width: 140) {
                        MilkdropView.openPresetsFolder()
                    }
                    // Not bundled: 131 MB and no clear license; projectM's default pack, unzip into the folder
                    Win32Button("Get presets", width: 90) {
                        NSWorkspace.shared.open(URL(string: "https://github.com/projectM-visualizer/presets-cream-of-the-crop")!)
                    }
                    Spacer()
                }
                Win32Checkbox("Random order", isOn: setting(\.milkdropShuffle))
                Win32Checkbox("Sharp Retina rendering (slower; applies when Milkdrop is selected again)", isOn: setting(\.milkdropRetina))
                HStack(spacing: 6) {
                    Text("Next preset after:").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                    Win32ComboBox(selection: setting(\.milkdropSeconds),
                                  options: [15, 30, 60, 120, 300].map { (value: $0, title: "\($0) seconds") }, width: 120)
                    Spacer()
                }
            }
        }
    }

    /// AVS 2.6.1 Settings ▸ Presets/Hotkeys, and the presets folder (Winamp's Plugins\avs)
    private var avsSection: some View {
        Win32GroupBox("Advanced Visualization Studio") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Win32Checkbox("Randomly switch presets every", isOn: setting(\.avsRandomSwitch))
                    Win32NumberField(value: setting(\.avsRandomSeconds))
                    Text("seconds").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                    Spacer()
                }
                HStack(spacing: 6) {
                    Win32Button("Presets folder", width: 100) {
                        AVSPresets.prepareFolder()
                        NSWorkspace.shared.open(AVSPresets.folder)
                    }
                    Win32Button("Import presets...", width: 110) { AVSPresets.importWithPanel() }
                    // The Winamp 2.95 pack (112 presets, newpicks) is a separate download, as the FFmpeg plug-in
                    Win32Button("Get presets", width: 90) { NSWorkspace.shared.open(AppConstants.App.pluginsPage) }
                    Spacer()
                }
                note("Right-click the AVS window for presets. Space: random preset, U / Y: next / previous, R: random switching, T: preset name, F: frame rate, F1-F12 and 0-9: load a hotkey preset (with ⌃ save it), ⌥Return: full screen. Get presets: the Winamp 2.95 pack (112 presets); open it with MacAmp to install. Import copies .avs files or folders, e.g. Winamp's Plugins\\avs.")
            }
        }
    }

    private var goomSection: some View {
        Win32GroupBox("What A Goom!") {
            VStack(alignment: .leading, spacing: 6) {
                goomResolution("Width", setting(\.goomOptions.width), range: GoomOptions.widths)
                goomResolution("Height", setting(\.goomOptions.height), range: GoomOptions.heights)
                Win32Checkbox("CinemaScope", isOn: setting(\.goomOptions.cinemascope))
                Win32Checkbox("Show frame rate", isOn: setting(\.goomOptions.showFPS))
                Win32Checkbox("Show song title", isOn: setting(\.goomOptions.showTitle))
                HStack {
                    Text("Frame rate limit").font(.system(size: 11)).foregroundColor(Win32Colors.text)
                    Win32ComboBox(selection: setting(\.goomOptions.frameRate) { _ in
                        PlayerCoordinator.shared.visualizerStudioWindow?.studioView.updateAnimation()
                    }, options: GoomOptions.frameRates.map { (value: $0, title: $0 == 0 ? "None" : "\($0) FPS") }, width: 85)
                    Spacer()
                    Win32Button("About", width: 70) {
                        if let credits = macamp_goom_credits() {
                            Win32Dialog.inform(title: "What A Goom!", message: String(cString: credits))
                        }
                    }
                }
                note("L opens effects. Highlight an effect to apply it, then close with L, Return or Esc. M toggles the cube, keypad + / − moves the camera, and Space shows credits.")
            }
        }
    }

    private func goomResolution(_ title: String, _ value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).frame(width: 38, alignment: .leading)
            Win32Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                        in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .accessibilityLabel(title)
                .accessibilityValue("\(value.wrappedValue) pixels")
            Text("\(value.wrappedValue) px").monospacedDigit().frame(width: 42, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundColor(Win32Colors.text)
    }
    
    private var dspPluginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("DSP/Effect plug-in") {
                PluginListBox(rows: ["(none)", "MacAmp DSP Effects \(AppConstants.App.version) [dsp_effects]"],
                              selection: Binding(get: { viewModel.isDspEnabled ? 1 : 0 }, set: { viewModel.isDspEnabled = $0 == 1 }))
            }
            if viewModel.isDspEnabled { dspSection }
        }
    }
    
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Win32GroupBox("General purpose plug-ins (loaded at startup)") {
                PluginListBox(rows: ["MacAmp Global Hotkeys \(AppConstants.App.version) [gen_hotkeys]"], selection: .constant(0))
            }
            hotkeysSection
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
            HStack {
                Spacer()
                Win32Button("Reset effects", width: 110, height: 21) { viewModel.resetDSP() }
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
                        
                        Win32Slider(value: $viewModel.dspPitchSemitones, in: -12.0...12.0, step: 1.0)
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
                        
                        Win32Slider(value: $viewModel.dspPlaybackRate, in: 0.5...2.0, step: 0.05)
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
                        
                        Win32Slider(value: $viewModel.dspReverbMix, in: 0.0...100.0, step: 1.0)
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
    
    // MARK: - Section 6: Skins
    // MARK: - Skins (docs/UI-screens/pref-skins.png)
    private var skinsSection: some View {
        Win32GroupBox("Skins") {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        skinRow("<Base Skin>", url: nil)
                        ForEach(viewModel.installedSkins, id: \.self) { url in skinRow(url.deletingPathExtension().lastPathComponent, url: url) }
                    }
                }
                .frame(height: 150)
                .background(Color.white)
                .win32Sunken()
                ScrollView {
                    Text(skinDescription)
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(3)
                        .textSelection(.enabled)
                }
                .frame(height: 64)
                .background(Win32Colors.dialogBg)
                .win32Sunken()
                HStack(spacing: 8) {
                    Win32Button("Set skins directory...", width: nil) { viewModel.chooseSkinsDirectory() }
                    Win32Checkbox("Random skin on play", isOn: setting(\.randomSkinOnPlay))
                    Spacer()
                }
                HStack {
                    Spacer()
                    Button("Get more skins") { PlayerCoordinator.shared.handleGetMoreSkins() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
        }
        .task(id: viewModel.selectedSkinURL) {
            let url = viewModel.selectedSkinURL
            skinDescription = await Task.detached { SkinManager.skinDescription(of: url) }.value
        }
    }

    private func skinRow(_ title: String, url: URL?) -> some View {
        let selected = viewModel.selectedSkinURL?.path == url?.path
        return Text(title)
            .font(.system(size: 11))
            .foregroundColor(selected ? .white : Win32Colors.text)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, minHeight: 15, alignment: .leading)
            .background(selected ? Win32Colors.selectionHighlight : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.selectSkin(url: url) }
    }
}

// MARK: - Setup ▸ File types (Winamp "File type setup")
/// Winamp's Bookmarks page: the list with Open / Enqueue / Remove / Edit (double-click opens).
private struct BookmarksSection: View {
    @ObservedObject private var store = BookmarkStore.shared
    @State private var selection = Set<UUID>()


    private var selected: [Bookmark] { store.items.filter { selection.contains($0.id) } }

    var body: some View {
        Win32GroupBox("Bookmarks") {
            HStack(alignment: .top, spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.items.isEmpty {
                            Text("(no bookmarks) — add with ⌥I or the playlist's \"Bookmark item(s)\"")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(4)
                        }
                        ForEach(store.items) { bookmark in
                            row(bookmark)
                        }
                    }
                    .padding(2)
                }
                .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 260)
                .background(Color.white)
                .win32Sunken()

                VStack(spacing: 6) {
                    Win32Button("Open", width: 70) { PlayerCoordinator.shared.openBookmarks(selected, enqueue: false) }
                    Win32Button("Enqueue", width: 70) { PlayerCoordinator.shared.openBookmarks(selected, enqueue: true) }
                    Win32Button("Remove", width: 70) { store.remove(selection); selection = [] }
                    Win32Button("Edit", width: 70) { if let first = selected.first { edit(first) } }
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    private func row(_ bookmark: Bookmark) -> some View {
        let isOn = selection.contains(bookmark.id)
        return Text(bookmark.title)
            .font(.system(size: 11))
            .lineLimit(1)
            .foregroundColor(isOn ? .white : Win32Colors.text)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 15, alignment: .leading)
            .background(isOn ? Win32Colors.selectionBlue : Color.clear)
            .contentShape(Rectangle())
            .help(bookmark.url.isFileURL ? bookmark.url.path : bookmark.url.absoluteString)
            .onTapGesture(count: 2) { PlayerCoordinator.shared.openBookmarks([bookmark], enqueue: false) }
            .onTapGesture {
                // ⌘-click adds to the selection, like a Win32 multi-select list
                if NSEvent.modifierFlags.contains(.command) {
                    if isOn { selection.remove(bookmark.id) } else { selection.insert(bookmark.id) }
                } else {
                    selection = [bookmark.id]
                }
            }
    }

    /// Winamp's "Edit bookmark" dialog: Title and File
    private func edit(_ bookmark: Bookmark) {
        let location = bookmark.url.isFileURL ? bookmark.url.path : bookmark.url.absoluteString
        guard let values = Win32Dialog.promptFields(title: "Edit bookmark", fields: [("Title", bookmark.title), ("File", location)]) else { return }
        let title = values[0].trimmingCharacters(in: .whitespaces)
        let file = values[1].trimmingCharacters(in: .whitespaces)
        guard !file.isEmpty else { return }
        var updated = bookmark
        updated.title = title.isEmpty ? bookmark.title : title
        updated.url = file.contains("://") ? (URL(string: file) ?? bookmark.url) : URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        store.update(updated)
    }
}

private struct FileTypesSection: View {
    @ObservedObject private var manager = FileAssociationManager.shared
    @ObservedObject private var icons = DocumentIconManager.shared
    @State private var registerOnStart = PersistenceManager.shared.state.registerFileTypesOnStart
    @State private var enqueueByDefault = PersistenceManager.shared.state.enqueueAsDefaultAction
    @State private var playCDs = PersistenceManager.shared.state.playInsertedAudioCDs
    @State private var busy = false

    var body: some View {
        Win32GroupBox("File type setup") {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Win32GroupBox("Associated extensions") {
                        HStack(alignment: .top, spacing: 6) {
                            extensionList
                            VStack(spacing: 8) {
                                Win32Button("Select\nall", width: 62, height: 40) { run { await manager.selectAll() } }
                                Win32Button("Select\nnone", width: 62, height: 40) { run { await manager.selectNone() } }
                            }
                        }
                    }
                    if let error = manager.lastError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    iconBox("File icon", kind: .audio)
                    iconBox("Playlist icon", kind: .playlist)
                    if let error = icons.lastError {
                        Text(error).font(.system(size: 10)).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                    } else if !icons.canChangeIcons {
                        Text("Icons can be changed in local builds only")
                            .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Win32Checkbox("Register types on MacAmp start", isOn: Binding(
                        get: { registerOnStart },
                        set: { registerOnStart = $0; PersistenceManager.shared.state.registerFileTypesOnStart = $0; PersistenceManager.shared.saveSession() }
                    ))
                    Win32Checkbox("Associate with audio CDs (play a CD when it's inserted)", isOn: Binding(
                        get: { playCDs },
                        set: { playCDs = $0; PersistenceManager.shared.state.playInsertedAudioCDs = $0; PersistenceManager.shared.saveSession() }
                    ))
                    Win32Checkbox("Enqueue as default action", isOn: Binding(
                        get: { enqueueByDefault },
                        set: { enqueueByDefault = $0; PersistenceManager.shared.state.enqueueAsDefaultAction = $0; PersistenceManager.shared.saveSession() }
                    ))
                    Text("Finder: right-click ▸ Services ▸ Play / Enqueue in MacAmp")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 128)
            }
        }
        .onAppear { manager.refresh() }
        .disabled(busy)
    }

    /// Win32 multi-select list box: highlighted rows are the extensions that open in MacAmp
    private var extensionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(manager.entries) { entry in
                    let isOn = manager.isAssociated(entry.ext)
                    Button(action: { run { await manager.setAssociated(entry.ext, !isOn) } }) {
                        Text(entry.ext)
                            .font(.system(size: 11))
                            .foregroundColor(isOn ? .white : Win32Colors.text)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 15, alignment: .leading)
                            .background(isOn ? Win32Colors.selectionBlue : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(2)
        }
        // Tall enough for every extension (15 pt rows + padding), so the list doesn't scroll
        .frame(width: 84, height: CGFloat(manager.entries.count) * 15 + 6)
        .background(Color.white)
        .win32Sunken()
    }

    /// Winamp's icon chooser: vertical slider on the left, the icon Finder will show on the right
    private func iconBox(_ title: String, kind: DocumentIconManager.Kind) -> some View {
        let iconSize: CGFloat = 64
        return Win32GroupBox(title) {
            HStack(spacing: 10) {
                Win32VerticalTickSlider(
                    position: Binding(
                        get: { icons.selection[kind] ?? 0 },
                        set: { icons.preview($0, for: kind) } // dragging only changes the preview
                    ),
                    count: DocumentIconManager.resourceIDs.count,
                    height: iconSize,
                    onCommit: { Task { await icons.commit(for: kind) } } // applied once, on release
                )
                .disabled(!icons.canChangeIcons)
                if let image = icons.previewImage(for: kind) {
                    Image(nsImage: image)
                        .interpolation(.none) // original 32 px pixel art, doubled
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Color.clear.frame(width: iconSize, height: iconSize)
                }
                Spacer(minLength: 0)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task { @MainActor in
            await work()
            busy = false
        }
    }
}

// MARK: - Setup ▸ Agent (Winamp's agent: tray icon, file types; on macOS: login item and menu bar icon)
private struct AgentSection: View {
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginStatus = LoginItem.statusText
    @State private var showMenuBarIcon = PersistenceManager.shared.state.showMenuBarIcon
    @State private var maintainTypes = PersistenceManager.shared.state.registerFileTypesOnStart

    var body: some View {
        Win32GroupBox("Agent") {
            VStack(alignment: .leading, spacing: 6) {
                Win32Checkbox("Open MacAmp at login", isOn: Binding(
                    get: { openAtLogin },
                    set: { newValue in
                        LoginItem.setEnabled(newValue)
                        openAtLogin = LoginItem.isEnabled
                        loginStatus = LoginItem.statusText
                    }
                ))
                if let loginStatus {
                    Text(loginStatus).font(.system(size: 10)).foregroundColor(.secondary).padding(.leading, 19)
                }
                Win32Checkbox("Show MacAmp icon in the menu bar", isOn: Binding(
                    get: { showMenuBarIcon },
                    set: { newValue in
                        showMenuBarIcon = newValue
                        PersistenceManager.shared.state.showMenuBarIcon = newValue
                        PersistenceManager.shared.saveSession()
                        StatusBarManager.shared.setVisible(newValue)
                    }
                ))
                Win32Checkbox("Maintain file associations", isOn: Binding(
                    get: { maintainTypes },
                    set: { newValue in
                        maintainTypes = newValue
                        PersistenceManager.shared.state.registerFileTypesOnStart = newValue
                        PersistenceManager.shared.saveSession()
                    }
                ))
            }
        }
    }
}

/// White Win32 list box for the Plug-ins pages: one selectable row per built-in module.
private struct PluginListBox: View {
    let rows: [String]
    @Binding var selection: Int
    /// The box's own height (a frame from outside would squeeze it and let the rows spill over the group title)
    var height: CGFloat = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    let isOn = index == selection
                    Text(rows[index])
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundColor(isOn ? .white : Win32Colors.text)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 15, alignment: .leading)
                        .background(isOn ? Win32Colors.selectionBlue : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = index }
                }
            }
            .padding(2)
        }
        .frame(height: height)
        .background(Color.white)
        .win32Sunken()
    }
}

// MARK: - Setup (Winamp "Winamp setup" page)
private struct SetupSection: View {
    @State private var offline = PersistenceManager.shared.state.networkOffline
    @State private var proxy = PersistenceManager.shared.state.httpProxy
    @State private var checksForUpdates = PersistenceManager.shared.state.checkForUpdates

    var body: some View {
        Win32GroupBox("MacAmp setup") {
            VStack(alignment: .leading, spacing: 10) {
                Win32GroupBox("Internet settings") {
                    VStack(alignment: .leading, spacing: 6) {
                        Win32RadioButton("Use the system Internet connection", isSelected: !offline) { setOffline(false) }
                        Win32RadioButton("No Internet connection available", isSelected: offline) { setOffline(true) }
                        Win32GroupBox("HTTP proxy: 'Server:Port' (blank for none)") {
                            VStack(alignment: .leading, spacing: 4) {
                                Win32TextField(text: Binding(
                                    get: { proxy },
                                    set: { newValue in
                                        proxy = newValue
                                        PersistenceManager.shared.state.httpProxy = newValue
                                        PersistenceManager.shared.scheduleSave()
                                    }
                                ))
                                if !proxy.trimmingCharacters(in: .whitespaces).isEmpty && MacAmpNetwork.parseProxy(proxy) == nil {
                                    Text("Use the form server:port, e.g. proxy.example.com:8080")
                                        .font(.system(size: 10)).foregroundColor(.red)
                                }
                            }
                        }
                        .disabled(offline)
                        HStack {
                            Win32Checkbox("Check for new versions of MacAmp at startup", isOn: Binding(
                                get: { checksForUpdates },
                                set: { newValue in
                                    checksForUpdates = newValue
                                    PersistenceManager.shared.state.checkForUpdates = newValue
                                    PersistenceManager.shared.scheduleSave()
                                }
                            ))
                            Spacer()
                            Win32Button("Check now", width: 80) { Task { await UpdateChecker.check(manual: true) } }
                        }
                        .disabled(offline)
                    }
                }
            }
        }
    }

    private func setOffline(_ value: Bool) {
        offline = value
        PersistenceManager.shared.state.networkOffline = value
        PersistenceManager.shared.saveSession()
    }
}

/// "Open at login" through ServiceManagement (macOS 13+).
import ServiceManagement
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var statusText: String? {
        switch SMAppService.mainApp.status {
        case .requiresApproval: return "Allow MacAmp in System Settings ▸ General ▸ Login Items"
        default: return nil
        }
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("MacAmp: login item change failed: \(error)")
        }
    }
}

/// Options ▸ Library tabs (2.95)
enum LibraryPrefsTab: String, CaseIterable { case general = "General", radio = "Internet Radio" }

