import AppKit
import CryptoKit

/// Plug-ins ▸ General Purpose ▸ Last.fm Scrobbler (gen_audioscrobbler, a 2.x add-on, not in Winamp 2.95 itself).
/// Off by default; while off or not connected it does nothing: no requests, no timers.
public struct LastFMScrobble: Codable, Equatable {
    public var artist: String
    public var title: String
    public var duration: Int
    /// When the track started playing (UTC, seconds since 1970), as Last.fm wants it
    public var timestamp: Int
}

/// `{"error": n, "message": ...}` from Last.fm
public struct LastFMError: LocalizedError, Equatable {
    public let code: Int
    public let message: String
    public var errorDescription: String? { message.isEmpty ? "Last.fm error \(code)" : message }
    /// The session key no longer works (the user revoked MacAmp on last.fm): connect again
    static let invalidSession = 9
    /// auth.getSession before the user allowed MacAmp in the browser
    static let tokenNotAuthorized = 14
}

enum LastFM {
    /// Tests point this at a local server
    static var apiURL = URL(string: AppConstants.LastFM.apiURL)!
    static var apiKey = AppConstants.LastFM.apiKey
    static var sharedSecret = AppConstants.LastFM.sharedSecret
    static let sessionSecretName = "LastFMSession"
    /// track.scrobble takes at most this many tracks per request
    static let batchLimit = 50

    static var hasAPIKey: Bool { !apiKey.isEmpty && !sharedSecret.isEmpty }

