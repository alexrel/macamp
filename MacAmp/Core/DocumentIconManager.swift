import AppKit
import Security

/// Applies a chosen document icon to the app bundle. Injectable so tests work on a copy and never
/// touch Launch Services.
public protocol BundleIconInstaller {
    /// Replaces `target` (an .icns inside the bundle) with `icon`.
    func install(icon: URL, as target: URL) throws
    /// Re-signs the bundle with its ad-hoc identity after a resource changed.
    func resign(bundle: URL) throws
    /// Tells Launch Services / Finder to pick up the new document icons.
    func register(bundle: URL)
    /// True if the bundle's current signature is intact (nothing to re-sign over a broken bundle).
    func verify(bundle: URL) -> Bool
}

public struct SystemBundleIconInstaller: BundleIconInstaller {
    public init() {}

    public func install(icon: URL, as target: URL) throws {
        let data = try Data(contentsOf: icon)
        try data.write(to: target, options: .atomic)
    }

    public func resign(bundle: URL) throws {
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", "--preserve-metadata=entitlements,requirements,flags,runtime", bundle.path]
        let errors = Pipe()
        codesign.standardError = errors
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "MacAmp.DocumentIcons", code: Int(codesign.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "codesign failed: \(message)"])
        }
    }

    public func verify(bundle: URL) -> Bool {
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--verify", "--strict", bundle.path]
        codesign.standardError = Pipe()
        guard (try? codesign.run()) != nil else { return false }
        codesign.waitUntilExit()
        return codesign.terminationStatus == 0
    }

    public func register(bundle: URL) {
        let lsregister = Process()
        lsregister.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        lsregister.arguments = ["-f", bundle.path]
        try? lsregister.run()
        lsregister.waitUntilExit()
        NSWorkspace.shared.noteFileSystemChanged(bundle.path)
    }
}

/// Winamp's "File icon" / "Playlist icon" sliders. Finder takes document icons from the handler app's
/// bundle, so a choice is applied by swapping the .icns the Info.plist points to, re-signing the bundle
/// ad-hoc and re-registering it. Only possible for local (ad-hoc signed, writable) builds; a
/// Developer ID signature must not be replaced, so the sliders are disabled there.
@MainActor
public final class DocumentIconManager: ObservableObject {
    public enum Kind: String, CaseIterable {
        case audio, playlist
        /// .icns name referenced by CFBundleTypeIconFile in Info.plist
        var bundleIconName: String { self == .audio ? "WinampAudioFile" : "WinampPlaylist" }
        /// Winamp 2.95 defaults: #131 (page with bolt) for files, #102 (bolt) for playlists
        var defaultResourceID: Int { self == .audio ? 131 : 102 }
    }

    /// Document icons from winamp.exe 2.95 (RT_GROUP_ICON IDs), in resource order like Winamp's slider.
    public static let resourceIDs = [102, 131, 162, 163, 164, 178, 179, 180, 181, 182]

    public static let shared = DocumentIconManager(
        bundleURL: Bundle.main.bundleURL,
        installer: SystemBundleIconInstaller(),
        canModifyBundle: DocumentIconManager.isLocallySigned(Bundle.main.bundleURL)
    )

    @Published public private(set) var selection: [Kind: Int] = [:]
    @Published public private(set) var isApplying = false
    @Published public private(set) var lastError: String?
    public let canChangeIcons: Bool

    private let bundleURL: URL
    private let installer: BundleIconInstaller
    private var persistence: PersistenceManager { PersistenceManager.shared }

    public init(bundleURL: URL, installer: BundleIconInstaller, canModifyBundle: Bool) {
        self.bundleURL = bundleURL
        self.installer = installer
        self.canChangeIcons = canModifyBundle
        for kind in Kind.allCases {
            let id = persistence.state.documentIconIDs[kind.rawValue] ?? kind.defaultResourceID
            // Unknown IDs (e.g. from an older build's icon set) fall back to the Winamp default
            selection[kind] = DocumentIconManager.resourceIDs.firstIndex(of: id)
                ?? DocumentIconManager.resourceIDs.firstIndex(of: kind.defaultResourceID) ?? 0
        }
    }

    public func resourceID(for kind: Kind) -> Int {
        DocumentIconManager.resourceIDs[selection[kind] ?? 0]
    }

    public func choiceURL(resourceID: Int) -> URL {
        bundleURL.appendingPathComponent("Contents/Resources/Choices/winamp-icon-\(resourceID).icns")
    }

    private func targetURL(for kind: Kind) -> URL {
        bundleURL.appendingPathComponent("Contents/Resources/\(kind.bundleIconName).icns")
    }

