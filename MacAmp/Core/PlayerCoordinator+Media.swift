import Cocoa

/// Video (⌥V) and Minibrowser (⌥T) windows, made on first use.
extension PlayerCoordinator {
    var videoController: VideoController {
        if let video { return video }
        let made = VideoController(rect: auxWindowRect("video", size: NSSize(width: 275, height: 232)))
        video = made
        return made
    }

    var browserController: BrowserController {
        if let browser { return browser }
        let made = BrowserController(rect: auxWindowRect("browser", size: NSSize(width: 350, height: 348)))
        browser = made
        return made
    }

    @objc public func handleToggleVideo() { videoController.toggle() }
    @objc public func handleToggleBrowser() { browserController.toggle() }

    /// After every successful load: the video window shows a video file's picture, or lets go of the last one
    func videoTrackLoaded(_ url: URL) {
        if VideoController.isVideo(url) || video != nil { videoController.trackLoaded(url.withoutPlaybackRange) }
    }

    /// File types ▸ "Associate with audio CDs": play a disc when macOS mounts it
    func watchForAudioCDs() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { note in
            guard let volume = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { PlayerCoordinator.shared.audioCDMounted(volume) }
        }
    }

    func audioCDMounted(_ volume: URL) {
        guard persistence.state.playInsertedAudioCDs, let cd = AudioCD(volume: volume), !cd.tracks.isEmpty else { return }
        LibraryActions.playCD(cd, tracks: cd.trackItems, enqueue: false)
    }
}