    /// api_sig: md5 of every parameter as name + value, names sorted, then the shared secret (format is left out)
    static func signature(_ params: [String: String], secret: String) -> String {
        let text = params.keys.sorted().map { $0 + params[$0]! }.joined() + secret
        return Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func formEncoded(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.keys.sorted().map { key in
            key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + params[key]!.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
    }

    /// A signed call: reading methods (auth.*) by GET, writing ones (track.*) by POST, as the API asks
    static func call(_ method: String, _ params: [String: String] = [:], post: Bool = false) async throws -> [String: Any] {
        guard !MacAmpNetwork.isOffline else { throw MacAmpNetwork.offlineError }
        var all = params
        all["method"] = method
        all["api_key"] = apiKey
        all["api_sig"] = signature(all, secret: sharedSecret)
        all["format"] = "json"
        var request: URLRequest
        if post {
            request = URLRequest(url: apiURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(formEncoded(all).utf8)
        } else {
            request = URLRequest(url: URL(string: apiURL.absoluteString + "?" + formEncoded(all))!)
        }
        let (data, _) = try await MacAmpNetwork.session.data(for: request)
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LastFMError(code: 0, message: "Unexpected answer from Last.fm")
        }
        if let code = body["error"] as? Int { throw LastFMError(code: code, message: body["message"] as? String ?? "") }
        return body
    }
}

/// Counts how long the current track really played (pauses don't count) and scrobbles it once that reaches Last.fm's
/// rule; Now Playing goes out when the track starts. Unsent scrobbles wait in session.json for the next chance.
@MainActor
public final class Scrobbler: ObservableObject {
    public static let shared = Scrobbler()

    /// For Preferences: what's going on (connecting, the last error)
    @Published public private(set) var status = ""
    @Published public private(set) var isConnecting = false

    /// Tests move the clock instead of waiting
    var now: () -> Date = Date.init
    private struct Play {
        var scrobble: LastFMScrobble
        var played: TimeInterval = 0
        var playingSince: Date?
        var sent = false
    }
    private var current: Play?
    private var timer: DispatchWorkItem?
    private var isFlushing = false
    private var persistence: PersistenceManager { PersistenceManager.shared }

    public var isEnabled: Bool { persistence.state.lastFMEnabled }
    public var user: String { persistence.state.lastFMUser }
    var session: String? { LocalSecret.read(LastFM.sessionSecretName) }
    public var isConnected: Bool { session != nil }
    var isActive: Bool { isEnabled && isConnected }
    public var queuedCount: Int { persistence.state.lastFMQueue.count }

    /// Last.fm's rule: a track over 30 s counts once played for half its length or 4 minutes, whichever comes first
    nonisolated static func threshold(for duration: TimeInterval) -> TimeInterval? {
        duration > AppConstants.LastFM.shortestScrobbled ? min(duration / 2, AppConstants.LastFM.scrobbleAfterAtMost) : nil
    }

    // MARK: Playback

    nonisolated static func skipReason(artist: String, title: String, duration: TimeInterval, isStream: Bool) -> String? {
        if isStream { return "radio isn't scrobbled" }
        if artist.isEmpty || title.isEmpty { return "“\(title.isEmpty ? "this track" : title)” has no artist or title tag" }
        if threshold(for: duration) == nil { return "\(Int(AppConstants.LastFM.shortestScrobbled)) seconds or shorter" }
        return nil
    }

    /// A new track was loaded (before it starts playing). Radio, untagged files and short tracks are skipped, with the
    /// reason in the plug-in page's status line until a track that counts starts.
    public func trackStarted(artist: String, title: String, duration: TimeInterval, isStream: Bool = false) {
        timer?.cancel()
        current = nil
        guard isActive else { return }
        let artist = artist.trimmingCharacters(in: .whitespaces), title = title.trimmingCharacters(in: .whitespaces)
        if let reason = Self.skipReason(artist: artist, title: title, duration: duration, isStream: isStream) {
            status = "Not scrobbled: " + reason
            return
        }
        status = ""
        let scrobble = LastFMScrobble(artist: artist, title: title, duration: Int(duration),
                                      timestamp: Int(now().timeIntervalSince1970))
        current = Play(scrobble: scrobble)
        guard let session else { return }
        Task {
            _ = try? await LastFM.call("track.updateNowPlaying", ["artist": artist, "track": title,
                                                                 "duration": String(scrobble.duration), "sk": session], post: true)
        }
    }

    /// Engine status changed: the clock runs only while playing
    public func playbackChanged(playing: Bool) {
        guard var play = current, !play.sent else { return }
        if let since = play.playingSince {
            play.played += now().timeIntervalSince(since)
            play.playingSince = nil
        }
        timer?.cancel()
        if playing { play.playingSince = now() }
        current = play
        guard playing, let limit = Self.threshold(for: TimeInterval(play.scrobble.duration)) else { return }
        // One timer to the moment the track counts: nothing runs in between
        let check = DispatchWorkItem { [weak self] in self?.checkPlayed() }
        timer = check
        DispatchQueue.main.asyncAfter(deadline: .now() + max(limit - play.played, 0), execute: check)
    }

    /// The timer fired (or a test moved the clock): scrobble once the played time reaches the rule
    func checkPlayed() {
        guard var play = current, !play.sent, let since = play.playingSince,
              let limit = Self.threshold(for: TimeInterval(play.scrobble.duration)),
              play.played + now().timeIntervalSince(since) >= limit else { return }
        play.sent = true
        current = play
        persistence.state.lastFMQueue.append(play.scrobble)
        persistence.scheduleSave()
        Task { await flush() }
    }

    /// Sends the waiting scrobbles, 50 at a time. On any failure they stay queued for the next scrobble or launch.
    public func flush() async {
        guard isActive, !isFlushing, let session else { return }
        isFlushing = true
        defer { isFlushing = false }
        while !persistence.state.lastFMQueue.isEmpty {
            let batch = Array(persistence.state.lastFMQueue.prefix(LastFM.batchLimit))
            var params = ["sk": session]
            for (i, item) in batch.enumerated() {
                params["artist[\(i)]"] = item.artist
                params["track[\(i)]"] = item.title
                params["timestamp[\(i)]"] = String(item.timestamp)
                params["duration[\(i)]"] = String(item.duration)
            }
            do {
                _ = try await LastFM.call("track.scrobble", params, post: true)
                persistence.state.lastFMQueue.removeFirst(batch.count)
                persistence.scheduleSave()
                status = ""
            } catch let error as LastFMError where error.code == LastFMError.invalidSession {
                disconnect()
                status = "Last.fm no longer accepts MacAmp: Connect again"
                return
            } catch {
                status = "Not sent yet: \(error.localizedDescription)"
                return
            }
        }
    }

    // MARK: Account

    /// Desktop auth: a token, the Last.fm page in the browser where the user allows MacAmp, then the session
    public func connect() {
        guard LastFM.hasAPIKey, !isConnecting else { return }
        isConnecting = true
        status = "Connecting..."
        Task {
            defer { isConnecting = false }
            do {
                guard let token = try await LastFM.call("auth.getToken")["token"] as? String,
                      let page = URL(string: AppConstants.LastFM.authURL + "?" + LastFM.formEncoded(["api_key": LastFM.apiKey, "token": token]))
                else { throw LastFMError(code: 0, message: "No token from Last.fm") }
                NSWorkspace.shared.open(page)
                status = "Allow MacAmp on the Last.fm page in your browser..."
                let deadline = now().addingTimeInterval(AppConstants.LastFM.authPollLimit)
                while now() < deadline {
                    try await Task.sleep(for: .seconds(AppConstants.LastFM.authPollInterval))
                    guard isConnecting else { return }
                    do {
                        let answer = try await LastFM.call("auth.getSession", ["token": token])
                        guard let session = answer["session"] as? [String: Any], let key = session["key"] as? String,
                              LocalSecret.write(key, for: LastFM.sessionSecretName)
                        else { throw LastFMError(code: 0, message: "No session from Last.fm") }
                        persistence.state.lastFMUser = session["name"] as? String ?? ""
                        persistence.scheduleSave()
                        status = ""
                        objectWillChange.send()
                        await flush()
                        return
                    } catch let error as LastFMError where error.code == LastFMError.tokenNotAuthorized {
                        continue
                    }
                }
                status = "Not allowed in time: Connect again"
            } catch {
                status = "[Error] \(error.localizedDescription)"
            }
        }
    }

    public func disconnect() {
        isConnecting = false
        timer?.cancel()
        current = nil
        LocalSecret.write("", for: LastFM.sessionSecretName)
        persistence.state.lastFMUser = ""
        persistence.scheduleSave()
        status = ""
        objectWillChange.send()
    }

    public func setEnabled(_ enabled: Bool) {
        persistence.state.lastFMEnabled = enabled
        persistence.scheduleSave()
        if !enabled { timer?.cancel(); current = nil }
        objectWillChange.send()
        if enabled { Task { await flush() } }
    }
}
