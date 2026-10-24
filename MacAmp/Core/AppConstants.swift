import Foundation
import CoreGraphics

/// Canonical constants and layout coordinates for the Winamp 2.95 reproduction.
/// Values come from the original winamp.exe 2.95 (docs/winamp295-extracted), its base skin and Webamp references.
public enum AppConstants {
    
    // MARK: - Version
    public enum App {
        /// MacAmp's own version (MARKETING_VERSION, major.minor), e.g. "1.0"
        public static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        /// The Winamp release MacAmp reproduces
        public static let basedOn = "Winamp 2.95"
        /// What Winamp 2.95's in_mp3 sends to SHOUTcast / Icecast servers
        public static let streamUserAgent = "WinampMPEG/2.9"
        /// MacAmp's page: updates (About), plug-ins (Get plug-ins, #plugins), Minibrowser start page
        public static let website = URL(string: "https://alexrel.com/macamp")!
        public static let pluginsPage = URL(string: "https://alexrel.com/macamp#plugins")!
    }
    
    // MARK: - Window Dimensions (1x Base Scale)
    public enum Window {
        /// Standard Winamp 2.x main window width in pixels
        public static let width: CGFloat = 275
        /// Standard Winamp 2.x main window height in pixels
        public static let height: CGFloat = 116
        /// Height of window titlebar / shade mode strip
        public static let shadeHeight: CGFloat = 14
        
        /// Playlist horizontal resizing increment grid (275 / 11)
        public static let resizeStepX: CGFloat = 25
        /// Playlist vertical resizing increment grid (116 / 4)
        public static let resizeStepY: CGFloat = 29
        
        /// Magnetic docking snap threshold in pixels
        public static let snapDistance: CGFloat = 10
    }
    
    // MARK: - Main Window Control Layout
    public enum MainWindow {
        /// Exact 1x pixel frames for all sub-components in normal mode
        public enum Layout {
            // TitleBar Buttons (y: 3, 9x9 px)
            public static let optionsButton = NSRect(x: 6, y: 3, width: 9, height: 9)
            public static let minimizeButton = NSRect(x: 244, y: 3, width: 9, height: 9)
            public static let shadeButton = NSRect(x: 254, y: 3, width: 9, height: 9)
            public static let closeButton = NSRect(x: 264, y: 3, width: 9, height: 9)
            
            // ClutterBar (O, A, I, D, V)
            public static let clutterBarBg = NSRect(x: 10, y: 22, width: 8, height: 43)
            public static let clutterOptionsButton = NSRect(x: 10, y: 25, width: 8, height: 8)
            public static let clutterAlwaysOnTopButton = NSRect(x: 10, y: 33, width: 8, height: 7)
            public static let clutterFileInfoButton = NSRect(x: 10, y: 40, width: 8, height: 7)
            public static let clutterDoubleSizeButton = NSRect(x: 10, y: 47, width: 8, height: 8)
            public static let clutterVisualizerButton = NSRect(x: 10, y: 55, width: 8, height: 7)
            
            // Displays and Indicators
            public static let workingIndicator = NSRect(x: 24, y: 28, width: 3, height: 9)
            public static let playbackIndicator = NSRect(x: 26, y: 28, width: 9, height: 9)
            public static let timeDisplay = NSRect(x: 39, y: 26, width: 59, height: 13)
            public static let visualizer = NSRect(x: 24, y: 43, width: 76, height: 16)
            public static let marquee = NSRect(x: 112, y: 27, width: 152, height: 6)
            /// TrueType title: the bitmap font's 6 px row is too low, so use the whole LCD box in MAIN.BMP (rows 24-35)
            public static let marqueeTrueType = NSRect(x: 112, y: 24, width: 152, height: 12)
            public static let bitrate = CGPoint(x: 111, y: 43)
            public static let sampleRate = CGPoint(x: 156, y: 43)
            public static let monoIndicator = NSRect(x: 212, y: 41, width: 27, height: 12)
            public static let stereoIndicator = NSRect(x: 239, y: 41, width: 29, height: 12)
            
