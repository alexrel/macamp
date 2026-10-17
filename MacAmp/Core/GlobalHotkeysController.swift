import Cocoa
import ApplicationServices

/// Manages background global hotkeys allowing control of MacAmp from any application.
/// Uses NSEvent global monitor for classic Winamp Ctrl+Alt combinations,
/// and provides accessibility permission detection and prompts.
public final class GlobalHotkeysController: ObservableObject {
    public static let shared = GlobalHotkeysController()
    
    @Published public var isEnabled: Bool {
        didSet {
            PersistenceManager.shared.state.isGlobalHotkeysEnabled = isEnabled
            PersistenceManager.shared.saveSession()
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    @Published public var isAccessibilityTrusted: Bool = false
    
    private var globalMonitor: Any?
    
    private init() {
        self.isEnabled = PersistenceManager.shared.state.isGlobalHotkeysEnabled
        self.isAccessibilityTrusted = AXIsProcessTrusted()
    }
    
    deinit {
        stopMonitoring()
    }
    
    public func setup() {
        checkAccessibilityPermission()
        if isEnabled {
            startMonitoring()
        }
    }
    
    @discardableResult
    public func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.isAccessibilityTrusted = trusted
        }
        return trusted
    }
    
    public func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            self.isAccessibilityTrusted = trusted
        }
    }
    
    public func startMonitoring() {
        guard globalMonitor == nil else { return }
        
        // NSEvent global monitor intercepts key events when MacAmp is in the background
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
    }
    
    public func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
    
    private func handleGlobalKeyEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCtrlAlt = flags.contains(.control) && flags.contains(.option)
        
        guard isCtrlAlt else { return }
        
        DispatchQueue.main.async {
            let coord = PlayerCoordinator.shared
            
            switch event.keyCode {
            case 7: // X -> Play
                coord.handlePlay()
            case 8, 49: // C or Space -> Toggle Play/Pause
                coord.handlePlayPause()
            case 9: // V -> Stop
                coord.handleStop()
            case 6, 123: // Z or Left Arrow -> Previous Track
                coord.handlePrev()
            case 11, 124: // B or Right Arrow -> Next Track
                coord.handleNext()
            case 126: // Up Arrow -> Volume Up
                coord.increaseVolume(by: 0.05)
            case 125: // Down Arrow -> Volume Down
                coord.decreaseVolume(by: 0.05)
            case 46: // M -> Toggle Mute
                coord.toggleMute()
            default:
                break
            }
        }
    }
}
