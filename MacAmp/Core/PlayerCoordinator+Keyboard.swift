import Cocoa
import UniformTypeIdentifiers

extension PlayerCoordinator {
    // MARK: - Keyboard Handling
    public func handleKeyDown(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // 0. Winamp 2.95 keys that work in every window (docs/UI-screens/shortkeys.txt)
        if NSApp.keyWindow === eqWindow,
           eqView.handleEqualizerKey(characters: event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode, flags: flags) {
            return true
        }
        if let video, NSApp.keyWindow === video.window, video.handleKey(event) { return true }
        if handleWinampGlobalKey(keyCode: event.keyCode, flags: flags) { return true }
        
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
        
        // 2. Modifier keys: ⌃ / ⌥ / ⇧ as in Winamp 2.95 (docs/UI-screens/shortkeys.txt), ⌘ for macOS habits
        let mods = flags.intersection([.command, .control, .option, .shift])
        switch (mods, chars) {
        // ⌘ — macOS conventions
        case ([.command], ","), ([.command], "p"): showPreferencesWindow(); return true
        case ([.command], "o"): openFileDialog(); return true
        case ([.command], "u"), ([.command], "l"): openURLDialog(); return true
        case ([.command], "d"): toggleDoubleSize(); return true
        case ([.command], "j"): showJumpToTimeWindow(); return true
        case ([.command], "q"): NSApp.terminate(nil); return true
        // ⌃ — Winamp
        case ([.control], "p"): showPreferencesWindow(); return true
        case ([.control], "l"): openURLDialog(); return true
        case ([.control], "d"): toggleDoubleSize(); return true
        case ([.control], "j"): showJumpToTimeWindow(); return true
        case ([.control], "a"): handleToggleAlwaysOnTop(); return true
        case ([.control], "e"): handleToggleEasyMove(); return true
        case ([.control], "t"): toggleTimeDisplayMode(); return true
        case ([.control], "w"): toggleMainShade(); return true
        case ([.control], "z"): handleStartOfList(); return true
        case ([.control], "v"): handleToggleStopAfterCurrent(); return true
        case ([.control], "k"): handleSelectVisPlugin(); return true
        case ([.control, .shift], "k"): toggleVisualizerStudio(); return true
        // ⌥ — Winamp Alt
        case ([.option], "w"): handleToggleMainWindow(); return true
        case ([.option], "e"): handleTogglePlaylist(); return true
        case ([.option], "g"): handleToggleEqualizer(); return true
        case ([.option], "l"): handleToggleLibrary(); return true
        case ([.option], "t"): handleToggleBrowser(); return true
        case ([.option], "v"): handleToggleVideo(); return true
        case ([.option], "s"): handleSkinBrowser(); return true
        case ([.option], "o"): handleVisualizationOptions(); return true
        case ([.option], "k"): handleConfigureVisPlugin(); return true
        case ([.option], "i"): handleAddBookmark(); return true
        case ([.control, .option], "i"): handleEditBookmarks(); return true
        case ([.option], "m"): minimizeAll(); return true
        // ⇧
        case ([.shift], "l"): openDirectoryDialog(); return true
        case ([.shift], "v"): handleStopWithFadeout(); return true
        default: break
        }
        // ⌥3 (by key code: ⌥ changes the typed character on some layouts)
        if mods == [.option] && (event.keyCode == 20 || chars == "3") {
            showTrackInfoWindow()
            return true
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

    /// Keypad, F1, ⌃Tab, ⌥F, Insert / Help, ⌃F4. Returns false for other keys.
    func handleWinampGlobalKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        typealias K = AppConstants.KeyCodes
        let mods = flags.intersection([.command, .control, .option, .shift])
        if flags.contains(.numericPad) && (mods.isEmpty || mods == [.control]) {
            switch (keyCode, mods) {
            case (K.keypad5, []): handlePlay()
            case (K.keypad4, []): handlePrev()
            case (K.keypad6, []): handleNext()
            case (K.keypad1, []): handleTenTracksBack()
            case (K.keypad3, []): handleTenTracksForward()
            case (K.keypad7, []): handleBack5Seconds()
            case (K.keypad9, []): handleForward5Seconds()
            case (K.keypad8, []): increaseVolume(by: 0.05)
            case (K.keypad2, []): decreaseVolume(by: 0.05)
            case (K.keypad0, []): openFileDialog()
            case (K.keypad0, [.control]): openURLDialog()
            case (K.keypadDecimal, []): showJumpToFileWindow()
            default: return false
            }
            return true
        }
        switch (keyCode, mods) {
        case (K.f1, []): handleAbout()
        case (K.insertHelp, []): openDirectoryDialog()
        case (K.tab, [.control]): cycleWinampWindows()
        case (K.f4, [.control]):
            // Close (hide) the equalizer or playlist editor that has the focus
            if NSApp.keyWindow === eqWindow { handleToggleEqualizer() } else if NSApp.keyWindow === plWindow { handleTogglePlaylist() } else if NSApp.keyWindow === libraryWindow { hideLibraryWindow() } else if let video, NSApp.keyWindow === video.window { video.close() } else if let browser, NSApp.keyWindow === browser.window { browser.hide() } else { return false }
        default:
            // ⌥F: jump to the main menu
            guard mods == [.option], keyCode == 3 /* F */ else { return false }
            let origin = mainWindow.frame.origin
            showMainContextMenu(at: NSPoint(x: origin.x, y: mainWindow.frame.maxY - 14))
        }
        return true
    }
    
    /// ⌃Tab: next visible Winamp window (main → equalizer → playlist).
    func cycleWinampWindows() {
        let windows = [mainWindow, eqWindow, plWindow, libraryWindow, video?.window, browser?.window].compactMap { $0 }.filter(\.isVisible)
        guard !windows.isEmpty else { return }
        let current = windows.firstIndex { $0 === NSApp.keyWindow } ?? -1
        windows[(current + 1) % windows.count].makeKeyAndOrderFront(nil)
    }
}
