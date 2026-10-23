import Foundation

/// One entry of the Media Library, with Winamp's columns: Artist, Title, Album, Length, Track #, Genre, Year, Filename.
public struct MediaLibraryItem: Codable, Identifiable, Hashable {
    public var url: URL
    public var title: String
    public var artist: String = ""
    public var album: String = ""
    public var length: TimeInterval = 0
    public var trackNumber: Int = 0
    public var genre: String = ""
    public var year: String = ""
    public var comment: String = ""
    public var isVideo: Bool = false
    public var id: String { url.isFileURL ? url.standardizedFileURL.path : url.absoluteString }

    public var track: TrackItem { TrackItem(url: url, title: title, artist: artist, duration: length) }
}

/// A user view (Library ▸ Add new view): a query shown as a simple list or as an artist / album browser.
public struct LibraryView: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var query: String
    public var artistAlbumBrowser: Bool = false
}

/// A playlist kept in the library (Library ▸ Playlists).
public struct LibraryPlaylist: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var tracks: [TrackItem]
}

/// Winamp's Media Library database: the files of the folders you added, saved views and playlists.
/// Stored as JSON next to the session (Application Support/MacAmp/library.json); scanning runs in the background.
@MainActor
public final class MediaLibrary: ObservableObject {
    public static let shared = MediaLibrary(storeURL: PersistenceManager.shared.baseDir.appendingPathComponent("library.json"))

    @Published public private(set) var items: [MediaLibraryItem] = []
    @Published public private(set) var folders: [URL] = []
    @Published public var views: [LibraryView] = []
    @Published public var playlists: [LibraryPlaylist] = []
    @Published public private(set) var scanningFolder: URL?
    @Published public private(set) var scannedCount = 0

    private let storeURL: URL

    struct Store: Codable {
        var items: [MediaLibraryItem]
        var folders: [URL]
        var views: [LibraryView]
        var playlists: [LibraryPlaylist]
    }

    public init(storeURL: URL) {
        self.storeURL = storeURL
        if let data = try? Data(contentsOf: storeURL), let store = try? JSONDecoder().decode(Store.self, from: data) {
            items = store.items
            folders = store.folders
            views = store.views
            playlists = store.playlists
        }
        if views.isEmpty { views = MediaLibrary.defaultViews }
    }

    /// Local Media ▸ Audio / Video, as Winamp ships them.
    static let defaultViews = [
        LibraryView(name: "Audio", query: "type = 0", artistAlbumBrowser: true),
        LibraryView(name: "Video", query: "type = 1"),
    ]

    public func save() {
        let store = Store(items: items, folders: folders, views: views, playlists: playlists)
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: Folders and scanning

    /// Library ▸ Add directory to library: remembers the folder and adds its audio files.
    public func addDirectory(_ folder: URL) async {
        let folder = folder.standardizedFileURL
        if !folders.contains(folder) { folders.append(folder) }
        await scan(folder)
    }

    /// Re-reads every library folder: new files are added, tags of known files refreshed.
    public func rescan() async {
        for folder in folders { await scan(folder) }
    }

    private func scan(_ folder: URL) async {
        scanningFolder = folder
        scannedCount = 0
        let files = await Task.detached(priority: .utility) { MediaLibrary.audioFiles(in: folder) }.value
        let read = await MediaLibrary.readItems(files) { [weak self] done in
            Task { @MainActor in self?.scannedCount = done }
        }
        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in read { byID[item.id] = item }
        items = byID.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        scanningFolder = nil
        save()
    }

    nonisolated static func audioFiles(in folder: URL) -> [URL] {
        let all = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?.allObjects as? [URL] ?? []
        return all.filter { AppConstants.Audio.supportedExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// Tags and length of each file, a few files at a time.
    nonisolated static func readItems(_ files: [URL], progress: @escaping @Sendable (Int) -> Void) async -> [MediaLibraryItem] {
        await withTaskGroup(of: MediaLibraryItem?.self) { group in
            var results: [MediaLibraryItem] = []
            var next = 0
            let parallel = 4
            func add(_ url: URL) { group.addTask { await item(for: url) } }
            while next < min(parallel, files.count) { add(files[next]); next += 1 }
            while let result = await group.next() {
                if let result { results.append(result) }
                progress(results.count)
                if next < files.count { add(files[next]); next += 1 }
            }
            return results
        }
    }

    nonisolated static func item(for url: URL) async -> MediaLibraryItem? {
        let meta = await AudioMetadataService.shared.readMetadata(from: url)
        let v2 = meta.id3v2, v1 = meta.id3v1
        let fileName = url.deletingPathExtension().lastPathComponent
        func pick(_ a: String, _ b: String) -> String { !a.isEmpty ? a : (ID3v1Tag.isPlaceholder(b) ? "" : b) }
        var item = MediaLibraryItem(url: url, title: pick(v2.title, v1.title))
        if item.title.isEmpty || item.title == fileName { item.title = fileName }
        item.artist = pick(v2.artist, v1.artist)
        item.album = pick(v2.album, v1.album)
        item.genre = v2.genre.isEmpty && v1.genreIndex < ID3Genre.allGenres.count ? ID3Genre.name(for: v1.genreIndex) : v2.genre
        item.year = pick(v2.year, v1.year)
        item.comment = pick(v2.comment, v1.comment)
        item.trackNumber = Int(v2.trackNumber.split(separator: "/").first ?? "") ?? Int(v1.trackNumber)
        item.length = MIDIRenderer.isMIDI(url) ? MIDIRenderer.duration(of: url) : meta.techInfo.duration
        item.isVideo = VideoController.isVideo(url)
        return item
    }

    /// Library ▸ Compact library: forget files that no longer exist. Returns how many were removed.
    @discardableResult
    public func compact() -> Int {
        let before = items.count
        items.removeAll { $0.url.isFileURL && !FileManager.default.fileExists(atPath: $0.url.path) }
        save()
        return before - items.count
    }

    /// Adds tracks directly (dropped files, extracted CD tracks).
    public func add(_ newItems: [MediaLibraryItem]) {
        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in newItems { byID[item.id] = item }
        items = byID.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        save()
    }

    // MARK: Search and views

    /// The search box: every word must appear in artist, title, album, genre or file name.
    public static func filter(_ items: [MediaLibraryItem], search: String) -> [MediaLibraryItem] {
        let words = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let haystack = [item.artist, item.title, item.album, item.genre, item.url.lastPathComponent].joined(separator: " ").lowercased()
            return words.allSatisfy(haystack.contains)
        }
    }

    public func items(for view: LibraryView?) -> [MediaLibraryItem] {
        guard let view, let query = try? LibraryQuery.parse(view.query) else { return items }
        return items.filter(query.matches)
    }

    // MARK: Playlists

    /// Library ▸ Remove from library: forgets the items; the files stay on disk.
    public func remove(_ ids: Set<String>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    public func createPlaylist(named name: String, tracks: [TrackItem] = []) {
        playlists.append(LibraryPlaylist(name: name, tracks: tracks))
        save()
    }

    public func removePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }
}
