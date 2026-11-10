import AppKit

final class VisualizerSelectionList: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private static let rowHeight: CGFloat = 17
    private static let textColor = NSColor(white: 0.8, alpha: 1)
    private static let selectionColor = NSColor(srgbRed: 1, green: 0.8, blue: 0.13, alpha: 1)
    private static let cellID = NSUserInterfaceItemIdentifier("VisualizerChoice")

    private let table = PresetTable()
    private let scrollView = PresetScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "No .milk presets found. Add them to the presets folder.")
    private let openFolderButton = NSButton(title: "Open presets folder", target: nil, action: nil)
    private var titles: [String] = []
    private var lastSelectedRow: Int?
    private var isReloading = false

    var onSelectionChanged: ((Int) -> Void)?
    var onOpenFolder: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Void)?

    var selectedRow: Int? { titles.indices.contains(table.selectedRow) ? table.selectedRow : nil }
    var contentHeight: CGFloat { titles.isEmpty ? 68 : CGFloat(titles.count) * Self.rowHeight }

    init(frame: NSRect, titles: [String], selectedRow: Int?, accessibilityLabel: String) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor

        let column = NSTableColumn(identifier: Self.cellID)
        column.width = bounds.width
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.usesAutomaticRowHeights = false
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel(accessibilityLabel)
        table.onKeyDown = { [weak self] event in self?.onKeyDown?(event) }

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = table
        scrollView.onScrollRows = { [weak self] offset in self?.moveSelection(by: offset) }
        addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = Self.textColor
        addSubview(emptyLabel)
        openFolderButton.bezelStyle = .inline
        openFolderButton.target = self
        openFolderButton.action = #selector(openFolder)
        addSubview(openFolderButton)

        reload(titles: titles, selectedRow: selectedRow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        emptyLabel.frame = NSRect(x: 8, y: max(24, bounds.height - 40), width: max(0, bounds.width - 16), height: 32)
        openFolderButton.frame = NSRect(x: 8, y: max(4, bounds.height - 64), width: min(145, bounds.width - 8), height: 20)
    }

    func reload(titles: [String], selectedRow: Int?) {
        isReloading = true
        defer {
            lastSelectedRow = self.selectedRow
            isReloading = false
        }
        self.titles = titles
        lastSelectedRow = nil
        scrollView.isHidden = titles.isEmpty
        emptyLabel.isHidden = !titles.isEmpty
        openFolderButton.isHidden = !titles.isEmpty
        table.reloadData()
        if let selectedRow, !titles.isEmpty {
            select(row: selectedRow)
        } else {
            table.deselectAll(nil)
        }
    }

    func focusList() {
        if !titles.isEmpty { window?.makeFirstResponder(table) }
    }

    func moveSelection(by offset: Int) {
        guard !titles.isEmpty else { return }
        select(row: (selectedRow ?? (offset < 0 ? titles.count : -1)) + offset)
    }

    private func select(row: Int) {
        let row = min(max(0, row), titles.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)

        let clip = scrollView.contentView
        var viewport = clip.bounds
        viewport.origin.y = table.rect(ofRow: row).midY - viewport.height / 2
        clip.scroll(to: clip.constrainBoundsRect(viewport).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    @objc private func openFolder() { onOpenFolder?() }

    func numberOfRows(in tableView: NSTableView) -> Int { titles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label: NSTextField
        if let reused = tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? NSTextField {
            label = reused
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = Self.cellID
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingTail
        }
        label.stringValue = titles[row]
        label.textColor = row == selectedRow ? Self.selectionColor : Self.textColor
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selected = selectedRow
        let changed = selected != lastSelectedRow
        if let old = lastSelectedRow, titles.indices.contains(old),
           let label = table.view(atColumn: 0, row: old, makeIfNecessary: false) as? NSTextField {
            label.textColor = Self.textColor
        }
        if let selected, let label = table.view(atColumn: 0, row: selected, makeIfNecessary: false) as? NSTextField {
            label.textColor = Self.selectionColor
        }
        lastSelectedRow = selected
        if changed, !isReloading, let selected { onSelectionChanged?(selected) }
    }

    private final class PresetTable: NSTableView {
        var onKeyDown: ((NSEvent) -> Void)?

        override func keyDown(with event: NSEvent) {
            if let onKeyDown { onKeyDown(event) } else { super.keyDown(with: event) }
        }
    }

    private final class PresetScrollView: NSScrollView {
        var onScrollRows: ((Int) -> Void)?
        private var pendingRows: CGFloat = 0

        override func scrollWheel(with event: NSEvent) {
            if event.phase == .began { pendingRows = 0 }
            let scale = event.hasPreciseScrollingDeltas ? VisualizerSelectionList.rowHeight : 1
            pendingRows -= event.scrollingDeltaY / scale
            let wholeRows = Int(pendingRows)
            if wholeRows != 0 {
                pendingRows -= CGFloat(wholeRows)
                onScrollRows?(wholeRows)
            }
        }
    }
}
