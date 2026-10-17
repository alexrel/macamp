import Cocoa
import WebKit

public class MinibrowserWindowView: NSView, WKNavigationDelegate, NSTextFieldDelegate {
    
    // MARK: - Constants
    private enum Layout {
        static let topBarHeight: CGFloat = 14.0
        static let navBarHeight: CGFloat = 24.0
        static let bottomBorderHeight: CGFloat = 8.0
        static let leftBorderWidth: CGFloat = 8.0
        static let rightBorderWidth: CGFloat = 8.0
        static let resizeGripSize: CGFloat = 18.0
        static let shadeHeight: CGFloat = 14.0
    }
    
    // MARK: - UI Components
    public private(set) var closeButton: SkinButton!
    public private(set) var shadeButton: SkinButton!
    
    private var navBarView: NSView!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var stopButton: NSButton!
    private var homeButton: NSButton!
    private var urlField: NSTextField!
    
    public private(set) var webView: WKWebView!
    
    public var isShadeMode: Bool = false {
        didSet {
            updateLayoutForShadeMode()
            layoutSubviews()
            needsDisplay = true
        }
    }
    
    public var onToggleShade: (() -> Void)?
    public var onClose: (() -> Void)?
    
    // MARK: - Initializer
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupComponents()
        layoutSubviews()
        loadDefaultHome()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var isFlipped: Bool { true }
    
