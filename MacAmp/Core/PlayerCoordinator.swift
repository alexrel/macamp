import Cocoa
import Foundation
import Combine

public class PlayerCoordinator: NSObject {
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
    
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        super.init()
    }
    
    public func start() {
        setupWindows()
        setupBindings()
        restoreState()
    }
    
    // MARK: - Window Setup
    private func setupWindows() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let originX = screenFrame.minX + max(50, (screenFrame.width - AppConstants.Window.width) / 2)
        let originY = screenFrame.maxY - 150
        
        // 1. Main Window
        let mainRect = NSRect(x: originX, y: originY, width: AppConstants.Window.width, height: AppConstants.Window.height)
        mainWindow = WinampWindow(windowID: .main, contentRect: mainRect)
        mainView = MainWindowView()
        mainWindow.contentView = mainView
        
        // 2. Equalizer Window (docked directly below Main: y = originY - height)
        let eqRect = NSRect(x: originX, y: originY - AppConstants.Window.height, width: AppConstants.Window.width, height: AppConstants.Window.height)
        eqWindow = WinampWindow(windowID: .equalizer, contentRect: eqRect)
        eqView = EqualizerWindowView()
        eqWindow.contentView = eqView
        
        // 3. Playlist Window (docked directly below EQ: y = originY - 2 * height)
        let plRect = NSRect(x: originX, y: originY - (2 * AppConstants.Window.height), width: AppConstants.Window.width, height: AppConstants.Window.height)
        plWindow = WinampWindow(windowID: .playlist, contentRect: plRect)
        plView = PlaylistWindowView(playlist: playlist)
        plWindow.contentView = plView
        
        // Show windows
        mainWindow.makeKeyAndOrderFront(nil)
        eqWindow.orderFront(nil)
        plWindow.orderFront(nil)
    }
    
    // MARK: - Bindings & Events
    private func setupBindings() {
        // 1. Audio Engine Callbacks
        audioEngine.onTimeUpdate = { [weak self] currentSec in
            guard let self else { return }
            self.mainView.timeDisplay.currentTime = currentSec
            if let meta = self.audioEngine.currentMetadata, meta.duration > 0 {
                self.mainView.seekSlider.value = currentSec / meta.duration
            }
        }
        
        audioEngine.onSpectralDataUpdate = { [weak self] bins in
            self?.mainView.visualizer.spectrumAmplitudes = bins
        }
        
        audioEngine.onWaveformDataUpdate = { [weak self] wave in
            self?.mainView.visualizer.waveformPoints = wave
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
        
        // Window Toggles
        mainView.eqToggle.onChanged = { [weak self] isVisible in
            guard let self else { return }
            if isVisible {
                self.eqWindow.orderFront(nil)
            } else {
                self.eqWindow.orderOut(nil)
            }
            self.persistence.state.isEqWindowVisible = isVisible
        }
        
        mainView.plToggle.onChanged = { [weak self] isVisible in
            guard let self else { return }
            if isVisible {
                self.plWindow.orderFront(nil)
            } else {
                self.plWindow.orderOut(nil)
            }
            self.persistence.state.isPlaylistVisible = isVisible
        }
        
        // Shade mode toggles
        mainView.onToggleShade = { [weak self] in self?.toggleMainShade() }
        eqView.onToggleShade = { [weak self] in self?.toggleEqShade() }
        plView.onToggleShade = { [weak self] in self?.togglePlShade() }
        
        // Close EQ & PL
        eqView.onClose = { [weak self] in
            self?.mainView.eqToggle.isOn = false
        }
        plView.onClose = { [weak self] in
            self?.mainView.plToggle.isOn = false
        }
        
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
        
        // Redraw on skin change
        skinManager.skinDidChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.mainView.needsDisplay = true
                self?.eqView.needsDisplay = true
                self?.plView.needsDisplay = true
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Playback Handling
    public func loadAndPlay(track: TrackItem) {
        Task {
            do {
                let meta = try await audioEngine.load(url: track.url)
                await MainActor.run {
                    self.mainView.marquee.text = "\(track.artist) - \(track.title)"
                    self.mainView.timeDisplay.totalDuration = meta.duration
                    self.mainView.timeDisplay.status = .playing
                    self.audioEngine.play()
                    self.mainView.needsDisplay = true
                    self.plView.needsDisplay = true
                }
            } catch {
                print("Failed to load track \(track.url): \(error)")
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
        panel.allowedContentTypes = [
            .init(filenameExtension: "mp3")!,
            .init(filenameExtension: "flac")!,
            .init(filenameExtension: "wav")!,
            .init(filenameExtension: "aiff")!,
            .init(filenameExtension: "aif")!,
            .init(filenameExtension: "m4a")!,
            .init(filenameExtension: "aac")!,
            .init(filenameExtension: "alac")!,
            .init(filenameExtension: "ogg")!
        ]
        
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
    
    public func openSkinChooser() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "wsz")!,
            .init(filenameExtension: "zip")!
        ]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if skinManager.loadSkin(from: url) {
                persistence.state.activeSkinPath = url.path
                persistence.saveSession()
            }
        }
    }
    
    // MARK: - Drag & Drop Handling
    public func handleDroppedFiles(_ paths: [String]) {
        var tracksToAdd: [TrackItem] = []
        let audioExtensions: Set<String> = ["mp3", "flac", "wav", "aiff", "aif", "m4a", "aac", "alac", "ogg"]
        let skinExtensions: Set<String> = ["wsz", "zip"]
        let playlistExtensions: Set<String> = ["m3u", "pls"]
        
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            
            if skinExtensions.contains(ext) {
                if skinManager.loadSkin(from: url) {
                    persistence.state.activeSkinPath = url.path
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
                            if skinManager.loadSkin(from: url) {
                                persistence.state.activeSkinPath = url.path
                                persistence.saveSession()
                            }
                            continue
                        }
                        
                        // Recursively scan for audio files
                        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                            for case let fileURL as URL in enumerator {
                                if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                                    tracksToAdd.append(TrackItem(url: fileURL, title: fileURL.deletingPathExtension().lastPathComponent))
                                }
                            }
                        }
                    } else if audioExtensions.contains(ext) {
                        tracksToAdd.append(TrackItem(url: url, title: url.deletingPathExtension().lastPathComponent))
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
        case 123: // Left Arrow -> Seek back 5 seconds
            let cur = audioEngine.currentTime
            audioEngine.seek(to: max(0, cur - 5.0))
            return true
        case 124: // Right Arrow -> Seek forward 5 seconds
            if let meta = audioEngine.currentMetadata {
                let cur = audioEngine.currentTime
                audioEngine.seek(to: min(meta.duration, cur + 5.0))
            }
            return true
        case 126: // Up Arrow -> Volume up 5%
            let newVol = min(1.0, audioEngine.volume + 0.05)
            audioEngine.setVolume(newVol)
            mainView.volumeSlider.value = newVol
            persistence.state.volume = newVol
            return true
        case 125: // Down Arrow -> Volume down 5%
            let newVol = max(0.0, audioEngine.volume - 0.05)
            audioEngine.setVolume(newVol)
            mainView.volumeSlider.value = newVol
            persistence.state.volume = newVol
            return true
        case 49: // Space -> Toggle Pause/Resume
            audioEngine.togglePause()
            return true
        case 36: // Enter / Return -> Play selected or current track
            if let cur = playlist.currentTrack ?? playlist.tracks.first {
                loadAndPlay(track: cur)
            }
            return true
        case 51: // Backspace / Delete -> Remove selected in playlist
            playlist.removeSelected()
            plView.needsDisplay = true
            return true
        default:
            break
        }
        
        // 2. Modifier keys
        if flags.contains(.command) || flags.contains(.control) {
            switch chars {
            case "d":
                toggleDoubleSize()
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
            switch chars {
            case "s":
                openSkinChooser()
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
    
    // MARK: - Always On Top
    public func setAlwaysOnTop(_ enabled: Bool) {
        persistence.state.isAlwaysOnTop = enabled
        let level: NSWindow.Level = enabled ? .floating : .normal
        mainWindow?.level = level
        eqWindow?.level = level
        plWindow?.level = level
    }
    
    // MARK: - Skins Discovery
    private func discoverAvailableSkins() -> [URL] {
        var foundURLs: [URL] = []
        let candidates: [URL?] = [
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("MacAmp/Skins"),
            URL(fileURLWithPath: "webamp-master/packages/webamp/demo/skins"),
            URL(fileURLWithPath: "ClassicSkins")
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let enumerator = FileManager.default.enumerator(at: candidate, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "wsz" && !fileURL.lastPathComponent.contains("base-2.91") {
                        foundURLs.append(fileURL)
                    }
                }
            }
        }
        return foundURLs
    }
    
    // MARK: - Context Menu
    public func showMainContextMenu(at screenPoint: NSPoint? = nil, in view: NSView? = nil) {
        let menu = NSMenu(title: "Winamp")
        
        // About
        let aboutItem = NSMenuItem(title: "Winamp...", action: #selector(handleAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())
        
        // Play submenu
        let playMenu = NSMenu(title: "Play")
        let playFileItem = NSMenuItem(title: "File...", action: #selector(handlePlayFile), keyEquivalent: "l")
        playFileItem.target = self
        playMenu.addItem(playFileItem)
        
        let playDirItem = NSMenuItem(title: "Directory...", action: #selector(handlePlayDirectory), keyEquivalent: "L")
        playDirItem.target = self
        playMenu.addItem(playDirItem)
        
        let playMenuItem = NSMenuItem(title: "Play", action: nil, keyEquivalent: "")
        playMenuItem.submenu = playMenu
        menu.addItem(playMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // Windows toggles
        let eqItem = NSMenuItem(title: "Equalizer", action: #selector(handleToggleEqualizer), keyEquivalent: "")
        eqItem.target = self
        eqItem.state = mainView.eqToggle.isOn ? .on : .off
        menu.addItem(eqItem)
        
        let plItem = NSMenuItem(title: "Playlist", action: #selector(handleTogglePlaylist), keyEquivalent: "")
        plItem.target = self
        plItem.state = mainView.plToggle.isOn ? .on : .off
        menu.addItem(plItem)
        menu.addItem(NSMenuItem.separator())
        
        // Skins submenu
        let skinsMenu = NSMenu(title: "Skins")
        let baseSkinItem = NSMenuItem(title: "Winamp Classic (Default)", action: #selector(handleResetBaseSkin), keyEquivalent: "")
        baseSkinItem.target = self
        baseSkinItem.state = (skinManager.currentSkin?.name == "base-2.91" || skinManager.currentSkin == nil) ? .on : .off
        skinsMenu.addItem(baseSkinItem)
        
        let loadSkinItem = NSMenuItem(title: "Load Skin...", action: #selector(handleLoadSkin), keyEquivalent: "")
        loadSkinItem.target = self
        skinsMenu.addItem(loadSkinItem)
        
        let discoveredSkins = discoverAvailableSkins()
        if !discoveredSkins.isEmpty {
            skinsMenu.addItem(NSMenuItem.separator())
            for skinURL in discoveredSkins {
                let name = skinURL.deletingPathExtension().lastPathComponent
                let item = NSMenuItem(title: name, action: #selector(handleSkinSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = skinURL
                item.state = (skinManager.currentSkin?.name == name) ? .on : .off
                skinsMenu.addItem(item)
            }
        }
        
        let skinsMenuItem = NSMenuItem(title: "Skins", action: nil, keyEquivalent: "")
        skinsMenuItem.submenu = skinsMenu
        menu.addItem(skinsMenuItem)
        
        // Options submenu
        let optionsMenu = NSMenu(title: "Options")
        let topItem = NSMenuItem(title: "Always On Top", action: #selector(handleToggleAlwaysOnTop), keyEquivalent: "")
        topItem.target = self
        topItem.state = persistence.state.isAlwaysOnTop ? .on : .off
        optionsMenu.addItem(topItem)
        
        let dblItem = NSMenuItem(title: "Double Size", action: #selector(handleToggleDoubleSize), keyEquivalent: "d")
        dblItem.target = self
        dblItem.state = (windowManager.currentScale == 2.0) ? .on : .off
        optionsMenu.addItem(dblItem)
        
        let optMenuItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        optMenuItem.submenu = optionsMenu
        menu.addItem(optMenuItem)
        
        // Playback submenu
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
        
        let pbMenuItem = NSMenuItem(title: "Playback", action: nil, keyEquivalent: "")
        pbMenuItem.submenu = pbMenu
        menu.addItem(pbMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit MacAmp", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        let targetPt = screenPoint ?? NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: targetPt, in: nil)
    }
    
    // MARK: - Menu Actions
    @objc public func handleAbout() {
        let alert = NSAlert()
        alert.messageText = "MacAmp 2.91"
        alert.informativeText = "Pixel-perfect classic Winamp 2.91 reproduction for macOS.\n\nBuilt with Swift, AppKit, and AVFoundation.\nSupports classic .wsz skins, 10-band EQ with presets, and authentic audio engine."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc public func handlePlayFile() {
        openFileDialog()
    }
    
    @objc public func handlePlayDirectory() {
        openDirectoryDialog()
    }
    
    @objc public func handleToggleEqualizer() {
        mainView.eqToggle.isOn.toggle()
        mainView.eqToggle.onChanged?(mainView.eqToggle.isOn)
    }
    
    @objc public func handleTogglePlaylist() {
        mainView.plToggle.isOn.toggle()
        mainView.plToggle.onChanged?(mainView.plToggle.isOn)
    }
    
    @objc public func handleResetBaseSkin() {
        skinManager.resetToBaseSkin()
        persistence.state.activeSkinPath = nil
        persistence.saveSession()
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
        } else if let track = playlist.currentTrack ?? playlist.tracks.first {
            loadAndPlay(track: track)
        }
    }
    
    @objc public func handlePause() {
        audioEngine.togglePause()
    }
    
    @objc public func handleStop() {
        audioEngine.stop()
        mainView.timeDisplay.status = .stopped
        mainView.needsDisplay = true
    }
    
    @objc public func handleNext() {
        playNext()
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
    
    @objc public func handleQuit() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Shade Mode Toggles
    public func toggleMainShade() {
        let newShade = !mainView.isShadeMode
        mainView.isShadeMode = newShade
        
        let newH: CGFloat = newShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        let scale = windowManager.currentScale
        
        var frame = mainWindow.frame
        let diff = (frame.height - (newH * scale))
        frame.origin.y += diff
        frame.size.height = newH * scale
        mainWindow.setFrame(frame, display: true, animate: false)
        persistence.state.isMainWindowShade = newShade
    }
    
    public func toggleEqShade() {
        let newShade = !eqView.isShadeMode
        eqView.isShadeMode = newShade
        
        let newH: CGFloat = newShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        let scale = windowManager.currentScale
        
        var frame = eqWindow.frame
        let diff = (frame.height - (newH * scale))
        frame.origin.y += diff
        frame.size.height = newH * scale
        eqWindow.setFrame(frame, display: true, animate: false)
        persistence.state.isEqWindowShade = newShade
    }
    
    public func togglePlShade() {
        let newShade = !plView.isShadeMode
        plView.isShadeMode = newShade
        
        let newH: CGFloat = newShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        let scale = windowManager.currentScale
        
        var frame = plWindow.frame
        let diff = (frame.height - (newH * scale))
        frame.origin.y += diff
        frame.size.height = newH * scale
        plWindow.setFrame(frame, display: true, animate: false)
        persistence.state.isPlaylistShade = newShade
    }
    
    // MARK: - Double Size Toggle (1x / 2x)
    public func toggleDoubleSize() {
        let current = windowManager.currentScale
        let newScale: CGFloat = (current == 1.0) ? 2.0 : 1.0
        windowManager.currentScale = newScale
        
        for (_, win) in windowManager.windows {
            var frame = win.frame
            let oldW = frame.width / current
            let oldH = frame.height / current
            frame.size.width = oldW * newScale
            frame.size.height = oldH * newScale
            win.setFrame(frame, display: true, animate: false)
        }
        
        persistence.state.scaleFactor = (newScale == 2.0) ? .x2 : .x1
    }
    
    // MARK: - State Restoration
    private func restoreState() {
        let s = persistence.state
        
        // Volume & Balance
        audioEngine.setVolume(s.volume)
        mainView.volumeSlider.value = s.volume
        audioEngine.setBalance(s.balance)
        mainView.balanceSlider.value = s.balance
        
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
            toggleDoubleSize()
        }
        
        // Skin restoration
        if let skinPath = s.activeSkinPath, FileManager.default.fileExists(atPath: skinPath) {
            skinManager.loadSkin(from: URL(fileURLWithPath: skinPath))
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
}
