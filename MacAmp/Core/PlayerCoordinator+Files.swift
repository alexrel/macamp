import Cocoa
import UniformTypeIdentifiers

extension PlayerCoordinator {
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
    public func showPreferencesWindow() {
        PreferencesWindow.show()
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
    /// Files dropped on the main or equalizer window: appended to the playlist; if nothing is playing,
    /// the first dropped track starts.
    public func handleDroppedFiles(_ paths: [String]) {
        Task { @MainActor in
            let tracksToAdd = await collectTracks(fromPaths: paths)
            guard !tracksToAdd.isEmpty else { return }
            let wasStopped = (audioEngine.status == .stopped)
            playlist.add(tracks: tracksToAdd)
            plView.needsDisplay = true
            if wasStopped {
                loadAndPlay(track: tracksToAdd[0])
            }
        }
    }
    
    /// Files dropped into the playlist editor: inserted where they were dropped (Winamp behavior).
    /// Playback starts only if the playlist was empty and nothing was playing.
    public func handleFilesDroppedInPlaylist(_ paths: [String], at index: Int) {
        Task { @MainActor in
            let tracks = await collectTracks(fromPaths: paths)
            guard !tracks.isEmpty else { return }
            let wasEmpty = playlist.tracks.isEmpty
            playlist.insert(tracks: tracks, at: min(index, playlist.tracks.count))
            plView.needsDisplay = true
            if wasEmpty && audioEngine.status == .stopped {
                loadAndPlay(track: tracks[0])
            }
        }
    }
    
    /// File URLs on a drag pasteboard (files, folders, playlists, skins).
    public static func droppedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    
    /// Turns dropped / opened paths into playlist entries: audio files, folders (recursively), M3U/PLS.
    /// Skins (.wsz/.zip or an unpacked skin folder) are installed and applied instead.
    /// Tags are read off the main thread, so a big folder doesn't freeze the windows.
    func collectTracks(fromPaths allPaths: [String]) async -> [TrackItem] {
        // Plug-ins (.macampplugin) are installed, after the user says yes
        let plugins = allPaths.filter { $0.lowercased().hasSuffix(".macampplugin") }
        plugins.forEach(confirmAndInstallPlugin)
        var paths = allPaths.filter { !$0.lowercased().hasSuffix(".macampplugin") }
        // Options ▸ Sort files on load: several files at once go in by name, not in the order Finder hands them over
        if persistence.state.sortFilesOnLoad { paths.sort { $0.localizedStandardCompare($1) == .orderedAscending } }
        // Formats only a plug-in plays, without that plug-in: say so instead of nothing happening
        let supported = AppConstants.Audio.supportedExtensions
        if let missing = paths.map({ URL(fileURLWithPath: $0).pathExtension.lowercased() })
            .first(where: { PluginManager.ffmpegFormats.contains($0) && !supported.contains($0) }) {
            mainView?.marquee.showTemporaryMessage("\(missing.uppercased()) files need the FFmpeg plug-in (Preferences ▸ Plug-ins ▸ Input)", duration: 5)
        }
        let (tracks, skins) = await Task.detached(priority: .userInitiated) {
            await PlayerCoordinator.scanPaths(paths)
        }.value
        skins.forEach(installAndApplySkin)
        return tracks
    }

    /// Installing a plug-in runs its programs on this Mac, so it asks first (as Winamp's installers did)
    func confirmAndInstallPlugin(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard let plugin = PluginManager.read(url) else {
            _ = Win32Dialog.confirm(title: "Install plug-in", message: "\(url.lastPathComponent) isn't a MacAmp plug-in.", confirmTitle: "OK", cancelTitle: "Cancel")
            return
        }
        let formats = plugin.extensions.sorted().map { $0.uppercased() }.joined(separator: ", ")
        guard Win32Dialog.confirm(title: "Install plug-in",
                                  message: "Install \(plugin.title)?\n\nIt adds: \(formats).\n\nMacAmp will run the plug-in's programs to convert these files for playback.",
                                  confirmTitle: "Install", cancelTitle: "Cancel") else { return }
        do {
            _ = try PluginManager.install(url)
            mainView?.marquee.showTemporaryMessage("Plug-in installed: \(plugin.title)", duration: 4)
        } catch {
            _ = Win32Dialog.confirm(title: "Install plug-in", message: "Couldn't install it: \(error.localizedDescription)", confirmTitle: "OK", cancelTitle: "Cancel")
        }
    }

    nonisolated static func scanPaths(_ paths: [String]) async -> (tracks: [TrackItem], skins: [URL]) {
        var entries: [TrackItem] = []
        var skins: [URL] = []
        let audioExtensions = AppConstants.Audio.supportedExtensions
        let skinExtensions = AppConstants.Audio.skinExtensions
        let playlistExtensions = AppConstants.Audio.playlistExtensions
        
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            
            if skinExtensions.contains(ext) {
                skins.append(url)
            } else if playlistExtensions.contains(ext) {
                entries.append(contentsOf: await PlaylistIO.loadEntries(from: url))
            } else {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    // Unpacked skin folder?
                    let fm = FileManager.default
                    if fm.fileExists(atPath: url.appendingPathComponent("MAIN.BMP").path) || fm.fileExists(atPath: url.appendingPathComponent("main.bmp").path) {
                        skins.append(url)
                        continue
                    }
                    // Recursively scan for audio files, in name order like Winamp's "Add directory"
                    let all = fm.enumerator(at: url, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
                    // An album rip with a CUE sheet is listed as its tracks, not as one long file
                    let sheets = all.filter { $0.pathExtension.lowercased() == "cue" }
                        .compactMap { cue in (try? Data(contentsOf: cue)).map { (cue, TextEncoding.decode($0)) } }
                    let covered = Set(sheets.flatMap { CueSheet.referencedFiles(content: $0.1, baseURL: $0.0.deletingLastPathComponent()) })
                    var found = all.filter { audioExtensions.contains($0.pathExtension.lowercased()) && !covered.contains($0.standardizedFileURL) }
                        + sheets.map(\.0)
                    found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                    for file in found {
                        if let sheet = sheets.first(where: { $0.0 == file }) {
                            entries.append(contentsOf: CueSheet.parse(content: sheet.1, baseURL: file.deletingLastPathComponent()))
                        } else {
                            entries.append(TrackItem.entry(url: file))
                        }
                    }
                } else if audioExtensions.contains(ext) {
                    entries.append(TrackItem.entry(url: url))
                }
            }
        }
        // Read all tags at once, in parallel
        return (await TrackItem.resolveAll(entries), skins)
    }
    
