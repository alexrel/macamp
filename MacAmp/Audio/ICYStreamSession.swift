import Foundation
import Accelerate

/// A streaming network session that connects to SHOUTcast and Icecast servers,
/// requests and parses live ICY metadata (station name, bitrate, live song titles),
/// and generates real-time spectral and waveform data for the Winamp visualizer.
public class ICYStreamSession: NSObject, URLSessionDataDelegate {
    
    // MARK: - Properties
    public let streamURL: URL
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    
    public private(set) var stationName: String?
    public private(set) var genre: String?
    public private(set) var bitrate: Int = 128
    public private(set) var sampleRate: Int = 44
    public private(set) var currentStreamTitle: String = ""
    
    // ICY Parsing State
    private var metaInterval: Int = 0
    private var audioByteCounter: Int = 0
    private var isReadingMetaLength: Bool = false
    private var metaLengthExpected: Int = 0
    private var metaBuffer = Data()
    
    // Spectral & Waveform Generation
    private var audioSampleBuffer: [Float] = []
    private var lastVisUpdate: TimeInterval = 0
    
    // Callbacks
    public var onMetadataUpdate: ((_ artist: String, _ title: String, _ bitrate: Int?, _ sampleRate: Int?) -> Void)?
    public var onSpectralData: (([Float]) -> Void)?
    public var onWaveformData: (([Float]) -> Void)?
    
    // MARK: - Init & Lifecycle
    public init(url: URL) {
        self.streamURL = url
        super.init()
    }
    
    deinit {
        stop()
    }
    
    public func start() {
        stop()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 0 // Continuous streaming
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        
        var request = URLRequest(url: streamURL)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue("WinampMPEG/2.91", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        let task = session.dataTask(with: request)
        self.dataTask = task
        task.resume()
    }
    
    public func stop() {
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
        
        audioByteCounter = 0
        metaLengthExpected = 0
        metaBuffer.removeAll()
        audioSampleBuffer.removeAll()
    }
    
    // MARK: - URLSessionDataDelegate
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            parseHeaders(http.allHeaderFields)
        }
        completionHandler(.allow)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !data.isEmpty else { return }
        
        if metaInterval <= 0 {
            // No ICY metadata in this stream: all bytes are audio
            processAudioChunk(data)
            return
        }
        
        var offset = 0
        let total = data.count
        
