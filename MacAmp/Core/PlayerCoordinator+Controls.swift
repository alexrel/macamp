import Cocoa

extension PlayerCoordinator {
    // MARK: - Main window controls as in Winamp 2.95
    // Each transport button does more with a modifier (⇧-click, ⌃-click) and has its own right-click menu
    // listing those actions (strings from winamp.exe 2.95); other controls have small menus too.

    /// Winamp's Ctrl+Click. ⌘ works as well: on a Mac many people use ⌃-click to right-click.
    private var isCtrlClick: Bool { !NSEvent.modifierFlags.intersection([.control, .command]).isEmpty }
    private var isShiftClick: Bool { NSEvent.modifierFlags.contains(.shift) }

    func wireMainWindowControls() {
        mainView.prevButton.action = { [weak self] in self?.previousClicked() }
        mainView.playButton.action = { [weak self] in self?.playClicked() }
        mainView.pauseButton.action = { [weak self] in self?.handlePause() }
        mainView.stopButton.action = { [weak self] in self?.stopClicked() }
        mainView.nextButton.action = { [weak self] in self?.nextClicked() }
        mainView.ejectButton.action = { [weak self] in self?.ejectClicked() }

        mainView.prevButton.contextMenuProvider = { [unowned self] in
            menu([hint("Previous", "Click", #selector(handlePrev)),
                  hint("Start of list", "⌃Click", #selector(handleStartOfList)),
                  hint("Rewind 5 seconds", "⇧Click", #selector(handleBack5Seconds))])
        }
        mainView.playButton.contextMenuProvider = { [unowned self] in
            menu([hint("Play/restart", "Click", #selector(handlePlay)),
                  hint("Open location...", "⌃Click", #selector(handlePlayURL)),
                  hint("Open file...", "⇧Click", #selector(handlePlayFile))])
        }
        mainView.pauseButton.contextMenuProvider = { [unowned self] in
            menu([hint("Pause/Unpause", "Click", #selector(handlePause))])
        }
        mainView.stopButton.contextMenuProvider = { [unowned self] in
            menu([hint("Stop", "Click", #selector(handleStop)),
                  hint("Stop w/ fadeout", "⇧Click", #selector(handleStopWithFadeout)),
                  hint("Stop after current", "⌃Click", #selector(handleToggleStopAfterCurrent), checked: stopAfterCurrent)])
        }
        mainView.nextButton.contextMenuProvider = { [unowned self] in
            menu([hint("Next", "Click", #selector(handleNext)),
                  hint("Fastforward 5 seconds", "⇧Click", #selector(handleForward5Seconds)),
                  hint("End of list", "⌃Click", #selector(handleEndOfList))])
        }
        mainView.ejectButton.contextMenuProvider = { [unowned self] in
            menu([hint("Open file...", "Click", #selector(handlePlayFile)),
                  hint("Open directory...", "⇧Click", #selector(handlePlayDirectory)),
                  hint("Open location...", "⌃Click", #selector(handlePlayURL))])
        }
        mainView.seekSlider.contextMenuProvider = { [unowned self] in
            menu([hint("Jump to time", "⌃J", #selector(handleJumpToTime)),
                  hint("Rewind 5 seconds", "←", #selector(handleBack5Seconds)),
                  hint("Forward 5 seconds", "→", #selector(handleForward5Seconds))])
        }
        mainView.shuffleToggle.contextMenuProvider = { [unowned self] in
            menu([hint("Shuffle", "S", #selector(handleToggleShuffle), checked: playlist.isShuffle)])
        }
        mainView.repeatToggle.contextMenuProvider = { [unowned self] in
            menu([hint("Repeat", "R", #selector(handleToggleRepeat), checked: playlist.isRepeat)])
        }
        mainView.eqToggle.contextMenuProvider = { [unowned self] in
            menu([hint("Graphical Equalizer", "⌥G", #selector(handleToggleEqualizer), checked: mainView.eqToggle.isOn)])
        }
        mainView.plToggle.contextMenuProvider = { [unowned self] in
            menu([hint("Playlist Editor", "⌥E", #selector(handleTogglePlaylist), checked: mainView.plToggle.isOn)])
        }
        mainView.timeDisplay.contextMenuProvider = { [unowned self] in
            let remaining = mainView.timeDisplay.mode == .remaining
            return menu([hint("Time elapsed", "⌃T toggles", #selector(handleTimeElapsed), checked: !remaining),
                         hint("Time remaining", "⌃T toggles", #selector(handleTimeRemaining), checked: remaining)])
        }
        mainView.marquee.contextMenuProvider = { [unowned self] in
            menu([hint("File info", "⌥3 or Dblclick", #selector(handleTrackInfo)),
                  hint("Jump to file...", "J", #selector(handleJumpToFile)),
                  hint("Jump to time...", "⌃J", #selector(handleJumpToTime)),
                  hint("Autoscroll songname", "", #selector(handleToggleAutoscroll), checked: persistence.state.isMarqueeScrollEnabled)])
        }
        applyMainWindowTooltips()
    }

    func previousClicked() {
        if isCtrlClick { handleStartOfList() } else if isShiftClick { handleBack5Seconds() } else { playPrevious() }
    }

    func playClicked() {
        if isCtrlClick { openURLDialog() } else if isShiftClick { openFileDialog() } else { handlePlay() }
    }

    func stopClicked() {
        if isShiftClick { handleStopWithFadeout() } else if isCtrlClick { handleToggleStopAfterCurrent() } else { handleStop() }
    }

    func nextClicked() {
        if isCtrlClick { handleEndOfList() } else if isShiftClick { handleForward5Seconds() } else { playNext() }
    }

    func ejectClicked() {
        if isCtrlClick { openURLDialog() } else if isShiftClick { openDirectoryDialog() } else { openFileDialog() }
    }

    /// ⌃-click Next: the last track of the playlist.
    @objc func handleEndOfList() {
        guard let last = playlist.tracks.last else { return }
        loadAndPlay(track: last)
    }

    @objc func handleToggleAutoscroll() {
        persistence.state.isMarqueeScrollEnabled.toggle()
        persistence.scheduleSave()
        mainView.marquee.fontSettingsChanged() // restarts or stops the scroll timer and redraws
    }

    /// Preferences ▸ Display ▸ "Display tooltips in MacAmp's main window".
    func applyMainWindowTooltips() {
        let on = persistence.state.mainWindowTooltips
        let tips: [(NSView?, String)] = [
            (mainView.prevButton, "Previous"), (mainView.playButton, "Play"), (mainView.pauseButton, "Pause"),
            (mainView.stopButton, "Stop"), (mainView.nextButton, "Next"), (mainView.ejectButton, "Open file(s)"),
            (mainView.seekSlider, "Seek bar"), (mainView.volumeSlider, "Volume bar"), (mainView.balanceSlider, "Panning bar"),
            (mainView.shuffleToggle, "Toggle shuffle"), (mainView.repeatToggle, "Toggle repeat"),
            (mainView.eqToggle, "Toggle Graphical Equalizer"), (mainView.plToggle, "Toggle Playlist Editor"),
            (mainView.optionsButton, "Main menu"), (mainView.minimizeButton, "Minimize"),
            (mainView.shadeButton, "Toggle windowshade mode"), (mainView.closeButton, "Close"),
        ]
        for (view, tip) in tips { view?.toolTip = on ? tip : nil }
    }

    /// Skins ▸ "Random skin on play": a different installed skin each time playback is started.
    func applyRandomSkinIfNeeded() {
        guard persistence.state.randomSkinOnPlay else { return }
        let current = skinManager.isBaseSkinActive ? nil : skinManager.currentSkinURL
        let choices: [URL?] = ([nil] + skinManager.installedSkins().map { Optional($0) }).filter { $0?.path != current?.path }
        guard let pick = choices.randomElement() else { return }
        if let pick {
            if skinManager.loadSkin(from: pick) { persistence.state.activeSkinPath = pick.path }
        } else {
            skinManager.resetToBaseSkin()
            persistence.state.activeSkinPath = nil
        }
        persistence.scheduleSave()
    }

    // MARK: Menu helpers

    private func menu(_ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        return menu
    }

    /// "Previous ........ (Click)": Winamp's two-column item, the hint right-aligned in parentheses.
    private func hint(_ title: String, _ hint: String, _ action: Selector, checked: Bool = false) -> NSMenuItem {
        let item = menuItem(title, action, checked: checked)
        guard !hint.isEmpty else { return item }
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 230)]
        let font = NSFont.menuFont(ofSize: 0)
        item.attributedTitle = NSAttributedString(string: "\(title)\t(\(hint))",
                                                  attributes: [.paragraphStyle: style, .font: font])
        return item
    }

    // MARK: - Disk Writer (out_disk)

    /// With the Disk Writer as output, Play writes the playlist from `track` to the end into files
    /// (in playlist order); Stop cancels. Progress shows in the song title.
    func startDiskWriter(from track: TrackItem) {
        diskWriterTask?.cancel()
        guard let start = playlist.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        audioEngine.stop()
        let tracks = Array(playlist.tracks[start...])
        let folder = persistence.state.diskWriterFolder
        let format = persistence.state.diskWriterFormat
        diskWriterTask = Task { @MainActor in
            var written = 0
            for (offset, item) in tracks.enumerated() {
                guard !Task.isCancelled else { break }
                playlist.currentIndex = start + offset
                plView.needsDisplay = true
                mainView.marquee.text = "Writing \(offset + 1)/\(tracks.count): \(item.displayName)"
                do {
                    _ = try await DiskWriter.write(item, to: folder, format: format)
                    written += 1
                } catch is CancellationError {
                    break
                } catch {
                    mainView.marquee.showTemporaryMessage("Disk Writer: can't write \(item.displayName)")
                }
            }
            mainView.marquee.text = "Disk Writer: \(written) file(s) in \(folder.lastPathComponent)"
            diskWriterTask = nil
        }
    }

    func stopDiskWriter() {
        diskWriterTask?.cancel()
        diskWriterTask = nil
    }
}
