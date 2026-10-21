import Foundation
import CoreGraphics
import AppKit

/// Scrolling text display for current track title and system messages.
/// Renders using TEXT.BMP (5x6 bitmap font).
/// When text exceeds marquee width (152px), it pauses for 2.5s at start,
/// then smoothly scrolls at 2px per tick (0.12s interval) with a looping trailing copy.
///
/// The scroll timer only exists while it is needed: text wider than the marquee, scrolling enabled,
/// and `isScrollingActive` (playing and window visible). Otherwise the marquee costs no CPU.
public class MarqueeView: WinampControlView {
    /// Persistent song title or default text.
    public var text: String = "MACAMP \(AppConstants.App.version)" {
        didSet {
            if temporaryMessage == nil {
                currentDisplayText = text
                resetScroll()
                needsDisplay = true
            }
        }
    }
    
    /// Currently displayed text in ticker (temporary status message or song title).
    public private(set) var currentDisplayText: String = "MACAMP \(AppConstants.App.version)"
    
    /// Set by PlayerCoordinator: false while paused/stopped or when the window is hidden/minimized.
    public var isScrollingActive: Bool = true {
        didSet { if oldValue != isScrollingActive { updateScrollTimer() } }
    }
    
    /// Text width cache, keyed on everything the width depends on
    private var cachedWidthKey: String?
    private var cachedWidth: CGFloat = 0
    
    private var temporaryMessage: String?
    private var temporaryTimer: Timer?
    private var scrollOffset: CGFloat = 0.0
    private var scrollTimer: Timer?
    private var isPausedAtStart = true
    private var pauseTicksRemaining: Int = Int(AppConstants.Marquee.pauseDuration / AppConstants.Marquee.scrollInterval)
    
    public init() {
        super.init(frame: MarqueeView.preferredFrame)
        updateScrollTimer()
    }
    
    /// Bitmap font: the 6 px text row. TrueType: the taller LCD box, so letters aren't cut.
    public static var preferredFrame: NSRect {
        PersistenceManager.shared.state.marqueeFontMode == .desktop
            ? AppConstants.MainWindow.Layout.marqueeTrueType
            : AppConstants.MainWindow.Layout.marquee
    }
    
    /// Call after title font preferences change.
    public func fontSettingsChanged() {
        frame = MarqueeView.preferredFrame
        cachedWidthKey = nil
        needsDisplay = true
        updateScrollTimer()
    }
    
    /// The chosen TrueType font, shrunk if needed so whole letters (ascender to descender) fit the LCD.
    func trueTypeFont() -> NSFont {
        let state = PersistenceManager.shared.state
        var size = CGFloat(state.desktopFontSize)
        func make(_ size: CGFloat) -> NSFont {
            NSFont(name: state.desktopFontFamily, size: size) ?? NSFont.systemFont(ofSize: size)
        }
        var font = make(size)
        while font.ascender - font.descender > bounds.height - 1, size > 5 {
            size -= 0.5
            font = make(size)
        }
        return font
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
            self.temporaryTimer = nil
            self.currentDisplayText = self.text
            self.resetScroll()
            self.needsDisplay = true
        }
    }
    
    public func resetScroll() {
        scrollOffset = 0.0
        isPausedAtStart = true
        pauseTicksRemaining = Int(AppConstants.Marquee.pauseDuration / AppConstants.Marquee.scrollInterval)
        updateScrollTimer()
    }
    
    /// Re-evaluates whether the scroll timer should run (call after text, font or preference changes).
    public func updateScrollTimer() {
        let needsScrolling = isScrollingActive
            && PersistenceManager.shared.state.isMarqueeScrollEnabled
            && currentTextWidth() > bounds.width
        if needsScrolling {
            guard scrollTimer == nil else { return }
            let timer = Timer(timeInterval: AppConstants.Marquee.scrollInterval, repeats: true) { [weak self] _ in
                self?.tick()
            }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            scrollTimer = timer
        } else {
            scrollTimer?.invalidate()
            scrollTimer = nil
            if scrollOffset != 0 && !isScrollingActive {
                // Frozen mid-scroll looks broken; show the start of the text while idle
                scrollOffset = 0
                needsDisplay = true
            }
        }
    }
    
    public var isScrollTimerRunning: Bool { scrollTimer != nil }
    
    /// Pixel width of the current text; measured once per text/font change instead of on every tick.
    private func currentTextWidth() -> CGFloat {
        let state = PersistenceManager.shared.state
        guard state.marqueeFontMode == .desktop else {
            return CGFloat(currentDisplayText.count) * AppConstants.Font.charWidth
        }
        let key = "\(state.desktopFontFamily)|\(state.desktopFontSize)|\(bounds.height)|\(currentDisplayText)"
        if key == cachedWidthKey { return cachedWidth }
        let font = trueTypeFont()
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        cachedWidth = NSString(string: currentDisplayText).size(withAttributes: attrs).width
        cachedWidthKey = key
        return cachedWidth
    }
    
    private func tick() {
        let totalTextWidth = currentTextWidth()
        guard PersistenceManager.shared.state.isMarqueeScrollEnabled, totalTextWidth > bounds.width else {
            // Text now fits (or scrolling was disabled in preferences): stop ticking
            scrollOffset = 0
            needsDisplay = true
            updateScrollTimer()
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
            let font = trueTypeFont()
            
            // Text color from current skin playlist style, or classic fluorescent green
            let textColor = SkinManager.shared.currentSkin?.playlistStyle.normalColor
                ?? NSColor(red: 0.0, green: 0.9, blue: 0.0, alpha: 1.0)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let str = NSString(string: currentDisplayText)
            // Center the glyph box (ascender..descender). draw(at:) positions the whole line box, which
            // includes the font's leading above the baseline, so take that extra space back out.
            let glyphHeight = font.ascender - font.descender
            let lineHeight = str.size(withAttributes: attrs).height
            let yPos = ((bounds.height - glyphHeight) / 2 - (lineHeight - glyphHeight)).rounded()
            
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
