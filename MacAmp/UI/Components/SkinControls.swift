import Foundation
import CoreGraphics
import AppKit

// MARK: - CGContext Skin Image Drawing Extension
extension CGContext {
    /// Draws a CGImage right-side-up in an isFlipped AppKit NSView.
    @inlinable
    public func drawSkinImage(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1.0, y: -1.0)
        draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        restoreGState()
    }
}

// MARK: - Winamp Base Control View
open class WinampControlView: NSView {
    open override var isFlipped: Bool { true }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.layer?.magnificationFilter = .nearest
        self.layer?.minificationFilter = .nearest
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.layer?.magnificationFilter = .nearest
        self.layer?.minificationFilter = .nearest
    }
    
    open override func rightMouseDown(with event: NSEvent) {
        PlayerCoordinator.shared.showMainContextMenu(at: NSEvent.mouseLocation)
    }
}

// MARK: - SkinButton
public class SkinButton: WinampControlView {
    public var normalSlice: SpriteSlice
    public var pressedSlice: SpriteSlice
    public var action: (() -> Void)?
    
    public private(set) var isPressed = false {
        didSet {
            if oldValue != isPressed {
                needsDisplay = true
            }
        }
    }
    
    public init(normal: SpriteSlice, pressed: SpriteSlice, action: (() -> Void)? = nil) {
        self.normalSlice = normal
        self.pressedSlice = pressed
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: normal.rect.width, height: normal.rect.height))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        let slice = isPressed ? pressedSlice : normalSlice
        if let image = SkinManager.shared.image(for: slice) {
            context.drawSkinImage(image, in: bounds)
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        isPressed = true
        trackMouse(with: event)
    }
    
    private func trackMouse(with initialEvent: NSEvent) {
        guard let window = self.window else { return }
        
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            
            let localPoint = convert(nextEvent.locationInWindow, from: nil)
            let isInside = bounds.contains(localPoint)
            
            switch nextEvent.type {
            case .leftMouseDragged:
                self.isPressed = isInside
            case .leftMouseUp:
                keepTracking = false
                self.isPressed = false
                if isInside {
                    action?()
                }
            default:
                break
            }
        }
    }
}

// MARK: - SkinToggle
public class SkinToggle: WinampControlView {
    public var offNormal: SpriteSlice
    public var offPressed: SpriteSlice
    public var onNormal: SpriteSlice
    public var onPressed: SpriteSlice
    
    public var isOn: Bool = false {
        didSet {
            if oldValue != isOn {
                needsDisplay = true
                onChanged?(isOn)
            }
        }
    }
    
    public var onChanged: ((Bool) -> Void)?
    
    private var isTrackingPressed = false {
        didSet {
            if oldValue != isTrackingPressed {
                needsDisplay = true
            }
        }
    }
    
    public init(offNormal: SpriteSlice, offPressed: SpriteSlice, onNormal: SpriteSlice, onPressed: SpriteSlice, isOn: Bool = false, onChanged: ((Bool) -> Void)? = nil) {
        self.offNormal = offNormal
        self.offPressed = offPressed
        self.onNormal = onNormal
        self.onPressed = onPressed
        self.isOn = isOn
        self.onChanged = onChanged
        super.init(frame: NSRect(x: 0, y: 0, width: offNormal.rect.width, height: offNormal.rect.height))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        
        let slice: SpriteSlice
        if isOn {
            slice = isTrackingPressed ? onPressed : onNormal
        } else {
            slice = isTrackingPressed ? offPressed : offNormal
        }
        
        if let image = SkinManager.shared.image(for: slice) {
            context.drawSkinImage(image, in: bounds)
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        isTrackingPressed = true
        trackMouse(with: event)
    }
    
    private func trackMouse(with initialEvent: NSEvent) {
        guard let window = self.window else { return }
        
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            
            let localPoint = convert(nextEvent.locationInWindow, from: nil)
            let isInside = bounds.contains(localPoint)
            
            switch nextEvent.type {
            case .leftMouseDragged:
                self.isTrackingPressed = isInside
            case .leftMouseUp:
                keepTracking = false
                self.isTrackingPressed = false
                if isInside {
                    self.isOn.toggle()
                }
            default:
                break
            }
        }
    }
}
