import Foundation
import CoreGraphics
import AppKit

/// Scrolling text display for current track title and system messages.
/// Renders using TEXT.BMP (5x6 bitmap font).
/// When text exceeds marquee width (152px), it pauses for 2.5s at start,
/// then smoothly scrolls at 2px per tick (0.12s interval) with a looping trailing copy.
public class MarqueeView: WinampControlView {
    /// Persistent song title or default text.
    public var text: String = "MACAMP 2.91 (CLASSIC)" {
        didSet {
            if temporaryMessage == nil {
                currentDisplayText = text
                resetScroll()
                needsDisplay = true
            }
        }
    }
    
    /// Currently displayed text in ticker (temporary status message or song title).
    public private(set) var currentDisplayText: String = "MACAMP 2.91 (CLASSIC)"
    
    private var temporaryMessage: String?
    private var temporaryTimer: Timer?
    private var scrollOffset: CGFloat = 0.0
    private var scrollTimer: Timer?
    private var isPausedAtStart = true
    private var pauseTicksRemaining: Int = Int(AppConstants.Marquee.pauseDuration / AppConstants.Marquee.scrollInterval)
    
    public init() {
        super.init(frame: AppConstants.MainWindow.Layout.marquee)
        startScrollTimer()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Shows a temporary status message (e.g. Volume, Balance, EQ, Seek) for `duration` seconds,
    /// then automatically reverts back to displaying the current track title.
    public func showTemporaryMessage(_ message: String, duration: TimeInterval = 1.5) {
        temporaryMessage = message
        currentDisplayText = message
        resetScroll()
        needsDisplay = true
        
        temporaryTimer?.invalidate()
        temporaryTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.temporaryMessage = nil
            self.currentDisplayText = self.text
            self.resetScroll()
            self.needsDisplay = true
        }
    }
    
    public func resetScroll() {
        scrollOffset = 0.0
        isPausedAtStart = true
        pauseTicksRemaining = Int(AppConstants.Marquee.pauseDuration / AppConstants.Marquee.scrollInterval)
    }
    
    private func startScrollTimer() {
        scrollTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.Marquee.scrollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
        }
    }
    
    private func currentTextWidth() -> CGFloat {
        let state = PersistenceManager.shared.state
        if state.marqueeFontMode == .desktop {
            let font = NSFont(name: state.desktopFontFamily, size: CGFloat(state.desktopFontSize))
                ?? NSFont.monospacedSystemFont(ofSize: CGFloat(state.desktopFontSize), weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            return NSString(string: currentDisplayText).size(withAttributes: attrs).width
        } else {
            return CGFloat(currentDisplayText.count) * AppConstants.Font.charWidth
        }
    }
    
    private func tick() {
        guard PersistenceManager.shared.state.isMarqueeScrollEnabled else {
            scrollOffset = 0
            needsDisplay = true
            return
        }
        
        let totalTextWidth = currentTextWidth()
        guard totalTextWidth > bounds.width else {
            scrollOffset = 0
            needsDisplay = true
            return
        }
        
        if pauseTicksRemaining > 0 {
            pauseTicksRemaining -= 1
            return
        }
        
        scrollOffset += 2.0 // Classic Winamp 2px step
        
        if scrollOffset > totalTextWidth + 24.0 {
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
        
        // 1. Fill entire marquee background with authentic space glyphs from TEXT.BMP.
        // In Winamp/Webamp, the marquee always covers the background graphics/text on MAIN.BMP.
        BitmapFont.drawSpaceBackground(in: context, width: bounds.width, height: bounds.height)
        
        let state = PersistenceManager.shared.state
        let totalTextWidth = currentTextWidth()
        
        if state.marqueeFontMode == .desktop {
            let font = NSFont(name: state.desktopFontFamily, size: CGFloat(state.desktopFontSize))
                ?? NSFont.monospacedSystemFont(ofSize: CGFloat(state.desktopFontSize), weight: .medium)
            
            // Text color from current skin playlist style, or classic fluorescent green
            let textColor = SkinManager.shared.currentSkin?.playlistStyle.normalColor
                ?? NSColor(red: 0.0, green: 0.9, blue: 0.0, alpha: 1.0)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let str = NSString(string: currentDisplayText)
            let textSize = str.size(withAttributes: attrs)
            let yPos = max(0, (bounds.height - textSize.height) / 2)
            
            // Draw primary desktop text
            str.draw(at: CGPoint(x: -scrollOffset, y: yPos), withAttributes: attrs)
            
            // If scrolling, draw trailing looped copy
            if scrollOffset > 0 {
                let loopedX = totalTextWidth + 24.0 - scrollOffset
                str.draw(at: CGPoint(x: loopedX, y: yPos), withAttributes: attrs)
            }
        } else {
            // 2. Draw primary text using authentic BitmapFont
            BitmapFont.draw(string: currentDisplayText, in: context, at: CGPoint(x: -scrollOffset, y: 0))
            
            // 3. If scrolling, loop text
            if scrollOffset > 0 {
                let loopedX = totalTextWidth + 20.0 - scrollOffset
                BitmapFont.draw(string: currentDisplayText, in: context, at: CGPoint(x: loopedX, y: 0))
            }
        }
    }
    
    deinit {
        scrollTimer?.invalidate()
        temporaryTimer?.invalidate()
    }
}
