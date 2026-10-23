import Cocoa
import AVFoundation
import VideoToolbox

/// Winamp's Video window (⌥V; Winamp video.cpp / draw_vw.cpp). The audio engine plays the file's sound as for any
/// track, so the EQ, visualizer, seek bar, time and volume work as usual; this window shows the picture with a muted
/// AVPlayer that follows the engine's clock.
@MainActor
final class VideoController: NSObject, AVPlayerItemLegibleOutputPushDelegate {
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

    // Audio tracks and subtitles (▼ menu)
    private(set) var audioTracks: [VideoTracks.AudioTrack] = []
    private var chosenAudio: [URL: CMPersistentTrackID] = [:]
    private var reloadingAudio = false
    struct SubtitleChoice: Equatable {
        let title: String
        let language: String?
        let option: AVMediaSelectionOption?
        let file: URL?
    }
    private(set) var subtitleChoices: [SubtitleChoice] = []
    private(set) var currentSubtitle: SubtitleChoice?
    private var legibleGroup: AVMediaSelectionGroup?
    private var srtCues: [SubtitleCue] = []
    /// Embedded subtitles arrive as text and are drawn like .srt ones (the same look, in the window and fullscreen)
    private let legibleOutput = AVPlayerItemLegibleOutput()
    private(set) var subtitleText: String?

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
        legibleOutput.suppressesPlayerRendering = true
        legibleOutput.setDelegate(self, queue: .main)
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
            let item = AVPlayerItem(asset: asset)
            item.add(legibleOutput)
            player.replaceCurrentItem(with: item)
            frameView.info = "\(name) (\(Int(naturalSize!.width))x\(Int(naturalSize!.height)))"
            if !window.isVisible, state.videoAutoOpen {
                openedAutomatically = true
                show()
            }
            if state.videoAutoResize { setZoom(.normal) }
            startSync()
            await loadTracksAndSubtitles(asset, url)
        }
    }

    private func loadTracksAndSubtitles(_ asset: AVURLAsset, _ url: URL) async {
        audioTracks = await VideoTracks.audioTracks(of: url)
        legibleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
        let embedded = (legibleGroup?.options ?? []).filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }.map {
            SubtitleChoice(title: $0.displayName, language: $0.extendedLanguageTag ?? $0.locale?.language.languageCode?.identifier, option: $0, file: nil)
        }
        subtitleChoices = embedded + SRT.files(for: url).map { SubtitleChoice(title: $0.title, language: $0.language, option: nil, file: $0.url) }
        // Off unless a language was picked before: then the same language again
        let remembered = state.videoSubtitleLanguage.flatMap { lang in subtitleChoices.first { VideoController.sameLanguage($0.language, lang) } }
        selectSubtitle(remembered, remember: false)
    }

    /// "ru" matches "ru-RU" and "rus"
    nonisolated static func sameLanguage(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        let x = Locale.Language(identifier: a).languageCode?.identifier ?? a, y = Locale.Language(identifier: b).languageCode?.identifier ?? b
        return x.lowercased() == y.lowercased()
    }

    // MARK: Audio track and subtitles

    func selectAudio(_ track: VideoTracks.AudioTrack) {
        guard let url = currentURL, chosenAudio[url] ?? audioTracks.first?.id != track.id else { return }
        Task { @MainActor in
            if track.id == audioTracks.first?.id {
                VideoTracks.setOverride(nil, for: url)
            } else {
                frameView.info = "Preparing audio track..."
                do { VideoTracks.setOverride(try await VideoTracks.extract(track.id, from: url), for: url) } catch {
                    frameView.info = "[Error] Can't read this audio track: " + error.localizedDescription
                    return
                }
            }
            chosenAudio[url] = track.id
            await reloadAudio(url)
            frameView.info = "\(url.deletingPathExtension().lastPathComponent): \(track.title)"
        }
    }

    /// The engine plays the newly chosen track from where it was
    private func reloadAudio(_ url: URL) async {
        let engine = coordinator.audioEngine
        let time = engine.currentTime, status = engine.status
        reloadingAudio = true
        defer { reloadingAudio = false }
        guard (try? await engine.load(url: url)) != nil else { return }
        switch status {
        case .playing: engine.play(); engine.seek(to: time)
        case .paused: engine.preparePaused(at: time)
        case .stopped: break
        }
    }

    func chosenAudioID() -> CMPersistentTrackID? { currentURL.flatMap { chosenAudio[$0] } ?? audioTracks.first?.id }

    func selectSubtitle(_ choice: SubtitleChoice?, remember: Bool = true) {
        currentSubtitle = choice
        srtCues = choice?.file.map(SRT.load) ?? []
        if let group = legibleGroup { player.currentItem?.select(choice?.option, in: group) }
        setSubtitleText(nil)
        if remember {
            PersistenceManager.shared.state.videoSubtitleLanguage = choice?.language
            PersistenceManager.shared.scheduleSave()
        }
    }

    private func setSubtitleText(_ text: String?) {
        guard text != subtitleText else { return }
        subtitleText = text
        surface.subtitle = text
        (fullscreen?.window.contentView as? VideoSurfaceView)?.subtitle = text
    }

    nonisolated func legibleOutput(_ output: AVPlayerItemLegibleOutput, didOutputAttributedStrings strings: [NSAttributedString],
                                   nativeSampleBuffers: [Any], forItemTime itemTime: CMTime) {
        let text = strings.map(\.string).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        MainActor.assumeIsolated {
            guard currentSubtitle?.option != nil else { return }
            setSubtitleText(text.isEmpty ? nil : text)
        }
    }

    /// "avc1", "vp09", "hvc1"...
    nonisolated static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "?"
    }

    /// Playback stopped: Winamp leaves fullscreen (if set) and closes the window it opened by itself.
    func playbackStopped() {
        guard !reloadingAudio else { return } // switching audio tracks reloads the engine: not a stop
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
        audioTracks = []
        subtitleChoices = []
        currentSubtitle = nil
        srtCues = []
        setSubtitleText(nil)
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
        if !srtCues.isEmpty { setSubtitleText(SRT.text(at: target, in: srtCues)) }
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

    /// Window size for the video at a zoom, frame included, and the scale the picture really gets. A picture that
    /// doesn't fit `screen` is shrunk keeping its proportions; the window is never below Winamp's 275 × 116.
    static func windowSize(video: CGSize, zoom: Zoom, insets: NSEdgeInsets, screen: NSSize? = nil) -> (size: NSSize, scale: CGFloat) {
        var scale = zoom.rawValue
        if let screen, video.width > 0, video.height > 0 {
            let room = CGSize(width: screen.width - insets.left - insets.right, height: screen.height - insets.top - insets.bottom)
            scale = min(scale, room.width / video.width, room.height / video.height)
        }
        let size = NSSize(width: max(GenWindowFrameView.minimumSize.width, (video.width * scale).rounded() + insets.left + insets.right),
                          height: max(GenWindowFrameView.minimumSize.height, (video.height * scale).rounded() + insets.top + insets.bottom))
        return (size, scale)
    }

    func setZoom(_ zoom: Zoom) {
        guard let naturalSize, fullscreen == nil else { return }
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame
        let (size, scale) = VideoController.windowSize(video: naturalSize, zoom: zoom, insets: frameView.frameInsets, screen: screen?.size)
        var frame = NSRect(x: window.frame.minX, y: window.frame.maxY - size.height, width: size.width, height: size.height)
        if let screen { // keep it on the screen it's on
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        window.setFrame(frame, display: true)
        frameView.info = "\(currentURL?.deletingPathExtension().lastPathComponent ?? "") (\(Int(naturalSize.width))x\(Int(naturalSize.height)), \(Int((scale * 100).rounded()))%)"
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
        if audioTracks.count > 1 {
            let tracks = NSMenu()
            for track in audioTracks {
                let item = Win32ClosureMenuItem(title: track.title) { [weak self] in self?.selectAudio(track) }
                item.state = track.id == chosenAudioID() ? .on : .off
                tracks.addItem(item)
            }
            let item = NSMenuItem(title: "Audio track", action: nil, keyEquivalent: "")
            item.submenu = tracks
            menu.addItem(item)
        }
        if !subtitleChoices.isEmpty {
            let subs = NSMenu()
            let off = Win32ClosureMenuItem(title: "Off") { [weak self] in self?.selectSubtitle(nil) }
            off.state = currentSubtitle == nil ? .on : .off
            subs.addItem(off)
            for choice in subtitleChoices {
                let item = Win32ClosureMenuItem(title: choice.title) { [weak self] in self?.selectSubtitle(choice) }
                item.state = choice == currentSubtitle ? .on : .off
                subs.addItem(item)
            }
            let item = NSMenuItem(title: "Subtitles", action: nil, keyEquivalent: "")
            item.submenu = subs
            menu.addItem(item)
        }
        if audioTracks.count > 1 || !subtitleChoices.isEmpty { menu.addItem(.separator()) }
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
        view.subtitle = subtitleText
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
    private let subtitleLayer = CATextLayer()
    /// Subtitle text over the bottom of the picture (white with a black outline, as players draw them)
    var subtitle: String? { didSet { if subtitle != oldValue { needsLayout = true } } }
    var onDoubleClick: (() -> Void)?
    var player: AVPlayer? { get { playerLayer.player } set { playerLayer.player = newValue } }
    var keepsAspect = true { didSet { playerLayer.videoGravity = keepsAspect ? .resizeAspect : .resize } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        subtitleLayer.alignmentMode = .center
        subtitleLayer.isWrapped = true
        subtitleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        subtitleLayer.shadowColor = NSColor.black.cgColor
        subtitleLayer.shadowOpacity = 0.9
        subtitleLayer.shadowRadius = 2
        subtitleLayer.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(subtitleLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        let size = max(13, (bounds.height * 0.065).rounded())
        let text = subtitle ?? ""
        subtitleLayer.isHidden = text.isEmpty
        subtitleLayer.string = NSAttributedString(string: text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black, .strokeWidth: -4.0, // negative: fill and outline
        ])
        let width = bounds.width * 0.9
        let height = ceil((subtitleLayer.string as? NSAttributedString)?.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                                                    options: [.usesLineFragmentOrigin]).height ?? 0)
        // The layer tree isn't flipped: y 0 is the bottom edge
        subtitleLayer.frame = NSRect(x: (bounds.width - width) / 2, y: max(4, bounds.height * 0.04), width: width, height: height + 2)
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
