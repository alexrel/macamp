import Cocoa
import UniformTypeIdentifiers

extension PlayerCoordinator {
    // MARK: - State Restoration
    func restoreState() {
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
        eqView.autoToggle.isOn = s.isEqAuto
        audioEngine.setPreamp(gainDb: s.preampDb)
        eqView.preampSlider.value = Double(s.preampDb)
        for (i, gain) in s.eqBandsDb.enumerated() {
            audioEngine.setEQBand(index: i, gainDb: gain)
            if i < eqView.bandSliders.count {
                eqView.bandSliders[i].value = Double(gain)
            }
        }
        
        // DSP effects (Preferences view model only applies them on change, so restore here)
        audioEngine.applyDSP(enabled: s.isDspEnabled, pitchSemitones: s.dspPitchSemitones, rate: s.dspPlaybackRate,
                             reverbMix: s.dspReverbMix, reverbPreset: s.dspReverbPreset)
        
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
        
        // Scale synchronization
        let targetScale: CGFloat = (s.scaleFactor == .x2) ? 2.0 : 1.0
        if windowManager.currentScale != targetScale {
            windowManager.setScale(targetScale)
        }
        mainView.doubleSizeButton.isSelected = (s.scaleFactor == .x2)
        
        // Shade restoration (only if view state does not already match saved state)
        if mainView.isShadeMode != s.isMainWindowShade {
            toggleMainShade()
        }
        if eqView.isShadeMode != s.isEqWindowShade {
            toggleEqShade()
        }
        if plView.isShadeMode != s.isPlaylistShade {
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
            
            var targetIndex: Int = 0
            if let savedIndex = s.lastPlayedTrackIndex, savedIndex >= 0 && savedIndex < playlist.tracks.count {
                targetIndex = savedIndex
            } else if let savedURLStr = s.lastPlayedTrackURL,
                      let matchIndex = playlist.tracks.firstIndex(where: { $0.url.absoluteString == savedURLStr }) {
                targetIndex = matchIndex
            }
            
            playlist.currentIndex = targetIndex
            playlist.selectedIndices = [targetIndex]
            plView.scrollToTrack(targetIndex, centered: true)
            lastLoadedTrackID = playlist.tracks[targetIndex].id
            
            // Playlists saved by older versions guessed artists from file names; re-read them once in the background
            playlist.migrateLegacyFileNameMetadata { [weak self] in
                guard let self, let current = self.playlist.currentTrack, self.audioEngine.status != .playing else { return }
                self.mainView.marquee.text = current.displayName
                self.plView.needsDisplay = true
            }
            
            let track = playlist.tracks[targetIndex]
            if s.lastPlaybackState == .paused || (s.lastPlaybackState == .playing && s.lastPlayedTrackTime > 0) {
                // Immediately prime UI for paused state
                mainView.marquee.text = track.displayName
                mainView.marquee.resetScroll()
                mainView.timeDisplay.totalDuration = track.duration
                mainView.timeDisplay.currentTime = s.lastPlayedTrackTime
                mainView.timeDisplay.status = .paused
                mainView.seekSlider.isThumbHidden = false
                mainView.seekSlider.value = track.duration > 0 ? (s.lastPlayedTrackTime / track.duration) : 0.0
                plView.status = .paused
                plView.currentTime = s.lastPlayedTrackTime
                updateBlinkState(for: .paused)
                
                preparePausedPlayback(track: track, at: s.lastPlayedTrackTime)
            } else {
                // Stopped state
                mainView.marquee.text = track.displayName
                mainView.marquee.resetScroll()
                mainView.timeDisplay.totalDuration = track.duration
                mainView.timeDisplay.currentTime = 0.0
                mainView.timeDisplay.status = .stopped
                mainView.seekSlider.isThumbHidden = true
                mainView.seekSlider.value = 0.0
                plView.status = .stopped
                plView.currentTime = 0.0
            }
            plView.needsDisplay = true
        }
        
        updateWindowMasks()
    }
    
    public func saveState() {
        persistence.state.volume = mainView.volumeSlider.value
        persistence.state.balance = mainView.balanceSlider.value
        persistence.state.isEqEnabled = eqView.onToggle.isOn
        persistence.state.isEqAuto = eqView.autoToggle.isOn
        persistence.state.autoGenreEQ = eqView.autoToggle.isOn
        persistence.state.preampDb = Float(eqView.preampSlider.value)
        persistence.state.eqBandsDb = eqView.bandSliders.map { Float($0.value) }
        persistence.state.isAlwaysOnTop = (mainWindow?.level == .floating)
        
        // Save current playback state and position
        persistence.state.lastPlaybackState = audioEngine.status
        persistence.state.lastPlayedTrackTime = audioEngine.currentTime
        if let curIdx = playlist.currentIndex, curIdx < playlist.tracks.count {
            persistence.state.lastPlayedTrackIndex = curIdx
            persistence.state.lastPlayedTrackURL = playlist.tracks[curIdx].url.absoluteString
        }
        
        saveWindowLayout()
        persistence.savePlaylist(playlist.tracks)
        persistence.saveSession()
    }
    
    public func saveWindowLayout() {
        guard let main = mainWindow, let eq = eqWindow, let pl = plWindow else { return }
        
        persistence.state.windowPositions["main"] = [
            Double(round(main.frame.minX)),
            Double(round(main.frame.minY)),
            Double(round(main.frame.width)),
            Double(round(main.frame.height))
        ]
        persistence.state.windowPositions["equalizer"] = [
            Double(round(eq.frame.minX)),
            Double(round(eq.frame.minY)),
            Double(round(eq.frame.width)),
            Double(round(eq.frame.height))
        ]
        persistence.state.windowPositions["playlist"] = [
            Double(round(pl.frame.minX)),
            Double(round(pl.frame.minY)),
            Double(round(pl.frame.width)),
            Double(round(pl.frame.height))
        ]
        
        persistence.state.playlistWindowSize = [
            Double(round(pl.frame.width)),
            Double(round(pl.frame.height))
        ]
        persistence.state.scaleFactor = (windowManager.currentScale == 2.0) ? .x2 : .x1
        persistence.state.isMainWindowShade = mainView.isShadeMode
        persistence.state.isEqWindowShade = eqView.isShadeMode
        persistence.state.isPlaylistShade = plView.isShadeMode
        persistence.state.isEqWindowVisible = eq.isVisible
        persistence.state.isPlaylistVisible = pl.isVisible
        saveAuxFrame(video?.window, "video")
        saveAuxFrame(browser?.window, "browser")
        if let library = libraryWindow {
            persistence.state.isLibraryVisible = library.isVisible
            saveLibraryFrame()
        }
        persistence.state.isEqAuto = eqView.autoToggle.isOn
        persistence.state.autoGenreEQ = eqView.autoToggle.isOn
        
        persistence.saveSession()
    }
}
