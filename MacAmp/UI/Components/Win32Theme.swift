import SwiftUI
import AppKit

// MARK: - Win32 Classic Theme Colors
public enum Win32Colors {
    public static let dialogBg = Color(red: 212/255, green: 208/255, blue: 200/255) // #D4D0C8
    public static let windowBg = Color.white
    public static let borderLight = Color.white
    public static let borderShadow = Color(red: 128/255, green: 128/255, blue: 128/255) // #808080
    public static let borderDark = Color(red: 64/255, green: 64/255, blue: 64/255) // #404040
    public static let selectionBlue = Color(red: 10/255, green: 36/255, blue: 106/255) // #0A246A
    public static let selectionHighlight = Color(red: 49/255, green: 106/255, blue: 197/255) // #316AC5
    public static let text = Color.black
    public static let textDisabled = Color(red: 128/255, green: 128/255, blue: 128/255)
}

// MARK: - Win32 3D Borders
public struct Win32SunkenBorder: ViewModifier {
    public var cornerRadius: CGFloat = 0
    public func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    // Top and Left dark shadows
                    VStack(spacing: 0) {
                        Rectangle().fill(Win32Colors.borderShadow).frame(height: 1)
                        Rectangle().fill(Win32Colors.borderDark).frame(height: 1)
                        Spacer()
                    }
                    HStack(spacing: 0) {
                        Rectangle().fill(Win32Colors.borderShadow).frame(width: 1)
                        Rectangle().fill(Win32Colors.borderDark).frame(width: 1)
                        Spacer()
                    }
                    // Bottom and Right highlights
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(Win32Colors.dialogBg).frame(height: 1)
                        Rectangle().fill(Win32Colors.borderLight).frame(height: 1)
                    }
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(Win32Colors.dialogBg).frame(width: 1)
                        Rectangle().fill(Win32Colors.borderLight).frame(width: 1)
                    }
                }
            )
    }
}

public struct Win32RaisedBorder: ViewModifier {
    public var isPressed: Bool = false
    public func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    if isPressed {
                        VStack(spacing: 0) {
                            Rectangle().fill(Win32Colors.borderDark).frame(height: 1)
                            Rectangle().fill(Win32Colors.borderShadow).frame(height: 1)
                            Spacer()
                        }
                        HStack(spacing: 0) {
                            Rectangle().fill(Win32Colors.borderDark).frame(width: 1)
                            Rectangle().fill(Win32Colors.borderShadow).frame(width: 1)
                            Spacer()
                        }
                    } else {
                        // Top and Left highlights
                        VStack(spacing: 0) {
                            Rectangle().fill(Win32Colors.borderLight).frame(height: 1)
                            Rectangle().fill(Win32Colors.dialogBg).frame(height: 1)
                            Spacer()
                        }
                        HStack(spacing: 0) {
                            Rectangle().fill(Win32Colors.borderLight).frame(width: 1)
                            Rectangle().fill(Win32Colors.dialogBg).frame(width: 1)
                            Spacer()
                        }
                        // Bottom and Right shadows
                        VStack(spacing: 0) {
                            Spacer()
                            Rectangle().fill(Win32Colors.borderShadow).frame(height: 1)
                            Rectangle().fill(Win32Colors.borderDark).frame(height: 1)
                        }
                        HStack(spacing: 0) {
                            Spacer()
                            Rectangle().fill(Win32Colors.borderShadow).frame(width: 1)
                            Rectangle().fill(Win32Colors.borderDark).frame(width: 1)
                        }
                    }
                }
            )
    }
}

public extension View {
    func win32Sunken() -> some View {
        self.modifier(Win32SunkenBorder())
    }
    func win32Raised(isPressed: Bool = false) -> some View {
        self.modifier(Win32RaisedBorder(isPressed: isPressed))
    }
}

