import AVFoundation
import CryptoKit

/// An audio CD as macOS mounts it: `/Volumes/<disc>/1 Audio Track.aiff`, ... plus `.TOC.plist`.
/// Names come from MusicBrainz by Disc ID: Winamp 2.95 used CDDB, which is gone.
public struct AudioCD: Sendable {
    public struct Track: Sendable, Equatable {
        public let number: Int
        public let url: URL
        public var title: String
        public var artist: String
        public let length: TimeInterval
    }

    public let volume: URL
    public let firstTrack: Int
    public let lastTrack: Int
    /// Track starts in sectors, counting the 2 s lead-in (track 1 normally starts at 150), and the lead-out
    public let offsets: [Int]
    public let leadout: Int
    public var album = ""
    public var artist = ""
    public var year = ""
    public var tracks: [Track]

    /// Reads `.TOC.plist`; nil when the volume isn't an audio CD.
    public init?(volume: URL) {
        guard let data = try? Data(contentsOf: volume.appendingPathComponent(".TOC.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let toc = AudioCD.parseTOC(plist) else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(at: volume, includingPropertiesForKeys: nil)) ?? []
        self.init(volume: volume, toc: toc, files: files)
    }

    init(volume: URL, toc: (first: Int, last: Int, offsets: [Int], leadout: Int), files: [URL]) {
        self.volume = volume
        firstTrack = toc.first
        lastTrack = toc.last
        offsets = toc.offsets
        leadout = toc.leadout
        // "1 Audio Track.aiff": the file name starts with the track number
        let byNumber = Dictionary(files.compactMap { url in
            Int(url.lastPathComponent.prefix { $0.isNumber }).map { ($0, url) }
        }, uniquingKeysWith: { a, _ in a })
        tracks = toc.offsets.indices.compactMap { i in
            let number = toc.first + i
            guard let url = byNumber[number] else { return nil }
            let end = i + 1 < toc.offsets.count ? toc.offsets[i + 1] : toc.leadout
            return Track(number: number, url: url, title: "Track \(number)", artist: "", length: Double(end - toc.offsets[i]) / 75)
        }
    }

    /// Session 1's audio tracks from `.TOC.plist` (an enhanced CD's data session is left out, as MusicBrainz does).
    static func parseTOC(_ plist: [String: Any]) -> (first: Int, last: Int, offsets: [Int], leadout: Int)? {
        guard let sessions = plist["Sessions"] as? [[String: Any]],
              let session = sessions.first(where: { ($0["Session Number"] as? Int ?? 1) == 1 }) ?? sessions.first,
              let leadout = session["Leadout Block"] as? Int,
              let array = session["Track Array"] as? [[String: Any]] else { return nil }
        let audio = array.filter { !($0["Data"] as? Bool ?? false) }
            .compactMap { t -> (Int, Int)? in
                guard let point = t["Point"] as? Int, let start = t["Start Block"] as? Int else { return nil }
                return (point, start)
            }
            .sorted { $0.0 < $1.0 }
        guard let first = audio.first, let last = audio.last else { return nil }
        // shortcut: assumes LBA when track 1 starts at 0 (the usual case); a hidden track before track 1 would be misread
        let shift = first.1 < 150 ? 150 : 0
        return (first.0, last.0, audio.map { $0.1 + shift }, leadout + shift)
    }

    // MARK: MusicBrainz

    /// MusicBrainz Disc ID: SHA-1 of the TOC as hex text, in MusicBrainz's URL-safe Base64.
    public var discID: String { AudioCD.discID(first: firstTrack, last: lastTrack, leadout: leadout, offsets: offsets) }

    static func discID(first: Int, last: Int, leadout: Int, offsets: [Int]) -> String {
        var text = String(format: "%02X%02X%08X", first, last, leadout)
        for i in 0..<99 { text += String(format: "%08X", i < offsets.count ? offsets[i] : 0) }
        return Data(Insecure.SHA1.hash(data: Data(text.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: ".").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "-")
    }

    /// Fills album, artist, year and track names from MusicBrainz; the CD stays as it is when the disc is unknown or offline.
    public func lookedUp() async -> AudioCD {
        let toc = ([firstTrack, lastTrack, leadout] + offsets).map(String.init).joined(separator: "+")
        guard !MacAmpNetwork.isOffline,
              let url = URL(string: "https://musicbrainz.org/ws/2/discid/\(discID)?toc=\(toc)&inc=recordings+artist-credits&fmt=json") else { return self }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MacAmp/\(AppConstants.App.version) (macOS audio player)", forHTTPHeaderField: "User-Agent")
        // MusicBrainz answers 503 when busy (1 request/s per client): one retry a second later
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 1_100_000_000) }
            guard let (data, response) = try? await MacAmpNetwork.session.data(for: request) else { continue }
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 200 { return applying(musicBrainz: data) }
            if status != 503 { break }
        }
        return self
    }