            // Sliders
            public static let volumeSlider = NSRect(x: 107, y: 57, width: 68, height: 13)
            public static let volumeTrackWidth: CGFloat = 65.0
            public static let balanceSlider = NSRect(x: 177, y: 57, width: 38, height: 13)
            public static let seekSlider = NSRect(x: 16, y: 72, width: 248, height: 10)
            
            // Window Toggles (EQ, PL)
            public static let eqToggle = NSRect(x: 219, y: 58, width: 23, height: 12)
            public static let plToggle = NSRect(x: 242, y: 58, width: 23, height: 12)
            
            // Transport Controls (CBUTTONS.BMP)
            public static let prevButton = NSRect(x: 16, y: 88, width: 23, height: 18)
            public static let playButton = NSRect(x: 39, y: 88, width: 23, height: 18)
            public static let pauseButton = NSRect(x: 62, y: 88, width: 23, height: 18)
            public static let stopButton = NSRect(x: 85, y: 88, width: 23, height: 18)
            public static let nextButton = NSRect(x: 108, y: 88, width: 22, height: 18)
            public static let ejectButton = NSRect(x: 136, y: 89, width: 22, height: 16)
            
            // Shuffle & Repeat (SHUFREP.BMP)
            public static let shuffleToggle = NSRect(x: 164, y: 89, width: 47, height: 15)
            public static let repeatToggle = NSRect(x: 210, y: 89, width: 28, height: 15)
        }
        
        /// Exact 1x pixel frames for controls repositioned in shade mode
        public enum ShadeLayout {
            public static let visualizer = NSRect(x: 79, y: 5, width: 38, height: 5)
            public static let timeDisplay = NSRect(x: 127, y: 4, width: 30, height: 6)
            public static let seekSlider = NSRect(x: 226, y: 4, width: 17, height: 7)
            
            // Mini transport button click targets over pre-rendered TITLEBAR.BMP icons
            public static let prevButton = NSRect(x: 167, y: 2, width: 9, height: 10)
            public static let playButton = NSRect(x: 176, y: 2, width: 9, height: 10)
            public static let pauseButton = NSRect(x: 186, y: 2, width: 9, height: 10)
            public static let stopButton = NSRect(x: 196, y: 2, width: 9, height: 10)
            public static let nextButton = NSRect(x: 205, y: 2, width: 9, height: 10)
            public static let ejectButton = NSRect(x: 215, y: 2, width: 9, height: 10)
        }
    }
    
    // MARK: - Equalizer Window Control Layout
    public enum Equalizer {
        /// Standard 10 band center frequencies in Hz
        public static let bandFrequencies: [Int] = [
            60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000
        ]
        
        public static let minGainDb: Float = -12.0
        public static let maxGainDb: Float = 12.0
        public static let zeroGainDb: Float = 0.0
        
        /// Number of slider animation steps in EQMAIN.BMP (28 frames: 0..27)
        public static let sliderFrames: Int = 28
        
        /// Snap to 0 dB threshold
        public static let snapThresholdDb: Float = 0.6
        
        /// 1x layout coordinates for Equalizer window
        public enum Layout {
            public static let closeButton = NSRect(x: 264, y: 3, width: 9, height: 9)
            public static let shadeButton = NSRect(x: 254, y: 3, width: 9, height: 9)
            
            public static let onToggle = NSRect(x: 14, y: 18, width: 26, height: 12)
            public static let autoToggle = NSRect(x: 40, y: 18, width: 32, height: 12)
            public static let presetsButton = NSRect(x: 217, y: 18, width: 44, height: 12)
            
            public static let graphRect = NSRect(x: 86, y: 17, width: 113, height: 19)
            
            public static let preampSlider = NSRect(x: 21, y: 38, width: 14, height: 63)
            public static let bandWidth: CGFloat = 14
            public static let bandHeight: CGFloat = 63
            public static let bandY: CGFloat = 38
            public static let bandXPositions: [CGFloat] = [78, 96, 114, 132, 150, 168, 186, 204, 222, 240]
            
