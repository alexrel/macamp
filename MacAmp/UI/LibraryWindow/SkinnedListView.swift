import SwiftUI
import AppKit
import Combine

/// The Media Library's lists, as gen_ml skins a Windows ListView (skinnedlistview / skinnedheader / skinnedscrollwnd):
/// GENEX colours, a header with a three-colour frame and sort arrow, selection bars that dim when the list loses focus,
/// 14 px GENEX scrollbars. Behaviour of the ListView: click a header to sort (again: reverse; another column keeps the
/// direction), drag column edges, Enter plays and ⇧Enter enqueues, right-click menu, drag rows to the playlist.
struct MediaListView<Row: Identifiable>: NSViewRepresentable where Row.ID: Hashable {
    typealias Column = (title: String, width: CGFloat, alignment: Alignment, value: (Row) -> String)
    let rows: [Row]
    let columns: [Column]
    @Binding var selection: Set<Row.ID>
    /// Column widths and sort are remembered under this name
    var autosave: String
    /// Sort column title until the user picks one (nil: the order given)
    var defaultSort: String? = nil
    /// "All (N artists)" stays on top whatever the sort
    var pinsFirstRow = false
    var url: ((Row) -> URL?)? = nil
    var menu: (([Row]) -> NSMenu?)? = nil
    var onDelete: (([Row]) -> Void)? = nil
    /// Double-click / Enter; `shift` is ⇧ held (Winamp: ⇧ swaps Play and Enqueue)
    let onActivate: ([Row], _ shift: Bool) -> Void

    func makeCoordinator() -> SkinnedListController {
        SkinnedListController(columns: columns.map { .init(title: $0.title, width: $0.width, alignment: $0.alignment == .trailing ? .right : .left) },
                              autosave: autosave, defaultSort: defaultSort)
    }

    func makeNSView(context: Context) -> SkinnedListContainer { context.coordinator.container }

    func updateNSView(_ view: SkinnedListContainer, context: Context) {
        let c = context.coordinator
        let byID = Dictionary(self.rows.map { (AnyHashable($0.id), $0) }, uniquingKeysWith: { a, _ in a })
        func pick(_ ids: [AnyHashable]) -> [Row] { ids.compactMap { byID[$0] } }
        c.pinsFirstRow = pinsFirstRow
        c.onSelection = { ids in selection = Set(ids.compactMap { $0.base as? Row.ID }) }
        c.onActivate = { ids, shift in onActivate(pick(ids), shift) }
        c.onDelete = onDelete.map { delete in { ids in delete(pick(ids)) } }
        c.menu = menu.map { build in { ids in build(pick(ids)) } }
        c.setItems(self.rows.map { row in .init(id: AnyHashable(row.id), values: columns.map { $0.value(row) }, url: url?(row)) })
        c.setSelection(Set(selection.map(AnyHashable.init)))
    }
}

// MARK: - Controller (data source, sorting, selection)

