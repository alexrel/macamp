import Foundation
import CoreGraphics
import AppKit

/// Digital time display rendering minutes and seconds using NUMBERS.BMP sprites (normal mode)
/// or TEXT.BMP font digits (shade mode).
///
/// Winamp 2.x Geometry:
/// - In normal mode (frame 59x13):
///   - Minus sign: at x: 0, y: 6 (5x1 px)
///   - Minute tens (M1): at x: 9 (9x13 px)
///   - Minute ones (M2): at x: 21 (9x13 px)
///   - Green colon separator: permanently baked into MAIN.BMP between x: 30 and 38
///   - Second tens (S1): at x: 39 (9x13 px)
///   - Second ones (S2): at x: 51 (9x13 px)
/// - In pause mode, PlayerCoordinator drives synchronized blinking (isBlinkVisible toggles every 500ms).
///   When blink is off, digits disappear while the green colon remains steadily visible.
public class TimeDisplayView: WinampControlView {
    public var currentTime: TimeInterval = 0 {
        didSet {
            // Updated 10x/s while playing; only the change of a displayed second needs a redraw
            if displayedSeconds(for: oldValue) != displayedSeconds(for: currentTime) {
                needsDisplay = true
            }
        }
    }
    
    private func displayedSeconds(for time: TimeInterval) -> Int {
        if mode == .remaining && totalDuration > 0 {
            return -max(0, Int(totalDuration - time))
        }
        return max(0, Int(time))
    }
    public var totalDuration: TimeInterval = 0 {
        didSet { needsDisplay = true }
    }
    public var mode: TimeDisplayMode = .elapsed {
        didSet { needsDisplay = true }
    }
    public var status: PlayerStatus = .stopped {
        didSet { needsDisplay = true }
    }
    
    public var onToggleMode: (() -> Void)?
    
    /// Driven synchronously by PlayerCoordinator across Main and Playlist windows
    public var isBlinkVisible: Bool = true {
        didSet { needsDisplay = true }
    }
    
    public init() {
        super.init(frame: AppConstants.MainWindow.Layout.timeDisplay)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard status != .stopped else { return }
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        // Calculate display time
        let displaySeconds: Int
        let isNegative: Bool
        if mode == .remaining && totalDuration > 0 {
            let remaining = max(0, Int(totalDuration - currentTime))
            displaySeconds = remaining
            isNegative = true
        } else {
            displaySeconds = max(0, Int(currentTime))
            isNegative = false
        }
        
        let minutes = displaySeconds / 60
        let seconds = displaySeconds % 60
        
        // In shade mode (height <= 8), draw mini text font without painting over background colon
        if bounds.height <= 8 {
            BitmapFont.drawMiniTime(
                minutes: minutes,
                seconds: seconds,
                isNegative: isNegative,
                status: status,
                isBlinkVisible: isBlinkVisible,
                in: context,
                at: .zero
            )
            return
        }
        
        // In large display mode, when paused and blinking off, do not draw digits (let background colon show)
        guard isBlinkVisible else { return }
        
        let m1 = (minutes / 10) % 10
        let m2 = minutes % 10
        let s1 = (seconds / 10) % 10
        let s2 = seconds % 10
        
        let dW = AppConstants.TimeDisplay.digitWidth
        let dH = AppConstants.TimeDisplay.digitHeight
        
        // Minus sign
        if isNegative {
            if let minusImg = SkinManager.shared.image(for: SpriteCatalog.minusSign) {
                context.drawSkinImage(minusImg, in: AppConstants.TimeDisplay.minusRect)
            }
        }
        
        // Digit 1 (Minute tens)
        if let d1Img = SkinManager.shared.image(for: SpriteCatalog.digit(m1)) {
            context.drawSkinImage(d1Img, in: NSRect(x: AppConstants.TimeDisplay.minuteTensX, y: 0, width: dW, height: dH))
        }
        
        // Digit 2 (Minute units)
        if let d2Img = SkinManager.shared.image(for: SpriteCatalog.digit(m2)) {
            context.drawSkinImage(d2Img, in: NSRect(x: AppConstants.TimeDisplay.minuteOnesX, y: 0, width: dW, height: dH))
        }
        
        // Digit 3 (Second tens)
        if let d3Img = SkinManager.shared.image(for: SpriteCatalog.digit(s1)) {
            context.drawSkinImage(d3Img, in: NSRect(x: AppConstants.TimeDisplay.secondTensX, y: 0, width: dW, height: dH))
        }
        
        // Digit 4 (Second units)
        if let d4Img = SkinManager.shared.image(for: SpriteCatalog.digit(s2)) {
            context.drawSkinImage(d4Img, in: NSRect(x: AppConstants.TimeDisplay.secondOnesX, y: 0, width: dW, height: dH))
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        onToggleMode?()
    }
    
    public override func mouseUp(with event: NSEvent) {
    }
}
