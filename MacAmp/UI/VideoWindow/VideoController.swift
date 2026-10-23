import Cocoa
import AVFoundation
import VideoToolbox

/// Winamp's Video window (⌥V; Winamp video.cpp / draw_vw.cpp). The audio engine plays the file's sound as for any
/// track, so the EQ, visualizer, seek bar, time and volume work as usual; this window shows the picture with a muted
/// AVPlayer that follows the engine's clock.
@MainActor
final class VideoController: NSObject {
    nonisolated static let extensions: Set<String> = ["mp4", "m4v", "mov"]
    nonisolated static func isVideo(_ url: URL) -> Bool { url.isFileURL && extensions.contains(url.pathExtension.lowercased()) }

    let window: WinampWindow
    let frameView: MediaWindowFrameView
    private let surface = VideoSurfaceView()
    let player = AVPlayer()
    private(set) var currentURL: URL?
    private(set) var naturalSize: CGSize?
    private var syncTimer: Timer?
    private var openedAutomatically = false
    private var fullscreen: (window: NSWindow, activity: NSObjectProtocol?)?
    private var state: AppState { PersistenceManager.shared.state }
    private var coordinator: PlayerCoordinator { .shared }

    /// Video options: what the zoom buttons and keys set (Winamp: 1 Normal, ` Half, 2 Double)
    enum Zoom: CGFloat { case half = 0.5, normal = 1, double = 2 }