final class SkinnedListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Item { let id: AnyHashable; let values: [String]; let url: URL? }
    struct Column { let title: String; let width: CGFloat; let alignment: NSTextAlignment }

    let container: SkinnedListContainer
    var table: SkinnedTableView { container.table }
    let columns: [Column]
    private(set) var items: [Item] = []
    private var source: [Item] = []
    var pinsFirstRow = false
    var onSelection: (([AnyHashable]) -> Void)?
    var onActivate: (([AnyHashable], Bool) -> Void)?
    var onDelete: (([AnyHashable]) -> Void)?
    var menu: (([AnyHashable]) -> NSMenu?)?
    private let defaultsKey: String
    private var updatingSelection = false
    private var skinChange: AnyCancellable?

    /// Sorted column (index) and direction, remembered per list
    private(set) var sortColumn: Int?
    private(set) var ascending = true

    init(columns: [Column], autosave: String, defaultSort: String?) {
        self.columns = columns
        defaultsKey = "MacAmpList." + autosave
        container = SkinnedListContainer()
        super.init()
        let saved = UserDefaults.standard.string(forKey: defaultsKey + ".sort") ?? defaultSort
        sortColumn = saved.flatMap { title in columns.firstIndex { $0.title == title } }
        ascending = UserDefaults.standard.object(forKey: defaultsKey + ".ascending") as? Bool ?? true

        for (i, column) in columns.enumerated() {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.title))
            col.title = column.title
            col.width = column.width
            col.minWidth = 16
            col.resizingMask = .userResizingMask
            col.headerCell.alignment = .left
            _ = i
            table.addTableColumn(col)
        }
        table.autosaveName = defaultsKey
        table.autosaveTableColumns = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.onActivate = { [weak self] shift in self?.activate(shift: shift) }
        table.onDelete = { [weak self] in
            guard let self, let onDelete = self.onDelete, !self.table.selectedRowIndexes.isEmpty else { return false }
            onDelete(self.selectedIDs)
            return true
        }
        table.contextMenu = { [weak self] in
            guard let self else { return nil }
            return self.menu?(self.selectedIDs)
        }
        (table.headerView as? SkinnedHeaderView)?.sortState = { [weak self] in (self?.sortColumn, self?.ascending ?? true) }
        container.onWidthChange = { [weak self] old, new in
            guard let self else { return }
            let widths = SkinnedListController.resized(self.table.tableColumns.map(\.width), from: old, to: new,
                                                       mode: PersistenceManager.shared.state.libraryColumnResizing, sorted: self.sortColumn)
            for (col, width) in zip(self.table.tableColumns, widths) where col.width != width { col.width = width }
        }
        skinChange = SkinManager.shared.skinDidChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.container.applyTheme() }
    }

    var selectedIDs: [AnyHashable] { table.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].id : nil } }

    func setItems(_ newItems: [Item]) {
        let changed = newItems.count != source.count || zip(newItems, source).contains { $0.id != $1.id || $0.values != $1.values }
        guard changed else { return }
        let selected = Set(selectedIDs)
        source = newItems
        resort()
        setSelection(selected)
    }

    func setSelection(_ ids: Set<AnyHashable>) {
        let indexes = IndexSet(items.indices.filter { ids.contains(items[$0].id) })
        guard indexes != table.selectedRowIndexes else { return }
        updatingSelection = true
        table.selectRowIndexes(indexes, byExtendingSelection: false)
        updatingSelection = false
    }

    /// gen_ml Column resizing when the list's width changes: 0 Normal (columns keep their widths),
    /// 1 Selected column only (the sorted column, else the last, takes the difference), 2 Proportional (all scale)
    static func resized(_ widths: [CGFloat], from old: CGFloat, to new: CGFloat, mode: Int, sorted: Int?) -> [CGFloat] {
        guard old > 0, !widths.isEmpty else { return widths }
        switch mode {
        case 1:
            var result = widths
            let i = sorted.flatMap { widths.indices.contains($0) ? $0 : nil } ?? widths.count - 1
            result[i] = max(16, result[i] + new - old)
            return result
        case 2: return widths.map { max(16, $0 * new / old) }
        default: return widths
        }
    }

    /// Stable sort on the shown text (numbers compare as numbers: "9" < "10", "4:58" < "10:01")
    static func sorted(_ items: [Item], column: Int?, ascending: Bool, pinsFirstRow: Bool) -> [Item] {
        guard let column else { return items }
        let pinned = pinsFirstRow ? Array(items.prefix(1)) : []
        let rest = pinsFirstRow ? Array(items.dropFirst()) : items
        let sorted = rest.enumerated().sorted { a, b in
            let r = a.element.values[column].localizedStandardCompare(b.element.values[column])
            if r == .orderedSame { return a.offset < b.offset }
            return ascending ? r == .orderedAscending : r == .orderedDescending
        }.map(\.element)
        return pinned + sorted
    }

    private func resort() {
        items = SkinnedListController.sorted(source, column: sortColumn, ascending: ascending, pinsFirstRow: pinsFirstRow)
        table.reloadData()
        container.needsLayout = true
    }

    /// gen_ml: the same column again reverses; another column keeps the direction
    func clickedHeader(_ column: Int) {
        if sortColumn == column { ascending.toggle() } else { sortColumn = column }
        UserDefaults.standard.set(columns[column].title, forKey: defaultsKey + ".sort")
        UserDefaults.standard.set(ascending, forKey: defaultsKey + ".ascending")
        let selected = Set(selectedIDs)
        resort()
        setSelection(selected)
        table.headerView?.needsDisplay = true
    }

    @objc func doubleClicked() {
        guard table.clickedRow >= 0 else { return }
        activate(shift: NSEvent.modifierFlags.contains(.shift))
    }

    private func activate(shift: Bool) {
        let ids = selectedIDs
        if !ids.isEmpty { onActivate?(ids, shift) }
    }

    // MARK: NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let index = tableView.tableColumns.firstIndex(of: tableColumn) else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? SkinnedCell) ?? SkinnedCell(identifier: id)
        cell.label.stringValue = items[row].values[index]
        cell.label.alignment = columns[index].alignment
        cell.label.textColor = table.textColor(row: row)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SkinnedRowView() }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        if let index = tableView.tableColumns.firstIndex(of: tableColumn) { clickedHeader(index) }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        table.refreshColors()
        if !updatingSelection { onSelection?(selectedIDs) }
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        items[row].url as NSURL?
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        items[row].values.first
    }
}

