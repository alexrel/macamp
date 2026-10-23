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

    /// Frame of the Library / Video / Minibrowser windows, kept in windowPositions[key]
    func saveAuxFrame(_ window: NSWindow?, _ key: String) {
        guard let frame = window?.frame else { return }
        persistence.state.windowPositions[key] = [frame.minX, frame.minY, frame.width, frame.height].map { Double(round($0)) }
        persistence.scheduleSave()
    }

    /// The saved frame if it's still on a screen, else `size` beside the main window (where Winamp opens them)
    func auxWindowRect(_ key: String, size: NSSize) -> NSRect {
        if let saved = persistence.state.windowPositions[key], saved.count >= 4,
           windowManager.isRectVisibleOnAnyScreen(NSRect(x: saved[0], y: saved[1], width: saved[2], height: saved[3])) {
            return NSRect(x: saved[0], y: saved[1], width: saved[2], height: saved[3])
        }
        let main = mainWindow?.frame ?? NSRect(x: 100, y: 400, width: 275, height: 116)
        return NSRect(x: main.maxX, y: main.maxY - size.height, width: size.width, height: size.height)
    }

    private func makeLibraryWindow() -> WinampWindow {
        // Winamp opens the library beside the main window, about 500 × 348
        let rect = auxWindowRect("library", size: GenWindowFrameView.snappedSize(NSSize(width: 500, height: 348)))
        let window = WinampWindow(windowID: .library, contentRect: rect)
        let frame = GenWindowFrameView(title: "MacAmp Library", content: NSHostingView(rootView: MediaLibraryView()))
        frame.onClose = { [weak self] in self?.hideLibraryWindow() }
        frame.onResized = { [weak self] _ in self?.saveLibraryFrame() }
        window.contentView = frame
        return window
    }
}
