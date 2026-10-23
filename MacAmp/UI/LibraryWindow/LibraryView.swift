import SwiftUI
import AppKit

/// The page the Library shows; other windows open it on a page (Video's "TV" button, the Minibrowser's radio link)
@MainActor
final class LibraryNavigation: ObservableObject {
    static let shared = LibraryNavigation()
    @Published var node: LibraryNode = .localMedia
}

/// Nodes of the library tree (docs/UI-screens/library*.png)
enum LibraryNode: Hashable {
    case localMedia
    case view(UUID)
    case playlists
    case playlist(UUID)
    case devices
    case cd(URL)
    case internetRadio
}

/// Winamp 2.95 Media Library content (inside the GEN frame): tree on the left with the "Library" button,
/// the selected node's page on the right.
struct MediaLibraryView: View {
    @ObservedObject var library = MediaLibrary.shared
    @ObservedObject private var navigation = LibraryNavigation.shared
    private var node: LibraryNode {
        get { navigation.node }
        nonmutating set { navigation.node = newValue }
    }
    @State private var discs: [URL] = PlayerCoordinator.mountedAudioCDs()
    @State private var treeWidth = CGFloat(PersistenceManager.shared.state.libraryTreeWidth)

    var body: some View {
        let theme = GenexTheme.current
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                tree(theme)
                GenexButton("Library") { LibraryActions.showLibraryMenu() }
                    .frame(maxWidth: .infinity)
            }
            .frame(width: treeWidth)
            PaneDivider(vertical: true) { delta in
                treeWidth = min(400, max(80, treeWidth + delta))
            } onEnd: {
                PersistenceManager.shared.state.libraryTreeWidth = Double(treeWidth)
                PersistenceManager.shared.scheduleSave()
            }
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 2)
        .background(theme.windowBackground)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            discs = PlayerCoordinator.mountedAudioCDs()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            discs = PlayerCoordinator.mountedAudioCDs()
        }
    }

    // MARK: Tree

    private func tree(_ theme: GenexTheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                treeRow("Local Media", .localMedia, indent: 0, theme)
                ForEach(library.views) { view in treeRow(view.name, .view(view.id), indent: 1, last: view.id == library.views.last?.id, theme) }
                treeRow("Playlists", .playlists, indent: 0, theme)
                ForEach(library.playlists) { list in treeRow(list.name, .playlist(list.id), indent: 1, last: list.id == library.playlists.last?.id, theme) }
                treeRow("Devices", .devices, indent: 0, theme)
                ForEach(discs, id: \.self) { disc in treeRow("CD \(disc.lastPathComponent)", .cd(disc), indent: 1, last: disc == discs.last, theme) }
                treeRow("Internet Radio", .internetRadio, indent: 0, theme)
            }
            .padding(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.itemBackground)
        .overlay(Rectangle().stroke(theme.divider, lineWidth: 1))
    }

    private func treeRow(_ title: String, _ target: LibraryNode, indent: Int, last: Bool = false, _ theme: GenexTheme) -> some View {
        let selected = node == target
        return HStack(spacing: 0) {
            // Winamp's tree: dotted branches from the parent, the last child's ending at its row
            if indent > 0 { TreeConnector(isLast: last, color: theme.divider, height: 15).padding(.leading, 2) }
            Text(title)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(selected ? theme.selectedText : theme.itemForeground)
                .padding(.horizontal, 2)
                .background(selected ? theme.selection : Color.clear)
            Spacer(minLength: 0)
        }
        .frame(height: 15)
        .contentShape(Rectangle())
        .gesture(TapGesture(count: 2).onEnded {
            if case .playlist(let id) = target { LibraryActions.play(library.playlists.first { $0.id == id }?.tracks ?? [], enqueue: false) }
        })
        .simultaneousGesture(TapGesture().onEnded { node = target })
        .contextMenu { treeContextMenu(target) }
    }

    @ViewBuilder
    private func treeContextMenu(_ target: LibraryNode) -> some View {
        switch target {
        case .view(let id) where !MediaLibrary.defaultViews.map(\.name).contains(library.views.first { $0.id == id }?.name ?? ""):
            Button("Delete view") { library.views.removeAll { $0.id == id }; library.save(); node = .localMedia }
        case .playlist(let id):
            Button("Play") { LibraryActions.play(library.playlists.first { $0.id == id }?.tracks ?? [], enqueue: false) }
            Button("Enqueue") { LibraryActions.play(library.playlists.first { $0.id == id }?.tracks ?? [], enqueue: true) }
            Button("Delete playlist") { library.removePlaylist(id); node = .playlists }
        default:
            EmptyView()
        }
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch node {
        case .localMedia:
            MediaListPage(items: library.items)
        case .view(let id):
            if let view = library.views.first(where: { $0.id == id }) {
                if view.artistAlbumBrowser {
                    ArtistAlbumPage(items: library.items(for: view))
                } else {
                    MediaListPage(items: library.items(for: view), searchKey: view.id.uuidString)
                }
            }
        case .playlists:
            InfoPage(text: "This is where you manage your playlists.\n\nA playlist contains a series of audio tracks which can be played in sequence.\n\nDouble click a playlist on the left to load it into the Playlist Editor and play it, or select it to see its tracks.",
                     buttons: [("Create new playlist", LibraryActions.createPlaylist),
                               ("Import playlist from file", LibraryActions.importPlaylistFile),
                               ("Import active (current) playlist", LibraryActions.importCurrentPlaylist)])
        case .playlist(let id):
            MediaListPage(items: (library.playlists.first { $0.id == id }?.tracks ?? []).map(MediaLibraryItem.init(track:)),
                          searchable: false)
        case .devices:
            InfoPage(text: "This is the list of devices (CD players) currently connected to your Mac.\n\nInsert an audio CD in a CD drive to see it here.", buttons: [])
        case .cd(let disc):
            CDPage(disc: disc)
        case .internetRadio:
            RadioPage()
        }
    }
}

