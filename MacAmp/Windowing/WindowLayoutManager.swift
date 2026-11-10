import Cocoa
import Foundation

/// Manages positions, magnetic snapping, scale and docked movement of Winamp windows.
public class WindowLayoutManager: NSObject {
    public static let shared = WindowLayoutManager()
    
    public var snapThreshold: CGFloat = CGFloat(PersistenceManager.shared.state.windowSnapDistance)
    private let adjacencyTolerance: CGFloat = 2.0
    
    private var effectiveSnapThreshold: CGFloat {
        snapThreshold * scale(for: .main)
    }
    private var effectiveAdjacencyTolerance: CGFloat {
        adjacencyTolerance * scale(for: .main)
    }
    
    public private(set) var windows: [WindowID: NSWindow] = [:]
    private var adjacencies: [WindowID: Set<WindowID>] = [:]
    
    public var currentScale: CGFloat = 1.0
    func scale(for id: WindowID) -> CGFloat {
        PersistenceManager.shared.state.interfaceScale.multiplier * (id.keepsOwnSize ? 1 : currentScale)
    }
    /// Window size in points for a size in skin pixels. Each 275 px column is rounded on its own, so windows docked
    /// side by side are exactly as wide as a wider one below them at any scale (275 × 1.5 isn't a whole number).
    static func scaled(_ logical: NSSize) -> NSSize {
        let scale = PersistenceManager.shared.state.interfaceScale.multiplier
        let column = AppConstants.Window.width
        let columns = (logical.width / column).rounded(.down)
        return NSSize(width: columns * (column * scale).rounded() + ((logical.width - columns * column) * scale).rounded(),
                      height: (logical.height * scale).rounded())
    }
    func frameSize(for id: WindowID, logical: NSSize) -> NSSize {
        let size = Self.scaled(logical), double = id.keepsOwnSize ? 1 : currentScale
        return NSSize(width: size.width * double, height: size.height * double)
    }
    public var onLayoutChanged: (() -> Void)?
    
    /// Stored window origins when temporarily relocated from a disconnected external display.
    public var savedExternalPositions: [WindowID: NSPoint]? = nil
    /// Tracks if the user intentionally dragged/moved windows after they were brought to the main display.
    public var hasUserMovedWindowsSinceRelocation: Bool = false
    
    private override init() {
        super.init()
    }
    
    public func register(window: NSWindow, for id: WindowID) {
        windows[id] = window
        window.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        updateAdjacencies()
    }
    
    public func unregister(id: WindowID) {
        windows.removeValue(forKey: id)
        adjacencies.removeValue(forKey: id)
        updateAdjacencies()
    }
    
    // MARK: - Dragging & Snapping
    public func startDrag(for id: WindowID) -> [WindowID: NSPoint] {
        hasUserMovedWindowsSinceRelocation = true
        savedExternalPositions = nil
        updateAdjacencies()
        // Main window moves all attached visible windows; other windows move individually
        let group: Set<WindowID> = (id == .main) ? findGroup(for: id) : [id]
        var origins: [WindowID: NSPoint] = [:]
        for gid in group {
            if let win = windows[gid], win.isVisible {
                origins[gid] = win.frame.origin
            }
        }
        return origins
    }
    
