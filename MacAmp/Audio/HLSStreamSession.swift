import Foundation

/// What the engine needs from a radio connection: SHOUTcast / Icecast (ICY) or HTTP Live Streaming
public protocol RadioStreamSession: AnyObject {
    /// Content-Type of the audio handed to `onAudioData`, known before its first bytes
    var contentType: String? { get }
    var genre: String? { get }
    var onMetadataUpdate: ((_ artist: String, _ title: String, _ bitrate: Int?, _ sampleRate: Int?) -> Void)? { get set }
    /// Compressed audio, in order, one call at a time
    var onAudioData: ((Data) -> Void)? { get set }
    /// The connection ended (not after `stop()`)
    var onFinished: ((Error?) -> Void)? { get set }
    func start()
    func stop()
}

extension ICYStreamSession: RadioStreamSession {}

/// HTTP Live Streaming radio (BBC, FIP, RTL, NHK...): reads the playlist, fetches each new segment and hands its audio
/// to the same decoder as SHOUTcast streams, so EQ, DSP and the visualizer work. Segments measured on stations:
/// MPEG-TS with AAC inside, and packed AAC with an ID3 tag in front. fMP4 segments, encryption and LATM audio are
/// left to AVPlayer (the engine's fallback).
/// shortcut: in-segment ID3 titles aren't read: of ~40 stations measured none sent TIT2 / TPE1 (only timestamps, RTL 102.5
/// its own JSON with the show); read them if a station that does shows up
public final class HLSStreamSession: RadioStreamSession {
    public let playlistURL: URL
    public private(set) var contentType: String?
    public let genre: String? = nil
    public var onMetadataUpdate: ((_ artist: String, _ title: String, _ bitrate: Int?, _ sampleRate: Int?) -> Void)?
    public var onAudioData: ((Data) -> Void)?
    public var onFinished: ((Error?) -> Void)?
    private var task: Task<Void, Never>?

    /// A live stream starts this many segments before its end, enough for the engine's prebuffer
    static let liveEdgeSegments = 3
    /// Content-Type that makes the engine hand the stream to AVPlayer
    static let fallbackContentType = "application/vnd.apple.mpegurl"

    public init(url: URL) { playlistURL = url }
    deinit { task?.cancel() }

    public func start() {
        stop()
        task = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func run() async {
        do {
            // A master playlist points to the media playlist; a media playlist read here is used as is
            var media = playlistURL
            var playlist = HLSPlaylist.parse(try await text(media), base: media)
            if let variant = playlist.preferredVariant {
                media = variant
                playlist = HLSPlaylist.parse(try await text(media), base: media)
            }
            var next: Int?
            while !Task.isCancelled {
                guard !playlist.isEncrypted, !playlist.hasInitSection else { return handOver() }
                let first = playlist.mediaSequence
                let start = max(first, next ?? (playlist.isEnded ? first : first + playlist.segments.count - Self.liveEdgeSegments))
                for (offset, segment) in playlist.segments.enumerated() where first + offset >= start {
                    guard let audio = HLSSegment.audio(from: try await data(segment)) else { return handOver() }
                    try Task.checkCancellation()
                    if contentType == nil { contentType = audio.contentType }
                    onAudioData?(audio.bytes)
                    next = first + offset + 1
                }
                if playlist.isEnded { break }
                try await Task.sleep(nanoseconds: UInt64(max(1, playlist.targetDuration / 2) * 1_000_000_000))
                playlist = HLSPlaylist.parse(try await text(media), base: media)
            }
            if !Task.isCancelled { onFinished?(nil) }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { onFinished?(error) }
        }
    }

    /// Segments this client can't read: the engine's decoder refuses this Content-Type and AVPlayer takes the stream
    private func handOver() {
        guard !Task.isCancelled else { return }
        contentType = Self.fallbackContentType
        onAudioData?(Data())
    }

    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(AppConstants.App.streamUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await MacAmpNetwork.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return data
    }

    private func text(_ url: URL) async throws -> String { TextEncoding.decode(try await data(url)) }
}

/// An HLS playlist: a master one (variants, audio renditions) or a media one (segments)
struct HLSPlaylist {
    var variants: [(url: URL, bandwidth: Int, codecs: String)] = []
    var audioRenditions: [URL] = []
    var segments: [URL] = []
    var mediaSequence = 0
    var targetDuration: Double = 6
    var isEnded = false
    var isEncrypted = false
    var hasInitSection = false

