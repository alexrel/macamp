import Foundation

public struct EQPreset: Codable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let preampDb: Float
    public let bandsDb: [Float] // 10 values in dB (-12.0 ... +12.0)
    
    public init(name: String, preampDb: Float, bandsDb: [Float]) {
        self.name = name
        self.preampDb = preampDb
        self.bandsDb = bandsDb
    }
    
    /// Converts Winamp 0..63 integer representation (where 33 ≈ 0 dB) to dB (-12.0 ... +12.0)
    public static func fromWinampValues(name: String, preampInt: Int, bandsInt: [Int]) -> EQPreset {
        let convert: (Int) -> Float = { val in
            // 0 = -12 dB, 33 = 0 dB, 63 = +12 dB
            if val <= 33 {
                return Float(val - 33) / 33.0 * 12.0
            } else {
                return Float(val - 33) / 30.0 * 12.0
            }
        }
        return EQPreset(
            name: name,
            preampDb: convert(preampInt),
            bandsDb: bandsInt.map(convert)
        )
    }
}

public class EqualizerPresetsManager {
    public static let shared = EqualizerPresetsManager()
    
    /// The 17 authentic built-in Winamp 2.95 presets
    public let builtInPresets: [EQPreset] = [
        .fromWinampValues(name: "Classical", preampInt: 33, bandsInt: [33, 33, 33, 33, 33, 33, 20, 20, 20, 16]),
        .fromWinampValues(name: "Club", preampInt: 33, bandsInt: [33, 33, 38, 42, 42, 42, 38, 33, 33, 33]),
        .fromWinampValues(name: "Dance", preampInt: 33, bandsInt: [48, 44, 36, 32, 32, 22, 20, 20, 32, 32]),
        .fromWinampValues(name: "Full Bass", preampInt: 33, bandsInt: [48, 48, 48, 42, 35, 25, 18, 15, 14, 14]),
        .fromWinampValues(name: "Full Bass & Treble", preampInt: 33, bandsInt: [44, 42, 33, 20, 24, 35, 46, 50, 52, 52]),
        .fromWinampValues(name: "Full Treble", preampInt: 33, bandsInt: [16, 16, 16, 25, 37, 50, 58, 58, 58, 60]),
        .fromWinampValues(name: "Laptop speakers/headphones", preampInt: 33, bandsInt: [40, 50, 41, 26, 28, 35, 40, 48, 53, 56]),
        .fromWinampValues(name: "Large hall", preampInt: 33, bandsInt: [49, 49, 42, 42, 33, 24, 24, 24, 33, 33]),
        .fromWinampValues(name: "Live", preampInt: 33, bandsInt: [24, 33, 39, 41, 42, 42, 39, 37, 37, 36]),
        .fromWinampValues(name: "Party", preampInt: 33, bandsInt: [44, 44, 33, 33, 33, 33, 33, 33, 44, 44]),
        .fromWinampValues(name: "Pop", preampInt: 33, bandsInt: [29, 40, 44, 45, 41, 30, 28, 28, 29, 29]),
        .fromWinampValues(name: "Reggae", preampInt: 33, bandsInt: [33, 33, 31, 22, 33, 43, 43, 33, 33, 33]),
        .fromWinampValues(name: "Rock", preampInt: 33, bandsInt: [45, 40, 23, 19, 26, 39, 47, 50, 50, 50]),
        .fromWinampValues(name: "Ska", preampInt: 33, bandsInt: [28, 24, 25, 31, 39, 42, 47, 48, 50, 48]),
        .fromWinampValues(name: "Soft", preampInt: 33, bandsInt: [40, 35, 30, 28, 30, 39, 46, 48, 50, 52]),
        .fromWinampValues(name: "Soft Rock", preampInt: 33, bandsInt: [39, 39, 36, 31, 25, 23, 26, 31, 37, 47]),
        .fromWinampValues(name: "Techno", preampInt: 33, bandsInt: [45, 42, 33, 23, 24, 33, 45, 48, 48, 47])
    ]
    
    public private(set) var userPresets: [EQPreset] = []
    
    private init() {
        loadUserPresets()
    }
    
    private var presetsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("MacAmp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("eq_presets.json")
    }
    
    private func loadUserPresets() {
        guard let data = try? Data(contentsOf: presetsFileURL),
              let decoded = try? JSONDecoder().decode([EQPreset].self, from: data) else {
            return
        }
        self.userPresets = decoded
    }
    
    public func saveUserPreset(_ preset: EQPreset) {
        userPresets.removeAll(where: { $0.name == preset.name })
        userPresets.append(preset)
        if let data = try? JSONEncoder().encode(userPresets) {
            try? data.write(to: presetsFileURL)
        }
    }
    
    public func deleteUserPreset(name: String) {
        userPresets.removeAll(where: { $0.name == name })
        if let data = try? JSONEncoder().encode(userPresets) {
            try? data.write(to: presetsFileURL)
        }
    }
    
    public static let flatPreset = EQPreset(name: "Flat", preampDb: 0.0, bandsDb: Array(repeating: 0.0, count: 10))
}