// MARK: - Table, rows, cells

final class SkinnedTableView: NSTableView {
    var onActivate: ((Bool) -> Void)?
    var onDelete: (() -> Bool)?
    var contextMenu: (() -> NSMenu?)?
    private var keyObservers: [NSObjectProtocol] = []

    /// Winamp draws the selection bar in the "active" colours only while the list has the focus
    var isActive: Bool { window?.isKeyWindow == true && window?.firstResponder === self }

    func textColor(row: Int) -> NSColor {
        let theme = GenexTheme.current
        guard selectedRowIndexes.contains(row) else { return theme.ns(.itemForeground) }
        return theme.ns(isActive ? .selectionText : .inactiveSelectionText)
    }

    func refreshColors() {
        enumerateAvailableRowViews { rowView, row in
            rowView.needsDisplay = true
            for case let cell as SkinnedCell in rowView.subviews { cell.label.textColor = self.textColor(row: row) }
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onActivate?(event.modifierFlags.contains(.shift)) // Return, keypad Enter
        case 51, 117: if onDelete?() != true { super.keyDown(with: event) } // Delete, Forward Delete
        default: super.keyDown(with: event)
        }
    }

    /// Right-click selects the row under the mouse first, as Windows does
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        return contextMenu?()
    }

    override func becomeFirstResponder() -> Bool { defer { refreshColors() }; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { defer { refreshColors() }; return super.resignFirstResponder() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: window, queue: .main) { [weak self] _ in self?.refreshColors() }
        }
    }
}

final class SkinnedRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let active = (superview as? SkinnedTableView)?.isActive ?? false
        GenexTheme.current.ns(active ? .selectionBackground : .inactiveSelectionBackground).setFill()
        bounds.fill()
    }
}

final class SkinnedCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.font = SkinnedListContainer.font
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = true
        label.autoresizingMask = [.width]
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 2, y: 0, width: max(0, bounds.width - 4), height: bounds.height)
    }
}

// MARK: - Header (skinnedheader.cpp)

final class SkinnedHeaderView: NSTableHeaderView {
    var sortState: (() -> (column: Int?, ascending: Bool))?
    private var pressedColumn = -1

    override func draw(_ dirtyRect: NSRect) {
        let theme = GenexTheme.current
        theme.ns(.headerEmpty).setFill()
        bounds.fill()
        guard let table = tableView else { return }
        let sort = sortState?()
        for i in table.tableColumns.indices {
            drawItem(headerRect(ofColumn: i), title: table.tableColumns[i].title, pressed: i == pressedColumn,
                     sortAscending: sort?.column == i ? sort?.ascending : nil, theme: theme)
        }
    }

