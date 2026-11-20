import Foundation
import CryptoKit
import IOKit

/// Small secrets (the Subsonic password, the Last.fm session) in the app's defaults, encrypted for this Mac.
/// Not the Keychain: an ad-hoc signed app changes its signature after every update or document icon change, and the
/// Keychain then asks the user again. shortcut: the key is this Mac's hardware UUID, so a stored value is useless
/// elsewhere but readable by anything running as this user; upgrade if MacAmp ever ships cert-signed.
enum LocalSecret {
    private static var key: SymmetricKey {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String ?? ""
        return SymmetricKey(data: SHA256.hash(data: Data((uuid + "MacAmp").utf8)))
    }

    static func read(_ name: String) -> String? {
        guard let sealed = UserDefaults.standard.data(forKey: name),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves `value` under `name`; an empty one removes it
    @discardableResult
    static func write(_ value: String, for name: String) -> Bool {
        guard !value.isEmpty else { UserDefaults.standard.removeObject(forKey: name); return true }
        guard let sealed = try? AES.GCM.seal(Data(value.utf8), using: key).combined else { return false }
        UserDefaults.standard.set(sealed, forKey: name)
        return true
    }
}
