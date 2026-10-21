import Cocoa
import UniformTypeIdentifiers

extension PlayerCoordinator {
    // MARK: - Synchronized Blinking for Pause Mode
    
    func updateBlinkState(for status: PlayerStatus) {
        // Blinking only needs a timer while paused and a time display is actually on screen
        let timeVisible = isWindowOnScreen(mainWindow) || isWindowOnScreen(plWindow)
        if status == .paused && timeVisible && blinkTimer != nil { return }
        blinkTimer?.invalidate()
        blinkTimer = nil
        
        if status == .paused && timeVisible {
            isBlinkVisible = true
            mainView.timeDisplay.isBlinkVisible = true
            plView.isBlinkVisible = true
            
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                // Scheduled on RunLoop.main below
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isBlinkVisible.toggle()
                    self.mainView.timeDisplay.isBlinkVisible = self.isBlinkVisible
                    self.plView.isBlinkVisible = self.isBlinkVisible
                }
            }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            blinkTimer = timer
        } else {
            isBlinkVisible = true
            mainView.timeDisplay.isBlinkVisible = true
            plView.isBlinkVisible = true
        }
    }
    
    // MARK: - Playback Handling
    /// Artist / title to show: the file's tags, except for a CUE track, whose file tags describe the whole
    /// album (the engine then reports none and the sheet's names are kept).
    func trackTags(_ meta: TrackMetadata, for track: TrackItem) -> (artist: String, title: String) {
        guard track.url.playbackRange != nil else { return (meta.artist, meta.title) }
        audioEngine.updateCurrentMetadata(title: track.title, artist: track.artist)
        return (track.artist, track.title)
    }
    
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
                        // Follow the playing track, unless the user has scrolled away from the previous one
                        // (playlist.next() already moved currentIndex, so use the track that was actually playing)
                        let wasFollowing = self.lastLoadedTrackID
                            .flatMap { id in self.playlist.tracks.firstIndex(where: { $0.id == id }) }
                            .map { self.plView.isTrackVisible($0) } ?? true
                        self.playlist.currentIndex = idx
                        self.lastLoadedTrackID = track.id
                        if wasFollowing {
                            self.plView.scrollToTrack(idx, centered: false)
                        }
                        self.persistence.state.lastPlayedTrackIndex = idx
                        self.persistence.state.lastPlayedTrackURL = track.url.absoluteString
                        self.persistence.state.lastPlayedTrackTime = 0.0
                        self.persistence.saveSession()
                    }
                    let (artist, title) = self.trackTags(meta, for: track)
                    self.playlist.updateTrack(url: track.url, duration: meta.duration, artist: artist, title: title)
                    self.mainView.marquee.text = TrackItem.displayName(artist: artist, title: title)
                    self.mainView.marquee.resetScroll()
                    self.mainView.timeDisplay.totalDuration = meta.duration
                    self.mainView.timeDisplay.status = .playing
                    self.audioEngine.play()
                    self.mainView.needsDisplay = true
                    self.plView.needsDisplay = true
                    MediaKeyController.shared.updateNowPlayingInfo()
                    StatusBarManager.shared.updateStatus()
                    
                    if self.persistence.state.isEqAuto {
                        self.applyAutoEQ(for: track.url)
                    }
                }
            } catch is CancellationError {
                // Superseded by a newer load (e.g. rapid Next presses) — nothing to report.
            } catch {
                print("Failed to load track \(track.url): \(error)")
                await MainActor.run {
                    let offline = (error as? URLError)?.code == .notConnectedToInternet && MacAmpNetwork.isOffline
                    self.mainView.marquee.showTemporaryMessage(offline ? "Internet disabled (Preferences > Setup)" : (track.url.isFileURL ? "Cannot open file" : "Stream Error"))
                }
            }
        }
    }
    
    /// Primes audio engine and displays in paused state at a specific position without playing out loud.
    public func preparePausedPlayback(track: TrackItem, at savedTime: TimeInterval) {
        if !track.url.isFileURL {
            mainView.marquee.text = track.displayName
            mainView.marquee.resetScroll()
            mainView.timeDisplay.totalDuration = track.duration
            mainView.timeDisplay.currentTime = savedTime
            mainView.timeDisplay.status = .paused
            mainView.seekSlider.isThumbHidden = false
            mainView.seekSlider.value = track.duration > 0 ? (savedTime / track.duration) : 0.0
            plView.currentTime = savedTime
            plView.status = .paused
            updateBlinkState(for: .paused)
            mainView.needsDisplay = true
            plView.needsDisplay = true
            return
        }
        
        Task {
            do {
                let meta = try await audioEngine.load(url: track.url)
                await MainActor.run {
                    let (artist, title) = self.trackTags(meta, for: track)
                    self.playlist.updateTrack(url: track.url, duration: meta.duration, artist: artist, title: title)
                    self.audioEngine.preparePaused(at: savedTime)
                    
                    self.mainView.marquee.text = TrackItem.displayName(artist: artist, title: title)
                    self.mainView.marquee.resetScroll()
                    self.mainView.timeDisplay.totalDuration = meta.duration
                    self.mainView.timeDisplay.currentTime = savedTime
                    self.mainView.timeDisplay.status = .paused
                    self.mainView.seekSlider.isThumbHidden = false
                    self.mainView.seekSlider.value = meta.duration > 0 ? (savedTime / meta.duration) : 0.0
                    
                    self.plView.currentTime = savedTime
                    self.plView.status = .paused
                    self.updateBlinkState(for: .paused)
                    
                    self.mainView.needsDisplay = true
                    self.plView.needsDisplay = true
                    
                    MediaKeyController.shared.updateNowPlayingInfo()
                    StatusBarManager.shared.updateStatus()
                    
                    if self.persistence.state.isEqAuto {
                        self.applyAutoEQ(for: track.url)
                    }
                }
            } catch is CancellationError {
                // Superseded by a newer load.
            } catch {
                print("Failed to preload paused track \(track.url): \(error)")
            }
        }
    }
    
    /// Auto-loads EQ preset based on track's ID3 genre when EQ AUTO is active
    public func applyAutoEQ(for url: URL) {
        guard persistence.state.isEqAuto else { return }
        guard url.isFileURL else {
            applyAutoEQ(genre: audioEngine.icySession?.genre ?? "")
            return
        }
        Task { @MainActor in
            let meta = await AudioMetadataService.shared.readMetadata(from: url)
            // Skip if another track started while the tags were read
            guard playlist.currentTrack?.url == url else { return }
            applyAutoEQ(genre: meta.id3v2.genre.isEmpty ? (meta.id3v1.genreIndex < ID3Genre.allGenres.count ? ID3Genre.name(for: meta.id3v1.genreIndex) : "") : meta.id3v2.genre)
        }
    }
    
    private func applyAutoEQ(genre rawGenre: String) {
        let cleanedGenre = rawGenre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedGenre.isEmpty else { return }
        
        let allPresets = EqualizerPresetsManager.shared.builtInPresets + EqualizerPresetsManager.shared.userPresets
        if let match = allPresets.first(where: { preset in
            let pName = preset.name.lowercased()
            return cleanedGenre == pName || cleanedGenre.contains(pName) || pName.contains(cleanedGenre)
        }) {
            eqView.applyPreset(match)
            mainView.marquee.showTemporaryMessage("EQ Auto: \(match.name)")
        }
    }
    
    // MARK: - End of Track (Stop after current / Manual playlist advance)
    
    /// Winamp Ctrl+V: stop when the current track ends (one-shot).
    public static let fadeOutStopDuration: TimeInterval = 3.0
    
    public enum TrackEndAction: Equatable {
        case stop, replayCurrent, advance
    }
    
    /// What Winamp does when a track ends: "Stop after current" wins (one-shot); with
    /// "Manual playlist advance" it stays on the track (replaying it if Repeat is on); otherwise next track.
    public nonisolated static func actionAfterTrackEnd(stopAfterCurrent: Bool, manualAdvance: Bool, isRepeat: Bool) -> TrackEndAction {
        if stopAfterCurrent { return .stop }
        if manualAdvance { return isRepeat ? .replayCurrent : .stop }
        return .advance
    }
    
    func handleTrackFinished() {
        let action = PlayerCoordinator.actionAfterTrackEnd(stopAfterCurrent: stopAfterCurrent,
                                                           manualAdvance: persistence.state.manualPlaylistAdvance,
                                                           isRepeat: playlist.isRepeat)
        if stopAfterCurrent {
            stopAfterCurrent = false
            MainMenuManager.shared.updateStates()
        }
        switch action {
        case .stop:
            handleStop()
        case .replayCurrent:
            if let current = playlist.currentTrack { loadAndPlay(track: current) } else { handleStop() }
        case .advance:
            playNext()
        }
    }
    
    @objc public func handleStopWithFadeout() {
        guard audioEngine.status == .playing else {
            handleStop()
            return
        }
        audioEngine.stop(fadeOutDuration: PlayerCoordinator.fadeOutStopDuration)
        handleStop() // engine is already stopped; this updates UI, persistence and Now Playing
    }
    
    @objc public func handleToggleStopAfterCurrent() {
        stopAfterCurrent.toggle()
        mainView.marquee.showTemporaryMessage(stopAfterCurrent ? "Stop after current: ON" : "Stop after current: OFF")
        MainMenuManager.shared.updateStates()
    }
    
    @objc public func handleToggleManualAdvance() {
        persistence.state.manualPlaylistAdvance.toggle()
        persistence.scheduleSave()
        mainView.marquee.showTemporaryMessage(persistence.state.manualPlaylistAdvance ? "Manual playlist advance: ON" : "Manual playlist advance: OFF")
        MainMenuManager.shared.updateStates()
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
}