    static func isHLS(_ text: String) -> Bool { text.contains("#EXT-X-TARGETDURATION") || text.contains("#EXT-X-STREAM-INF") }

    static func parse(_ text: String, base: URL) -> HLSPlaylist {
        var playlist = HLSPlaylist()
        var pendingVariant: (bandwidth: Int, codecs: String)?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let attributes = Self.attributes(line)
                if line.hasPrefix("#EXT-X-STREAM-INF:") {
                    pendingVariant = (Int(attributes["BANDWIDTH"] ?? "") ?? 0, attributes["CODECS"] ?? "")
                } else if line.hasPrefix("#EXT-X-MEDIA:"), attributes["TYPE"] == "AUDIO", let uri = attributes["URI"],
                          let url = URL(string: uri, relativeTo: base) {
                    playlist.audioRenditions.append(url.absoluteURL)
                } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                    playlist.mediaSequence = Int(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) ?? 0
                } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                    playlist.targetDuration = Double(line.dropFirst("#EXT-X-TARGETDURATION:".count)) ?? 6
                } else if line.hasPrefix("#EXT-X-ENDLIST") {
                    playlist.isEnded = true
                } else if line.hasPrefix("#EXT-X-KEY:"), attributes["METHOD"] != "NONE" {
                    playlist.isEncrypted = true
                } else if line.hasPrefix("#EXT-X-MAP:") {
                    playlist.hasInitSection = true
                }
            } else if let url = URL(string: line, relativeTo: base)?.absoluteURL {
                if let variant = pendingVariant {
                    playlist.variants.append((url, variant.bandwidth, variant.codecs))
                    pendingVariant = nil
                } else {
                    playlist.segments.append(url)
                }
            }
        }
        return playlist
    }

    /// For a master playlist: a separate audio rendition, else the best audio-only variant, else the lightest one
    /// (a video stream's audio comes with the smallest picture)
    var preferredVariant: URL? {
        if let audio = audioRenditions.first { return audio }
        let videoCodecs = ["avc", "hvc", "hev", "vp0", "av01"]
        let audioOnly = variants.filter { v in !v.codecs.isEmpty && !videoCodecs.contains { v.codecs.lowercased().contains($0) } }
        return (audioOnly.max { $0.bandwidth < $1.bandwidth } ?? variants.min { $0.bandwidth < $1.bandwidth })?.url
    }

    /// KEY=VALUE,KEY="quoted, value" after the tag's colon
    static func attributes(_ line: String) -> [String: String] {
        guard let colon = line.firstIndex(of: ":") else { return [:] }
        var result: [String: String] = [:]
        var key = "", value = "", inKey = true, quoted = false
        func flush() { if !key.isEmpty { result[key] = value }; key = ""; value = ""; inKey = true }
        for ch in line[line.index(after: colon)...] {
            if inKey {
                if ch == "=" { inKey = false } else if ch != "," { key.append(ch) }
            } else if ch == "\"" {
                quoted.toggle()
            } else if ch == "," && !quoted {
                flush()
            } else {
                value.append(ch)
            }
        }
        flush()
        return result
    }
}

/// The audio inside one HLS segment
enum HLSSegment {
    static let tsPacket = 188