    public func applyDrag(id: WindowID, totalDelta: CGPoint, startOrigins: [WindowID: NSPoint]) {
        let groupIDs = Set(startOrigins.keys)
        let roundedDeltaX = round(totalDelta.x)
        let roundedDeltaY = round(totalDelta.y)
        
        // 1. Calculate proposed un-snapped frames for all group windows
        var proposedFrames: [WindowID: NSRect] = [:]
        for gid in groupIDs {
            guard let win = windows[gid], win.isVisible, let startOrigin = startOrigins[gid] else { continue }
            let proposedOrigin = NSPoint(
                x: round(startOrigin.x + roundedDeltaX),
                y: round(startOrigin.y + roundedDeltaY)
            )
            proposedFrames[gid] = NSRect(origin: proposedOrigin, size: win.frame.size)
        }
        
        // 2. Find best magnetic snap on X and Y axes independently
        let effectiveSnapThreshold = effectiveSnapThreshold
        var bestSnapX: CGFloat = 0
        var minDistanceX: CGFloat = CGFloat.infinity
        
        var bestSnapY: CGFloat = 0
        var minDistanceY: CGFloat = CGFloat.infinity
        
        for gid in groupIDs {
            guard let proposedFrame = proposedFrames[gid], let win = windows[gid] else { continue }
            
            // Snap against screen visible frame
            if let screen = win.screen {
                let sf = screen.visibleFrame
                
                // Screen X snapping (left and right edges)
                let leftDist = abs(proposedFrame.minX - sf.minX)
                if leftDist <= effectiveSnapThreshold && leftDist < minDistanceX {
                    minDistanceX = leftDist
                    bestSnapX = round(sf.minX - proposedFrame.minX)
                }
                let rightDist = abs(proposedFrame.maxX - sf.maxX)
                if rightDist <= effectiveSnapThreshold && rightDist < minDistanceX {
                    minDistanceX = rightDist
                    bestSnapX = round(sf.maxX - proposedFrame.maxX)
                }
                
                // Screen Y snapping (bottom and top edges)
                let bottomDist = abs(proposedFrame.minY - sf.minY)
                if bottomDist <= effectiveSnapThreshold && bottomDist < minDistanceY {
                    minDistanceY = bottomDist
                    bestSnapY = round(sf.minY - proposedFrame.minY)
                }
                let topDist = abs(proposedFrame.maxY - sf.maxY)
                if topDist <= effectiveSnapThreshold && topDist < minDistanceY {
                    minDistanceY = topDist
                    bestSnapY = round(sf.maxY - proposedFrame.maxY)
                }
            }
            
            // Snap against other (non-group) visible windows
            for (otherId, otherWin) in windows where !groupIDs.contains(otherId) && otherWin.isVisible {
                let otherFrame = otherWin.frame
                
                let verticalOverlap = (proposedFrame.maxY >= otherFrame.minY - effectiveSnapThreshold) &&
                                      (proposedFrame.minY <= otherFrame.maxY + effectiveSnapThreshold)
                let horizontalOverlap = (proposedFrame.maxX >= otherFrame.minX - effectiveSnapThreshold) &&
                                        (proposedFrame.minX <= otherFrame.maxX + effectiveSnapThreshold)
                
                // Horizontal docking candidates (when vertical overlap exists)
                if verticalOverlap {
                    let candidatesX: [CGFloat] = [
                        round(otherFrame.maxX - proposedFrame.minX), // target docks to right of other
                        round(otherFrame.minX - proposedFrame.maxX), // target docks to left of other
                        round(otherFrame.minX - proposedFrame.minX), // align left edges
                        round(otherFrame.maxX - proposedFrame.maxX)  // align right edges
                    ]
                    for dx in candidatesX {
                        let dist = abs(dx)
                        if dist <= effectiveSnapThreshold && dist < minDistanceX {
                            minDistanceX = dist
                            bestSnapX = dx
                        }
                    }
                }
                
                // Vertical docking candidates (when horizontal overlap exists)
                if horizontalOverlap {
                    let candidatesY: [CGFloat] = [
                        round(otherFrame.maxY - proposedFrame.minY), // target docks above other
                        round(otherFrame.minY - proposedFrame.maxY), // target docks below other
                        round(otherFrame.minY - proposedFrame.minY), // align bottom edges
                        round(otherFrame.maxY - proposedFrame.maxY)  // align top edges
                    ]
                    for dy in candidatesY {
                        let dist = abs(dy)
                        if dist <= effectiveSnapThreshold && dist < minDistanceY {
                            minDistanceY = dist
                            bestSnapY = dy
                        }
                    }
                }
            }
        }
        
        // 3. Apply final snapped position to all group windows in a single update
        let totalShiftX = roundedDeltaX + bestSnapX
        let totalShiftY = roundedDeltaY + bestSnapY
        
        for (gid, startOrigin) in startOrigins {
            guard let win = windows[gid], win.isVisible else { continue }
            win.setFrameOrigin(NSPoint(
                x: round(startOrigin.x + totalShiftX),
                y: round(startOrigin.y + totalShiftY)
            ))
        }
    }
    
