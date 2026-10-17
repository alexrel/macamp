import Cocoa
import MediaPlayer

/// Controls macOS system-wide media keys (F7, F8, F9, headphones, Touch Bar)
/// and publishes track metadata to macOS Control Center / Now Playing.
public final class MediaKeyController: NSObject {
    public static let shared = MediaKeyController()
    
    private override init() {
        super.init()
    }
    
    public func setup() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            PlayerCoordinator.shared.handlePlay()
            self?.updateNowPlayingInfo()
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            PlayerCoordinator.shared.handlePause()
            self?.updateNowPlayingInfo()
            return .success
        }
        
        // Toggle Play/Pause command (standard F8 / headphone single click)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            PlayerCoordinator.shared.handlePlayPause()
            self?.updateNowPlayingInfo()
            return .success
        }
        
        // Stop command
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            PlayerCoordinator.shared.handleStop()
            self?.updateNowPlayingInfo()
            return .success
        }
        
        // Next Track command (F9 / headphone double click)
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            PlayerCoordinator.shared.handleNext()
            self?.updateNowPlayingInfo()
            return .success
        }
        
        // Previous Track command (F7 / headphone triple click)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            PlayerCoordinator.shared.handlePrev()
            self?.updateNowPlayingInfo()
            return .success
        }
        
        // Seek position command
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            PlayerCoordinator.shared.seek(to: posEvent.positionTime)
            self?.updateNowPlayingInfo()
            return .success
        }
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
