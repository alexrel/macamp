import Cocoa
import Foundation

public class PlaylistWindowView: WinampControlView {
    public let playlist: PlaylistModel
    
    // Titlebar buttons
    public private(set) var closeButton: SkinButton!
    public private(set) var shadeButton: SkinButton!
    
    // Bottom toolbar buttons
    public private(set) var addButton: SkinButton!
    public private(set) var remButton: SkinButton!
    public private(set) var selButton: SkinButton!
    public private(set) var miscButton: SkinButton!
    public private(set) var listButton: SkinButton!
    
    // Scroll state
    private var scrollOffset: Int = 0
    
    public var isShadeMode: Bool = false {
        didSet {
            updateLayoutForShadeMode()
            needsDisplay = true
        }
    }
    
    public var onToggleShade: (() -> Void)?
    public var onClose: (() -> Void)?
    public var onPlayTrack: ((TrackItem) -> Void)?
    public var onAddFiles: (() -> Void)?
    
    public init(playlist: PlaylistModel) {
        self.playlist = playlist
        super.init(frame: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.height))
        setupControls()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupControls() {
        // 1. TitleBar buttons (Close at right: 2, Shade at right: 12)
        closeButton = SkinButton(normal: SpriteCatalog.plCloseNormal, pressed: SpriteCatalog.plCloseNormal) { [weak self] in
            self?.onClose?()
        }
        addSubview(closeButton)
        
        shadeButton = SkinButton(normal: SpriteCatalog.plShadeNormal, pressed: SpriteCatalog.plShadeNormal) { [weak self] in
            self?.onToggleShade?()
        }
        addSubview(shadeButton)
        
        // 2. Bottom Toolbar Buttons
        addButton = SkinButton(normal: SpriteCatalog.plAddFile, pressed: SpriteCatalog.plAddFile) { [weak self] in
            self?.showAddMenu()
        }
        addSubview(addButton)
        
        remButton = SkinButton(normal: SpriteCatalog.plRemoveSel, pressed: SpriteCatalog.plRemoveSel) { [weak self] in
            self?.showRemMenu()
        }
        addSubview(remButton)
        
        selButton = SkinButton(normal: SpriteCatalog.plSelectAll, pressed: SpriteCatalog.plSelectAll) { [weak self] in
            self?.showSelMenu()
        }
        addSubview(selButton)
        
        miscButton = SkinButton(normal: SpriteCatalog.plMiscOptions, pressed: SpriteCatalog.plMiscOptions) { [weak self] in
            self?.showMiscMenu()
        }
        addSubview(miscButton)
        
        listButton = SkinButton(normal: SpriteCatalog.plLoadList, pressed: SpriteCatalog.plLoadList) { [weak self] in
            self?.showListMenu()
        }
        addSubview(listButton)
        
        layoutButtons()
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutButtons()
    }
    
    private func layoutButtons() {
        closeButton.frame = NSRect(x: bounds.width - 11, y: 3, width: 9, height: 9)
        shadeButton.frame = NSRect(x: bounds.width - 21, y: 3, width: 9, height: 9)
        
        let bottomY = bounds.height - 30
        addButton.frame = NSRect(x: 14, y: bottomY, width: 22, height: 18)
        remButton.frame = NSRect(x: 43, y: bottomY, width: 22, height: 18)
        selButton.frame = NSRect(x: 72, y: bottomY, width: 22, height: 18)
        miscButton.frame = NSRect(x: 101, y: bottomY, width: 22, height: 18)
        listButton.frame = NSRect(x: bounds.width - 44, y: bottomY, width: 22, height: 18)
    }
    
    private func updateLayoutForShadeMode() {
        let isFull = !isShadeMode
        addButton.isHidden = !isFull
        remButton.isHidden = !isFull
        selButton.isHidden = !isFull
        miscButton.isHidden = !isFull
        listButton.isHidden = !isFull
    }
    