// MARK: - Win32 Classic Button
public struct Win32Button: View {
    public let title: String
    public var width: CGFloat? = 75
    public var height: CGFloat = 23
    /// Default (Enter) button: Win32 draws it with an extra black outline
    public var isDefault: Bool = false
    public let action: () -> Void
    
    @State private var isPressed: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    
    public init(_ title: String, width: CGFloat? = 75, height: CGFloat = 23, isDefault: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.width = width
        self.height = height
        self.isDefault = isDefault
        self.action = action
    }
    
    public var body: some View {
        let button = Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundColor(isEnabled ? Win32Colors.text : Win32Colors.textDisabled)
                .shadow(color: isEnabled ? .clear : Win32Colors.borderLight, radius: 0, x: 1, y: 1) // etched disabled text
                .padding(.horizontal, 8)
                .frame(width: width, height: height)
                .background(Win32Colors.dialogBg)
                .win32Raised(isPressed: isPressed)
                .overlay(Rectangle().stroke(Color.black, lineWidth: isDefault ? 1 : 0))
        }
        .buttonStyle(Win32ButtonStyle(isPressed: $isPressed))
        .focusable(false)
        if isDefault {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }
}

public struct Win32ButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Win32 GroupBox
public struct Win32GroupBox<Content: View>: View {
    public let label: String
    public let content: Content
    
    public init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Etched outer rectangle with 1px dark shadow and 1px light highlight
            ZStack {
                RoundedRectangle(cornerRadius: 1)
                    .stroke(Win32Colors.borderShadow, lineWidth: 1)
                RoundedRectangle(cornerRadius: 1)
                    .stroke(Win32Colors.borderLight, lineWidth: 1)
                    .offset(x: 1, y: 1)
            }
            .padding(.top, 6)
            
            // Label with background matching dialogBg to cleanly interrupt the top etched border
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
                .padding(.horizontal, 4)
                .background(Win32Colors.dialogBg)
                .padding(.leading, 8)
                .zIndex(2)
            
            // GroupBox Content
            // Win32 group boxes leave a clear gap between the caption and the first control
            content
                .padding(.horizontal, 10)
                .padding(.top, 22)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Win32 Checkbox
public struct Win32Checkbox: View {
    public let label: String
    @Binding public var isOn: Bool
    
    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }
    
    public var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(alignment: .center, spacing: 6) {
                ZStack {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 13, height: 13)
                        .win32Sunken()
                    
                    if isOn {
                        Path { path in
                            path.move(to: CGPoint(x: 2.5, y: 6.5))
                            path.addLine(to: CGPoint(x: 5.5, y: 10.0))
                            path.addLine(to: CGPoint(x: 10.5, y: 3.0))
                        }
                        .stroke(Color.black, style: StrokeStyle(lineWidth: 1.8, lineCap: .square, lineJoin: .miter))
                        .frame(width: 13, height: 13)
                    }
                }
                
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Win32 Radio Button
public struct Win32RadioButton: View {
    public let label: String
    public let isSelected: Bool
    public let action: () -> Void
    
    public init(_ label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Win32Colors.borderShadow, lineWidth: 1)
                        )
                    
                    if isSelected {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 4.5, height: 4.5)
                    }
                }
                
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Win32 Number Field
public struct Win32NumberField: View {
    @Binding public var value: Int
    public var width: CGFloat = 32
    
    public init(value: Binding<Int>, width: CGFloat = 32) {
        self._value = value
        self.width = width
    }
    
    public var body: some View {
        // The shared Win32TextField, centered and digits-only
        Win32TextField(text: Binding(
            get: { String(value) },
            set: { newText in
                let digits = newText.filter(\.isNumber)
                value = Int(digits) ?? 0
            }
        ), height: 18, alignment: .center, monospaced: true)
            .frame(width: width)
    }
}

// MARK: - Win32 Tab Control (property sheet)
/// Tabs and page drawn as one control, like a Win32 property sheet: the selected tab is taller,
/// regular weight, and opens into the page (no border line under it); other tabs sit 2 px lower.
public struct Win32TabView<T: Hashable & RawRepresentable, Content: View>: View where T.RawValue == String {
    public let tabs: [T]
    @Binding public var selectedTab: T
    public let content: Content