        while offset < total {
            if metaLengthExpected > 0 {
                // Currently accumulating metadata bytes
                let needed = metaLengthExpected - metaBuffer.count
                let available = total - offset
                let take = min(needed, available)
                metaBuffer.append(data.subdata(in: offset..<(offset + take)))
                offset += take
                
                if metaBuffer.count == metaLengthExpected {
                    parseMetadataPayload(metaBuffer)
                    metaBuffer.removeAll(keepingCapacity: true)
                    metaLengthExpected = 0
                    audioByteCounter = 0
                }
            } else if isReadingMetaLength {
                // Reading the single length byte
                let lenByte = Int(data[offset])
                offset += 1
                isReadingMetaLength = false
                let metaBytes = lenByte * 16
                if metaBytes > 0 {
                    metaLengthExpected = metaBytes
                    metaBuffer.removeAll(keepingCapacity: true)
                } else {
                    audioByteCounter = 0
                }
            } else {
                // Reading audio bytes up to metaInterval
                let needed = metaInterval - audioByteCounter
                let available = total - offset
                let take = min(needed, available)
                
                if take > 0 {
                    let audioChunk = data.subdata(in: offset..<(offset + take))
                    processAudioChunk(audioChunk)
                    audioByteCounter += take
                    offset += take
                }
                
                if audioByteCounter >= metaInterval {
                    isReadingMetaLength = true
                }
            }
        }
    }
    
    // MARK: - Header Parsing
    private func parseHeaders(_ headers: [AnyHashable: Any]) {
        var metaint = 0
        var br = 128
        var name: String?
        var gen: String?
        
        for (k, v) in headers {
            let key = "\(k)".lowercased()
            let val = "\(v)"
            
            if key == "icy-metaint" {
                metaint = Int(val) ?? 0
            } else if key == "icy-br" {
                br = Int(val) ?? 128
            } else if key == "icy-name" {
                name = val
            } else if key == "icy-genre" {
                gen = val
            }
        }
        
        self.metaInterval = metaint
        self.bitrate = br
        self.stationName = name
        self.genre = gen
        
        let initialTitle = name ?? (streamURL.lastPathComponent.isEmpty ? (streamURL.host ?? "Internet Radio") : streamURL.lastPathComponent)
        let initialArtist = gen ?? "Internet Stream"
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onMetadataUpdate?(initialArtist, initialTitle, self.bitrate, self.sampleRate)
        }
    }
    
    // MARK: - Metadata Payload Parsing
    private func parseMetadataPayload(_ data: Data) {
        guard let rawString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return
        }
        
        // Typical format: StreamTitle='Artist - Song Title';StreamUrl='';
        guard let titleRange = rawString.range(of: "StreamTitle='") else { return }
        let afterPrefix = rawString[titleRange.upperBound...]
        guard let endRange = afterPrefix.range(of: "';") else { return }
        let streamTitle = String(afterPrefix[..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        
        guard !streamTitle.isEmpty, streamTitle != currentStreamTitle else { return }
        self.currentStreamTitle = streamTitle
        
        let artist: String
        let title: String
        if streamTitle.contains(" - ") {
            let parts = streamTitle.components(separatedBy: " - ")
            artist = parts[0].trimmingCharacters(in: .whitespaces)
            title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        } else {
            title = streamTitle
            artist = stationName ?? "Internet Stream"
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onMetadataUpdate?(artist, title, self.bitrate, self.sampleRate)
        }
    }
    
    // MARK: - Audio Chunk Analysis (Visualizer Tap)
    private func processAudioChunk(_ data: Data) {
        // Sample byte differences to generate real-time music-synchronized waveform & spectrum
        let now = Date().timeIntervalSince1970
        guard now - lastVisUpdate >= 0.033 else { return } // ~30-60 fps
        lastVisUpdate = now
        
        let count = data.count
        guard count >= 128 else { return }
        
        // Extract up to 1024 sample values normalized to -1.0 ... 1.0
        var samples = [Float]()
        samples.reserveCapacity(512)
        let strideVal = max(1, count / 512)
        
        data.withUnsafeBytes { rawPtr in
            let bytes = rawPtr.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: count - 1, by: strideVal) {
                let v = Float(Int(bytes[i]) - 128) / 128.0
                samples.append(v)
            }
        }
        
        guard samples.count >= 64 else { return }
        
        // Generate 19-band spectrum from sample energy
        var spectrum = [Float](repeating: 0.0, count: AppConstants.Visualizer.numSpectrumBars)
        let binSize = samples.count / 19
        for b in 0..<19 {
            var sum: Float = 0
            let start = b * binSize
            let end = min(samples.count, start + binSize)
            for j in start..<end {
                sum += abs(samples[j])
            }
            let avg = (end > start) ? (sum / Float(end - start)) : 0
            // Boost high bins slightly to mimic natural audio frequency weighting
            let freqWeight = 1.0 + Float(b) * 0.05
            spectrum[b] = min(1.0, avg * 2.2 * freqWeight)
        }
        
        // Generate waveform (75 points for Winamp oscilloscope)
        var waveform = [Float]()
        waveform.reserveCapacity(75)
        let waveStride = max(1, samples.count / 75)
        for i in stride(from: 0, to: min(samples.count, 75 * waveStride), by: waveStride) {
            waveform.append(samples[i])
        }
        while waveform.count < 75 {
            waveform.append(0)
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onSpectralData?(spectrum)
            self.onWaveformData?(waveform)
        }
    }
    
    // MARK: - Playlist / Stream URL Resolver
    /// Resolves direct stream audio URLs from .pls or .m3u web playlists
    public static func resolveStreamURL(from url: URL) async -> URL {
        guard !url.isFileURL else { return url }
        
        let pathExt = url.pathExtension.lowercased()
        if pathExt != "pls" && pathExt != "m3u" && pathExt != "m3u8" {
            return url
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("WinampMPEG/2.91", forHTTPHeaderField: "User-Agent")
        
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return url
        }
        
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            
            if line.lowercased().hasPrefix("file") && line.contains("=") {
                let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, let target = URL(string: parts[1]) {
                    return target
                }
            } else if line.lowercased().hasPrefix("http://") || line.lowercased().hasPrefix("https://") {
                if let target = URL(string: line) {
                    return target
                }
            }
        }
        
        return url
    }
}
