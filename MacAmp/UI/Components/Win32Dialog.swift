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

    /// Several labeled text fields (e.g. Edit bookmark: Title, File). Returns the values, or nil on Cancel / Esc.
    public static func promptFields(title: String, fields: [(label: String, value: String)], width: CGFloat = 400) -> [String]? {
        let model = FieldsModel(values: fields.map(\.value))
        let accepted = runModal(title: title, width: width) { finish in
            FieldsView(labels: fields.map(\.label), model: model, finish: finish)
        }
        return accepted ? model.values : nil
    }

    /// Asks a yes/no question. Returns true for the confirm button.
    public static func confirm(title: String, message: String, confirmTitle: String = "OK", cancelTitle: String = "Cancel") -> Bool {
        runModal(title: title, width: 340) { finish in
            ConfirmView(message: message, confirmTitle: confirmTitle, cancelTitle: cancelTitle, finish: finish)
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
                    Win32Button("OK", isDefault: true) { finish(true) }
                    Win32Button("Cancel") { finish(false) }
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
        let hosting = NSHostingView(rootView: content(finish).frame(width: width).fixedSize(horizontal: false, vertical: true))
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
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
                    Win32Button(okTitle, isDefault: true) { finish(true) }
                    Win32Button("Cancel") { finish(false) }
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
        let cancelTitle: String
        let finish: (Bool) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(Win32Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Spacer()
                    Win32Button(confirmTitle, isDefault: true) { finish(true) }
                    Win32Button(cancelTitle) { finish(false) }
                }
            }
            .padding(12)
            .background(Win32Colors.dialogBg)
        }
    }
}