    private let tabHeight: CGFloat = 20

    public init(tabs: [T], selectedTab: Binding<T>, @ViewBuilder content: () -> Content) {
        self.tabs = tabs
        self._selectedTab = selectedTab
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    tabButton(tab)
                }
                // Page top edge continues to the right of the tabs
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle().fill(Win32Colors.borderLight).frame(height: 1)
                }
                .frame(height: tabHeight)
            }
            .padding(.leading, 2)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Win32Colors.dialogBg)
                .overlay(pageBorder)
        }
    }

    private func tabButton(_ tab: T) -> some View {
        let isSelected = tab == selectedTab
        return Button(action: { selectedTab = tab }) {
            Text(tab.rawValue)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, isSelected ? 10 : 8)
                .frame(height: isSelected ? tabHeight : tabHeight - 2)
                .background(Win32Colors.dialogBg)
                .overlay(tabBorder(isSelected: isSelected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .padding(.horizontal, isSelected ? -2 : 0) // selected tab overlaps its neighbours by 2 px
        .zIndex(isSelected ? 1 : 0)
    }

    private func tabBorder(isSelected: Bool) -> some View {
        ZStack {
            // Top highlight (inset 1 px at the ends: Win32's clipped tab corners)
            VStack(spacing: 0) {
                Rectangle().fill(Win32Colors.borderLight).frame(height: 1).padding(.horizontal, 1)
                Spacer(minLength: 0)
                // Unselected tabs sit on the page's top edge; the selected one opens into the page
                Rectangle().fill(isSelected ? Win32Colors.dialogBg : Win32Colors.borderLight).frame(height: 1)
            }
            HStack(spacing: 0) {
                Rectangle().fill(Win32Colors.borderLight).frame(width: 1).padding(.top, 1)
                Spacer(minLength: 0)
                Rectangle().fill(Win32Colors.borderShadow).frame(width: 1).padding(.top, 1)
                Rectangle().fill(Win32Colors.borderDark).frame(width: 1).padding(.top, 2)
            }
        }
    }

    private var pageBorder: some View {
        ZStack {
            HStack(spacing: 0) {
                Rectangle().fill(Win32Colors.borderLight).frame(width: 1)
                Spacer(minLength: 0)
                Rectangle().fill(Win32Colors.borderShadow).frame(width: 1)
                Rectangle().fill(Win32Colors.borderDark).frame(width: 1)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle().fill(Win32Colors.borderShadow).frame(height: 1)
                Rectangle().fill(Win32Colors.borderDark).frame(height: 1)
            }
        }
    }
}

// MARK: - Small triangle glyph (◄ ►) drawn as a shape, so both directions have identical size
public struct Win32TriangleIcon: View {
    public enum Direction { case left, right }
    public let direction: Direction
    @Environment(\.isEnabled) private var isEnabled

    public init(_ direction: Direction) {
        self.direction = direction
    }

    public var body: some View {
        Path { path in
            if direction == .left {
                path.move(to: CGPoint(x: 4, y: 0)); path.addLine(to: CGPoint(x: 0, y: 4)); path.addLine(to: CGPoint(x: 4, y: 8))
            } else {
                path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 4, y: 4)); path.addLine(to: CGPoint(x: 0, y: 8))
            }
            path.closeSubpath()
        }
        .fill(isEnabled ? Win32Colors.text : Win32Colors.textDisabled)
        .frame(width: 4, height: 8)
    }
}

