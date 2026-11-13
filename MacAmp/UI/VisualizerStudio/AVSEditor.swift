import Cocoa
import SwiftUI
import CAVS
import UniformTypeIdentifiers

/// Effect names as AVS 2.6.1 (Winamp 2.95) shows them, where libavs words them differently.
enum AVSEffectNames {
    private static let classic = [
        "Set Render Mode": "Set render mode", "Clear Screen": "Clear screen", "On Beat Clear": "OnBeat Clear",
        "Oscilloscope Star": "Oscilliscope Star", "SVP": "SVP Loader", "Video": "AVI", "Unique Tone": "Unique tone",
    ]
    /// The 45 effects of 2.6.1 (libavs names); the rest (2.81 and the fork's) go in a separate submenu
    static let classicEffects: Set<String> = [
        "Simple", "Dot Plane", "Oscilloscope Star", "Fadeout", "Blitter Feedback", "On Beat Clear", "Blur", "Bass Spin",
        "Moving Particle", "Roto Blitter", "SVP", "Colorfade", "Color Clip", "Rotating Stars", "Ring", "Movement",
        "Scatter", "Dot Grid", "Buffer Save", "Dot Fountain", "Water", "Comment", "Brightness", "Interleave", "Grain",
        "Clear Screen", "Mirror", "Starfield", "Text", "Bump", "Mosaic", "Water Bump", "Video", "Custom BPM", "Picture",
        "Dynamic Distance Modifier", "SuperScope", "Invert", "Unique Tone", "Timescope", "Set Render Mode",
        "Interferences", "Dynamic Shift", "Dynamic Movement", "Fast Brightness",
    ]
    static let groups = ["Render", "Trans", "Misc"]
    /// libavs' name of the container effect
    static let effectList = "Effect List"

    static func title(group: String, name: String) -> String {
        switch name {
        case "Root": return "Main"
        case effectList: return "Effect list"
        default:
            let shown = classic[name] ?? name
            return group.isEmpty ? shown : "\(group) / \(shown)"
        }
    }
}

/// The "Winamp AVS Editor" model: the preset tree and the selected effect's parameters, through libavs' editor API.
@MainActor
final class AVSEditorModel: ObservableObject {
    struct Node: Identifiable, Equatable {
        let id: AVS_Component_Handle
        let title: String
        let depth: Int
        let enabled: Bool
        let canHaveChildren: Bool
        /// For the dotted branches: the last of its siblings, and for each level above it whether a stem goes on down
        var isLast = true
        var stems: [Bool] = []
    }
    struct Effect: Identifiable {
        let id: AVS_Effect_Handle
        let group: String
        let name: String
        var title: String { AVSEffectNames.classic(name) }
    }
    struct Parameter: Identifiable {
        let id: AVS_Parameter_Handle
        let info: AVS_Parameter_Info
        var name: String { String(cString: info.name) }
    }

    @Published private(set) var nodes: [Node] = []
    @Published var selected: AVS_Component_Handle = 0
    @Published private(set) var status = ""
    /// Bumped after every change the panel has to re-read
    @Published private(set) var revision = 0
    private(set) var effects: [Effect] = []
    private var shownHandle: AVS_Handle = 0
    private var shownPreset: URL?

    /// The Studio view whose AVS is edited (tests hand in their own)
    var studioProvider: () -> RetroVisualizerView? = { PlayerCoordinator.shared.visualizerStudioWindow?.studioView }
    var studio: RetroVisualizerView? { studioProvider() }
    var view: AVSView? { studio?.avsView }
    var avs: AVS_Handle { view?.handle ?? 0 }

    /// Follows the engine: a random switch or a transition swaps it, and the tree is read again.
    func tick() {
        if avs != shownHandle || view?.presetURL != shownPreset { refresh() }
        guard let view else {
            status = "AVS is not running"
            return
        }
        let size = view.renderSize.width > 0 ? view.renderSize : AVSView.renderSize(for: view.bounds.size)
        status = "\(AVSView.fpsText(view.fps, size)) - \(view.presetName)"
    }