            // Shade mode sliders
            public static let shadeVolumeSlider = NSRect(x: 61, y: 4, width: 97, height: 7)
            public static let shadeBalanceSlider = NSRect(x: 164, y: 4, width: 42, height: 7)
        }
    }
    
    // MARK: - Playlist Window Layout
    public enum Playlist {
        public static let trackRowHeight: CGFloat = 13
        public static let minTracksVisible: Int = 4
        
        /// Authentic Winamp 2.x geometry parameters
        public enum Layout {
            public static let topBarHeight: CGFloat = 20
            public static let bottomBarHeight: CGFloat = 38
            public static let shadeHeight: CGFloat = 14
            
            public static let cornerPieceWidth: CGFloat = 25
            public static let titlePieceWidth: CGFloat = 100
            
            public static let leftBorderWidth: CGFloat = 12
            public static let rightBorderWidth: CGFloat = 20
            public static let sideBorderTileHeight: CGFloat = 29
            
            public static let bottomLeftWidth: CGFloat = 125
            public static let bottomRightWidth: CGFloat = 150
            public static let bottomTileWidth: CGFloat = 25
            
            public static let buttonYOffsetFromBottom: CGFloat = 8
            public static let buttonWidth: CGFloat = 22
            public static let buttonHeight: CGFloat = 18
            
            public static let addX: CGFloat = 14
            public static let remX: CGFloat = 43
            public static let selX: CGFloat = 72
            public static let miscX: CGFloat = 101
            public static let listXOffsetFromRight: CGFloat = 44
            
            public static let runningTimeOffsetFromRight: CGFloat = 143
            public static let runningTimeYOffsetFromBottom: CGFloat = 11
            
            public static let miniTimeOffsetFromRight: CGFloat = 84
            public static let miniTimeYOffsetFromBottom: CGFloat = 23
            
            // Mini transport action buttons in playlist bottom bar (botY + 22)
            public static let actionButtonsYOffsetFromBottom: CGFloat = 22
            public static let actionPrevXOffsetFromRight: CGFloat = 146
            public static let actionPlayXOffsetFromRight: CGFloat = 137
            public static let actionPauseXOffsetFromRight: CGFloat = 127
            public static let actionStopXOffsetFromRight: CGFloat = 117
            public static let actionNextXOffsetFromRight: CGFloat = 108
            public static let actionEjectXOffsetFromRight: CGFloat = 99
            public static let actionButtonWidth: CGFloat = 9
            public static let actionButtonHeight: CGFloat = 9
            
            // Scroll buttons in bottom-right corner next to LIST
            public static let scrollButtonOffsetFromRight: CGFloat = 15
            public static let scrollUpYOffsetFromBottom: CGFloat = 2
            public static let scrollDownYOffsetFromBottom: CGFloat = 8
            public static let scrollButtonWidth: CGFloat = 8
            public static let scrollButtonHeight: CGFloat = 5
            
            public static let scrollbarOffsetFromRight: CGFloat = 15
            public static let scrollbarThumbWidth: CGFloat = 8
            public static let scrollbarThumbHeight: CGFloat = 18
            
            public static let closeButtonOffsetFromRight: CGFloat = 11
            public static let shadeButtonOffsetFromRight: CGFloat = 20
            public static let topButtonY: CGFloat = 3
            public static let topButtonSize: CGFloat = 9
            
            public static let resizeGripSize: CGFloat = 20
        }
    }
    
    // MARK: - Time Display & Mini Time
    public enum TimeDisplay {
        public static let minusRect = NSRect(x: 0, y: 6, width: 5, height: 1)
        public static let digitWidth: CGFloat = 9
        public static let digitHeight: CGFloat = 13
        public static let minuteTensX: CGFloat = 9
        public static let minuteOnesX: CGFloat = 21
        public static let secondTensX: CGFloat = 39
        public static let secondOnesX: CGFloat = 51
        
        /// Relative X offsets for mini time display in shade / playlist
        public enum MiniOffsets {
            public static let minusX: CGFloat = 1
            public static let minuteTensX: CGFloat = 7
            public static let minuteOnesX: CGFloat = 12
            // Colon is baked into skin background between 17..19
            public static let secondTensX: CGFloat = 20
            public static let secondOnesX: CGFloat = 25
        }
    }
    
