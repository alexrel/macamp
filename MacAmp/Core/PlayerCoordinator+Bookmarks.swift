import Cocoa

extension PlayerCoordinator {
    // MARK: - Bookmarks (Winamp 2.6+)

    /// Winamp's Bookmarks submenu: add / edit, then the bookmarks themselves.
    public func buildBookmarksMenu() -> NSMenu {
        let menu = NSMenu(title: "Bookmarks")
        fillBookmarksMenu(menu)
        return menu
    }

    func fillBookmarksMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let add = NSMenuItem(title: "Add current as bookmark", action: #selector(handleAddBookmark), keyEquivalent: "i")
        add.keyEquivalentModifierMask = [.option]
        add.target = self
        add.isEnabled = playlist.currentTrack != nil
        menu.addItem(add)
        let edit = NSMenuItem(title: "Edit bookmarks...", action: #selector(handleEditBookmarks), keyEquivalent: "i")
        edit.keyEquivalentModifierMask = [.control, .option]
        edit.target = self
        menu.addItem(edit)
        menu.addItem(NSMenuItem.separator())

        let bookmarks = BookmarkStore.shared.items
        if bookmarks.isEmpty {
            let empty = NSMenuItem(title: "(no bookmarks)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for bookmark in bookmarks {
            let item = NSMenuItem(title: bookmark.title, action: #selector(handleBookmarkSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bookmark.id
            item.toolTip = bookmark.url.isFileURL ? bookmark.url.path : bookmark.url.absoluteString
            menu.addItem(item)
        }
    }

    @objc func handleAddBookmark() {
        guard let track = playlist.currentTrack else { return }
        BookmarkStore.shared.add([track])
        mainView.marquee.showTemporaryMessage("Bookmarked: \(track.displayName)")
    }

    @objc func handleEditBookmarks() {
        PreferencesWindow.show(treeItem: .bookmarks)
    }

    @objc func handleBookmarkSelected(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let bookmark = BookmarkStore.shared.items.first(where: { $0.id == id }) else { return }
        openBookmarks([bookmark], enqueue: false)
    }

    /// Bookmarks ▸ Open plays them (like opening files from Finder); Enqueue adds them to the playlist.
    public func openBookmarks(_ bookmarks: [Bookmark], enqueue: Bool) {
        Task { @MainActor in
            let files = bookmarks.filter(\.url.isFileURL)
            var tracks = await collectTracks(fromPaths: files.map(\.url.path))
            // Streams have nothing to read; keep the bookmark's title
            tracks += bookmarks.filter { !$0.url.isFileURL }.map { TrackItem.entry(url: $0.url, title: $0.title) }
            guard !tracks.isEmpty else {
                mainView.marquee.showTemporaryMessage("Bookmark not found")
                return
            }
            addOpenedTracks(tracks, fromPaths: [], enqueue: enqueue)
        }
    }
}