    /// macOS has VP9 (YouTube) and, on newer Macs, AV1 decoders, but AVFoundation uses them only for apps that ask
    nonisolated static let systemDecodersRegistered: Void = {
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_AV1)
    }()

    init(rect: NSRect) {
        _ = VideoController.systemDecodersRegistered
        window = WinampWindow(windowID: .video, contentRect: rect)
        frameView = MediaWindowFrameView(sheet: "VIDEO", content: surface)
        super.init()
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        surface.player = player
        surface.onDoubleClick = { [weak self] in self?.toggleFullscreen() }
        window.contentView = frameView
        frameView.onClose = { [weak self] in self?.close() }
        frameView.onResized = { [weak self] _ in self?.coordinator.saveAuxFrame(self?.window, "video") }
        frameView.onButton = { [weak self] index in self?.button(index) }
        applyOptions()
    }

    func applyOptions() {
        surface.keepsAspect = state.videoKeepAspect
    }

    // MARK: Following the player

    /// A track finished loading: show its picture, or let go of the last video.
    func trackLoaded(_ url: URL) {
        guard VideoController.isVideo(url) else { return clear(closeIfAuto: true) }
        Task { @MainActor in
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return clear(closeIfAuto: true) }
            let name = url.deletingPathExtension().lastPathComponent
            // The sound plays through the engine either way; say so when macOS can't draw the picture
            guard (try? await track.load(.isPlayable)) == true else {
                clear(closeIfAuto: false)
                let codec = (try? await track.load(.formatDescriptions))?.first.map { VideoController.fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "?"
                frameView.info = "\(name): macOS can't decode this picture (\(codec))"
                if !window.isVisible, state.videoAutoOpen { openedAutomatically = true; show() }
                return
            }
            let (size, transform) = (try? await track.load(.naturalSize, .preferredTransform)) ?? (.zero, .identity)
            let shown = size.applying(transform)
            naturalSize = CGSize(width: abs(shown.width), height: abs(shown.height))
            currentURL = url
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            frameView.info = "\(name) (\(Int(naturalSize!.width))x\(Int(naturalSize!.height)))"
            if !window.isVisible, state.videoAutoOpen {
                openedAutomatically = true
                show()
            }
            if state.videoAutoResize { setZoom(.normal) }
            startSync()
        }
    }

    /// "avc1", "vp09", "hvc1"...
    nonisolated static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "?"
    }

    /// Playback stopped: Winamp leaves fullscreen (if set) and closes the window it opened by itself.
    func playbackStopped() {
        player.pause()
        if state.videoRemoveFullscreenOnStop { exitFullscreen() }
        if state.videoAutoClose, openedAutomatically, fullscreen == nil { hide() }
    }

    private func clear(closeIfAuto: Bool) {
        syncTimer?.invalidate()
        syncTimer = nil
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        naturalSize = nil
        frameView.info = ""
        if closeIfAuto, state.videoAutoClose, openedAutomatically, fullscreen == nil { hide() }
    }

    private func startSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
    }

    /// The picture follows the engine: same state, and a seek when they drift apart (after a seek bar drag, say)
    func sync() {
        let engine = coordinator.audioEngine
        guard currentURL != nil, engine.currentMetadata?.url.withoutPlaybackRange == currentURL else { return }
        let target = engine.currentTime
        let drift = abs(player.currentTime().seconds - target)
        switch engine.status {
        case .playing:
            if drift > 0.2 { player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
            if player.rate == 0 { player.rate = 1 }
        case .paused:
            if player.rate != 0 { player.pause() }
            if drift > 0.05 { player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        case .stopped:
            if player.rate != 0 { player.pause() }
        }
    }

    // MARK: Window

    func show() {
        window.level = state.isAlwaysOnTop ? .floating : .normal
        window.makeKeyAndOrderFront(nil)
        coordinator.saveAuxFrame(window, "video")
        coordinator.updateActivityState()
    }

    func hide() {
        coordinator.saveAuxFrame(window, "video")
        window.orderOut(nil)
        openedAutomatically = false
        coordinator.updateActivityState()
    }

    /// Close box: Video options "Stop playback on video window close"
    func close() {
        hide()
        if state.videoStopOnClose, currentURL != nil, coordinator.audioEngine.status != .stopped { coordinator.handleStop() }
    }

    func toggle() { window.isVisible ? close() : show() }

    /// Window size for the video at a zoom, frame included; never below Winamp's 275 × 116
    static func windowSize(video: CGSize, zoom: Zoom, insets: NSEdgeInsets) -> NSSize {
        NSSize(width: max(GenWindowFrameView.minimumSize.width, (video.width * zoom.rawValue).rounded() + insets.left + insets.right),
               height: max(GenWindowFrameView.minimumSize.height, (video.height * zoom.rawValue).rounded() + insets.top + insets.bottom))
    }

    func setZoom(_ zoom: Zoom) {
        guard let naturalSize, fullscreen == nil else { return }
        var size = VideoController.windowSize(video: naturalSize, zoom: zoom, insets: frameView.frameInsets)
        if let screen = (window.screen ?? NSScreen.main)?.visibleFrame {
            size = NSSize(width: min(size.width, screen.width), height: min(size.height, screen.height))
        }
        let top = window.frame.maxY
        window.setFrame(NSRect(x: window.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
        coordinator.saveAuxFrame(window, "video")
    }

    // MARK: Buttons, menu, keys

    private func button(_ index: Int) {
        switch index {
        case 0: toggleFullscreen()
        case 1: setZoom(.normal)
        case 2: setZoom(.double)
        case 3: // the "TV" button opens the Library on its Video view
            let videos = MediaLibrary.shared.views.first { $0.query.replacingOccurrences(of: " ", with: "") == "type=1" }
            if state.libraryTVButtonOpensVideo {
                coordinator.showLibraryWindow(at: videos.map { .view($0.id) } ?? .localMedia)
            } else {
                coordinator.showLibraryWindow()
            }
        default: frameView.popUp(menu(), button: 4)
        }
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ key: String = "", _ mods: NSEvent.ModifierFlags = [], _ action: @escaping () -> Void) {
            let item = Win32ClosureMenuItem(title: title, handler: action)
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = mods
            menu.addItem(item)
        }
        add("Fullscreen", "\r", [.option]) { [weak self] in self?.toggleFullscreen() }
        menu.addItem(.separator())
        add("Normal size", "1") { [weak self] in self?.setZoom(.normal) }
        add("Half size", "`") { [weak self] in self?.setZoom(.half) }
        add("Double size", "2") { [weak self] in self?.setZoom(.double) }
        menu.addItem(.separator())
        add("Video options...") { PreferencesWindow.show(treeItem: .video) }
        menu.addItem(.separator())
        let main = NSMenuItem(title: "MacAmp", action: nil, keyEquivalent: "")
        main.submenu = coordinator.buildWinampMenu()
        menu.addItem(main)
        return menu
    }

    /// Keys while the video window (or its fullscreen) has the focus
    func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (mods, event.keyCode, event.charactersIgnoringModifiers ?? "") {
        case ([.option], 36, _), ([.option], 76, _): toggleFullscreen()
        case ([], 53, _) where fullscreen != nil: exitFullscreen()
        case ([], _, "1"): setZoom(.normal)
        case ([], _, "`"): setZoom(.half)
        case ([], _, "2"): setZoom(.double)
        default: return false
        }
        return true
    }

    // MARK: Fullscreen

    var isFullscreen: Bool { fullscreen != nil }

    func toggleFullscreen() { fullscreen == nil ? enterFullscreen() : exitFullscreen() }

    private func enterFullscreen() {
        guard fullscreen == nil, let screen = window.screen ?? NSScreen.main else { return }
        let full = FullscreenVideoWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        let view = VideoSurfaceView()
        view.player = player
        view.keepsAspect = state.videoKeepAspect
        view.onDoubleClick = { [weak self] in self?.exitFullscreen() }
        full.contentView = view
        full.backgroundColor = .black
        full.level = .statusBar
        full.onKey = { [weak self] event in self?.handleKey(event) == true || PlayerCoordinator.shared.handleKeyDown(event) }
        full.setFrame(screen.frame, display: true)
        full.makeKeyAndOrderFront(nil)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        // Video options: "Disable screensaver when in fullscreen mode"
        let activity = state.videoDisableScreensaver
            ? ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Fullscreen video") : nil
        fullscreen = (full, activity)
    }

    func exitFullscreen() {
        guard let (full, activity) = fullscreen else { return }
        fullscreen = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        NSApp.presentationOptions = []
        full.orderOut(nil)
        if window.isVisible { window.makeKeyAndOrderFront(nil) }
    }
}

/// The picture: an AVPlayerLayer on black. Right-click opens the main menu, as in Winamp; double-click toggles fullscreen.
final class VideoSurfaceView: NSView {
    private let playerLayer = AVPlayerLayer()
    var onDoubleClick: (() -> Void)?
    var player: AVPlayer? { get { playerLayer.player } set { playerLayer.player = newValue } }
    var keepsAspect = true { didSet { playerLayer.videoGravity = keepsAspect ? .resizeAspect : .resize } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { PlayerCoordinator.shared.buildWinampMenu() }
}

/// Borderless fullscreen window that takes keys (Esc and ⌥Enter leave it; the rest are MacAmp's keys)
final class FullscreenVideoWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}
