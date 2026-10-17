import Cocoa
import CoreGraphics

/// Visualizer presets available in Retro Visualizer Studio
public enum StudioVisualizerPreset: Int, CaseIterable {
    case fireSpectrum = 0
    case phosphorOscilloscope = 1
    case neonCyber = 2
    case matrixRain = 3
    case solarOrb = 4
    
    public var title: String {
        switch self {
        case .fireSpectrum: return "Fire Spectrum & Peak Glow"
        case .phosphorOscilloscope: return "Retro Phosphor CRT Oscilloscope"
        case .neonCyber: return "Neon Cyber City Spectrum"
        case .matrixRain: return "Matrix Digital Rain"
        case .solarOrb: return "Solar Radial Orb"
        }
    }
}

/// A high-performance 60 FPS retro visualizer canvas with multiple classic AVS-inspired modes,
/// CRT phosphor glow, floor reflections, particle dynamics, and an auto-fading HUD.
public final class RetroVisualizerView: NSView {
    
    // MARK: - Properties
    public var currentPreset: StudioVisualizerPreset = .fireSpectrum {
        didSet {
            triggerHUD()
            needsDisplay = true
        }
    }
    
    // Audio Data
    public var spectrum: [Float] = Array(repeating: 0.0, count: 64)
    public var waveform: [Float] = Array(repeating: 0.0, count: 128)
    
    // Peak tracking
    private var peakHeights: [Float] = Array(repeating: 0.0, count: 64)
    private var peakVelocity: [Float] = Array(repeating: 0.0, count: 64)
    
    // Display link / Animation Timer
    private var displayTimer: Timer?
    private var lastFrameTime: TimeInterval = Date().timeIntervalSince1970
    private var fpsCounter: Int = 0
    private var currentFPS: Int = 60
    private var fpsTimer: TimeInterval = 0
    
    // Matrix Rain State
    private struct MatrixDrop {
        var x: CGFloat
        var y: CGFloat
        var speed: CGFloat
        var chars: [Character]
    }
    private var matrixDrops: [MatrixDrop] = []
    
    // Solar Orb Particles
    private struct SolarParticle {
        var angle: CGFloat
        var distance: CGFloat
        var speed: CGFloat
        var size: CGFloat
        var alpha: CGFloat
    }
    private var solarParticles: [SolarParticle] = []
    
    // HUD overlay state
    private var hudAlpha: CGFloat = 1.0
    private var lastUserActivity: TimeInterval = Date().timeIntervalSince1970
    
    // Actions
    public var onExit: (() -> Void)?
    public var onToggleFullScreen: (() -> Void)?
    
