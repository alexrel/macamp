import Cocoa
import SwiftUI

/// Small modal Win32-style dialogs (text prompt, Yes/No confirmation) used instead of NSAlert,
/// so every MacAmp dialog shares the classic look of Preferences and File Info.
public enum Win32Dialog {
    /// Asks for a line of text. Returns nil on Cancel / Esc.
    public static func prompt(title: String, message: String, defaultValue: String = "", okTitle: String = "OK", width: CGFloat = 340) -> String? {
        let model = PromptModel(text: defaultValue)
        let accepted = runModal(title: title, width: width) { finish in
            PromptView(message: message, okTitle: okTitle, model: model, finish: finish)
        }
        return accepted ? model.text : nil
    }

    /// Winamp's "Open location": an address typed or picked from the ones entered before. Nil on Cancel / Esc.
    static func promptLocation(history: [String]) -> String? {
        let model = PromptModel(text: "")
        let accepted = runModal(title: "Open location", width: 296) { finish in
            LocationView(history: history, model: model, finish: finish)
        }
        return accepted ? model.text : nil
    }

    /// Several labeled text fields (e.g. Edit bookmark: Title, File). Returns the values, or nil on Cancel / Esc.
    public static func promptFields(title: String, fields: [(label: String, value: String)], width: CGFloat = 400) -> [String]? {
        let model = FieldsModel(values: fields.map(\.value))
        let accepted = runModal(title: title, width: width) { finish in
            FieldsView(labels: fields.map(\.label), model: model, finish: finish)
        }
        return accepted ? model.values : nil
    }

