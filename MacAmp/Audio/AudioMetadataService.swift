import Foundation
import CoreGraphics
import AppKit
import AVFoundation
import AudioToolbox

// MARK: - Standard ID3 Genres
public struct ID3Genre {
    public static let allGenres: [String] = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop",
        "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B", "Rap",
        "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska", "Death Metal", "Pranks",
        "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk", "Fusion", "Trance",
        "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
        "AlternRock", "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock",
        "Ethnic", "Gothic", "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream",
        "Southern Rock", "Comedy", "Cult", "Gangsta", "Top 40", "Christian Rap", "Pop/Funk", "Jungle",
        "Native American", "Cabaret", "New Wave", "Psychadelic", "Rave", "Showtunes", "Trailer", "Lo-Fi",
        "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock",
        "Folk", "Folk-Rock", "National Folk", "Swing", "Fast Fusion", "Bebob", "Latin", "Revival",
        "Celtic", "Bluegrass", "Avantgarde", "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock",
        "Big Band", "Chorus", "Easy Listening", "Acoustic", "Humour", "Speech", "Chanson", "Opera",
        "Chamber Music", "Sonata", "Symphony", "Booty Bass", "Primus", "Porn Groove", "Satire", "Slow Jam",
        "Club", "Tango", "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythm Blues", "Soft Rock",
        "Indie", "Club-House", "Hardcore", "Terror", "Indie Rock", "BritPop", "Afro-Punk", "Polsk Punk",
        "Beat", "Christian Gangsta Rap", "Heavy Metal", "Black Metal", "Crossover", "Contemporary Christian", "Christian Rock", "Merengue",
        "Salsa", "Thrash Metal", "Anime", "JPop", "Synthpop", "Abstract", "Art Rock", "Baroque",
        "Bhangra", "Big Beat", "Breakbeat", "Chillout", "Downtempo", "Dub", "EBM", "Eclectic",
        "Electro", "Electroclash", "Emo", "Experimental", "Garage", "Global", "IDM", "Illbient",
        "Industro-Goth", "Jam Band", "Krautrock", "Leftfield", "Lounge", "Math Rock", "New Romantic", "Nu-Breakz",
        "Post-Punk", "Post-Rock", "Psytrance", "Shoegaze", "Space Rock", "Trop Rock", "World Music", "Neoclassical"
    ]
    
    public static func name(for index: UInt8) -> String {
        let idx = Int(index)
        if idx >= 0 && idx < allGenres.count {
            return allGenres[idx]
        }
        return "Unknown"
    }
    
    public static func index(for name: String) -> UInt8 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (i, genre) in allGenres.enumerated() {
            if genre.lowercased() == trimmed {
                return UInt8(i)
            }
        }
        return 255 // 255 = None / Unknown in ID3v1
    }
}

// MARK: - Audio Technical Stream Info
public struct AudioTechnicalInfo: Equatable {
    public var fileSize: Int64 = 0
    public var headerOffset: Int64 = 0
    public var duration: TimeInterval = 0
    public var formatDescription: String = "MPEG 1.0 layer 3"
    public var bitrate: Int = 0 // in kbps (e.g. 320)
    public var isVBR: Bool = false
    public var sampleRate: Double = 44100.0
    public var channels: Int = 2
    public var channelMode: String = "Joint Stereo"
    public var hasCRC: Bool = false
    public var isCopyrighted: Bool = false
    public var isOriginal: Bool = true
    public var emphasis: String = "None"
    
    public init() {}
    
    public var formattedDuration: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
    
    public var formattedFileSize: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let numStr = formatter.string(from: NSNumber(value: fileSize)) ?? "\(fileSize)"
        let mb = Double(fileSize) / (1024.0 * 1024.0)
        return String(format: "%@ bytes (%.2f MB)", numStr, mb)
    }
}

// MARK: - ID3v1 Tag
public struct ID3v1Tag: Equatable {
    public var hasTag: Bool = false
    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var year: String = ""
    public var comment: String = ""
    public var trackNumber: UInt8 = 0
    public var genreIndex: UInt8 = 255
    
    public init() {}
}

