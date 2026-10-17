import Cocoa
import Foundation

/// Manages positions, magnetic snapping, scale and docked movement of Winamp windows.
public class WindowLayoutManager: NSObject {
    public static let shared = WindowLayoutManager()
    
    public var snapThreshold: CGFloat = CGFloat(PersistenceManager.shared.state.windowSnapDistance)
    private let adjacencyTolerance: CGFloat = 2.0
    
    private var effectiveSnapThreshold: CGFloat {
        snapThreshold * currentScale
    }
    private var effectiveAdjacencyTolerance: CGFloat {
        adjacencyTolerance * currentScale
    }
    
    public private(set) var windows: [WindowID: NSWindow] = [:]
    private var adjacencies: [WindowID: Set<WindowID>] = [:]
    
    public var currentScale: CGFloat = 1.0
    
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
        updateAdjacencies()
        // Main window moves all attached windows; other windows move individually
        let group: Set<WindowID> = (id == .main) ? findGroup(for: id) : [id]
        var origins: [WindowID: NSPoint] = [:]
        for gid in group {
            if let origin = windows[gid]?.frame.origin {
                origins[gid] = origin
            }
        }
        return origins
    }
    
    public func applyDrag(id: WindowID, totalDelta: CGPoint, startOrigins: [WindowID: NSPoint]) {
        let groupIDs = Set(startOrigins.keys)
        let roundedDeltaX = round(totalDelta.x)
        let roundedDeltaY = round(totalDelta.y)
        
        // 1. Move all group windows by raw delta
        for (gid, startOrigin) in startOrigins {
            guard let win = windows[gid] else { continue }
            win.setFrameOrigin(NSPoint(
                x: round(startOrigin.x + roundedDeltaX),
                y: round(startOrigin.y + roundedDeltaY)
            ))
        }
        
        // 2. Find best magnetic snap against screen edges and other windows
        var bestSnap = CGPoint.zero
        var minDistance = CGFloat.infinity
        
        for gid in groupIDs {
            guard let win = windows[gid] else { continue }
            
            // Snap against screen visible frame
            if let screen = win.screen {
                let screenSnap = calculateScreenSnap(target: win.frame, screenFrame: screen.visibleFrame, threshold: effectiveSnapThreshold)
                let dist = hypot(screenSnap.x, screenSnap.y)
                if dist > 0 && dist < minDistance {
                    minDistance = dist
                    bestSnap = screenSnap
                }
            }
            
            // Snap against other (non-group) windows
            for (otherId, otherWin) in windows where !groupIDs.contains(otherId) {
                let snap = calculateWindowSnap(target: win.frame, other: otherWin.frame, threshold: effectiveSnapThreshold)
                let dist = hypot(snap.x, snap.y)
                if dist > 0 && dist < minDistance {
                    minDistance = dist
                    bestSnap = snap
                }
            }
        }
        
        // 3. Apply snap adjustment to all group windows
        if bestSnap != .zero {
            let snapX = round(bestSnap.x)
            let snapY = round(bestSnap.y)
            for gid in groupIDs {
                guard let win = windows[gid] else { continue }
                let current = win.frame.origin
                win.setFrameOrigin(NSPoint(x: round(current.x + snapX), y: round(current.y + snapY)))
            }
        }
    }
    
    public func endDrag(for id: WindowID) {
        updateAdjacencies()
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
                guard let frameA = windows[idA]?.frame, let frameB = windows[idB]?.frame else { continue }
                
                if areFramesAdjacent(frameA, frameB, tolerance: effectiveAdjacencyTolerance) {
                    adjacencies[idA]?.insert(idB)
                    adjacencies[idB]?.insert(idA)
                }
            }
        }
    }
    
    private func findGroup(for root: WindowID) -> Set<WindowID> {
        var visited = Set<WindowID>()
        var queue = [root]
        
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if visited.insert(current).inserted {
                if let neighbors = adjacencies[current] {
                    for neighbor in neighbors where !visited.contains(neighbor) {
                        queue.append(neighbor)
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
    
    // MARK: - Snap Calculations
    private func calculateWindowSnap(target: NSRect, other: NSRect, threshold: CGFloat) -> CGPoint {
        var snap = CGPoint.zero
        
        let verticalOverlap = (target.maxY >= other.minY - threshold) && (target.minY <= other.maxY + threshold)
        let horizontalOverlap = (target.maxX >= other.minX - threshold) && (target.minX <= other.maxX + threshold)
        
        // Horizontal snapping
        if verticalOverlap {
            if abs(target.minX - other.maxX) <= threshold {
                snap.x = round(other.maxX - target.minX)
            } else if abs(target.maxX - other.minX) <= threshold {
                snap.x = round(other.minX - target.maxX)
            } else if abs(target.minX - other.minX) <= threshold {
                snap.x = round(other.minX - target.minX)
            } else if abs(target.maxX - other.maxX) <= threshold {
                snap.x = round(other.maxX - target.maxX)
            }
        }
        
        // Vertical snapping
        if horizontalOverlap {
            if abs(target.minY - other.maxY) <= threshold {
                snap.y = round(other.maxY - target.minY)
            } else if abs(target.maxY - other.minY) <= threshold {
                snap.y = round(other.minY - target.maxY)
            } else if abs(target.minY - other.minY) <= threshold {
                snap.y = round(other.minY - target.minY)
            } else if abs(target.maxY - other.maxY) <= threshold {
                snap.y = round(other.maxY - target.maxY)
            }
        }
        
        return snap
    }
    
    private func calculateScreenSnap(target: NSRect, screenFrame: NSRect, threshold: CGFloat) -> CGPoint {
        var snap = CGPoint.zero
        
        if abs(target.minX - screenFrame.minX) <= threshold {
            snap.x = round(screenFrame.minX - target.minX)
        } else if abs(target.maxX - screenFrame.maxX) <= threshold {
            snap.x = round(screenFrame.maxX - target.maxX)
        }
        
        if abs(target.minY - screenFrame.minY) <= threshold {
            snap.y = round(screenFrame.minY - target.minY)
        } else if abs(target.maxY - screenFrame.maxY) <= threshold {
            snap.y = round(screenFrame.maxY - target.maxY)
        }
        
        return snap
    }
    
    // MARK: - Shade Mode Height Change & Docked Windows Shift
    public func findWindowsBelow(id: WindowID) -> Set<WindowID> {
        guard windows[id] != nil else { return [] }
        var result = Set<WindowID>()
        var queue: [WindowID] = [id]
        
        while !queue.isEmpty {
            let currentId = queue.removeFirst()
            guard let currentWin = windows[currentId] else { continue }
            let currentFrame = currentWin.frame
            
            for (otherId, otherWin) in windows where otherId != currentId && !result.contains(otherId) && otherId != id {
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
        let scale = (id == .playlist) ? 1.0 : currentScale
        let newH = round(newHeightUnscaled * scale)
        let oldFrame = win.frame
        let diff = round(oldFrame.height - newH)
        guard abs(diff) > 0.001 else { return }
        
        // Find windows docked below BEFORE changing frame
        let belowWindows = findWindowsBelow(id: id)
        
        // Update target window frame
        let unscaledW = (id == .playlist) ? round(win.frame.width) : AppConstants.Window.width
        let newW = (id == .playlist) ? unscaledW : round(unscaledW * scale)
        var newTargetFrame = oldFrame
        newTargetFrame.origin.x = round(newTargetFrame.origin.x)
        newTargetFrame.origin.y = round(newTargetFrame.origin.y + diff)
        newTargetFrame.size.width = newW
        newTargetFrame.size.height = newH
        win.setFrame(newTargetFrame, display: true, animate: false)
        
        if let content = win.contentView {
            content.frame = NSRect(x: 0, y: 0, width: win.frame.width, height: newH)
            content.bounds = NSRect(x: 0, y: 0, width: unscaledW, height: newHeightUnscaled)
            content.needsLayout = true
            content.layoutSubtreeIfNeeded()
            content.needsDisplay = true
            for sub in content.subviews {
                sub.needsDisplay = true
            }
        }
        
        // Move all attached windows below by diff so they remain docked with 0 gap
        for belowId in belowWindows {
            guard let belowWin = windows[belowId] else { continue }
            var belowFrame = belowWin.frame
            belowFrame.origin.x = round(belowFrame.origin.x)
            belowFrame.origin.y = round(belowFrame.origin.y + diff)
            belowWin.setFrame(belowFrame, display: true, animate: false)
        }
        
        clampToScreen()
        updateAdjacencies()
    }
    
    // MARK: - Window Scaling (1x / 2x)
    public func setScale(_ newScale: CGFloat) {
        guard newScale != currentScale else { return }
        let oldScale = currentScale
        currentScale = newScale
        
        guard let mainWin = windows[.main] else { return }
        let anchorX = mainWin.frame.minX
        let anchorY = mainWin.frame.maxY
        
        for (id, win) in windows {
            if id == .playlist {
                // Playlist window remains at 1x resolution (canDouble = false in Winamp)
                let deltaX = (win.frame.minX - anchorX) / oldScale
                let deltaY = (anchorY - win.frame.maxY) / oldScale
                
                let newMinX = round(anchorX + (deltaX * newScale))
                let newMaxY = round(anchorY - (deltaY * newScale))
                let winW = round(win.frame.width)
                let winH = round(win.frame.height)
                let newMinY = round(newMaxY - winH)
                
                win.setFrame(NSRect(x: newMinX, y: newMinY, width: winW, height: winH), display: true, animate: false)
                if let content = win.contentView {
                    content.bounds = NSRect(x: 0, y: 0, width: winW, height: winH)
                    content.needsDisplay = true
                }
            } else {
                let deltaX = (win.frame.minX - anchorX) / oldScale
                let deltaY = (anchorY - win.frame.maxY) / oldScale
                let unscaledW = AppConstants.Window.width
                let unscaledH = win.frame.height / oldScale
                
                let newW = round(unscaledW * newScale)
                let newH = round(unscaledH * newScale)
                let newMinX = round(anchorX + (deltaX * newScale))
                let newMaxY = round(anchorY - (deltaY * newScale))
                let newMinY = round(newMaxY - newH)
                
                win.setFrame(NSRect(x: newMinX, y: newMinY, width: newW, height: newH), display: true, animate: false)
                
                if let content = win.contentView {
                    content.bounds = NSRect(x: 0, y: 0, width: unscaledW, height: unscaledH)
                    content.needsDisplay = true
                }
            }
        }
        
        clampToScreen()
        updateAdjacencies()
    }
    
    public func clampToScreen() {
        guard let mainWin = windows[.main], let screen = mainWin.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        
        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity
        
        for (_, win) in windows {
            minX = min(minX, win.frame.minX)
            maxX = max(maxX, win.frame.maxX)
            minY = min(minY, win.frame.minY)
            maxY = max(maxY, win.frame.maxY)
        }
        
        var shiftX: CGFloat = 0
        var shiftY: CGFloat = 0
        
        if maxY > visible.maxY {
            shiftY = visible.maxY - maxY
        }
        if minY + shiftY < visible.minY {
            shiftY = visible.minY - minY
        }
        if minX < visible.minX {
            shiftX = visible.minX - minX
        } else if maxX > visible.maxX {
            shiftX = visible.maxX - maxX
        }
        
        if shiftX != 0 || shiftY != 0 {
            let roundedShiftX = round(shiftX)
            let roundedShiftY = round(shiftY)
            for (_, win) in windows {
                let origin = win.frame.origin
                win.setFrameOrigin(NSPoint(x: round(origin.x + roundedShiftX), y: round(origin.y + roundedShiftY)))
            }
        }
    }
}
