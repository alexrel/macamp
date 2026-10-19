import Cocoa
import Foundation

// MARK: - Skinned Popup Menu Component for Winamp Playlist
public struct SkinnedMenuItem {
    public let normalSlice: SpriteSlice
    public let selectedSlice: SpriteSlice
    public let action: () -> Void
    
    public init(normal: SpriteSlice, selected: SpriteSlice, action: @escaping () -> Void) {
        self.normalSlice = normal
        self.selectedSlice = selected
        self.action = action
    }
}

public class SkinnedPopupMenuView: WinampControlView {
    public let barSlice: SpriteSlice
    public let items: [SkinnedMenuItem]
    public var hoveredIndex: Int? = nil
    public var onClose: (() -> Void)? = nil
    private var mouseMonitor: Any? = nil
    
    public init(bar: SpriteSlice, items: [SkinnedMenuItem], onClose: (() -> Void)? = nil) {
        self.barSlice = bar
        self.items = items
        self.onClose = onClose
        let h = CGFloat(items.count * 18)
        super.init(frame: NSRect(x: 0, y: 0, width: 25, height: h))
        self.wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            if mouseMonitor == nil {
                mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self = self else { return event }
                    let loc = self.convert(event.locationInWindow, from: nil)
                    if !self.bounds.contains(loc) {
                        self.close()
                    }
                    return event
                }
            }
        } else {
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                mouseMonitor = nil
            }
        }
    }
    
    public func close() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        removeFromSuperview()
        onClose?()
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        close()
    }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
    
    public override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let idx = Int(pt.y / 18)
        let valid = (idx >= 0 && idx < items.count && pt.x >= 3) ? idx : nil
        if hoveredIndex != valid {
            hoveredIndex = valid
            needsDisplay = true
        }
    }
    
    public override func mouseExited(with event: NSEvent) {
        if hoveredIndex != nil {
            hoveredIndex = nil
            needsDisplay = true
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let idx = Int(pt.y / 18)
        guard idx >= 0 && idx < items.count && pt.x >= 3 else {
            close()
            return
        }
        
        hoveredIndex = idx
        needsDisplay = true
        
        guard let win = self.window else { return }
        var keepTracking = true
        while keepTracking {
            guard let next = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            let curPt = convert(next.locationInWindow, from: nil)
            let curIdx = Int(curPt.y / 18)
            let isInside = (curIdx >= 0 && curIdx < items.count && curPt.x >= 3)
            
            switch next.type {
            case .leftMouseDragged:
                let newHover = isInside ? curIdx : nil
                if hoveredIndex != newHover {
                    hoveredIndex = newHover
                    needsDisplay = true
                }
            case .leftMouseUp:
                keepTracking = false
                if isInside {
                    let action = items[curIdx].action
                    close()
                    action()
                } else {
                    close()
                }
            default:
                break
            }
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        // 1. Draw 3px vertical decorative bar on the left
        if let barImg = SkinManager.shared.image(for: barSlice) {
            context.drawSkinImage(barImg, in: NSRect(x: 0, y: 0, width: 3, height: bounds.height))
        }
        
        // 2. Draw each 22x18 menu item
        for (index, item) in items.enumerated() {
            let itemRect = NSRect(x: 3, y: CGFloat(index * 18), width: 22, height: 18)
            let isHovered = (hoveredIndex == index)
            let slice = isHovered ? item.selectedSlice : item.normalSlice
            if let img = SkinManager.shared.image(for: slice) {
                context.drawSkinImage(img, in: itemRect)
            }
        }
    }
}

/// Playlist window view featuring resizable frame (25x29 grid step increments),
/// authentic PLEDIT.BMP skinned frame decoration, track selection, scrollbar,
/// ADD/REM/SEL/MISC/LIST bottom toolbar menus, total running time display, and windowshade mode.
public class PlaylistWindowView: WinampControlView {
    public let playlist: PlaylistModel
    
    // MARK: - Titlebar Buttons
    public private(set) var closeButton: SkinButton!
    public private(set) var shadeButton: SkinButton!
    
    // MARK: - Bottom Toolbar Buttons
    public private(set) var addButton: SkinButton!
    public private(set) var remButton: SkinButton!
    public private(set) var selButton: SkinButton!
    public private(set) var miscButton: SkinButton!
    public private(set) var listButton: SkinButton!
    public private(set) var activePopupMenu: SkinnedPopupMenuView?
    
    // MARK: - Bottom Right Mini Transport & Scroll Buttons
    public private(set) var plPrevButton: SkinButton!
    public private(set) var plPlayButton: SkinButton!
    public private(set) var plPauseButton: SkinButton!
    public private(set) var plStopButton: SkinButton!
    public private(set) var plNextButton: SkinButton!
    public private(set) var plEjectButton: SkinButton!
    public private(set) var plScrollUpButton: SkinButton!
    public private(set) var plScrollDownButton: SkinButton!
    
    // MARK: - Playback & Scroll State
    public var currentTime: TimeInterval = 0 {
        didSet { needsDisplay = true }
    }
    public var status: PlayerStatus = .stopped {
        didSet { needsDisplay = true }
    }
    public var isBlinkVisible: Bool = true {
        didSet { needsDisplay = true }
    }
    private var scrollOffset: Int = 0
    private var isDraggingScrollThumb: Bool = false
    private var selectionAnchorIndex: Int? = nil
    private var dropInsertionIndex: Int? = nil
    
    public var isShadeMode: Bool = false {
        didSet {
            updateLayoutForShadeMode()
            layoutButtons()
            clampScrollOffset()
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
            for sub in subviews {
                sub.needsDisplay = true
            }
        }
    }
    
    private func clampScrollOffset() {
        let topH = AppConstants.Playlist.Layout.topBarHeight
        let botH = AppConstants.Playlist.Layout.bottomBarHeight
        let rowH = AppConstants.Playlist.trackRowHeight
        let availableH = max(0, bounds.height - topH - botH)
        let visibleRows = max(1, Int(availableH / rowH))
        let maxScroll = max(0, playlist.tracks.count - visibleRows)
        scrollOffset = max(0, min(scrollOffset, maxScroll))
    }
    
    // Callbacks to PlayerCoordinator
    public var onToggleShade: (() -> Void)?
    public var onClose: (() -> Void)?
    public var onPlayTrack: ((TrackItem) -> Void)?
    public var onAddFiles: (() -> Void)?
    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onStop: (() -> Void)?
    public var onPrevious: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onEject: (() -> Void)?
    
    public init(playlist: PlaylistModel) {
        self.playlist = playlist
        super.init(frame: NSRect(x: 0, y: 0, width: AppConstants.Window.width, height: AppConstants.Window.height))
        setupControls()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupControls() {
        // 1. TitleBar buttons (Close at right - 11, Shade at right - 20)
        // Background plTopRight already draws the unpressed icons; SkinButton only draws when pressed.
        closeButton = SkinButton(normal: nil, pressed: SpriteCatalog.plClosePressed) { [weak self] in
            self?.onClose?()
        }
        addSubview(closeButton)
        
        shadeButton = SkinButton(normal: nil, pressed: SpriteCatalog.plShadePressed) { [weak self] in
            self?.onToggleShade?()
        }
        addSubview(shadeButton)
        
        // 2. Bottom Toolbar Buttons
        // plBottomLeft and plBottomRight background already draw [+ ADD], [- REM], [SEL], [MISC], [LIST OPTS].
        // SkinButtons are transparent click targets showing their authentic pressed sprite on mouseDown.
        addButton = SkinButton(normal: nil, pressed: SpriteCatalog.plAddPressed) { [weak self] in
            self?.showAddMenu()
        }
        addSubview(addButton)
        
        remButton = SkinButton(normal: nil, pressed: SpriteCatalog.plRemovePressed) { [weak self] in
            self?.showRemMenu()
        }
        addSubview(remButton)
        
        selButton = SkinButton(normal: nil, pressed: SpriteCatalog.plSelectPressed) { [weak self] in
            self?.showSelMenu()
        }
        addSubview(selButton)
        
        miscButton = SkinButton(normal: nil, pressed: SpriteCatalog.plMiscPressed) { [weak self] in
            self?.showMiscMenu()
        }
        addSubview(miscButton)
        
        listButton = SkinButton(normal: nil, pressed: SpriteCatalog.plListPressed) { [weak self] in
            self?.showListMenu()
        }
        addSubview(listButton)
        
        // 3. Mini Transport Buttons in Bottom Bar
        plPrevButton = SkinButton { [weak self] in self?.onPrevious?() }
        plPrevButton.isShadeButton = true
        addSubview(plPrevButton)
        
        plPlayButton = SkinButton { [weak self] in self?.onPlay?() }
        plPlayButton.isShadeButton = true
        addSubview(plPlayButton)
        
        plPauseButton = SkinButton { [weak self] in self?.onPause?() }
        plPauseButton.isShadeButton = true
        addSubview(plPauseButton)
        
        plStopButton = SkinButton { [weak self] in self?.onStop?() }
        plStopButton.isShadeButton = true
        addSubview(plStopButton)
        
        plNextButton = SkinButton { [weak self] in self?.onNext?() }
        plNextButton.isShadeButton = true
        addSubview(plNextButton)
        
        plEjectButton = SkinButton { [weak self] in self?.onEject?() }
        plEjectButton.isShadeButton = true
        addSubview(plEjectButton)
        
        // 4. Scroll Buttons in Bottom Right
        plScrollUpButton = SkinButton { [weak self] in self?.scrollByPages(-1) }
        plScrollUpButton.isShadeButton = true
        addSubview(plScrollUpButton)
        
        plScrollDownButton = SkinButton { [weak self] in self?.scrollByPages(1) }
        plScrollDownButton.isShadeButton = true
        addSubview(plScrollDownButton)
        
        layoutButtons()
    }
    
    public override func layout() {
        super.layout()
        layoutButtons()
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutButtons()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutButtons()
    }
    
    public func scrollByPages(_ direction: Int) {
        let step = 4 * direction
        let topH = AppConstants.Playlist.Layout.topBarHeight
        let botH = AppConstants.Playlist.Layout.bottomBarHeight
        let rowH = AppConstants.Playlist.trackRowHeight
        let visibleRows = Int((bounds.height - topH - botH) / rowH)
        let maxOffset = max(0, playlist.tracks.count - visibleRows)
        scrollOffset = max(0, min(maxOffset, scrollOffset + step))
        needsDisplay = true
    }
    
    /// Positions titlebar and toolbar buttons relative to current dynamic window dimensions
    private func layoutButtons() {
        if let cur = activePopupMenu {
            cur.close()
            activePopupMenu = nil
        }
        
        typealias Layout = AppConstants.Playlist.Layout
        
        closeButton.frame = NSRect(
            x: bounds.width - Layout.closeButtonOffsetFromRight,
            y: Layout.topButtonY,
            width: Layout.topButtonSize,
            height: Layout.topButtonSize
        )
        shadeButton.frame = NSRect(
            x: bounds.width - Layout.shadeButtonOffsetFromRight,
            y: Layout.topButtonY,
            width: Layout.topButtonSize,
            height: Layout.topButtonSize
        )
        
        let bottomY = bounds.height - Layout.bottomBarHeight
        let btnY = bottomY + Layout.buttonYOffsetFromBottom
        let btnW = Layout.buttonWidth
        let btnH = Layout.buttonHeight
        
        addButton.frame = NSRect(x: Layout.addX, y: btnY, width: btnW, height: btnH)
        remButton.frame = NSRect(x: Layout.remX, y: btnY, width: btnW, height: btnH)
        selButton.frame = NSRect(x: Layout.selX, y: btnY, width: btnW, height: btnH)
        miscButton.frame = NSRect(x: Layout.miscX, y: btnY, width: btnW, height: btnH)
        listButton.frame = NSRect(x: bounds.width - Layout.listXOffsetFromRight, y: btnY, width: btnW, height: btnH)
        
        // Mini transport action buttons (botY + 22)
        let actionY = bottomY + Layout.actionButtonsYOffsetFromBottom
        let aW = Layout.actionButtonWidth
        let aH = Layout.actionButtonHeight
        plPrevButton?.frame = NSRect(x: bounds.width - Layout.actionPrevXOffsetFromRight, y: actionY, width: aW, height: aH)
        plPlayButton?.frame = NSRect(x: bounds.width - Layout.actionPlayXOffsetFromRight, y: actionY, width: aW, height: aH)
        plPauseButton?.frame = NSRect(x: bounds.width - Layout.actionPauseXOffsetFromRight, y: actionY, width: aW, height: aH)
        plStopButton?.frame = NSRect(x: bounds.width - Layout.actionStopXOffsetFromRight, y: actionY, width: aW, height: aH)
        plNextButton?.frame = NSRect(x: bounds.width - Layout.actionNextXOffsetFromRight, y: actionY, width: aW, height: aH)
        plEjectButton?.frame = NSRect(x: bounds.width - Layout.actionEjectXOffsetFromRight, y: actionY, width: aW, height: aH)
        
        // Scroll buttons
        let sW = Layout.scrollButtonWidth
        let sH = Layout.scrollButtonHeight
        let sX = bounds.width - Layout.scrollButtonOffsetFromRight
        plScrollUpButton?.frame = NSRect(x: sX, y: bottomY + Layout.scrollUpYOffsetFromBottom, width: sW, height: sH)
        plScrollDownButton?.frame = NSRect(x: sX, y: bottomY + Layout.scrollDownYOffsetFromBottom, width: sW, height: sH)
    }
    
    private func updateLayoutForShadeMode() {
        if let cur = activePopupMenu {
            cur.close()
            activePopupMenu = nil
        }
        
        let isFull = !isShadeMode
        addButton.isHidden = !isFull
        remButton.isHidden = !isFull
        selButton.isHidden = !isFull
        miscButton.isHidden = !isFull
        listButton.isHidden = !isFull
        plPrevButton?.isHidden = !isFull
        plPlayButton?.isHidden = !isFull
        plPauseButton?.isHidden = !isFull
        plStopButton?.isHidden = !isFull
        plNextButton?.isHidden = !isFull
        plEjectButton?.isHidden = !isFull
        plScrollUpButton?.isHidden = !isFull
        plScrollDownButton?.isHidden = !isFull
        
        shadeButton.normalSlice = nil
        shadeButton.pressedSlice = isShadeMode ? SpriteCatalog.plExpandPressed : SpriteCatalog.plShadePressed
    }
    
    private func createMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }
    
    // MARK: - Skinned Menus
    private func showSkinnedMenu(bar: SpriteSlice, items: [SkinnedMenuItem], above button: NSView) {
        if let current = activePopupMenu {
            let isSame = abs(current.frame.minX - (button.frame.minX - 3)) < 1
            current.close()
            activePopupMenu = nil
            if isSame {
                return
            }
        }
        
        let menu = SkinnedPopupMenuView(bar: bar, items: items)
        menu.onClose = { [weak self, weak menu] in
            if self?.activePopupMenu === menu {
                self?.activePopupMenu = nil
            }
        }
        
        let totalH = CGFloat(items.count * 18)
        let menuX = button.frame.minX - 3
        let menuY = button.frame.maxY - totalH
        
        menu.frame = NSRect(x: menuX, y: menuY, width: 25, height: totalH)
        addSubview(menu)
        activePopupMenu = menu
        menu.needsDisplay = true
    }
    
    private func showAddMenu() {
        let items: [SkinnedMenuItem] = [
            SkinnedMenuItem(
                normal: SpriteCatalog.plAddUrl,
                selected: SpriteCatalog.plAddUrlSelected,
                action: { [weak self] in self?.promptAddURL() }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plAddDir,
                selected: SpriteCatalog.plAddDirSelected,
                action: { [weak self] in self?.handleAddDirectory() }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plAddFile,
                selected: SpriteCatalog.plAddFileSelected,
                action: { [weak self] in self?.handleAddFile() }
            )
        ]
        showSkinnedMenu(bar: SpriteCatalog.plAddMenuBar, items: items, above: addButton)
    }
    
    private func showRemMenu() {
        let items: [SkinnedMenuItem] = [
            SkinnedMenuItem(
                normal: SpriteCatalog.plRemoveMisc,
                selected: SpriteCatalog.plRemoveMiscSelected,
                action: { [weak self] in
                    guard let self = self else { return }
                    self.showRemoveMiscSubmenu(at: self.remButton)
                }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plRemoveAll,
                selected: SpriteCatalog.plRemoveAllSelected,
                action: { [weak self] in self?.handleClearAll() }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plCrop,
                selected: SpriteCatalog.plCropSelected,
                action: { [weak self] in self?.handleCrop() }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plRemoveSel,
                selected: SpriteCatalog.plRemoveSelSelected,
                action: { [weak self] in self?.handleRemoveSelected() }
            )
        ]
        showSkinnedMenu(bar: SpriteCatalog.plRemoveMenuBar, items: items, above: remButton)
    }
    
    private func showSelMenu() {
        let items: [SkinnedMenuItem] = [
            SkinnedMenuItem(
                normal: SpriteCatalog.plInvertSelection,
                selected: SpriteCatalog.plInvertSelectionSelected,
                action: { [weak self] in self?.handleInvertSelection() }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plSelectZero,
                selected: SpriteCatalog.plSelectZeroSelected,
                action: { [weak self] in self?.handleSelectNone() }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plSelectAll,
                selected: SpriteCatalog.plSelectAllSelected,
                action: { [weak self] in self?.handleSelectAll() }
            )
        ]
        showSkinnedMenu(bar: SpriteCatalog.plSelectMenuBar, items: items, above: selButton)
    }
    
    private func showMiscMenu() {
        let items: [SkinnedMenuItem] = [
            SkinnedMenuItem(
                normal: SpriteCatalog.plSortList,
                selected: SpriteCatalog.plSortListSelected,
                action: { [weak self] in
                    guard let self = self else { return }
                    self.showSortSubmenu(at: self.miscButton)
                }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plFileInfo,
                selected: SpriteCatalog.plFileInfoSelected,
                action: { [weak self] in self?.handleFileInfo() }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plMiscOptions,
                selected: SpriteCatalog.plMiscOptionsSelected,
                action: { [weak self] in
                    guard let self = self else { return }
                    self.showMiscOptionsSubmenu(at: self.miscButton)
                }
            )
        ]
        showSkinnedMenu(bar: SpriteCatalog.plMiscMenuBar, items: items, above: miscButton)
    }
    
    private func showListMenu() {
        let items: [SkinnedMenuItem] = [
            SkinnedMenuItem(
                normal: SpriteCatalog.plNewList,
                selected: SpriteCatalog.plNewListSelected,
                action: { [weak self] in self?.handleClearAll() }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plSaveList,
                selected: SpriteCatalog.plSaveListSelected,
                action: { [weak self] in self?.handleSaveList() }
            ),
            SkinnedMenuItem(
                normal: SpriteCatalog.plLoadList,
                selected: SpriteCatalog.plLoadListSelected,
                action: { [weak self] in self?.handleLoadList() }
            )
        ]
        showSkinnedMenu(bar: SpriteCatalog.plListMenuBar, items: items, above: listButton)
    }
    
    private func showRemoveMiscSubmenu(at button: NSView) {
        let menu = NSMenu(title: "Remove Misc")
        menu.autoenablesItems = false
        menu.addItem(createMenuItem(title: "Remove Dead Files", action: #selector(handleRemoveDeadFiles)))
        menu.addItem(createMenuItem(title: "Remove Duplicates", action: #selector(handleRemoveDuplicates)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }
    
    private func showSortSubmenu(at button: NSView) {
        let menu = NSMenu(title: "Sort")
        menu.autoenablesItems = false
        menu.addItem(createMenuItem(title: "Sort list by title", action: #selector(handleSortTitle)))
        menu.addItem(createMenuItem(title: "Sort list by filename", action: #selector(handleSortFilename)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(createMenuItem(title: "Reverse list", action: #selector(handleReverse)))
        menu.addItem(createMenuItem(title: "Randomize list", action: #selector(handleRandomize)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }
    
    private func showMiscOptionsSubmenu(at button: NSView) {
        let menu = NSMenu(title: "Misc Options")
        menu.autoenablesItems = false
        menu.addItem(createMenuItem(title: "Jump to file... (J)", action: #selector(handleJumpToFile)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(createMenuItem(title: "Scroll to current track", action: #selector(handleScrollToCurrentTrack)))
        menu.addItem(createMenuItem(title: "Clear selection", action: #selector(handleSelectNone)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }
    
    public func promptAddURL() {
        let alert = NSAlert()
        alert.messageText = "Open URL"
        alert.informativeText = "Enter an Internet location to open:\n(e.g.: http://www.server.com:8000/stream.mp3)"
        alert.alertStyle = .informational
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        inputField.placeholderString = "http://"
        inputField.stringValue = "http://"
        alert.accessoryView = inputField
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        
        alert.window.initialFirstResponder = inputField
        
        if alert.runModal() == .alertFirstButtonReturn {
            var urlString = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlString.isEmpty && urlString != "http://" && urlString != "https://" else { return }
            if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") && !urlString.lowercased().hasPrefix("ftp://") {
                urlString = "http://" + urlString
            }
            if let url = URL(string: urlString) {
                let wasEmpty = playlist.tracks.isEmpty
                let ext = url.pathExtension.lowercased()
                if ext == "m3u" || ext == "pls" || ext == "m3u8" {
                    Task {
                        let tracks = await PlaylistIO.loadPlaylistAsync(from: url)
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
                            if !tracks.isEmpty {
                                self.playlist.add(tracks: tracks)
                            } else {
                                let track = TrackItem.create(from: url)
                                self.playlist.add(track: track)
                            }
                            self.needsDisplay = true
                            if wasEmpty, let first = self.playlist.tracks.first {
                                PlayerCoordinator.shared.loadAndPlay(track: first)
                            }
                        }
                    }
                } else {
                    let track = TrackItem.create(from: url)
                    playlist.add(track: track)
                    needsDisplay = true
                    if wasEmpty {
                        PlayerCoordinator.shared.loadAndPlay(track: track)
                    }
                }
            }
        }
    }
    
    private func handleFileInfo() {
        let selectedIndex: Int? = {
            if let sel = playlist.selectedIndices.first, sel < playlist.tracks.count {
                return sel
            }
            return playlist.currentIndex
        }()
        
        guard let idx = selectedIndex, idx < playlist.tracks.count else {
            PlayerCoordinator.shared.mainView?.marquee.showTemporaryMessage("No track selected")
            return
        }
        
        PlayerCoordinator.shared.showTrackInfoWindow(trackIndex: idx)
    }
    
    @objc private func contextPlaySelected() {
        if let sel = playlist.selectedIndices.first, sel < playlist.tracks.count {
            playlist.currentIndex = sel
            onPlayTrack?(playlist.tracks[sel])
            needsDisplay = true
        }
    }
    
    @objc private func contextViewFileInfo() {
        handleFileInfo()
    }
    
    @objc private func contextRemoveSelected() {
        playlist.removeSelected()
        needsDisplay = true
    }
    
    @objc private func contextCropSelected() {
        playlist.crop()
        needsDisplay = true
    }
    
    @objc private func contextClearPlaylist() {
        playlist.clear()
        needsDisplay = true
    }
    
    @objc private func handleRemoveDeadFiles() {
        let removed = playlist.removeDeadFiles()
        PlayerCoordinator.shared.mainView.marquee.showTemporaryMessage("Removed \(removed) dead file(s)")
        needsDisplay = true
    }
    
    @objc private func handleRemoveDuplicates() {
        let removed = playlist.removeDuplicates()
        PlayerCoordinator.shared.mainView.marquee.showTemporaryMessage("Removed \(removed) duplicate(s)")
        needsDisplay = true
    }
    
    @objc private func handleScrollToCurrentTrack() {
        if let idx = playlist.currentIndex {
            let rowH = AppConstants.Playlist.trackRowHeight
            let topH = AppConstants.Playlist.Layout.topBarHeight
            let botH = AppConstants.Playlist.Layout.bottomBarHeight
            let visibleRows = Int((bounds.height - topH - botH) / rowH)
            if idx < scrollOffset || idx >= scrollOffset + visibleRows {
                scrollOffset = max(0, idx - visibleRows / 2)
                needsDisplay = true
            }
        }
    }
    
    // MARK: - Menu Actions
    @objc private func handleJumpToFile() {
        PlayerCoordinator.shared.showJumpToFileWindow()
    }
    
    @objc private func handleAddFile() {
        onAddFiles?()
    }
    
    @objc private func handleAddDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let dirURL = panel.url {
            let extensions = AppConstants.Audio.supportedExtensions
            if let enumerator = FileManager.default.enumerator(at: dirURL, includingPropertiesForKeys: nil) {
                var newTracks: [TrackItem] = []
                for case let fileURL as URL in enumerator {
                    if extensions.contains(fileURL.pathExtension.lowercased()) {
                        newTracks.append(TrackItem.create(from: fileURL))
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
        
        let isKey = NSApp.isActive && (window?.isKeyWindow ?? false)
        typealias Layout = AppConstants.Playlist.Layout
        
        if isShadeMode {
            // Draw Shade Mode Bar (height: 14)
            // Left: 25px, Mid: tiled 25px, Right: 50px
            let rightSlice = isKey ? SpriteCatalog.plShadeRightSel : SpriteCatalog.plShadeRight
            if let leftImg = SkinManager.shared.image(for: SpriteCatalog.plShadeLeft) {
                context.drawSkinImage(leftImg, in: NSRect(x: 0, y: 0, width: Layout.cornerPieceWidth, height: Layout.shadeHeight))
            }
            if let midImg = SkinManager.shared.image(for: SpriteCatalog.plShadeMiddle) {
                context.drawTiledHorizontal(
                    image: midImg,
                    from: Layout.cornerPieceWidth,
                    to: bounds.width - 50.0,
                    y: 0,
                    width: Layout.cornerPieceWidth,
                    height: Layout.shadeHeight
                )
            }
            if let rightImg = SkinManager.shared.image(for: rightSlice) {
                context.drawSkinImage(rightImg, in: NSRect(x: bounds.width - 50.0, y: 0, width: 50.0, height: Layout.shadeHeight))
            }
            
            // Draw shade track title and duration
            if let track = playlist.currentTrack {
                let trackIdx = (playlist.currentIndex ?? 0) + 1
                let durStr = track.formattedDuration
                let durWidth = CGFloat(durStr.count) * AppConstants.Font.charWidth
                let rightMargin = bounds.width - 55.0
                let durX = max(5.0, rightMargin - durWidth)
                
                let maxTitleWidth = max(0, durX - 10.0 - 5.0)
                let maxChars = Int(maxTitleWidth / AppConstants.Font.charWidth)
                let rawTitle = "\(trackIdx). \(track.artist) - \(track.title)"
                let titleStr = (rawTitle.count > maxChars) ? (String(rawTitle.prefix(max(0, maxChars - 1))) + "…") : rawTitle
                
                BitmapFont.draw(string: titleStr, in: context, at: CGPoint(x: 5, y: 4))
                BitmapFont.draw(string: durStr, in: context, at: CGPoint(x: durX, y: 4))
            } else {
                let noFile = "[No file]"
                BitmapFont.draw(string: noFile, in: context, at: CGPoint(x: 5, y: 4))
                let totalStr = playlist.formattedTotalDuration
                let totalX = bounds.width - 55.0 - CGFloat(totalStr.count) * AppConstants.Font.charWidth
                BitmapFont.draw(string: totalStr, in: context, at: CGPoint(x: max(5.0, totalX), y: 4))
            }
            return
        }
        
        let topH = Layout.topBarHeight
        let leftSlice = isKey ? SpriteCatalog.plTopLeftSel : SpriteCatalog.plTopLeft
        let titleSlice = isKey ? SpriteCatalog.plTopTitleSel : SpriteCatalog.plTopTitle
        let tileSlice = isKey ? SpriteCatalog.plTopTileSel : SpriteCatalog.plTopTile
        let rightSlice = isKey ? SpriteCatalog.plTopRightSel : SpriteCatalog.plTopRight
        
        // 1. Draw Top Bar (height: 20 in normal mode)
        // Authentic Winamp geometry: Left corner (25px), Centered Title (100px), Right corner (25px)
        let titleW = Layout.titlePieceWidth
        let leftW = Layout.cornerPieceWidth
        let rightW = Layout.cornerPieceWidth
        let titleX = round((bounds.width - titleW) / 2.0)
        
        if let leftImg = SkinManager.shared.image(for: leftSlice) {
            context.drawSkinImage(leftImg, in: NSRect(x: 0, y: 0, width: leftW, height: topH))
        }
        if let tileImg = SkinManager.shared.image(for: tileSlice) {
            context.drawTiledHorizontal(image: tileImg, from: leftW, to: titleX, y: 0, width: leftW, height: topH)
        }
        if let titleImg = SkinManager.shared.image(for: titleSlice) {
            context.drawSkinImage(titleImg, in: NSRect(x: titleX, y: 0, width: titleW, height: topH))
        }
        if let tileImg = SkinManager.shared.image(for: tileSlice) {
            context.drawTiledHorizontal(image: tileImg, from: titleX + titleW, to: bounds.width - rightW, y: 0, width: leftW, height: topH)
        }
        if let rightImg = SkinManager.shared.image(for: rightSlice) {
            context.drawSkinImage(rightImg, in: NSRect(x: bounds.width - rightW, y: 0, width: rightW, height: topH))
        }
        
        // 2. Draw Bottom Bar (height: 38)
        let botH = Layout.bottomBarHeight
        let botY = bounds.height - botH
        if let bLeft = SkinManager.shared.image(for: SpriteCatalog.plBottomLeft) {
            context.drawSkinImage(bLeft, in: NSRect(x: 0, y: botY, width: Layout.bottomLeftWidth, height: botH))
        }
        if let bTile = SkinManager.shared.image(for: SpriteCatalog.plBottomTile) {
            context.drawTiledHorizontal(
                image: bTile,
                from: Layout.bottomLeftWidth,
                to: bounds.width - Layout.bottomRightWidth,
                y: botY,
                width: Layout.bottomTileWidth,
                height: botH
            )
        }
        if let bRight = SkinManager.shared.image(for: SpriteCatalog.plBottomRight) {
            context.drawSkinImage(bRight, in: NSRect(x: bounds.width - Layout.bottomRightWidth, y: botY, width: Layout.bottomRightWidth, height: botH))
        }
        
        // 2b. Draw Left and Right Side Borders
        if let lTile = SkinManager.shared.image(for: SpriteCatalog.plLeftTile) {
            context.drawTiledVertical(image: lTile, x: 0, from: topH, to: botY, width: Layout.leftBorderWidth, height: Layout.sideBorderTileHeight)
        }
        if let rTile = SkinManager.shared.image(for: SpriteCatalog.plRightTile) {
            context.drawTiledVertical(image: rTile, x: bounds.width - Layout.rightBorderWidth, from: topH, to: botY, width: Layout.rightBorderWidth, height: Layout.sideBorderTileHeight)
        }
        
        // 3. Draw Track List Area
        let listHeight = bounds.height - topH - botH
        guard listHeight > 0 else { return }
        let listRect = NSRect(x: Layout.leftBorderWidth, y: topH, width: bounds.width - (Layout.leftBorderWidth + Layout.rightBorderWidth), height: listHeight)
        let style = SkinManager.shared.currentSkin?.playlistStyle ?? PlaylistStyle()
        
        // Track list background
        context.setFillColor(style.normalBGColor.cgColor)
        context.fill(listRect)
        
        // Draw track rows (13px each)
        let rowH = AppConstants.Playlist.trackRowHeight
        let visibleRows = max(1, Int(listRect.height / rowH))
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
            
            // Text color: selected/current = white, normal = green
            let textColor = (isSelected || isCurrent) ? style.currentColor : style.normalColor
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
            
            // Title on left
            let titleStr = track.formattedTitle(with: trackIndex + 1)
            let textRect = NSRect(x: rowRect.minX + 2, y: rowRect.minY + 1, width: rowRect.width - 56, height: rowH - 1)
            (titleStr as NSString).draw(in: textRect, withAttributes: attrs)
            
            // Duration on right
            let durStr = track.formattedDuration
            let durRect = NSRect(x: rowRect.maxX - 52, y: rowRect.minY + 1, width: 50, height: rowH - 1)
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
        
        // 3b. Draw Drop Insertion Indicator Line for Track Reordering
        if let dropIndex = dropInsertionIndex {
            let relativeRow = dropIndex - scrollOffset
            let insertY = listRect.minY + CGFloat(relativeRow) * rowH
            if insertY >= listRect.minY && insertY <= listRect.maxY + 1 {
                context.setFillColor(NSColor.white.cgColor)
                context.fill(NSRect(x: listRect.minX, y: insertY - 1, width: listRect.width, height: 2))
            }
        }
        
        // 4. Draw Scrollbar Handle
        let trackHeight = listRect.height
        if trackHeight > 0 && playlist.tracks.count > visibleRows {
            let maxScroll = max(1, playlist.tracks.count - visibleRows)
            let ratio = CGFloat(scrollOffset) / CGFloat(maxScroll)
            let thumbY = topH + ratio * max(0, trackHeight - Layout.scrollbarThumbHeight)
            let thumbSlice = isDraggingScrollThumb ? SpriteCatalog.plScrollHandleSelected : SpriteCatalog.plScrollHandle
            if let thumbImg = SkinManager.shared.image(for: thumbSlice) {
                context.drawSkinImage(thumbImg, in: NSRect(
                    x: bounds.width - Layout.scrollbarOffsetFromRight,
                    y: thumbY,
                    width: Layout.scrollbarThumbWidth,
                    height: Layout.scrollbarThumbHeight
                ))
            }
        }
        
        // 5. Draw Running Duration in bottom bar (selectedTime / totalTime)
        let runMsg = playlist.runningTimeMessage
        BitmapFont.draw(string: runMsg, in: context, at: CGPoint(
            x: bounds.width - Layout.runningTimeOffsetFromRight,
            y: botY + Layout.runningTimeYOffsetFromBottom
        ))
        
        // 6. Draw Mini Track Time in bottom bar
        let mins = Int(currentTime) / 60
        let secs = Int(currentTime) % 60
        BitmapFont.drawMiniTime(
            minutes: mins,
            seconds: secs,
            isNegative: false,
            status: status,
            isBlinkVisible: isBlinkVisible,
            in: context,
            at: CGPoint(
                x: bounds.width - Layout.miniTimeOffsetFromRight,
                y: botY + Layout.miniTimeYOffsetFromBottom
            )
        )
    }
    
    // MARK: - Mouse Interaction & Resizing
    public override func resetCursorRects() {
        super.resetCursorRects()
        let gripSize = AppConstants.Playlist.Layout.resizeGripSize
        let resizeRect = isShadeMode
            ? NSRect(x: bounds.width - gripSize, y: 0, width: gripSize, height: AppConstants.Playlist.Layout.shadeHeight)
            : NSRect(x: bounds.width - gripSize, y: bounds.height - gripSize, width: gripSize, height: gripSize)
        addCursorRect(resizeRect, cursor: .resizeUpDown)
        
        if !isShadeMode {
            let topH = AppConstants.Playlist.Layout.topBarHeight
            let botH = AppConstants.Playlist.Layout.bottomBarHeight
            let trackHeight = max(0, bounds.height - topH - botH)
            let scrollTrackRect = NSRect(
                x: bounds.width - AppConstants.Playlist.Layout.rightBorderWidth,
                y: topH,
                width: AppConstants.Playlist.Layout.rightBorderWidth,
                height: trackHeight
            )
            addCursorRect(scrollTrackRect, cursor: .resizeUpDown)
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let gripSize = AppConstants.Playlist.Layout.resizeGripSize
        let topH = AppConstants.Playlist.Layout.topBarHeight
        let botH = AppConstants.Playlist.Layout.bottomBarHeight
        
        // 1. Check resize grip (bottom-right 20x20 in normal, right 20x14 in shade)
        let resizeRect = isShadeMode
            ? NSRect(x: bounds.width - gripSize, y: 0, width: gripSize, height: AppConstants.Playlist.Layout.shadeHeight)
            : NSRect(x: bounds.width - gripSize, y: bounds.height - gripSize, width: gripSize, height: gripSize)
        if resizeRect.contains(local) {
            guard let win = self.window as? WinampWindow else { return }
            startResizeDrag(with: event, in: win)
            return
        }
        
        // 2. Titlebar double-click (toggles shade)
        let titleH = isShadeMode ? AppConstants.Playlist.Layout.shadeHeight : topH
        if event.clickCount == 2 && local.y <= titleH {
            onToggleShade?()
            return
        }
        
        // 3. Titlebar drag (moves window)
        if local.y <= titleH {
            guard let win = self.window as? WinampWindow else { return }
            win.startWindowDrag(with: event)
            trackWindowDrag(with: event, in: win)
            return
        }
        
        // 4. Scrollbar track click and interactive dragging
        let scrollTrackRect = NSRect(
            x: bounds.width - AppConstants.Playlist.Layout.rightBorderWidth,
            y: topH,
            width: AppConstants.Playlist.Layout.rightBorderWidth,
            height: bounds.height - topH - botH
        )
        if scrollTrackRect.contains(local) {
            let rowH = AppConstants.Playlist.trackRowHeight
            let trackHeight = bounds.height - topH - botH
            let visibleRows = Int(trackHeight / rowH)
            
            guard playlist.tracks.count > visibleRows else { return }
            
            let maxScroll = playlist.tracks.count - visibleRows
            let thumbH = AppConstants.Playlist.Layout.scrollbarThumbHeight
            let travelRange = max(1.0, trackHeight - thumbH)
            let currentThumbY = topH + (CGFloat(scrollOffset) / CGFloat(maxScroll)) * travelRange
            let thumbRect = NSRect(
                x: bounds.width - AppConstants.Playlist.Layout.rightBorderWidth,
                y: currentThumbY,
                width: AppConstants.Playlist.Layout.rightBorderWidth,
                height: thumbH
            )
            
            let thumbClickOffsetY: CGFloat
            if thumbRect.contains(local) {
                // Clicked directly on thumb: keep relative grab point
                thumbClickOffsetY = local.y - currentThumbY
            } else {
                // Clicked on track: jump thumb center to click location
                let targetThumbY = local.y - thumbH / 2.0
                let clampedThumbY = max(topH, min(topH + travelRange, targetThumbY))
                let norm = (clampedThumbY - topH) / travelRange
                let newOffset = max(0, min(maxScroll, Int(round(norm * CGFloat(maxScroll)))))
                if newOffset != scrollOffset {
                    scrollOffset = newOffset
                }
                thumbClickOffsetY = thumbH / 2.0
            }
            
            isDraggingScrollThumb = true
            needsDisplay = true
            
            guard let win = self.window else { return }
            var keepTracking = true
            while keepTracking {
                guard let nextEvent = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
                switch nextEvent.type {
                case .leftMouseDragged:
                    let currentPoint = convert(nextEvent.locationInWindow, from: nil)
                    let targetThumbY = currentPoint.y - thumbClickOffsetY
                    let clampedThumbY = max(topH, min(topH + travelRange, targetThumbY))
                    let norm = (clampedThumbY - topH) / travelRange
                    let newOffset = max(0, min(maxScroll, Int(round(norm * CGFloat(maxScroll)))))
                    if newOffset != scrollOffset {
                        scrollOffset = newOffset
                        needsDisplay = true
                    }
                case .leftMouseUp:
                    keepTracking = false
                    isDraggingScrollThumb = false
                    needsDisplay = true
                default:
                    break
                }
            }
            return
        }
        
        // 5. Track list click
        let listRect = NSRect(
            x: AppConstants.Playlist.Layout.leftBorderWidth,
            y: topH,
            width: bounds.width - (AppConstants.Playlist.Layout.leftBorderWidth + AppConstants.Playlist.Layout.rightBorderWidth),
            height: bounds.height - topH - botH
        )
        if listRect.contains(local) {
            guard let win = self.window as? WinampWindow else { return }
            let rowH = AppConstants.Playlist.trackRowHeight
            let clickedRow = Int((local.y - topH) / rowH)
            let trackIndex = scrollOffset + clickedRow
            if trackIndex < playlist.tracks.count {
                if event.clickCount == 2 {
                    if event.modifierFlags.contains(.option) || local.x >= (listRect.maxX - 45) {
                        // Double-click on duration column or Option+double-click -> Track Info
                        PlayerCoordinator.shared.showTrackInfoWindow(trackIndex: trackIndex)
                    } else {
                        // Double-click -> Play track immediately
                        playlist.currentIndex = trackIndex
                        onPlayTrack?(playlist.tracks[trackIndex])
                    }
                } else {
                    // Single click with modifier or drag
                    if event.modifierFlags.contains(.shift) {
                        let anchor = selectionAnchorIndex ?? (playlist.currentIndex ?? trackIndex)
                        let lower = min(anchor, trackIndex)
                        let upper = max(anchor, trackIndex)
                        playlist.selectedIndices = Set(lower...upper)
                        needsDisplay = true
                    } else if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                        if playlist.selectedIndices.contains(trackIndex) {
                            playlist.selectedIndices.remove(trackIndex)
                        } else {
                            playlist.selectedIndices.insert(trackIndex)
                        }
                        selectionAnchorIndex = trackIndex
                        needsDisplay = true
                    } else {
                        // If clicking an unselected track, immediately select only it
                        if !playlist.selectedIndices.contains(trackIndex) {
                            playlist.selectedIndices = [trackIndex]
                            selectionAnchorIndex = trackIndex
                            needsDisplay = true
                        }
                        // Track drag for interactive reordering
                        startTrackDrag(with: event, clickedIndex: trackIndex, in: win)
                    }
                }
                needsDisplay = true
            }
        }
    }
    
    // MARK: - Track List Context Menu
    public override func menu(for event: NSEvent) -> NSMenu? {
        let local = convert(event.locationInWindow, from: nil)
        let topH = AppConstants.Playlist.Layout.topBarHeight
        let botH = AppConstants.Playlist.Layout.bottomBarHeight
        let listRect = NSRect(
            x: AppConstants.Playlist.Layout.leftBorderWidth,
            y: topH,
            width: bounds.width - (AppConstants.Playlist.Layout.leftBorderWidth + AppConstants.Playlist.Layout.rightBorderWidth),
            height: bounds.height - topH - botH
        )
        guard listRect.contains(local) else {
            return PlayerCoordinator.shared.buildWinampMenu()
        }
        
        let rowH = AppConstants.Playlist.trackRowHeight
        let clickedRow = Int((local.y - topH) / rowH)
        let trackIndex = scrollOffset + clickedRow
        if trackIndex < playlist.tracks.count {
            if !playlist.selectedIndices.contains(trackIndex) {
                playlist.selectedIndices = [trackIndex]
                needsDisplay = true
            }
            
            let menu = NSMenu(title: "Track Context Menu")
            let playItem = NSMenuItem(title: "Play", action: #selector(contextPlaySelected), keyEquivalent: "\r")
            playItem.target = self
            menu.addItem(playItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let infoItem = NSMenuItem(title: "View file info... (Alt+3)", action: #selector(contextViewFileInfo), keyEquivalent: "3")
            infoItem.keyEquivalentModifierMask = [.option]
            infoItem.target = self
            menu.addItem(infoItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let removeItem = NSMenuItem(title: "Remove selected (Delete)", action: #selector(contextRemoveSelected), keyEquivalent: "")
            removeItem.target = self
            menu.addItem(removeItem)
            
            let cropItem = NSMenuItem(title: "Crop selected (Ctrl+Delete)", action: #selector(contextCropSelected), keyEquivalent: "")
            cropItem.target = self
            menu.addItem(cropItem)
            
            let clearItem = NSMenuItem(title: "Clear playlist", action: #selector(contextClearPlaylist), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
            
            return menu
        }
        return PlayerCoordinator.shared.buildWinampMenu()
    }
    
    public override func scrollWheel(with event: NSEvent) {
        if event.deltaY > 0 {
            scrollOffset = max(0, scrollOffset - 1)
        } else if event.deltaY < 0 {
            let rowH = AppConstants.Playlist.trackRowHeight
            let topH = AppConstants.Playlist.Layout.topBarHeight
            let botH = AppConstants.Playlist.Layout.bottomBarHeight
            let visibleRows = Int((bounds.height - topH - botH) / rowH)
            let maxOffset = max(0, playlist.tracks.count - visibleRows)
            scrollOffset = min(maxOffset, scrollOffset + 1)
        }
        needsDisplay = true
    }
    
    /// Interactive playlist resizing loop snapped to canonical 25px horizontal and 29px vertical steps
    private func startResizeDrag(with initialEvent: NSEvent, in win: WinampWindow) {
        let initialMouse = NSEvent.mouseLocation
        let initialFrame = win.frame
        let isShade = self.isShadeMode
        
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            switch nextEvent.type {
            case .leftMouseDragged:
                let currentMouse = NSEvent.mouseLocation
                let deltaX = currentMouse.x - initialMouse.x
                let deltaY = initialMouse.y - currentMouse.y // mouse moving down = larger height
                
                let stepsX = round(deltaX / AppConstants.Window.resizeStepX)
                let baseWidth = max(AppConstants.Window.width, round(initialFrame.width))
                let newWidth = max(AppConstants.Window.width, baseWidth + stepsX * AppConstants.Window.resizeStepX)
                
                let newHeight: CGFloat
                if isShade {
                    newHeight = AppConstants.Window.shadeHeight
                } else {
                    let stepsY = round(deltaY / AppConstants.Window.resizeStepY)
                    let baseHeight = max(AppConstants.Window.height, round(initialFrame.height))
                    newHeight = max(AppConstants.Window.height, baseHeight + stepsY * AppConstants.Window.resizeStepY)
                }
                
                let newMinX = round(initialFrame.minX)
                let newMaxY = round(initialFrame.maxY)
                let newMinY = round(newMaxY - newHeight)
                
                let newFrame = NSRect(x: newMinX, y: newMinY, width: newWidth, height: newHeight)
                if newFrame != win.frame {
                    win.setFrame(newFrame, display: true, animate: false)
                    self.frame = NSRect(x: 0, y: 0, width: newWidth, height: newHeight)
                    self.layoutButtons()
                    self.needsDisplay = true
                }
                
            case .leftMouseUp:
                keepTracking = false
                WindowLayoutManager.shared.updateAdjacencies()
                PersistenceManager.shared.state.playlistWindowSize = [Double(round(win.frame.width)), Double(round(win.frame.height))]
                PersistenceManager.shared.saveSession()
                PlayerCoordinator.shared.saveWindowLayout()
                
            default:
                break
            }
        }
    }
    
    /// Interactive track drag reordering loop
    private func startTrackDrag(with initialEvent: NSEvent, clickedIndex: Int, in win: WinampWindow) {
        let initialPoint = convert(initialEvent.locationInWindow, from: nil)
        var hasStartedDragging = false
        var keepTracking = true
        
        let rowH = AppConstants.Playlist.trackRowHeight
        let topH = AppConstants.Playlist.Layout.topBarHeight
        let botH = AppConstants.Playlist.Layout.bottomBarHeight
        
        while keepTracking {
            guard let nextEvent = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            switch nextEvent.type {
            case .leftMouseDragged:
                let currentPoint = convert(nextEvent.locationInWindow, from: nil)
                if !hasStartedDragging {
                    let dragDistance = hypot(currentPoint.x - initialPoint.x, currentPoint.y - initialPoint.y)
                    if dragDistance >= 4 {
                        hasStartedDragging = true
                    }
                }
                
                if hasStartedDragging {
                    let visibleRows = Int((bounds.height - topH - botH) / rowH)
                    // Auto-scroll when dragging outside the track list boundaries
                    if currentPoint.y < topH {
                        scrollOffset = max(0, scrollOffset - 1)
                    } else if currentPoint.y > bounds.height - botH {
                        let maxOffset = max(0, playlist.tracks.count - visibleRows)
                        scrollOffset = min(maxOffset, scrollOffset + 1)
                    }
                    
                    // Calculate drop insertion index
                    let relY = currentPoint.y - topH
                    let rowFloat = relY / rowH
                    let targetRow = Int(round(rowFloat))
                    let targetIndex = max(0, min(playlist.tracks.count, scrollOffset + targetRow))
                    if dropInsertionIndex != targetIndex {
                        dropInsertionIndex = targetIndex
                        needsDisplay = true
                    }
                }
                
            case .leftMouseUp:
                keepTracking = false
                if hasStartedDragging, let targetIndex = dropInsertionIndex {
                    dropInsertionIndex = nil
                    playlist.moveTracks(from: playlist.selectedIndices, to: targetIndex)
                    needsDisplay = true
                } else {
                    dropInsertionIndex = nil
                    // If we didn't drag, and clicked on a previously multi-selected item, collapse selection now
                    if !initialEvent.modifierFlags.contains(.shift) &&
                       !initialEvent.modifierFlags.contains(.command) &&
                       !initialEvent.modifierFlags.contains(.control) {
                        playlist.selectedIndices = [clickedIndex]
                        selectionAnchorIndex = clickedIndex
                    }
                    needsDisplay = true
                }
                
            default:
                break
            }
        }
    }
}
