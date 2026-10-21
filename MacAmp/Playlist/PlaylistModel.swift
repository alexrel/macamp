import Foundation
import AVFoundation
import AudioToolbox

/// A tag with its values already loaded (AVFoundation loads them asynchronously).
public struct MetadataValues: Sendable {
    public let key: String
    public let commonKey: AVMetadataKey?
    public let string: String?
    public let number: NSNumber?
    public let data: Data?
    
    /// The asset's metadata items with their values; with `common`, the common-key items come first.
    public static func load(from asset: AVAsset, common: Bool = false) async -> [MetadataValues] {
        var items = (try? await asset.load(.metadata)) ?? []
        if common { items = ((try? await asset.load(.commonMetadata)) ?? []) + items }
        var result: [MetadataValues] = []
        for item in items {
            let key = (item.key as? String) ?? item.commonKey?.rawValue ?? item.identifier?.rawValue ?? ""
            let (string, number, data) = (try? await item.load(.stringValue, .numberValue, .dataValue)) ?? (nil, nil, nil)
            result.append(MetadataValues(key: key, commonKey: item.commonKey, string: string, number: number, data: data))
        }
        return result
    }
}

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
    
    /// Entry for a playlist line before its file is read: the title / duration the playlist file gave.
    public static func entry(url: URL, title: String? = nil, duration: TimeInterval = 0) -> TrackItem {
        guard url.isFileURL else {
            let name = url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent
            return TrackItem(url: url, title: title ?? name, artist: "Internet Stream", duration: duration)
        }
        return TrackItem(url: url, title: title ?? url.deletingPathExtension().lastPathComponent, duration: duration)
    }
    
    /// Creates a TrackItem with duration and tags read from the file. Tags win over the playlist's
    /// title; its duration is used only when the file has none.
    public static func create(from url: URL, titleFallback: String? = nil, durationFallback: TimeInterval = 0) async -> TrackItem {
        guard url.isFileURL else { return entry(url: url, title: titleFallback, duration: durationFallback) }
        let resolved = await resolveMetadataAsync(from: url)
        var title = resolved.title
        if let fallback = titleFallback, !fallback.isEmpty, title == url.deletingPathExtension().lastPathComponent {
            title = fallback
        }
        let duration = resolved.duration > 0 ? resolved.duration : durationFallback
        return TrackItem(url: url, title: title, artist: resolved.artist, duration: duration)
    }
    
    /// Reads the files of playlist entries in parallel (mostly waiting on disk), keeping their order and IDs.
    public static func resolveAll(_ entries: [TrackItem]) async -> [TrackItem] {
        await withTaskGroup(of: (Int, TrackItem).self) { group in
            for (i, entry) in entries.enumerated() {
                group.addTask {
                    let item = await create(from: entry.url, titleFallback: entry.title, durationFallback: entry.duration)
                    return (i, TrackItem(id: entry.id, url: item.url, title: item.title, artist: item.artist, duration: item.duration))
                }
            }
            var items = entries
            for await (i, item) in group { items[i] = item }
            return items
        }
    }
    
    public static func createAll(from urls: [URL]) async -> [TrackItem] {
        await resolveAll(urls.map { TrackItem(url: $0, title: "") })
    }
    
    /// AudioToolbox estimated duration (fastest & most resilient for MP3/AAC/VBR), then AVFoundation, then the PCM length.
    public static func resolveDuration(from url: URL) async -> TimeInterval {
        let estimated = estimatedDuration(of: url)
        if estimated > 0 { return estimated }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        if let time = try? await asset.load(.duration), time.seconds.isFinite, time.seconds > 0 {
            return time.seconds
        }
        if let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0, file.length > 0 {
            let d = Double(file.length) / file.processingFormat.sampleRate
            if d.isFinite && d > 0 { return d }
        }
        return 0
    }
    
    /// AudioToolbox estimated duration; 0 if unknown.
    static func estimatedDuration(of url: URL) -> TimeInterval {
        var fileID: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr, let fileID else { return 0 }
        defer { AudioFileClose(fileID) }
        var estimatedDuration: Float64 = 0
        var propSize = UInt32(MemoryLayout<Float64>.size)
        guard AudioFileGetProperty(fileID, kAudioFilePropertyEstimatedDuration, &propSize, &estimatedDuration) == noErr,
              estimatedDuration.isFinite, estimatedDuration > 0 else { return 0 }
        return TimeInterval(estimatedDuration)
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
    public static func resolveArtistAndTitle(from url: URL) async -> (artist: String, title: String) {
        let fileBaseName = url.deletingPathExtension().lastPathComponent
        var artist = "", title = fileBaseName
        // Common keys first, then raw ID3 / iTunes frames
        for item in await MetadataValues.load(from: AVURLAsset(url: url), common: true) {
            let isTitle = item.commonKey == .commonKeyTitle || item.key.contains("TIT2") || item.key.hasSuffix("©nam")
            let isArtist = item.commonKey == .commonKeyArtist || item.key.contains("TPE1") || item.key.hasSuffix("©ART")
            guard let value = item.string?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { continue }
            if isTitle && title == fileBaseName {
                title = TextEncoding.repairCyrillic(value)
            } else if isArtist && artist.isEmpty {
                artist = TextEncoding.repairCyrillic(value)
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
        async let duration = resolveDuration(from: url)
        let (artist, title) = await resolveArtistAndTitle(from: url)
        return (await duration, artist, title)
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
    
    /// Inserts tracks before `index` (clamped; `tracks.count` = append), keeping the current track,
    /// selection and shuffle order pointing at the same songs. Used for drops into the playlist.
    public func insert(tracks newTracks: [TrackItem], at index: Int) {
        guard !newTracks.isEmpty else { return }
        let position = max(0, min(index, tracks.count))
        let currentID = currentTrack?.id
        tracks.insert(contentsOf: newTracks, at: position)
        if let currentID {
            currentIndex = tracks.firstIndex { $0.id == currentID }
        } else {
            currentIndex = position
        }
        selectedIndices = Set(position..<(position + newTracks.count))
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
            var resolved: [(UUID, (artist: String, title: String))] = []
            for track in suspects {
                resolved.append((track.id, await TrackItem.resolveArtistAndTitle(from: track.url)))
            }
            guard let model = self else { return }
            let finalResolved = resolved
            await MainActor.run {
                model.applyMigratedMetadata(finalResolved)
                completion?()
            }
        }
    }
    
    private func applyMigratedMetadata(_ resolved: [(UUID, (artist: String, title: String))]) {
        for (id, meta) in resolved {
            guard let idx = tracks.firstIndex(where: { $0.id == id }) else { continue }
            let old = tracks[idx]
            tracks[idx] = TrackItem(id: old.id, url: old.url, title: meta.title, artist: meta.artist, duration: old.duration)
        }
        PersistenceManager.shared.savePlaylist(tracks)
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
    
    /// Winamp "Sort list by path and filename"
    public func sortByPath() {
        let currentID = currentTrack?.id
        tracks.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        if let currentID, let idx = tracks.firstIndex(where: { $0.id == currentID }) { currentIndex = idx }
        syncShuffleOrder()
    }
    
    /// Winamp "Read extended info on selection": re-reads tags and durations of the given tracks in the background.
    public func refreshMetadata(at indices: [Int], completion: (() -> Void)? = nil) {
        let targets = indices.filter { $0 >= 0 && $0 < tracks.count }.map { tracks[$0] }.filter { $0.url.isFileURL }
        guard !targets.isEmpty else {
            completion?()
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            var resolved: [(UUID, (artist: String, title: String))] = []
            var durations: [UUID: TimeInterval] = [:]
            for track in targets {
                resolved.append((track.id, await TrackItem.resolveArtistAndTitle(from: track.url)))
                durations[track.id] = await TrackItem.resolveDuration(from: track.url)
            }
            guard let model = self else { return }
            let finalResolved = resolved
            let finalDurations = durations
            await MainActor.run {
                model.applyMigratedMetadata(finalResolved)
                for (id, duration) in finalDurations where duration > 0 {
                    model.updateTrack(id: id, duration: duration)
                }
                completion?()
            }
        }
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