/// Win32 push button with a triangle glyph before/after the title (e.g. "◄ Prev", "Next ►").
public struct Win32ArrowButton: View {
    public let title: String
    public let direction: Win32TriangleIcon.Direction
    public var width: CGFloat? = 75
    public let action: () -> Void
    @State private var isPressed = false
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, direction: Win32TriangleIcon.Direction, width: CGFloat? = 75, action: @escaping () -> Void) {
        self.title = title
        self.direction = direction
        self.width = width
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if direction == .left { Win32TriangleIcon(.left) }
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(isEnabled ? Win32Colors.text : Win32Colors.textDisabled)
                if direction == .right { Win32TriangleIcon(.right) }
            }
            .frame(width: width, height: 23)
            .background(Win32Colors.dialogBg)
            .win32Raised(isPressed: isPressed)
        }
        .buttonStyle(Win32ButtonStyle(isPressed: $isPressed))
        .focusable(false)
    }
}

// MARK: - Win32 Text Field
/// Single-line edit box backed by a stock NSTextField, so the text doesn't jump when the field
/// gains focus (a SwiftUI plain TextField positions its field editor differently from the static text).
///
/// This is the only text input in MacAmp: dialogs, Track Info, Jump to File and number fields all use it.
public struct Win32TextField: View {
    public enum Focus { case none, cursor, selectAll }

    public let placeholder: String
    @Binding public var text: String
    public var height: CGFloat = 20
    public var alignment: NSTextAlignment = .natural
    public var monospaced: Bool = false
    /// Take keyboard focus when the window appears (search boxes, prompts)
    public var autoFocus: Focus = .none

    @Environment(\.isEnabled) private var isEnabled

    /// Gap between the sunken border and the text
    public static let textInset: CGFloat = 4

    public init(_ placeholder: String = "", text: Binding<String>, height: CGFloat = 20,
                alignment: NSTextAlignment = .natural, monospaced: Bool = false, autoFocus: Focus = .none) {
        self.placeholder = placeholder
        self._text = text
        self.height = height
        self.alignment = alignment
        self.monospaced = monospaced
        self.autoFocus = autoFocus
    }

    public var body: some View {
        // The field is one line tall; the sunken box around it centers it vertically
        Win32NSTextField(placeholder: placeholder, text: $text, isEnabled: isEnabled,
                         alignment: alignment, monospaced: monospaced, autoFocus: autoFocus)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Win32TextField.textInset)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(isEnabled ? Color.white : Win32Colors.dialogBg) // disabled edit boxes are gray in Win32
            .win32Sunken()
    }
}

struct Win32NSTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isEnabled: Bool
    var alignment: NSTextAlignment = .natural
    var monospaced: Bool = false
    var autoFocus: Win32TextField.Focus = .none

    func makeNSView(context: Context) -> NSTextField {
        // Stock cell on purpose: measured after real clicks and Tab focus, it keeps the text in place
        // (custom drawing/editor rects made it jump)
        let field = NSTextField()
        field.isEditable = true
        field.isSelectable = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = monospaced ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 11)
        field.alignment = alignment
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if autoFocus != .none {
            let selectAll = autoFocus == .selectAll
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                window.makeFirstResponder(field)
                if !selectAll, let editor = field.currentEditor() {
                    editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
                }
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text, field.currentEditor() == nil {
            field.stringValue = text
        }
        field.isEnabled = isEnabled
        field.textColor = isEnabled ? .black : NSColor(white: 128 / 255, alpha: 1)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            // Keep length limits applied by the binding (e.g. ID3v1's 30 chars) visible while typing
            if field.stringValue != text.wrappedValue {
                field.stringValue = text.wrappedValue
            }
        }
    }
}

// MARK: - Win32 Drop-down List (ComboBox, CBS_DROPDOWNLIST)
/// White sunken box with the current value and a raised ▼ button; opens a plain menu.
public struct Win32ComboBox<Value: Hashable>: View {
    @Binding public var selection: Value
    public let options: [(value: Value, title: String)]
    public var width: CGFloat?
    
    @Environment(\.isEnabled) private var isEnabled
    
    public init(selection: Binding<Value>, options: [(value: Value, title: String)], width: CGFloat? = nil) {
        self._selection = selection
        self.options = options
        self.width = width
    }
    
