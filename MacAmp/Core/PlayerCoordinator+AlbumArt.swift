import Cocoa

/// Album Art, a General Purpose plug-in (off by default, like the 2.x Album Art plug-ins): the playing track's cover in a
/// GEN.BMP frame that docks like the other windows. Frame kept in windowPositions["albumArt"]. Not on the clutterbar's
/// "I", which is File Info in 2.95.
extension PlayerCoordinator {
    static let albumArtFrameKey = "albumArt"
    /// The window's title and its item in the Winamp main menu and the menu bar's Window menu
    static let albumArtTitle = "Album Art"

    @objc public func handleToggleAlbumArt() {
        if isWindowOnScreen(albumArtWindow) { hideAlbumArtWindow() } else { showAlbumArtWindow() }
    }

    func showAlbumArtWindow() {
        guard persistence.state.albumArtEnabled else { return }
        let window = albumArtWindow ?? makeAlbumArtWindow()
        albumArtWindow = window
        window.level = persistence.state.isAlwaysOnTop ? .floating : .normal
        window.makeKeyAndOrderFront(nil)
        persistence.state.isAlbumArtVisible = true
        persistence.scheduleSave()
        refreshAlbumArt()
    }

    func hideAlbumArtWindow() {
        saveAuxFrame(albumArtWindow, Self.albumArtFrameKey)
        albumArtWindow?.orderOut(nil)
        persistence.state.isAlbumArtVisible = false
        persistence.scheduleSave()
    }

    /// Plug-in switched off in Preferences: the window goes and the menu item with it
    func setAlbumArtEnabled(_ enabled: Bool) {
        if !enabled, albumArtWindow?.isVisible == true { hideAlbumArtWindow() }
        persistence.state.albumArtEnabled = enabled
        persistence.scheduleSave()
    }

    /// After a track loads: the new cover, read off the main thread; nothing while the window is closed
    func refreshAlbumArt() {
        guard let window = albumArtWindow, window.isVisible, let view = albumArtView else { return }
        guard let url = playlist.currentTrack?.url else { view.image = nil; return }
        Task { @MainActor in
            let data = await AlbumArt.imageData(for: url)
            guard playlist.currentTrack?.url == url else { return } // another track started meanwhile
            view.image = data.flatMap(NSImage.init(data:))
        }
    }

    private var albumArtView: AlbumArtView? {
        (albumArtWindow?.contentView as? GenWindowFrameView)?.subviews.compactMap { $0 as? AlbumArtView }.first
    }

    /// Winamp's column width; this height leaves the picture about square inside the frame
    static let albumArtHeight: CGFloat = 290

    private func makeAlbumArtWindow() -> WinampWindow {
        let rect = auxWindowRect(Self.albumArtFrameKey, size: GenWindowFrameView.snappedSize(NSSize(width: AppConstants.Window.width, height: Self.albumArtHeight)))
        let window = WinampWindow(windowID: .albumArt, contentRect: rect)
        let frame = GenWindowFrameView(title: Self.albumArtTitle, content: AlbumArtView())
        frame.onClose = { [weak self] in self?.hideAlbumArtWindow() }
        frame.onResized = { [weak self] _ in self?.saveAuxFrame(self?.albumArtWindow, Self.albumArtFrameKey) }
        window.contentView = frame
        window.updateContentScale(windowManager.scale(for: .albumArt))
        return window
    }
}

/// Where a track's cover comes from, in this order: the picture in the file's tags, an image file in its folder
/// (folder.jpg, cover.jpg...), and for a Subsonic track the downloaded file or the server's cover
enum AlbumArt {
    static let folderNames = ["folder", "cover", "front", "album", "albumart", "albumartsmall"]
    static let imageExtensions = ["jpg", "jpeg", "png"]

    /// The picture's bytes (an NSImage is made from them on the main thread)
    static func imageData(for url: URL) async -> Data? {
        if Subsonic.isTrack(url) {
            if let file = Subsonic.cacheFile(for: url), FileManager.default.fileExists(atPath: file.path), let art = await embedded(file) { return art }
            return (try? await Subsonic.coverArt(for: url)) ?? nil
        }
        guard url.isFileURL else { return nil } // radio
        let file = url.withoutPlaybackRange
        if let art = await embedded(file) { return art }
        return folderImage(in: file.deletingLastPathComponent())
    }

    static func embedded(_ file: URL) async -> Data? {
        guard let data = await AudioMetadataService.shared.readMetadata(from: file).artwork?.imageData, !data.isEmpty else { return nil }
        return data
    }

    static func folderImage(in folder: URL) -> Data? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let byName = Dictionary(files.map { ($0.lastPathComponent.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        for name in folderNames {
            for ext in imageExtensions {
                if let file = byName["\(name).\(ext)"], let data = try? Data(contentsOf: file) { return data }
            }
        }
        return nil
    }
}

/// The cover fitted into the window on the skin's list background (GENEX), or "No album art"
final class AlbumArtView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let theme = GenexTheme.current
        theme.ns(.itemBackground).setFill()
        bounds.fill()
        guard let image, image.size.width > 0, image.size.height > 0 else {
            let text = NSAttributedString(string: "No album art", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.ns(.itemForeground)])
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
            return
        }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
    }
}
