import Cocoa
import Carbon.HIToolbox

/// One system-wide hotkey. `GlobalHotkeysController.hotkeys` is the single source of truth:
/// it is what gets registered and what Preferences displays.
public struct GlobalHotkey {
    public let action: String
    /// Mac-style label, e.g. "⌃⌥X"
    public let label: String
    let keyCode: UInt32
    let perform: () -> Void
}

/// Classic Winamp global hotkeys (Ctrl+Alt+key on Windows, ⌃⌥+key on the Mac), working while MacAmp is in the background.
///
/// Uses Carbon `RegisterEventHotKey`: macOS delivers only the registered combinations to the app, so no
/// Accessibility / Input Monitoring permission is needed, and the keystroke is consumed instead of also
/// reaching the frontmost app (an `NSEvent` global monitor needed Accessibility and only observed keys).
public final class GlobalHotkeysController: ObservableObject {
    public static let shared = GlobalHotkeysController()

    @Published public var isEnabled: Bool {
        didSet {
            PersistenceManager.shared.state.isGlobalHotkeysEnabled = isEnabled
            PersistenceManager.shared.saveSession()
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    /// Combinations another app already owns (registration failed); shown in Preferences.
    @Published public private(set) var unavailableHotkeys: [String] = []

    public static let modifierLabel = "⌃⌥"

    public let hotkeys: [GlobalHotkey] = {
        let coord = { PlayerCoordinator.shared }
        func key(_ action: String, _ symbol: String, _ code: Int, _ perform: @escaping () -> Void) -> GlobalHotkey {
            GlobalHotkey(action: action, label: GlobalHotkeysController.modifierLabel + symbol, keyCode: UInt32(code), perform: perform)
        }
        return [
            key("Play", "X", kVK_ANSI_X) { coord().handlePlay() },
            key("Play / Pause", "C", kVK_ANSI_C) { coord().handlePlayPause() },
            key("Play / Pause", "Space", kVK_Space) { coord().handlePlayPause() },
            key("Stop", "V", kVK_ANSI_V) { coord().handleStop() },
            key("Previous Track", "Z", kVK_ANSI_Z) { coord().handlePrev() },
            key("Previous Track", "←", kVK_LeftArrow) { coord().handlePrev() },
            key("Next Track", "B", kVK_ANSI_B) { coord().handleNext() },
            key("Next Track", "→", kVK_RightArrow) { coord().handleNext() },
            key("Volume Up", "↑", kVK_UpArrow) { coord().increaseVolume(by: 0.05) },
            key("Volume Down", "↓", kVK_DownArrow) { coord().decreaseVolume(by: 0.05) },
            key("Toggle Mute", "M", kVK_ANSI_M) { coord().toggleMute() }
        ]
    }()

    /// Rows for Preferences: one per action, alternatives joined ("⌃⌥C  or  ⌃⌥Space").
    public var displayRows: [(action: String, shortcut: String)] {
        var rows: [(action: String, shortcut: String)] = []
        for hotkey in hotkeys {
            if let i = rows.firstIndex(where: { $0.action == hotkey.action }) {
                rows[i].shortcut += "  or  " + hotkey.label
            } else {
                rows.append((hotkey.action, hotkey.label))
            }
        }
        return rows
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x4D414D50 // 'MAMP'

    public var registeredHotkeyCount: Int { hotKeyRefs.count }

    private init() {
        self.isEnabled = PersistenceManager.shared.state.isGlobalHotkeysEnabled
    }

    deinit {
        stopMonitoring()
    }

    public func setup() {
        if isEnabled {
            startMonitoring()
        }
    }

    public func startMonitoring() {
        guard hotKeyRefs.isEmpty else { return }
        installEventHandlerIfNeeded()

        let modifiers = UInt32(controlKey | optionKey)
        var unavailable: [String] = []
        for (index, hotkey) in hotkeys.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: GlobalHotkeysController.signature, id: UInt32(index))
            let status = RegisterEventHotKey(hotkey.keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
            } else {
                unavailable.append(hotkey.label)
            }
        }
        unavailableHotkeys = unavailable
    }

    public func stopMonitoring() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        unavailableHotkeys = []
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == GlobalHotkeysController.signature else {
                return OSStatus(eventNotHandledErr)
            }
            GlobalHotkeysController.shared.trigger(index: Int(hotKeyID.id))
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    /// Runs the action for a registered hotkey (exposed for tests).
    public func trigger(index: Int) {
        guard isEnabled, hotkeys.indices.contains(index) else { return }
        let action = hotkeys[index].perform
        DispatchQueue.main.async { action() }
    }
}
