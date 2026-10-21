import AppKit
import UniformTypeIdentifiers

/// Launch Services operations used for file associations; injectable so tests never touch the real system.
public protocol DefaultAppProvider {
    func defaultApplication(for type: UTType) -> URL?
    func applications(for type: UTType) -> [URL]
    func setDefaultApplication(_ app: URL, for type: UTType) async throws
}

/// The real thing: NSWorkspace / Launch Services.
public struct WorkspaceDefaultAppProvider: DefaultAppProvider {
    public init() {}
    public func defaultApplication(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }
    public func applications(for type: UTType) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: type)
    }
    public func setDefaultApplication(_ app: URL, for type: UTType) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
    }
}

/// One row of Preferences ▸ Setup ▸ File types (Winamp's "Associated extensions" list).
public struct FileTypeEntry: Identifiable, Equatable {
    public enum Kind { case audio, playlist, skin }
    public let ext: String
    public let kind: Kind
    public var id: String { ext }
    public var type: UTType? { UTType(filenameExtension: ext) }
}

/// Winamp's file type setup for macOS: makes MacAmp the default app for chosen extensions,
/// remembers which app had them before (to give them back when unchecked) and can re-register on launch.
@MainActor
public final class FileAssociationManager: ObservableObject {
    public static let shared = FileAssociationManager(
        provider: WorkspaceDefaultAppProvider(),
        appURL: Bundle.main.bundleURL,
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "alexrel.MacAmp"
    )

    public let entries: [FileTypeEntry]
    /// Extensions whose files currently open in MacAmp
    @Published public private(set) var associated: Set<String> = []
    @Published public private(set) var lastError: String?

    private let provider: DefaultAppProvider
    private let appURL: URL
    private let bundleIdentifier: String
    private var persistence: PersistenceManager { PersistenceManager.shared }

    public init(provider: DefaultAppProvider, appURL: URL, bundleIdentifier: String) {
        self.provider = provider
        self.appURL = appURL
        self.bundleIdentifier = bundleIdentifier
        let audio = AppConstants.Audio.supportedExtensions.subtracting(["alac"]).sorted()
        self.entries = audio.map { FileTypeEntry(ext: $0, kind: .audio) }
            + AppConstants.Audio.playlistExtensions.sorted().map { FileTypeEntry(ext: $0, kind: .playlist) }
            + [FileTypeEntry(ext: "wsz", kind: .skin)]
        refresh()
    }

    /// Re-reads which extensions open in MacAmp right now (another app may have taken them since).
    public func refresh() {
        associated = Set(entries.compactMap { entry in
            guard let type = entry.type, let app = provider.defaultApplication(for: type) else { return nil }
            return isMacAmp(app) ? entry.ext : nil
        })
    }

    public func isAssociated(_ ext: String) -> Bool { associated.contains(ext) }

    public func setAssociated(_ ext: String, _ enabled: Bool) async {
        await setAssociated(Set([ext]), enabled)
    }

    /// Makes MacAmp the default app for `exts`, or gives them back to the app that had them before.
    public func setAssociated(_ exts: Set<String>, _ enabled: Bool) async {
        lastError = nil
        var desired = Set(persistence.state.fileAssociations)
        var previous = persistence.state.fileAssociationPrevious
        var failed: [String] = []
        // Extensions sharing a type (aif/aiff, m3u/m3u8) are switched together
        var handledTypes = Set<String>()

        for entry in entries where exts.contains(entry.ext) {
            guard let type = entry.type else { failed.append(entry.ext); continue }
            if enabled { desired.insert(entry.ext) } else { desired.remove(entry.ext) }
            guard handledTypes.insert(type.identifier).inserted else { continue }
            do {
                if enabled {
                    if let current = provider.defaultApplication(for: type), !isMacAmp(current) {
                        previous[type.identifier] = current.path
                    }
                    try await provider.setDefaultApplication(appURL, for: type)
                } else if let current = provider.defaultApplication(for: type), isMacAmp(current),
                          let fallback = fallbackApplication(for: type, remembered: previous[type.identifier]) {
                    try await provider.setDefaultApplication(fallback, for: type)
                    previous[type.identifier] = nil
                }
            } catch {
                failed.append(entry.ext)
            }
        }

        persistence.state.fileAssociations = desired.sorted()
        persistence.state.fileAssociationPrevious = previous
        persistence.scheduleSave()
        if !failed.isEmpty {
            lastError = "Could not change: " + failed.map { "." + $0 }.joined(separator: ", ")
        }
        refresh()
    }

    public func selectAll() async {
        await setAssociated(Set(entries.map(\.ext)), true)
    }

    public func selectNone() async {
        await setAssociated(Set(entries.map(\.ext)), false)
    }

    /// "Register types on MacAmp start": take back the chosen types if another app grabbed them.
    public func reapplyOnLaunchIfNeeded() async {
        guard persistence.state.registerFileTypesOnStart else { return }
        refresh()
        let missing = Set(persistence.state.fileAssociations).subtracting(associated)
        guard !missing.isEmpty else { return }
        await setAssociated(missing, true)
    }

    /// The app that had the type before MacAmp, if it is still installed; otherwise any other app that can open it.
    private func fallbackApplication(for type: UTType, remembered: String?) -> URL? {
        if let remembered, FileManager.default.fileExists(atPath: remembered) {
            return URL(fileURLWithPath: remembered)
        }
        return provider.applications(for: type).first { !isMacAmp($0) }
    }

    private func isMacAmp(_ app: URL) -> Bool {
        if app.standardizedFileURL == appURL.standardizedFileURL { return true }
        return Bundle(url: app)?.bundleIdentifier == bundleIdentifier
    }

    // MARK: - Icons

    /// The original Winamp 2.95 document icons shipped in the app bundle.
    public static func documentIcon(for kind: FileTypeEntry.Kind) -> NSImage? {
        let name: String
        switch kind {
        case .audio: name = "WinampAudioFile"
        case .playlist: name = "WinampPlaylist"
        case .skin: name = "WinampSkin"
        }
        return Bundle.main.image(forResource: name)
    }
}
