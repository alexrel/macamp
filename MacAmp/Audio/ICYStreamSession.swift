import Foundation

/// A streaming network session that connects to SHOUTcast and Icecast servers,
/// requests and parses live ICY metadata (station name, bitrate, live song titles),
/// and hands the remaining compressed audio bytes to `onAudioData` for decoding.
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
    public var metaInt: Int { metaInterval }
    /// HTTP Content-Type of the stream (e.g. "audio/mpeg", "audio/aacp"); known before the first audio bytes.
    public private(set) var contentType: String?
    
    // Testing Hooks
    public func feedHeadersForTesting(_ headers: [AnyHashable: Any]) {
        parseHeaders(headers)
    }
    public func feedDataForTesting(_ data: Data) {
        consume(data)
    }
    
    // ICY Parsing State
    private var metaInterval: Int = 0
    private var audioByteCounter: Int = 0
    private var isReadingMetaLength: Bool = false
    private var metaLengthExpected: Int = 0
    private var metaBuffer = Data()
    
    // Callbacks
    public var onMetadataUpdate: ((_ artist: String, _ title: String, _ bitrate: Int?, _ sampleRate: Int?) -> Void)?
    /// Compressed audio bytes with ICY metadata blocks stripped. Called on the session's serial delegate queue.
    public var onAudioData: ((Data) -> Void)?
    /// Connection ended (server closed, network error, HTTP error). Not called after `stop()`. Called on the delegate queue.
    public var onFinished: ((Error?) -> Void)?
    
    /// Serial queue for all URLSession callbacks, so audio chunks arrive (and are decoded) strictly in order.
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "MacAmp.ICYStreamSession"
        return queue
    }()
    
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
        
        let config = MacAmpNetwork.configuration() // user's HTTP proxy, if any
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 0 // Continuous streaming
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        self.session = session
        
        var request = URLRequest(url: streamURL)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue(AppConstants.App.streamUserAgent, forHTTPHeaderField: "User-Agent")
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
        isReadingMetaLength = false
        metaBuffer.removeAll()
    }
    
    // MARK: - URLSessionDataDelegate
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                completionHandler(.cancel)
                onFinished?(URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
                return
            }
            parseHeaders(http.allHeaderFields)
        }
        contentType = response.mimeType ?? contentType
        completionHandler(.allow)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Cancellation comes from stop(); don't report it as a failure
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        guard task === dataTask else { return }
        onFinished?(error)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        consume(data)
    }
    
    /// Splits incoming bytes into audio (forwarded to `onAudioData`) and ICY metadata blocks.
    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        
        if metaInterval <= 0 {
            // No ICY metadata in this stream: all bytes are audio
            onAudioData?(data)
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
                    onAudioData?(data.subdata(in: offset..<(offset + take)))
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
            } else if key == "content-type" {
                contentType = val
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
        // Many Russian stations send StreamTitle in CP1251 without declaring it
        let rawString = TextEncoding.decode(data)
        
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
        request.setValue(AppConstants.App.streamUserAgent, forHTTPHeaderField: "User-Agent")
        
        guard let (data, _) = try? await MacAmpNetwork.session.data(for: request) else {
            return url
        }
        let content = TextEncoding.decode(data)
        
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
