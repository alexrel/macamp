import Cocoa
import Foundation
import Combine
import UniformTypeIdentifiers

@MainActor
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
    
    public var visualizerStudioWindow: RetroVisualizerWindow?
    /// Media Library (⌥L), made on first show
    public var libraryWindow: WinampWindow?
    /// Video and Minibrowser windows (PlayerCoordinator+Media), made on first use
    var video: VideoController?
    var browser: BrowserController?
    
    var cancellables = Set<AnyCancellable>()
    public var isDeminiaturizing: Bool = false
    
    // State used by the extensions (PlayerCoordinator+*.swift)
    var blinkTimer: Timer?
    var isBlinkVisible: Bool = true
    /// Track whose audio was last loaded (playing/paused); used to decide whether the playlist follows track changes.
    var lastLoadedTrackID: UUID?
    public internal(set) var stopAfterCurrent = false
    /// Finder opens that arrive before the windows exist (launch by double-clicking a file)
    var isStarted = false
    var pendingFinderOpens: [(paths: [String], enqueue: Bool)] = []
    var preMuteVolume: Double = 0.5
    /// Preferences ▸ Visualization ▸ Refresh rate
    var visualizerThrottle = VisualizerThrottle()
    /// The Visualizer Studio's own reading of the analysis (spectrum with falloff, and the waveform), so it works
    /// whatever the main window's visualizer shows (spectrum, oscilloscope or off)
    let studioFeed: VisualizerView = { let v = VisualizerView(); v.mode = .spectrum; return v }()
    /// Disk Writer run in progress (Play with the Disk Writer output)
    var diskWriterTask: Task<Void, Never>?
    
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
        if persistence.state.isLibraryVisible { showLibraryWindow(); mainWindow.makeKeyAndOrderFront(nil) }
        watchForAudioCDs()
        PluginConversion.onProgress = { [weak self] url, fraction in
            let text = "Converting for playback: \(Int(fraction * 100))%"
            self?.mainView.marquee.showTemporaryMessage(text, duration: 1)
            if let video = self?.video, VideoController.isVideo(url) { video.frameView.info = "\(url.lastPathComponent): \(text)" }
        }
        if persistence.state.isBrowserVisible { browserController.show(); mainWindow.makeKeyAndOrderFront(nil) }
        if persistence.state.libraryRescanOnStart { Task { await MediaLibrary.shared.rescan() } }
        isStarted = true
        // First start: Winamp's installer launched it with demo.mp3, the llama intro, which then stayed in the playlist
        // as an ordinary entry. Copied out of the bundle, whose path changes when the app is moved or translocated.
        if persistence.isFirstRun, playlist.tracks.isEmpty, pendingFinderOpens.isEmpty,
           let bundled = Bundle.main.url(forResource: "demo", withExtension: "mp3") {
            let demo = persistence.baseDir.appendingPathComponent("demo.mp3")
            try? FileManager.default.copyItem(at: bundled, to: demo)
            if FileManager.default.fileExists(atPath: demo.path) { handleDroppedFiles([demo.path]) }
        }
        processPendingFinderOpens()
    }
    
    // MARK: - Window Setup
    func setupWindows() {
        let state = persistence.state
        let savedPositions = state.windowPositions
        windowManager.currentScale = state.scaleFactor.scale
        let scale = windowManager.scale(for: .main)
        let eqScale = windowManager.scale(for: .equalizer)
        let plScale = windowManager.scale(for: .playlist)
        let mainHeight = state.isMainWindowShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        let eqHeight = state.isEqWindowShade ? AppConstants.Window.shadeHeight : AppConstants.Window.height
        let mainSize = windowManager.frameSize(for: .main, logical: NSSize(width: AppConstants.Window.width, height: mainHeight))
        let eqSize = windowManager.frameSize(for: .equalizer, logical: NSSize(width: AppConstants.Window.width, height: eqHeight))
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let defaultOriginX = floor(screenFrame.minX + max(50, (screenFrame.width - mainSize.width) / 2))
        let defaultOriginY = floor(screenFrame.maxY - 150)
        
        // Playlist sizing (canonical 25px X step, 29px Y step)
        let rawPlW = CGFloat(state.playlistWindowSize.first ?? Double(AppConstants.Window.width))
        let rawPlH = CGFloat(state.playlistWindowSize.last ?? Double(AppConstants.Window.height))
        let stepsX = max(0, round((rawPlW - AppConstants.Window.width) / AppConstants.Window.resizeStepX))
        let plW = AppConstants.Window.width + stepsX * AppConstants.Window.resizeStepX
        let stepsY = max(0, round((rawPlH - AppConstants.Window.height) / AppConstants.Window.resizeStepY))
        let plH = AppConstants.Window.height + stepsY * AppConstants.Window.resizeStepY
        let plHeight = state.isPlaylistShade ? AppConstants.Window.shadeHeight : plH
        let plSize = windowManager.frameSize(for: .playlist, logical: NSSize(width: plW, height: plHeight))
        
        let mainRect: NSRect
        let eqRect: NSRect
        let plRect: NSRect
        
        if let mPos = savedPositions["main"], mPos.count >= 2,
           let ePos = savedPositions["equalizer"], ePos.count >= 2,
           let pPos = savedPositions["playlist"], pPos.count >= 2 {
            
            // An entry gives the top-left corner (see savedFrame(of:)); the size follows from the state above
            func restored(_ pos: [Double], _ size: NSSize) -> NSRect {
                let top = pos.count >= 4 ? pos[1] + pos[3] : pos[1] + size.height
                return NSRect(x: pos[0], y: top - size.height, width: size.width, height: size.height)
            }
            let rawMainRect = restored(mPos, mainSize)
            let rawEqRect = restored(ePos, eqSize)
            let rawPlRect = restored(pPos, plSize)
            
            // Check if saved position is visible on any currently connected screen
            if windowManager.isRectVisibleOnAnyScreen(rawMainRect) {
                mainRect = rawMainRect
                eqRect = rawEqRect
                plRect = rawPlRect
            } else {
                // Saved positions were on a disconnected display!
                windowManager.savedExternalPositions = [
                    .main: rawMainRect.origin,
                    .equalizer: rawEqRect.origin,
                    .playlist: rawPlRect.origin
                ]
                windowManager.hasUserMovedWindowsSinceRelocation = false
                
                // Relocate entire docked cluster to main screen preserving relative offsets
                let deltaX = defaultOriginX - rawMainRect.minX
                let deltaY = defaultOriginY - rawMainRect.minY
                mainRect = NSRect(origin: NSPoint(x: round(rawMainRect.minX + deltaX), y: round(rawMainRect.minY + deltaY)), size: rawMainRect.size)
                eqRect = NSRect(origin: NSPoint(x: round(rawEqRect.minX + deltaX), y: round(rawEqRect.minY + deltaY)), size: rawEqRect.size)
                plRect = NSRect(origin: NSPoint(x: round(rawPlRect.minX + deltaX), y: round(rawPlRect.minY + deltaY)), size: rawPlRect.size)
            }
        } else {
            // Default standard Winamp layout (Main top -> EQ middle -> PL bottom)
            mainRect = NSRect(origin: NSPoint(x: defaultOriginX, y: defaultOriginY), size: mainSize)
            eqRect = NSRect(origin: NSPoint(x: defaultOriginX, y: mainRect.minY - eqSize.height), size: eqSize)
            plRect = NSRect(origin: NSPoint(x: defaultOriginX, y: eqRect.minY - plSize.height), size: plSize)
        }
        
        // 1. Main Window
        mainWindow = WinampWindow(windowID: .main, contentRect: mainRect)
        mainWindow.delegate = self
        mainView = MainWindowView()
        mainView.isShadeMode = state.isMainWindowShade
        mainView.autoresizesSubviews = false
        mainWindow.contentView = mainView
        mainWindow.updateContentScale(scale, logicalSize: NSSize(width: AppConstants.Window.width, height: mainHeight))
        
        // 2. Equalizer Window
        eqWindow = WinampWindow(windowID: .equalizer, contentRect: eqRect)
        eqView = EqualizerWindowView()
        eqView.isShadeMode = state.isEqWindowShade
        eqView.autoresizesSubviews = false
        eqWindow.contentView = eqView
        eqWindow.updateContentScale(eqScale, logicalSize: NSSize(width: AppConstants.Window.width, height: eqHeight))
        
        // 3. Playlist Window
        plWindow = WinampWindow(windowID: .playlist, contentRect: plRect)
        plView = PlaylistWindowView(playlist: playlist)
        plView.isShadeMode = state.isPlaylistShade
        plView.autoresizesSubviews = false
        plWindow.contentView = plView
        plWindow.updateContentScale(plScale, logicalSize: NSSize(width: plW, height: plHeight))
        plWindow.initialFirstResponder = plView // playlist keyboard navigation works as soon as the window is key
    }
    
    // MARK: - Window Display
    func showWindows() {
        bringAllWindowsToFront()
        updateActivityState()
    }
    
    // MARK: - Bindings & Events
    func setupBindings() {
        // 1. Audio Engine Callbacks
        audioEngine.onStatusUpdate = { [weak self] status in
            guard let self else { return }
            if status == .stopped { self.video?.playbackStopped() }
            self.persistence.state.lastPlaybackState = status
            self.persistence.state.lastPlayedTrackTime = self.audioEngine.currentTime
            if let curIdx = self.playlist.currentIndex, curIdx < self.playlist.tracks.count {
                self.persistence.state.lastPlayedTrackIndex = curIdx
                self.persistence.state.lastPlayedTrackURL = self.playlist.tracks[curIdx].url.absoluteString
            }
            self.persistence.scheduleSave()
            
            self.mainView.timeDisplay.status = status
            self.plView.status = status
            self.updateBlinkState(for: status)
            self.mainView.seekSlider.isThumbHidden = (status == .stopped)
            if status == .stopped {
                self.mainView.seekSlider.value = 0.0
            }
            // Winamp: a paused visualizer freezes on its last picture, a stopped one goes back to the skin's
            if status == .stopped {
                self.mainView.visualizer.clear()
            }
            self.updateActivityState()
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
            let seekSec = val * meta.duration
            self.audioEngine.seek(to: seekSec)
            self.persistence.state.lastPlayedTrackTime = seekSec
            self.persistence.scheduleSave()
        }
        
        audioEngine.onVisualizerFrame = { [weak self] frame in
            guard let self else { return }
            let (draw, frames) = self.visualizerThrottle.shouldDraw(at: CACurrentMediaTime(), fps: self.persistence.state.visualizerFPS)
            guard draw else { return }
            // Only while playing: the emptied frame sent when analysis switches off would make a paused picture fall
            // and repaint a stopped one
            if self.audioEngine.status == .playing {
                self.mainView.visualizer.falloffScale = frames
                self.mainView.visualizer.update(from: frame)
            }
            if let studio = self.visualizerStudioWindow, studio.isVisible {
                self.studioFeed.falloffScale = frames
                self.studioFeed.update(from: frame)
                studio.updateSpectrum(self.studioFeed.spectrumAmplitudes)
                studio.updateWaveform(self.studioFeed.waveformPoints)
            }
        }
        
        audioEngine.onStreamEvent = { [weak self] message in
            self?.mainView.marquee.showTemporaryMessage(message, duration: 2.5)
        }
        
        audioEngine.onMetadataUpdate = { [weak self] artist, title, bitrate, sampleRate in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.mainView.marquee.text = TrackItem.displayName(artist: artist, title: title)
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
            self?.handleTrackFinished()
        }
        audioEngine.crossfadeDuration = persistence.state.crossfadeSeconds
        audioEngine.canCrossfadeIntoNext = { [weak self] in
            guard let self else { return false }
            let action = PlayerCoordinator.actionAfterTrackEnd(stopAfterCurrent: self.stopAfterCurrent,
                                                               manualAdvance: self.persistence.state.manualPlaylistAdvance,
                                                               isRepeat: self.playlist.isRepeat)
            // A CUE album plays continuously (live / gapless albums), so its tracks don't crossfade
            return action == .advance && self.playlist.hasNext && self.playlist.currentTrack?.url.playbackRange == nil
        }
        
        // 2. Transport actions
        wireMainWindowControls()
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
        
        // Layout change persistence
        windowManager.onLayoutChanged = { [weak self] in
            self?.saveWindowLayout()
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
            self.windowManager.updateAdjacencies()
            self.saveWindowLayout()
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
            self.windowManager.updateAdjacencies()
            self.saveWindowLayout()
        }
        
        // EQ Toggles
        eqView.onToggle.onChanged = { [weak self] isOn in
            guard let self else { return }
            self.audioEngine.setEqEnabled(isOn)
            self.persistence.state.isEqEnabled = isOn
            self.persistence.saveSession()
        }
        
        eqView.autoToggle.onChanged = { [weak self] isOn in
            guard let self else { return }
            self.persistence.state.isEqAuto = isOn
            self.persistence.state.autoGenreEQ = isOn
            self.persistence.saveSession()
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
        
        // ClutterBar buttons (A, I, D, V)
        mainView.onToggleAlwaysOnTop = { [weak self] in self?.handleToggleAlwaysOnTop() }
        mainView.onTrackInfo = { [weak self] in self?.showTrackInfoWindow() }
        mainView.onToggleDoubleSize = { [weak self] in self?.toggleDoubleSize() }
        mainView.onToggleVisualizerMode = { [weak self] in self?.cycleVisualizerMode() }
        
        // Time display mode toggle
        mainView.timeDisplay.onToggleMode = { [weak self] in self?.toggleTimeDisplayMode() }
        
        // Visualizer mode cycle (clicking directly on visualizer view)
        mainView.visualizer.onToggleMode = { [weak self] in self?.cycleVisualizerMode() }
        mainView.visualizer.menuProvider = { [weak self] in self?.buildVisualizationMenu() ?? NSMenu() }
        
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
                self.refreshAllViews()
                // New skin, new cursors
                self.mainView.invalidateSkinCursorsRecursively()
                self.eqView.invalidateSkinCursorsRecursively()
                self.plView.invalidateSkinCursorsRecursively()
                self.visualizerStudioWindow?.frameView.invalidateSkinCursorsRecursively()
            }
            .store(in: &cancellables)
            
        // Observe window focus & application active state changes to update active titlebars
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitleBarFocus() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitleBarFocus() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitleBarFocus() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitleBarFocus() }
            .store(in: &cancellables)
            
        // Hidden (Cmd+H), minimized or fully covered windows: stop visualizer, marquee and blink work
        let activityNotifications: [(NotificationCenter, Notification.Name)] = [
            (NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification),
            (NotificationCenter.default, NSWindow.didMiniaturizeNotification),
            (NotificationCenter.default, NSWindow.didDeminiaturizeNotification),
            (NotificationCenter.default, NSApplication.didHideNotification),
            (NotificationCenter.default, NSApplication.didUnhideNotification)
        ]
        for (center, name) in activityNotifications {
            center.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.updateActivityState() }
                .store(in: &cancellables)
        }
        
        // Observe screen configuration changes (monitor connect/disconnect, resolution changes)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.windowManager.handleScreenParametersChanged()
            }
            .store(in: &cancellables)
    }
    
    public func updateTitleBarFocus() {
        mainView?.needsDisplay = true
        eqView?.needsDisplay = true
        plView?.needsDisplay = true
        libraryWindow?.contentView?.needsDisplay = true
        video?.frameView.needsDisplay = true
        browser?.frameView.needsDisplay = true
        visualizerStudioWindow?.frameView.needsDisplay = true
    }
    
    public func refreshAllViews() {
        mainView?.setNeedsDisplayRecursively()
        eqView?.setNeedsDisplayRecursively()
        plView?.setNeedsDisplayRecursively()
        visualizerStudioWindow?.frameView.setNeedsDisplayRecursively()
        // The Library, Video and Minibrowser frames are skinned too: without this they kept the old skin until clicked
        libraryWindow?.contentView?.setNeedsDisplayRecursively()
        video?.frameView.setNeedsDisplayRecursively()
        browser?.frameView.setNeedsDisplayRecursively()
        updateWindowMasks()
    }
    
    // MARK: - Activity Gating (CPU / battery)
    
    func isWindowOnScreen(_ window: NSWindow?) -> Bool {
        guard let window, window.isVisible, !window.isMiniaturized, !NSApp.isHidden else { return false }
        return window.occlusionState.contains(.visible)
    }
    
    /// Turns per-frame work on only when someone can see it: spectrum tap (visualizer visible and on),
    /// marquee scrolling (playing, main window visible) and the pause blink (a time display visible).
    public func updateActivityState() {
        guard let mainView else { return }
        let mainVisible = isWindowOnScreen(mainWindow)
        let studioVisible = isWindowOnScreen(visualizerStudioWindow)
        visualizerStudioWindow?.studioView.setActivity(visible: studioVisible, playing: audioEngine.status == .playing)
        audioEngine.isAnalysisEnabled = (mainVisible && mainView.visualizer.mode != .off) || studioVisible
        mainView.marquee.isScrollingActive = mainVisible && audioEngine.status == .playing
        updateBlinkState(for: audioEngine.status)
    }
    
    func cycleVisualizerMode() {
        let next = mainView.visualizer.mode.next
        setVisualizerMode(next)
        let modeName = (next == .spectrum) ? "Spectrum" : (next == .oscilloscope ? "Oscilloscope" : "Off")
        mainView.marquee.showTemporaryMessage("Vis Mode: \(modeName)")
    }
}