    public func endDrag(for id: WindowID) {
        updateAdjacencies()
        onLayoutChanged?()
    }

    
    // MARK: - Adjacency Graph
    public func updateAdjacencies() {
        adjacencies.removeAll()
        for id in windows.keys {
            adjacencies[id] = []
        }
        
        let allIDs = Array(windows.keys)
        for i in 0..<allIDs.count {
            for j in (i + 1)..<allIDs.count {
                let idA = allIDs[i]
                let idB = allIDs[j]
                guard let winA = windows[idA], let winB = windows[idB],
                      winA.isVisible, winB.isVisible else { continue }
                
                if areFramesAdjacent(winA.frame, winB.frame, tolerance: effectiveAdjacencyTolerance) {
                    adjacencies[idA]?.insert(idB)
                    adjacencies[idB]?.insert(idA)
                }
            }
        }
    }
    
    public func findGroup(for root: WindowID) -> Set<WindowID> {
        guard let rootWin = windows[root], rootWin.isVisible else { return [root] }
        var visited = Set<WindowID>()
        var queue = [root]
        
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if visited.insert(current).inserted {
                if let neighbors = adjacencies[current] {
                    for neighbor in neighbors where !visited.contains(neighbor) {
                        if let neighborWin = windows[neighbor], neighborWin.isVisible {
                            queue.append(neighbor)
                        }
                    }
                }
            }
        }
        return visited
    }
    
    private func areFramesAdjacent(_ a: NSRect, _ b: NSRect, tolerance: CGFloat) -> Bool {
        let touchX = abs(a.maxX - b.minX) <= tolerance || abs(a.minX - b.maxX) <= tolerance
        let overlapY = a.maxY > b.minY && a.minY < b.maxY
        if touchX && overlapY { return true }
        
        let touchY = abs(a.maxY - b.minY) <= tolerance || abs(a.minY - b.maxY) <= tolerance
        let overlapX = a.maxX > b.minX && a.minX < b.maxX
        if touchY && overlapX { return true }
        
        return false
    }
    
    // MARK: - Shade Mode Height Change & Docked Windows Shift
    public func findWindowsBelow(id: WindowID) -> Set<WindowID> {
        guard let currentWin = windows[id], currentWin.isVisible else { return [] }
        var result = Set<WindowID>()
        var queue: [WindowID] = [id]
        
        while !queue.isEmpty {
            let currentId = queue.removeFirst()
            guard let cWin = windows[currentId], cWin.isVisible else { continue }
            let currentFrame = cWin.frame
            
            for (otherId, otherWin) in windows where otherId != currentId && !result.contains(otherId) && otherId != id && otherWin.isVisible {
                let otherFrame = otherWin.frame
                let isDirectlyBelow = abs(currentFrame.minY - otherFrame.maxY) <= effectiveAdjacencyTolerance
                let horizontalOverlap = currentFrame.maxX > otherFrame.minX && currentFrame.minX < otherFrame.maxX
                if isDirectlyBelow && horizontalOverlap {
                    result.insert(otherId)
                    queue.append(otherId)
                }
            }
        }
        return result
    }
    
    public func handleWindowHeightChange(id: WindowID, newHeightUnscaled: CGFloat) {
        guard let win = windows[id] else { return }
        let scale = scale(for: id)
        let logicalWidth = win.contentView?.bounds.width ?? (win.frame.width / scale).rounded()
        let newH = frameSize(for: id, logical: NSSize(width: logicalWidth, height: newHeightUnscaled)).height
        let oldFrame = win.frame
        let diff = oldFrame.height - newH
        guard abs(diff) > 0.001 else { return }
        
        // Find windows docked below BEFORE changing frame
        let belowWindows = findWindowsBelow(id: id)
        
        // Update target window frame
        var newTargetFrame = oldFrame
        newTargetFrame.origin.y += diff
        newTargetFrame.size.height = newH
        win.setFrame(newTargetFrame, display: true, animate: false)
        win.updateContentScale(scale, logicalSize: NSSize(width: logicalWidth, height: newHeightUnscaled))
        
        // Move all attached windows below by diff so they remain docked with 0 gap
        for belowId in belowWindows {
            guard let belowWin = windows[belowId] else { continue }
            var belowFrame = belowWin.frame
            belowFrame.origin.y += diff
            belowWin.setFrame(belowFrame, display: true, animate: false)
        }
        
        clampToScreen()
        updateAdjacencies()
        onLayoutChanged?()
    }
    
    // MARK: - Window Scaling (1x / 2x)
    public func setScale(_ newScale: CGFloat) {
        let oldScale = currentScale
        let tolerance = max(4.0, effectiveAdjacencyTolerance)
        currentScale = newScale
        
        guard let mainWin = windows[.main] else { return }
        let anchorX = mainWin.frame.minX
        let anchorY = mainWin.frame.maxY
        
        let oldFrames = windows.mapValues(\.frame)
        let logicalSizes = windows.compactMapValues { window in
            window.contentView.map { NSSize(width: $0.bounds.width.rounded(), height: $0.bounds.height.rounded()) }
        }
        var targetSizes: [WindowID: NSSize] = [:]
        for (id, size) in logicalSizes { targetSizes[id] = frameSize(for: id, logical: size) }
        guard oldScale != newScale || targetSizes.contains(where: { oldFrames[$0.key]?.size != $0.value }) else { return }
        
        // Calculate new frames using docking relationships
        var newFrames: [WindowID: NSRect] = [:]
        
        // 1. Root anchor: MainWindow top-left remains fixed at (anchorX, anchorY)
        if let mainSize = targetSizes[.main] {
            newFrames[.main] = NSRect(
                x: anchorX,
                y: anchorY - mainSize.height,
                width: mainSize.width,
                height: mainSize.height
            )
        }
        
        // 2. Iteratively place all windows docked to placed windows
        let windowOrder = WindowID.allCases
        var unplaced = Set(targetSizes.keys)
        unplaced.remove(.main)
        
        while !unplaced.isEmpty {
            var progress = false
            for u in windowOrder where unplaced.contains(u) {
                guard let oldU = oldFrames[u], let sizeU = targetSizes[u] else { continue }
                
                var placedFrame: NSRect? = nil
                var closestAlignment = CGFloat.infinity
                
                // A window spanning two neighbors follows the one closest to its top-left corner.
                for p in windowOrder {
                    guard let oldP = oldFrames[p], let newP = newFrames[p],
                          p == .main || windows[p]?.isVisible == true || windows[u]?.isVisible == false else { continue }
                    
                    let touchAbove = abs(oldU.minY - oldP.maxY) <= tolerance
                    let touchBelow = abs(oldU.maxY - oldP.minY) <= tolerance
                    let touchRight = abs(oldU.minX - oldP.maxX) <= tolerance
                    let touchLeft  = abs(oldU.maxX - oldP.minX) <= tolerance
                    
                    let overlapH = oldU.maxX > oldP.minX + 1.0 && oldU.minX < oldP.maxX - 1.0
                    let overlapV = oldU.maxY > oldP.minY + 1.0 && oldU.minY < oldP.maxY - 1.0
                    
                    let frame: NSRect
                    let alignment: CGFloat
                    if (touchAbove || touchBelow) && overlapH {
                        alignment = abs(oldU.minX - oldP.minX)
                        let newY = touchAbove ? newP.maxY : newP.minY - sizeU.height
                        let newX = calculateDockedX(oldU: oldU, oldP: oldP, newP: newP, sizeU: sizeU, tolerance: tolerance)
                        frame = NSRect(origin: NSPoint(x: newX, y: newY), size: sizeU)
                    } else if (touchRight || touchLeft) && overlapV {
                        alignment = abs(oldU.maxY - oldP.maxY)
                        let newX = touchRight ? newP.maxX : newP.minX - sizeU.width
                        let newY = calculateDockedY(oldU: oldU, oldP: oldP, newP: newP, sizeU: sizeU, tolerance: tolerance)
                        frame = NSRect(origin: NSPoint(x: newX, y: newY), size: sizeU)
                    } else {
                        continue
                    }

                    if alignment < closestAlignment {
                        closestAlignment = alignment
                        placedFrame = frame
                    }
                }
                
                if let frame = placedFrame {
                    newFrames[u] = frame
                    unplaced.remove(u)
                    progress = true
                }
            }

            // Start the next disconnected group at its floating anchor.
            if !progress, let root = windowOrder.first(where: { unplaced.contains($0) }),
               let old = oldFrames[root], let size = targetSizes[root] {
                let ratio = newScale / oldScale
                let x = anchorX + (old.minX - anchorX) * ratio
                let y = anchorY + (old.maxY - anchorY) * ratio - size.height
                newFrames[root] = NSRect(origin: NSPoint(x: x.rounded(), y: y.rounded()), size: size)
                unplaced.remove(root)
            }
        }

        // 3. Apply new frames to all windows
        for (id, win) in windows {
            guard let newFrame = newFrames[id], let logicalSize = logicalSizes[id] else { continue }
            if win.frame != newFrame {
                win.setFrame(newFrame, display: true, animate: false)
                win.updateContentScale(scale(for: id), logicalSize: logicalSize)
            }
        }
        
        updateAdjacencies()
        clampToScreen()
        onLayoutChanged?()
    }
    
    private func calculateDockedX(oldU: NSRect, oldP: NSRect, newP: NSRect, sizeU: NSSize, tolerance: CGFloat) -> CGFloat {
        if abs(oldU.minX - oldP.minX) <= tolerance {
            // Left edges were aligned
            return newP.minX
        } else if abs(oldU.maxX - oldP.maxX) <= tolerance {
            // Right edges were aligned
            return newP.maxX - sizeU.width
        } else {
            // Proportional offset
            return (newP.minX + (oldU.minX - oldP.minX) / oldP.width * newP.width).rounded()
        }
    }
    
    private func calculateDockedY(oldU: NSRect, oldP: NSRect, newP: NSRect, sizeU: NSSize, tolerance: CGFloat) -> CGFloat {
        if abs(oldU.maxY - oldP.maxY) <= tolerance {
            // Top edges were aligned
            return newP.maxY - sizeU.height
        } else if abs(oldU.minY - oldP.minY) <= tolerance {
            // Bottom edges were aligned
            return newP.minY
        } else {
            // Proportional offset
            return (newP.maxY - (oldP.maxY - oldU.maxY) / oldP.height * newP.height - sizeU.height).rounded()
        }
    }
    
    // MARK: - Multi-Monitor & Screen Bounds Clamping
    
    /// Checks whether a given rect intersects any active connected screen by at least minWidth x minHeight.
    public func isRectVisibleOnAnyScreen(_ rect: NSRect, minVisibleWidth: CGFloat = 50, minVisibleHeight: CGFloat = 30) -> Bool {
        for screen in NSScreen.screens {
            let intersection = screen.visibleFrame.intersection(rect)
            if !intersection.isNull && intersection.width >= minVisibleWidth && intersection.height >= minVisibleHeight {
                return true
            }
        }
        return false
    }
    
    /// Handles display connection / disconnection and resolution changes.
    /// If an external screen was disconnected, moves off-screen windows cleanly to the main screen.
    /// If the external screen was reconnected and windows were not moved by the user, restores them to the external screen.
    public func handleScreenParametersChanged() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        // 1. Try to restore to external monitor if it was reconnected and user hasn't moved windows
        if let saved = savedExternalPositions, !hasUserMovedWindowsSinceRelocation {
            var canRestore = true
            for (id, pos) in saved {
                guard let win = windows[id] else { continue }
                let rect = NSRect(origin: pos, size: win.frame.size)
                if !isRectVisibleOnAnyScreen(rect) {
                    canRestore = false
                    break
                }
            }
            
            if canRestore {
                for (id, pos) in saved {
                    windows[id]?.setFrameOrigin(pos)
                }
                savedExternalPositions = nil
                updateAdjacencies()
                clampToScreen()
                onLayoutChanged?()
                return
            }
        }
        
        // 2. Check each window group to see if any are now off-screen (disconnected monitor)
        var processed = Set<WindowID>()
        for id in windows.keys {
            guard windows[id] != nil, !processed.contains(id) else { continue }
            let group = findGroup(for: id)
            processed.formUnion(group)
            
            var minX = CGFloat.infinity
            var maxX = -CGFloat.infinity
            var minY = CGFloat.infinity
            var maxY = -CGFloat.infinity
            
            for gid in group {
                guard let gWin = windows[gid] else { continue }
                minX = min(minX, gWin.frame.minX)
                maxX = max(maxX, gWin.frame.maxX)
                minY = min(minY, gWin.frame.minY)
                maxY = max(maxY, gWin.frame.maxY)
            }
            guard minX < maxX && minY < maxY else { continue }
            let groupRect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            
            if !isRectVisibleOnAnyScreen(groupRect) {
                // Save current positions for restoration when monitor is reconnected
                var origins: [WindowID: NSPoint] = [:]
                for gid in group {
                    if let gWin = windows[gid] {
                        origins[gid] = gWin.frame.origin
                    }
                }
                self.savedExternalPositions = origins
                self.hasUserMovedWindowsSinceRelocation = false
                
                // Shift whole group onto the primary screen's visible frame
                let mainScreen = NSScreen.main ?? screens[0]
                let visible = mainScreen.visibleFrame
                let groupW = maxX - minX
                let targetX = round(visible.minX + max(20.0, (visible.width - groupW) / 2.0))
                let targetTopY = round(visible.maxY - 50.0)
                let shiftX = round(targetX - minX)
                let shiftY = round(targetTopY - maxY)
                
                for gid in group {
                    guard let gWin = windows[gid] else { continue }
                    let origin = gWin.frame.origin
                    gWin.setFrameOrigin(NSPoint(x: round(origin.x + shiftX), y: round(origin.y + shiftY)))
                }
            }
        }
        
        // 3. Ensure all windows are clamped into visible screen boundaries
        clampToScreen()
    }
    
    public func clampToScreen() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        var processed = Set<WindowID>()
        var didShift = false
        
        for id in windows.keys {
            guard windows[id]?.isVisible == true, !processed.contains(id) else { continue }
            let group = findGroup(for: id)
            processed.formUnion(group)
            
            var minX = CGFloat.infinity
            var maxX = -CGFloat.infinity
            var minY = CGFloat.infinity
            var maxY = -CGFloat.infinity
            
            for gid in group {
                guard let gWin = windows[gid] else { continue }
                minX = min(minX, gWin.frame.minX)
                maxX = max(maxX, gWin.frame.maxX)
                minY = min(minY, gWin.frame.minY)
                maxY = max(maxY, gWin.frame.maxY)
            }
            
            guard minX < maxX && minY < maxY else { continue }
            let groupRect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            
            // Find which screen contains the largest portion of the group
            var targetScreen: NSScreen? = nil
            var maxArea: CGFloat = 0
            for screen in screens {
                let inter = screen.visibleFrame.intersection(groupRect)
                if !inter.isNull && !inter.isEmpty {
                    let area = inter.width * inter.height
                    if area > maxArea {
                        maxArea = area
                        targetScreen = screen
                    }
                }
            }
            
            let isCompletelyOffscreen = (targetScreen == nil) || (maxArea < 50.0)
            let chosenScreen = targetScreen ?? NSScreen.main ?? screens[0]
            let visible = chosenScreen.visibleFrame
            
            var shiftX: CGFloat = 0
            var shiftY: CGFloat = 0
            
            if isCompletelyOffscreen {
                // Relocate cleanly onto the visible frame of chosen screen
                let groupW = maxX - minX
                let targetX = round(visible.minX + max(20.0, (visible.width - groupW) / 2.0))
                shiftX = targetX - minX
                let targetTopY = round(visible.maxY - 50.0)
                shiftY = targetTopY - maxY
            } else {
                // Window intersects this screen; clamp overflowing edges
                if maxY > visible.maxY {
                    shiftY = visible.maxY - maxY
                }
                // Keep the title bars reachable when the whole group cannot fit.
                if groupRect.height <= visible.height, minY + shiftY < visible.minY {
                    shiftY = visible.minY - minY
                }
                if groupRect.width > visible.width || minX < visible.minX {
                    shiftX = visible.minX - minX
                } else if maxX > visible.maxX {
                    shiftX = visible.maxX - maxX
                }
            }
            
            if shiftX != 0 || shiftY != 0 {
                for gid in group {
                    guard let gWin = windows[gid] else { continue }
                    let origin = gWin.frame.origin
                    gWin.setFrameOrigin(NSPoint(x: origin.x + shiftX, y: origin.y + shiftY))
                }
                didShift = true
            }
        }
        
        if didShift {
            updateAdjacencies()
            onLayoutChanged?()
        }
    }
}
