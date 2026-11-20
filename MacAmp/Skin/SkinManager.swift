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
        return currentSkinURL == nil || currentSkin?.name == AppConstants.Skins.baseName
    }

    /// The built-in HD redraw of the base skin (in the app; from the repository when tests run)
    public let baseHDSkinURL: URL? = [
        Bundle.main.url(forResource: AppConstants.Skins.baseHDName, withExtension: AppConstants.Skins.hdExtension),
        URL(fileURLWithPath: "MacAmp/Resources/\(AppConstants.Skins.baseHDName).\(AppConstants.Skins.hdExtension)")
    ].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }

    public var isBaseHDSkinActive: Bool {
        currentSkinURL != nil && currentSkinURL?.standardizedFileURL == baseHDSkinURL?.standardizedFileURL
    }

    /// The skin a saved path points to. The built-in HD skin lives inside the app, whose path changes when it moves
    /// (an update, /Applications): its file name is enough to find it again.
    public func savedSkinURL(_ path: String) -> URL? {
        if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        guard let builtIn = baseHDSkinURL, URL(fileURLWithPath: path).lastPathComponent == builtIn.lastPathComponent else { return nil }
        return builtIn
    }

    /// The two built-in skins, never listed among the installed ones or deleted
    static func isBuiltIn(_ url: URL) -> Bool {
        [AppConstants.Skins.baseName, AppConstants.Skins.baseHDName].contains(url.deletingPathExtension().lastPathComponent.lowercased())
    }
    
    /// Where skins are listed and installed: Preferences ▸ Skins ▸ "Set skins directory...", by default
    /// ~/Library/Application Support/MacAmp/Skins
    public var skinsDirectory: URL {
        if let custom = PersistenceManager.shared.state.skinsDirectoryPath, FileManager.default.fileExists(atPath: custom) {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
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
        let base = AppConstants.Skins.baseName
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: base, withExtension: "wsz"),
            Bundle.main.resourceURL?.appendingPathComponent("\(base).wsz"),
            Bundle.main.resourceURL?.appendingPathComponent("skin/\(base).wsz"),
            URL(fileURLWithPath: "skin/\(base).wsz"),
            URL(fileURLWithPath: "skin/\(base)")
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
    
    /// A skin's name in the lists and menus: the file name, with " (HD)" for an .msz HD skin, which often shares its
    /// name with the classic .wsz it was drawn from, unless the name already says HD ("… Remaster HD")
    public static func listName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard url.pathExtension.lowercased() == AppConstants.Skins.hdExtension,
              name.range(of: #"\bHD\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { return name }
        return name + " (HD)"
    }

    /// Returns all user-installed skins in the MacAmp/Skins directory, sorted alphabetically.
    public func installedSkins() -> [URL] {
        let dir = skinsDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        
        let skinExtensions = AppConstants.Audio.skinExtensions
        var result: [URL] = []
        
        for url in files {
            let ext = url.pathExtension.lowercased()
            // The built-in skins have their own entries at the top of the list
            if SkinManager.isBuiltIn(url) {
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
    
    /// Loads a skin archive or directory without copying it.
    @discardableResult
    public func loadSkin(from url: URL) -> Bool {
        guard let skin = SkinLoader.shared.loadSkin(from: url) else {
            print("SkinManager: Failed to load skin from \(url.path)")
            return false
        }
        
        apply(skin, from: url)
        return true
    }

    private func apply(_ skin: Skin, from url: URL) {
        self.currentSkinURL = url
        self.currentSkin = skin
        self.skinDidChange.send(skin)
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
        let hdSkin: Skin?
        if sourceURL.pathExtension.lowercased() == AppConstants.Skins.hdExtension {
            guard let skin = SkinLoader.shared.loadSkin(from: sourceURL) else { return nil }
            hdSkin = skin
        } else {
            hdSkin = nil
        }
        
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
        
        if let hdSkin {
            apply(hdSkin, from: targetURL)
            return targetURL
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
        if SkinManager.isBuiltIn(url) {
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
        sheetWithScale(name)?.image
    }

    func sheetWithScale(_ name: String) -> (image: CGImage, scale: Int)? {
        let key = name.uppercased()
        if let current = currentSkin, let sheet = current.images[key] {
            return (sheet, current.pixelScale)
        }
        guard let base = baseSkin, let sheet = base.images[key] else { return nil }
        return (sheet, base.pixelScale)
    }

    /// The text Winamp shows under the skin list: the skin author's own .txt (readme), not its config files
    nonisolated public static func skinDescription(of url: URL?) -> String {
        guard let url else { return "MacAmp base skin v\(AppConstants.App.version) (Winamp base skin v2.91)" }
        let configFiles: Set<String> = ["pledit.txt", "viscolor.txt", "region.txt", "genex.txt"]
        var data = Data()
        if url.hasDirectoryPath {
            let texts = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "txt" && !configFiles.contains($0.lastPathComponent.lowercased()) }
            data = texts.first.flatMap { try? Data(contentsOf: $0) } ?? Data()
        } else {
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            // -C: names match without case (README.TXT, Readme.txt...)
            unzip.arguments = ["-C", "-p", url.path, "*.txt", "-x"] + configFiles.map { "*" + $0 }
            let pipe = Pipe()
            unzip.standardOutput = pipe
            unzip.standardError = FileHandle.nullDevice
            if (try? unzip.run()) != nil {
                data = pipe.fileHandleForReading.readDataToEndOfFile()
                unzip.waitUntilExit()
            }
        }
        // Skin readmes are Windows text: UTF-8 if it decodes, else Windows-1251/1252 via the playlist's repair
        let text = String(data: data, encoding: .utf8) ?? TextEncoding.repairCyrillic(String(data: data, encoding: .isoLatin1) ?? "")
        let trimmed = String(text.prefix(4000)).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? url.deletingPathExtension().lastPathComponent : trimmed
    }
}