extension MediaLibraryItem {
    init(track: TrackItem) {
        self.init(url: track.url, title: track.title)
        artist = track.artist
        length = track.duration
    }
}

// MARK: - Shared list (columns, header, rows)

struct MediaColumn {
    let title: String
    let width: CGFloat
    let alignment: Alignment
    let value: (MediaLibraryItem) -> String

    static let standard: [MediaColumn] = [
        MediaColumn(title: "Artist", width: 120, alignment: .leading) { $0.artist },
        MediaColumn(title: "Title", width: 150, alignment: .leading) { $0.title },
        MediaColumn(title: "Album", width: 120, alignment: .leading) { $0.album },
        MediaColumn(title: "Length", width: 46, alignment: .trailing) { $0.length > 0 ? PlaylistModel.formatTime($0.length) : "" },
        MediaColumn(title: "Track #", width: 46, alignment: .trailing) { $0.trackNumber > 0 ? String($0.trackNumber) : "" },
        MediaColumn(title: "Genre", width: 80, alignment: .leading) { $0.genre },
        MediaColumn(title: "Year", width: 40, alignment: .leading) { $0.year },
        MediaColumn(title: "Filename", width: 260, alignment: .leading) { $0.url.isFileURL ? $0.url.path : $0.url.absoluteString },
    ]
}

// MARK: - Local Media / views / playlist pages

struct MediaListPage: View {
    let items: [MediaLibraryItem]
    var searchable = true
    /// Which list this is, for a remembered search ("LocalMedia", a view's id)
    var searchKey = "LocalMedia"
    @State private var search = ""
    @State private var selection = Set<String>()