    func refresh() {
        shownHandle = avs
        shownPreset = view?.presetURL
        guard shownHandle != 0 else {
            nodes = []
            effects = []
            return
        }
        if effects.isEmpty {
            var count: UInt32 = 0
            if let list = avs_effect_library(avs, &count) {
                effects = (0..<Int(count)).compactMap { i in
                    var info = AVS_Effect_Info()
                    guard avs_effect_info(avs, list[i], &info), info.is_user_creatable else { return nil }
                    return Effect(id: list[i], group: String(cString: info.group), name: String(cString: info.name))
                }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
        }
        var result: [Node] = []
        func walk(_ component: AVS_Component_Handle, depth: Int, isLast: Bool = true, stems: [Bool] = []) {
            var info = AVS_Effect_Info()
            avs_effect_info(avs, avs_component_effect(avs, component), &info)
            var properties = AVS_Component_Properties()
            avs_component_properties_get(avs, component, &properties)
            result.append(Node(id: component, title: AVSEffectNames.title(group: String(cString: info.group), name: String(cString: info.name)),
                               depth: depth, enabled: properties.enabled, canHaveChildren: info.can_have_child_components,
                               isLast: isLast, stems: stems))
            var count: UInt32 = 0
            guard let children = avs_component_children(avs, component, &count) else { return }
            let handles = (0..<Int(count)).map { children[$0] } // the array is invalidated by the next call
            // Main's children hang off Main's own stem; deeper ones keep their parent's line while it has siblings below
            let childStems = depth == 0 ? [] : stems + [!isLast]
            for (index, child) in handles.enumerated() {
                walk(child, depth: depth + 1, isLast: index == handles.count - 1, stems: childStems)
            }
        }
        walk(avs_component_root(avs), depth: 0)
        nodes = result
        if !result.contains(where: { $0.id == selected }) { selected = result.first?.id ?? 0 }
        revision += 1
    }

    // MARK: Tree commands (+, -, x2, drag)

    func add(_ effect: Effect) {
        let node = nodes.first { $0.id == selected }
        let position = node?.depth == 0 || node?.canHaveChildren == true ? AVS_COMPONENT_POSITION_CHILD : AVS_COMPONENT_POSITION_AFTER
        let created = avs_component_create(avs, effect.id, node?.id ?? 0, position)
        if created != 0 { selected = created }
        refresh()
    }

    func removeSelected() {
        guard let node = nodes.first(where: { $0.id == selected }), node.depth > 0 else { return }
        avs_component_delete(avs, node.id)
        refresh()
    }

    func duplicateSelected() {
        guard let node = nodes.first(where: { $0.id == selected }), node.depth > 0 else { return }
        let copy = avs_component_duplicate(avs, node.id)
        if copy != 0 { selected = copy }
        refresh()
    }

    /// Dropped on a row: into it if it is a list, otherwise before it.
    func move(_ component: AVS_Component_Handle, onto target: AVS_Component_Handle) {
        guard component != target, let node = nodes.first(where: { $0.id == target }) else { return }
        let position = node.canHaveChildren ? AVS_COMPONENT_POSITION_CHILD : AVS_COMPONENT_POSITION_BEFORE
        guard node.depth > 0 || position == AVS_COMPONENT_POSITION_CHILD else { return }
        avs_component_move(avs, component, target, position)
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        var properties = AVS_Component_Properties()
        avs_component_properties_get(avs, selected, &properties)
        properties.enabled = enabled
        avs_component_properties_set(avs, selected, properties)
        refresh()
    }

    // MARK: Parameters

    var selectedEffect: AVS_Effect_Handle { avs_component_effect(avs, selected) }
    var selectedNode: Node? { nodes.first { $0.id == selected } }

    func effectHelp() -> String {
        var info = AVS_Effect_Info()
        guard avs_effect_info(avs, selectedEffect, &info) else { return "" }
        return String(cString: info.help)
    }

    func parameters(_ handles: UnsafePointer<AVS_Parameter_Handle>?, count: Int) -> [Parameter] {
        guard let handles else { return [] }
        return (0..<count).compactMap { i in
            var info = AVS_Parameter_Info()
            guard avs_parameter_info(avs, selectedEffect, handles[i], &info), info.type != AVS_PARAM_INVALID else { return nil }
            return Parameter(id: handles[i], info: info)
        }
    }

    var selectedParameters: [Parameter] {
        var info = AVS_Effect_Info()
        guard avs_effect_info(avs, selectedEffect, &info) else { return [] }
        let all = parameters(info.parameters, count: Int(info.parameters_length))
        // Main shows only "Clear every frame"; the rest of Root is preset metadata
        return selectedNode?.depth == 0 ? all.filter { $0.info.type == AVS_PARAM_BOOL } : all
    }

    func bool(_ p: AVS_Parameter_Handle, _ path: [Int64] = []) -> Bool {
        var path = path
        return avs_parameter_get_bool(avs, selected, p, UInt32(path.count), &path)
    }
    func int(_ p: AVS_Parameter_Handle, _ path: [Int64] = []) -> Int64 {
        var path = path
        return avs_parameter_get_int(avs, selected, p, UInt32(path.count), &path)
    }
    func float(_ p: AVS_Parameter_Handle, _ path: [Int64] = []) -> Double {
        var path = path
        return avs_parameter_get_float(avs, selected, p, UInt32(path.count), &path)
    }
    func color(_ p: AVS_Parameter_Handle, _ path: [Int64] = []) -> UInt64 {
        var path = path
        return avs_parameter_get_color(avs, selected, p, UInt32(path.count), &path)
    }
    func string(_ p: AVS_Parameter_Handle, _ path: [Int64] = []) -> String {
        var path = path
        return avs_parameter_get_string(avs, selected, p, UInt32(path.count), &path).map { String(cString: $0) } ?? ""
    }
    func listLength(_ p: AVS_Parameter_Handle, _ path: [Int64] = []) -> Int {
        var path = path
        return Int(avs_parameter_list_length(avs, selected, p, UInt32(path.count), &path))
    }

    func set(_ p: AVS_Parameter_Handle, bool value: Bool, _ path: [Int64] = []) {
        var path = path
        _ = avs_parameter_set_bool(avs, selected, p, value, UInt32(path.count), &path)
        revision += 1
    }
    func set(_ p: AVS_Parameter_Handle, int value: Int64, _ path: [Int64] = []) {
        var path = path
        _ = avs_parameter_set_int(avs, selected, p, value, UInt32(path.count), &path)
        revision += 1
    }
    func set(_ p: AVS_Parameter_Handle, float value: Double, _ path: [Int64] = []) {
        var path = path
        _ = avs_parameter_set_float(avs, selected, p, value, UInt32(path.count), &path)
        revision += 1
    }
    func set(_ p: AVS_Parameter_Handle, color value: UInt64, _ path: [Int64] = []) {
        var path = path
        _ = avs_parameter_set_color(avs, selected, p, value, UInt32(path.count), &path)
        revision += 1
    }
    func set(_ p: AVS_Parameter_Handle, string value: String, _ path: [Int64] = []) {
        var path = path
        _ = avs_parameter_set_string(avs, selected, p, value, UInt32(path.count), &path)
    }
    func run(_ p: AVS_Parameter_Handle, _ path: [Int64] = []) {
        var path = path
        _ = avs_parameter_run_action(avs, selected, p, UInt32(path.count), &path)
        revision += 1
    }
    /// `path`: the indices of the lists this one is nested in
    func addListElement(_ p: AVS_Parameter_Handle, _ path: [Int64] = []) {
        var path = path
        let end = Int64(listLength(p, path))
        _ = avs_parameter_list_element_add(avs, selected, p, end, 0, nil, UInt32(path.count), &path)
        revision += 1
    }
    func removeListElement(_ p: AVS_Parameter_Handle, _ path: [Int64] = []) {
        var path = path
        let last = Int64(listLength(p, path) - 1)
        _ = avs_parameter_list_element_remove(avs, selected, p, last, UInt32(path.count), &path)
        revision += 1
    }

    // MARK: Preset menu

    func loadPreset() {
        let panel = NSOpenPanel()
        panel.directoryURL = AVSPresets.folder
        panel.allowedContentTypes = [AVSPresets.contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        studio?.loadAVSPreset(url)
        refresh()
    }

    func savePreset() {
        let panel = NSSavePanel()
        panel.directoryURL = view?.presetURL?.deletingLastPathComponent() ?? AVSPresets.folder
        let name = view?.presetName ?? ""
        panel.nameFieldStringValue = name.isEmpty ? "untitled" : name
        panel.allowedContentTypes = [AVSPresets.contentType]
        guard panel.runModal() == .OK, let url = panel.url, let view else { return }
        if view.save(to: url) {
            studio?.loadAVSPreset(url)
        } else {
            Win32Dialog.inform(title: "AVS", message: "Could not save \(url.lastPathComponent).")
        }
        refresh()
    }

    func newPreset() {
        view?.loadEmpty()
        refresh()
    }
}

extension AVSEffectNames {
    static func classic(_ name: String) -> String { title(group: "", name: name) }
}

/// The "Winamp AVS Editor" window (Screenshot_9 ... 17): menu, effect tree with + / - / x2, the effect's panel,
/// status line. Opened by Configure plug-in (⌥K) and the AVS window's menu.
@MainActor
final class AVSEditorWindowController: NSWindowController, NSWindowDelegate {
    static let size = NSSize(width: 580, height: 420)
    private(set) static var shared: AVSEditorWindowController?
    static var isOpen: Bool { shared?.window?.isVisible == true }
    private let model = AVSEditorModel()
    private var timer: Timer?

    static func show() {
        let controller = shared ?? AVSEditorWindowController()
        shared = controller
        controller.model.refresh()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Winamp AVS Editor"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        super.init(window: window)
        window.delegate = self
        window.installScaledDialog(AVSEditorView(model: model), size: Self.size)
        window.center()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.model.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        model.tick()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        Self.shared = nil
    }
}

struct AVSEditorView: View {
    @ObservedObject var model: AVSEditorModel

    /// Proportions of the 2.6.1 editor (Screenshot_9 ... 17): 10 pt margins, small square buttons with gaps,
    /// the tree under them, the grey dock area, the effect's group box level with the buttons
    private enum Metrics {
        static let margin: CGFloat = 10
        static let columnWidth: CGFloat = 196
        static let columnGap: CGFloat = 8
        static let buttonHeight: CGFloat = 20
        static let buttonGap: CGFloat = 7
        /// x2 stands a little apart from + and -
        static let cloneGap: CGFloat = 14
        static let dockHeight: CGFloat = 112
        static let rowGap: CGFloat = 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            menuBar
            HStack(alignment: .top, spacing: Metrics.columnGap) {
                VStack(alignment: .leading, spacing: Metrics.rowGap) {
                    treeButtons
                    tree
                    // Where "Dock in config" puts the picture
                    Rectangle().fill(Color(white: 0.4)).win32Sunken().frame(height: Metrics.dockHeight)
                }
                .frame(width: Metrics.columnWidth)
                Win32GroupBox(model.selectedNode?.title ?? "No effect/setting selected") {
                    ScrollView { AVSParameterPanel(model: model).id("\(model.selected)-\(model.revision)") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, Metrics.margin)
            HStack {
                Text(model.status)
                Spacer()
                Text(AVSView.productName)
            }
            .font(.system(size: 11))
            .foregroundColor(Win32Colors.text)
            .lineLimit(1)
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 6)
        }
        .frame(width: AVSEditorWindowController.size.width, height: AVSEditorWindowController.size.height)
        .background(Win32Colors.dialogBg)
    }

    private var menuBar: some View {
        HStack(spacing: 0) {
            Win32MenuTitle(title: "Preset") {
                [Win32ClosureMenuItem(title: "Load...") { model.loadPreset() },
                 Win32ClosureMenuItem(title: "Save...") { model.savePreset() },
                 Win32ClosureMenuItem(title: "New") { model.newPreset() }]
            }
            Win32MenuTitle(title: "Settings") {
                [Win32ClosureMenuItem(title: "Presets/Hotkeys") { PreferencesWindow.show(treeItem: .visPlugin) }]
            }
            Spacer()
            Win32MenuTitle(title: "Help") {
                [Win32ClosureMenuItem(title: "Effect help") {
                    let help = model.effectHelp()
                    Win32Dialog.inform(title: model.selectedNode?.title ?? "AVS", message: help.isEmpty ? "No help for this effect." : help)
                 },
                 Win32ClosureMenuItem(title: "About AVS...") {
                    Win32Dialog.inform(title: "About AVS", message: "\(AVSView.productName)\nCopyright © 1998-2005 Nullsoft, Inc. (BSD license)\nJustin Frankel, Francis Gastellu, Christophe Thibault & Brennan Underwood\nlibavs for macOS: the grandchild/vis_avs fork, adapted by MacAmp.")
                 }]
            }
        }
        .frame(height: Win32MenuTitle.height)
        .padding(.horizontal, Metrics.margin - Win32MenuTitle.TitleView.padding)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity)
        // The menu bar is a band of its own, lighter than the dialog, as in the Winamp screenshots
        .background(Win32MenuTitle.barColor)
        .overlay(alignment: .bottom) { Rectangle().fill(Win32Colors.borderShadow).frame(height: 1) }
    }

    private var treeButtons: some View {
        HStack(spacing: Metrics.buttonGap) {
            Win32GlyphButton(glyph: .plus, size: Metrics.buttonHeight) {
                let menu = addMenu()
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
            Win32GlyphButton(glyph: .minus, size: Metrics.buttonHeight) { model.removeSelected() }
            Win32Button("x2", width: 26, height: Metrics.buttonHeight) { model.duplicateSelected() }
                .padding(.leading, Metrics.cloneGap - Metrics.buttonGap)
        }
    }

    /// "+": the effects by group as in 2.6.1, then Effect list; the 2.81+ ones apart at the bottom
    private func addMenu() -> NSMenu {
        let menu = NSMenu()
        func submenu(_ title: String, _ effects: [AVSEditorModel.Effect], fullTitles: Bool = false) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu()
            for effect in effects {
                let name = fullTitles ? AVSEffectNames.title(group: effect.group, name: effect.name) : effect.title
                item.submenu?.addItem(Win32ClosureMenuItem(title: name) { model.add(effect) })
            }
            return item
        }
        for group in AVSEffectNames.groups {
            menu.addItem(submenu(group, model.effects.filter { $0.group == group && AVSEffectNames.classicEffects.contains($0.name) }))
        }
        if let list = model.effects.first(where: { $0.name == AVSEffectNames.effectList }) {
            menu.addItem(Win32ClosureMenuItem(title: "Effect list") { model.add(list) })
        }
        menu.addItem(.separator())
        menu.addItem(submenu("More effects (AVS 2.81+)", model.effects.filter {
            !$0.group.isEmpty && !AVSEffectNames.classicEffects.contains($0.name)
        }, fullTitles: true))
        return menu
    }

    private var tree: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.nodes) { node in
                    let isSelected = node.id == model.selected
                    // The Preferences tree's look: dotted branches, the selection only behind the text
                    HStack(spacing: 2) {
                        HStack(spacing: 0) {
                            ForEach(Array(node.stems.enumerated()), id: \.offset) { _, continues in
                                TreeStem(isVisible: continues)
                            }
                            if node.depth > 0 { TreeConnector(isLast: node.isLast) }
                        }
                        Text(node.title)
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? .white : node.enabled ? Win32Colors.text : .gray)
                            .lineLimit(1)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(isSelected ? Win32Colors.selectionHighlight : Color.clear)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, node.depth > 0 ? 2 : 4)
                    .padding(.vertical, node.depth > 0 ? 0 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selected = node.id }
                        .onDrag { NSItemProvider(object: String(node.id) as NSString) }
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            _ = providers.first?.loadObject(ofClass: NSString.self) { object, _ in
                                guard let text = object as? String, let moved = AVS_Component_Handle(text) else { return }
                                DispatchQueue.main.async { model.move(moved, onto: node.id) }
                            }
                            return true
                        }
                }
            }
            .padding(.vertical, 2)
        }
        .background(Color.white)
        .win32Sunken()
    }
}

