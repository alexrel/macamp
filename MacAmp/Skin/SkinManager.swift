import Foundation
import CoreGraphics
import Combine

public class SkinManager: ObservableObject {
    public static let shared = SkinManager()
    
    @Published public private(set) var currentSkin: Skin?
    public private(set) var currentSkinURL: URL?
    private var baseSkin: Skin?
    
    public let skinDidChange = PassthroughSubject<Skin, Never>()
    
    /// True if the current skin is the built-in Winamp base skin (base-2.91.wsz)
    public var isBaseSkinActive: Bool {
        return currentSkinURL == nil || currentSkin?.name == "base-2.91"
    }
    
    /// Dedicated directory where installed custom skins are stored: ~/Library/Application Support/MacAmp/Skins
    public var skinsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("MacAmp").appendingPathComponent("Skins")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private init() {
        loadBaseSkin()
    }
    
    private func loadBaseSkin() {
        // Look for base-2.91.wsz or unpacked folder in Bundle or project resources
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: "base-2.91", withExtension: "wsz"),
            Bundle.main.resourceURL?.appendingPathComponent("base-2.91.wsz"),
            Bundle.main.resourceURL?.appendingPathComponent("skin/base-2.91.wsz"),
            URL(fileURLWithPath: "skin/base-2.91.wsz"),
            URL(fileURLWithPath: "skin/base-2.91")
        ]
        
        for url in candidateURLs.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let loaded = SkinLoader.shared.loadSkin(from: url) {
                    self.baseSkin = loaded
                    self.currentSkin = loaded
                    self.currentSkinURL = nil
                    print("SkinManager: Successfully loaded base skin from \(url.path)")
                    return
                }
            }
        }
        
        print("SkinManager: Warning - base skin not found at standard paths.")
    }
    
    /// Returns all user-installed skins in the MacAmp/Skins directory, sorted alphabetically.
    public func installedSkins() -> [URL] {
        let dir = skinsDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        
        let skinExtensions = Set(["wsz", "zip"])
        var result: [URL] = []
        
        for url in files {
            let ext = url.pathExtension.lowercased()
            let name = url.deletingPathExtension().lastPathComponent
            
            // Skip base skin from custom skins list
            if name.lowercased().contains("base-2.91") {
                continue
            }
            
            if skinExtensions.contains(ext) {
                result.append(url)
            } else {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let bmp1 = url.appendingPathComponent("MAIN.BMP")
                    let bmp2 = url.appendingPathComponent("main.bmp")
                    if fm.fileExists(atPath: bmp1.path) || fm.fileExists(atPath: bmp2.path) {
                        result.append(url)
                    } else if let subfiles = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        let hasNestedMain = subfiles.contains { sub in
                            let s1 = sub.appendingPathComponent("MAIN.BMP")
                            let s2 = sub.appendingPathComponent("main.bmp")
                            return fm.fileExists(atPath: s1.path) || fm.fileExists(atPath: s2.path)
                        }
                        if hasNestedMain {
                            result.append(url)
                        }
                    }
                }
            }
        }
        
        return result.sorted {
            $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare($1.deletingPathExtension().lastPathComponent) == .orderedAscending
        }
    }
    
    /// Loads a skin from a .wsz file or directory without copying it.
    @discardableResult
    public func loadSkin(from url: URL) -> Bool {
        guard let skin = SkinLoader.shared.loadSkin(from: url) else {
            print("SkinManager: Failed to load skin from \(url.path)")
            return false
        }
        
        self.currentSkinURL = url
        self.currentSkin = skin
        self.skinDidChange.send(skin)
        return true
    }
    
    /// Installs a skin from any file or folder URL into MacAmp's Skins directory, then loads it.
    @discardableResult
    public func installSkin(from sourceURL: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            print("SkinManager: Source skin file does not exist at \(sourceURL.path)")
            return nil
        }
        
        let dir = skinsDirectory
        let targetURL = dir.appendingPathComponent(sourceURL.lastPathComponent)
        
        // If source is not already inside skinsDirectory, copy it
        if sourceURL.path != targetURL.path {
            if fm.fileExists(atPath: targetURL.path) {
                try? fm.removeItem(at: targetURL)
            }
            do {
                try fm.copyItem(at: sourceURL, to: targetURL)
                print("SkinManager: Successfully installed skin to \(targetURL.path)")
            } catch {
                print("SkinManager: Failed to install skin: \(error)")
                return nil
            }
        }
        
        if loadSkin(from: targetURL) {
            return targetURL
        }
        return nil
    }
    
    /// Deletes an installed skin from the MacAmp/Skins directory.
    /// If the deleted skin was currently active, gracefully reverts to base skin.
    @discardableResult
    public func deleteSkin(at url: URL) -> Bool {
        // Safety guard: Never delete built-in base skin
        if url.lastPathComponent.lowercased().contains("base-2.91") {
            print("SkinManager: Cannot delete built-in base skin")
            return false
        }
        
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return false
        }
        
        do {
            try fm.removeItem(at: url)
            print("SkinManager: Successfully deleted skin file at \(url.path)")
        } catch {
            print("SkinManager: Failed to delete skin: \(error)")
            return false
        }
        
        // If deleted skin was active, revert to base skin
        let skinName = url.deletingPathExtension().lastPathComponent
        if currentSkinURL?.path == url.path || currentSkin?.name == skinName {
            resetToBaseSkin()
        }
        
        return true
    }
    
    /// Reverts to the built-in Winamp base skin.
    public func resetToBaseSkin() {
        self.currentSkinURL = nil
        if let base = baseSkin {
            self.currentSkin = base
            self.skinDidChange.send(base)
        }
        PersistenceManager.shared.state.activeSkinPath = nil
        PersistenceManager.shared.saveSession()
    }
    
    /// Returns the cropped sprite image for the given slice, falling back to base skin if needed.
    public func image(for slice: SpriteSlice) -> CGImage? {
        if let current = currentSkin, let img = current.image(for: slice) {
            return img
        }
        return baseSkin?.image(for: slice)
    }
    
    /// Returns the full sheet CGImage for the given sheet name.
    public func sheet(_ name: String) -> CGImage? {
        let key = name.uppercased()
        if let current = currentSkin, let sheet = current.images[key] {
            return sheet
        }
        return baseSkin?.images[key]
    }
}
