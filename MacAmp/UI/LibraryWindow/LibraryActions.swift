import Cocoa

/// What the Media Library's buttons and menus do with the player.
@MainActor
enum LibraryActions {
    private static var coordinator: PlayerCoordinator { .shared }

    /// Winamp's Play replaces the playlist and starts the first track; Enqueue appends.
    static func play(_ tracks: [TrackItem], enqueue: Bool, startAt start: Int = 0) {
        guard !tracks.isEmpty else { return }
        // A disc being ripped can't play: refuse before the playlist is touched
        if tracks.contains(where: { AudioCD.isRipping($0.url) }) {
            coordinator.mainView?.marquee.showTemporaryMessage(AudioCD.busyMessage, duration: 4)
            return
        }
        let c = coordinator
        if enqueue {
            c.playlist.add(tracks: tracks)
        } else {
            c.audioEngine.stop()
            c.playlist.clear()
            c.playlist.add(tracks: tracks)
            if c.playlist.tracks.indices.contains(start) { c.loadAndPlay(track: c.playlist.tracks[start]) }
        }
        c.plView?.needsDisplay = true
    }

    /// Double-click / Enter: Play or Enqueue (Options ▸ Media Library); ⇧ swaps them, as in gen_ml.
    static func doubleClick(_ tracks: [TrackItem], shift: Bool = false) {
        play(tracks, enqueue: PersistenceManager.shared.state.libraryDoubleClickEnqueues != shift)
    }