    // MARK: - Setup
    private func setupComponents() {
        wantsLayer = true
        
        // 1. Title bar buttons
        closeButton = SkinButton(normal: nil, pressed: SpriteCatalog.plClosePressed) { [weak self] in
            self?.onClose?()
        }
        addSubview(closeButton)
        
        shadeButton = SkinButton(normal: nil, pressed: SpriteCatalog.plShadePressed) { [weak self] in
            self?.onToggleShade?()
        }
        addSubview(shadeButton)
        
        // 2. Navigation Bar
        navBarView = NSView()
        navBarView.wantsLayer = true
        navBarView.layer?.backgroundColor = Win32Colors.dialogBg.cgColor
        addSubview(navBarView)
        
        let makeNavBtn: (String, Selector) -> NSButton = { title, action in
            let btn = NSButton(title: title, target: self, action: action)
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            btn.isBordered = true
            btn.focusRingType = .none
            return btn
        }
        
        backButton = makeNavBtn("◀", #selector(handleBack))
        navBarView.addSubview(backButton)
        
        forwardButton = makeNavBtn("▶", #selector(handleForward))
        navBarView.addSubview(forwardButton)
        
        reloadButton = makeNavBtn("⟳", #selector(handleReload))
        navBarView.addSubview(reloadButton)
        
        stopButton = makeNavBtn("✕", #selector(handleStop))
        navBarView.addSubview(stopButton)
        
        homeButton = makeNavBtn("⌂", #selector(handleHome))
        navBarView.addSubview(homeButton)
        
        // URL text field
        urlField = NSTextField()
        urlField.font = NSFont.systemFont(ofSize: 11)
        urlField.focusRingType = .none
        urlField.placeholderString = "Enter URL or search..."
        urlField.target = self
        urlField.action = #selector(handleURLEnter)
        urlField.delegate = self
        navBarView.addSubview(urlField)
        
        // 3. WebKit View
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.wantsLayer = true
        addSubview(webView)
    }
    
    public func layoutSubviews() {
        let w = bounds.width
        let h = bounds.height
        
        // Title buttons
        closeButton.frame = NSRect(x: w - 11, y: 3, width: 9, height: 9)
        shadeButton.frame = NSRect(x: w - 20, y: 3, width: 9, height: 9)
        
        if isShadeMode {
            navBarView.isHidden = true
            webView.isHidden = true
            return
        }
        
        navBarView.isHidden = false
        webView.isHidden = false
        
        // Nav Bar layout
        let topBarH = Layout.topBarHeight
        let navH = Layout.navBarHeight
        navBarView.frame = NSRect(x: Layout.leftBorderWidth, y: topBarH, width: w - (Layout.leftBorderWidth + Layout.rightBorderWidth), height: navH)
        
        let btnW: CGFloat = 22
        let btnH: CGFloat = 18
        let btnY: CGFloat = 3
        
        backButton.frame = NSRect(x: 2, y: btnY, width: btnW, height: btnH)
        forwardButton.frame = NSRect(x: 26, y: btnY, width: btnW, height: btnH)
        reloadButton.frame = NSRect(x: 50, y: btnY, width: btnW, height: btnH)
        stopButton.frame = NSRect(x: 74, y: btnY, width: btnW, height: btnH)
        homeButton.frame = NSRect(x: 98, y: btnY, width: btnW, height: btnH)
        
        let urlX: CGFloat = 124
        let urlW = max(50, navBarView.bounds.width - urlX - 4)
        urlField.frame = NSRect(x: urlX, y: btnY, width: urlW, height: btnH)
        
        // Web View layout
        let webY = topBarH + navH
        let webH = max(20, h - webY - Layout.bottomBorderHeight)
        webView.frame = NSRect(x: Layout.leftBorderWidth, y: webY, width: w - (Layout.leftBorderWidth + Layout.rightBorderWidth), height: webH)
    }
    
    private func updateLayoutForShadeMode() {
        guard let win = self.window as? WinampWindow else { return }
        let currentFrame = win.frame
        let targetH = isShadeMode ? Layout.shadeHeight : CGFloat(PersistenceManager.shared.state.minibrowserWindowSize[1])
        let newY = currentFrame.maxY - targetH
        let newFrame = NSRect(x: currentFrame.minX, y: newY, width: currentFrame.width, height: targetH)
        win.setFrame(newFrame, display: true, animate: false)
        self.frame = NSRect(x: 0, y: 0, width: currentFrame.width, height: targetH)
        layoutSubviews()
        WindowLayoutManager.shared.updateAdjacencies()
    }
    
    // MARK: - Navigation Actions
    @objc private func handleBack() {
        if webView.canGoBack { webView.goBack() }
    }
    
    @objc private func handleForward() {
        if webView.canGoForward { webView.goForward() }
    }
    
    @objc private func handleReload() {
        webView.reload()
    }
    
    @objc private func handleStop() {
        webView.stopLoading()
    }
    
    @objc private func handleHome() {
        loadDefaultHome()
    }
    
    @objc private func handleURLEnter() {
        var str = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return }
        if !str.lowercased().hasPrefix("http://") && !str.lowercased().hasPrefix("https://") {
            str = "https://" + str
        }
        if let url = URL(string: str) {
            webView.load(URLRequest(url: url))
        }
    }
    
    public func loadURL(_ url: URL) {
        urlField.stringValue = url.absoluteString
        webView.load(URLRequest(url: url))
    }
    
    private func loadDefaultHome() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          body {
            background-color: #1a1a1a;
            color: #d4d0c8;
            font-family: -apple-system, Monaco, "Courier New", sans-serif;
            margin: 0;
            padding: 14px;
            font-size: 11px;
          }
          h1 {
            font-size: 14px;
            color: #ffcc00;
            margin-top: 0;
            margin-bottom: 6px;
            display: flex;
            align-items: center;
            gap: 6px;
          }
          p {
            color: #a0a0a0;
            margin-bottom: 12px;
            line-height: 1.4;
          }
          .card {
            background: #282828;
            border: 1px solid #3c3c3c;
            border-radius: 4px;
            padding: 8px 10px;
            margin-bottom: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
          }
          .card strong {
            color: #ffffff;
            font-size: 12px;
          }
          .card span {
            color: #888888;
            font-size: 10px;
            margin-left: 6px;
          }
          .play-btn {
            background: #0a246a;
            color: #ffffff;
            text-decoration: none;
            padding: 4px 10px;
            border-radius: 3px;
            font-weight: bold;
            font-size: 10px;
            border: 1px solid #316ac5;
            transition: background 0.15s ease;
          }
          .play-btn:hover {
            background: #316ac5;
          }
          .hint {
            font-size: 10px;
            color: #666666;
            margin-top: 14px;
            text-align: center;
          }
        </style>
        </head>
        <body>
          <h1>⚡ Winamp Minibrowser</h1>
          <p>Select an online radio stream below or enter any web address above to browse music and media.</p>
          
          <div class="card">
            <div><strong>SomaFM: Groove Salad</strong><span>Downtempo / Ambient</span></div>
            <a class="play-btn" href="http://ice1.somafm.com/groovesalad-128-mp3">▶ Stream</a>
          </div>
          
          <div class="card">
            <div><strong>SomaFM: Secret Agent</strong><span>Spy / Surf / Lounge</span></div>
            <a class="play-btn" href="http://ice1.somafm.com/secretagent-128-mp3">▶ Stream</a>
          </div>
          
          <div class="card">
            <div><strong>SomaFM: Drone Zone</strong><span>Atmospheric Ambient</span></div>
            <a class="play-btn" href="http://ice1.somafm.com/dronezone-128-mp3">▶ Stream</a>
          </div>
          
          <div class="card">
            <div><strong>Radio Paradise</strong><span>Eclectic Rock & Pop</span></div>
            <a class="play-btn" href="http://stream.radioparadise.com/rock-128">▶ Stream</a>
          </div>
          
          <div class="hint">Click any stream link to instantly play it through MacAmp Audio Engine</div>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        urlField.stringValue = "winamp://minibrowser/home"
    }
    
    // MARK: - WKNavigationDelegate (Stream Interception)
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let pathExt = url.pathExtension.lowercased()
            let isAudioStream = AppConstants.Audio.supportedExtensions.contains(pathExt) ||
                                AppConstants.Audio.playlistExtensions.contains(pathExt) ||
                                url.absoluteString.contains("somafm.com") ||
                                url.absoluteString.contains("stream.radioparadise.com")
            
            if isAudioStream {
                decisionHandler(.cancel)
                let item = TrackItem.create(from: url)
                PlayerCoordinator.shared.playlist.add(track: item)
                PlayerCoordinator.shared.loadAndPlay(track: item)
                PlayerCoordinator.shared.mainView?.marquee.showTemporaryMessage("STREAMING: \(item.title)")
                return
            }
        }
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let currentURL = webView.url, currentURL.absoluteString != "about:blank" {
            urlField.stringValue = currentURL.absoluteString
        }
    }
    
    // MARK: - Drawing (Winamp Skinned Frame)
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let w = bounds.width
        let h = bounds.height
        let skin = SkinManager.shared
        let isKey = window?.isKeyWindow ?? false
        
        // 1. Draw Title Bar
        if isShadeMode {
            let leftSlice = SpriteCatalog.plShadeLeft
            let midSlice = SpriteCatalog.plShadeMiddle
            let rightSlice = isKey ? SpriteCatalog.plShadeRightSel : SpriteCatalog.plShadeRight
            
            if let leftImg = skin.image(for: leftSlice) {
                context.drawSkinImage(leftImg, in: NSRect(x: 0, y: 0, width: 25, height: Layout.shadeHeight))
            }
            if let midImg = skin.image(for: midSlice) {
                context.drawTiledHorizontal(image: midImg, from: 25, to: w - 50, y: 0, width: 25, height: Layout.shadeHeight)
            }
            if let rightImg = skin.image(for: rightSlice) {
                context.drawSkinImage(rightImg, in: NSRect(x: w - 50, y: 0, width: 50, height: Layout.shadeHeight))
            }
            
            BitmapFont.draw(string: "WINAMP MINIBROWSER", in: context, at: CGPoint(x: 5, y: 4))
            return
        }
        
        let topH = Layout.topBarHeight
        let leftSlice = isKey ? SpriteCatalog.plTopLeftSel : SpriteCatalog.plTopLeft
        let tileSlice = isKey ? SpriteCatalog.plTopTileSel : SpriteCatalog.plTopTile
        let rightSlice = isKey ? SpriteCatalog.plTopRightSel : SpriteCatalog.plTopRight
        
        if let leftImg = skin.image(for: leftSlice) {
            context.drawSkinImage(leftImg, in: NSRect(x: 0, y: 0, width: 25, height: topH))
        }
        if let tileImg = skin.image(for: tileSlice) {
            context.drawTiledHorizontal(image: tileImg, from: 25, to: w - 25, y: 0, width: 25, height: topH)
        }
        if let rightImg = skin.image(for: rightSlice) {
            context.drawSkinImage(rightImg, in: NSRect(x: w - 25, y: 0, width: 25, height: topH))
        }
        
        // Title Text
        BitmapFont.draw(string: "WINAMP MINIBROWSER", in: context, at: CGPoint(x: 28, y: 3))
        
        // 2. Left and Right Borders
        let sideH = h - topH - Layout.bottomBorderHeight
        if let leftSlice = skin.image(for: SpriteCatalog.plLeftTile) {
            context.drawTiledVertical(image: leftSlice, x: 0, from: topH, to: topH + sideH, width: Layout.leftBorderWidth, height: 29)
        }
        if let rightSlice = skin.image(for: SpriteCatalog.plRightTile) {
            context.drawTiledVertical(image: rightSlice, x: w - Layout.rightBorderWidth, from: topH, to: topH + sideH, width: Layout.rightBorderWidth, height: 29)
        }
        
        // 3. Bottom Border
        let botY = h - Layout.bottomBorderHeight
        if let botSlice = skin.image(for: SpriteCatalog.plBottomLeft) {
            context.drawSkinImage(botSlice, in: NSRect(x: 0, y: botY, width: min(w, 125), height: Layout.bottomBorderHeight))
        }
        if w > 125, let botTile = skin.image(for: SpriteCatalog.plBottomTile) {
            context.drawTiledHorizontal(image: botTile, from: 125, to: w - 20, y: botY, width: 25, height: Layout.bottomBorderHeight)
        }
        if let botRight = skin.image(for: SpriteCatalog.plBottomRight) {
            context.drawSkinImage(botRight, in: NSRect(x: w - 20, y: botY, width: 20, height: Layout.bottomBorderHeight))
        }
    }
    
