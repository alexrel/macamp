import Foundation

public struct AppState: Codable {
    public var volume: Double = AppConstants.Audio.defaultVolume
    public var balance: Double = AppConstants.Audio.defaultBalance
    
    public var isEqEnabled: Bool = true
    public var isEqAuto: Bool = false
    public var preampDb: Float = 0.0
    public var eqBandsDb: [Float] = Array(repeating: 0.0, count: 10)
    
    public var isShuffle: Bool = false
    public var isRepeat: Bool = false
    
    public var visualizerMode: VisualizerMode = .spectrum
    public var visualizerShowPeaks: Bool = true
    public var timeDisplayMode: TimeDisplayMode = .elapsed
    public var scaleFactor: ScaleFactor = .x1
    
    public var isMainWindowShade: Bool = false
    public var isEqWindowVisible: Bool = true
    public var isEqWindowShade: Bool = false
    public var isPlaylistVisible: Bool = true
    public var isPlaylistShade: Bool = false
    public var isAlwaysOnTop: Bool = false
    
    public var windowPositions: [String: [Double]] = [:]
    public var playlistWindowSize: [Double] = [Double(AppConstants.Window.width), Double(AppConstants.Window.height)]
    
    public var lastPlayedTrackURL: String? = nil
    public var lastPlayedTrackTime: Double = 0.0
    public var activeSkinPath: String? = nil
    
    // Preferences - Titles & Display
    public var marqueeFontMode: MarqueeFontMode = .bitmap
    public var desktopFontFamily: String = "Monaco"
    public var desktopFontSize: Double = 9.0
    public var showTrackNumberInTitle: Bool = true
    public var isMarqueeScrollEnabled: Bool = true
    public var windowSnapDistance: Int = 10
    
    // Preferences - Playlist
    public var showNumbersInPlaylist: Bool = true
    public var playlistZeroPadding: Bool = false
    public var playlistShowExtensions: Bool = false
    public var authenticShuffle: Bool = true
    
    // Preferences - Audio & Hotkeys
    public var audioFadeOutDurationMs: Double = 200.0
    public var autoGenreEQ: Bool = false
    public var isGlobalHotkeysEnabled: Bool = true
    
    // Preferences - DSP & Effects
    public var isDspEnabled: Bool = false
    public var dspPitchSemitones: Double = 0.0
    public var dspPlaybackRate: Double = 1.0
    public var dspReverbMix: Double = 0.0
    public var dspReverbPreset: Int = 1
    
    public init() {}
}

public enum MarqueeFontMode: String, Codable, CaseIterable {
    case bitmap = "bitmap"
    case desktop = "desktop"
}

public class PersistenceManager {
    public static let shared = PersistenceManager()
    
    public var state: AppState = AppState()
    
    private var baseDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("MacAmp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var sessionURL: URL {
        baseDir.appendingPathComponent("session.json")
    }
    
    private var playlistURL: URL {
        baseDir.appendingPathComponent("playlist.json")
    }
    
    private init() {
        loadSession()
    }
    
    public func loadSession() {
        guard let data = try? Data(contentsOf: sessionURL),
              let decoded = try? JSONDecoder().decode(AppState.self, from: data) else {
            return
        }
        self.state = decoded
    }
    
    public func saveSession() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: sessionURL)
        }
    }
    
    public func loadPlaylist() -> [TrackItem] {
        guard let data = try? Data(contentsOf: playlistURL),
              let decoded = try? JSONDecoder().decode([TrackItem].self, from: data) else {
            return []
        }
        return decoded
    }
    
    public func savePlaylist(_ tracks: [TrackItem]) {
        if let data = try? JSONEncoder().encode(tracks) {
            try? data.write(to: playlistURL)
        }
    }
}