    /// Right-click on library items (ml_local: Play / Enqueue selection, Explore item folder, Remove from library)
    static func itemMenu(_ items: [MediaLibraryItem], removable: Bool) -> NSMenu? {
        guard !items.isEmpty else { return nil }
        let menu = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) { menu.addItem(Win32ClosureMenuItem(title: title, handler: action)) }
        add("Play selection\tEnter") { play(items.map(\.track), enqueue: false) }
        add("Enqueue selection\t⇧Enter") { play(items.map(\.track), enqueue: true) }
        menu.addItem(.separator())
        add("Explore item folder") { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url).filter(\.isFileURL)) }
        if removable {
            menu.addItem(.separator())
            add("Remove from library\tDelete") { removeFromLibrary(items) }
        }
        return menu
    }

    static func removeFromLibrary(_ items: [MediaLibraryItem]) {
        MediaLibrary.shared.remove(Set(items.map(\.id)))
    }

    static func playStations(_ stations: [RadioStation], enqueue: Bool) {
        let tracks = stations.compactMap { station in station.streamURL.map { TrackItem.entry(url: $0, title: station.name) } }
        play(tracks, enqueue: enqueue)
    }

    /// "N items [h:mm:ss]" under the list.
    static func summary(_ items: [MediaLibraryItem]) -> String {
        let total = items.reduce(0) { $0 + $1.length }
        let h = Int(total) / 3600, m = Int(total) / 60 % 60, s = Int(total) % 60
        let time = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return "\(items.count) item\(items.count == 1 ? "" : "s") [\(time)]"
    }

    // MARK: Library button menu (docs/UI-screens/library-menu.png)

    static func showLibraryMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) { menu.addItem(Win32ClosureMenuItem(title: title, handler: action)) }
        add("Compact library (remove missing items)...") {
            let removed = MediaLibrary.shared.compact()
            coordinator.mainView?.marquee.showTemporaryMessage("Library: removed \(removed) missing item(s)")
        }
        menu.addItem(.separator())
        add("Add new view...", addView)
        add("Add new playlist...", createPlaylist)
        menu.addItem(.separator())
        add("Add directory to library...", addDirectory)
        add("Rescan library folders") { Task { await MediaLibrary.shared.rescan() } }
        add("Library preferences...") { PreferencesWindow.show(treeItem: .library) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    static func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Add directory to library"
        guard panel.runModal() == .OK else { return }
        let folders = panel.urls
        Task { for folder in folders { await MediaLibrary.shared.addDirectory(folder) } }
    }

    /// Add view: a name and a query (see LibraryQuery), shown as a simple list.
    static func addView() {
        guard let values = Win32Dialog.promptFields(title: "Add view", fields: [("Name", ""), ("Query", "type = 0")], width: 460) else { return }
        let name = values[0].trimmingCharacters(in: .whitespaces), query = values[1].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            _ = try LibraryQuery.parse(query)
            MediaLibrary.shared.views.append(LibraryView(name: name, query: query))
            MediaLibrary.shared.save()
        } catch {
            _ = Win32Dialog.confirm(title: "Add view", message: "The query isn't valid: \(error).\n\nExample: type = 0 & artist = \"air\" & length > 360",
                                    confirmTitle: "OK", cancelTitle: "Cancel")
        }
    }

    static func createPlaylist() {
        guard let name = Win32Dialog.prompt(title: "Create playlist", message: "Name:")?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else { return }
        MediaLibrary.shared.createPlaylist(named: name)
    }

    static func importPlaylistFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AppConstants.Audio.playlistExtensions.compactMap { .init(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            let tracks = await PlaylistIO.loadPlaylist(from: url)
            MediaLibrary.shared.createPlaylist(named: url.deletingPathExtension().lastPathComponent, tracks: tracks)
        }
    }

    static func importCurrentPlaylist() {
        let tracks = coordinator.playlist.tracks
        guard !tracks.isEmpty else { return }
        MediaLibrary.shared.createPlaylist(named: "Playlist \(MediaLibrary.shared.playlists.count + 1)", tracks: tracks)
    }

    /// Plays CD tracks at once; MusicBrainz names replace "Track N" in the playlist when they arrive.
    static func playCD(_ cd: AudioCD, tracks: [TrackItem], enqueue: Bool) {
        play(tracks, enqueue: enqueue)
        guard cd.album.isEmpty else { return }
        Task { @MainActor in
            guard let named = await AudioCD.named(volume: cd.volume) else { return }
            for track in named.tracks { coordinator.playlist.updateTrack(url: track.url, artist: track.artist, title: track.title) }
            coordinator.plView?.needsDisplay = true
        }
    }

    /// Devices ▸ CD ▸ Extract, with Preferences ▸ Options ▸ CD Ripping.
    static func rip(_ cd: AudioCD, tracks: [Int]) {
        let state = PersistenceManager.shared.state
        let volume = cd.volume.standardizedFileURL.path
        let progress = RipProgress.shared
        guard !AudioCD.ripping.contains(volume) else { return }
        AudioCD.ripping.insert(volume)
        progress.status[volume] = "Extracting..."
        // The drive can't play and rip at once: stop playback from this disc
        if let current = coordinator.playlist.currentTrack, AudioCD.isRipping(current.url), coordinator.audioEngine.status != .stopped {
            coordinator.handleStop()
        }
        Task { @MainActor in
            defer { AudioCD.ripping.remove(volume); progress.objectWillChange.send() }
            do {
                let (files, failed) = try await cd.rip(tracks, to: state.cdRipFolder, template: state.cdRipTemplate, format: state.cdRipFormat, aacKbps: state.cdRipAACKbps,
                                                       writeTags: state.cdRipWriteTags) { i, n in progress.status[volume] = "Extracting track \(i) of \(n)..." }
                if state.cdRipAddToLibrary, !files.isEmpty { MediaLibrary.shared.add(await MediaLibrary.readItems(files) { _ in }) }
                var playlistError = ""
                if files.count == cd.tracks.count { // 2.95: playlists only for an entire CD
                    do {
                        try cd.writeRipPlaylists(files, to: state.cdRipFolder, template: state.cdRipPlaylistTemplate,
                                                 m3u: state.cdRipM3U, extended: state.cdRipExtendedM3U, pls: state.cdRipPLS)
                    } catch {
                        playlistError = "; couldn't write the playlist: \(error.localizedDescription)"
                    }
                    if state.cdRipLibraryPlaylist {
                        MediaLibrary.shared.createPlaylist(named: cd.album.isEmpty ? "Audio CD" : "\(cd.artist) - \(cd.album)",
                                                           tracks: cd.ripItems(files))
                    }
                }
                let skipped = failed.isEmpty ? "" : "; couldn't read track(s) \(failed.map(String.init).joined(separator: ", "))"
                progress.status[volume] = "Extracted \(files.count) track(s) to \(files.first?.deletingLastPathComponent().lastPathComponent ?? state.cdRipFolder.lastPathComponent)\(skipped)\(playlistError)"
            } catch {
                progress.status[volume] = "[Error] \(error.localizedDescription)"
            }
        }
    }
}

/// Extract progress per disc (volume path), kept outside the CD page so switching pages doesn't hide a running rip.
@MainActor
final class RipProgress: ObservableObject {
    static let shared = RipProgress()
    @Published var status: [String: String] = [:]
}