    func applying(musicBrainz data: Data) -> AudioCD {
        struct Credit: Decodable { let name: String; let joinphrase: String? }
        struct MBTrack: Decodable {
            let position: Int; let title: String; let artistCredit: [Credit]?
            enum CodingKeys: String, CodingKey { case position, title, artistCredit = "artist-credit" }
        }
        struct Disc: Decodable { let id: String }
        struct Medium: Decodable { let discs: [Disc]?; let tracks: [MBTrack]? }
        struct Release: Decodable {
            let title: String; let date: String?; let artistCredit: [Credit]?; let media: [Medium]
            enum CodingKeys: String, CodingKey { case title, date, media, artistCredit = "artist-credit" }
        }
        struct Response: Decodable { let releases: [Release]? }
        guard let releases = try? JSONDecoder().decode(Response.self, from: data).releases,
              let release = releases.first(where: { $0.media.contains { $0.discs?.contains { $0.id == discID } ?? false } }) ?? releases.first,
              let medium = release.media.first(where: { $0.discs?.contains { $0.id == discID } ?? false })
                ?? release.media.first(where: { $0.tracks?.count == tracks.count }) else { return self }
        func name(_ credits: [Credit]?) -> String { (credits ?? []).map { $0.name + ($0.joinphrase ?? "") }.joined() }
        var cd = self
        cd.album = release.title
        cd.artist = name(release.artistCredit)
        cd.year = String((release.date ?? "").prefix(4))
        for i in cd.tracks.indices {
            guard let mb = medium.tracks?.first(where: { $0.position == cd.tracks[i].number - firstTrack + 1 }) else { continue }
            cd.tracks[i].title = mb.title
            cd.tracks[i].artist = mb.artistCredit.map(name) ?? cd.artist
        }
        return cd
    }

    /// The disc in `volume` with MusicBrainz names, looked up once per disc (25 tracks added at once make one request).
    public static func named(volume: URL) async -> AudioCD? {
        guard let cd = AudioCD(volume: volume) else { return nil }
        return await NameCache.shared.lookedUp(cd)
    }

    /// Name of an untagged file on a mounted audio CD ("1 Audio Track.aiff"), for playlists and the player.
    static func name(for url: URL) async -> (artist: String, title: String)? {
        guard url.isFileURL, url.pathExtension.lowercased() == "aiff",
              FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(".TOC.plist").path),
              let cd = await named(volume: url.deletingLastPathComponent()), !cd.album.isEmpty,
              let track = cd.tracks.first(where: { $0.url.lastPathComponent == url.lastPathComponent }) else { return nil }
        return (track.artist.isEmpty ? cd.artist : track.artist, track.title)
    }

    private actor NameCache {
        static let shared = NameCache()
        private var lookups: [String: Task<AudioCD, Never>] = [:]

        func lookedUp(_ cd: AudioCD) async -> AudioCD {
            let key = cd.discID
            let task = lookups[key] ?? Task { await cd.lookedUp() }
            lookups[key] = task
            let named = await task.value
            if named.album.isEmpty { lookups[key] = nil } // unknown or offline: ask again next time
            // Same disc in another drive / remount: keep its names, but this volume's file URLs
            var result = cd
            (result.album, result.artist, result.year) = (named.album, named.artist, named.year)
            for i in result.tracks.indices {
                if let n = named.tracks.first(where: { $0.number == result.tracks[i].number }) {
                    (result.tracks[i].title, result.tracks[i].artist) = (n.title, n.artist)
                }
            }
            return result
        }
    }

    public var trackItems: [TrackItem] {
        tracks.map { TrackItem(url: $0.url, title: $0.title, artist: $0.artist, duration: $0.length) }
    }

    // MARK: Ripping (Library ▸ Devices ▸ CD ▸ Extract)

    /// Output path from Winamp's naming template: `<Artist>`, `<Album>`, `<Title>`, `<Year>`, `<#>`; `/` makes folders.
    public func ripName(for track: Track, template: String) -> String {
        func clean(_ s: String, _ fallback: String) -> String {
            let v = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? fallback : v
        }
        let values = ["<Artist>": clean(track.artist.isEmpty ? artist : track.artist, "Unknown Artist"),
                      "<Album>": clean(album, "Audio CD"), "<Title>": clean(track.title, "Track \(track.number)"),
                      "<Year>": clean(year, ""), "<#>": String(format: "%02d", track.number)]
        return values.reduce(template) { $0.replacingOccurrences(of: $1.key, with: $1.value, options: .caseInsensitive) }
            .split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "/")
    }

    /// Volumes being ripped: the drive reads one place at a time, so MacAmp doesn't play from them meanwhile
    /// (Winamp's CD plug-in refused too); seeking between the rip and playback stalls both for seconds.
    @MainActor public static var ripping = Set<String>()
    public static let busyMessage = "Audio CD is being ripped - wait for Extract to finish"

    @MainActor public static func isRipping(_ url: URL) -> Bool {
        url.isFileURL && ripping.contains(url.deletingLastPathComponent().standardizedFileURL.path)
    }

    /// Encodes the tracks into `folder` (lossless or AAC, macOS encoders) and tags them. A track that fails
    /// (scratch, read error) is skipped, not the whole rip; only cancelling stops it.
    public func rip(_ numbers: [Int], to folder: URL, template: String, format: DiskWriterFormat, writeTags: Bool,
                    progress: @escaping @MainActor (Int, Int) -> Void) async throws -> (written: [URL], failed: [Int]) {
        var written: [URL] = [], failed: [Int] = []
        for (i, track) in tracks.filter({ numbers.contains($0.number) }).enumerated() {
            await progress(i + 1, numbers.count)
            do {
                let url = try await DiskWriter.write(TrackItem(url: track.url, title: track.title), to: folder,
                                                     name: ripName(for: track, template: template), format: format)
                if writeTags {
                    try? await AudioTagWriter.write([.artist: track.artist.isEmpty ? artist : track.artist, .title: track.title, .album: album,
                                                     .albumArtist: artist, .year: year, .track: "\(track.number)/\(tracks.count)",
                                                     .comment: "Extracted by MacAmp"], to: url)
                }
                written.append(url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failed.append(track.number)
            }
        }
        return (written, failed)
    }
}