    // MARK: - Visualizer
    public enum Visualizer {
        public static let width: Int = 76
        public static let height: Int = 16
        
        public static let numSpectrumBars: Int = 19
        public static let barWidth: Int = 3
        public static let barSpacing: Int = 1
        
        public static let numWaveformPoints: Int = 76
        /// "Thin bands": one 1 px bar per visualizer column; 4 thin bands make one thick bar
        public static let numThinBands: Int = 76
        
        /// Falloff speeds
        public static let peakFalloffRate: Float = 0.35
        public static let barFalloffRate: Float = 0.5
    }
    
    // MARK: - Marquee / Font
    public enum Font {
        public static let charWidth: CGFloat = 5
        public static let charHeight: CGFloat = 6
    }
    
    public enum Marquee {
        public static let width: CGFloat = 152
        public static let height: CGFloat = 6
        public static let pauseDuration: TimeInterval = 2.5
        public static let scrollInterval: TimeInterval = 0.12
    }
    
    // MARK: - Audio Engine Constants & Supported Formats
    public enum Audio {
        public static let bufferSize: UInt32 = 1024
        public static let defaultVolume: Double = 0.75
        public static let defaultBalance: Double = 0.0 // -1.0 (Left) ... 0.0 (Center) ... +1.0 (Right)
        
        /// Everything MacAmp plays: its own formats plus those of installed plug-ins (in_ffmpeg: MKV, WMA, APE...)
        public static var supportedExtensions: Set<String> { builtInExtensions.union(PluginManager.extensions) }
        public static let builtInExtensions: Set<String> = [
            "mp3", "flac", "wav", "aiff", "aif", "m4a", "aac", "alac", "ogg", "oga", "opus",
            "mp2", "mp1", "au", "snd",          // in_mp3 / in_wave formats macOS decodes too
            "mid", "midi", "rmi", "kar",        // in_midi: rendered with the system General MIDI synth
            "mp4", "m4v", "mov"                 // video: sound through the engine, picture in the Video window
        ]
        public static let skinExtensions: Set<String> = ["wsz", "zip"]
        public static let playlistExtensions: Set<String> = ["m3u", "m3u8", "pls", "xspf", "cue"] // xspf: VLC's own format
    }
    
    // MARK: - macOS Keyboard Codes
    public enum KeyCodes {
        public static let leftArrow: UInt16 = 123
        public static let rightArrow: UInt16 = 124
        public static let downArrow: UInt16 = 125
        public static let upArrow: UInt16 = 126
        public static let space: UInt16 = 49
        public static let returnKey: UInt16 = 36
        public static let deleteKey: UInt16 = 51
        public static let f3: UInt16 = 99
        public static let escape: UInt16 = 53
        public static let enterKey: UInt16 = 76      // keypad Enter
        public static let forwardDelete: UInt16 = 117
        public static let home: UInt16 = 115
        public static let end: UInt16 = 119
        public static let pageUp: UInt16 = 116
        public static let pageDown: UInt16 = 121
        public static let digit3: UInt16 = 20
        public static let digit1: UInt16 = 18
        public static let digit2: UInt16 = 19
        public static let tab: UInt16 = 48
        public static let f1: UInt16 = 122
        public static let f4: UInt16 = 118
        /// Help on Apple keyboards, Insert on PC keyboards
        public static let insertHelp: UInt16 = 114
        // Numeric keypad
        public static let keypad0: UInt16 = 82
        public static let keypad1: UInt16 = 83
        public static let keypad2: UInt16 = 84
        public static let keypad3: UInt16 = 85
        public static let keypad4: UInt16 = 86
        public static let keypad5: UInt16 = 87
        public static let keypad6: UInt16 = 88
        public static let keypad7: UInt16 = 89
        public static let keypad8: UInt16 = 91
        public static let keypad9: UInt16 = 92
        public static let keypadDecimal: UInt16 = 65
    }
}
