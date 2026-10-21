import Cocoa
import MediaPlayer

/// Controls macOS system-wide media keys (F7, F8, F9, headphones, Touch Bar)
/// and publishes track metadata to macOS Control Center / Now Playing.
@MainActor
public final class MediaKeyController: NSObject {
    public static let shared = MediaKeyController()
    
    private override init() {
        super.init()
    }
    
    public func setup() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            MediaKeyController.onMain { PlayerCoordinator.shared.handlePlay() }
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            MediaKeyController.onMain { PlayerCoordinator.shared.handlePause() }
        }
        
        // Toggle Play/Pause command (standard F8 / headphone single click)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            MediaKeyController.onMain { PlayerCoordinator.shared.handlePlayPause() }
        }
        
        // Stop command
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { _ in
            MediaKeyController.onMain { PlayerCoordinator.shared.handleStop() }
        }
        
        // Next Track command (F9 / headphone double click)
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            MediaKeyController.onMain { PlayerCoordinator.shared.handleNext() }
        }
        
        // Previous Track command (F7 / headphone triple click)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            MediaKeyController.onMain { PlayerCoordinator.shared.handlePrev() }
        }
        
        // Seek position command
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = posEvent.positionTime
            return MediaKeyController.onMain { PlayerCoordinator.shared.seek(to: position) }
        }
    }
    
    /// Remote command handlers aren't main-actor isolated; run the action there and report success right away.
    private nonisolated static func onMain(_ action: @escaping @MainActor () -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor in
            action()
            MediaKeyController.shared.updateNowPlayingInfo()
        }
        return .success
    }
    
    public func updateNowPlayingInfo() {
        let coord = PlayerCoordinator.shared
        guard let track = coord.playlist.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track.title.isEmpty ? track.url.lastPathComponent : track.title
        if !track.artist.isEmpty {
            info[MPMediaItemPropertyArtist] = track.artist
        }
        if track.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = track.duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = coord.audioEngine.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = (coord.audioEngine.status == .playing) ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
