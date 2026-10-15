import Foundation
import AVFoundation

public struct TrackItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    
    public init(id: UUID = UUID(), url: URL, title: String, artist: String = "Unknown Artist", duration: TimeInterval = 0) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
    }
    
    /// Creates a TrackItem and extracts duration from audio file header immediately
    public static func create(from url: URL) -> TrackItem {
        var duration: TimeInterval = 0
        if let file = try? AVAudioFile(forReading: url) {
            let sr = file.processingFormat.sampleRate
            if sr > 0 {
                duration = Double(file.length) / sr
            }
        }
        let title = url.deletingPathExtension().lastPathComponent
        return TrackItem(url: url, title: title, artist: "Unknown Artist", duration: duration)
    }
    
    public var formattedDuration: String {
        guard duration > 0 else { return "0:00" }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    public func formattedTitle(with index: Int) -> String {
        return "\(index). \(artist) - \(title)"
    }
}

public class PlaylistModel: ObservableObject {
    @Published public private(set) var tracks: [TrackItem] = []
    @Published public var currentIndex: Int? = nil
    @Published public var selectedIndices: Set<Int> = []
    
    @Published public var isShuffle: Bool = false
    @Published public var isRepeat: Bool = false
    
    private var shuffleOrder: [Int] = []
    private var shufflePosition: Int = 0
    
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
        updateShuffleOrder()
        if currentIndex == nil {
            currentIndex = 0
        }
    }
    
    public func add(tracks newTracks: [TrackItem]) {
        tracks.append(contentsOf: newTracks)
        updateShuffleOrder()
        if currentIndex == nil && !tracks.isEmpty {
            currentIndex = 0
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
        updateShuffleOrder()
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
        updateShuffleOrder()
    }
    
    public func clear() {
        tracks.removeAll()
        selectedIndices.removeAll()
        currentIndex = nil
        shuffleOrder.removeAll()
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
    
    // MARK: - Sorting
    public func sortByTitle() {
        tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        updateShuffleOrder()
    }
    
    public func sortByFilename() {
        tracks.sort { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
        updateShuffleOrder()
    }
    
    public func reverse() {
        tracks.reverse()
        if let current = currentIndex {
            currentIndex = (tracks.count - 1) - current
        }
        updateShuffleOrder()
    }
    
    public func randomize() {
        tracks.shuffle()
        currentIndex = tracks.isEmpty ? nil : 0
        updateShuffleOrder()
    }
    
    // MARK: - Navigation
    public func next() -> TrackItem? {
        guard !tracks.isEmpty else { return nil }
        
        if isShuffle {
            guard !shuffleOrder.isEmpty else { return nil }
            shufflePosition += 1
            if shufflePosition >= shuffleOrder.count {
                if isRepeat {
                    shufflePosition = 0
                } else {
                    return nil
                }
            }
            let nextIdx = shuffleOrder[shufflePosition]
            currentIndex = nextIdx
            return tracks[nextIdx]
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
            guard !shuffleOrder.isEmpty else { return nil }
            shufflePosition = max(0, shufflePosition - 1)
            let prevIdx = shuffleOrder[shufflePosition]
            currentIndex = prevIdx
            return tracks[prevIdx]
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
    
    private func updateShuffleOrder() {
        shuffleOrder = Array(0..<tracks.count).shuffled()
        if let cur = currentIndex, let pos = shuffleOrder.firstIndex(of: cur) {
            shufflePosition = pos
        } else {
            shufflePosition = 0
        }
    }
}
