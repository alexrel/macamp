import Foundation
import CoreGraphics
import AppKit

public enum SliderOrientation {
    case horizontal
    case vertical
}

public class SkinSlider: WinampControlView {
    public let orientation: SliderOrientation
    public var minValue: Double
    public var maxValue: Double
    public var snapCenter: Bool
    public var snapThreshold: Double
    
    public var value: Double {
        didSet {
            let clamped = max(minValue, min(maxValue, value))
            if clamped != value {
                self.value = clamped
                return
            }
            needsDisplay = true
        }
    }
    
    public var onValueChanged: ((Double) -> Void)?
    
    // Sprites
    public var backgroundSlice: SpriteSlice?
    public var backgroundFrameProvider: ((Int) -> SpriteSlice)?
    public var thumbNormal: SpriteSlice
    public var thumbPressed: SpriteSlice
    
    private var isDragging = false {
        didSet {
            if oldValue != isDragging {
                needsDisplay = true
            }
        }
    }
    
    public init(
        frame: NSRect,
        orientation: SliderOrientation = .horizontal,
        minValue: Double = 0.0,
        maxValue: Double = 1.0,
        initialValue: Double = 0.5,
        snapCenter: Bool = false,
        snapThreshold: Double = 0.05,
        background: SpriteSlice? = nil,
        bgFrameProvider: ((Int) -> SpriteSlice)? = nil,
        thumbNormal: SpriteSlice,
        thumbPressed: SpriteSlice,
        onValueChanged: ((Double) -> Void)? = nil
    ) {
        self.orientation = orientation
        self.minValue = minValue
        self.maxValue = maxValue
        self.value = initialValue
        self.snapCenter = snapCenter
        self.snapThreshold = snapThreshold
        self.backgroundSlice = background
        self.backgroundFrameProvider = bgFrameProvider
        self.thumbNormal = thumbNormal
        self.thumbPressed = thumbPressed
        self.onValueChanged = onValueChanged
        super.init(frame: frame)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Normalized 0.0 ... 1.0
    public var normalizedValue: Double {
        guard maxValue > minValue else { return 0.0 }
        return (value - minValue) / (maxValue - minValue)
    }
    
    public var isThumbHidden: Bool = false {
        didSet {
            if oldValue != isThumbHidden {
                needsDisplay = true
            }
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        // 1. Draw background
        if let frameProvider = backgroundFrameProvider {
            let frameIndex = Int(round(normalizedValue * 27.0))
            let slice = frameProvider(frameIndex)
            if let bgImg = SkinManager.shared.image(for: slice) {
                context.drawSkinImage(bgImg, in: bounds)
            }
        } else if let bgSlice = backgroundSlice, let bgImg = SkinManager.shared.image(for: bgSlice) {
            context.drawSkinImage(bgImg, in: bounds)
        }
        
        // 2. Draw thumb
        if !isThumbHidden {
            var thumbSlice = isDragging ? thumbPressed : thumbNormal
            if backgroundSlice?.name == "MAIN_SHADE_POS_BG" {
                if normalizedValue <= 0.33 {
                    thumbSlice = SpriteCatalog.mainShadePosThumbLeft
                } else if normalizedValue >= 0.66 {
                    thumbSlice = SpriteCatalog.mainShadePosThumbRight
                } else {
                    thumbSlice = SpriteCatalog.mainShadePosThumb
                }
            }
            
            let thumbW = thumbSlice.rect.width
            let thumbH = thumbSlice.rect.height
            
            var thumbRect: NSRect
            if orientation == .horizontal {
                let travelDistance = bounds.width - thumbW
                let thumbX = CGFloat(normalizedValue) * travelDistance
                let thumbY = (bounds.height - thumbH) / 2.0
                thumbRect = NSRect(x: round(thumbX), y: round(thumbY), width: thumbW, height: thumbH)
            } else {
                // Inverted for vertical slider (top is max value, bottom is min value)
                // Travel distance is 51px (bounds.height 63 - 1 - 11 = 51)
                // At 0 dB (normalizedValue 0.5), thumbY = 25, centering thumb line at row 30 (dash is at row 68 in EQMAIN.BMP)
                let travelDistance = bounds.height - 1.0 - thumbH
                let thumbY = floor((1.0 - CGFloat(normalizedValue)) * travelDistance)
                let thumbX: CGFloat = 1.0
                thumbRect = NSRect(x: thumbX, y: thumbY, width: thumbW, height: thumbH)
            }
            
            if let thumbImg = SkinManager.shared.image(for: thumbSlice) {
                context.drawSkinImage(thumbImg, in: thumbRect)
            }
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        guard !isThumbHidden else { return }
        isDragging = true
        updateValue(with: event)
        trackMouse(with: event)
    }
    
    private func updateValue(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let thumbSlice = isDragging ? thumbPressed : thumbNormal
        
        var norm: Double
        if orientation == .horizontal {
            let travel = bounds.width - thumbSlice.rect.width
            guard travel > 0 else { return }
            let clickX = localPoint.x - (thumbSlice.rect.width / 2.0)
            norm = Double(clickX / travel)
        } else {
            let travel = bounds.height - 1.0 - thumbSlice.rect.height
            guard travel > 0 else { return }
            let clickY = localPoint.y - (thumbSlice.rect.height / 2.0)
            norm = 1.0 - Double(clickY / travel)
        }
        
        norm = max(0.0, min(1.0, norm))
        
        // Center snap logic
        if snapCenter {
            let centerNorm = 0.5
            if abs(norm - centerNorm) <= snapThreshold {
                norm = centerNorm
            }
        }
        
        let calculated = minValue + norm * (maxValue - minValue)
        self.value = calculated
        onValueChanged?(calculated)
    }
    
    private func trackMouse(with initialEvent: NSEvent) {
        guard let window = self.window else { return }
        
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            
            switch nextEvent.type {
            case .leftMouseDragged:
                updateValue(with: nextEvent)
            case .leftMouseUp:
                keepTracking = false
                self.isDragging = false
            default:
                break
            }
        }
    }
}