// MARK: - ID3v2 Tag
public struct ID3v2Tag: Equatable {
    public var hasTag: Bool = false
    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var year: String = ""
    public var trackNumber: String = "" // "5" or "5/12"
    public var discNumber: String = ""  // "1" or "1/1"
    public var genre: String = ""
    public var composer: String = ""
    public var originalArtist: String = ""
    public var copyright: String = ""
    public var url: String = ""
    public var encodedBy: String = ""
    public var comment: String = ""
    
    public init() {}
}

// MARK: - Embedded Artwork
public struct ArtworkInfo: Equatable {
    public var imageData: Data
    public var mimeType: String
    public var description: String
    
    public init(imageData: Data, mimeType: String = "image/jpeg", description: String = "Cover (front)") {
        self.imageData = imageData
        self.mimeType = mimeType
        self.description = description
    }
    
    public var image: NSImage? {
        return NSImage(data: imageData)
    }
}

// MARK: - Complete Track Metadata
public struct AudioFileMetadata: Equatable {
    public var url: URL
    public var techInfo: AudioTechnicalInfo
    public var id3v1: ID3v1Tag
    public var id3v2: ID3v2Tag
    public var artwork: ArtworkInfo?
    public var isReadOnly: Bool = false
    
    public init(url: URL) {
        self.url = url
        self.techInfo = AudioTechnicalInfo()
        self.id3v1 = ID3v1Tag()
        self.id3v2 = ID3v2Tag()
    }
    
    /// Copies relevant fields from ID3v2 to ID3v1 (truncating to ID3v1 character limits)
    public mutating func copyToID3v1() {
        id3v1.hasTag = true
        id3v1.title = String(id3v2.title.prefix(30))
        id3v1.artist = String(id3v2.artist.prefix(30))
        id3v1.album = String(id3v2.album.prefix(30))
        id3v1.year = String(id3v2.year.prefix(4))
        id3v1.comment = String(id3v2.comment.prefix(28))
        
        let trackStr = id3v2.trackNumber.components(separatedBy: "/").first ?? id3v2.trackNumber
        if let t = UInt8(trackStr.trimmingCharacters(in: .whitespaces)) {
            id3v1.trackNumber = t
        }
        
        id3v1.genreIndex = ID3Genre.index(for: id3v2.genre)
    }
    
    /// Copies fields from ID3v1 into ID3v2
    public mutating func copyFromID3v1() {
        id3v2.hasTag = true
        if !id3v1.title.isEmpty { id3v2.title = id3v1.title }
        if !id3v1.artist.isEmpty { id3v2.artist = id3v1.artist }
        if !id3v1.album.isEmpty { id3v2.album = id3v1.album }
        if !id3v1.year.isEmpty { id3v2.year = id3v1.year }
        if id3v1.trackNumber > 0 { id3v2.trackNumber = "\(id3v1.trackNumber)" }
        if !id3v1.comment.isEmpty { id3v2.comment = id3v1.comment }
        if id3v1.genreIndex < ID3Genre.allGenres.count {
            id3v2.genre = ID3Genre.name(for: id3v1.genreIndex)
        }
    }
}

// MARK: - Audio Metadata Service
public class AudioMetadataService {
    public static let shared = AudioMetadataService()
    
    private init() {}
    
    // MARK: - Public Read API
    
    /// Fully reads audio stream specifications, ID3v1, ID3v2, and embedded cover art for a track URL.
    public func readMetadata(from url: URL) -> AudioFileMetadata {
        var metadata = AudioFileMetadata(url: url)
        
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // 1. Check file size & permissions
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            metadata.techInfo.fileSize = (attrs[.size] as? Int64) ?? 0
            if let posix = attrs[.posixPermissions] as? NSNumber {
                let perms = posix.intValue
                if (perms & 0o200) == 0 { // no write permission
                    metadata.isReadOnly = true
                }
            }
        }
        
        // 2. Read technical stream properties (AudioToolbox / CoreAudio)
        readTechnicalAudioInfo(from: url, into: &metadata.techInfo)
        
        // 3. Read ID3v1 tag from last 128 bytes of file (for MP3)
        readID3v1(from: url, into: &metadata.id3v1)
        