/// A level of the tree above a row: the dotted line of an ancestor that has more children below, or empty space.
struct TreeStem: View {
    let isVisible: Bool

    var body: some View {
        Canvas { context, size in
            guard isVisible else { return }
            var path = Path()
            path.move(to: CGPoint(x: 6, y: 0))
            path.addLine(to: CGPoint(x: 6, y: size.height))
            context.stroke(path, with: .color(TreeConnector.lineColor), style: StrokeStyle(lineWidth: 1, dash: [1, 1]))
        }
        .frame(width: 16, height: 18)
    }
}

/// The selected effect's settings, laid out from libavs' parameter descriptions.
struct AVSParameterPanel: View {
    @ObservedObject var model: AVSEditorModel
    /// 2.6.1's names for the expression boxes; the code run per point or pixel gets the tall box
    private static let codeLabels: [String: (label: String, isTall: Bool)] = [
        "Init": ("Init:", false), "Beat": ("On Beat:", false), "Frame": ("Per Frame:", false),
        "Point": ("Per Point:", true), "Pixel": ("Per Pixel:", true),
    ]
    private static let labelWidth: CGFloat = 64
    private static let fieldHeight: CGFloat = 36
    private static let tallFieldHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let node = model.selectedNode, node.depth > 0 {
                Win32Checkbox("Enabled", isOn: Binding(get: { node.enabled }, set: { model.setEnabled($0) }))
            }
            ForEach(model.selectedParameters) { parameter in
                row(parameter, path: [])
            }
        }
        .font(.system(size: 11))
        .foregroundColor(Win32Colors.text)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func row(_ p: AVSEditorModel.Parameter, path: [Int64]) -> some View {
        let info = p.info
        let name = model.selectedNode?.depth == 0 && p.name == "Clear" ? "Clear every frame" : p.name
        switch info.type {
        case AVS_PARAM_BOOL:
            Win32Checkbox(name, isOn: Binding(get: { model.bool(p.id, path) }, set: { model.set(p.id, bool: $0, path) }))
        case AVS_PARAM_INT where info.int_max > info.int_min && info.int_max - info.int_min <= 100_000:
            labeledSlider(name, value: Binding(get: { Double(model.int(p.id, path)) }, set: { model.set(p.id, int: Int64($0.rounded()), path) }),
                          range: Double(info.int_min)...Double(info.int_max), step: 1, format: "%.0f")
        case AVS_PARAM_INT:
            HStack {
                Text(name)
                Win32NumberField(value: Binding(get: { Int(model.int(p.id, path)) }, set: { model.set(p.id, int: Int64($0), path) }), width: 60)
            }
        case AVS_PARAM_FLOAT where info.float_max > info.float_min:
            labeledSlider(name, value: Binding(get: { model.float(p.id, path) }, set: { model.set(p.id, float: $0, path) }),
                          range: info.float_min...info.float_max, step: 0, format: "%.3f")
        case AVS_PARAM_FLOAT:
            HStack {
                Text(name)
                Win32TextField(text: Binding(get: { String(model.float(p.id, path)) },
                                             set: { if let v = Double($0) { model.set(p.id, float: v, path) } }))
                    .frame(width: 80)
            }
        case AVS_PARAM_SELECT:
            HStack {
                Text(name)
                Win32ComboBox(selection: Binding(get: { model.int(p.id, path) }, set: { model.set(p.id, int: $0, path) }),
                              options: (0..<Int(info.options_length)).map { (value: Int64($0), title: String(cString: info.options[$0]!)) },
                              width: 150)
            }
        case AVS_PARAM_COLOR:
            AVSColorWell(title: name, color: model.color(p.id, path)) { model.set(p.id, color: $0, path) }
        case AVS_PARAM_STRING, AVS_PARAM_RESOURCE:
            // As SuperScope in 2.6.1: the label left of the field, one line, the per-point / per-pixel code taller
            let code = Self.codeLabels[p.name]
            HStack(alignment: .top, spacing: 6) {
                Text(code?.label ?? "\(name):")
                    .frame(width: Self.labelWidth, alignment: .leading)
                    .padding(.top, 3)
                AVSCodeEditor(text: model.string(p.id, path)) { model.set(p.id, string: $0, path) }
                    .frame(height: code?.isTall == true ? Self.tallFieldHeight : Self.fieldHeight)
            }
        case AVS_PARAM_ACTION:
            Win32Button(name, width: 110) { model.run(p.id, path) }
        case AVS_PARAM_LIST:
            listRow(p, name: name, path: path)
        default:
            EmptyView()
        }
    }

    /// Lists (SuperScope's colours, Dynamic Movement's buffers ...): their elements, with + / - to grow or shrink.
    private func listRow(_ p: AVSEditorModel.Parameter, name: String, path: [Int64]) -> some View {
        let children = model.parameters(p.info.children, count: Int(p.info.children_length))
        let count = model.listLength(p.id, path)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(name) (\(count))")
                Win32Button("+", width: 22, height: 18) { model.addListElement(p.id, path) }
                    .disabled(p.info.children_length_max > 0 && count >= Int(p.info.children_length_max))
                Win32Button("-", width: 22, height: 18) { model.removeListElement(p.id, path) }
                    .disabled(count <= Int(p.info.children_length_min))
            }
            ForEach(0..<count, id: \.self) { index in
                ForEach(children) { child in
                    AnyView(row(child, path: path + [Int64(index)]))
                }
                .padding(.leading, 12)
            }
        }
    }

    private func labeledSlider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        HStack {
            Text(name).frame(width: 110, alignment: .leading)
            Win32Slider(value: value, in: range, step: step).frame(height: 22)
            Text(String(format: format, value.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
    }
}

/// A colour button (0x00RRGGBB, as AVS stores colours) that opens the colour panel.
struct AVSColorWell: View {
    let title: String
    let color: UInt64
    let onChange: (UInt64) -> Void

    var body: some View {
        HStack {
            Text(title)
            Button(action: { AVSColorPanelTarget.shared.edit(color, onChange) }) {
                Rectangle()
                    .fill(Color(red: Double(color >> 16 & 0xFF) / 255, green: Double(color >> 8 & 0xFF) / 255,
                                blue: Double(color & 0xFF) / 255))
                    .frame(width: 60, height: 16)
                    .win32Sunken()
            }
            .buttonStyle(.plain)
        }
    }
}

final class AVSColorPanelTarget: NSObject {
    static let shared = AVSColorPanelTarget()
    private var onChange: ((UInt64) -> Void)?

    func edit(_ color: UInt64, _ onChange: @escaping (UInt64) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.color = NSColor(srgbRed: CGFloat(color >> 16 & 0xFF) / 255, green: CGFloat(color >> 8 & 0xFF) / 255,
                              blue: CGFloat(color & 0xFF) / 255, alpha: 1)
        panel.orderFront(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) {
        guard let rgb = panel.color.usingColorSpace(.sRGB) else { return }
        let value = UInt64(rgb.redComponent * 255) << 16 | UInt64(rgb.greenComponent * 255) << 8 | UInt64(rgb.blueComponent * 255)
        onChange?(value)
    }
}

/// A sunken multi-line, monospaced edit box for expressions; every edit recompiles, as AVS does.
struct AVSCodeEditor: NSViewRepresentable {
    let text: String
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .bezelBorder
        let view = scroll.documentView as! NSTextView
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.string = text
        view.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            onChange(view.string)
        }
    }
}