    private func drawItem(_ r: NSRect, title: String, pressed: Bool, sortAscending: Bool?, theme: GenexTheme) {
        func line(_ rect: NSRect, _ slot: GenexTheme.Slot) { theme.ns(slot).setFill(); rect.fill() }
        line(r, .headerBackground)
        let lightSlot: GenexTheme.Slot = pressed ? .headerFrameBottom : .headerFrameTop
        line(NSRect(x: r.minX, y: r.minY, width: r.width, height: 1), lightSlot)
        line(NSRect(x: r.minX, y: r.minY, width: 1, height: r.height), lightSlot)
        line(NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height), .headerFrameBottom)
        line(NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1), .headerFrameBottom)
        if !pressed {
            line(NSRect(x: r.maxX - 2, y: r.minY + 1, width: 1, height: r.height - 2), .headerFrameMiddle)
            line(NSRect(x: r.minX + 1, y: r.maxY - 2, width: r.width - 2, height: 1), .headerFrameMiddle)
        }
        let shift: CGFloat = pressed ? 1 : 0
        var textRight = r.maxX - 5 + shift
        // Sort arrow at the right, as gen_ml draws it when there is room
        if let ascending = sortAscending, r.width > 16 + 7 + 8 {
            let a = NSRect(x: r.maxX - 8 - 7, y: r.midY - 2, width: 7, height: 4)
            let path = NSBezierPath()
            if ascending {
                path.move(to: NSPoint(x: a.minX, y: a.maxY)); path.line(to: NSPoint(x: a.maxX, y: a.maxY)); path.line(to: NSPoint(x: a.midX, y: a.minY))
            } else {
                path.move(to: NSPoint(x: a.minX, y: a.minY)); path.line(to: NSPoint(x: a.maxX, y: a.minY)); path.line(to: NSPoint(x: a.midX, y: a.maxY))
            }
            path.close()
            theme.ns(.headerText).setFill()
            path.fill()
            textRight = a.minX - 3
        }
        let textRect = NSRect(x: r.minX + 5 + shift, y: r.minY + 1, width: textRight - r.minX - 5 - shift, height: r.height - 2)
        guard textRect.width > 4 else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: SkinnedListContainer.font, .foregroundColor: theme.ns(.headerText), .paragraphStyle: style]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(with: NSRect(x: textRect.minX, y: textRect.midY - size.height / 2, width: textRect.width, height: size.height),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let column = self.column(at: point)
        // Not on a column edge (that drag resizes)
        if column >= 0, let table = tableView {
            let r = headerRect(ofColumn: column)
            if point.x > r.minX + 3, point.x < r.maxX - 3, table.tableColumns.indices.contains(column) {
                pressedColumn = column
                display()
            }
        }
        super.mouseDown(with: event)
        pressedColumn = -1
        needsDisplay = true
    }
}

// MARK: - Container: the table plus GENEX scrollbars (skinnedscrollwnd.cpp)

final class SkinnedListContainer: NSView {
    static let font = NSFont.systemFont(ofSize: 11)
    static let rowHeight: CGFloat = 13
    static let headerHeight: CGFloat = 16