        // 4. Read ID3v2 & AVMetadata (TIT2, TPE1, APIC/Cover, etc.)
        readAVAndID3v2Metadata(from: url, into: &metadata.id3v2, artwork: &metadata.artwork)
        
        // 5. If ID3v1 is empty but ID3v2 exists, populate ID3v1 draft values so user can easily toggle on
        if !metadata.id3v1.hasTag && metadata.id3v2.hasTag {
            metadata.id3v1.title = String(metadata.id3v2.title.prefix(30))
            metadata.id3v1.artist = String(metadata.id3v2.artist.prefix(30))
            metadata.id3v1.album = String(metadata.id3v2.album.prefix(30))
            metadata.id3v1.year = String(metadata.id3v2.year.prefix(4))
            metadata.id3v1.comment = String(metadata.id3v2.comment.prefix(28))
            let tStr = metadata.id3v2.trackNumber.components(separatedBy: "/").first ?? ""
            if let t = UInt8(tStr) { metadata.id3v1.trackNumber = t }
            metadata.id3v1.genreIndex = ID3Genre.index(for: metadata.id3v2.genre)
        }
        
        // 6. If ID3v2 is empty but ID3v1 exists, populate ID3v2
        if !metadata.id3v2.hasTag && metadata.id3v1.hasTag {
            metadata.id3v2.title = metadata.id3v1.title
            metadata.id3v2.artist = metadata.id3v1.artist
            metadata.id3v2.album = metadata.id3v1.album
            metadata.id3v2.year = metadata.id3v1.year
            metadata.id3v2.comment = metadata.id3v1.comment
            if metadata.id3v1.trackNumber > 0 { metadata.id3v2.trackNumber = "\(metadata.id3v1.trackNumber)" }
            if metadata.id3v1.genreIndex < ID3Genre.allGenres.count {
                metadata.id3v2.genre = ID3Genre.name(for: metadata.id3v1.genreIndex)
            }
        }
        
        // 7. Fallback title if both tags are absent
        if metadata.id3v2.title.isEmpty && metadata.id3v1.title.isEmpty {
            metadata.id3v2.title = url.deletingPathExtension().lastPathComponent
        }
        