    private var currentTitle: String {
        options.first(where: { $0.value == selection })?.title ?? ""
    }
    
    public var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 0) {
                Text(currentTitle)
                    .font(.system(size: 11))
                    .foregroundColor(isEnabled ? Win32Colors.text : Win32Colors.textDisabled)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("▼")
                    .font(.system(size: 7))
                    .foregroundColor(isEnabled ? Win32Colors.text : Win32Colors.textDisabled)
                    .frame(width: 16, height: 16)
                    .background(Win32Colors.dialogBg)
                    .win32Raised()
                    .padding(.trailing, 2)
            }
            .frame(width: width, height: 20)
            .background(isEnabled ? Color.white : Win32Colors.dialogBg)
            .win32Sunken()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
    
    private func showMenu() {
        let menu = NSMenu()
        var selectedItem: NSMenuItem?
        for option in options {
            let item = Win32ClosureMenuItem(title: option.title) { selection = option.value }
            if option.value == selection {
                item.state = .on
                selectedItem = item
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: selectedItem, at: NSEvent.mouseLocation, in: nil)
    }
}

/// NSMenuItem that runs a closure (used by Win32 drop-down lists).
final class Win32ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        self.target = self
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func run() { handler() }
}

// MARK: - Win32 vertical trackbar with tick marks (TBS_VERT | TBS_AUTOTICKS)
/// Integer positions 0..<count, top to bottom, like Winamp's File icon / Playlist icon sliders.
/// AppKit-backed (mouseDown tracking loop) so press-and-drag is reliable inside dialogs.
public struct Win32VerticalTickSlider: NSViewRepresentable {
    @Binding public var position: Int
    public let count: Int
    public var height: CGFloat = 76
    /// Called once when the drag / click ends (expensive work belongs here, not in `position`'s setter)
    public var onCommit: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled

    public init(position: Binding<Int>, count: Int, height: CGFloat = 76, onCommit: (() -> Void)? = nil) {
        self._position = position
        self.count = max(1, count)
        self.height = height
        self.onCommit = onCommit
    }

    public func makeNSView(context: Context) -> Win32VerticalTickSliderView {
        Win32VerticalTickSliderView(frame: NSRect(x: 0, y: 0, width: Win32VerticalTickSliderView.width, height: height))
    }

    public func updateNSView(_ view: Win32VerticalTickSliderView, context: Context) {
        view.count = count
        view.position = position
        view.isEnabled = isEnabled
        view.onChange = { newValue in if newValue != position { position = newValue } }
        view.onCommit = onCommit
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: Win32VerticalTickSliderView, context: Context) -> CGSize? {
        CGSize(width: Win32VerticalTickSliderView.width, height: height)
    }
}

public final class Win32VerticalTickSliderView: NSView {
    static let width: CGFloat = 28
    private let thumbWidth: CGFloat = 20
    private let thumbHeight: CGFloat = 10

    var count = 10 { didSet { needsDisplay = true } }
    var position = 0 { didSet { if oldValue != position { needsDisplay = true } } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var onChange: ((Int) -> Void)?
    var onCommit: (() -> Void)?

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var step: CGFloat { count > 1 ? (bounds.height - thumbHeight) / CGFloat(count - 1) : 0 }

    private func position(at point: NSPoint) -> Int {
        guard count > 1, step > 0 else { return 0 }
        return min(count - 1, max(0, Int(((point.y - thumbHeight / 2) / step).rounded())))
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        func track(_ e: NSEvent) {
            let p = position(at: convert(e.locationInWindow, from: nil))
            if p != position {
                position = p
                onChange?(p)
            }
        }
        track(event)
        // Standard AppKit tracking loop: follow the mouse until the button is released
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            track(next)
            if next.type == .leftMouseUp { break }
        }
        onCommit?()
    }

