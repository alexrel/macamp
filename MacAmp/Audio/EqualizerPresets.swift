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
    
    /// Converts dB (-12.0 ... +12.0) back to Winamp 0..63 integer representation (where 33 ≈ 0 dB)
    public static func toWinampValue(db: Float) -> Int {
        if db <= 0 {
            let ratio = (db + 12.0) / 12.0
            return max(0, min(33, Int(round(ratio * 33.0))))
        } else {
            let ratio = db / 12.0
            return max(33, min(63, 33 + Int(round(ratio * 30.0))))
        }
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
    
    // MARK: - Winamp .EQF File Format Support
    private static let eqfHeader = "Winamp EQ library file v1.1\u{1A}!--"
    
    public func loadEQF(from url: URL) -> [EQPreset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let headerData = EqualizerPresetsManager.eqfHeader.data(using: .ascii),
              data.starts(with: headerData) else {
            return []
        }
        
        var presets: [EQPreset] = []
        var offset = headerData.count
        let presetRecordLength = 257 + 11 // 257 bytes name + 10 bands + 1 preamp
        
        while offset + presetRecordLength <= data.count {
            let nameData = data.subdata(in: offset..<offset + 257)
            let nameString = (nameData.split(separator: 0).first.flatMap { String(bytes: $0, encoding: .isoLatin1) }) ?? "Preset"
            
            let bandBytes = data.subdata(in: offset + 257..<offset + 267)
            let preampByte = data[offset + 267]
            
            let bandValues = bandBytes.map { 64 - Int($0) }
            let preampValue = 64 - Int(preampByte)
            
            presets.append(EQPreset.fromWinampValues(name: nameString, preampInt: preampValue, bandsInt: bandValues))
            offset += presetRecordLength
        }
        
        return presets
    }
    
    public func createEQFData(presets: [EQPreset]) -> Data {
        var data = Data()
        if let hData = EqualizerPresetsManager.eqfHeader.data(using: .ascii) {
            data.append(hData)
        }
        
        for preset in presets {
            // 257 bytes null-padded name
            var nameBytes = Array(preset.name.prefix(256).utf8)
            nameBytes.append(contentsOf: Array(repeating: UInt8(0), count: 257 - nameBytes.count))
            data.append(contentsOf: nameBytes)
            
            // 10 bands (64 - val)
            for i in 0..<10 {
                let gainDb = (i < preset.bandsDb.count) ? preset.bandsDb[i] : 0.0
                let winampVal = EQPreset.toWinampValue(db: gainDb)
                data.append(UInt8(max(0, min(255, 64 - winampVal))))
            }
            
            // Preamp (64 - val)
            let preampWinampVal = EQPreset.toWinampValue(db: preset.preampDb)
            data.append(UInt8(max(0, min(255, 64 - preampWinampVal))))
        }
        
        return data
    }
    
    public func saveEQF(presets: [EQPreset], to url: URL) throws {
        let data = createEQFData(presets: presets)
        try data.write(to: url)
    }
}