    var body: some View {
        let theme = GenexTheme.current
        let shown = MediaLibrary.filter(items, search: search)
        VStack(spacing: 3) {
            if searchable {
                SearchBar(text: $search)
                    .onAppear { if PersistenceManager.shared.state.libraryRememberSearch { search = PersistenceManager.shared.state.librarySearches[searchKey] ?? "" } }
                    .onChange(of: search) { _, value in
                        guard PersistenceManager.shared.state.libraryRememberSearch else { return }
                        PersistenceManager.shared.state.librarySearches[searchKey] = value
                        PersistenceManager.shared.scheduleSave()
                    }
            }
            MediaListView(rows: shown, columns: MediaColumn.standard.map { ($0.title, $0.width, $0.alignment, $0.value) },
                          selection: $selection, autosave: searchable ? "LocalMedia" : "Playlist", defaultSort: searchable ? "Artist" : nil,
                          url: { $0.url }, menu: { LibraryActions.itemMenu($0, removable: searchable) },
                          onDelete: searchable ? { LibraryActions.removeFromLibrary($0) } : nil) { rows, shift in
                // 2.95: "Play entire playlist on playlist item doubleclick" / "Play entire query on single query item doubleclick"
                let state = PersistenceManager.shared.state
                let whole = searchable ? state.libraryPlayWholeQuery : state.libraryPlayWholePlaylist
                if whole, rows.count == 1, state.libraryDoubleClickEnqueues == shift, let start = shown.firstIndex(where: { $0.id == rows[0].id }) {
                    LibraryActions.play(shown.map(\.track), enqueue: false, startAt: start)
                } else {
                    LibraryActions.doubleClick(rows.map(\.track), shift: shift)
                }
            }
            HStack(spacing: 3) {
                let picked = shown.filter { selection.contains($0.id) }.map(\.track)
                GenexButton("Play", width: 46) { LibraryActions.play(picked, enqueue: false) }.disabled(picked.isEmpty)
                GenexButton("Enqueue", width: 56) { LibraryActions.play(picked, enqueue: true) }.disabled(picked.isEmpty)
                GenexButton("Play all", width: 56) { LibraryActions.play(shown.map(\.track), enqueue: false) }.disabled(shown.isEmpty)
                GenexButton("Enqueue all", width: 70) { LibraryActions.play(shown.map(\.track), enqueue: true) }.disabled(shown.isEmpty)
                Text(LibraryActions.summary(shown))
                    .font(.system(size: 10))
                    .foregroundColor(theme.windowText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    var body: some View {
        let theme = GenexTheme.current
        HStack(spacing: 4) {
            Text("Search:").font(.system(size: 11)).foregroundColor(theme.windowText)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(theme.itemForeground)
                .padding(.horizontal, 3)
                .frame(height: 15)
                .background(theme.itemBackground)
                .overlay(Rectangle().stroke(theme.divider, lineWidth: 1))
        }
    }
}

/// Local Media ▸ Audio: Artist and Album panes above the track list.
struct ArtistAlbumPage: View {
    let items: [MediaLibraryItem]
    @State private var artist: String?
    @State private var album: String?
    @State private var panesHeight = CGFloat(PersistenceManager.shared.state.libraryPanesHeight)
    @State private var artistFraction = CGFloat(PersistenceManager.shared.state.libraryArtistFraction)

    private struct Group: Identifiable { let id: String; let name: String; let albums: Int; let tracks: Int }

    var body: some View {
        let byArtist = Dictionary(grouping: items, by: \.artist)
        let artists = [Group(id: "*", name: "All (\(byArtist.count) artists)", albums: Set(items.map(\.album)).count, tracks: items.count)]
            + byArtist.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { name in
                Group(id: name, name: name.isEmpty ? "(unknown artist)" : name,
                      albums: Set(byArtist[name]!.map(\.album)).count, tracks: byArtist[name]!.count)
            }
        let artistItems = artist.map { byArtist[$0] ?? [] } ?? items
        let byAlbum = Dictionary(grouping: artistItems, by: \.album)
        let albums = [Group(id: "*", name: "All (\(byAlbum.count) albums)", albums: 0, tracks: artistItems.count)]
            + byAlbum.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { name in
                Group(id: name, name: name.isEmpty ? "(unknown album)" : name, albums: 0, tracks: byAlbum[name]!.count)
            }
        let tracks = album.map { byAlbum[$0] ?? [] } ?? artistItems
        VStack(spacing: 0) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    MediaListView(rows: artists, columns: [("Artist", 150, .leading, { $0.name }), ("Albums", 46, .trailing, { String($0.albums) }),
                                                            ("Tracks", 46, .trailing, { String($0.tracks) })],
                                  selection: Binding(get: { [artist ?? "*"] }, set: { artist = $0.first == "*" ? nil : $0.first; album = nil }),
                                  autosave: "AudioArtists", defaultSort: "Artist", pinsFirstRow: true) { _, shift in
                        LibraryActions.doubleClick(tracks.map(\.track), shift: shift)
                    }
                    .frame(width: max(60, (geo.size.width - 4) * artistFraction))
                    PaneDivider(vertical: true) { delta in
                        artistFraction = min(0.85, max(0.15, artistFraction + delta / max(1, geo.size.width - 4)))
                    } onEnd: {
                        PersistenceManager.shared.state.libraryArtistFraction = Double(artistFraction)
                        PersistenceManager.shared.scheduleSave()
                    }
                    MediaListView(rows: albums, columns: [("Album", 170, .leading, { $0.name }), ("Tracks", 46, .trailing, { String($0.tracks) })],
                                  selection: Binding(get: { [album ?? "*"] }, set: { album = $0.first == "*" ? nil : $0.first }),
                                  autosave: "AudioAlbums", defaultSort: "Album", pinsFirstRow: true) { _, shift in
                        LibraryActions.doubleClick(tracks.map(\.track), shift: shift)
                    }
                }
            }
            .frame(height: panesHeight)
            PaneDivider(vertical: false) { delta in
                panesHeight = min(400, max(40, panesHeight + delta))
            } onEnd: {
                PersistenceManager.shared.state.libraryPanesHeight = Double(panesHeight)
                PersistenceManager.shared.scheduleSave()
            }
            MediaListPage(items: tracks)
        }
    }
}

struct InfoPage: View {
    let text: String
    let buttons: [(String, () -> Void)]
    var body: some View {
        let theme = GenexTheme.current
        VStack(spacing: 3) {
            Spacer()
            Text(text)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundColor(theme.windowText)
                .padding(.horizontal, 20)
            Spacer()
            HStack(spacing: 3) {
                ForEach(buttons.indices, id: \.self) { i in GenexButton(buttons[i].0, action: buttons[i].1) }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Devices ▸ CD

struct CDPage: View {
    let disc: URL
    @State private var cd: AudioCD?
    @State private var selection = Set<String>()
    @State private var status = ""
    @ObservedObject private var progress = RipProgress.shared

    var body: some View {
        let theme = GenexTheme.current
        let volume = disc.standardizedFileURL.path
        let ripping = AudioCD.ripping.contains(volume)
        let tracks = (cd?.tracks ?? []).map { t -> MediaLibraryItem in
            var item = MediaLibraryItem(url: t.url, title: t.title)
            item.artist = t.artist
            item.trackNumber = t.number
            item.length = t.length
            return item
        }
        let picked = tracks.filter { selection.contains($0.id) }
        VStack(alignment: .leading, spacing: 3) {
            Text(cd.map { $0.album.isEmpty ? disc.lastPathComponent : "\($0.artist) - \($0.album)\($0.year.isEmpty ? "" : " (\($0.year))")" } ?? disc.lastPathComponent)
                .font(.system(size: 11)).foregroundColor(theme.windowText).lineLimit(1)
            MediaListView(rows: tracks, columns: [("Track #", 50, .trailing, { String($0.trackNumber) }),
                                                  ("Artist", 130, .leading, { $0.artist }),
                                                  ("Title", 220, .leading, { $0.title }),
                                                  ("Length", 50, .trailing, { PlaylistModel.formatTime($0.length) })],
                          selection: $selection, autosave: "CD", url: { $0.url },
                          menu: { LibraryActions.itemMenu($0, removable: false) }) { rows, shift in
                play(rows, enqueue: PersistenceManager.shared.state.libraryDoubleClickEnqueues != shift)
            }
            HStack(spacing: 3) {
                GenexButton("Play CD") { play(tracks, enqueue: false) }
                GenexButton("Enqueue CD") { play(tracks, enqueue: true) }
                GenexButton("Play selected") { play(picked, enqueue: false) }.disabled(picked.isEmpty)
                GenexButton("Enqueue selected") { play(picked, enqueue: true) }.disabled(picked.isEmpty)
                GenexButton("Extract") {
                    guard let cd else { return }
                    LibraryActions.rip(cd, tracks: (picked.isEmpty ? tracks : picked).map(\.trackNumber))
                }.disabled(ripping)
                GenexButton("Eject CD") { try? NSWorkspace.shared.unmountAndEjectDevice(at: disc) }.disabled(ripping)
                Text(progress.status[volume] ?? status).font(.system(size: 10)).foregroundColor(theme.windowText).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .task(id: disc) {
            cd = AudioCD(volume: disc)
            status = cd == nil ? "Not an audio CD" : "Looking up MusicBrainz..."
            if cd != nil, let found = await AudioCD.named(volume: disc) {
                cd = found
                status = found.album.isEmpty ? "Disc not found on MusicBrainz" : ""
            }
        }
    }

    private func play(_ items: [MediaLibraryItem], enqueue: Bool) {
        guard let cd else { return }
        LibraryActions.playCD(cd, tracks: items.map { TrackItem(url: $0.url, title: $0.title, artist: $0.artist, duration: $0.length) }, enqueue: enqueue)
    }
}

// MARK: - Internet Radio

struct RadioPage: View {
    @State private var stations: [RadioStation] = []
    @State private var genres: [String] = []
    @State private var search = ""
    @State private var genre = ""
    @State private var bandwidth = RadioDirectory.Bandwidth.any
    @State private var selection = Set<String>()
    @State private var status = ""

    var body: some View {
        let theme = GenexTheme.current
        let picked = stations.filter { selection.contains($0.id) }
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                SearchBar(text: $search).onSubmit { refresh() }
                Text("Bandwidth:").font(.system(size: 11)).foregroundColor(theme.windowText)
                Win32ComboBox(selection: $bandwidth, options: RadioDirectory.Bandwidth.allCases.map { ($0, $0.rawValue) }, width: 90)
                Text("Genre:").font(.system(size: 11)).foregroundColor(theme.windowText)
                Win32ComboBox(selection: $genre, options: [("", "")] + genres.map { ($0, $0) }, width: 110)
            }
            MediaListView(rows: stations, columns: [("Name", 200, .leading, { $0.name }), ("Genre", 90, .leading, { $0.genre }),
                                                     ("Now playing", 110, .leading, { _ in "" }),
                                                     ("Listeners", 60, .trailing, { String($0.clickcount) }),
                                                     ("Bitrate (kbps)", 80, .trailing, { $0.bitrate > 0 ? String($0.bitrate) : "" })],
                          selection: $selection, autosave: "InternetRadio", url: { $0.streamURL }) { rows, shift in
                LibraryActions.playStations(rows, enqueue: PersistenceManager.shared.state.libraryDoubleClickEnqueues != shift)
            }
            HStack(spacing: 3) {
                GenexButton("Play", width: 46) { LibraryActions.playStations(picked, enqueue: false) }.disabled(picked.isEmpty)
                GenexButton("Enqueue", width: 56) { LibraryActions.playStations(picked, enqueue: true) }.disabled(picked.isEmpty)
                GenexButton("Refresh", width: 56) { refresh() }
                Text(status).font(.system(size: 10)).foregroundColor(theme.windowText).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .onAppear { if stations.isEmpty { refresh(force: false) } }
        .onChange(of: genre) { _, _ in refresh(force: false) }
        .onChange(of: bandwidth) { _, _ in refresh(force: false) }
    }

    /// The cached list while it's fresh (Library prefs ▸ Internet Radio ▸ refresh frequency); Refresh always fetches
    private func refresh(force: Bool = true) {
        let state = PersistenceManager.shared.state
        let limit = state.libraryMaxStreams
        if !force, let cached = RadioDirectory.cachedStations(search: search, genre: genre, bandwidth: bandwidth, limit: limit,
                                                              maxAgeHours: state.radioRefreshHours) {
            stations = cached
            status = "\(stations.count) stations (radio-browser.info)"
            if genres.isEmpty { Task { @MainActor in genres = (try? await RadioDirectory.genres()) ?? [] } }
            return
        }
        status = "Loading stations..."
        Task { @MainActor in
            do {
                if genres.isEmpty { genres = try await RadioDirectory.genres() }
                stations = try await RadioDirectory.stations(search: search, genre: genre, bandwidth: bandwidth, limit: limit)
                RadioDirectory.cache(stations, search: search, genre: genre, bandwidth: bandwidth, limit: limit)
                status = "\(stations.count) stations (radio-browser.info)"
            } catch {
                // Offline: an old list is better than none
                if let old = RadioDirectory.cachedStations(search: search, genre: genre, bandwidth: bandwidth, limit: limit, maxAgeHours: 0) {
                    stations = old
                }
                status = "[Error] \(error.localizedDescription)"
            }
        }
    }
}

/// gen_ml's draggable divider between two panes (skinneddivider.cpp): a thin gap with the resize cursor
struct PaneDivider: View {
    /// true: between a left and a right pane
    let vertical: Bool
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    @State private var last: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: vertical ? 4 : nil, height: vertical ? nil : 4)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let moved = vertical ? value.translation.width : value.translation.height
                    onDrag(moved - last)
                    last = moved
                }
                .onEnded { _ in
                    last = 0
                    onEnd()
                })
    }
}

