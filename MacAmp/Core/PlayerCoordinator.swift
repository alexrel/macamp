import Cocoa
import Foundation
import Combine
import UniformTypeIdentifiers

public class PlayerCoordinator: NSObject, NSWindowDelegate {
    public static let shared = PlayerCoordinator()
    
    // Core Managers
    public let playlist = PlaylistModel()
    public let audioEngine = AudioEngine.shared
    public let skinManager = SkinManager.shared
    public let windowManager = WindowLayoutManager.shared
    public let persistence = PersistenceManager.shared
    
    // Windows & Views
    public var mainWindow: WinampWindow!
    public var mainView: MainWindowView!
    
    public var eqWindow: WinampWindow!
    public var eqView: EqualizerWindowView!
    
    public var plWindow: WinampWindow!
    public var plView: PlaylistWindowView!
    
    public var mbWindow: WinampWindow!
    public var mbView: MinibrowserWindowView!
    
    private var cancellables = Set<AnyCancellable>()
    public var isDeminiaturizing: Bool = false
    
    private override init() {
        super.init()
    }
    
    public func start() {
        // 1. Restore active custom skin before views/windows are created, so views render with it immediately
        if let skinPath = persistence.state.activeSkinPath {
            if FileManager.default.fileExists(atPath: skinPath) {
                if !skinManager.loadSkin(from: URL(fileURLWithPath: skinPath)) {
                    persistence.state.activeSkinPath = nil
                    persistence.saveSession()
                }
            } else {
                persistence.state.activeSkinPath = nil
                persistence.saveSession()
            }
        }
        
        setupWindows()
        setupBindings()
        restoreState()
        showWindows()
    }
    
    // MARK: - Window Setup
    private func setupWindows() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let originX = floor(screenFrame.minX + max(50, (screenFrame.width - AppConstants.Window.width) / 2))
        let originY = floor(screenFrame.maxY - 150)
        
        // 1. Main Window
        let mainRect = NSRect(x: originX, y: originY, width: AppConstants.Window.width, height: AppConstants.Window.height)
        mainWindow = WinampWindow(windowID: .main, contentRect: mainRect)
        mainWindow.delegate = self
        mainView = MainWindowView()
        mainView.autoresizesSubviews = false
        mainWindow.contentView = mainView
        
        // 2. Equalizer Window (docked directly below Main: y = originY - height)
        let eqRect = NSRect(x: originX, y: originY - AppConstants.Window.height, width: AppConstants.Window.width, height: AppConstants.Window.height)
        eqWindow = WinampWindow(windowID: .equalizer, contentRect: eqRect)
        eqView = EqualizerWindowView()
        eqView.autoresizesSubviews = false
        eqWindow.contentView = eqView
        
        // 3. Playlist Window (docked directly below EQ: y = originY - 2 * height)
        let rawPlW = CGFloat(persistence.state.playlistWindowSize.first ?? Double(AppConstants.Window.width))
        let rawPlH = CGFloat(persistence.state.playlistWindowSize.last ?? Double(AppConstants.Window.height))
        // Sanitize any previously saved fractional or distorted playlist widths to canonical 25px grid
        let stepsX = max(0, round((rawPlW - AppConstants.Window.width) / AppConstants.Window.resizeStepX))
        let plW = AppConstants.Window.width + stepsX * AppConstants.Window.resizeStepX
        let stepsY = max(0, round((rawPlH - AppConstants.Window.height) / AppConstants.Window.resizeStepY))
        let plH = AppConstants.Window.height + stepsY * AppConstants.Window.resizeStepY
        
        let plRect = NSRect(x: originX, y: originY - (2 * AppConstants.Window.height) - (plH - AppConstants.Window.height), width: plW, height: plH)
        plWindow = WinampWindow(windowID: .playlist, contentRect: plRect)
        plView = PlaylistWindowView(playlist: playlist)
        plView.frame = NSRect(x: 0, y: 0, width: plW, height: plH)
        plView.autoresizesSubviews = false
        plWindow.contentView = plView
        
        // 4. Minibrowser Window (docked below Playlist: y = plRect.minY - mbH)
        let rawMbW = CGFloat(persistence.state.minibrowserWindowSize.first ?? Double(AppConstants.Window.width))
        let rawMbH = CGFloat(persistence.state.minibrowserWindowSize.last ?? Double(AppConstants.Window.height))
        let mbStepsX = max(0, round((rawMbW - AppConstants.Window.width) / AppConstants.Window.resizeStepX))
        let mbW = AppConstants.Window.width + mbStepsX * AppConstants.Window.resizeStepX
        let mbStepsY = max(0, round((rawMbH - AppConstants.Window.height) / AppConstants.Window.resizeStepY))
        let mbH = AppConstants.Window.height + mbStepsY * AppConstants.Window.resizeStepY
        
