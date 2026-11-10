import Cocoa
import SwiftUI

/// Winamp 2.95 Media Library window (⌥L): a GEN.BMP frame around the library page; frame kept in windowPositions["library"].
extension PlayerCoordinator {
    @objc public func handleToggleLibrary() {
        if libraryWindow?.isVisible == true {
            hideLibraryWindow()
        } else {
            showLibraryWindow()
        }
    }

    /// Main window lightning bolt: "Open library on main window lightning bolt click", else the About box
    func handleLightningBolt() {
        if persistence.state.libraryOnLightningBolt { showLibraryWindow() } else { handleAbout() }
    }

    /// Shows the Library on one of its pages
    func showLibraryWindow(at node: LibraryNode) {
        LibraryNavigation.shared.node = node
        showLibraryWindow()
    }

    public func showLibraryWindow() {
        let window = libraryWindow ?? makeLibraryWindow()
        libraryWindow = window
        window.level = persistence.state.isAlwaysOnTop ? .floating : .normal
        window.makeKeyAndOrderFront(nil)
        persistence.state.isLibraryVisible = true
        saveLibraryFrame()
        updateActivityState()
    }

    public func hideLibraryWindow() {
        saveLibraryFrame()
        libraryWindow?.orderOut(nil)
        persistence.state.isLibraryVisible = false
        persistence.scheduleSave()
        updateActivityState()
    }

    func saveLibraryFrame() { saveAuxFrame(libraryWindow, "library") }

    /// A windowPositions entry, the same for every window: [left, top − height, width, height] with the size in skin
    /// pixels, so it survives a change of scale. At 100% that is the plain frame older sessions saved.
    func savedFrame(of window: NSWindow) -> [Double]? {
        guard let size = window.contentView?.bounds.size else { return nil }
        return [window.frame.minX, window.frame.maxY - size.height, size.width, size.height].map(Double.init)
    }

    /// Frame of the Library / Video / Minibrowser windows, kept in windowPositions[key]
    func saveAuxFrame(_ window: NSWindow?, _ key: String) {
        guard let window, let entry = savedFrame(of: window) else { return }
        persistence.state.windowPositions[key] = entry
        persistence.scheduleSave()
    }

    /// The saved frame if it's still on a screen, else `size` beside the main window (where Winamp opens them)
    func auxWindowRect(_ key: String, size: NSSize) -> NSRect {
        if let saved = persistence.state.windowPositions[key], saved.count >= 4 {
            let size = WindowLayoutManager.scaled(NSSize(width: saved[2], height: saved[3]))
            let frame = NSRect(x: saved[0], y: saved[1] + saved[3] - size.height, width: size.width, height: size.height)
            if windowManager.isRectVisibleOnAnyScreen(frame) { return frame }
        }
        let main = mainWindow?.frame ?? NSRect(x: 100, y: 400, width: 275, height: 116)
        let (width, height) = (WindowLayoutManager.scaled(size).width, WindowLayoutManager.scaled(size).height)
        var origin = NSPoint(x: main.maxX, y: main.maxY - height)
        if let visible = (mainWindow?.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = max(visible.minX, min(origin.x, visible.maxX - width))
            origin.y = min(visible.maxY - height, max(origin.y, visible.minY))
        }
        return NSRect(x: origin.x, y: origin.y, width: width, height: height)
    }

    private func makeLibraryWindow() -> WinampWindow {
        // Winamp opens the library beside the main window, about 500 × 348
        let rect = auxWindowRect("library", size: GenWindowFrameView.snappedSize(NSSize(width: 500, height: 348)))
        let window = WinampWindow(windowID: .library, contentRect: rect)
        let frame = GenWindowFrameView(title: "MacAmp Library", content: ScaledHostingContent(MediaLibraryView(), insideScaledFrame: true))
        frame.onClose = { [weak self] in self?.hideLibraryWindow() }
        frame.onResized = { [weak self] _ in self?.saveLibraryFrame() }
        window.contentView = frame
        window.updateContentScale(windowManager.scale(for: .library))
        return window
    }
}
