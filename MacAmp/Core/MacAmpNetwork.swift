import Foundation

/// Network settings from Preferences ▸ Setup (Winamp "Internet settings"), applied to every
/// connection MacAmp opens itself: radio streams and remote playlists.
public enum MacAmpNetwork {
    /// "No Internet connection available": don't open network streams at all
    public static var isOffline: Bool { PersistenceManager.shared.state.networkOffline }

    /// Parses Winamp's "Server:Port" proxy field; nil for blank or malformed input.
    public static func parseProxy(_ text: String) -> (host: String, port: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withoutScheme = trimmed.replacingOccurrences(of: "http://", with: "")
        let parts = withoutScheme.split(separator: ":", maxSplits: 1).map(String.init)
        guard let host = parts.first, !host.isEmpty else { return nil }
        let port = parts.count == 2 ? Int(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))) : 80
        guard let port, (1...65535).contains(port) else { return nil }
        return (host, port)
    }

    /// Session configuration with the user's HTTP proxy (or the system settings when blank).
    public static func configuration(from base: URLSessionConfiguration = .default) -> URLSessionConfiguration {
        let config = base
        if let proxy = parseProxy(PersistenceManager.shared.state.httpProxy) {
            config.connectionProxyDictionary = [
                "HTTPEnable": 1,
                "HTTPProxy": proxy.host,
                "HTTPPort": proxy.port,
                "HTTPSEnable": 1,
                "HTTPSProxy": proxy.host,
                "HTTPSPort": proxy.port
            ]
        }
        return config
    }

    /// Shared session for short requests (playlist downloads), rebuilt when the proxy changes.
    public static var session: URLSession {
        let proxy = PersistenceManager.shared.state.httpProxy
        if proxy != cachedProxy || cachedSession == nil {
            cachedSession = URLSession(configuration: configuration())
            cachedProxy = proxy
        }
        return cachedSession!
    }
    private static var cachedSession: URLSession?
    private static var cachedProxy: String?

    public static let offlineError = URLError(.notConnectedToInternet, userInfo: [
        NSLocalizedDescriptionKey: "Internet access is turned off in Preferences ▸ Setup"
    ])
}