/// Tags for files MacAmp writes: Vorbis comments in FLAC, iTunes atoms in M4A.
/// shortcut: WAV and AIFF stay untagged, add ID3 chunks if someone rips to them and misses names.
enum AudioTagWriter {
    enum Field: String { case artist = "ARTIST", title = "TITLE", album = "ALBUM", albumArtist = "ALBUMARTIST", year = "DATE",
                         track = "TRACKNUMBER", comment = "COMMENT" }

    static func write(_ tags: [Field: String], to url: URL) async throws {
        let tags = tags.filter { !$0.value.isEmpty }
        switch url.pathExtension.lowercased() {
        case "flac": try writeFLAC(tags, to: url)
        case "m4a": try await writeM4A(tags, to: url)
        default: break
        }
    }

    /// Replaces the FLAC VORBIS_COMMENT block (type 4) and rewrites the file.
    static func writeFLAC(_ tags: [Field: String], to url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.prefix(4) == Data("fLaC".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        var blocks: [(type: UInt8, body: Data)] = []
        var pos = 4, last = false
        while !last {
            guard pos + 4 <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            last = data[pos] & 0x80 != 0
            let type = data[pos] & 0x7F
            let length = Int(data[pos + 1]) << 16 | Int(data[pos + 2]) << 8 | Int(data[pos + 3])
            guard pos + 4 + length <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            if type != 4 { blocks.append((type, data.subdata(in: pos + 4 ..< pos + 4 + length))) }
            pos += 4 + length
        }
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        let vendor = Data("MacAmp \(AppConstants.App.version)".utf8)
        var comment = le32(vendor.count) + vendor + le32(tags.count)
        for (field, value) in tags.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let entry = Data("\(field.rawValue)=\(value)".utf8)
            comment += le32(entry.count) + entry
        }
        blocks.insert((4, comment), at: min(1, blocks.count)) // after STREAMINFO
        var out = Data("fLaC".utf8)
        for (i, block) in blocks.enumerated() {
            let n = block.body.count
            out += [block.type | (i == blocks.count - 1 ? 0x80 : 0), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]
            out += block.body
        }
        out += data[pos...]
        try out.write(to: url, options: .atomic)
    }

    /// M4A: a passthrough export with the iTunes metadata, then the copy replaces the file.
    static func writeM4A(_ tags: [Field: String], to url: URL) async throws {
        func item(_ id: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = id
            item.value = value
            return item
        }
        var items: [AVMetadataItem] = []
        let ids: [Field: AVMetadataIdentifier] = [.artist: .iTunesMetadataArtist, .title: .iTunesMetadataSongName, .album: .iTunesMetadataAlbum,
                                                  .albumArtist: .iTunesMetadataAlbumArtist, .year: .iTunesMetadataReleaseDate,
                                                  .comment: .iTunesMetadataUserComment]
        for (field, value) in tags {
            if let id = ids[field] { items.append(item(id, value as NSString)) }
        }
        if let track = tags[.track] {
            let parts = track.split(separator: "/").compactMap { Int($0) }
            let n = parts.first ?? 0, total = parts.count > 1 ? parts[1] : 0
            items.append(item(.iTunesMetadataTrackNumber, Data([0, 0, UInt8(n >> 8), UInt8(n & 0xFF), UInt8(total >> 8), UInt8(total & 0xFF), 0, 0]) as NSData))
        }
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let temp = url.deletingPathExtension().appendingPathExtension("tagging.m4a")
        try? FileManager.default.removeItem(at: temp)
        export.metadata = items
        export.outputURL = temp
        export.outputFileType = .m4a
        await export.export() // macOS 14: export(to:as:) needs 15
        guard export.status == .completed else { throw export.error ?? CocoaError(.fileWriteUnknown) }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }
}
