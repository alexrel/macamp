import Foundation
import CoreGraphics

/// Canonical constants for Winamp 2.95 emulation.
/// All values are based on Winamp 2.95 source and Webamp specifications.
public enum AppConstants {
    
    // MARK: - Window Dimensions (1x Base Scale)
    public enum Window {
        public static let width: CGFloat = 275
        public static let height: CGFloat = 116
        public static let shadeHeight: CGFloat = 14
        
        // Playlist resizing grid increments
        public static let resizeStepX: CGFloat = 25
        public static let resizeStepY: CGFloat = 29
        
        // Magnetic docking snap threshold in pixels
        public static let snapDistance: CGFloat = 10
    }
    
    // MARK: - Equalizer
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
    }
    
    // MARK: - Visualizer
    public enum Visualizer {
        public static let width: Int = 76
        public static let height: Int = 16
        
        public static let numSpectrumBars: Int = 19
        public static let barWidth: Int = 3
        public static let barSpacing: Int = 1
        
        public static let numWaveformPoints: Int = 76
        
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
        public static let width: CGFloat = 154
        public static let height: CGFloat = 6
        public static let pauseDuration: TimeInterval = 2.5
        public static let scrollInterval: TimeInterval = 0.12
    }
    
    // MARK: - Playlist
    public enum Playlist {
        public static let trackRowHeight: CGFloat = 13
        public static let minTracksVisible: Int = 4
    }
    
    // MARK: - Audio Engine
    public enum Audio {
        public static let bufferSize: UInt32 = 1024
        public static let defaultVolume: Double = 0.75
        public static let defaultBalance: Double = 0.0 // -1.0 (Left) ... 0.0 (Center) ... +1.0 (Right)
    }
}
