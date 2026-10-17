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
    public let action: () -> Void
    
    @State private var isPressed: Bool = false
    
    public init(_ title: String, width: CGFloat? = 75, height: CGFloat = 23, action: @escaping () -> Void) {
        self.title = title
        self.width = width
        self.height = height
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(Win32Colors.text)
                .padding(.horizontal, 8)
                .frame(width: width, height: height)
                .background(Win32Colors.dialogBg)
                .win32Raised(isPressed: isPressed)
        }
        .buttonStyle(Win32ButtonStyle(isPressed: $isPressed))
        .focusable(false)
    }
}

public struct Win32ButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .onChange(of: configuration.isPressed) { pressed in
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
            content
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 8)
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
        TextField("", value: $value, formatter: NumberFormatter())
            .font(.system(size: 11, design: .monospaced))
            .multilineTextAlignment(.center)
            .textFieldStyle(.plain)
            .frame(width: width, height: 18)
            .background(Color.white)
            .win32Sunken()
    }
}

// MARK: - Win32 Tab Header
public struct Win32TabHeader<T: Hashable & RawRepresentable>: View where T.RawValue == String {
    public let tabs: [T]
    @Binding public var selectedTab: T
    
    public init(tabs: [T], selectedTab: Binding<T>) {
        self.tabs = tabs
        self._selectedTab = selectedTab
    }
    
    public var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                let isSelected = (selectedTab == tab)
                Button(action: { selectedTab = tab }) {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                        .foregroundColor(Win32Colors.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, isSelected ? 4 : 3)
                        .background(Win32Colors.dialogBg)
                        .overlay(
                            ZStack {
                                VStack(spacing: 0) {
                                    Rectangle().fill(Win32Colors.borderLight).frame(height: 1)
                                    Spacer()
                                    if !isSelected {
                                        Rectangle().fill(Win32Colors.borderShadow).frame(height: 1)
                                    }
                                }
                                HStack(spacing: 0) {
                                    Rectangle().fill(Win32Colors.borderLight).frame(width: 1)
                                    Spacer()
                                    Rectangle().fill(Win32Colors.borderDark).frame(width: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .offset(y: isSelected ? 1 : 0)
                .zIndex(isSelected ? 2 : 1)
            }
            Spacer()
        }
        .overlay(
            VStack {
                Spacer()
                Rectangle().fill(Win32Colors.borderLight).frame(height: 1)
            },
            alignment: .bottom
        )
    }
}

// MARK: - Win32 Text Field
public struct Win32TextField: View {
    public let placeholder: String
    @Binding public var text: String
    public var height: CGFloat = 20
    
    public init(_ placeholder: String = "", text: Binding<String>, height: CGFloat = 20) {
        self.placeholder = placeholder
        self._text = text
        self.height = height
    }
    
    public var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 11))
            .textFieldStyle(.plain)
            .padding(.horizontal, 4)
            .frame(height: height)
            .background(Color.white)
            .win32Sunken()
    }
}