        return metadata
    }
    
    // MARK: - Public Write API
    
    /// Writes updated metadata (ID3v1 and ID3v2.3) in-place to the target audio file.
    public func writeMetadata(_ metadata: AudioFileMetadata, to url: URL) throws {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            throw NSError(domain: "MacAmp.AudioMetadataService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "File is read-only or permission denied: \(url.lastPathComponent)"
            ])
        }
        
        let ext = url.pathExtension.lowercased()
        if ext == "mp3" {
            try writeMP3Tags(metadata, to: url)
        } else {
            // For non-MP3 files (M4A/AAC, FLAC), we update ID3v1/ID3v2 tags via temporary copy or standard tags
            try writeNonMP3Metadata(metadata, to: url)
        }
    }
    
    // MARK: - Internal Technical Stream Extraction
    
    private func readTechnicalAudioInfo(from url: URL, into tech: inout AudioTechnicalInfo) {
        var fileID: AudioFileID?
        let openStatus = AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID)
        if openStatus == noErr, let fileID = fileID {
            defer { AudioFileClose(fileID) }
            
            // Format & Stream description
            var asbd = AudioStreamBasicDescription()
            var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioFileGetProperty(fileID, kAudioFilePropertyDataFormat, &asbdSize, &asbd) == noErr {
                tech.sampleRate = asbd.mSampleRate
                tech.channels = Int(asbd.mChannelsPerFrame)
                tech.channelMode = (tech.channels == 1) ? "Mono" : ((tech.channels == 2) ? "Joint Stereo" : "\(tech.channels) Channels")
                
                switch asbd.mFormatID {
                case kAudioFormatMPEGLayer3:
                    tech.formatDescription = "MPEG 1.0 layer 3"
                case kAudioFormatMPEG4AAC:
                    tech.formatDescription = "MPEG-4 AAC"
                case kAudioFormatAppleLossless:
                    tech.formatDescription = "Apple Lossless (ALAC)"
                case kAudioFormatFLAC:
                    tech.formatDescription = "FLAC Lossless"
                case kAudioFormatLinearPCM:
                    tech.formatDescription = "Linear PCM"
                default:
                    tech.formatDescription = "Audio Stream (\(asbd.mFormatID))"
                }
            }
            
            // Bitrate
            var bitRate: UInt32 = 0
            var bitRateSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioFileGetProperty(fileID, kAudioFilePropertyBitRate, &bitRateSize, &bitRate) == noErr && bitRate > 0 {
                tech.bitrate = Int(bitRate / 1000)
            }
            
            // Estimated duration
            var estDur: Float64 = 0
            var estDurSize = UInt32(MemoryLayout<Float64>.size)
            if AudioFileGetProperty(fileID, kAudioFilePropertyEstimatedDuration, &estDurSize, &estDur) == noErr {
                tech.duration = TimeInterval(estDur)
            }
            
            // Data offset (audio stream header found at)
            var dataOffset: Int64 = 0
            var dataOffsetSize = UInt32(MemoryLayout<Int64>.size)
            if AudioFileGetProperty(fileID, kAudioFilePropertyDataOffset, &dataOffsetSize, &dataOffset) == noErr {
                tech.headerOffset = dataOffset
            }
        }
        
        // Fallback duration and bitrate via AVURLAsset if AudioToolbox yielded 0
        if tech.duration <= 0 || tech.bitrate <= 0 {
            let asset = AVURLAsset(url: url)
            let dur = CMTimeGetSeconds(asset.duration)
            if dur.isFinite && dur > 0 {
                tech.duration = dur
                if tech.bitrate <= 0 && tech.fileSize > 0 {
                    tech.bitrate = Int(Double(tech.fileSize * 8) / (dur * 1000.0))
                }
            }
        }
        
        // Scan first MP3 audio frame header to extract detailed MPEG flags
        if url.pathExtension.lowercased() == "mp3" {
            scanMPEGFrameHeader(from: url, into: &tech)
        }
    }
    
    /// Parses the 4-byte MPEG frame header at the audio stream data offset
    private func scanMPEGFrameHeader(from url: URL, into tech: inout AudioTechnicalInfo) {
        guard let file = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? file.close() }
        
        // Seek to audio stream offset
        let startOffset = max(0, tech.headerOffset)
        try? file.seek(toOffset: UInt64(startOffset))
        
        // Read up to 4096 bytes to find the sync word 0xFF 0xFB/0xFA/0xF3/0xF2
        guard let chunk = try? file.read(upToCount: 4096), chunk.count >= 4 else { return }
        
        for i in 0..<(chunk.count - 3) {
            let b0 = chunk[i]
            let b1 = chunk[i + 1]
            let b2 = chunk[i + 2]
            let b3 = chunk[i + 3]
            
            // Sync word: 11 bits set (0xFF, and high 3 bits of b1 are 0xE0)
            if b0 == 0xFF && (b1 & 0xE0) == 0xE0 {
                let mpegVersion = (b1 >> 3) & 0x03
                let layer = (b1 >> 1) & 0x03
                let hasCRC = (b1 & 0x01) == 0 // 0 means CRC protected!
                
                tech.hasCRC = hasCRC
                tech.headerOffset = startOffset + Int64(i)
                
                // MPEG Version string
                let verStr = (mpegVersion == 3) ? "1.0" : ((mpegVersion == 2) ? "2.0" : "2.5")
                let layerStr = (layer == 1) ? "layer 3" : ((layer == 2) ? "layer 2" : "layer 1")
                tech.formatDescription = "MPEG \(verStr) \(layerStr)"
                
                // Bitrate lookup table (MPEG 1.0 Layer 3)
                if mpegVersion == 3 && layer == 1 {
                    let bitrateIdx = Int((b2 >> 4) & 0x0F)
                    let bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
                    if bitrateIdx < bitrates.count && bitrates[bitrateIdx] > 0 {
                        tech.bitrate = bitrates[bitrateIdx]
                    }
                }
                
                // Channel mode
                let mode = (b3 >> 6) & 0x03
                switch mode {
                case 0: tech.channelMode = "Stereo"
                case 1: tech.channelMode = "Joint Stereo"
                case 2: tech.channelMode = "Dual Channel"
                case 3: tech.channelMode = "Mono"; tech.channels = 1
                default: break
                }
                
                tech.isCopyrighted = ((b3 >> 3) & 0x01) == 1
                tech.isOriginal = ((b3 >> 2) & 0x01) == 1
                
                let emphasis = b3 & 0x03
                switch emphasis {
                case 0: tech.emphasis = "None"
                case 1: tech.emphasis = "50/15 ms"
                case 3: tech.emphasis = "CCIT J.17"
                default: tech.emphasis = "Reserved"
                }
                
                break
            }
        }
    }
    
    // MARK: - ID3v1 Parser
    
    private func readID3v1(from url: URL, into tag: inout ID3v1Tag) {
        guard let file = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? file.close() }
        
        let fileSize = (try? file.seekToEnd()) ?? 0
        guard fileSize >= 128 else { return }
        
        try? file.seek(toOffset: fileSize - 128)
        guard let data = try? file.read(upToCount: 128), data.count == 128 else { return }
        
        // Header must be "TAG"
        guard data[0] == 0x54, data[1] == 0x41, data[2] == 0x47 else { return }
        
        tag.hasTag = true
        tag.title = decodeID3String(data[3..<33])
        tag.artist = decodeID3String(data[33..<63])
        tag.album = decodeID3String(data[63..<93])
        tag.year = decodeID3String(data[93..<97])
        
        // Check for ID3v1.1 track number at offset 125/126
        if data[125] == 0x00 && data[126] != 0x00 {
            tag.comment = decodeID3String(data[97..<125])
            tag.trackNumber = data[126]
        } else {
            tag.comment = decodeID3String(data[97..<127])
            tag.trackNumber = 0
        }
        
        tag.genreIndex = data[127]
    }
    
    private func decodeID3String(_ slice: Data) -> String {
        let bytes = Data(slice)
        // Strip trailing nulls and spaces
        var end = bytes.count
        while end > 0 && (bytes[end - 1] == 0 || bytes[end - 1] == 32) {
            end -= 1
        }
        guard end > 0 else { return "" }
        let sub = bytes[0..<end]
        
        // Try UTF-8 first
        if let str = String(data: sub, encoding: .utf8), !str.isEmpty {
            return str
        }
        // Fallback to Windows Cyrillic (Windows-1251)
        let cfEnc = CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        if let str = String(data: sub, encoding: String.Encoding(rawValue: nsEnc)), !str.isEmpty {
            return str
        }
        // Fallback to ISO Latin-1
        return String(data: sub, encoding: .isoLatin1) ?? ""
    }
    
    // MARK: - AVFoundation & ID3v2 Reader
    
    private func readAVAndID3v2Metadata(from url: URL, into id3v2: inout ID3v2Tag, artwork: inout ArtworkInfo?) {
        let asset = AVURLAsset(url: url)
        
        // Inspect all metadata items
        for item in asset.metadata {
            guard let keyStr = (item.key as? String) ?? item.commonKey?.rawValue ?? item.identifier?.rawValue else {
                continue
            }
            
            // Title (TIT2, ©nam)
            if keyStr == "TIT2" || keyStr.contains("TIT2") || keyStr.hasSuffix("©nam") || item.commonKey == .commonKeyTitle {
                if let val = item.stringValue, !val.isEmpty, id3v2.title.isEmpty {
                    id3v2.title = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // Artist (TPE1, ©ART)
            else if keyStr == "TPE1" || keyStr.contains("TPE1") || keyStr.hasSuffix("©ART") || item.commonKey == .commonKeyArtist {
                if let val = item.stringValue, !val.isEmpty, id3v2.artist.isEmpty {
                    id3v2.artist = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // Album (TALB, ©alb)
            else if keyStr == "TALB" || keyStr.contains("TALB") || keyStr.hasSuffix("©alb") || item.commonKey == .commonKeyAlbumName {
                if let val = item.stringValue, !val.isEmpty, id3v2.album.isEmpty {
                    id3v2.album = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // Year (TYER, TDRC, ©day)
            else if keyStr == "TYER" || keyStr == "TDRC" || keyStr.contains("TYER") || keyStr.contains("TDRC") || keyStr.hasSuffix("©day") {
                if let val = item.stringValue, !val.isEmpty, id3v2.year.isEmpty {
                    id3v2.year = String(val.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4))
                    id3v2.hasTag = true
                }
            }
            // Track Number (TRCK, trkn)
            else if keyStr == "TRCK" || keyStr.contains("TRCK") || keyStr.hasSuffix("trkn") {
                if let val = item.stringValue, !val.isEmpty, id3v2.trackNumber.isEmpty {
                    id3v2.trackNumber = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                } else if let num = item.numberValue, id3v2.trackNumber.isEmpty {
                    id3v2.trackNumber = "\(num)"
                    id3v2.hasTag = true
                }
            }
            // Disc Number (TPOS, disk)
            else if keyStr == "TPOS" || keyStr.contains("TPOS") || keyStr.hasSuffix("disk") {
                if let val = item.stringValue, !val.isEmpty, id3v2.discNumber.isEmpty {
                    id3v2.discNumber = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // Genre (TCON, ©gen, gnre)
            else if keyStr == "TCON" || keyStr.contains("TCON") || keyStr.hasSuffix("©gen") || keyStr.hasSuffix("gnre") {
                if let val = item.stringValue, !val.isEmpty, id3v2.genre.isEmpty {
                    // Normalize standard ID3 genre (e.g. "(17)" -> "Rock")
                    var g = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    if g.hasPrefix("(") && g.hasSuffix(")") {
                        let inner = String(g.dropFirst().dropLast())
                        if let idx = UInt8(inner) {
                            g = ID3Genre.name(for: idx)
                        }
                    }
                    id3v2.genre = g
                    id3v2.hasTag = true
                }
            }
            // Composer (TCOM, ©wrt)
            else if keyStr == "TCOM" || keyStr.contains("TCOM") || keyStr.hasSuffix("©wrt") {
                if let val = item.stringValue, !val.isEmpty, id3v2.composer.isEmpty {
                    id3v2.composer = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // Original Artist (TOPE)
            else if keyStr == "TOPE" || keyStr.contains("TOPE") {
                if let val = item.stringValue, !val.isEmpty, id3v2.originalArtist.isEmpty {
                    id3v2.originalArtist = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // Copyright (TCOP, cprt)
            else if keyStr == "TCOP" || keyStr.contains("TCOP") || keyStr.hasSuffix("cprt") {
                if let val = item.stringValue, !val.isEmpty, id3v2.copyright.isEmpty {
                    id3v2.copyright = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // URL (WXXX, WOAR, WCOP)
            else if keyStr.hasPrefix("W") || keyStr.contains("WXXX") {
                if let val = item.stringValue, !val.isEmpty, id3v2.url.isEmpty {
                    id3v2.url = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // Encoded By (TENC, ©too)
            else if keyStr == "TENC" || keyStr.contains("TENC") || keyStr.hasSuffix("©too") {
                if let val = item.stringValue, !val.isEmpty, id3v2.encodedBy.isEmpty {
                    id3v2.encodedBy = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // Comment (COMM, ©cmt)
            else if keyStr == "COMM" || keyStr.contains("COMM") || keyStr.hasSuffix("©cmt") {
                if let val = item.stringValue, !val.isEmpty, id3v2.comment.isEmpty {
                    id3v2.comment = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    id3v2.hasTag = true
                }
            }
            // Artwork / Cover Art (APIC, covr, artwork)
            else if keyStr == "APIC" || keyStr.contains("APIC") || keyStr.hasSuffix("covr") || item.commonKey == .commonKeyArtwork {
                if artwork == nil, let data = item.dataValue {
                    let mime = (data.prefix(3) == Data([0xFF, 0xD8, 0xFF])) ? "image/jpeg" : "image/png"
                    artwork = ArtworkInfo(imageData: data, mimeType: mime)
                    id3v2.hasTag = true
                }
            }
        }
    }
    
    // MARK: - MP3 In-Place Tag Writing
    
    private func writeMP3Tags(_ metadata: AudioFileMetadata, to url: URL) throws {
        let fileData = try Data(contentsOf: url, options: .alwaysMapped)
        guard fileData.count >= 128 else {
            throw NSError(domain: "MacAmp.AudioMetadataService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "File is too small to contain audio frames."
            ])
        }
        
        // 1. Identify and strip existing ID3v2 tag at the start of file
        var audioStartOffset = 0
        if fileData.count >= 10 && fileData[0] == 0x49 && fileData[1] == 0x44 && fileData[2] == 0x33 { // "ID3"
            let size = decodeSynchsafe(fileData[6..<10])
            audioStartOffset = 10 + Int(size)
        }
        
        // 2. Identify and strip existing ID3v1 tag at the end of file (128 bytes)
        var audioEndOffset = fileData.count
        if fileData.count >= 128 {
            let last128 = fileData[(fileData.count - 128)...]
            if last128[last128.startIndex] == 0x54 && last128[last128.startIndex + 1] == 0x41 && last128[last128.startIndex + 2] == 0x47 { // "TAG"
                audioEndOffset = fileData.count - 128
            }
        }
        
        if audioStartOffset > audioEndOffset {
            audioStartOffset = 0
            audioEndOffset = fileData.count
        }
        
        let audioPayload = fileData[audioStartOffset..<audioEndOffset]
        
        // 3. Build new ID3v2.3 tag
        var newID3v2Data = Data()
        if metadata.id3v2.hasTag {
            newID3v2Data = buildID3v2Tag(metadata.id3v2, artwork: metadata.artwork)
        }
        
        // 4. Build new ID3v1 tag
        var newID3v1Data = Data()
        if metadata.id3v1.hasTag {
            newID3v1Data = buildID3v1Tag(metadata.id3v1)
        }
        
        // 5. Combine: [ID3v2] + [Audio Frames] + [ID3v1]
        var combined = Data()
        combined.reserveCapacity(newID3v2Data.count + audioPayload.count + newID3v1Data.count)
        combined.append(newID3v2Data)
        combined.append(audioPayload)
        combined.append(newID3v1Data)
        
        // 6. Write atomically to disk
        try combined.write(to: url, options: .atomic)
    }
    
    // MARK: - ID3v1 Tag Generator
    
    private func buildID3v1Tag(_ tag: ID3v1Tag) -> Data {
        var data = Data(count: 128)
        data[0] = 0x54 // 'T'
        data[1] = 0x41 // 'A'
        data[2] = 0x47 // 'G'
        
        encodeString(tag.title, into: &data, offset: 3, length: 30)
        encodeString(tag.artist, into: &data, offset: 33, length: 30)
        encodeString(tag.album, into: &data, offset: 63, length: 30)
        encodeString(tag.year, into: &data, offset: 93, length: 4)
        encodeString(tag.comment, into: &data, offset: 97, length: 28)
        
        data[125] = 0x00 // ID3v1.1 indicator
        data[126] = tag.trackNumber
        data[127] = tag.genreIndex
        
        return data
    }
    
    private func encodeString(_ string: String, into data: inout Data, offset: Int, length: Int) {
        // Encode using Windows-1251 (or ISO Latin 1 fallback) so Russian titles display authentically
        let cfEnc = CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        let bytes = string.data(using: String.Encoding(rawValue: nsEnc)) ?? string.data(using: .isoLatin1) ?? string.data(using: .utf8) ?? Data()
        
        let writeCount = min(bytes.count, length)
        for i in 0..<writeCount {
            data[offset + i] = bytes[i]
        }
    }
    
    // MARK: - ID3v2.3 Tag Generator
    
    private func buildID3v2Tag(_ tag: ID3v2Tag, artwork: ArtworkInfo?) -> Data {
        var framesData = Data()
        
        // Text Frames (Encoding: 0x03 for UTF-8)
        func appendTextFrame(id: String, value: String) {
            guard !value.isEmpty else { return }
            var frame = Data()
            frame.append(0x03) // UTF-8 encoding flag
            if let valData = value.data(using: .utf8) {
                frame.append(valData)
            }
            appendFrame(id: id, payload: frame, to: &framesData)
        }
        
        appendTextFrame(id: "TIT2", value: tag.title)
        appendTextFrame(id: "TPE1", value: tag.artist)
        appendTextFrame(id: "TALB", value: tag.album)
        appendTextFrame(id: "TYER", value: tag.year)
        appendTextFrame(id: "TRCK", value: tag.trackNumber)
        appendTextFrame(id: "TPOS", value: tag.discNumber)
        appendTextFrame(id: "TCON", value: tag.genre)
        appendTextFrame(id: "TCOM", value: tag.composer)
        appendTextFrame(id: "TOPE", value: tag.originalArtist)
        appendTextFrame(id: "TCOP", value: tag.copyright)
        appendTextFrame(id: "TENC", value: tag.encodedBy)
        
        // URL frame (WXXX)
        if !tag.url.isEmpty {
            var wxxx = Data()
            wxxx.append(0x00) // ISO Latin 1 description
            wxxx.append(0x00) // empty description null terminator
            if let urlBytes = tag.url.data(using: .isoLatin1) {
                wxxx.append(urlBytes)
            }
            appendFrame(id: "WXXX", payload: wxxx, to: &framesData)
        }
        
        // Comment frame (COMM)
        if !tag.comment.isEmpty {
            var comm = Data()
            comm.append(0x03) // UTF-8
            comm.append(contentsOf: [0x65, 0x6E, 0x67]) // Language: "eng"
            comm.append(0x00) // Short description null terminator
            if let cBytes = tag.comment.data(using: .utf8) {
                comm.append(cBytes)
            }
            appendFrame(id: "COMM", payload: comm, to: &framesData)
        }
        
        // Artwork frame (APIC)
        if let art = artwork, !art.imageData.isEmpty {
            var apic = Data()
            apic.append(0x03) // UTF-8 description
            // MIME type (null terminated ASCII)
            if let mimeBytes = art.mimeType.data(using: .ascii) {
                apic.append(mimeBytes)
            }
            apic.append(0x00) // MIME null terminator
            apic.append(0x03) // Picture Type: 0x03 = Front Cover
            apic.append(0x00) // Description null terminator
            apic.append(art.imageData)
            appendFrame(id: "APIC", payload: apic, to: &framesData)
        }
        
        // Build 10-byte ID3v2.3 Header
        var header = Data()
        header.append(contentsOf: [0x49, 0x44, 0x33]) // "ID3"
        header.append(contentsOf: [0x03, 0x00])       // Version 2.3.0
        header.append(0x00)                         // Flags: 0
        header.append(encodeSynchsafe(UInt32(framesData.count)))
        
        header.append(framesData)
        return header
    }
    
    private func appendFrame(id: String, payload: Data, to output: inout Data) {
        guard let idBytes = id.data(using: .ascii), idBytes.count == 4 else { return }
        output.append(idBytes)
        
        // 32-bit big-endian frame size (normal uint in ID3v2.3)
        var sizeBE = UInt32(payload.count).bigEndian
        output.append(Data(bytes: &sizeBE, count: 4))
        
        // 2-byte flags (0x0000)
        output.append(contentsOf: [0x00, 0x00])
        
        // Payload
        output.append(payload)
    }
    
    // MARK: - Synchsafe Integer Helpers
    
    private func decodeSynchsafe(_ slice: Data) -> UInt32 {
        var result: UInt32 = 0
        for byte in slice {
            result = (result << 7) | UInt32(byte & 0x7F)
        }
        return result
    }
    
    private func encodeSynchsafe(_ value: UInt32) -> Data {
        var val = value
        let b3 = UInt8(val & 0x7F)
        val >>= 7
        let b2 = UInt8(val & 0x7F)
        val >>= 7
        let b1 = UInt8(val & 0x7F)
        val >>= 7
        let b0 = UInt8(val & 0x7F)
        return Data([b0, b1, b2, b3])
    }
    
    // MARK: - Non-MP3 Metadata Fallback
    
    private func writeNonMP3Metadata(_ metadata: AudioFileMetadata, to url: URL) throws {
        // Non-MP3 files (e.g. M4A/FLAC) can be edited via AVAssetExportSession or local caches
        // For now, if the file cannot be modified in-place, throw informative error
        throw NSError(domain: "MacAmp.AudioMetadataService", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "In-place tag editing for .\(url.pathExtension) is not yet supported. Only MP3 ID3 tags are currently writable."
        ])
    }
}