    public override func draw(_ dirtyRect: NSRect) {
        let light = NSColor.white, shadow = NSColor(white: 128 / 255, alpha: 1), dark = NSColor(white: 64 / 255, alpha: 1)
        let face = NSColor(red: 212 / 255, green: 208 / 255, blue: 200 / 255, alpha: 1)
        let alpha: CGFloat = isEnabled ? 1 : 0.5

        // Sunken channel
        let channel = NSRect(x: thumbWidth / 2 - 2, y: 2, width: 4, height: bounds.height - 4)
        NSColor.white.withAlphaComponent(alpha).setFill(); channel.fill()
        shadow.withAlphaComponent(alpha).setFill()
        NSRect(x: channel.minX, y: channel.minY, width: channel.width, height: 1).fill()
        NSRect(x: channel.minX, y: channel.minY, width: 1, height: channel.height).fill()
        light.setFill()
        NSRect(x: channel.minX, y: channel.maxY - 1, width: channel.width, height: 1).fill()
        NSRect(x: channel.maxX - 1, y: channel.minY, width: 1, height: channel.height).fill()

        // Ticks
        NSColor.black.withAlphaComponent(alpha).setFill()
        for i in 0..<count {
            NSRect(x: thumbWidth + 3, y: (thumbHeight / 2 + CGFloat(i) * step).rounded(.down), width: 3, height: 1).fill()
        }

        // Raised thumb pointing at the ticks
        let y = (CGFloat(position) * step).rounded(.down)
        let tip = thumbWidth - 5
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: 0, y: y))
        outline.line(to: NSPoint(x: tip, y: y))
        outline.line(to: NSPoint(x: thumbWidth, y: y + thumbHeight / 2))
        outline.line(to: NSPoint(x: tip, y: y + thumbHeight))
        outline.line(to: NSPoint(x: 0, y: y + thumbHeight))
        outline.close()
        face.setFill(); outline.fill()
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: 0.5, y: y + thumbHeight - 0.5))
        highlight.line(to: NSPoint(x: 0.5, y: y + 0.5))
        highlight.line(to: NSPoint(x: tip, y: y + 0.5))
        highlight.line(to: NSPoint(x: thumbWidth - 0.5, y: y + thumbHeight / 2))
        light.setStroke(); highlight.lineWidth = 1; highlight.stroke()
        let lowlight = NSBezierPath()
        lowlight.move(to: NSPoint(x: 0.5, y: y + thumbHeight - 0.5))
        lowlight.line(to: NSPoint(x: tip, y: y + thumbHeight - 0.5))
        lowlight.line(to: NSPoint(x: thumbWidth - 0.5, y: y + thumbHeight / 2))
        dark.setStroke(); lowlight.lineWidth = 1; lowlight.stroke()
    }
}

// MARK: - Win32 Trackbar (slider)
/// Sunken groove with a raised rectangular thumb, as in Win32 trackbar controls.
public struct Win32Slider: View {
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public var step: Double
    
    @Environment(\.isEnabled) private var isEnabled
    private let thumbWidth: CGFloat = 11
    private let thumbHeight: CGFloat = 21
    
    public init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 0) {
        self._value = value
        self.range = range
        self.step = step
    }
    
    public var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - thumbWidth)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white)
                    .frame(height: 4)
                    .win32Sunken()
                    .padding(.horizontal, thumbWidth / 2)
                Rectangle()
                    .fill(Win32Colors.dialogBg)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .win32Raised()
                    .offset(x: CGFloat(fraction) * travel)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isEnabled, span > 0 else { return }
                let f = min(1, max(0, Double((drag.location.x - thumbWidth / 2) / travel)))
                var newValue = range.lowerBound + f * span
                if step > 0 {
                    newValue = (newValue / step).rounded() * step
                }
                value = min(range.upperBound, max(range.lowerBound, newValue))
            })
        }
        .frame(height: thumbHeight)
        .opacity(isEnabled ? 1 : 0.6)
    }
}
