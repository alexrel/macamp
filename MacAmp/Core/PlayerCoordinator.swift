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
        let originX = screenFrame.minX + 80
        let originY = screenFrame.maxY - 200
        
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
        mainView.prevButton.action = { [weak self] in self?.playPrevious() }
        mainView.nextButton.action = { [weak self] in self?.playNext() }
        mainView.ejectButton.action = { [weak self] in self?.openFileDialog() }
        mainView.onEject = { [weak self] in self?.openFileDialog() }
        
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
    
    public func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .init(filenameExtension: "mp3")!,
            .init(filenameExtension: "flac")!,
            .init(filenameExtension: "wav")!,
            .init(filenameExtension: "aiff")!,
            .init(filenameExtension: "m4a")!,
            .init(filenameExtension: "aac")!,
            .init(filenameExtension: "alac")!
        ]
        
        if panel.runModal() == .OK {
            let tracks = panel.urls.map { url in
                TrackItem(url: url, title: url.deletingPathExtension().lastPathComponent)
            }
            let wasEmpty = playlist.tracks.isEmpty
            playlist.add(tracks: tracks)
            plView.needsDisplay = true
            
            if wasEmpty, let first = playlist.tracks.first {
                loadAndPlay(track: first)
            }
        }
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
        persistence.savePlaylist(playlist.tracks)
        persistence.saveSession()
    }
}
