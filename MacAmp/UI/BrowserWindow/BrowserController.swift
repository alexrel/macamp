import Cocoa
import WebKit

/// Winamp's Minibrowser (⌥T): a small web window in MB.BMP. Buttons: Back, Forward, Stop, Reload and a menu
/// (Update Links ⌃⌥R, Open Internet Location... ⌃O). Nullsoft's start page and its "dynamic links" are gone,
/// so the start page is local, with links to what lives on. Links to audio files and playlists play in MacAmp.
@MainActor
final class BrowserController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let window: BrowserWindow
    let frameView: MediaWindowFrameView
    let webView: WKWebView
    private var coordinator: PlayerCoordinator { .shared }

    init(rect: NSRect) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent() // no cookies or history kept between runs, as befits a side window
        // The start page has an address of its own, so Back and Forward reach it like any page
        config.setURLSchemeHandler(StartPageScheme(), forURLScheme: BrowserController.startURL.scheme!)
        // Sound a page starts (a radio site's play button) goes to the player instead, with its EQ and visualization
        config.userContentController.addUserScript(WKUserScript(source: BrowserController.mediaScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView = WKWebView(frame: .zero, configuration: config)
        window = BrowserWindow(windowID: .browser, contentRect: rect)
        frameView = MediaWindowFrameView(sheet: "MB", content: webView)
        super.init()
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(WeakScriptHandler(self), name: "macampPlay")
        webView.customUserAgent = nil
        window.contentView = frameView
        window.updateContentScale(WindowLayoutManager.shared.scale(for: .browser))
        window.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        frameView.onClose = { [weak self] in self?.hide() }
        frameView.onResized = { [weak self] _ in self?.coordinator.saveAuxFrame(self?.window, "browser") }
        frameView.onButton = { [weak self] index in self?.button(index) }
        loadStartPage()
    }

    func show() {
        window.level = PersistenceManager.shared.state.isAlwaysOnTop ? .floating : .normal
        window.makeKeyAndOrderFront(nil)
        PersistenceManager.shared.state.isBrowserVisible = true
        coordinator.saveAuxFrame(window, "browser")
        coordinator.updateActivityState()
    }

    func hide() {
        coordinator.saveAuxFrame(window, "browser")
        window.orderOut(nil)
        PersistenceManager.shared.state.isBrowserVisible = false
        coordinator.updateActivityState()
    }

    func toggle() { window.isVisible ? hide() : show() }

    /// Opens an address in the minibrowser (Open Internet Location, links from elsewhere in MacAmp)
    func open(_ url: URL) {
        show()
        webView.load(URLRequest(url: url))
    }

    func loadStartPage() {
        webView.load(URLRequest(url: BrowserController.startURL))
        frameView.info = "MacAmp Minibrowser"
    }

    // MARK: Buttons, menu, keys

    private func button(_ index: Int) {
        switch index {
        case 0: webView.goBack()
        case 1: webView.goForward()
        case 2: webView.stopLoading()
        case 3: webView.reload()
        default: frameView.popUp(menu(), button: 4)
        }
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        let update = Win32ClosureMenuItem(title: "Update Links") { [weak self] in self?.loadStartPage() }
        update.keyEquivalent = "r"
        update.keyEquivalentModifierMask = [.control, .option]
        let open = Win32ClosureMenuItem(title: "Open Internet Location...") { [weak self] in self?.promptLocation() }
        open.keyEquivalent = "o"
        open.keyEquivalentModifierMask = [.control]
        menu.addItem(update)
        menu.addItem(open)
        return menu
    }

    func promptLocation() {
        guard let text = Win32Dialog.prompt(title: "Open Internet Location", message: "Address:",
                                            defaultValue: webView.url?.absoluteString ?? "https://", width: 420)?
            .trimmingCharacters(in: .whitespaces), !text.isEmpty else { return }
        if let url = BrowserController.address(from: text) { open(url) }
    }

    /// What the user typed as a URL: "example.com" gets https://
    static func address(from text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let url = URL(string: t), let scheme = url.scheme, ["http", "https", "file"].contains(scheme.lowercased()) { return url }
        return URL(string: "https://" + t)
    }

    /// Minibrowser keys (2.95): ⌥← Back, ⌥→ Forward, ⌃R Reload, ⌃⌥R Update Links, ⌃O Open Internet Location
    func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (mods, event.keyCode, event.hotkeyCharacters?.lowercased() ?? "") {
        case ([.option], 123, _), ([.option, .function], 123, _): webView.goBack()
        case ([.option], 124, _), ([.option, .function], 124, _): webView.goForward()
        case ([.control], _, "r"): webView.reload()
        case ([.control, .option], _, "r"): loadStartPage()
        case ([.control], _, "o"): promptLocation()
        default: return false
        }
        return true
    }

    // MARK: WKNavigationDelegate

    /// Audio files and playlists play in MacAmp (Winamp's minibrowser did the same); the rest stays in the browser
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // macamp://radio: the Library's Internet Radio page
        if action.request.url == BrowserController.radioURL {
            decisionHandler(.cancel)
            return coordinator.showLibraryWindow(at: .internetRadio)
        }
        guard let url = action.request.url, BrowserController.isMedia(url) else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        onMedia(url)
    }

    static let radioURL = URL(string: "macamp://radio")!

    /// Stops any <audio>/<video> a page plays from an http(s) address and hands the address to MacAmp.
    /// Streams a page assembles itself (blob:, YouTube) can't play outside it and stay in the page.
    static let mediaScript = """
    document.addEventListener('play', function (e) {
        var m = e.target, src = m.src || m.currentSrc; // src: the address set now; currentSrc lags until it loads
        if (!/^https?:/i.test(src)) return;
        m.pause();
        window.webkit.messageHandlers.macampPlay.postMessage({ src: src, title: document.title });
    }, true);
    """

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let src = body["src"] as? String, let url = URL(string: src),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        frameView.info = "Playing in MacAmp: " + src
        onMedia(url)
    }

    /// Where page sound and media links go: the player (replaceable in tests)
    var onMedia: (URL) -> Void = { url in BrowserController.play(url) }

    static func play(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if AppConstants.Audio.playlistExtensions.contains(ext) {
            Task { @MainActor in
                guard let (data, _) = try? await MacAmpNetwork.session.data(from: url) else { return }
                LibraryActions.play(PlaylistIO.parse(data: data, ext: ext, baseURL: url.deletingLastPathComponent()), enqueue: false)
            }
        } else {
            LibraryActions.play([TrackItem.entry(url: url)], enqueue: false)
        }
    }

    static func isMedia(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        let ext = url.pathExtension.lowercased()
        return AppConstants.Audio.supportedExtensions.contains(ext) || AppConstants.Audio.playlistExtensions.contains(ext)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        frameView.info = "Loading " + (webView.url?.absoluteString ?? "") + "..."
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        frameView.info = webView.url.map { $0 == BrowserController.startURL ? "MacAmp Minibrowser" : $0.absoluteString } ?? ""
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError(error) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError(error) }

    private func showError(_ error: Error) {
        if BrowserController.isInterruption(error) {
            // Another click or Stop replaced the load, or MacAmp took the link to play it: show where we are
            frameView.info = webView.url.map { $0 == BrowserController.startURL ? "MacAmp Minibrowser" : $0.absoluteString } ?? ""
        } else {
            frameView.info = "[Error] " + error.localizedDescription
        }
    }

    /// Cancelled loads (NSURLErrorCancelled -999) and WebKit's "frame load interrupted" (102) are not failures
    static func isInterruption(_ error: Error) -> Bool {
        let e = error as NSError
        return (e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled) || (e.domain == "WebKitErrorDomain" && e.code == 102)
    }

    static let startURL = URL(string: "macamp://start")!

    /// The 2.95 start page's look (maroon bar, four link boxes), with links that still work
    static let startPage = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    body { margin: 0; font: 13px Verdana, Arial, sans-serif; background: #fff; color: #000; }
    .bar { background: #800000; color: #ffd700; font: bold 22px Arial Black, Arial, sans-serif; padding: 4px 8px; border-bottom: 3px solid #ffd700; }
    p.welcome { margin: 10px 12px; font-size: 14px; }
    .links { margin: 0 12px; border: 1px solid #bbb; padding: 4px 10px; }
    .links a { font: bold 18px Verdana, Arial, sans-serif; color: #00f; }
    .links div { font-size: 11px; margin: 0 0 8px 0; }
    .foot { text-align: center; font-size: 11px; margin: 8px; }
    </style></head><body>
    <div class="bar">MACAMP</div>
    <p class="welcome">Welcome to the Minibrowser, connect to the internet and check out the cool links below.</p>
    <div class="links">
    <a href="https://alexrel.com/macamp">MacAmp</a><div>Updates, the FFmpeg plug-in and what's new.</div>
    <a href="macamp://radio">Internet Radio</a><div>Tens of thousands of free stations in the Library (radio-browser.info), playing right in MacAmp.</div>
    <a href="https://skins.webamp.org/">Free Skins</a><div>Give MacAmp a new look: the Winamp Skin Museum, every classic skin ever made.</div>
    <a href="https://winampheritage.com/">Winamp Heritage</a><div>Skins, plug-ins and visualizations from the Winamp community archive.</div>
    <a href="https://freemusicarchive.org/">Grab Some Music</a><div>Free, legal music to download and play.</div>
    </div>
    <div class="foot">MacAmp &mdash; based on Winamp 2.95 by Nullsoft</div>
    </body></html>
    """
}

/// The minibrowser's window: its keys come before the web view's, which takes every key otherwise
final class BrowserWindow: WinampWindow {
    var onKey: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Serves macamp://start, the Minibrowser's start page
final class StartPageScheme: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let data = Data(BrowserController.startPage.utf8)
        task.didReceive(URLResponse(url: task.request.url ?? BrowserController.startURL, mimeType: "text/html",
                                    expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// WKUserContentController keeps its handlers strongly; this breaks the cycle with the controller
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
