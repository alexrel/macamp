import Foundation

public enum PlayerStatus: String, Codable {
    case stopped
    case playing
    case paused
}

public enum VisualizerMode: Int, Codable, CaseIterable {
    case spectrum = 0
    case oscilloscope = 1
    case off = 2
    
    public var next: VisualizerMode {
        VisualizerMode(rawValue: (self.rawValue + 1) % VisualizerMode.allCases.count) ?? .spectrum
    }
}

public enum TimeDisplayMode: String, Codable {
    case elapsed
    case remaining
}

public enum AudioChannelMode: String, Codable {
    case stereo
    case mono
}

public enum WindowID: String, Codable, CaseIterable {
    case main
    case equalizer
    case playlist
    case library
    case video
    case browser
    
    /// Freely resizable windows that stay at 1x in Double Size mode (Winamp's playlist and general-purpose windows)
    public var keepsOwnSize: Bool { self != .main && self != .equalizer }
}

public enum ScaleFactor: Int, Codable {
    case x1 = 1
    case x2 = 2
    
    public var scale: CGFloat {
        CGFloat(rawValue)
    }
    
    public var toggle: ScaleFactor {
        self == .x1 ? .x2 : .x1
    }
}

// MARK: - Visualizer Options (Winamp 2.x "Visualization" menu)

public enum AnalyzerStyle: String, Codable, CaseIterable {
    case normal, fire, line
    public var title: String {
        switch self {
        case .normal: return "Normal style"
        case .fire: return "Fire style"
        case .line: return "Line style"
        }
    }
}

public enum AnalyzerBands: String, Codable, CaseIterable {
    case thick, thin
    public var title: String { self == .thick ? "Thick bands" : "Thin bands" }
    /// Bars across the 76 px visualizer
    public var count: Int { self == .thick ? AppConstants.Visualizer.numSpectrumBars : AppConstants.Visualizer.numThinBands }
}

public enum ScopeStyle: String, Codable, CaseIterable {
    case dot, line, solid
    public var title: String {
        switch self {
        case .dot: return "Dot scope"
        case .line: return "Line scope"
        case .solid: return "Solid scope"
        }
    }
}

public enum VisualizerFalloff: Int, Codable, CaseIterable {
    case slowest = 0, slow, moderate, fast, fastest
    public var title: String {
        switch self {
        case .slowest: return "Slowest"
        case .slow: return "Slow"
        case .moderate: return "Moderate"
        case .fast: return "Fast"
        case .fastest: return "Fastest"
        }
    }
    /// Height (0...1) a bar loses per frame (~43 fps)
    public var barStep: Float { [0.008, 0.016, 0.03, 0.05, 0.08][rawValue] }
    /// Height (0...1) a peak marker loses per frame
    public var peakStep: Float { [0.003, 0.006, 0.012, 0.02, 0.035][rawValue] }
}

public struct VisualizerOptions: Codable, Equatable {
    public var analyzerStyle: AnalyzerStyle = .normal
    public var bands: AnalyzerBands = .thick
    public var scopeStyle: ScopeStyle = .dot
    public var barFalloff: VisualizerFalloff = .moderate
    public var peakFalloff: VisualizerFalloff = .moderate
    public init() {}
}
