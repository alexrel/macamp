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
    case minibrowser
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