    func installAndApplySkin(at url: URL) {
        if let installedURL = skinManager.installSkin(from: url) {
            persistence.state.activeSkinPath = installedURL.path
            persistence.saveSession()
        }
    }
    
    // MARK: - Opening from Finder (double-click, Open With, Services)
    
    
    /// Files opened from Finder. Winamp semantics: play them, or just add them when
    /// "Enqueue as default action" is on (or the Enqueue service was used).
    public func openFromFinder(_ paths: [String], enqueue: Bool? = nil) {
        let shouldEnqueue = enqueue ?? persistence.state.enqueueAsDefaultAction
        // Launching MacAmp by double-clicking a file delivers it before the windows exist
        guard isStarted else {
            pendingFinderOpens.append((paths, shouldEnqueue))
            return
        }
        Task { @MainActor in
            let tracks = await collectTracks(fromPaths: paths)
            guard !tracks.isEmpty else { return }
            addOpenedTracks(tracks, fromPaths: paths, enqueue: shouldEnqueue)
        }
    }

    func addOpenedTracks(_ tracks: [TrackItem], fromPaths paths: [String], enqueue shouldEnqueue: Bool) {
        // Winamp: "Play" on a playlist file replaces the current list; "Enqueue" appends to it
        let opensPlaylistFile = paths.contains { AppConstants.Audio.playlistExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        if opensPlaylistFile && !shouldEnqueue {
            audioEngine.stop()
            playlist.clear()
        }
        playlist.add(tracks: tracks)
        plView.needsDisplay = true
        if !shouldEnqueue || audioEngine.status == .stopped && playlist.tracks.count == tracks.count {
            loadAndPlay(track: tracks[0])
            if let idx = playlist.tracks.firstIndex(where: { $0.id == tracks[0].id }) {
                plView.scrollToTrack(idx, centered: false)
            }
        }
        bringAllWindowsToFront()
    }
    
    func processPendingFinderOpens() {
        let pending = pendingFinderOpens
        pendingFinderOpens.removeAll()
        for item in pending {
            openFromFinder(item.paths, enqueue: item.enqueue)
        }
    }
}