    // MARK: - Menus
    private func showAddMenu() {
        let menu = NSMenu(title: "Add")
        menu.addItem(NSMenuItem(title: "Add File...", action: #selector(handleAddFile), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Add Directory...", action: #selector(handleAddDirectory), keyEquivalent: ""))
        popup(menu: menu, below: addButton)
    }
    
    private func showRemMenu() {
        let menu = NSMenu(title: "Remove")
        menu.addItem(NSMenuItem(title: "Remove Selected", action: #selector(handleRemoveSelected), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Crop (Keep Selected)", action: #selector(handleCrop), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear All", action: #selector(handleClearAll), keyEquivalent: ""))
        popup(menu: menu, below: remButton)
    }
    
    private func showSelMenu() {
        let menu = NSMenu(title: "Select")
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(handleSelectAll), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "Select None", action: #selector(handleSelectNone), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Invert Selection", action: #selector(handleInvertSelection), keyEquivalent: ""))
        popup(menu: menu, below: selButton)
    }
    
    private func showMiscMenu() {
        let menu = NSMenu(title: "Misc")
        menu.addItem(NSMenuItem(title: "Sort by Title", action: #selector(handleSortTitle), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Sort by Filename", action: #selector(handleSortFilename), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reverse List", action: #selector(handleReverse), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Randomize List", action: #selector(handleRandomize), keyEquivalent: ""))
        popup(menu: menu, below: miscButton)
    }
    
    private func showListMenu() {
        let menu = NSMenu(title: "List")
        menu.addItem(NSMenuItem(title: "New List", action: #selector(handleClearAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Save List (M3U)...", action: #selector(handleSaveList), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Load List (M3U)...", action: #selector(handleLoadList), keyEquivalent: "o"))
        popup(menu: menu, below: listButton)
    }
    
    private func popup(menu: NSMenu, below button: NSView) {
        let point = convert(NSPoint(x: button.frame.minX, y: button.frame.maxY), to: nil)
        if let window {
            let screenPoint = window.convertToScreen(NSRect(origin: point, size: .zero)).origin
            menu.popUp(positioning: nil, at: screenPoint, in: nil)
        }
    }
    
    // MARK: - Menu Actions
    @objc private func handleAddFile() {
        onAddFiles?()
    }
    @objc private func handleAddDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let dirURL = panel.url {
            let extensions = ["mp3", "flac", "wav", "aiff", "m4a", "aac", "alac", "ogg"]
            if let enumerator = FileManager.default.enumerator(at: dirURL, includingPropertiesForKeys: nil) {
                var newTracks: [TrackItem] = []
                for case let fileURL as URL in enumerator {
                    if extensions.contains(fileURL.pathExtension.lowercased()) {
                        newTracks.append(TrackItem(url: fileURL, title: fileURL.deletingPathExtension().lastPathComponent))
                    }
                }
                playlist.add(tracks: newTracks)
                needsDisplay = true
            }
        }
    }
    @objc private func handleRemoveSelected() {
        playlist.removeSelected()
        needsDisplay = true
    }
    @objc private func handleCrop() {
        playlist.crop()
        needsDisplay = true
    }
    @objc private func handleClearAll() {
        playlist.clear()
        needsDisplay = true
    }
    @objc private func handleSelectAll() {
        playlist.selectAll()
        needsDisplay = true
    }
    @objc private func handleSelectNone() {
        playlist.selectNone()
        needsDisplay = true
    }
    @objc private func handleInvertSelection() {
        playlist.invertSelection()
        needsDisplay = true
    }
    @objc private func handleSortTitle() {
        playlist.sortByTitle()
        needsDisplay = true
    }
    @objc private func handleSortFilename() {
        playlist.sortByFilename()
        needsDisplay = true
    }
    @objc private func handleReverse() {
        playlist.reverse()
        needsDisplay = true
    }
    @objc private func handleRandomize() {
        playlist.randomize()
        needsDisplay = true
    }
    @objc private func handleSaveList() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!]
        if panel.runModal() == .OK, let url = panel.url {
            try? PlaylistIO.saveM3U(tracks: playlist.tracks, to: url)
        }
    }
    @objc private func handleLoadList() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!, .init(filenameExtension: "pls")!]
        if panel.runModal() == .OK, let url = panel.url {
            let loaded = PlaylistIO.loadPlaylist(from: url)
            playlist.clear()
            playlist.add(tracks: loaded)
            needsDisplay = true
        }
    }
    
    // MARK: - Drawing Tracks & Frame
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        let isKey = window?.isKeyWindow ?? true
        
        if isShadeMode {
            // Shade background
            if let img = SkinManager.shared.image(for: SpriteCatalog.mainShadeBg) {
                context.draw(img, in: bounds)
            }
            return
        }
        
        // 1. Draw Top Bar (height: 20)
        let topH: CGFloat = 20
        let leftSlice = isKey ? SpriteCatalog.plTopLeftSel : SpriteCatalog.plTopLeft
        let titleSlice = isKey ? SpriteCatalog.plTopTitleSel : SpriteCatalog.plTopTitle
        let tileSlice = isKey ? SpriteCatalog.plTopTileSel : SpriteCatalog.plTopTile
        let rightSlice = isKey ? SpriteCatalog.plTopRightSel : SpriteCatalog.plTopRight
        
        if let leftImg = SkinManager.shared.image(for: leftSlice) {
            context.draw(leftImg, in: NSRect(x: 0, y: 0, width: 25, height: topH))
        }
        if let titleImg = SkinManager.shared.image(for: titleSlice) {
            context.draw(titleImg, in: NSRect(x: 25, y: 0, width: 100, height: topH))
        }
        if let tileImg = SkinManager.shared.image(for: tileSlice) {
            let tileWidth = bounds.width - 150
            if tileWidth > 0 {
                context.draw(tileImg, in: NSRect(x: 125, y: 0, width: tileWidth, height: topH))
            }
        }
        if let rightImg = SkinManager.shared.image(for: rightSlice) {
            context.draw(rightImg, in: NSRect(x: bounds.width - 25, y: 0, width: 25, height: topH))
        }
        
        // 2. Draw Bottom Bar (height: 38)
        let botH: CGFloat = 38
        let botY = bounds.height - botH
        if let bLeft = SkinManager.shared.image(for: SpriteCatalog.plBottomLeft) {
            context.draw(bLeft, in: NSRect(x: 0, y: botY, width: 125, height: botH))
        }
        if let bTile = SkinManager.shared.image(for: SpriteCatalog.plBottomTile) {
            let fillW = bounds.width - 275
            if fillW > 0 {
                context.draw(bTile, in: NSRect(x: 125, y: botY, width: fillW, height: botH))
            }
        }
        if let bRight = SkinManager.shared.image(for: SpriteCatalog.plBottomRight) {
            context.draw(bRight, in: NSRect(x: bounds.width - 150, y: botY, width: 150, height: botH))
        }
        
        // 3. Draw Track List Area
        let listRect = NSRect(x: 12, y: topH, width: bounds.width - 32, height: bounds.height - topH - botH)
        let style = SkinManager.shared.currentSkin?.playlistStyle ?? PlaylistStyle()
        
        // Black background
        context.setFillColor(style.normalBGColor.cgColor)
        context.fill(listRect)
        
        // Draw track rows (13px each)
        let rowH = AppConstants.Playlist.trackRowHeight
        let visibleRows = Int(listRect.height / rowH)
        let font = NSFont(name: style.fontName, size: 9) ?? NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        
        for i in 0..<visibleRows {
            let trackIndex = scrollOffset + i
            guard trackIndex < playlist.tracks.count else { break }
            let track = playlist.tracks[trackIndex]
            
            let rowY = listRect.minY + CGFloat(i) * rowH
            let rowRect = NSRect(x: listRect.minX, y: rowY, width: listRect.width, height: rowH)
            
            let isSelected = playlist.selectedIndices.contains(trackIndex)
            let isCurrent = (playlist.currentIndex == trackIndex)
            
            // Draw selection background
            if isSelected {
                context.setFillColor(style.selectedBGColor.cgColor)
                context.fill(rowRect)
            }
            
            // Text color: current = white, normal = green
            let textColor = isCurrent ? style.currentColor : style.normalColor
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
            
            // Title on left
            let titleStr = track.formattedTitle(with: trackIndex + 1)
            let textRect = NSRect(x: rowRect.minX + 2, y: rowRect.minY + 1, width: rowRect.width - 45, height: rowH - 1)
            (titleStr as NSString).draw(in: textRect, withAttributes: attrs)
            
            // Duration on right
            let durStr = track.formattedDuration
            let durRect = NSRect(x: rowRect.maxX - 40, y: rowRect.minY + 1, width: 38, height: rowH - 1)
            let durAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: {
                    let p = NSMutableParagraphStyle()
                    p.alignment = .right
                    return p
                }()
            ]
            (durStr as NSString).draw(in: durRect, withAttributes: durAttrs)
        }
        
        // 4. Draw Total Duration in bottom bar (right: 70, y: botY + 10)
        let totalTimeStr = playlist.formattedTotalDuration
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.normalColor
        ]
        (totalTimeStr as NSString).draw(at: NSPoint(x: bounds.width - 145, y: botY + 10), withAttributes: timeAttrs)
    }
    
