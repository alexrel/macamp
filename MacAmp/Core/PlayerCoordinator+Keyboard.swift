import Cocoa
import UniformTypeIdentifiers

extension PlayerCoordinator {
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
            case "k":
                toggleVisualizerStudio()
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
}
