import Foundation
import CoreGraphics
import AppKit

public class TimeDisplayView: WinampControlView {
    public var currentTime: TimeInterval = 0 {
        didSet { needsDisplay = true }
    }
    public var totalDuration: TimeInterval = 0 {
        didSet { needsDisplay = true }
    }
    public var mode: TimeDisplayMode = .elapsed {
        didSet { needsDisplay = true }
    }
    public var status: PlayerStatus = .stopped {
        didSet {
            updateBlinkTimer()
            needsDisplay = true
        }
    }
    
    public var onToggleMode: (() -> Void)?
    
    private var isBlinkVisible: Bool = true
    private var blinkTimer: Timer?
    
    public init() {
        super.init(frame: NSRect(x: 39, y: 26, width: 59, height: 13))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        
        if status == .paused {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.isBlinkVisible.toggle()
                self.needsDisplay = true
            }
        } else {
            isBlinkVisible = true
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard status != .stopped else { return }
        guard isBlinkVisible else { return }
        
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
        
        let m1 = (minutes / 10) % 10
        let m2 = minutes % 10
        let s1 = (seconds / 10) % 10
        let s2 = seconds % 10
        
        // Minus sign at x: 0, y: 6
        if isNegative {
            if let minusImg = SkinManager.shared.image(for: SpriteCatalog.minusSign) {
                context.drawSkinImage(minusImg, in: NSRect(x: 0, y: 6, width: 5, height: 1))
            }
        }
        
        // Digit 1 (Minute tens) at x: 9
        if let d1Img = SkinManager.shared.image(for: SpriteCatalog.digit(m1)) {
            context.drawSkinImage(d1Img, in: NSRect(x: 9, y: 0, width: 9, height: 13))
        }
        
        // Digit 2 (Minute units) at x: 21
        if let d2Img = SkinManager.shared.image(for: SpriteCatalog.digit(m2)) {
            context.drawSkinImage(d2Img, in: NSRect(x: 21, y: 0, width: 9, height: 13))
        }
        
        // Digit 3 (Second tens) at x: 39
        if let d3Img = SkinManager.shared.image(for: SpriteCatalog.digit(s1)) {
            context.drawSkinImage(d3Img, in: NSRect(x: 39, y: 0, width: 9, height: 13))
        }
        
        // Digit 4 (Second units) at x: 51
        if let d4Img = SkinManager.shared.image(for: SpriteCatalog.digit(s2)) {
            context.drawSkinImage(d4Img, in: NSRect(x: 51, y: 0, width: 9, height: 13))
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            onToggleMode?()
        }
    }
}
