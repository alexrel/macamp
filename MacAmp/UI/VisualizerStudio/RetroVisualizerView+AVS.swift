import Cocoa
import Carbon.HIToolbox

/// Advanced Visualization Studio in the Studio window: the AVS window's menu and keys as in Winamp 2.95 (AVS 2.6.1).
extension RetroVisualizerView {
    /// F1-F12 are slots 0-11, 0-9 slots 12-21, Shift+0-9 slots 22-31 (wnd.cpp)
    private static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                                       kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
    private static let digitKeys = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                                    kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    private static let digitSlots = 12, shiftDigitSlots = 22

    func syncAVS(closing: Bool = false) {
        if currentPreset == .avs && !closing {
            if let avsView {
                avsView.setVisible(isOnScreen)
                return
            }
            guard isOnScreen, let view = AVSView(studioFrame: bounds) else { return }
            addSubview(view)
            view.setVisible(true)
            avsView = view
            if let path = PersistenceManager.shared.state.avsPresetPath, view.load(URL(fileURLWithPath: path)) { return }
            if let first = AVSPresets.scan().allPresets.first { loadAVSPreset(first) }
        } else if let view = avsView {
            view.setVisible(false)
            view.removeFromSuperview()
            avsView = nil
        }
    }

    func loadAVSPreset(_ url: URL, transition: Bool = false) {
        guard let avsView, avsView.load(url, transition: transition) else { return }
        PersistenceManager.shared.state.avsPresetPath = url.path
        PersistenceManager.shared.scheduleSave()
        window?.title = "AVS - \(avsView.presetName)"
    }

    /// U / Y walk the presets in folder order; Space picks one at random (wnd.cpp next/previous/random_preset).
    func stepAVSPreset(by step: Int) {
        let presets = AVSPresets.scan().allPresets
        guard !presets.isEmpty else { return }
        let current = avsView?.presetURL.flatMap { presets.firstIndex(of: $0) }
        let index = current.map { ($0 + step + presets.count) % presets.count } ?? 0
        loadAVSPreset(presets[index])
    }

    func randomAVSPreset() {
        let presets = AVSPresets.scan().allPresets.filter { $0 != avsView?.presetURL }
        guard let preset = presets.randomElement() else { return }
        loadAVSPreset(preset, transition: true)
    }

    /// "Randomly switch presets every N seconds", counted while the picture moves
    func switchAVSPresetIfDue() {
        let state = PersistenceManager.shared.state
        // 2.6.1: not while the editor is open, unless full screen
        let editing = AVSEditorWindowController.isOpen && window?.styleMask.contains(.fullScreen) != true
        guard let avsView, state.avsRandomSwitch, !editing,
              CACurrentMediaTime() - avsView.loadedAt >= TimeInterval(max(1, state.avsRandomSeconds)) else { return }
        randomAVSPreset()
    }

    func handleAVSKey(_ event: NSEvent) -> Bool {
        guard let avsView else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = Int(event.keyCode)
        if modifiers == [.option] && (key == kVK_Return || key == kVK_ANSI_KeypadEnter) {
            onToggleFullScreen?()
            return true
        }
        if let index = Self.functionKeys.firstIndex(of: key), modifiers.isSubset(of: [.control]) {
            useAVSSlot(index, name: "F\(index + 1)", save: modifiers == [.control])
            return true
        }
        if let digit = Self.digitKeys.firstIndex(of: key), modifiers.isSubset(of: [.control, .shift]) {
            let shift = modifiers.contains(.shift)
            useAVSSlot((shift ? Self.shiftDigitSlots : Self.digitSlots) + digit, name: "\(shift ? "shift-" : "")\(digit)",
                       save: modifiers.contains(.control))
            return true
        }
        guard modifiers.isEmpty else { return PlayerCoordinator.shared.handleKeyDown(event) }
        switch key {
        case kVK_Space: randomAVSPreset()
        case kVK_ANSI_U: stepAVSPreset(by: 1)
        case kVK_ANSI_Y: stepAVSPreset(by: -1)
        case kVK_ANSI_T: avsView.showStatus(avsView.presetName)
        case kVK_ANSI_F: avsView.showsFPS.toggle()
        case kVK_ANSI_R:
            PersistenceManager.shared.state.avsRandomSwitch.toggle()
            PersistenceManager.shared.scheduleSave()
            avsView.showStatus(PersistenceManager.shared.state.avsRandomSwitch ? "random presets on" : "random presets off")
        case kVK_Escape, kVK_Tab: return false
        default: return PlayerCoordinator.shared.handleKeyDown(event)
        }
        return true
    }

    private func useAVSSlot(_ slot: Int, name: String, save: Bool) {
        guard let avsView else { return }
        let url = AVSView.slotURL(slot)
        if save {
            avsView.showStatus(avsView.save(to: url) ? "saved to \(name)" : "error saving to \(name)")
        } else {
            avsView.showStatus(avsView.load(url) ? "loaded from \(name)" : "error loading from \(name)")
        }
    }

    /// The AVS window's right-click menu (Screenshot_10): Fullscreen, AVS Editor, the preset folders and presets.
    func avsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let fullScreen = NSMenuItem(title: "Fullscreen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
        fullScreen.target = window
        menu.addItem(fullScreen)
        let editor = NSMenuItem(title: "AVS Editor", action: #selector(PlayerCoordinator.handleConfigureVisPlugin), keyEquivalent: "")
        editor.target = PlayerCoordinator.shared
        menu.addItem(editor)
        menu.addItem(.separator())
        addAVSPresetItems(AVSPresets.scan(), to: menu)
        return menu
    }

    private func addAVSPresetItems(_ folder: AVSPresets.Folder, to menu: NSMenu) {
        for sub in folder.subfolders {
            let item = NSMenuItem(title: sub.url.lastPathComponent, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            addAVSPresetItems(sub, to: submenu)
            item.submenu = submenu
            menu.addItem(item)
        }
        for preset in folder.presets {
            let item = NSMenuItem(title: preset.deletingPathExtension().lastPathComponent,
                                  action: #selector(chooseAVSPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.state = preset == avsView?.presetURL ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func chooseAVSPreset(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        loadAVSPreset(url)
    }
}