/// A title in a Win32 window's menu bar (Preset, Settings, Help), as the editor's menu in Winamp: 11 pt text, a light
/// blue box under the mouse and while its menu is open, the menu dropping just below it.
struct Win32MenuTitle: NSViewRepresentable {
    static let height: CGFloat = 19
    /// The menu bar band: lighter than the dialog face
    static let barColor = Color(red: 240 / 255, green: 239 / 255, blue: 236 / 255)
    let title: String
    let items: () -> [NSMenuItem]

    func makeNSView(context: Context) -> TitleView { TitleView(title: title, items: items) }
    func updateNSView(_ view: TitleView, context: Context) { view.items = items }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TitleView, context: Context) -> CGSize? {
        CGSize(width: nsView.title.size(withAttributes: TitleView.attributes).width + TitleView.padding * 2,
               height: Self.height)
    }

    final class TitleView: NSView {
        static let padding: CGFloat = 6
        /// Space between the title and its menu: AppKit's menu frame starts above its first item
        static let menuGap: CGFloat = 2
        /// The open or pointed-at title: a light blue box with a blue border (the Winamp screenshots)
        static let highlightFill = NSColor(srgbRed: 204 / 255, green: 232 / 255, blue: 255 / 255, alpha: 1)
        static let highlightBorder = NSColor(srgbRed: 153 / 255, green: 209 / 255, blue: 255 / 255, alpha: 1)
        static let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black]

        let title: String
        var items: () -> [NSMenuItem]
        private var isOpen = false
        private var isHovered = false

        init(title: String, items: @escaping () -> [NSMenuItem]) {
            self.title = title
            self.items = items
            super.init(frame: .zero)
            setAccessibilityRole(.menuButton)
            setAccessibilityLabel(title)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

        override func draw(_ dirtyRect: NSRect) {
            if isOpen || isHovered {
                Self.highlightFill.setFill()
                bounds.fill()
                Self.highlightBorder.setFill()
                bounds.frame(withWidth: 1)
            }
            let text = NSAttributedString(string: title, attributes: Self.attributes)
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let menu = NSMenu()
            items().forEach(menu.addItem)
            isOpen = true
            display()
            // Screen coordinates: the menu's top-left just under the title's bottom-left
            let corner = window.convertPoint(toScreen: convert(NSPoint(x: 0, y: bounds.maxY), to: nil))
            menu.popUp(positioning: nil, at: NSPoint(x: corner.x, y: corner.y - Self.menuGap), in: nil)
            isOpen = false
            isHovered = false
            needsDisplay = true
        }
    }
}