    // MARK: - Mouse & Drag Handling
    public override func resetCursorRects() {
        super.resetCursorRects()
        let gripSize = Layout.resizeGripSize
        let resizeRect = NSRect(x: bounds.width - gripSize, y: bounds.height - gripSize, width: gripSize, height: gripSize)
        addCursorRect(resizeRect, cursor: .resizeUpDown)
    }
    
    public override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let gripSize = Layout.resizeGripSize
        let topH = Layout.topBarHeight
        
        // 1. Check resize grip
        if !isShadeMode {
            let resizeRect = NSRect(x: bounds.width - gripSize, y: bounds.height - gripSize, width: gripSize, height: gripSize)
            if resizeRect.contains(local) {
                guard let win = self.window as? WinampWindow else { return }
                startResizeDrag(with: event, in: win)
                return
            }
        }
        
        // 2. Titlebar double click (toggle shade)
        if event.clickCount == 2 && local.y <= topH {
            onToggleShade?()
            return
        }
        
        // 3. Titlebar drag (move window)
        if local.y <= topH {
            guard let win = self.window as? WinampWindow else { return }
            win.startWindowDrag(with: event)
            trackWindowDrag(with: event, in: win)
            return
        }
    }
    
    private func trackWindowDrag(with initialEvent: NSEvent, in win: WinampWindow) {
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            switch nextEvent.type {
            case .leftMouseDragged:
                win.continueWindowDrag(with: nextEvent)
            case .leftMouseUp:
                win.endWindowDrag(with: nextEvent)
                keepTracking = false
            default:
                break
            }
        }
    }
    
    /// Grid-snapped resizing loop (25px horizontally, 29px vertically)
    private func startResizeDrag(with initialEvent: NSEvent, in win: WinampWindow) {
        let initialMouse = NSEvent.mouseLocation
        let initialFrame = win.frame
        
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            switch nextEvent.type {
            case .leftMouseDragged:
                let currentMouse = NSEvent.mouseLocation
                let deltaX = currentMouse.x - initialMouse.x
                let deltaY = initialMouse.y - currentMouse.y
                
                let stepsX = round(deltaX / AppConstants.Window.resizeStepX)
                let baseWidth = max(AppConstants.Window.width, round(initialFrame.width))
                let newWidth = max(AppConstants.Window.width, baseWidth + stepsX * AppConstants.Window.resizeStepX)
                
                let stepsY = round(deltaY / AppConstants.Window.resizeStepY)
                let baseHeight = max(AppConstants.Window.height, round(initialFrame.height))
                let newHeight = max(AppConstants.Window.height, baseHeight + stepsY * AppConstants.Window.resizeStepY)
                
                let newMinX = round(initialFrame.minX)
                let newMaxY = round(initialFrame.maxY)
                let newMinY = round(newMaxY - newHeight)
                
                let newFrame = NSRect(x: newMinX, y: newMinY, width: newWidth, height: newHeight)
                if newFrame != win.frame {
                    win.setFrame(newFrame, display: true, animate: false)
                    self.frame = NSRect(x: 0, y: 0, width: newWidth, height: newHeight)
                    self.layoutSubviews()
                    self.needsDisplay = true
                }
                
            case .leftMouseUp:
                keepTracking = false
                WindowLayoutManager.shared.updateAdjacencies()
                PersistenceManager.shared.state.minibrowserWindowSize = [Double(round(win.frame.width)), Double(round(win.frame.height))]
                PersistenceManager.shared.saveSession()
                
            default:
                break
            }
        }
    }
}