    /// ADTS AAC (or MPEG audio) bytes and their Content-Type; nil for what isn't handled (fMP4, LATM, unknown)
    static func audio(from data: Data) -> (bytes: Data, contentType: String)? {
        let bytes = [UInt8](data)
        if bytes.count >= tsPacket, bytes[0] == 0x47, bytes.count < 2 * tsPacket || bytes[tsPacket] == 0x47 {
            return demuxTS(bytes)
        }
        // Stations put one or more ID3 tags (timestamps, titles) in front: measured, NHK and RTL 102.5 send two
        var start = 0
        while case let length = id3Length(bytes, at: start), length > 0 { start += length }
        let audio = Array(bytes[start...])
        guard audio.count > 2, audio[0] == 0xFF, audio[1] & 0xE0 == 0xE0 else { return nil }
        return (Data(audio), contentType(frameHeader: audio[1]))
    }

    /// ADTS has layer bits 00 after the sync word; MPEG audio frames have a layer
    private static func contentType(frameHeader byte: UInt8) -> String { byte & 0x06 == 0 ? "audio/aac" : "audio/mpeg" }

    /// Size of the ID3v2 tag at `offset` (0 without one)
    static func id3Length(_ bytes: [UInt8], at offset: Int) -> Int {
        guard bytes.count >= offset + 10, bytes[offset] == 0x49, bytes[offset + 1] == 0x44, bytes[offset + 2] == 0x33 else { return 0 }
        let size = bytes[(offset + 6)...(offset + 9)].reduce(0) { ($0 << 7) | Int($1 & 0x7F) }
        let footer = bytes[offset + 5] & 0x10 != 0 ? 10 : 0
        return min(bytes.count - offset, 10 + size + footer)
    }

    /// MPEG-TS: PAT → PMT → the audio stream's PES packets, their headers dropped
    static func demuxTS(_ bytes: [UInt8]) -> (bytes: Data, contentType: String)? {
        var pmtPID: Int?, audioPID: Int?, type = ""
        var out = Data()
        var offset = 0
        while offset + tsPacket <= bytes.count {
            defer { offset += tsPacket }
            guard bytes[offset] == 0x47 else { continue }
            let start = bytes[offset + 1] & 0x40 != 0
            let pid = Int(bytes[offset + 1] & 0x1F) << 8 | Int(bytes[offset + 2])
            let control = (bytes[offset + 3] >> 4) & 0x3
            guard control & 0x1 != 0 else { continue } // no payload
            var payload = offset + 4
            if control & 0x2 != 0 { payload += 1 + Int(bytes[offset + 4]) }
            let end = offset + tsPacket
            guard payload < end else { continue }
            if pid == 0, start {
                // PAT: pointer field, then the first program's PMT PID
                let table = payload + 1 + Int(bytes[payload])
                guard table + 12 <= end else { continue }
                pmtPID = Int(bytes[table + 10] & 0x1F) << 8 | Int(bytes[table + 11])
            } else if pid == pmtPID, start, audioPID == nil {
                let table = payload + 1 + Int(bytes[payload])
                guard table + 12 <= end else { continue }
                let sectionEnd = min(end, table + 3 + (Int(bytes[table + 1] & 0x0F) << 8 | Int(bytes[table + 2])) - 4)
                var entry = table + 12 + (Int(bytes[table + 10] & 0x0F) << 8 | Int(bytes[table + 11]))
                while entry + 5 <= sectionEnd {
                    let streamType = bytes[entry]
                    let streamPID = Int(bytes[entry + 1] & 0x1F) << 8 | Int(bytes[entry + 2])
                    if streamType == 0x0F || streamType == 0x03 || streamType == 0x04 {
                        audioPID = streamPID
                        type = streamType == 0x0F ? "audio/aac" : "audio/mpeg"
                        break
                    }
                    entry += 5 + (Int(bytes[entry + 3] & 0x0F) << 8 | Int(bytes[entry + 4]))
                }
            } else if pid == audioPID {
                if start {
                    // PES header: 00 00 01, stream id, length, two flag bytes, header data length
                    guard payload + 9 <= end, bytes[payload] == 0, bytes[payload + 1] == 0, bytes[payload + 2] == 1 else { continue }
                    payload += 9 + Int(bytes[payload + 8])
                }
                if payload < end { out.append(contentsOf: bytes[payload..<end]) }
            }
        }
        return audioPID == nil || out.isEmpty ? nil : (out, type)
    }
}