/// A small Win32 push button with "+" or "-" drawn as centred 1 pt strokes: text glyphs sit off centre in a 20 pt box
struct Win32GlyphButton: View {
    enum Glyph { case plus, minus }
    /// Stroke length: 7 px, as MS Sans Serif draws them
    private static let armLength: CGFloat = 7
    let glyph: Glyph
    let size: CGFloat
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: { RunLoop.main.perform(inModes: [.common], block: action) }) {
            Canvas { context, canvas in
                // Centred on the face, as Win32 does: the bevel is 1 pt light on the left and top, 2 pt dark on the
                // right and bottom, so the face's middle is half a point up and left of the button's
                let mid = CGPoint(x: (canvas.width - 1) / 2, y: (canvas.height - 1) / 2)
                let half = Self.armLength / 2
                var path = Path()
                path.move(to: CGPoint(x: mid.x - half, y: mid.y))
                path.addLine(to: CGPoint(x: mid.x + half, y: mid.y))
                if glyph == .plus {
                    path.move(to: CGPoint(x: mid.x, y: mid.y - half))
                    path.addLine(to: CGPoint(x: mid.x, y: mid.y + half))
                }
                context.stroke(path, with: .color(Win32Colors.text), lineWidth: 1)
            }
            .frame(width: size, height: size)
            .background(Win32Colors.dialogBg)
            .win32Raised(isPressed: isPressed)
        }
        .buttonStyle(Win32ButtonStyle(isPressed: $isPressed))
        .focusable(false)
        .accessibilityLabel(glyph == .plus ? "Add effect" : "Remove effect")
    }
}