    /// A search box over a long list (MilkDrop's thousands of presets): type to filter, ↑ ↓ to pick, Return or a
    /// double click to take it. Returns the index into `items`, or nil on Cancel / Esc.
    static func find(title: String, prompt: String, items: [String], current: Int?) -> Int? {
        let model = FindModel(items: items, current: current)
        // The search field keeps focus; the arrows move through the list as in Jump to file
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case AppConstants.KeyCodes.upArrow: model.move(by: -1)
            case AppConstants.KeyCodes.downArrow: model.move(by: 1)
            case AppConstants.KeyCodes.pageUp: model.move(by: -findPageStep)
            case AppConstants.KeyCodes.pageDown: model.move(by: findPageStep)
            default: return event
            }
            return nil
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        let accepted = runModal(title: title, width: 420) { finish in
            FindView(prompt: prompt, model: model, finish: finish)
        }
        return accepted ? model.selected : nil
    }

    /// Rows Page Up / Page Down move in the find list
    private static let findPageStep = 10

    /// The items holding every word of the query, in any case and order ("ripples liquid" finds "Liquid Ripples/…")
    static func matches(_ query: String, in items: [String]) -> [Int] {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return Array(items.indices) }
        return items.indices.filter { index in words.allSatisfy { items[index].localizedCaseInsensitiveContains($0) } }
    }

    private final class FindModel: ObservableObject {
        let items: [String]
        @Published var query = "" {
            didSet {
                matches = Win32Dialog.matches(query, in: items)
                if selected.map({ !matches.contains($0) }) ?? true { selected = matches.first }
            }
        }
        @Published private(set) var matches: [Int]
        @Published var selected: Int?

        init(items: [String], current: Int?) {
            self.items = items
            matches = Array(items.indices)
            selected = current ?? (items.isEmpty ? nil : 0)
        }

        func move(by step: Int) {
            guard !matches.isEmpty else { return }
            let row = selected.flatMap { matches.firstIndex(of: $0) } ?? -1
            selected = matches[min(max(row + step, 0), matches.count - 1)]
        }
    }

    private struct FindView: View {
        let prompt: String
        @ObservedObject var model: FindModel
        let finish: (Bool) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(prompt)
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.text)
                    Win32TextField(text: $model.query, autoFocus: .cursor)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.matches, id: \.self) { index in
                                let isSelected = index == model.selected
                                Text(model.items[index])
                                    .font(.system(size: 11))
                                    .foregroundColor(isSelected ? .white : Win32Colors.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 6)
                                    .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                                    .background(isSelected ? Win32Colors.selectionBlue : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { model.selected = index; finish(true) }
                                    .onTapGesture { model.selected = index }
                                    .id(index)
                            }
                        }
                    }
                    .frame(height: 260)
                    .background(Color.white)
                    .win32Sunken()
                    .onAppear { if let index = model.selected { proxy.scrollTo(index, anchor: .center) } }
                    .onChange(of: model.selected) { _, index in if let index { proxy.scrollTo(index, anchor: .center) } }
                }
                HStack(spacing: 6) {
                    Text(model.query.isEmpty ? "\(model.items.count)" : "\(model.matches.count) / \(model.items.count)")
                        .font(.system(size: 11))
                        .foregroundColor(Win32Colors.textDisabled)
                    Spacer()
                    DialogButton("Load", isDefault: true) { finish(model.selected != nil) }
                    DialogButton("Cancel") { finish(false) }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(Win32Colors.dialogBg)
        }
    }

    /// Asks a yes/no question. Returns true for the confirm button.
    public static func confirm(title: String, message: String, confirmTitle: String = "OK", cancelTitle: String = "Cancel") -> Bool {
        runModal(title: title, width: 340) { finish in
            ConfirmView(message: message, confirmTitle: confirmTitle, cancelTitle: cancelTitle, finish: finish)
        }
    }

    static func inform(title: String, message: String) {
        _ = runModal(title: title, width: 340) { finish in
            ConfirmView(message: message, confirmTitle: "OK", cancelTitle: nil, finish: finish)
        }
    }

    private final class FieldsModel: ObservableObject {
        @Published var values: [String]
        init(values: [String]) { self.values = values }
    }

    private struct FieldsView: View {
        let labels: [String]
        @ObservedObject var model: FieldsModel
        let finish: (Bool) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(labels.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        Text(labels[i] + ":")
                            .font(.system(size: 11))
                            .foregroundColor(Win32Colors.text)
                            .frame(width: 36, alignment: .leading)
                        Win32TextField(text: $model.values[i], autoFocus: i == 0 ? .selectAll : .none)
                    }
                }
                HStack(spacing: 6) {
                    Spacer()
                    DialogButton("OK", isDefault: true) { finish(true) }
                    DialogButton("Cancel") { finish(false) }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(Win32Colors.dialogBg)
        }
    }

    private final class PromptModel: ObservableObject {
        @Published var text: String
        init(text: String) { self.text = text }
    }

    /// Escape closes (Cancel); Return is handled by the default button's keyboard shortcut.
    private final class DialogWindow: NSWindow {
        var onCancel: (() -> Void)?
        override func cancelOperation(_ sender: Any?) { onCancel?() }
        override var canBecomeKey: Bool { true }
    }

    private static func runModal<Content: View>(title: String, width: CGFloat, content: (@escaping (Bool) -> Void) -> Content) -> Bool {
        var result = false
        let window = DialogWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        let finish: (Bool) -> Void = { ok in
            result = ok
            NSApp.stopModal()
        }
        window.onCancel = { finish(false) }
        window.installScaledDialog(content(finish).frame(width: width).fixedSize(horizontal: false, vertical: true))
        window.center()
        // Above the player windows, which may be floating (Always On Top)
        window.level = .modalPanel

        let closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NSApp.stopModal()
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
        NotificationCenter.default.removeObserver(closeObserver)
        window.orderOut(nil)
        return result
    }

    private struct PromptView: View {
        let message: String
        let okTitle: String
        @ObservedObject var model: PromptModel
        let finish: (Bool) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Win32TextField(text: $model.text, autoFocus: .selectAll) // focused with text selected, like a Win32 prompt
                HStack(spacing: 6) {
                    Spacer()
                    DialogButton(okTitle, isDefault: true) { finish(true) }
                    DialogButton("Cancel") { finish(false) }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(Win32Colors.dialogBg)
        }
    }

    /// As Winamp 2.95's dialog: two lines of text, an editable drop-down of earlier addresses, Open / Cancel on the left
    private struct LocationView: View {
        let history: [String]
        @ObservedObject var model: PromptModel
        let finish: (Bool) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Enter an Internet location to open here:\nFor example: http://www.server.com/file.mp3") // verbatim: no link
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Win32TextField(text: $model.text, autoFocus: .selectAll)
                    .overlay(alignment: .trailing) {
                        Win32ComboBox(selection: $model.text, options: history.map { (value: $0, title: $0) }, label: "")
                    }
                HStack(spacing: 6) {
                    DialogButton("Open", isDefault: true) { finish(true) }
                    DialogButton("Cancel") { finish(false) }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(Win32Colors.dialogBg)
        }
    }

    private struct ConfirmView: View {
        let message: String
        let confirmTitle: String
        let cancelTitle: String?
        let finish: (Bool) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Spacer()
                    DialogButton(confirmTitle, isDefault: true) { finish(true) }
                    if let cancelTitle { DialogButton(cancelTitle) { finish(false) } }
                }
            }
            .padding(12)
            .background(Win32Colors.dialogBg)
        }
    }

    /// The dialogs' buttons are AppKit buttons drawn like Win32Button. AppKit runs their action while handling the click;
    /// a SwiftUI button's action goes through the main queue, which stays busy while a dialog opened from a SwiftUI
    /// action or a main-actor task is up, so OK / Cancel never fired (Preferences ▸ Bookmarks ▸ Edit).
    private struct DialogButton: NSViewRepresentable {
        let title: String
        var isDefault = false
        let action: () -> Void

        init(_ title: String, isDefault: Bool = false, action: @escaping () -> Void) {
            self.title = title
            self.isDefault = isDefault
            self.action = action
        }

        func makeNSView(context: Context) -> Win32PushButton { Win32PushButton(title: title, isDefault: isDefault) }
        func updateNSView(_ button: Win32PushButton, context: Context) { button.onPress = action }
        func sizeThatFits(_ proposal: ProposedViewSize, nsView: Win32PushButton, context: Context) -> CGSize? {
            CGSize(width: max(75, nsView.attributedTitle.size().width + 16), height: 23)
        }
    }
}

