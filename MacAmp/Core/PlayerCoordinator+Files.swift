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
            var first = true
            await collectTracks(fromPaths: paths) { batch in
                let wasStopped = (audioEngine.status == .stopped)
                playlist.add(tracks: batch)
                plView.needsDisplay = true
                if first && wasStopped {
                    loadAndPlay(track: batch[0])
                }
                first = false
            }
        }
    }
    
    /// Files dropped into the playlist editor: inserted where they were dropped (Winamp behavior).
    /// Playback starts only if the playlist was empty and nothing was playing.
    public func handleFilesDroppedInPlaylist(_ paths: [String], at index: Int) {
        Task { @MainActor in
            var start: Int?
            var end = index // each batch goes in right after the one before it
            await collectTracks(fromPaths: paths) { batch in
                let wasEmpty = playlist.tracks.isEmpty
                end = min(end, playlist.tracks.count)
                let first = start == nil
                // Everything dropped stays selected while it arrives, until the user selects something else
                let selection = playlist.selectedIndices
                let keepsDropSelected = first || selection == Set(start!..<end)
                playlist.insert(tracks: batch, at: end)
                start = start ?? end
                playlist.selectedIndices = keepsDropSelected ? Set(start!..<(end + batch.count))
                    : Set(selection.map { $0 >= end ? $0 + batch.count : $0 })
                end += batch.count
                plView.needsDisplay = true
                if first && wasEmpty && audioEngine.status == .stopped {
                    loadAndPlay(track: batch[0])
                }
            }
        }
    }
    
    /// File URLs on a drag pasteboard (files, folders, playlists, skins).
    public static func droppedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    
    /// Turns dropped / opened paths into playlist entries: audio files, folders (recursively), M3U/PLS.
    /// Skins (.wsz/.zip or an unpacked skin folder) are installed and applied instead.
    /// Files are read off the main thread, so a big folder doesn't freeze the windows.
    func collectTracks(fromPaths allPaths: [String]) async -> [TrackItem] {
        var tracks: [TrackItem] = []
        await collectTracks(fromPaths: allPaths) { tracks += $0 }
        return tracks
    }

    /// The same, handing the tracks over as they are found: a folder arrives one directory at a time, as in Winamp,
    /// instead of after its whole tree is read (minutes on a network share).
    func collectTracks(fromPaths allPaths: [String], each: ([TrackItem]) -> Void) async {
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
        let (batches, continuation) = AsyncStream.makeStream(of: [TrackItem].self)
        let scan = Task.detached(priority: .userInitiated) {
            let skins = await PlayerCoordinator.scanPaths(paths) { continuation.yield($0) }
            continuation.finish()
            return skins
        }
        // Clearing the playlist stops a folder that is still coming in (a clear made by `each` itself doesn't count)
        var clears = playlist.clearCount
        for await batch in batches {
            guard playlist.clearCount == clears else { scan.cancel(); break }
            each(batch)
            clears = playlist.clearCount
        }
        await scan.value.forEach(installAndApplySkin)
    }

    /// Installing a plug-in runs its programs on this Mac, so it asks first (as Winamp's installers did)
    func confirmAndInstallPlugin(_ path: String) {
        let url = URL(fileURLWithPath: path)
        // A preset pack only copies presets: nothing of it runs
        if let pack = PluginManager.presetPack(url) {
            guard Win32Dialog.confirm(title: "Install plug-in",
                                      message: "Install \(pack.title)?\n\nThe presets go into the AVS preset folder and show up in the AVS window's right-click menu.",
                                      confirmTitle: "Install", cancelTitle: "Cancel") else { return }
            let count = AVSPresets.importPresets(from: pack.folders)
            mainView?.marquee.showTemporaryMessage("AVS presets installed: \(count)", duration: 4)
            return
        }
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
        var tracks: [TrackItem] = []
        let skins = await scanPaths(paths) { tracks += $0 }
        return (tracks, skins)
    }

    /// Hands the entries of `paths` to `found` in order, non-empty batches as they turn up; returns the skins among them.
    /// Files and playlists come with their tags read; a folder comes by file name (see scanFolder).
    nonisolated static func scanPaths(_ paths: [String], found: ([TrackItem]) -> Void) async -> [URL] {
        var skins: [URL] = []
        var loose: [TrackItem] = [] // files and playlist entries: their tags are read at once, in parallel
        func flush() async {
            guard !loose.isEmpty else { return }
            found(await TrackItem.resolveAll(loose))
            loose = []
        }
        let audioExtensions = AppConstants.Audio.supportedExtensions
        let skinExtensions = AppConstants.Audio.skinExtensions
        let playlistExtensions = AppConstants.Audio.playlistExtensions
        let fm = FileManager.default
        
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            
            if skinExtensions.contains(ext) {
                skins.append(url)
            } else if playlistExtensions.contains(ext) {
                loose.append(contentsOf: await PlaylistIO.loadEntries(from: url))
            } else {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    // Unpacked skin folder?
                    if fm.fileExists(atPath: url.appendingPathComponent("MAIN.BMP").path) || fm.fileExists(atPath: url.appendingPathComponent("main.bmp").path) {
                        skins.append(url)
                        continue
                    }
                    await flush()
                    await scanFolder(url, found: found)
                } else if audioExtensions.contains(ext) {
                    loose.append(TrackItem.entry(url: url))
                }
            }
        }
        await flush()
        return skins
    }

    /// A folder's audio files, recursively and in name order like Winamp's "Add directory", one directory per batch.
    /// They go in by file name: PlaylistModel.prefetchMetadata reads tags and lengths once they are in the list.
    private nonisolated static func scanFolder(_ folder: URL, found: ([TrackItem]) -> Void) async {
        let audioExtensions = AppConstants.Audio.supportedExtensions
        let items = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        // An album rip with a CUE sheet is listed as its tracks, not as one long file
        // shortcut: a sheet only hides files of its own folder; look across folders if rips ever keep the audio elsewhere
        let sheets = items.filter { $0.pathExtension.lowercased() == "cue" }
            .compactMap { cue in (try? Data(contentsOf: cue)).map { (cue, TextEncoding.decode($0)) } }
        let covered = Set(sheets.flatMap { CueSheet.referencedFiles(content: $0.1, baseURL: folder) })
        var entries: [TrackItem] = []
        for item in items where !Task.isCancelled {
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if !entries.isEmpty { found(entries) }
                entries = []
                await scanFolder(item, found: found)
            } else if let sheet = sheets.first(where: { $0.0 == item }) {
                // CUE tracks are read now: prefetch would give them the album file's tags and length
                entries += await TrackItem.resolveAll(CueSheet.parse(content: sheet.1, baseURL: folder))
            } else if audioExtensions.contains(item.pathExtension.lowercased()), !covered.contains(item.standardizedFileURL) {
                entries.append(TrackItem.entry(url: item))
            }
        }
        if !entries.isEmpty { found(entries) }
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
            var first = true
            await collectTracks(fromPaths: paths) { batch in
                if first {
                    addOpenedTracks(batch, fromPaths: paths, enqueue: shouldEnqueue)
                } else {
                    playlist.add(tracks: batch)
                    plView.needsDisplay = true
                }
                first = false
            }
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
