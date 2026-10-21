import Foundation

/// A Winamp bookmark: a file or stream with its display title (winamp.bm kept the same two fields).
public struct Bookmark: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var title: String
    public var url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

/// Bookmarks menu / Preferences ▸ Bookmarks, saved with the session.
@MainActor
public final class BookmarkStore: ObservableObject {
    public static let shared = BookmarkStore()

    @Published public private(set) var items: [Bookmark]
    private var persistence: PersistenceManager { PersistenceManager.shared }

    init() {
        items = PersistenceManager.shared.state.bookmarks
    }

    /// Winamp "Add current as bookmark" / "Bookmark item(s)"; a file already bookmarked isn't added twice.
    public func add(_ tracks: [TrackItem]) {
        for track in tracks where !items.contains(where: { $0.url == track.url }) {
            // Streams carry a placeholder artist ("Internet Stream"); the station name alone is the bookmark
            items.append(Bookmark(title: track.url.isFileURL ? track.displayName : track.title, url: track.url))
        }
        save()
    }

    public func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    public func update(_ bookmark: Bookmark) {
        guard let index = items.firstIndex(where: { $0.id == bookmark.id }) else { return }
        items[index] = bookmark
        save()
    }

    private func save() {
        persistence.state.bookmarks = items
        persistence.saveSession()
        MainMenuManager.shared.updateStates()
    }
}