        let mbRect = NSRect(x: originX, y: plRect.minY - mbH, width: mbW, height: mbH)
        mbWindow = WinampWindow(windowID: .minibrowser, contentRect: mbRect)
        mbView = MinibrowserWindowView(frame: NSRect(x: 0, y: 0, width: mbW, height: mbH))
        mbView.autoresizesSubviews = false
        mbWindow.contentView = mbView
    }
    
    // MARK: - Window Display
    private func showWindows() {
        bringAllWindowsToFront()
    }
    
    // MARK: - Bindings & Events
    private func setupBindings() {
        // 1. Audio Engine Callbacks
        audioEngine.onStatusUpdate = { [weak self] status in
            guard let self else { return }
            self.mainView.timeDisplay.status = status
            self.plView.status = status
            self.updateBlinkState(for: status)
            self.mainView.seekSlider.isThumbHidden = (status == .stopped)
            if status == .stopped {
                self.mainView.seekSlider.value = 0.0
            }
            self.mainView.needsDisplay = true
            self.plView.needsDisplay = true
        }
        
        audioEngine.onTimeUpdate = { [weak self] currentSec in
            guard let self else { return }
            self.mainView.timeDisplay.currentTime = currentSec
            self.plView.currentTime = currentSec
            if let meta = self.audioEngine.currentMetadata, meta.duration > 0 {
                if !self.mainView.seekSlider.isDragging {
                    self.mainView.seekSlider.value = currentSec / meta.duration
                }
            }
        }
        
        mainView.seekSlider.onValueChanged = { [weak self] val in
            guard let self, let meta = self.audioEngine.currentMetadata, meta.duration > 0 else { return }
            let scrubSec = val * meta.duration
            self.mainView.timeDisplay.currentTime = scrubSec
            self.plView.currentTime = scrubSec
            let curM = Int(scrubSec) / 60
            let curS = Int(scrubSec) % 60
            let totM = Int(meta.duration) / 60
            let totS = Int(meta.duration) % 60
            let percent = Int(round(val * 100.0))
            let msg = String(format: "Seek To: %02d:%02d/%02d:%02d (%d%%)", curM, curS, totM, totS, percent)
            self.mainView.marquee.showTemporaryMessage(msg)
        }
        
        mainView.seekSlider.onTrackingEnded = { [weak self] val in
            guard let self, let meta = self.audioEngine.currentMetadata, meta.duration > 0 else { return }
            self.audioEngine.seek(to: val * meta.duration)
        }
        
        audioEngine.onSpectralDataUpdate = { [weak self] bins in
            self?.mainView.visualizer.spectrumAmplitudes = bins
        }
        
        audioEngine.onWaveformDataUpdate = { [weak self] wave in
            self?.mainView.visualizer.waveformPoints = wave
        }
        
        audioEngine.onMetadataUpdate = { [weak self] artist, title, bitrate, sampleRate in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.mainView.marquee.text = "\(artist) - \(title)"
                self.mainView.marquee.resetScroll()
                if let current = self.audioEngine.currentMetadata {
                    self.playlist.updateTrack(url: current.url, duration: 0, artist: artist, title: title)
                    self.plView.needsDisplay = true
                }
                self.mainView.needsDisplay = true
                MediaKeyController.shared.updateNowPlayingInfo()
                StatusBarManager.shared.updateStatus()
            }
        }
        
        audioEngine.onPlaybackFinished = { [weak self] in
            self?.playNext()
        }
        
        // 2. Transport actions
        mainView.playButton.action = { [weak self] in self?.handlePlay() }
        mainView.pauseButton.action = { [weak self] in self?.handlePause() }
        mainView.stopButton.action = { [weak self] in self?.handleStop() }
        mainView.prevButton.action = { [weak self] in self?.playPrevious() }
        mainView.nextButton.action = { [weak self] in self?.playNext() }
        mainView.ejectButton.action = { [weak self] in self?.openFileDialog() }
        mainView.onEject = { [weak self] in self?.openFileDialog() }
        mainView.onOpenOptions = { [weak self] in
            guard let self else { return }
            let pt = self.mainWindow.convertToScreen(NSRect(x: 10, y: self.mainWindow.frame.height - 20, width: 0, height: 0)).origin
            self.showMainContextMenu(at: pt)
        }
        
        mainView.shuffleToggle.onChanged = { [weak self] isShuffle in
            self?.playlist.isShuffle = isShuffle
            self?.persistence.state.isShuffle = isShuffle
        }
        
        mainView.repeatToggle.onChanged = { [weak self] isRepeat in
            self?.playlist.isRepeat = isRepeat
            self?.persistence.state.isRepeat = isRepeat
        }
        
        // Volume and Balance sliders sync
        mainView.volumeSlider.onValueChanged = { [weak self] val in
            guard let self = self else { return }
            self.audioEngine.setVolume(val)
            self.eqView.eqShadeVolumeSlider?.value = val
            self.persistence.state.volume = val
            let percent = Int(round(val * 100.0))
            self.mainView.marquee.showTemporaryMessage("Volume: \(percent)%")
        }
        
        mainView.balanceSlider.onValueChanged = { [weak self] val in
            guard let self = self else { return }
            self.audioEngine.setBalance(val)
            self.eqView.eqShadeBalanceSlider?.value = val
            self.persistence.state.balance = val
            let percent = Int(round(abs(val) * 100.0))
            let msg: String
            if percent == 0 {
                msg = "Balance: Center"
            } else if val < 0 {
                msg = "Balance: \(percent)% left"
            } else {
                msg = "Balance: \(percent)% right"
            }
            self.mainView.marquee.showTemporaryMessage(msg)
        }
        
        // Equalizer frequency band & preamp feedback in marquee
        eqView.onBandAdjusted = { [weak self] name, gainDb in
            guard let self else { return }
            let sign = gainDb >= 0 ? "+" : "-"
            let formatted = String(format: "EQ: %@: %@%.1f db", name, sign, abs(gainDb))
            self.mainView.marquee.showTemporaryMessage(formatted)
        }
        
        // Window Toggles
        mainView.eqToggle.onChanged = { [weak self] isVisible in
            guard let self else { return }
            self.persistence.state.isEqWindowVisible = isVisible
            if isVisible {
                self.eqWindow.level = self.persistence.state.isAlwaysOnTop ? .floating : .normal
                self.bringAllWindowsToFront()
            } else {
                self.eqWindow.orderOut(nil)
            }
        }
        
        mainView.plToggle.onChanged = { [weak self] isVisible in
            guard let self else { return }
            self.persistence.state.isPlaylistVisible = isVisible
            if isVisible {
                self.plWindow.level = self.persistence.state.isAlwaysOnTop ? .floating : .normal
                self.bringAllWindowsToFront()
            } else {
                self.plWindow.orderOut(nil)
            }
        }
        
        // Shade mode toggles
        mainView.onToggleShade = { [weak self] in self?.toggleMainShade() }
        eqView.onToggleShade = { [weak self] in self?.toggleEqShade() }
        plView.onToggleShade = { [weak self] in self?.togglePlShade() }
        mbView.onToggleShade = { [weak self] in
            guard let self = self else { return }
            self.mbView.isShadeMode.toggle()
            self.windowManager.updateAdjacencies()
        }
        
        // Close EQ, PL & MB
        eqView.onClose = { [weak self] in
            self?.mainView.eqToggle.isOn = false
        }
        plView.onClose = { [weak self] in
            self?.mainView.plToggle.isOn = false
        }
        mbView.onClose = { [weak self] in
            self?.toggleMinibrowser()
        }
        
        // Always on top toggle (ClutterBar A)
        mainView.onToggleAlwaysOnTop = { [weak self] in self?.handleToggleAlwaysOnTop() }
        
        // Double size toggle
        mainView.onToggleDoubleSize = { [weak self] in self?.toggleDoubleSize() }
        
        // Time display mode toggle
        mainView.timeDisplay.onToggleMode = { [weak self] in
            guard let self else { return }
            let nextMode: TimeDisplayMode = (self.mainView.timeDisplay.mode == .elapsed) ? .remaining : .elapsed
            self.mainView.timeDisplay.mode = nextMode
            self.persistence.state.timeDisplayMode = nextMode
        }
        
        // Visualizer mode cycle
        mainView.visualizer.onToggleMode = { [weak self] in
            guard let self else { return }
            let next = self.mainView.visualizer.mode.next
            self.mainView.visualizer.mode = next
            self.persistence.state.visualizerMode = next
        }
        
        // Playlist callbacks
        plView.onPlayTrack = { [weak self] track in
            self?.loadAndPlay(track: track)
        }
        plView.onAddFiles = { [weak self] in
            self?.openFileDialog()
        }
        plView.onPlay = { [weak self] in self?.handlePlay() }
        plView.onPause = { [weak self] in self?.handlePause() }
        plView.onStop = { [weak self] in self?.handleStop() }
        plView.onPrevious = { [weak self] in self?.playPrevious() }
        plView.onNext = { [weak self] in self?.playNext() }
        plView.onEject = { [weak self] in self?.openFileDialog() }
        
        // Observe playlist changes to automatically update playlist view
        playlist.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.plView.needsDisplay = true
            }
            .store(in: &cancellables)
        
        // Redraw on skin change
        skinManager.skinDidChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.mainView.setNeedsDisplayRecursively()
                self.eqView.setNeedsDisplayRecursively()
                self.plView.setNeedsDisplayRecursively()
                self.mbView?.setNeedsDisplayRecursively()
                self.updateWindowMasks()
            }
            .store(in: &cancellables)
    }
    
    public func refreshAllViews() {
        mainView?.setNeedsDisplayRecursively()
        eqView?.setNeedsDisplayRecursively()
        plView?.setNeedsDisplayRecursively()
        mbView?.setNeedsDisplayRecursively()
        updateWindowMasks()
    }
    
    // MARK: - Synchronized Blinking for Pause Mode
    private var blinkTimer: Timer?
    private var isBlinkVisible: Bool = true
    
    private func updateBlinkState(for status: PlayerStatus) {
        blinkTimer?.invalidate()
        blinkTimer = nil
        
        if status == .paused {
            isBlinkVisible = true
            mainView.timeDisplay.isBlinkVisible = true
            plView.isBlinkVisible = true
            
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.isBlinkVisible.toggle()
                self.mainView.timeDisplay.isBlinkVisible = self.isBlinkVisible
                self.plView.isBlinkVisible = self.isBlinkVisible
            }
        } else {
            isBlinkVisible = true
            mainView.timeDisplay.isBlinkVisible = true
            plView.isBlinkVisible = true
        }
    }
    
    // MARK: - Playback Handling
    public func loadAndPlay(track: TrackItem) {
        if !track.url.isFileURL {
            mainView.marquee.text = "[Connecting...] \(track.title)"
            mainView.marquee.resetScroll()
            mainView.needsDisplay = true
        }
        Task {
            do {
                let meta = try await audioEngine.load(url: track.url)
                await MainActor.run {
                    if let idx = self.playlist.tracks.firstIndex(where: { $0.id == track.id }) {
                        self.playlist.currentIndex = idx
                    }
                    self.playlist.updateTrack(url: track.url, duration: meta.duration, artist: meta.artist, title: meta.title)
                    self.mainView.marquee.text = "\(meta.artist) - \(meta.title)"
                    self.mainView.marquee.resetScroll()
                    self.mainView.timeDisplay.totalDuration = meta.duration
                    self.mainView.timeDisplay.status = .playing
                    self.audioEngine.play()
                    self.mainView.needsDisplay = true
                    self.plView.needsDisplay = true
                    MediaKeyController.shared.updateNowPlayingInfo()
                    StatusBarManager.shared.updateStatus()
                }
            } catch {
                print("Failed to load track \(track.url): \(error)")
                await MainActor.run {
                    self.mainView.marquee.showTemporaryMessage("Stream Error")
                }
            }
        }
    }
    
    public func playNext() {
        if let next = playlist.next() {
            loadAndPlay(track: next)
        } else {
            audioEngine.stop()
            mainView.timeDisplay.status = .stopped
            mainView.needsDisplay = true
        }
    }
    
    public func playPrevious() {
        if let prev = playlist.previous() {
            loadAndPlay(track: prev)
        }
    }
    
    // MARK: - Dialogs & File Opening
    public func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = AppConstants.Audio.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        
        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path }
            handleDroppedFiles(paths)
        }
    }
    
    public func openDirectoryDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path }
            handleDroppedFiles(paths)
        }
    }
    
    public func openURLDialog() {
        plView.promptAddURL()
    }
    
    public func openSkinChooser() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AppConstants.Audio.skinExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let installedURL = skinManager.installSkin(from: url) {
                persistence.state.activeSkinPath = installedURL.path
                persistence.saveSession()
            }
        }
    }
    
    /// Opens the MPEG Audio Info Box + ID3 Tag Editor (Alt+3) for the specified or selected track.
    public func showTrackInfoWindow(trackIndex: Int? = nil) {
        guard !playlist.tracks.isEmpty else {
            mainView?.marquee.showTemporaryMessage("No track in playlist")
            return
        }
        
        let targetIndex: Int = {
            if let idx = trackIndex, idx >= 0, idx < playlist.tracks.count {
                return idx
            }
            if let sel = playlist.selectedIndices.first, sel < playlist.tracks.count {
                return sel
            }
            if let cur = playlist.currentIndex, cur < playlist.tracks.count {
                return cur
            }
            return 0
        }()
        
        TrackInfoWindow.show(trackIndex: targetIndex)
    }
    
    /// Opens the Winamp Preferences (Ctrl+P / Cmd+,) dialog.
    public func showPreferencesWindow(category: PreferencesCategory = .titles) {
        PreferencesWindow.show(category: category)
    }
    
    /// Opens the Jump to File (J / F3) dialog.
    public func showJumpToFileWindow() {
        JumpToFileWindow.show()
    }
    
    /// Opens the Jump to Time (Ctrl+J) dialog.
    public func showJumpToTimeWindow() {
        JumpToTimeWindow.show()
    }
    
    // MARK: - Drag & Drop Handling
    public func handleDroppedFiles(_ paths: [String]) {
        var tracksToAdd: [TrackItem] = []
        let audioExtensions = AppConstants.Audio.supportedExtensions
        let skinExtensions = AppConstants.Audio.skinExtensions
        let playlistExtensions = AppConstants.Audio.playlistExtensions
        
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            
            if skinExtensions.contains(ext) {
                if let installedURL = skinManager.installSkin(from: url) {
                    persistence.state.activeSkinPath = installedURL.path
                    persistence.saveSession()
                }
            } else if playlistExtensions.contains(ext) {
                let loaded = PlaylistIO.loadPlaylist(from: url)
                tracksToAdd.append(contentsOf: loaded)
            } else {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        // Check if unpacked skin folder
                        let mainBmp1 = url.appendingPathComponent("MAIN.BMP")
                        let mainBmp2 = url.appendingPathComponent("main.bmp")
                        if FileManager.default.fileExists(atPath: mainBmp1.path) || FileManager.default.fileExists(atPath: mainBmp2.path) {
                            if let installedURL = skinManager.installSkin(from: url) {
                                persistence.state.activeSkinPath = installedURL.path
                                persistence.saveSession()
                            }
                            continue
                        }
                        
                        // Recursively scan for audio files
                        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                            for case let fileURL as URL in enumerator {
                                if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                                    tracksToAdd.append(TrackItem.create(from: fileURL))
                                }
                            }
                        }
                    } else if audioExtensions.contains(ext) {
                        tracksToAdd.append(TrackItem.create(from: url))
                    }
                }
            }
        }
        
        if !tracksToAdd.isEmpty {
            let wasEmpty = playlist.tracks.isEmpty
            let wasStopped = (audioEngine.status == .stopped)
            playlist.add(tracks: tracksToAdd)
            plView.needsDisplay = true
            
            if wasEmpty || wasStopped, let first = playlist.currentTrack ?? playlist.tracks.first {
                loadAndPlay(track: first)
            }
        }
    }
    
    // MARK: - Keyboard Handling
    public func handleKeyDown(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // 1. Navigation / Volume via Arrow keys and Special Keys
        switch event.keyCode {
        case AppConstants.KeyCodes.leftArrow: // Seek back 5 seconds
            let cur = audioEngine.currentTime
            audioEngine.seek(to: max(0, cur - 5.0))
            return true
        case AppConstants.KeyCodes.rightArrow: // Seek forward 5 seconds
            if let meta = audioEngine.currentMetadata {
                let cur = audioEngine.currentTime
                audioEngine.seek(to: min(meta.duration, cur + 5.0))
            }
            return true
        case AppConstants.KeyCodes.upArrow: // Volume up 5%
            increaseVolume(by: 0.05)
            return true
        case AppConstants.KeyCodes.downArrow: // Volume down 5%
            decreaseVolume(by: 0.05)
            return true
        case AppConstants.KeyCodes.space: // Toggle Pause/Resume
            audioEngine.togglePause()
            return true
        case AppConstants.KeyCodes.returnKey: // Play selected or current track
            if let cur = playlist.currentTrack ?? playlist.tracks.first {
                loadAndPlay(track: cur)
            }
            return true
        case AppConstants.KeyCodes.deleteKey: // Remove selected in playlist
            playlist.removeSelected()
            plView.needsDisplay = true
            return true
        case AppConstants.KeyCodes.f3: // Jump to file
            showJumpToFileWindow()
            return true
        default:
            break
        }
        
        // 2. Modifier keys
        if flags.contains(.command) || flags.contains(.control) {
            switch chars {
            case "p", ",":
                showPreferencesWindow()
                return true
            case "d":
                toggleDoubleSize()
                return true
            case "j":
                showJumpToTimeWindow()
                return true
            case "o", "l":
                openFileDialog()
                return true
            case "q":
                NSApp.terminate(nil)
                return true
            default:
                break
            }
        }
        
        if flags.contains(.option) {
            if event.keyCode == 20 || chars == "3" { // KeyCode 20 = '3' (Canonical Winamp Alt+3)
                showTrackInfoWindow()
                return true
            }
            switch chars {
            case "s":
                openSkinChooser()
                return true
            case "t":
                toggleMinibrowser()
                return true
            case "w":
                toggleMainShade()
                return true
            default:
                break
            }
        }
        
        if flags.contains(.shift) {
            if chars == "l" {
                openDirectoryDialog()
                return true
            }
        }
        
        if flags.contains(.control) || flags.contains(.command) {
            if chars == "u" {
                openURLDialog()
                return true
            }
        }
        
        // 3. Unmodified Winamp 2.x hotkeys
        if flags.isEmpty || flags == .capsLock {
            switch chars {
            case "z":
                playPrevious()
                return true
            case "x":
                handlePlay()
                return true
            case "c":
                handlePause()
                return true
            case "v":
                handleStop()
                return true
            case "b":
                playNext()
                return true
            case "j":
                showJumpToFileWindow()
                return true
            case "l":
                openFileDialog()
                return true
            case "r":
                handleToggleRepeat()
                return true
            case "s":
                handleToggleShuffle()
                return true
            default:
                break
            }
        }
        
        return false
    }
    
    // MARK: - Always On Top & Window Management
    public func setAlwaysOnTop(_ enabled: Bool) {
        persistence.state.isAlwaysOnTop = enabled
        let level: NSWindow.Level = enabled ? .floating : .normal
        mainWindow?.level = level
        eqWindow?.level = level
        plWindow?.level = level
        mbWindow?.level = level
        bringAllWindowsToFront()
        mainView?.alwaysOnTopButton?.isSelected = enabled
    }
    
    /// Toggles the Minibrowser window visibility.
    public func toggleMinibrowser() {
        let isVisible = persistence.state.isMinibrowserVisible
        persistence.state.isMinibrowserVisible = !isVisible
        if persistence.state.isMinibrowserVisible {
            mbWindow.level = persistence.state.isAlwaysOnTop ? .floating : .normal
            mbWindow.orderFront(nil)
            bringAllWindowsToFront()
        } else {
            mbWindow.orderOut(nil)
        }
        windowManager.updateAdjacencies()
        persistence.saveSession()
    }
    
    /// Brings all currently visible MacAmp windows to the front in proper z-order (Playlist -> Equalizer -> Minibrowser -> MainWindow)
    /// without allowing secondary windows to drop behind other desktop applications when switching window levels or activating.
    public func bringAllWindowsToFront() {
        if let main = mainWindow, main.isMiniaturized || isDeminiaturizing {
            return
        }
        
        let keyWin = NSApp.keyWindow
        
        if persistence.state.isMinibrowserVisible, let mb = mbWindow, !mb.isMiniaturized {
            mb.orderFront(nil)
        }
        if persistence.state.isPlaylistVisible, let pl = plWindow, !pl.isMiniaturized {
            pl.orderFront(nil)
        }
        if persistence.state.isEqWindowVisible, let eq = eqWindow, !eq.isMiniaturized {
            eq.orderFront(nil)
        }
        if let main = mainWindow, !main.isMiniaturized {
            main.orderFront(nil)
        }
        
        if let key = keyWin as? WinampWindow {
            key.makeKeyAndOrderFront(nil)
        } else {
            mainWindow?.makeKeyAndOrderFront(nil)
        }
    }
    
    /// Minimizes the main player window and immediately hides auxiliary windows so they never linger.
    public func minimizeAll() {
        isDeminiaturizing = false
        eqWindow?.orderOut(nil)
        plWindow?.orderOut(nil)
        mbWindow?.orderOut(nil)
        mainWindow?.miniaturize(nil)
    }
    
    // MARK: - NSWindowDelegate
    public func windowWillMiniaturize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == mainWindow else { return }
        isDeminiaturizing = false
        eqWindow?.orderOut(nil)
        plWindow?.orderOut(nil)
        mbWindow?.orderOut(nil)
    }
    
    public func windowDidMiniaturize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == mainWindow else { return }
        isDeminiaturizing = false
        eqWindow?.orderOut(nil)
        plWindow?.orderOut(nil)
        mbWindow?.orderOut(nil)
    }
    
    public func windowDidDeminiaturize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == mainWindow else { return }
        isDeminiaturizing = false
        bringAllWindowsToFront()
    }
    
    // MARK: - Context Menu
    public func buildSkinsSubmenu() -> NSMenu {
        let skinsMenu = NSMenu(title: "Skins")
        let baseSkinItem = NSMenuItem(title: "Winamp Classic (Default)", action: #selector(handleResetBaseSkin), keyEquivalent: "")
        baseSkinItem.target = self
        baseSkinItem.state = skinManager.isBaseSkinActive ? .on : .off
        skinsMenu.addItem(baseSkinItem)
        
        let installedSkins = skinManager.installedSkins()
        if !installedSkins.isEmpty {
            skinsMenu.addItem(NSMenuItem.separator())
            for skinURL in installedSkins {
                let name = skinURL.deletingPathExtension().lastPathComponent
                let item = NSMenuItem(title: name, action: #selector(handleSkinSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = skinURL
                let isActive = (!skinManager.isBaseSkinActive && (skinManager.currentSkinURL?.path == skinURL.path || skinManager.currentSkin?.name == name))
                item.state = isActive ? .on : .off
                skinsMenu.addItem(item)
            }
        }
        
        skinsMenu.addItem(NSMenuItem.separator())
        
        let loadSkinItem = NSMenuItem(title: "Load Skin...", action: #selector(handleLoadSkin), keyEquivalent: "")
        loadSkinItem.target = self
        skinsMenu.addItem(loadSkinItem)
        
        if !installedSkins.isEmpty {
            let deleteMenu = NSMenu(title: "Delete Skin")
            for skinURL in installedSkins {
                let name = skinURL.deletingPathExtension().lastPathComponent
                let delItem = NSMenuItem(title: name, action: #selector(handleDeleteSkin(_:)), keyEquivalent: "")
                delItem.target = self
                delItem.representedObject = skinURL
                deleteMenu.addItem(delItem)
            }
            let deleteSkinItem = NSMenuItem(title: "Delete Skin", action: nil, keyEquivalent: "")
            deleteSkinItem.submenu = deleteMenu
            skinsMenu.addItem(deleteSkinItem)
        }
        
        let openFolderItem = NSMenuItem(title: "Open Skins Folder", action: #selector(handleOpenSkinsFolder), keyEquivalent: "")
        openFolderItem.target = self
        skinsMenu.addItem(openFolderItem)
        
        return skinsMenu
    }
    
    public func buildWinampMenu() -> NSMenu {
        let menu = NSMenu(title: "Winamp Menu")
        
        // 1. About
        let aboutItem = NSMenuItem(title: "MacAmp...", action: #selector(handleAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        // 2. Track Info / ID3 Tag Editor (Alt+3)
        let infoItem = NSMenuItem(title: "View file info... (Alt+3)", action: #selector(handleTrackInfo), keyEquivalent: "3")
        infoItem.keyEquivalentModifierMask = [.option]
        infoItem.target = self
        menu.addItem(infoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Play submenu
        let playMenu = NSMenu(title: "Play")
        let playFileItem = NSMenuItem(title: "File...", action: #selector(handlePlayFile), keyEquivalent: "l")
        playFileItem.target = self
        playMenu.addItem(playFileItem)
        
        let playDirItem = NSMenuItem(title: "Directory...", action: #selector(handlePlayDirectory), keyEquivalent: "L")
        playDirItem.target = self
        playMenu.addItem(playDirItem)
        
        let playURLItem = NSMenuItem(title: "URL...", action: #selector(handlePlayURL), keyEquivalent: "u")
        playURLItem.target = self
        playMenu.addItem(playURLItem)
        playMenu.addItem(NSMenuItem.separator())
        
        let jumpFileItem = NSMenuItem(title: "Jump to file... (J)", action: #selector(handleJumpToFile), keyEquivalent: "j")
        jumpFileItem.target = self
        playMenu.addItem(jumpFileItem)
        
        let playMenuItem = NSMenuItem(title: "Play", action: nil, keyEquivalent: "")
        playMenuItem.submenu = playMenu
        menu.addItem(playMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // 4. Windows toggles
        let eqItem = NSMenuItem(title: "Equalizer", action: #selector(handleToggleEqualizer), keyEquivalent: "")
        eqItem.target = self
        eqItem.state = mainView.eqToggle.isOn ? .on : .off
        menu.addItem(eqItem)
        
        let plItem = NSMenuItem(title: "Playlist", action: #selector(handleTogglePlaylist), keyEquivalent: "")
        plItem.target = self
        plItem.state = mainView.plToggle.isOn ? .on : .off
        menu.addItem(plItem)
        
        let mbItem = NSMenuItem(title: "Minibrowser", action: #selector(handleToggleMinibrowser), keyEquivalent: "t")
        mbItem.keyEquivalentModifierMask = [.option]
        mbItem.target = self
        mbItem.state = persistence.state.isMinibrowserVisible ? .on : .off
        menu.addItem(mbItem)
        menu.addItem(NSMenuItem.separator())
        
        // 5. Options submenu
        let optionsMenu = NSMenu(title: "Options")
        
        let prefsItem = NSMenuItem(title: "Preferences... (Ctrl+P)", action: #selector(handlePreferences), keyEquivalent: "p")
        prefsItem.keyEquivalentModifierMask = [.control]
        prefsItem.target = self
        optionsMenu.addItem(prefsItem)
        optionsMenu.addItem(NSMenuItem.separator())
        
        let skinsSubmenu = buildSkinsSubmenu()
        let skinsSubItem = NSMenuItem(title: "Skins", action: nil, keyEquivalent: "")
        skinsSubItem.submenu = skinsSubmenu
        optionsMenu.addItem(skinsSubItem)
        optionsMenu.addItem(NSMenuItem.separator())
        
        let topItem = NSMenuItem(title: "Always On Top", action: #selector(handleToggleAlwaysOnTop), keyEquivalent: "")
        topItem.target = self
        topItem.state = persistence.state.isAlwaysOnTop ? .on : .off
        optionsMenu.addItem(topItem)
        
        let dblItem = NSMenuItem(title: "Double Size (Ctrl+D)", action: #selector(handleToggleDoubleSize), keyEquivalent: "d")
        dblItem.keyEquivalentModifierMask = [.control]
        dblItem.target = self
        dblItem.state = (windowManager.currentScale == 2.0) ? .on : .off
        optionsMenu.addItem(dblItem)
        
        let optMenuItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        optMenuItem.submenu = optionsMenu
        menu.addItem(optMenuItem)
        
        // 6. Skins at root menu
        let rootSkinsItem = NSMenuItem(title: "Skins", action: nil, keyEquivalent: "")
        rootSkinsItem.submenu = buildSkinsSubmenu()
        menu.addItem(rootSkinsItem)
        
        // 7. Playback submenu
        let pbMenu = NSMenu(title: "Playback")
        let prevItem = NSMenuItem(title: "Previous", action: #selector(handlePrev), keyEquivalent: "z")
        prevItem.target = self
        pbMenu.addItem(prevItem)
        
        let playItem = NSMenuItem(title: "Play", action: #selector(handlePlay), keyEquivalent: "x")
        playItem.target = self
        pbMenu.addItem(playItem)
        
        let pauseItem = NSMenuItem(title: "Pause", action: #selector(handlePause), keyEquivalent: "c")
        pauseItem.target = self
        pbMenu.addItem(pauseItem)
        
        let stopItem = NSMenuItem(title: "Stop", action: #selector(handleStop), keyEquivalent: "v")
        stopItem.target = self
        pbMenu.addItem(stopItem)
        
        let nextItem = NSMenuItem(title: "Next", action: #selector(handleNext), keyEquivalent: "b")
        nextItem.target = self
        pbMenu.addItem(nextItem)
        pbMenu.addItem(NSMenuItem.separator())
        
        let repItem = NSMenuItem(title: "Repeat", action: #selector(handleToggleRepeat), keyEquivalent: "r")
        repItem.target = self
        repItem.state = playlist.isRepeat ? .on : .off
        pbMenu.addItem(repItem)
        
        let shufItem = NSMenuItem(title: "Shuffle", action: #selector(handleToggleShuffle), keyEquivalent: "s")
        shufItem.target = self
        shufItem.state = playlist.isShuffle ? .on : .off
        pbMenu.addItem(shufItem)
        pbMenu.addItem(NSMenuItem.separator())
        
        let jumpTimeItem = NSMenuItem(title: "Jump to time... (Ctrl+J)", action: #selector(handleJumpToTime), keyEquivalent: "j")
        jumpTimeItem.keyEquivalentModifierMask = [.control]
        jumpTimeItem.target = self
        pbMenu.addItem(jumpTimeItem)
        
        let pbMenuItem = NSMenuItem(title: "Playback", action: nil, keyEquivalent: "")
        pbMenuItem.submenu = pbMenu
        menu.addItem(pbMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // 8. Exit
        let exitItem = NSMenuItem(title: "Exit", action: #selector(handleExit), keyEquivalent: "q")
        exitItem.target = self
        menu.addItem(exitItem)
        
        return menu
    }
    
    public func showMainContextMenu(at screenPoint: NSPoint? = nil, in view: NSView? = nil) {
        let menu = buildWinampMenu()
        let targetPt = screenPoint ?? NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: targetPt, in: view)
    }
    
    // MARK: - Menu Actions
    @objc public func handleJumpToFile() {
        showJumpToFileWindow()
    }
    
    @objc public func handleJumpToTime() {
        showJumpToTimeWindow()
    }
    
    @objc public func handlePreferences() {
        showPreferencesWindow()
    }
    
    @objc public func handleTrackInfo() {
        showTrackInfoWindow()
    }
    
    @objc public func handleMinimizeAll() {
        minimizeAll()
    }
    
    @objc public func handleBringAllToFront() {
        bringAllWindowsToFront()
    }
    
    @objc public func handleAbout() {
        AboutWindow.show()
    }
    
    @objc public func handlePlayFile() {
        openFileDialog()
    }
    
    @objc public func handlePlayDirectory() {
        openDirectoryDialog()
    }
    
    @objc public func handlePlayURL() {
        openURLDialog()
    }
    
    @objc public func handleToggleEqualizer() {
        mainView.eqToggle.isOn.toggle()
        mainView.eqToggle.onChanged?(mainView.eqToggle.isOn)
    }
    
    @objc public func handleTogglePlaylist() {
        mainView.plToggle.isOn.toggle()
        mainView.plToggle.onChanged?(mainView.plToggle.isOn)
    }
    
    @objc public func handleToggleMinibrowser() {
        toggleMinibrowser()
    }
    
    @objc public func handleResetBaseSkin() {
        skinManager.resetToBaseSkin()
    }
    
    @objc public func handleLoadSkin() {
        openSkinChooser()
    }
    
    @objc public func handleSkinSelected(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if skinManager.loadSkin(from: url) {
            persistence.state.activeSkinPath = url.path
            persistence.saveSession()
        }
    }
    
    @objc public func handleDeleteSkin(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let skinName = url.deletingPathExtension().lastPathComponent
        
        let alert = NSAlert()
        alert.messageText = "Delete Skin"
        alert.informativeText = "Are you sure you want to delete the skin \"\(skinName)\"?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            skinManager.deleteSkin(at: url)
        }
    }
    
    @objc public func handleOpenSkinsFolder() {
        let dir = skinManager.skinsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
    
    @objc public func handleToggleAlwaysOnTop() {
        setAlwaysOnTop(!persistence.state.isAlwaysOnTop)
    }
    
    @objc public func handleToggleDoubleSize() {
        toggleDoubleSize()
    }
    
    @objc public func handlePrev() {
        playPrevious()
    }
    
    @objc public func handlePlay() {
        if audioEngine.status == .paused {
            audioEngine.play()
            MediaKeyController.shared.updateNowPlayingInfo()
            StatusBarManager.shared.updateStatus()
        } else if audioEngine.status == .playing {
            audioEngine.seek(to: 0)
            MediaKeyController.shared.updateNowPlayingInfo()
        } else if let track = playlist.currentTrack ?? playlist.tracks.first {
            loadAndPlay(track: track)
        }
    }
    
    @objc public func handlePause() {
        audioEngine.togglePause()
        MediaKeyController.shared.updateNowPlayingInfo()
        StatusBarManager.shared.updateStatus()
    }
    
    @objc public func handlePlayPause() {
        if audioEngine.status == .playing {
            audioEngine.togglePause()
        } else {
            handlePlay()
        }
        MediaKeyController.shared.updateNowPlayingInfo()
        StatusBarManager.shared.updateStatus()
    }
    
    public func seek(to time: TimeInterval) {
        audioEngine.seek(to: time)
        MediaKeyController.shared.updateNowPlayingInfo()
    }
    
    @objc public func handleStop() {
        audioEngine.stop()
        mainView.timeDisplay.status = .stopped
        mainView.seekSlider.isThumbHidden = true
        mainView.seekSlider.value = 0.0
        mainView.visualizer.spectrumAmplitudes = Array(repeating: 0.0, count: AppConstants.Visualizer.numSpectrumBars)
        mainView.visualizer.waveformPoints = Array(repeating: 0.0, count: AppConstants.Visualizer.numWaveformPoints)
        mainView.needsDisplay = true
        MediaKeyController.shared.updateNowPlayingInfo()
        StatusBarManager.shared.updateStatus()
    }
    
    @objc public func handleNext() {
        playNext()
    }
    
    private var preMuteVolume: Double = 0.5
    
    @objc public func increaseVolume(by delta: Double = 0.05) {
        let newVol = min(1.0, audioEngine.volume + delta)
        audioEngine.setVolume(newVol)
        mainView.volumeSlider.value = newVol
        persistence.state.volume = newVol
        mainView.marquee.showTemporaryMessage("Volume: \(Int(newVol * 100))%")
        mainView.needsDisplay = true
    }
    
    @objc public func decreaseVolume(by delta: Double = 0.05) {
        let newVol = max(0.0, audioEngine.volume - delta)
        audioEngine.setVolume(newVol)
        mainView.volumeSlider.value = newVol
        persistence.state.volume = newVol
        mainView.marquee.showTemporaryMessage("Volume: \(Int(newVol * 100))%")
        mainView.needsDisplay = true
    }
    
    @objc public func toggleMute() {
        if audioEngine.volume > 0.001 {
            preMuteVolume = audioEngine.volume
            audioEngine.setVolume(0.0)
            mainView.volumeSlider.value = 0.0
            persistence.state.volume = 0.0
            mainView.marquee.showTemporaryMessage("Mute: ON")
        } else {
            let restored = (preMuteVolume > 0.001) ? preMuteVolume : 0.5
            audioEngine.setVolume(restored)
            mainView.volumeSlider.value = restored
            persistence.state.volume = restored
            mainView.marquee.showTemporaryMessage("Volume: \(Int(restored * 100))%")
        }
        mainView.needsDisplay = true
    }
    
    @objc public func handleToggleRepeat() {
        let newR = !playlist.isRepeat
        playlist.isRepeat = newR
        mainView.repeatToggle.isOn = newR
        persistence.state.isRepeat = newR
    }
    
    @objc public func handleToggleShuffle() {
        let newS = !playlist.isShuffle
        playlist.isShuffle = newS
        mainView.shuffleToggle.isOn = newS
        persistence.state.isShuffle = newS
    }
    
    @objc public func handleExit() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Shade Mode Toggles
    public func toggleMainShade() {
        let newShade = !mainView.isShadeMode
        let newH: CGFloat = newShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        windowManager.handleWindowHeightChange(id: .main, newHeightUnscaled: newH)
        mainView.isShadeMode = newShade
        
        mainView.needsLayout = true
        mainView.layoutSubtreeIfNeeded()
        mainView.needsDisplay = true
        mainView.subviews.forEach { $0.needsDisplay = true }
        
        persistence.state.isMainWindowShade = newShade
        persistence.saveSession()
        updateWindowMasks()
    }
    
    public func toggleEqShade() {
        let newShade = !eqView.isShadeMode
        let newH: CGFloat = newShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        windowManager.handleWindowHeightChange(id: .equalizer, newHeightUnscaled: newH)
        eqView.isShadeMode = newShade
        
        eqView.needsLayout = true
        eqView.layoutSubtreeIfNeeded()
        eqView.needsDisplay = true
        eqView.subviews.forEach { $0.needsDisplay = true }
        
        persistence.state.isEqWindowShade = newShade
        persistence.saveSession()
        updateWindowMasks()
    }
    
    public func togglePlShade() {
        let newShade = !plView.isShadeMode
        let newH: CGFloat = newShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        windowManager.handleWindowHeightChange(id: .playlist, newHeightUnscaled: newH)
        plView.isShadeMode = newShade
        
        plView.needsLayout = true
        plView.layoutSubtreeIfNeeded()
        plView.needsDisplay = true
        plView.subviews.forEach { $0.needsDisplay = true }
        
        persistence.state.isPlaylistShade = newShade
        persistence.saveSession()
    }
    
    // MARK: - Double Size Toggle (1x / 2x)
    public func setScale(_ factor: ScaleFactor) {
        let newScale: CGFloat = (factor == .x2) ? 2.0 : 1.0
        windowManager.setScale(newScale)
        mainView?.doubleSizeButton.isSelected = (newScale == 2.0)
        persistence.state.scaleFactor = factor
        persistence.saveSession()
        updateWindowMasks()
        MainMenuManager.shared.updateStates()
    }
    
    public func toggleDoubleSize() {
        let newScale: CGFloat = (windowManager.currentScale == 1.0) ? 2.0 : 1.0
        windowManager.setScale(newScale)
        mainView.doubleSizeButton.isSelected = (newScale == 2.0)
        persistence.state.scaleFactor = (newScale == 2.0) ? .x2 : .x1
        persistence.saveSession()
        updateWindowMasks()
        MainMenuManager.shared.updateStates()
    }
    
    // MARK: - State Restoration
    private func restoreState() {
        let s = persistence.state
        
        // Volume & Balance
        audioEngine.setVolume(s.volume)
        mainView.volumeSlider.value = s.volume
        eqView.eqShadeVolumeSlider.value = s.volume
        audioEngine.setBalance(s.balance)
        mainView.balanceSlider.value = s.balance
        eqView.eqShadeBalanceSlider.value = s.balance
        
        // EQ
        audioEngine.setEqEnabled(s.isEqEnabled)
        eqView.onToggle.isOn = s.isEqEnabled
        audioEngine.setPreamp(gainDb: s.preampDb)
        eqView.preampSlider.value = Double(s.preampDb)
        for (i, gain) in s.eqBandsDb.enumerated() {
            audioEngine.setEQBand(index: i, gainDb: gain)
            if i < eqView.bandSliders.count {
                eqView.bandSliders[i].value = Double(gain)
            }
        }
        
        // Window Visibility
        mainView.eqToggle.isOn = s.isEqWindowVisible
        if !s.isEqWindowVisible { eqWindow.orderOut(nil) }
        mainView.plToggle.isOn = s.isPlaylistVisible
        if !s.isPlaylistVisible { plWindow.orderOut(nil) }
        if !s.isMinibrowserVisible { mbWindow.orderOut(nil) }
        
        // Toggles
        mainView.shuffleToggle.isOn = s.isShuffle
        playlist.isShuffle = s.isShuffle
        mainView.repeatToggle.isOn = s.isRepeat
        playlist.isRepeat = s.isRepeat
        
        // Visualizer & Time
        mainView.visualizer.mode = s.visualizerMode
        mainView.timeDisplay.mode = s.timeDisplayMode
        
        // Scale
        if s.scaleFactor == .x2 {
            windowManager.setScale(2.0)
            mainView.doubleSizeButton.isSelected = true
        } else {
            mainView.doubleSizeButton.isSelected = false
        }
        
        // Shade restoration
        if s.isMainWindowShade {
            toggleMainShade()
        }
        if s.isEqWindowShade {
            toggleEqShade()
        }
        if s.isPlaylistShade {
            togglePlShade()
        }
        
        // Always on top
        if s.isAlwaysOnTop {
            setAlwaysOnTop(true)
        }
        
        // Load saved playlist
        let savedTracks = persistence.loadPlaylist()
        if !savedTracks.isEmpty {
            playlist.add(tracks: savedTracks)
            plView.needsDisplay = true
        }
        
        updateWindowMasks()
    }
    
    public func saveState() {
        persistence.state.volume = mainView.volumeSlider.value
        persistence.state.balance = mainView.balanceSlider.value
        persistence.state.isEqEnabled = eqView.onToggle.isOn
        persistence.state.preampDb = Float(eqView.preampSlider.value)
        persistence.state.eqBandsDb = eqView.bandSliders.map { Float($0.value) }
        persistence.state.isAlwaysOnTop = (mainWindow?.level == .floating)
        persistence.savePlaylist(playlist.tracks)
        persistence.saveSession()
    }
    
    // MARK: - Window Masking & Transparency
    /// Applies skin-defined transparency masks from REGION.TXT to MainWindow and EqualizerWindow.
    public func updateWindowMasks() {
        let region = skinManager.currentSkin?.region
        let mainPath = mainView.isShadeMode ? region?.windowShadeMask : region?.normalMask
        let eqPath = eqView.isShadeMode ? region?.equalizerShadeMask : region?.equalizerMask
        
        applyWindowMask(path: mainPath, to: mainView)
        applyWindowMask(path: eqPath, to: eqView)
    }
    
    private func applyWindowMask(path: CGPath?, to view: NSView) {
        guard let path = path else {
            view.layer?.mask = nil
            view.window?.invalidateShadow()
            return
        }
        
        let maskLayer = CAShapeLayer()
        maskLayer.frame = view.bounds
        maskLayer.fillColor = NSColor.black.cgColor
        maskLayer.fillRule = .nonZero
        maskLayer.path = path
        view.layer?.mask = maskLayer
        view.window?.invalidateShadow()
    }
}