    public func previewImage(for kind: Kind) -> NSImage? {
        NSImage(contentsOf: choiceURL(resourceID: resourceID(for: kind)))
    }

    /// While the slider is dragged: only the preview changes.
    public func preview(_ index: Int, for kind: Kind) {
        guard DocumentIconManager.resourceIDs.indices.contains(index) else { return }
        selection[kind] = index
    }

    /// Slider released: save the choice and apply it to Finder in the background.
    public func commit(for kind: Kind) async {
        persistence.state.documentIconIDs[kind.rawValue] = resourceID(for: kind)
        persistence.scheduleSave()
        guard bundleIconDiffersFromSelection(kind) else { return }
        if isApplying {
            // A re-sign is running; apply the latest position when it finishes
            pendingKinds.insert(kind)
            return
        }
        await apply(kinds: [kind])
        while !pendingKinds.isEmpty {
            let next = pendingKinds.filter(bundleIconDiffersFromSelection)
            pendingKinds.removeAll()
            guard !next.isEmpty else { break }
            await apply(kinds: Array(next))
        }
    }

    public func select(_ index: Int, for kind: Kind) async {
        preview(index, for: kind)
        await commit(for: kind)
    }

    private var pendingKinds = Set<Kind>()

    private func bundleIconDiffersFromSelection(_ kind: Kind) -> Bool {
        (try? Data(contentsOf: choiceURL(resourceID: resourceID(for: kind)))) != (try? Data(contentsOf: targetURL(for: kind)))
    }

    /// After a rebuild the bundle has the default icons again: put the chosen ones back.
    public func reapplyOnLaunchIfNeeded() async {
        let outdated = Kind.allCases.filter(bundleIconDiffersFromSelection)
        guard !outdated.isEmpty else { return }
        await apply(kinds: outdated)
    }

    private func apply(kinds: [Kind]) async {
        guard canChangeIcons else { return }
        lastError = nil
        isApplying = true
        let jobs = kinds.map { (choiceURL(resourceID: resourceID(for: $0)), targetURL(for: $0)) }
        let bundle = bundleURL
        let installer = self.installer
        let error: Error? = await Task.detached(priority: .userInitiated) {
            // Never start from a broken bundle: re-signing would cement whatever is wrong with it
            guard installer.verify(bundle: bundle) else {
                return NSError(domain: "MacAmp.DocumentIcons", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "The app's signature is not intact; rebuild MacAmp and try again"
                ])
            }
            // Keep the current icons so a failed re-sign can be undone (the old signature then matches again)
            let originals = jobs.map { (_, target) in (target, try? Data(contentsOf: target)) }
            do {
                for (icon, target) in jobs {
                    try installer.install(icon: icon, as: target)
                }
                try installer.resign(bundle: bundle)
                installer.register(bundle: bundle)
                return nil
            } catch {
                for (target, data) in originals {
                    if let data { try? data.write(to: target, options: .atomic) }
                }
                return error
            }
        }.value
        if let error {
            lastError = DocumentIconManager.shortMessage(for: error)
            // The bundle still has the previous icons: show them, not the one that failed
            for kind in kinds {
                if let id = currentBundleIconID(for: kind), let index = DocumentIconManager.resourceIDs.firstIndex(of: id) {
                    selection[kind] = index
                    persistence.state.documentIconIDs[kind.rawValue] = id
                }
            }
        }
        isApplying = false
    }

    /// Which choice the bundle's icon file currently is (by content).
    private func currentBundleIconID(for kind: Kind) -> Int? {
        guard let current = try? Data(contentsOf: targetURL(for: kind)) else { return nil }
        return DocumentIconManager.resourceIDs.first { (try? Data(contentsOf: choiceURL(resourceID: $0))) == current }
    }

    /// codesign's output is long and full of paths; keep the part a user can act on.
    static func shortMessage(for error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("unsealed contents") {
            return "Could not change the icon: the app bundle contains extra files. Rebuild MacAmp and try again."
        }
        return text.count > 160 ? String(text.prefix(160)) + "…" : text
    }

    /// True for ad-hoc signed bundles we can write to (local builds). Developer ID / App Store
    /// signatures are never replaced.
    public nonisolated static func isLocallySigned(_ bundle: URL) -> Bool {
        guard FileManager.default.isWritableFile(atPath: bundle.appendingPathComponent("Contents/Resources").path) else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        let flags = (dict[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        let adhocFlag: UInt32 = 0x0002 // kSecCodeSignatureAdhoc
        return flags & adhocFlag != 0
    }
}