    // MARK: - Mouse Interaction
    public override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        
        // Titlebar double-click
        if event.clickCount == 2 && local.y <= 20 {
            onToggleShade?()
            return
        }
        
        // Titlebar drag
        if local.y <= 20 {
            guard let win = self.window as? WinampWindow else { return }
            win.startWindowDrag(with: event)
            trackWindowDrag(with: event, in: win)
            return
        }
        
        // Track click
        let topH: CGFloat = 20
        let botH: CGFloat = 38
        let listRect = NSRect(x: 12, y: topH, width: bounds.width - 32, height: bounds.height - topH - botH)
        if listRect.contains(local) {
            let rowH = AppConstants.Playlist.trackRowHeight
            let clickedRow = Int((local.y - topH) / rowH)
            let trackIndex = scrollOffset + clickedRow
            if trackIndex < playlist.tracks.count {
                if event.clickCount == 2 {
                    // Play track
                    playlist.currentIndex = trackIndex
                    onPlayTrack?(playlist.tracks[trackIndex])
                } else {
                    // Select track
                    if event.modifierFlags.contains(.shift) {
                        playlist.selectedIndices.insert(trackIndex)
                    } else if event.modifierFlags.contains(.command) {
                        if playlist.selectedIndices.contains(trackIndex) {
                            playlist.selectedIndices.remove(trackIndex)
                        } else {
                            playlist.selectedIndices.insert(trackIndex)
                        }
                    } else {
                        playlist.selectedIndices = [trackIndex]
                    }
                }
                needsDisplay = true
            }
        }
    }
    
    public override func scrollWheel(with event: NSEvent) {
        if event.deltaY > 0 {
            scrollOffset = max(0, scrollOffset - 1)
        } else if event.deltaY < 0 {
            let maxOffset = max(0, playlist.tracks.count - 4)
            scrollOffset = min(maxOffset, scrollOffset + 1)
        }
        needsDisplay = true
    }
    
    private func trackWindowDrag(with initialEvent: NSEvent, in win: WinampWindow) {
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            switch nextEvent.type {
            case .leftMouseDragged:
                win.continueWindowDrag(with: nextEvent)
            case .leftMouseUp:
                keepTracking = false
                win.endWindowDrag(with: nextEvent)
            default:
                break
            }
        }
    }
}
