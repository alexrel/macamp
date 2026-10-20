import Foundation
import AVFoundation
import AudioToolbox

public struct TrackItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    
    public init(id: UUID = UUID(), url: URL, title: String, artist: String = "", duration: TimeInterval = 0) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
    }
    
    /// Creates a TrackItem and resolves duration and ID3 metadata immediately
    public static func create(from url: URL, titleFallback: String? = nil, durationFallback: TimeInterval = 0) -> TrackItem {
        if !url.isFileURL {
            let fallbackName = url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent
            let title = titleFallback ?? fallbackName
            return TrackItem(url: url, title: title, artist: "Internet Stream", duration: durationFallback)
        }
        
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        var duration = resolveDuration(from: url)
        if duration <= 0 && durationFallback > 0 {
            duration = durationFallback
        }
        
        var (artist, title) = resolveArtistAndTitle(from: url)
        if let fallback = titleFallback, !fallback.isEmpty, title == url.deletingPathExtension().lastPathComponent {
            title = fallback
        }
        
        return TrackItem(url: url, title: title, artist: artist, duration: duration)
    }
    
    public static func resolveDuration(from url: URL) -> TimeInterval {
        // 1. AudioToolbox estimated duration (fastest & most resilient for MP3/AAC/VBR)
        var fileID: AudioFileID?
        if AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr, let fileID = fileID {
            defer { AudioFileClose(fileID) }
            var estimatedDuration: Float64 = 0
            var propSize = UInt32(MemoryLayout<Float64>.size)
            if AudioFileGetProperty(fileID, kAudioFilePropertyEstimatedDuration, &propSize, &estimatedDuration) == noErr {
                if estimatedDuration.isFinite && estimatedDuration > 0 {
                    return TimeInterval(estimatedDuration)
                }
            }
        }
        
        // 2. AVURLAsset duration
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let assetDur = CMTimeGetSeconds(asset.duration)
        if assetDur.isFinite && assetDur > 0 {
            return assetDur
        }
        
        // 3. AVAudioFile length / sampleRate
        if let file = try? AVAudioFile(forReading: url) {
            let sr = file.processingFormat.sampleRate
            if sr > 0 && file.length > 0 {
                let d = Double(file.length) / sr
                if d.isFinite && d > 0 {
                    return d
                }
            }
        }
        
        return 0
    }
    
    /// "Artist - Title", or just the title when the artist is unknown (Winamp shows untagged files by file name).
    public static func displayName(artist: String, title: String) -> String {
        (artist.isEmpty || artist == legacyUnknownArtist) ? title : "\(artist) - \(title)"
    }
    
    public var displayName: String { TrackItem.displayName(artist: artist, title: title) }
    
    /// Placeholder older versions stored for untagged files; treated as "no artist".
    public static let legacyUnknownArtist = "Unknown Artist"
    
    /// Reads title/artist tags. Without tags the artist stays empty and the title is the file name,
    /// like Winamp: no guessing from separators, because file names don't follow one order
    /// ("Song - Artist - Cover [id]", "Song ｜ Artist ｜ Cover [id]", "Artist - Song", ...).
    public static func resolveArtistAndTitle(from url: URL) -> (artist: String, title: String) {
        var artist = ""
        let fileBaseName = url.deletingPathExtension().lastPathComponent
        var title = fileBaseName
        
        let asset = AVURLAsset(url: url)
        for item in asset.commonMetadata {
            if item.commonKey == .commonKeyTitle, let val = item.stringValue, !val.trimmingCharacters(in: .whitespaces).isEmpty {
                title = TextEncoding.repairCyrillic(val.trimmingCharacters(in: .whitespaces))
            } else if item.commonKey == .commonKeyArtist, let val = item.stringValue, !val.trimmingCharacters(in: .whitespaces).isEmpty {
                artist = TextEncoding.repairCyrillic(val.trimmingCharacters(in: .whitespaces))
            }
        }
        
        if artist.isEmpty || title == fileBaseName {
            for item in asset.metadata {
                let keyStr = (item.key as? String) ?? item.commonKey?.rawValue ?? item.identifier?.rawValue ?? ""
                if (keyStr == "TIT2" || keyStr.contains("TIT2") || keyStr.hasSuffix("©nam")) && title == fileBaseName {
                    if let val = item.stringValue, !val.trimmingCharacters(in: .whitespaces).isEmpty {
                        title = TextEncoding.repairCyrillic(val.trimmingCharacters(in: .whitespaces))
                    }
                } else if (keyStr == "TPE1" || keyStr.contains("TPE1") || keyStr.hasSuffix("©ART")) && artist.isEmpty {
                    if let val = item.stringValue, !val.trimmingCharacters(in: .whitespaces).isEmpty {
                        artist = TextEncoding.repairCyrillic(val.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        }
        
        if title == fileBaseName {
            // Names extracted from old ZIP/CD rips may themselves be CP1251 mojibake
            title = TextEncoding.repairCyrillic(fileBaseName)
        }
        
        return (artist, title)
    }
    
    public static func resolveMetadataAsync(from url: URL) async -> (duration: TimeInterval, artist: String, title: String) {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        var duration = resolveDuration(from: url)
        var (artist, title) = resolveArtistAndTitle(from: url)
        
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        if duration <= 0 {
            if let cmTime = try? await asset.load(.duration), cmTime.seconds.isFinite && cmTime.seconds > 0 {
                duration = cmTime.seconds
            }
        }
        
        if let metadata = try? await asset.load(.metadata) {
            for item in metadata {
                let keyStr = (item.key as? String) ?? item.commonKey?.rawValue ?? item.identifier?.rawValue ?? ""
                if (item.commonKey == .commonKeyTitle || keyStr == "TIT2" || keyStr.hasSuffix("©nam")),
                   let val = try? await item.load(.stringValue), !val.trimmingCharacters(in: .whitespaces).isEmpty {
                    title = TextEncoding.repairCyrillic(val.trimmingCharacters(in: .whitespaces))
                } else if (item.commonKey == .commonKeyArtist || keyStr == "TPE1" || keyStr.hasSuffix("©ART")),
                          let val = try? await item.load(.stringValue), !val.trimmingCharacters(in: .whitespaces).isEmpty {
                    artist = TextEncoding.repairCyrillic(val.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        
        return (duration, artist, title)
    }
    
    public var formattedDuration: String {
        guard duration > 0 else { return "0:00" }
        return PlaylistModel.formatTime(duration)
    }
    
    public func formattedTitle(with index: Int) -> String {
        let state = PersistenceManager.shared.state
        var prefix = ""
        if state.showNumbersInPlaylist {
            if state.playlistZeroPadding {
                prefix = String(format: "%02d. ", index)
            } else {
                prefix = "\(index). "
            }
        }
        var name = displayName
        if state.playlistShowExtensions && !url.pathExtension.isEmpty {
            name += ".\(url.pathExtension)"
        }
        return prefix + name
    }
}

public class PlaylistModel: ObservableObject {
    @Published public private(set) var tracks: [TrackItem] = []
    @Published public var currentIndex: Int? = nil {
        didSet { if !isUpdatingShuffle { alignShuffleToCurrent() } }
    }
    @Published public var selectedIndices: Set<Int> = []
    
    @Published public var isShuffle: Bool = false {
        didSet { if isShuffle && !oldValue { rebuildShuffleOrder() } }
    }
    @Published public var isRepeat: Bool = false
    
    /// Shuffle play order stored by track ID, so sorting/moving/removing tracks never invalidates it.
    /// Entries before `shufflePosition` are history (Previous), entries after it are still unplayed.
    private var shuffleOrder: [UUID] = []
    private var shufflePosition: Int = 0
    private var isUpdatingShuffle = false
    
    public init() {}
    
    public var currentTrack: TrackItem? {
        guard let idx = currentIndex, idx >= 0, idx < tracks.count else { return nil }
        return tracks[idx]
    }
    
    public var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
    
    public var selectedDuration: TimeInterval {
        if selectedIndices.isEmpty {
            if let cur = currentTrack {
                return cur.duration
            }
            return 0
        }
        return selectedIndices.reduce(0) { sum, idx in
            if idx >= 0 && idx < tracks.count {
                return sum + tracks[idx].duration
            }
            return sum
        }
    }
    
    public static func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }
    
    public var formattedTotalDuration: String {
        PlaylistModel.formatTime(totalDuration)
    }
    
    public var runningTimeMessage: String {
        let selStr = PlaylistModel.formatTime(selectedDuration)
        let totalStr = PlaylistModel.formatTime(totalDuration)
        return "\(selStr)/\(totalStr)"
    }
    
    // MARK: - Mutating Methods
    public func add(track: TrackItem) {
        tracks.append(track)
        if currentIndex == nil {
            currentIndex = 0
        }
        syncShuffleOrder()
        prefetchMetadata(for: [track.id])
    }
    
    public func add(tracks newTracks: [TrackItem]) {
        tracks.append(contentsOf: newTracks)
        if currentIndex == nil && !tracks.isEmpty {
            currentIndex = 0
        }
        syncShuffleOrder()
        prefetchMetadata(for: newTracks.map { $0.id })
    }
    
    public func updateTrack(id: UUID, duration: TimeInterval? = nil, artist: String? = nil, title: String? = nil) {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        updateTrack(at: idx, duration: duration, artist: artist, title: title)
    }
    
    public func updateTrack(url: URL, duration: TimeInterval? = nil, artist: String? = nil, title: String? = nil) {
        guard let idx = tracks.firstIndex(where: { $0.url == url }) else { return }
        updateTrack(at: idx, duration: duration, artist: artist, title: title)
    }
    
    public func updateTrack(at index: Int, duration: TimeInterval? = nil, artist: String? = nil, title: String? = nil) {
        guard index >= 0, index < tracks.count else { return }
        let old = tracks[index]
        let newDuration = (duration != nil && duration! > 0) ? duration! : old.duration
        let newArtist = (artist != nil && !artist!.isEmpty && artist != TrackItem.legacyUnknownArtist) ? artist! : old.artist
        let newTitle = (title != nil && !title!.isEmpty) ? title! : old.title
        
        guard newDuration != old.duration || newArtist != old.artist || newTitle != old.title else { return }
        
        tracks[index] = TrackItem(
            id: old.id,
            url: old.url,
            title: newTitle,
            artist: newArtist,
            duration: newDuration
        )
    }
    
    /// Re-reads tags of playlists saved by older versions, which stored "Unknown Artist" for untagged files
    /// and split file names on " - " (often putting the song name into the artist field).
    /// Runs off the main thread; returns immediately.
    public func migrateLegacyFileNameMetadata(completion: (() -> Void)? = nil) {
        let suspects = tracks.filter { track in
            guard track.url.isFileURL else { return false }
            let base = track.url.deletingPathExtension().lastPathComponent
            return track.artist == TrackItem.legacyUnknownArtist || "\(track.artist) - \(track.title)" == base
        }
        guard !suspects.isEmpty else {
            completion?()
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            let resolved = suspects.map { ($0.id, TrackItem.resolveArtistAndTitle(from: $0.url)) }
            await MainActor.run {
                guard let self else { return }
                for (id, meta) in resolved {
                    guard let idx = self.tracks.firstIndex(where: { $0.id == id }) else { continue }
                    let old = self.tracks[idx]
                    self.tracks[idx] = TrackItem(id: old.id, url: old.url, title: meta.title, artist: meta.artist, duration: old.duration)
                }
                PersistenceManager.shared.savePlaylist(self.tracks)
                completion?()
            }
        }
    }
    
    public func setTrack(at index: Int, _ track: TrackItem) {
        guard index >= 0, index < tracks.count else { return }
        tracks[index] = track
    }
    
    public func prefetchMetadata(for ids: [UUID]) {
        let targets = tracks.filter { ids.contains($0.id) && $0.duration <= 0 }
        guard !targets.isEmpty else { return }
        
        Task { [weak self] in
            for target in targets {
                let resolved = await TrackItem.resolveMetadataAsync(from: target.url)
                await MainActor.run { [weak self] in
                    self?.updateTrack(
                        id: target.id,
                        duration: resolved.duration,
                        artist: resolved.artist,
                        title: resolved.title
                    )
                }
            }
        }
    }
    
    public func remove(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        tracks.remove(at: index)
        selectedIndices.remove(index)
        
        if let current = currentIndex {
            if current == index {
                currentIndex = tracks.isEmpty ? nil : min(index, tracks.count - 1)
            } else if current > index {
                currentIndex = current - 1
            }
        }
        syncShuffleOrder()
    }
    
    public func removeSelected() {
        let toRemove = selectedIndices.sorted(by: >)
        for idx in toRemove {
            remove(at: idx)
        }
        selectedIndices.removeAll()
    }
    
    public func crop() {
        guard !selectedIndices.isEmpty else { return }
        tracks = tracks.enumerated().filter { selectedIndices.contains($0.offset) }.map { $0.element }
        selectedIndices.removeAll()
        currentIndex = tracks.isEmpty ? nil : 0
        syncShuffleOrder()
    }
    
    public func clear() {
        tracks.removeAll()
        selectedIndices.removeAll()
        currentIndex = nil
        shuffleOrder.removeAll()
        shufflePosition = 0
    }
    
    /// Reorders the specified tracks and inserts them at destinationIndex
    public func moveTracks(from sourceIndices: Set<Int>, to destinationIndex: Int) {
        guard !sourceIndices.isEmpty, destinationIndex >= 0, destinationIndex <= tracks.count else { return }
        
        let currentTrackID = currentTrack?.id
        let sortedSources = sourceIndices.sorted()
        let itemsToMove = sortedSources.map { tracks[$0] }
        
        // Remove items from tracks
        var remainingTracks: [TrackItem] = []
        for (i, t) in tracks.enumerated() {
            if !sourceIndices.contains(i) {
                remainingTracks.append(t)
            }
        }
        
        // Calculate new insertion index taking into account removed items preceding destination
        let numRemovedBeforeDest = sortedSources.filter { $0 < destinationIndex }.count
        let adjustedDest = max(0, min(destinationIndex - numRemovedBeforeDest, remainingTracks.count))
        
        remainingTracks.insert(contentsOf: itemsToMove, at: adjustedDest)
        self.tracks = remainingTracks
        
        // Update selection to match new indices of moved items
        var newSelected: Set<Int> = []
        for i in 0..<itemsToMove.count {
            newSelected.insert(adjustedDest + i)
        }
        self.selectedIndices = newSelected
        
        // Update currentIndex to follow currently playing track
        if let curID = currentTrackID, let newIdx = tracks.firstIndex(where: { $0.id == curID }) {
            self.currentIndex = newIdx
        }
        
        syncShuffleOrder()
        PersistenceManager.shared.savePlaylist(tracks)
    }
    
    // MARK: - Selection
    public func selectAll() {
        selectedIndices = Set(0..<tracks.count)
    }
    
    public func selectNone() {
        selectedIndices.removeAll()
    }
    
    public func invertSelection() {
        let all = Set(0..<tracks.count)
        selectedIndices = all.subtracting(selectedIndices)
    }
    
    @discardableResult
    public func removeDeadFiles() -> Int {
        let beforeCount = tracks.count
        tracks.removeAll { track in
            track.url.isFileURL && !FileManager.default.fileExists(atPath: track.url.path)
        }
        if let cur = currentIndex, cur >= tracks.count {
            currentIndex = tracks.isEmpty ? nil : tracks.count - 1
        }
        selectedIndices.removeAll()
        syncShuffleOrder()
        return beforeCount - tracks.count
    }
    
    @discardableResult
    public func removeDuplicates() -> Int {
        var seenURLs = Set<URL>()
        var unique: [TrackItem] = []
        for track in tracks {
            if !seenURLs.contains(track.url) {
                seenURLs.insert(track.url)
                unique.append(track)
            }
        }
        let removed = tracks.count - unique.count
        tracks = unique
        if let cur = currentIndex, cur >= tracks.count {
            currentIndex = tracks.isEmpty ? nil : tracks.count - 1
        }
        selectedIndices.removeAll()
        syncShuffleOrder()
        return removed
    }
    
    // MARK: - Sorting
    public func sortByTitle() {
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        syncShuffleOrder()
    }
    
    public func sortByFilename() {
        tracks.sort { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
        syncShuffleOrder()
    }
    
    public func reverse() {
        tracks.reverse()
        if let current = currentIndex {
            currentIndex = (tracks.count - 1) - current
        }
        syncShuffleOrder()
    }
    
    public func randomize() {
        tracks.shuffle()
        currentIndex = tracks.isEmpty ? nil : 0
        rebuildShuffleOrder()
    }
    
    // MARK: - Navigation
    public func next() -> TrackItem? {
        guard !tracks.isEmpty else { return nil }
        
        if isShuffle {
            if shuffleOrder.count != tracks.count { syncShuffleOrder() }
            guard !shuffleOrder.isEmpty else { return nil }
            if shufflePosition + 1 >= shuffleOrder.count {
                guard isRepeat else { return nil }
                // New pass: fresh order that does not start with the track that just finished
                rebuildShuffleOrder(keepCurrentFirst: false)
                if shuffleOrder.count > 1, shuffleOrder.first == currentTrack?.id {
                    shuffleOrder.swapAt(0, Int.random(in: 1..<shuffleOrder.count))
                }
                shufflePosition = 0
            } else {
                shufflePosition += 1
            }
            return selectShuffleEntry()
        } else {
            guard let cur = currentIndex else {
                currentIndex = 0
                return tracks.first
            }
            let nextIdx = cur + 1
            if nextIdx < tracks.count {
                currentIndex = nextIdx
                return tracks[nextIdx]
            } else if isRepeat {
                currentIndex = 0
                return tracks.first
            }
            return nil
        }
    }
    
    public func previous() -> TrackItem? {
        guard !tracks.isEmpty else { return nil }
        
        if isShuffle {
            if shuffleOrder.count != tracks.count { syncShuffleOrder() }
            guard !shuffleOrder.isEmpty else { return nil }
            shufflePosition = max(0, shufflePosition - 1)
            return selectShuffleEntry()
        } else {
            guard let cur = currentIndex else {
                currentIndex = 0
                return tracks.first
            }
            let prevIdx = cur - 1
            if prevIdx >= 0 {
                currentIndex = prevIdx
                return tracks[prevIdx]
            } else if isRepeat {
                currentIndex = tracks.count - 1
                return tracks.last
            }
            return nil
        }
    }
    
    // MARK: - Shuffle Order
    
    /// Makes the entry at `shufflePosition` the current track.
    private func selectShuffleEntry() -> TrackItem? {
        let id = shuffleOrder[shufflePosition]
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return nil }
        isUpdatingShuffle = true
        currentIndex = idx
        isUpdatingShuffle = false
        return tracks[idx]
    }
    
    /// Builds a new random order. By default the current track goes first so every other track is still ahead.
    private func rebuildShuffleOrder(keepCurrentFirst: Bool = true) {
        let currentID = currentTrack?.id
        var ids = tracks.map(\.id).shuffled()
        if keepCurrentFirst, let currentID, let pos = ids.firstIndex(of: currentID) {
            ids.remove(at: pos)
            ids.insert(currentID, at: 0)
        }
        shuffleOrder = ids
        shufflePosition = 0
    }
    
    /// Reconciles the order with the track list after a mutation: drops removed tracks,
    /// inserts new ones at random places among the unplayed entries, and re-aligns to the current track.
    private func syncShuffleOrder() {
        guard !shuffleOrder.isEmpty else {
            rebuildShuffleOrder()
            return
        }
        let liveIDs = Set(tracks.map(\.id))
        var order = shuffleOrder.filter { liveIDs.contains($0) }
        // New position = surviving entries that were before the old position
        let pos = shuffleOrder.prefix(shufflePosition).filter { liveIDs.contains($0) }.count
        let known = Set(order)
        for track in tracks where !known.contains(track.id) {
            let lower = min(pos + 1, order.count)
            order.insert(track.id, at: Int.random(in: lower...order.count))
        }
        shuffleOrder = order
        shufflePosition = min(pos, max(0, order.count - 1))
        alignShuffleToCurrent()
    }
    
    /// Called when the current track is chosen directly (double-click, Jump to File, restore).
    /// Moves that track right after the current shuffle position so history and the unplayed
    /// remainder stay intact.
    private func alignShuffleToCurrent() {
        // During a mutation the order is stale; syncShuffleOrder() re-aligns once it has reconciled it
        guard let currentID = currentTrack?.id, !shuffleOrder.isEmpty, shuffleOrder.count == tracks.count else { return }
        if shufflePosition < shuffleOrder.count, shuffleOrder[shufflePosition] == currentID { return }
        guard let oldPos = shuffleOrder.firstIndex(of: currentID) else { return }
        shuffleOrder.remove(at: oldPos)
        var target = shufflePosition + 1
        if oldPos < target { target -= 1 }
        target = min(max(0, target), shuffleOrder.count)
        shuffleOrder.insert(currentID, at: target)
        shufflePosition = target
    }
}