/// A push button in the Win32 look (raised bevel, black outline when it's the default, pressed shifts the text).
/// Return presses the default one, Esc the Cancel one (key equivalents, handled by AppKit).
final class Win32PushButton: NSButton {
    var onPress: (() -> Void)?
    private let isDefault: Bool

    init(title: String, isDefault: Bool) {
        self.isDefault = isDefault
        super.init(frame: NSRect(x: 0, y: 0, width: 75, height: 23))
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none // Win32 has no glow around the focused button
        font = .systemFont(ofSize: 11)
        keyEquivalent = isDefault ? "\r" : (title == "Cancel" ? "\u{1b}" : "")
        target = self
        action = #selector(press)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func press() { onPress?() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let face = NSColor(srgbRed: 212 / 255, green: 208 / 255, blue: 200 / 255, alpha: 1)
        let shadow = NSColor(srgbRed: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1)
        let dark = NSColor(srgbRed: 64 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1)
        var r = bounds
        face.setFill(); r.fill()
        if isDefault { NSColor.black.setFill(); r.frame(withWidth: 1); r = r.insetBy(dx: 1, dy: 1) }
        func edge(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) { c.setFill(); NSRect(x: x, y: y, width: w, height: h).fill() }
        let pressed = isHighlighted
        if pressed {
            shadow.setFill(); r.frame(withWidth: 1)
        } else {
            edge(r.minX, r.minY, r.width, 1, .white); edge(r.minX, r.minY, 1, r.height, .white)
            edge(r.minX, r.maxY - 1, r.width, 1, dark); edge(r.maxX - 1, r.minY, 1, r.height, dark)
            edge(r.minX + 1, r.maxY - 2, r.width - 2, 1, shadow); edge(r.maxX - 2, r.minY + 1, 1, r.height - 2, shadow)
        }
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black])
        let size = text.size()
        let shift: CGFloat = pressed ? 1 : 0
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2 + shift, y: (bounds.height - size.height) / 2 + shift))
    }
}
