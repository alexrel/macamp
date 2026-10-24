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
    // Setup (Optional storage so session.json files from older versions still decode)
    public var documentIconIDsStorage: [String: Int]? = nil
    public var networkOfflineStorage: Bool? = nil
    public var httpProxyStorage: String? = nil
    public var showMenuBarIconStorage: Bool? = nil
    /// Winamp "File icon" / "Playlist icon" choice: kind -> winamp.exe icon resource ID
    public var documentIconIDs: [String: Int] {
        get { documentIconIDsStorage ?? [:] }
        set { documentIconIDsStorage = newValue }
    }
    /// Winamp "No Internet connection available": never open network streams
    public var networkOffline: Bool {
        get { networkOfflineStorage ?? false }
        set { networkOfflineStorage = newValue }
    }
    /// Winamp "HTTP proxy: 'Server:Port' (blank for none)"
    public var httpProxy: String {
        get { httpProxyStorage ?? "" }
        set { httpProxyStorage = newValue }
    }
    public var showMenuBarIcon: Bool {
        get { showMenuBarIconStorage ?? true }
        set { showMenuBarIconStorage = newValue }
    }
    
    // Setup ▸ File types (Optional storage so session.json files from older versions still decode)
    public var fileAssociationsStorage: [String]? = nil
    public var fileAssociationPreviousStorage: [String: String]? = nil
    public var registerFileTypesOnStartStorage: Bool? = nil
    public var enqueueAsDefaultActionStorage: Bool? = nil
    /// Extensions the user wants opened by MacAmp
    public var fileAssociations: [String] {
        get { fileAssociationsStorage ?? [] }
        set { fileAssociationsStorage = newValue }
    }
    /// UTI -> path of the app that was the default before MacAmp took the type over
    public var fileAssociationPrevious: [String: String] {
        get { fileAssociationPreviousStorage ?? [:] }
        set { fileAssociationPreviousStorage = newValue }
    }
    /// Winamp "Register types on Winamp start" (on by default, as in Winamp)
    public var registerFileTypesOnStart: Bool {
        get { registerFileTypesOnStartStorage ?? true }
        set { registerFileTypesOnStartStorage = newValue }
    }
    /// Winamp "Enqueue as default action": files opened from Finder are added to the playlist instead of played
    public var enqueueAsDefaultAction: Bool {
        get { enqueueAsDefaultActionStorage ?? false }
        set { enqueueAsDefaultActionStorage = newValue }
    }
    
    /// Winamp Options: titles from file names get %20 / underscores shown as spaces (both on in 2.95)
    public var convertPercent20Storage: Bool? = nil
    public var convertUnderscoreStorage: Bool? = nil
    public var convertPercent20: Bool {
        get { convertPercent20Storage ?? true }
        set { convertPercent20Storage = newValue }
    }
    public var convertUnderscore: Bool {
        get { convertUnderscoreStorage ?? true }
        set { convertUnderscoreStorage = newValue }
    }
    /// Winamp Display: "Use Winamp-styled (skinned) cursors"
    public var useSkinnedCursorsStorage: Bool? = nil
    public var useSkinnedCursors: Bool {
        get { useSkinnedCursorsStorage ?? true }
        set { useSkinnedCursorsStorage = newValue }
    }
    /// Winamp Plug-ins: "Auto execute visualization plug-in on play" (the Retro Visualizer Studio)
    public var autoStartVisPluginStorage: Bool? = nil
    public var autoStartVisPlugin: Bool {
        get { autoStartVisPluginStorage ?? false }
        set { autoStartVisPluginStorage = newValue }
    }
    
    /// Display: "Dim titlebars when inactive" and "Display tooltips in Winamp's main window" (both on in 2.95)
    public var dimTitlebarsStorage: Bool? = nil
    public var dimTitlebars: Bool {
        get { dimTitlebarsStorage ?? true }
        set { dimTitlebarsStorage = newValue }
    }
    public var mainWindowTooltipsStorage: Bool? = nil
    public var mainWindowTooltips: Bool {
        get { mainWindowTooltipsStorage ?? true }
        set { mainWindowTooltipsStorage = newValue }
    }
    /// Shuffle morph rate 0 (slow: each pass a slight variation of the last) ... 1 (fast: a new order every pass)
    public var shuffleMorphRateStorage: Double? = nil
    public var shuffleMorphRate: Double {
        get { shuffleMorphRateStorage ?? 0.9 } // 2.95: "The default is very close to 'Fast'"
        set { shuffleMorphRateStorage = newValue }
    }
    /// Skins: "Random skin on play"
    public var randomSkinOnPlayStorage: Bool? = nil
    public var randomSkinOnPlay: Bool {
        get { randomSkinOnPlayStorage ?? false }
        set { randomSkinOnPlayStorage = newValue }
    }
    
    /// Options ▸ Media Library: double-click / Enter enqueues instead of playing; radio stations to fetch
    public var libraryDoubleClickEnqueuesStorage: Bool? = nil
    public var libraryDoubleClickEnqueues: Bool {
        get { libraryDoubleClickEnqueuesStorage ?? false }
        set { libraryDoubleClickEnqueuesStorage = newValue }
    }
    public var libraryMaxStreamsStorage: Int? = nil
    public var libraryMaxStreams: Int {
        get { libraryMaxStreamsStorage ?? 500 }
        set { libraryMaxStreamsStorage = newValue }
    }
    /// Options ▸ Library (2.95 General tab)
    public var libraryRememberSearchStorage: Bool? = nil
    public var libraryRememberSearch: Bool { get { libraryRememberSearchStorage ?? false } set { libraryRememberSearchStorage = newValue } }
    /// Column resizing: 0 Normal, 1 Selected column only, 2 Proportional (SkinnedListController.resized)
    public var libraryColumnResizingStorage: Int? = nil
    public var libraryColumnResizing: Int { get { libraryColumnResizingStorage ?? 0 } set { libraryColumnResizingStorage = newValue } }
    /// Remembered search text per list (Local Media, each view)
    public var librarySearchesStorage: [String: String]? = nil
    public var librarySearches: [String: String] { get { librarySearchesStorage ?? [:] } set { librarySearchesStorage = newValue } }
    public var libraryPlayWholePlaylistStorage: Bool? = nil
    public var libraryPlayWholePlaylist: Bool { get { libraryPlayWholePlaylistStorage ?? true } set { libraryPlayWholePlaylistStorage = newValue } }
    public var libraryPlayWholeQueryStorage: Bool? = nil
    public var libraryPlayWholeQuery: Bool { get { libraryPlayWholeQueryStorage ?? false } set { libraryPlayWholeQueryStorage = newValue } }
    public var libraryOnLightningBoltStorage: Bool? = nil
    public var libraryOnLightningBolt: Bool { get { libraryOnLightningBoltStorage ?? true } set { libraryOnLightningBoltStorage = newValue } }
    public var libraryTVButtonOpensVideoStorage: Bool? = nil
    public var libraryTVButtonOpensVideo: Bool { get { libraryTVButtonOpensVideoStorage ?? true } set { libraryTVButtonOpensVideoStorage = newValue } }
    /// Library dividers (dragged, remembered): tree width, Audio page's top panes height, Artist share of their width
    public var libraryTreeWidthStorage: Double? = nil
    public var libraryTreeWidth: Double { get { libraryTreeWidthStorage ?? 132 } set { libraryTreeWidthStorage = newValue } }
    public var libraryPanesHeightStorage: Double? = nil
    public var libraryPanesHeight: Double { get { libraryPanesHeightStorage ?? 110 } set { libraryPanesHeightStorage = newValue } }
    public var libraryArtistFractionStorage: Double? = nil
    public var libraryArtistFraction: Double { get { libraryArtistFractionStorage ?? 0.5 } set { libraryArtistFractionStorage = newValue } }
    /// Internet Radio tab: how old the cached station list may get (hours; 0 = never refresh by itself)
    public var radioRefreshHoursStorage: Int? = nil
    public var radioRefreshHours: Int { get { radioRefreshHoursStorage ?? 1 } set { radioRefreshHoursStorage = newValue } }

    /// Options ▸ Media Library: rescan the library folders at startup
    public var libraryRescanOnStartStorage: Bool? = nil
    public var libraryRescanOnStart: Bool {
        get { libraryRescanOnStartStorage ?? false }
        set { libraryRescanOnStartStorage = newValue }
    }
    
    /// File types ▸ "Associate with audio CDs": while MacAmp runs, an inserted audio CD plays (macOS keeps its own
    /// system-wide choice of app for CDs; MacAmp doesn't change it)
    public var playInsertedAudioCDsStorage: Bool? = nil
    public var playInsertedAudioCDs: Bool {
        get { playInsertedAudioCDsStorage ?? false }
        set { playInsertedAudioCDsStorage = newValue }
    }

    /// Visualization ▸ Refresh rate (10...40 fps; 2.95's default is 35)
    public var visualizerFPSStorage: Double? = nil
    public var visualizerFPS: Double {
        get { visualizerFPSStorage ?? 35 }
        set { visualizerFPSStorage = newValue }
    }

    /// Skins ▸ "Set skins directory..." (nil: Application Support/MacAmp/Skins)
    public var skinsDirectoryPath: String? = nil

    /// Video ▸ Subtitles: the language picked last, picked again in the next video (nil: subtitles off)
    public var videoSubtitleLanguage: String? = nil

    /// Options ▸ Video (the 2.95 page without its Windows-only overlay / DirectDraw settings)
    public var videoKeepAspectStorage: Bool? = nil
    public var videoKeepAspect: Bool { get { videoKeepAspectStorage ?? true } set { videoKeepAspectStorage = newValue } }
    public var videoAutoOpenStorage: Bool? = nil
    public var videoAutoOpen: Bool { get { videoAutoOpenStorage ?? true } set { videoAutoOpenStorage = newValue } }
    public var videoAutoResizeStorage: Bool? = nil
    public var videoAutoResize: Bool { get { videoAutoResizeStorage ?? true } set { videoAutoResizeStorage = newValue } }
    public var videoAutoCloseStorage: Bool? = nil
    public var videoAutoClose: Bool { get { videoAutoCloseStorage ?? true } set { videoAutoCloseStorage = newValue } }
    public var videoRemoveFullscreenOnStopStorage: Bool? = nil
    public var videoRemoveFullscreenOnStop: Bool { get { videoRemoveFullscreenOnStopStorage ?? false } set { videoRemoveFullscreenOnStopStorage = newValue } }
    public var videoDisableScreensaverStorage: Bool? = nil
    public var videoDisableScreensaver: Bool { get { videoDisableScreensaverStorage ?? true } set { videoDisableScreensaverStorage = newValue } }
    public var videoStopOnCloseStorage: Bool? = nil
    public var videoStopOnClose: Bool { get { videoStopOnCloseStorage ?? true } set { videoStopOnCloseStorage = newValue } }

    /// Options ▸ CD Ripping: where, how named, which encoder, tags, add to the library
    public var cdRipFolderStorage: String? = nil
    public var cdRipFolder: URL {
        get { cdRipFolderStorage.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0] }
        set { cdRipFolderStorage = newValue.path }
    }
    public var cdRipTemplateStorage: String? = nil
    public var cdRipTemplate: String {
        get { cdRipTemplateStorage ?? "<Artist> - <Album>/<#> - <Title>" }
        set { cdRipTemplateStorage = newValue }
    }
    public var cdRipFormatStorage: DiskWriterFormat? = nil
    public var cdRipFormat: DiskWriterFormat {
        get { cdRipFormatStorage ?? .flac }
        set { cdRipFormatStorage = newValue }
    }
    public var cdRipAACKbpsStorage: Int? = nil
    public var cdRipAACKbps: Int { get { cdRipAACKbpsStorage ?? 256 } set { cdRipAACKbpsStorage = newValue } }
    public var cdRipWriteTagsStorage: Bool? = nil
    public var cdRipWriteTags: Bool {
        get { cdRipWriteTagsStorage ?? true }
        set { cdRipWriteTagsStorage = newValue }
    }
    public var cdRipAddToLibraryStorage: Bool? = nil
    public var cdRipAddToLibrary: Bool {
        get { cdRipAddToLibraryStorage ?? true }
        set { cdRipAddToLibraryStorage = newValue }
    }
    /// CD Ripping ▸ Playlist (2.95): M3U (extended) / PLS of the extracted CD, name from a template like the files'
    public var cdRipM3UStorage: Bool? = nil
    public var cdRipM3U: Bool { get { cdRipM3UStorage ?? true } set { cdRipM3UStorage = newValue } }
    public var cdRipExtendedM3UStorage: Bool? = nil
    public var cdRipExtendedM3U: Bool { get { cdRipExtendedM3UStorage ?? true } set { cdRipExtendedM3UStorage = newValue } }
    public var cdRipPLSStorage: Bool? = nil
    public var cdRipPLS: Bool { get { cdRipPLSStorage ?? false } set { cdRipPLSStorage = newValue } }
    public var cdRipPlaylistTemplateStorage: String? = nil
    public var cdRipPlaylistTemplate: String {
        get { cdRipPlaylistTemplateStorage ?? "<Artist> - <Album>/<Artist> - <Album>" }
        set { cdRipPlaylistTemplateStorage = newValue }
    }
    public var cdRipLibraryPlaylistStorage: Bool? = nil
    public var cdRipLibraryPlaylist: Bool { get { cdRipLibraryPlaylistStorage ?? true } set { cdRipLibraryPlaylistStorage = newValue } }
    
    /// Plug-ins ▸ Output: Disk Writer (out_disk) instead of the speakers, with its folder and format
    public var diskWriterEnabledStorage: Bool? = nil
    public var diskWriterFolderStorage: String? = nil
    public var diskWriterFormatStorage: DiskWriterFormat? = nil
    public var diskWriterEnabled: Bool {
        get { diskWriterEnabledStorage ?? false }
        set { diskWriterEnabledStorage = newValue }
    }
    public var diskWriterFolder: URL {
        get { diskWriterFolderStorage.map { URL(fileURLWithPath: $0) } ?? DiskWriter.defaultFolder }
        set { diskWriterFolderStorage = newValue.path }
    }
    public var diskWriterFormat: DiskWriterFormat {
        get { diskWriterFormatStorage ?? .wav }
        set { diskWriterFormatStorage = newValue }
    }
    
    /// Winamp EasyMove (on by default in 2.95): drag main / equalizer windows from anywhere, not just the title bar
    public var easyMoveStorage: Bool? = nil
    public var easyMove: Bool {
        get { easyMoveStorage ?? true }
        set { easyMoveStorage = newValue }
    }
    
    /// Crossfade between tracks in seconds, 0 = off (Optional for decode compatibility)
    public var crossfadeSecondsStorage: Double? = nil
    public var crossfadeSeconds: Double {
        get { crossfadeSecondsStorage ?? 0 }
        set { crossfadeSecondsStorage = newValue }
    }
    
    /// Bookmarks menu entries (Optional for decode compatibility)
    public var bookmarksStorage: [Bookmark]? = nil
    public var bookmarks: [Bookmark] {
        get { bookmarksStorage ?? [] }
        set { bookmarksStorage = newValue }
    }
    
    /// Save playlists with paths relative to the playlist file where possible (portable playlists)
    public var savePlaylistRelativePathsStorage: Bool? = nil
    public var savePlaylistRelativePaths: Bool {
        get { savePlaylistRelativePathsStorage ?? false }
        set { savePlaylistRelativePathsStorage = newValue }
    }
    
    /// Winamp "Manual playlist advance": don't start the next track when one ends (Optional for decode compatibility)
    public var manualPlaylistAdvanceStorage: Bool? = nil
    public var manualPlaylistAdvance: Bool {
        get { manualPlaylistAdvanceStorage ?? false }
        set { manualPlaylistAdvanceStorage = newValue }
    }
    /// Optional so session.json files written before this field existed still decode
    public var visualizerOptionsStorage: VisualizerOptions? = nil
    public var visualizerOptions: VisualizerOptions {
        get { visualizerOptionsStorage ?? VisualizerOptions() }
        set { visualizerOptionsStorage = newValue }
    }
    public var timeDisplayMode: TimeDisplayMode = .elapsed
    public var scaleFactor: ScaleFactor = .x1
    
    public var isMainWindowShade: Bool = false
    public var isEqWindowVisible: Bool = true
    public var isEqWindowShade: Bool = false
    public var isPlaylistVisible: Bool = true
    public var isBrowserVisibleStorage: Bool? = nil
    public var isBrowserVisible: Bool {
        get { isBrowserVisibleStorage ?? false }
        set { isBrowserVisibleStorage = newValue }
    }
    public var isLibraryVisibleStorage: Bool? = nil
    public var isLibraryVisible: Bool {
        get { isLibraryVisibleStorage ?? false }
        set { isLibraryVisibleStorage = newValue }
    }
    public var isPlaylistShade: Bool = false
    public var isAlwaysOnTop: Bool = false
    
    public var windowPositions: [String: [Double]] = [:]
    /// Winamp's default playlist: minimum height plus 4 resize steps of 29 px (275 × 232)
    public var playlistWindowSize: [Double] = [Double(AppConstants.Window.width), Double(AppConstants.Window.height) + 4 * 29]
    
    public var lastPlayedTrackURL: String? = nil
    public var lastPlayedTrackIndex: Int? = nil
    public var lastPlayedTrackTime: Double = 0.0
    public var lastPlaybackState: PlayerStatus = .stopped
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
    public var selectedAudioOutputDeviceUID: String? = nil
    
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
    
    /// Application Support/MacAmp (session, playlist, library)
    public var baseDir: URL {
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
    
    private var pendingSave: DispatchWorkItem?
    
    /// Coalesces frequent saves (status changes, seeks) into one disk write shortly afterwards.
    /// `saveSession()` (e.g. on quit) flushes immediately and cancels the pending write.
    public func scheduleSave(after delay: TimeInterval = 1.0) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.saveSession()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    public func saveSession() {
        pendingSave?.cancel()
        pendingSave = nil
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