    let scrollView = NSScrollView()
    let table = SkinnedTableView()
    let vbar = SkinnedScrollBar(vertical: true)
    let hbar = SkinnedScrollBar(vertical: false)
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        table.headerView = SkinnedHeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: SkinnedListContainer.headerHeight))
        table.rowHeight = SkinnedListContainer.rowHeight
        table.intercellSpacing = .zero
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.focusRingType = .none
        table.gridStyleMask = []
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.usesAutomaticRowHeights = false
        table.postsFrameChangedNotifications = true
        scrollView.documentView = table
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(scrollView)
        addSubview(vbar)
        addSubview(hbar)
        for (name, object) in [(NSView.boundsDidChangeNotification, scrollView.contentView as NSView), (NSView.frameDidChangeNotification, table)] {
            NotificationCenter.default.addObserver(self, selector: #selector(contentMoved), name: name, object: object)
        }
        let line = SkinnedListContainer.rowHeight
        vbar.onStep = { [weak self] lines, pages in self?.scroll(dx: 0, dy: CGFloat(lines) * line + CGFloat(pages) * ((self?.clipSize.height ?? 0) - line)) }
        hbar.onStep = { [weak self] lines, pages in self?.scroll(dx: CGFloat(lines) * 16 + CGFloat(pages) * ((self?.clipSize.width ?? 0) - 16), dy: 0) }
        vbar.onTrack = { [weak self] f in self?.scrollTo(x: nil, y: f) }
        hbar.onTrack = { [weak self] f in self?.scrollTo(x: f, y: nil) }
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyTheme() {
        let background = GenexTheme.current.ns(.itemBackground)
        table.backgroundColor = background
        scrollView.backgroundColor = background
        table.reloadData()
        for view in [self, table, table.headerView, vbar, hbar] as [NSView?] { view?.needsDisplay = true }
    }

    private var clipSize: NSSize { scrollView.contentView.bounds.size }
    private var documentSize: NSSize { table.frame.size }

    @objc private func contentMoved() { needsLayout = true; updateBars() }

    /// The list got wider or narrower (old, new width): Preferences ▸ Library ▸ Column resizing
    var onWidthChange: ((CGFloat, CGFloat) -> Void)?
    private var lastWidth: CGFloat = 0

    override func layout() {
        super.layout()
        if lastWidth > 0, bounds.width > 0, bounds.width != lastWidth { onWidthChange?(lastWidth, bounds.width) }
        if bounds.width > 0 { lastWidth = bounds.width }
        // Scrollbars appear only when the content overflows; one may make room for the other
        let header = SkinnedListContainer.headerHeight
        let contentWidth = table.tableColumns.reduce(0) { $0 + $1.width }
        let contentHeight = CGFloat(table.numberOfRows) * table.rowHeight
        var showV = false, showH = false
        for _ in 0..<2 {
            showH = contentWidth > bounds.width - (showV ? 14 : 0)
            showV = contentHeight > bounds.height - header - (showH ? 14 : 0)
        }
        let w = bounds.width - (showV ? 14 : 0), h = bounds.height - (showH ? 14 : 0)
        scrollView.frame = NSRect(x: 0, y: 0, width: max(0, w), height: max(0, h))
        vbar.isHidden = !showV
        hbar.isHidden = !showH
        vbar.frame = NSRect(x: w, y: 0, width: 14, height: h)
        hbar.frame = NSRect(x: 0, y: h, width: w, height: 14)
        updateBars()
        needsDisplay = true
    }

    private func updateBars() {
        let clip = scrollView.contentView.bounds, doc = documentSize
        vbar.update(position: doc.height > clip.height ? clip.minY / (doc.height - clip.height) : 0, proportion: doc.height > 0 ? clip.height / doc.height : 1)
        hbar.update(position: doc.width > clip.width ? clip.minX / (doc.width - clip.width) : 0, proportion: doc.width > 0 ? clip.width / doc.width : 1)
    }

    func scroll(dx: CGFloat, dy: CGFloat) {
        let o = scrollView.contentView.bounds.origin
        setOrigin(NSPoint(x: o.x + dx, y: o.y + dy))
    }

    func scrollTo(x: CGFloat?, y: CGFloat?) {
        let o = scrollView.contentView.bounds.origin, clip = clipSize, doc = documentSize
        setOrigin(NSPoint(x: x.map { $0 * max(0, doc.width - clip.width) } ?? o.x, y: y.map { $0 * max(0, doc.height - clip.height) } ?? o.y))
    }

    private func setOrigin(_ p: NSPoint) {
        let clip = clipSize, doc = documentSize
        let origin = NSPoint(x: min(max(0, p.x), max(0, doc.width - clip.width)), y: min(max(0, p.y), max(0, doc.height - clip.height)))
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func draw(_ dirtyRect: NSRect) {
        // The square where both scrollbars meet
        if !vbar.isHidden && !hbar.isHidden {
            GenexTheme.current.ns(.scrollbarDeadArea).setFill()
            NSRect(x: vbar.frame.minX, y: hbar.frame.minY, width: 14, height: 14).fill()
        }
    }
}

/// A Winamp scrollbar from GENEX.BMP: 14 × 14 arrows, a thumb with 4 px ends and a 10 px grip kept,
/// a checkered track in the two scrollbar colours (the pressed side in the inverse colours).
final class SkinnedScrollBar: NSView {
    enum Part { case lessArrow, moreArrow, lessTrack, moreTrack, thumb }
    let vertical: Bool
    private(set) var position: CGFloat = 0
    private(set) var proportion: CGFloat = 1
    private var pressed: Part?
    /// (lines, pages) to scroll by
    var onStep: ((Int, Int) -> Void)?
    /// Thumb dragged: new position 0...1
    var onTrack: ((CGFloat) -> Void)?
    override var isFlipped: Bool { true }

    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(position: CGFloat, proportion: CGFloat) {
        let p = min(1, max(0, position)), q = min(1, max(0, proportion))
        guard p != self.position || q != self.proportion else { return }
        (self.position, self.proportion) = (p, q)
        needsDisplay = true
    }

    private var length: CGFloat { vertical ? bounds.height : bounds.width }
    private var trackLength: CGFloat { max(0, length - 28) }
    private var thumbLength: CGFloat { min(trackLength, max(18, (trackLength * proportion).rounded())) }
    private var thumbStart: CGFloat { 14 + ((trackLength - thumbLength) * position).rounded() }
    private func rect(_ start: CGFloat, _ length: CGFloat) -> NSRect {
        vertical ? NSRect(x: 0, y: start, width: 14, height: length) : NSRect(x: start, y: 0, width: length, height: 14)
    }
    private func along(_ event: NSEvent) -> CGFloat {
        let p = convert(event.locationInWindow, from: nil)
        return vertical ? p.y : p.x
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let theme = GenexTheme.current
        ctx.interpolationQuality = .none
        checker(ctx, rect(14, trackLength), theme.ns(.scrollbarForeground), theme.ns(.scrollbarBackground))
        let inverse = (theme.ns(.scrollbarInverseForeground), theme.ns(.scrollbarInverseBackground))
        if pressed == .lessTrack { checker(ctx, rect(14, thumbStart - 14), inverse.0, inverse.1) }
        if pressed == .moreTrack { checker(ctx, rect(thumbStart + thumbLength, length - 14 - thumbStart - thumbLength), inverse.0, inverse.1) }
        // Arrows: vertical at y 31, horizontal at y 45; less at x 0, more at x 14; pressed 28 px to the right
        let y: CGFloat = vertical ? 31 : 45
        if let less = GenexTheme.sprite(pressed == .lessArrow ? 28 : 0, y, 14, 14) { ctx.drawSkinImage(less, in: rect(0, 14)) }
        if let more = GenexTheme.sprite(pressed == .moreArrow ? 42 : 14, y, 14, 14) { ctx.drawSkinImage(more, in: rect(length - 14, 14)) }
        if trackLength >= 18, proportion < 1 { drawThumb(ctx) }
    }

    /// Thumb art: vertical at x 56 (pressed 70), y 31, 14 × 28; horizontal at x 84, y 31 (pressed 45), 28 × 14
    private func drawThumb(_ ctx: CGContext) {
        let isPressed = pressed == .thumb
        let source = vertical ? CGRect(x: isPressed ? 70 : 56, y: 31, width: 14, height: 28) : CGRect(x: 84, y: isPressed ? 45 : 31, width: 28, height: 14)
        let L = thumbLength, start = thumbStart
        let grip = min(10, max(0, L - 8)), fill = max(0, L - 8 - grip)
        // (offset in the 28 px art, length in the art, length on screen)
        let parts: [(CGFloat, CGFloat, CGFloat)] = [(0, 4, 4), (4, 5, (fill / 2).rounded(.down)), (9 + (10 - grip) / 2, grip, grip), (19, 5, fill - (fill / 2).rounded(.down)), (24, 4, 4)]
        var p = start
        for (offset, artLength, screenLength) in parts where screenLength > 0 && artLength > 0 {
            let piece = vertical ? CGRect(x: source.minX, y: source.minY + offset, width: 14, height: artLength)
                                 : CGRect(x: source.minX + offset, y: source.minY, width: artLength, height: 14)
            if let image = GenexTheme.sprite(piece.minX, piece.minY, piece.width, piece.height) { ctx.drawSkinImage(image, in: rect(p, screenLength)) }
            p += screenLength
        }
    }

    private func checker(_ ctx: CGContext, _ r: NSRect, _ fg: NSColor, _ bg: NSColor) {
        guard r.width > 0, r.height > 0 else { return }
        bg.setFill()
        r.fill()
        guard fg != bg else { return }
        fg.setFill()
        var y = r.minY
        while y < r.maxY {
            var x = r.minX + (Int(y) % 2 == 0 ? 0 : 1)
            while x < r.maxX { NSRect(x: x, y: y, width: 1, height: 1).fill(); x += 2 }
            y += 1
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard trackLength > 0 else { return }
        let at = along(event)
        let part: Part = at < 14 ? .lessArrow : at >= length - 14 ? .moreArrow
            : (proportion >= 1 ? .moreTrack : at < thumbStart ? .lessTrack : at >= thumbStart + thumbLength ? .moreTrack : .thumb)
        pressed = part
        needsDisplay = true
        defer { pressed = nil; needsDisplay = true }
        if part == .thumb {
            let grab = at - thumbStart
            while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), e.type != .leftMouseUp {
                let free = trackLength - thumbLength
                if free > 0 { onTrack?(min(1, max(0, (along(e) - grab - 14) / free))) }
            }
            return
        }
        // Arrows and the track repeat while held, like Windows: once now, then after a pause
        var mouse = at
        func step() {
            switch part {
            case .lessArrow: onStep?(-1, 0)
            case .moreArrow: onStep?(1, 0)
            case .lessTrack where mouse < thumbStart: onStep?(0, -1)
            case .moreTrack where mouse >= thumbStart + thumbLength: onStep?(0, 1)
            default: break
            }
            display()
        }
        step()
        NSEvent.startPeriodicEvents(afterDelay: 0.35, withPeriod: 0.05)
        defer { NSEvent.stopPeriodicEvents() }
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .periodic]) {
            if e.type == .leftMouseUp { break }
            if e.type == .leftMouseDragged { mouse = along(e) } else { step() }
        }
    }
}
