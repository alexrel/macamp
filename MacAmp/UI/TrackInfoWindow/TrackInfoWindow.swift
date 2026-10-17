import Cocoa
import SwiftUI

public class TrackInfoWindow: NSWindow {
    public static var sharedController: TrackInfoWindowController?
    
    public static func show(trackIndex: Int) {
        if let existing = sharedController {
            existing.loadTrack(at: trackIndex)
            if let win = existing.window {
                let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
                win.level = (playerLevel == .floating) ? .modalPanel : .floating
                win.makeKeyAndOrderFront(nil)
                win.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let controller = TrackInfoWindowController(trackIndex: trackIndex)
        sharedController = controller
        controller.showWindow(nil)
        if let win = controller.window {
            let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
            win.level = (playerLevel == .floating) ? .modalPanel : .floating
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

public class TrackInfoWindowController: NSWindowController, NSWindowDelegate {
    private var currentTrackIndex: Int
    
    public init(trackIndex: Int) {
        self.currentTrackIndex = trackIndex
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 570),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MPEG Audio Info Box + ID3 Tag Editor"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 490)
        window.center()
        
        // Ensure Track Info window always stays on top of player windows
        let playerLevel = PlayerCoordinator.shared.mainWindow?.level ?? .normal
        window.level = (playerLevel == .floating) ? .modalPanel : .floating
        window.hidesOnDeactivate = false
        
        super.init(window: window)
        window.delegate = self
        
        loadTrack(at: trackIndex)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func loadTrack(at index: Int) {
        let playlist = PlayerCoordinator.shared.playlist
        guard index >= 0 && index < playlist.tracks.count else { return }
        self.currentTrackIndex = index
        let track = playlist.tracks[index]
        
        window?.title = "Track Info - \(track.url.lastPathComponent)"
        
        let viewModel = TrackInfoViewModel(
            url: track.url,
            trackIndex: index,
            totalTracks: playlist.tracks.count,
            onTrackChanged: { [weak self] newIndex in
                self?.loadTrack(at: newIndex)
            },
            onMetadataUpdated: { [weak self] updatedMetadata in
                self?.handleMetadataSaved(updatedMetadata, at: index)
            }
        )
        
        let hostingView = NSHostingView(rootView: TrackInfoView(viewModel: viewModel, onClose: { [weak self] in
            self?.close()
        }))
        
        window?.contentView = hostingView
    }
    
    private func handleMetadataSaved(_ meta: AudioFileMetadata, at index: Int) {
        let coordinator = PlayerCoordinator.shared
        let playlist = coordinator.playlist
        guard index >= 0 && index < playlist.tracks.count else { return }
        
        let old = playlist.tracks[index]
        let newTitle = meta.id3v2.title.isEmpty ? (meta.id3v1.title.isEmpty ? old.title : meta.id3v1.title) : meta.id3v2.title
        let newArtist = meta.id3v2.artist.isEmpty ? (meta.id3v1.artist.isEmpty ? old.artist : meta.id3v1.artist) : meta.id3v2.artist
        
        let updatedTrack = TrackItem(
            id: old.id,
            url: old.url,
            title: newTitle,
            artist: newArtist,
            duration: old.duration
        )
        
        // 1. Update playlist model item
        playlist.setTrack(at: index, updatedTrack)
        coordinator.plView?.needsDisplay = true
        
        // 2. If this is the currently playing track, update MarqueeView and audio metadata
        if playlist.currentIndex == index {
            let tickerText = (newArtist.isEmpty || newArtist == "Unknown Artist")
                ? newTitle.uppercased()
                : "\(newArtist) - \(newTitle)".uppercased()
            coordinator.mainView?.marquee.text = tickerText
            coordinator.audioEngine.updateCurrentMetadata(title: newTitle, artist: newArtist)
        }
    }
    
    public func windowWillClose(_ notification: Notification) {
        TrackInfoWindow.sharedController = nil
    }
}
