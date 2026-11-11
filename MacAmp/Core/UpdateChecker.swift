import AppKit

/// Winamp's "Check for new versions at startup": asks GitHub for the latest release, at most once a day, and offers
/// to download it. The disk image is opened for the user; MacAmp never replaces itself.
public enum UpdateChecker {
    public struct Release: Equatable {
        public let version: String
        public let notes: String
        public let dmg: URL
    }

    /// The startup check runs at most this often
    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// Release notes in the offer are cut to this many characters
    static let notesLimit = 600
    static let diskImageSuffix = ".dmg"
    static let dialogTitle = "MacAmp update"
    /// A progress line stays this long if no newer one replaces it (a stalled download)
    static let progressHold: TimeInterval = 10

    /// "0.10" is newer than "0.9": compared number by number
    public static func isNewer(_ version: String, than current: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }, b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The release from GitHub's reply; nil when it has no disk image of ours
    public static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let link = assets.compactMap({ $0["browser_download_url"] as? String })
                .first(where: { $0.hasPrefix(AppConstants.App.releaseDownloadPrefix) && $0.hasSuffix(diskImageSuffix) }),
              let dmg = URL(string: link) else { return nil }
        let notes = (json["body"] as? String ?? "").replacingOccurrences(of: "\r\n", with: "\n")
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       notes: notes.count > notesLimit ? notes.prefix(notesLimit) + "…" : notes, dmg: dmg)
    }

    public static func isDue(last: Date?, now: Date = Date()) -> Bool {
        last.map { now.timeIntervalSince($0) >= checkInterval } ?? true
    }

    /// Downloads `url` to `target` (replacing it), reporting percent done on the main actor.
    static func download(_ url: URL, to target: URL, progress: @escaping @MainActor (Int) -> Void) async throws {
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            let task = MacAmpNetwork.session.downloadTask(with: url) { file, response, error in
                // The temporary file is gone once this returns: move it here
                done.resume(with: Result {
                    guard let file else { throw error ?? URLError(.unknown) }
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
                    _ = try? FileManager.default.removeItem(at: target) // the same release downloaded before
                    try FileManager.default.moveItem(at: file, to: target)
                })
            }
            observation = task.progress.observe(\.fractionCompleted) { taskProgress, _ in
                let percent = Int(taskProgress.fractionCompleted * 100)
                Task { @MainActor in progress(percent) }
            }
            task.resume()
        }
    }

    /// `manual`: the Check now button, which always asks and always answers. At startup: only when the setting is on,
    /// the last check is a day old, and silently unless there is a new version.
    @MainActor
    public static func check(manual: Bool) async {
        let persistence = PersistenceManager.shared
        if !manual {
            guard persistence.state.checkForUpdates, !MacAmpNetwork.isOffline, isDue(last: persistence.state.lastUpdateCheck) else { return }
        }
        var reportsErrors = manual, downloading = false
        do {
            if MacAmpNetwork.isOffline { throw MacAmpNetwork.offlineError }
            let (data, response) = try await MacAmpNetwork.session.data(from: AppConstants.App.latestRelease)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            persistence.state.lastUpdateCheck = Date()
            persistence.scheduleSave()
            let current = AppConstants.App.version
            guard let release = parse(data), isNewer(release.version, than: current) else {
                if manual { Win32Dialog.inform(title: dialogTitle, message: "MacAmp \(current) is the latest version.") }
                return
            }
            guard Win32Dialog.confirm(title: dialogTitle,
                                      message: "MacAmp \(release.version) is available (this is \(current)).\n\n\(release.notes)",
                                      confirmTitle: "Download", cancelTitle: "Later") else { return }
            reportsErrors = true // the user asked for the download: say so if it fails
            let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let target = downloads.appendingPathComponent(release.dmg.lastPathComponent)
            // Progress in the main window's song title line, where Winamp showed a stream buffering
            let marquee = PlayerCoordinator.shared.mainView?.marquee
            var shown = -1
            downloading = true
            marquee?.showTemporaryMessage("Downloading MacAmp \(release.version)...", duration: progressHold)
            try await download(release.dmg, to: target) { percent in
                guard percent != shown else { return }
                shown = percent
                marquee?.showTemporaryMessage("Downloading MacAmp \(release.version): \(percent)%", duration: progressHold)
            }
            marquee?.showTemporaryMessage("MacAmp \(release.version) downloaded")
            NSWorkspace.shared.open(target) // Finder shows the disk image: drag MacAmp to Applications
        } catch {
            if downloading { PlayerCoordinator.shared.mainView?.marquee.showTemporaryMessage("Download failed") }
            if reportsErrors { Win32Dialog.inform(title: dialogTitle, message: "Could not get the new version: \(error.localizedDescription)") }
        }
    }
}
