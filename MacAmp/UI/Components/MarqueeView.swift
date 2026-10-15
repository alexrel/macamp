import Foundation
import CoreGraphics
import AppKit

public class MarqueeView: WinampControlView {
    public var text: String = "WINAMP 2.95 (CLASSIC)" {
        didSet {
            resetScroll()
            needsDisplay = true
        }
    }
    
    private var scrollOffset: CGFloat = 0.0
    private var scrollTimer: Timer?
    private var isPausedAtStart = true
    
    public init() {
        super.init(frame: NSRect(x: 111, y: 24, width: AppConstants.Marquee.width, height: AppConstants.Marquee.height))
        startScrollTimer()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func resetScroll() {
        scrollOffset = 0.0
        isPausedAtStart = true
    }
    
    private func startScrollTimer() {
        scrollTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.Marquee.scrollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
        }
    }
    
    private var pauseTicksRemaining: Int = Int(AppConstants.Marquee.pauseDuration / AppConstants.Marquee.scrollInterval)
    
    private func tick() {
        let totalTextWidth = CGFloat(text.count) * AppConstants.Font.charWidth
        guard totalTextWidth > bounds.width else {
            scrollOffset = 0
            needsDisplay = true
            return
        }
        
        if pauseTicksRemaining > 0 {
            pauseTicksRemaining -= 1
            return
        }
        
        scrollOffset += 2.0 // Scroll 2 pixels per tick
        
        if scrollOffset > totalTextWidth + 20.0 {
            scrollOffset = 0.0
            pauseTicksRemaining = Int(AppConstants.Marquee.pauseDuration / AppConstants.Marquee.scrollInterval)
        }
        
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        // Clip to marquee bounds
        context.clip(to: bounds)
        
        // Draw primary text
        BitmapFont.draw(string: text, in: context, at: CGPoint(x: -scrollOffset, y: 0))
        
        // If scrolling, loop text
        let totalTextWidth = CGFloat(text.count) * AppConstants.Font.charWidth
        if scrollOffset > 0 {
            let loopedX = totalTextWidth + 20.0 - scrollOffset
            BitmapFont.draw(string: text, in: context, at: CGPoint(x: loopedX, y: 0))
        }
    }
    
    deinit {
        scrollTimer?.invalidate()
    }
}