    // MARK: - Lifecycle
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setupTrackingArea()
        initMatrixDrops()
        initSolarParticles()
        startAnimation()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        displayTimer?.invalidate()
    }
    
    public override var acceptsFirstResponder: Bool { true }
    
    private func setupTrackingArea() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
    
    public func startAnimation() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderTick()
        }
    }
    
    public func stopAnimation() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
    
    // MARK: - Input & Hotkeys
    public override func mouseMoved(with event: NSEvent) {
        triggerHUD()
    }
    
    public override func mouseDown(with event: NSEvent) {
        triggerHUD()
        cyclePreset()
    }
    
    public override func keyDown(with event: NSEvent) {
        triggerHUD()
        
        switch event.keyCode {
        case 53: // Esc -> Exit
            onExit?()
        case 3: // 'F' -> Toggle Fullscreen
            onToggleFullScreen?()
        case 49: // Space -> Next Preset
            cyclePreset()
        case 8: // 'C' -> Toggle Play / Pause
            PlayerCoordinator.shared.handlePlayPause()
        case 123: // Left Arrow -> Prev Track
            PlayerCoordinator.shared.handlePrev()
        case 124: // Right Arrow -> Next Track
            PlayerCoordinator.shared.handleNext()
        case 126: // Up Arrow -> Volume Up
            PlayerCoordinator.shared.increaseVolume()
        case 125: // Down Arrow -> Volume Down
            PlayerCoordinator.shared.decreaseVolume()
        default:
            super.keyDown(with: event)
        }
    }
    
    public func cyclePreset() {
        let nextRaw = (currentPreset.rawValue + 1) % StudioVisualizerPreset.allCases.count
        currentPreset = StudioVisualizerPreset(rawValue: nextRaw) ?? .fireSpectrum
    }
    
    private func triggerHUD() {
        lastUserActivity = Date().timeIntervalSince1970
        hudAlpha = 1.0
        needsDisplay = true
    }
    
    // MARK: - Update Tick
    private func renderTick() {
        let now = Date().timeIntervalSince1970
        let delta = now - lastFrameTime
        lastFrameTime = now
        
        // FPS calculation
        fpsCounter += 1
        fpsTimer += delta
        if fpsTimer >= 1.0 {
            currentFPS = fpsCounter
            fpsCounter = 0
            fpsTimer = 0
        }
        
        // HUD fade out after 3.5 seconds
        let idleTime = now - lastUserActivity
        if idleTime > 3.0 {
            let fade = CGFloat(max(0.0, 1.0 - (idleTime - 3.0) * 1.5))
            hudAlpha = fade
        }
        
        // Update peak physics
        for i in 0..<min(spectrum.count, peakHeights.count) {
            let val = spectrum[i]
            if val >= peakHeights[i] {
                peakHeights[i] = val
                peakVelocity[i] = 0.0
            } else {
                peakVelocity[i] += 0.003 // Gravity
                peakHeights[i] = max(0.0, peakHeights[i] - peakVelocity[i])
            }
        }
        
        // Update matrix rain
        let h = bounds.height
        for i in 0..<matrixDrops.count {
            matrixDrops[i].y -= matrixDrops[i].speed
            if matrixDrops[i].y < -200 {
                matrixDrops[i].y = h + CGFloat.random(in: 20...100)
                matrixDrops[i].speed = CGFloat.random(in: 4...12)
            }
        }
        
        // Update solar orb particles
        for i in 0..<solarParticles.count {
            solarParticles[i].angle += solarParticles[i].speed * 0.015
        }
        
        needsDisplay = true
    }
    
    // MARK: - Drawing Engine
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height
        
        // Background
        context.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1.0))
        context.fill(bounds)
        
        // Render Active Preset
        switch currentPreset {
        case .fireSpectrum:
            drawFireSpectrum(in: context, width: w, height: h)
        case .phosphorOscilloscope:
            drawPhosphorOscilloscope(in: context, width: w, height: h)
        case .neonCyber:
            drawNeonCyber(in: context, width: w, height: h)
        case .matrixRain:
            drawMatrixRain(in: context, width: w, height: h)
        case .solarOrb:
            drawSolarOrb(in: context, width: w, height: h)
        }
        
        // CRT Scanline Overlay
        drawCRTScanlines(in: context, width: w, height: h)
        
        // HUD Overlay
        if hudAlpha > 0.01 {
            drawHUD(in: context, width: w, height: h, alpha: hudAlpha)
        }
    }
    
    // MARK: - Preset 0: Fire Spectrum & Peaks
    private func drawFireSpectrum(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let barCount = min(64, spectrum.count)
        let spacing: CGFloat = 3.0
        let totalSpacing = spacing * CGFloat(barCount + 1)
        let barWidth = max(2.0, (w - totalSpacing) / CGFloat(barCount))
        let maxBarHeight = h * 0.65
        let baseY = h * 0.22
        
        // Floor Mirror Horizon
        context.setStrokeColor(CGColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.4))
        context.setLineWidth(1.0)
        context.strokeLineSegments(between: [CGPoint(x: 0, y: baseY), CGPoint(x: w, y: baseY)])
        
        for i in 0..<barCount {
            let amp = CGFloat(spectrum[i])
            let barH = max(2.0, amp * maxBarHeight)
            let x = spacing + CGFloat(i) * (barWidth + spacing)
            
            // Draw Main Vertical Bar (Gradient from bottom red to yellow to top white)
            let barRect = CGRect(x: x, y: baseY, width: barWidth, height: barH)
            drawVerticalGradientBar(in: context, rect: barRect, amp: amp)
            
            // Floor Reflection (Faded downwards)
            let mirrorH = barH * 0.4
            let mirrorRect = CGRect(x: x, y: baseY - mirrorH, width: barWidth, height: mirrorH)
            context.saveGState()
            context.setAlpha(0.25)
            drawVerticalGradientBar(in: context, rect: mirrorRect, amp: amp, isMirrored: true)
            context.restoreGState()
            
            // Peak Dot
            let peakH = CGFloat(peakHeights[i]) * maxBarHeight
            let peakY = baseY + peakH + 3.0
            context.setFillColor(CGColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 0.9))
            context.fill(CGRect(x: x, y: peakY, width: barWidth, height: 3.0))
        }
    }
    
    private func drawVerticalGradientBar(in context: CGContext, rect: CGRect, amp: CGFloat, isMirrored: Bool = false) {
        let colors = [
            CGColor(red: 0.85, green: 0.05, blue: 0.0, alpha: 1.0),   // Red
            CGColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),    // Orange
            CGColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1.0),    // Yellow
            CGColor(red: 1.0, green: 1.0, blue: 0.95, alpha: 1.0)    // White tip
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: (isMirrored ? colors.reversed() : colors) as CFArray, locations: [0.0, 0.4, 0.8, 1.0])!
        
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: isMirrored ? rect.maxY : rect.minY),
            end: CGPoint(x: rect.midX, y: isMirrored ? rect.minY : rect.maxY),
            options: []
        )
        context.restoreGState()
    }
    
    // MARK: - Preset 1: Phosphor CRT Oscilloscope
    private func drawPhosphorOscilloscope(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let count = waveform.count
        guard count > 1 else { return }
        
        let midY = h * 0.5
        let ampScale = h * 0.35
        let stepX = w / CGFloat(count - 1)
        
        // Multi-pass glow:
        // Pass 1: Wide Phosphor Halo (Blurry green/cyan)
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.0, green: 0.8, blue: 0.5, alpha: 0.15))
        context.setLineWidth(14.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawWaveformPath(in: context, count: count, midY: midY, ampScale: ampScale, stepX: stepX)
        context.strokePath()
        context.restoreGState()
        
        // Pass 2: Medium Neon Glow
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.1, green: 0.95, blue: 0.6, alpha: 0.45))
        context.setLineWidth(5.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawWaveformPath(in: context, count: count, midY: midY, ampScale: ampScale, stepX: stepX)
        context.strokePath()
        context.restoreGState()
        
        // Pass 3: Brilliant Electron Beam Core
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.85, green: 1.0, blue: 0.9, alpha: 1.0))
        context.setLineWidth(1.8)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawWaveformPath(in: context, count: count, midY: midY, ampScale: ampScale, stepX: stepX)
        context.strokePath()
        context.restoreGState()
    }
    
    private func drawWaveformPath(in context: CGContext, count: Int, midY: CGFloat, ampScale: CGFloat, stepX: CGFloat) {
        context.beginPath()
        for i in 0..<count {
            let sample = CGFloat(waveform[i])
            let pt = CGPoint(x: CGFloat(i) * stepX, y: midY + sample * ampScale)
            if i == 0 {
                context.move(to: pt)
            } else {
                context.addLine(to: pt)
            }
        }
    }
    
    // MARK: - Preset 2: Neon Cyber City
    private func drawNeonCyber(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let barCount = min(48, spectrum.count)
        let midX = w * 0.5
        let midY = h * 0.5
        let barW = max(3.0, (w * 0.45) / CGFloat(barCount))
        let maxLen = h * 0.4
        
        for i in 0..<barCount {
            let amp = CGFloat(spectrum[i])
            let len = max(4.0, amp * maxLen)
            let offset = CGFloat(i) * (barW + 2.0)
            
            // Right Side: Neon Cyan
            let rX = midX + 6.0 + offset
            let rectR = CGRect(x: rX, y: midY - len * 0.5, width: barW, height: len)
            context.setFillColor(CGColor(red: 0.0, green: 0.88, blue: 1.0, alpha: 0.85))
            context.fill(rectR)
            
            // Left Side: Neon Magenta / Violet
            let lX = midX - 6.0 - offset - barW
            let rectL = CGRect(x: lX, y: midY - len * 0.5, width: barW, height: len)
            context.setFillColor(CGColor(red: 0.95, green: 0.1, blue: 0.85, alpha: 0.85))
            context.fill(rectL)
        }
    }
    
    // MARK: - Preset 3: Matrix Digital Rain
    private func initMatrixDrops() {
        matrixDrops.removeAll()
        let chars = Array("0123456789ABCDEF!@#$%&*+-=<>WINAMP")
        let cols = 50
        for i in 0..<cols {
            let colChars = (0..<15).map { _ in chars.randomElement()! }
            let drop = MatrixDrop(
                x: CGFloat(i) * 28.0 + 10.0,
                y: CGFloat.random(in: 100...900),
                speed: CGFloat.random(in: 4...10),
                chars: colChars
            )
            matrixDrops.append(drop)
        }
    }
    
    private func drawMatrixRain(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        let bassAmp = CGFloat(spectrum.prefix(6).reduce(0, +) / 6.0)
        
        for (idx, drop) in matrixDrops.enumerated() {
            let specIdx = min(spectrum.count - 1, idx % spectrum.count)
            let colEnergy = CGFloat(spectrum[specIdx])
            
            for (charIdx, char) in drop.chars.enumerated() {
                let charY = drop.y - CGFloat(charIdx * 18)
                guard charY > -20 && charY < h + 20 else { continue }
                
                let isHead = (charIdx == 0)
                let alpha = isHead ? 1.0 : max(0.1, 0.9 - CGFloat(charIdx) * 0.06)
                let glowBoost = 1.0 + (colEnergy + bassAmp) * 0.5
                
                let textColor = isHead
                    ? NSColor(red: 0.85, green: 1.0, blue: 0.85, alpha: alpha)
                    : NSColor(red: 0.05 * glowBoost, green: 0.9 * glowBoost, blue: 0.2 * glowBoost, alpha: alpha)
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor
                ]
                
                let str = String(char) as NSString
                str.draw(at: CGPoint(x: drop.x, y: charY), withAttributes: attrs)
            }
        }
    }
    
    // MARK: - Preset 4: Solar Radial Orb
    private func initSolarParticles() {
        solarParticles.removeAll()
        for _ in 0..<60 {
            let p = SolarParticle(
                angle: CGFloat.random(in: 0...(CGFloat.pi * 2)),
                distance: CGFloat.random(in: 120...320),
                speed: CGFloat.random(in: 0.5...2.0),
                size: CGFloat.random(in: 2...5),
                alpha: CGFloat.random(in: 0.3...0.8)
            )
            solarParticles.append(p)
        }
    }
    
    private func drawSolarOrb(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        let center = CGPoint(x: w * 0.5, y: h * 0.5)
        let bassAmp = CGFloat(spectrum.prefix(4).reduce(0, +) / 4.0)
        let baseRadius: CGFloat = 80.0 + bassAmp * 45.0
        
        // 1. Center Glowing Core
        context.saveGState()
        let coreColor = CGColor(red: 1.0, green: 0.6 + bassAmp * 0.3, blue: 0.1, alpha: 0.8)
        context.setFillColor(coreColor)
        context.fillEllipse(in: CGRect(x: center.x - baseRadius, y: center.y - baseRadius, width: baseRadius * 2, height: baseRadius * 2))
        context.restoreGState()
        
        // 2. 360-degree Radial Spikes
        let rayCount = 48
        let angleStep = (CGFloat.pi * 2) / CGFloat(rayCount)
        context.saveGState()
        context.setLineWidth(3.0)
        context.setLineCap(.round)
        
        for i in 0..<rayCount {
            let angle = CGFloat(i) * angleStep
            let specIdx = min(spectrum.count - 1, i % spectrum.count)
            let amp = CGFloat(spectrum[specIdx])
            let rayLen = baseRadius + 15.0 + amp * 160.0
            
            let startX = center.x + cos(angle) * (baseRadius + 5.0)
            let startY = center.y + sin(angle) * (baseRadius + 5.0)
            let endX = center.x + cos(angle) * rayLen
            let endY = center.y + sin(angle) * rayLen
            
            context.setStrokeColor(CGColor(red: 1.0, green: 0.3 + amp * 0.7, blue: 0.1, alpha: 0.75))
            context.strokeLineSegments(between: [CGPoint(x: startX, y: startY), CGPoint(x: endX, y: endY)])
        }
        context.restoreGState()
        
        // 3. Orbiting Particles
        for p in solarParticles {
            let px = center.x + cos(p.angle) * p.distance
            let py = center.y + sin(p.angle) * p.distance
            context.setFillColor(CGColor(red: 1.0, green: 0.9, blue: 0.4, alpha: p.alpha))
            context.fillEllipse(in: CGRect(x: px - p.size * 0.5, y: py - p.size * 0.5, width: p.size, height: p.size))
        }
    }
    
    // MARK: - CRT Scanlines
    private func drawCRTScanlines(in context: CGContext, width w: CGFloat, height h: CGFloat) {
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.12))
        context.setLineWidth(1.0)
        
        var y: CGFloat = 0
        while y < h {
            context.strokeLineSegments(between: [CGPoint(x: 0, y: y), CGPoint(x: w, y: y)])
            y += 3.0
        }
        context.restoreGState()
    }
    
    // MARK: - HUD Overlay
    private func drawHUD(in context: CGContext, width w: CGFloat, height h: CGFloat, alpha: CGFloat) {
        let coord = PlayerCoordinator.shared
        let track = coord.playlist.currentTrack
        let status = coord.audioEngine.status
        let time = coord.audioEngine.currentTime
        let total = track?.duration ?? 0
        let statusStr = (status == .playing) ? "PLAYING" : ((status == .paused) ? "PAUSED" : "STOPPED")
        
        let titleStr = track?.title ?? "Winamp Studio"
        let artistStr = track?.artist ?? "MacAmp 2.91"
        
        let curM = Int(time) / 60
        let curS = Int(time) % 60
        let timeStr: String
        if total > 0 {
            let totM = Int(total) / 60
            let totS = Int(total) % 60
            timeStr = String(format: "%02d:%02d / %02d:%02d", curM, curS, totM, totS)
        } else {
            timeStr = String(format: "%02d:%02d (LIVE)", curM, curS)
        }
        
        // Top-Right: Preset info & FPS
        let presetStr = "PRESET [\(currentPreset.rawValue + 1)/\(StudioVisualizerPreset.allCases.count)]: \(currentPreset.title.uppercased())  •  \(currentFPS) FPS"
        let topAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(white: 0.9, alpha: alpha)
        ]
        let topSize = (presetStr as NSString).size(withAttributes: topAttrs)
        (presetStr as NSString).draw(at: CGPoint(x: w - topSize.width - 24, y: h - topSize.height - 20), withAttributes: topAttrs)
        
        // Bottom-Left: Track Title & Transport Status
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor(white: 1.0, alpha: alpha)
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(white: 0.75, alpha: alpha)
        ]
        let helpAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor(white: 0.5, alpha: alpha)
        ]
        
        (artistStr as NSString).draw(at: CGPoint(x: 28, y: 72), withAttributes: subAttrs)
        (titleStr as NSString).draw(at: CGPoint(x: 28, y: 48), withAttributes: titleAttrs)
        let subLine = "[\(statusStr)]  \(timeStr)  •  Winamp 2.91 AVS Studio"
        (subLine as NSString).draw(at: CGPoint(x: 28, y: 30), withAttributes: subAttrs)
        
        let helpLine = "[Space / Click]: Change Preset   |   [F]: Fullscreen   |   [Esc]: Exit   |   [←/→]: Tracks   |   [↑/↓]: Volume"
        (helpLine as NSString).draw(at: CGPoint(x: 28, y: 12), withAttributes: helpAttrs)
    }
}
