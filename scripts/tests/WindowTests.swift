import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func windowTests() {
    // 1. WindowLayoutManager & Magnetic Snapping Tests
    testGroup("WindowLayoutManager & Magnetic Snapping") {
        let wlm = WindowLayoutManager.shared
        assertEqual(wlm.currentScale, 1.0, "Scale factor should default to 1.0")

        // Create test mock windows
        let winA = NSWindow(contentRect: NSRect(x: 100, y: 500, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
        let winB = NSWindow(contentRect: NSRect(x: 100, y: 384, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
        let winC = NSWindow(contentRect: NSRect(x: 100, y: 268, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)

        wlm.register(window: winA, for: .main)
        wlm.register(window: winB, for: .equalizer)
        wlm.register(window: winC, for: .playlist)

        // When visible, winA and winB touch vertically (winA.minY == 500, winB.maxY == 500)
        winA.orderFront(nil)
        winB.orderFront(nil)
        winC.orderFront(nil)

        wlm.updateAdjacencies()
        let dragOrigins = wlm.startDrag(for: .main)
        assertTrue(dragOrigins.keys.contains(.main), "Group should contain main window")
        assertTrue(dragOrigins.keys.contains(.equalizer), "Group should contain docked equalizer window")
        assertTrue(dragOrigins.keys.contains(.playlist), "Group should contain docked playlist window")

        // Now test that hidden windows are NOT included in group or adjacencies
        winB.orderOut(nil)
        wlm.updateAdjacencies()
        let dragWithoutEQ = wlm.startDrag(for: .main)
        assertTrue(!dragWithoutEQ.keys.contains(.equalizer), "Hidden equalizer window must NOT participate in drag group")

        // Test applyDrag moving windows with rounded delta
        winB.orderFront(nil)
        let initialMainOrigin = winA.frame.origin
        let origins = wlm.startDrag(for: .main)
        wlm.applyDrag(id: .main, totalDelta: CGPoint(x: 20, y: -20), startOrigins: origins)
        let movedMainOrigin = winA.frame.origin
        assertTrue(movedMainOrigin.x > initialMainOrigin.x, "Main window should move with drag delta")

        // Dragged up against the menu bar the group stops together (issue 1: the playlist slid under the main window)
        if let screenTop = winA.screen?.visibleFrame.maxY {
            winA.setFrameOrigin(NSPoint(x: 100, y: screenTop - 116 - 10))
            winB.setFrameOrigin(NSPoint(x: 100, y: screenTop - 232 - 10))
            winC.setFrameOrigin(NSPoint(x: 100, y: screenTop - 348 - 10))
            wlm.updateAdjacencies()
            wlm.applyDrag(id: .main, totalDelta: CGPoint(x: 0, y: 60), startOrigins: wlm.startDrag(for: .main))
            print("  menu bar drag: main top \(winA.frame.maxY), screen top \(screenTop)")
            assertEqual(winB.frame.maxY, winA.frame.minY, "Equalizer stays docked under the main window")
            assertEqual(winC.frame.maxY, winB.frame.minY, "Playlist stays docked under the equalizer")
        }

        // Restore window positions
        winA.setFrameOrigin(NSPoint(x: 100, y: 500))
        winB.setFrameOrigin(NSPoint(x: 100, y: 384))
        winC.setFrameOrigin(NSPoint(x: 100, y: 268))
        wlm.updateAdjacencies()

        // Test findWindowsBelow
        let below = wlm.findWindowsBelow(id: .main)
        assertTrue(below.contains(.equalizer), "Equalizer should be found below Main window")
        assertTrue(below.contains(.playlist), "Playlist should be found below Equalizer window")

        // Test Scaling with Inverted Window Layout: Playlist TOP, Equalizer MIDDLE, Main BOTTOM
        // In 1x: Main at y=100 (height 116 -> maxY=216), EQ at y=216 (maxY=332), Playlist at y=332 (maxY=448)
        winA.setFrame(NSRect(x: 100, y: 100, width: 275, height: 116), display: false)
        winB.setFrame(NSRect(x: 100, y: 216, width: 275, height: 116), display: false)
        winC.setFrame(NSRect(x: 100, y: 332, width: 275, height: 116), display: false)
        winA.orderFront(nil)
        winB.orderFront(nil)
        winC.orderFront(nil)
        wlm.updateAdjacencies()

        // Scale 1x -> 2x
        wlm.setScale(2.0)
        assertEqual(wlm.currentScale, 2.0, "Scale factor should be 2.0")

        let main2x = winA.frame
        let eq2x = winB.frame
        let pl2x = winC.frame
        assertTrue(abs(eq2x.minY - main2x.maxY) <= 1.0, "At 2x: EQ bottom must touch Main top with 0 gap")
        assertTrue(abs(pl2x.minY - eq2x.maxY) <= 1.0, "At 2x: Playlist bottom must touch EQ top with 0 gap (no gap/flying up)")

        // Scale 2x -> 1x
        wlm.setScale(1.0)
        assertEqual(wlm.currentScale, 1.0, "Scale factor should be 1.0")

        let main1x = winA.frame
        let eq1x = winB.frame
        let pl1x = winC.frame
        assertTrue(abs(eq1x.minY - main1x.maxY) <= 1.0, "At 1x: EQ bottom must touch Main top with 0 gap")
        assertTrue(abs(pl1x.minY - eq1x.maxY) <= 1.0, "At 1x: Playlist bottom must touch EQ top with 0 gap (no overlap)")

        // A wide playlist touches both side-by-side windows. Its left edge identifies the anchor.
        for mainOnLeft in [true, false] {
            let left = mainOnLeft ? winA : winB
            let right = mainOnLeft ? winB : winA
            left.setFrameOrigin(NSPoint(x: 300, y: 380))
            right.setFrameOrigin(NSPoint(x: left.frame.maxX, y: left.frame.minY))
            let playlistSize = NSSize(width: 550, height: 145)
            winC.setFrame(NSRect(origin: NSPoint(x: left.frame.minX, y: left.frame.minY - playlistSize.height),
                                 size: playlistSize), display: false)
            wlm.updateAdjacencies()

            for scale: CGFloat in [2, 1] {
                wlm.setScale(scale)
                assertEqual(right.frame.minX, left.frame.maxX, "Player and EQ stay side by side at \(scale)×")
                assertEqual(right.frame.maxY, left.frame.maxY, "Player and EQ stay top-aligned at \(scale)×")
                assertEqual(winC.frame.minX, left.frame.minX, "Wide playlist stays left-aligned at \(scale)×")
                assertEqual(winC.frame.maxY, left.frame.minY, "Wide playlist stays docked below at \(scale)×")
                assertEqual(winC.frame.size, playlistSize, "Playlist keeps its own size")
            }
        }

        let persistence = PersistenceManager.shared
        winA.setFrameOrigin(NSPoint(x: 100, y: 380))
        winB.setFrameOrigin(NSPoint(x: winA.frame.maxX, y: winA.frame.minY))
        winC.setFrameOrigin(NSPoint(x: winA.frame.minX, y: winA.frame.minY - winC.frame.height))
        wlm.updateAdjacencies()
        persistence.state.interfaceScale = .large
        for classicScale: CGFloat in [1, 2, 1] {
            wlm.setScale(classicScale)
            assertEqual(winA.frame.width, 413 * classicScale, "Double Size multiplies the interface scale")
            assertEqual(winB.frame.minX, winA.frame.maxX, "EQ stays docked at 150%")
            assertEqual(winC.frame.size, NSSize(width: 826, height: 218), "Each 275 px column of the playlist is rounded like a window")
            if classicScale == 1 {
                assertEqual(winC.frame.maxX, winB.frame.maxX, "The playlist's right edge matches the EQ's at 150%")
            } else {
                assertEqual(winC.frame.width, winA.frame.width, "The playlist is as wide as the doubled main window at 150%")
            }
            let logicalBounds = winC.contentView!.bounds
            assertTrue(abs(logicalBounds.width - 550) < 0.001 && abs(logicalBounds.height - 145) < 0.001,
                       "Playlist retains the skin's coordinates")
            assertEqual(winC.frame.minX, winA.frame.minX, "Wide playlist stays left-aligned at 150%")
            assertEqual(winC.frame.maxY, winA.frame.minY, "Wide playlist remains docked at 150%")
        }
        winC.setFrameOrigin(NSPoint(x: winC.frame.minX + 30, y: winC.frame.minY))
        wlm.endDrag(for: .playlist)
        assertEqual(winC.frame.width, 826, "The width doesn't depend on what the playlist is docked to")
        winB.orderOut(nil)
        persistence.state.interfaceScale = .standard
        wlm.setScale(1)
        assertEqual(winB.frame.size, NSSize(width: 275, height: 116), "Hidden EQ returns to 100%")
        winB.orderFront(nil)

        winB.setFrameOrigin(NSPoint(x: 650, y: 380))
        winC.setFrameOrigin(NSPoint(x: winB.frame.minX, y: winB.frame.minY - winC.frame.height))
        wlm.updateAdjacencies()
        persistence.state.interfaceScale = .large
        wlm.setScale(1)
        assertEqual(winC.frame.maxY, winB.frame.minY, "A group detached from Main stays docked")
        assertEqual(winC.frame.minX, winB.frame.minX, "Detached group keeps its left edge aligned")
        persistence.state.interfaceScale = .standard
        wlm.setScale(1)

        // Test onLayoutChanged callback trigger
        var layoutChangedFired = false
        wlm.onLayoutChanged = {
            layoutChangedFired = true
        }
        wlm.endDrag(for: .main)
        assertTrue(layoutChangedFired, "onLayoutChanged must be triggered when dragging ends")
    }

    // 2. Window Position & Layout Persistence Tests
    testGroup("Window Position & Layout Persistence") {
        let persistence = PersistenceManager.shared

        // Simulate user arranging windows in inverted layout: Playlist (top), EQ (middle), Main (bottom)
        let pFrame = NSRect(x: 350, y: 600, width: 275, height: 116)
        let eFrame = NSRect(x: 350, y: 484, width: 275, height: 116)
        let mFrame = NSRect(x: 350, y: 368, width: 275, height: 116)

        persistence.state.windowPositions["playlist"] = [Double(pFrame.minX), Double(pFrame.minY), Double(pFrame.width), Double(pFrame.height)]
        persistence.state.windowPositions["equalizer"] = [Double(eFrame.minX), Double(eFrame.minY), Double(eFrame.width), Double(eFrame.height)]
        persistence.state.windowPositions["main"] = [Double(mFrame.minX), Double(mFrame.minY), Double(mFrame.width), Double(mFrame.height)]
        persistence.state.scaleFactor = .x1
        persistence.state.isMainWindowShade = false
        persistence.state.isEqWindowShade = false
        persistence.state.isPlaylistShade = false
        persistence.state.isEqWindowVisible = true
        persistence.state.isPlaylistVisible = true
        persistence.state.isEqAuto = true
        persistence.state.autoGenreEQ = true
        persistence.saveSession()

        // Simulate relaunch by reading back the session state
        persistence.loadSession()
        assertTrue(persistence.state.isEqAuto, "isEqAuto must be persisted across sessions")
        assertTrue(persistence.state.autoGenreEQ, "autoGenreEQ must be persisted across sessions")
        let loaded = persistence.state.windowPositions
        assertTrue(loaded["playlist"] != nil, "Playlist position must be persisted")
        assertTrue(loaded["equalizer"] != nil, "Equalizer position must be persisted")
        assertTrue(loaded["main"] != nil, "Main window position must be persisted")

        let loadedP = loaded["playlist"]!
        let loadedE = loaded["equalizer"]!
        let loadedM = loaded["main"]!

        assertEqual(loadedP[0], 350.0, "Playlist X coordinate restored accurately")
        assertEqual(loadedP[1], 600.0, "Playlist Y coordinate restored accurately (top)")
        assertEqual(loadedE[0], 350.0, "Equalizer X coordinate restored accurately")
        assertEqual(loadedE[1], 484.0, "Equalizer Y coordinate restored accurately (middle)")
        assertEqual(loadedM[0], 350.0, "Main X coordinate restored accurately")
        assertEqual(loadedM[1], 368.0, "Main Y coordinate restored accurately (bottom)")

        // Verify vertical order: Playlist > Equalizer > Main
        assertTrue(loadedP[1] > loadedE[1], "Playlist must be positioned above Equalizer")
        assertTrue(loadedE[1] > loadedM[1], "Equalizer must be positioned above Main window")

        // Test that adjacency graph correctly identifies docking when windows are restored at these coordinates
        let wlm = WindowLayoutManager.shared
        let winA = NSWindow(contentRect: NSRect(x: loadedM[0], y: loadedM[1], width: loadedM[2], height: loadedM[3]), styleMask: .borderless, backing: .buffered, defer: false)
        let winB = NSWindow(contentRect: NSRect(x: loadedE[0], y: loadedE[1], width: loadedE[2], height: loadedE[3]), styleMask: .borderless, backing: .buffered, defer: false)
        let winC = NSWindow(contentRect: NSRect(x: loadedP[0], y: loadedP[1], width: loadedP[2], height: loadedP[3]), styleMask: .borderless, backing: .buffered, defer: false)

        wlm.register(window: winA, for: .main)
        wlm.register(window: winB, for: .equalizer)
        wlm.register(window: winC, for: .playlist)
        winA.orderFront(nil)
        winB.orderFront(nil)
        winC.orderFront(nil)
        wlm.updateAdjacencies()

        let group = wlm.findGroup(for: .main)
        assertTrue(group.contains(.main), "Restored group contains Main")
        assertTrue(group.contains(.equalizer), "Restored group contains Equalizer")
        assertTrue(group.contains(.playlist), "Restored group contains Playlist")
    }

    // 2b. Multi-Monitor Safety & Display Disconnect/Reconnect Tests
    testGroup("Multi-Monitor Safety & Display Disconnect/Reconnect") {
        let wlm = WindowLayoutManager.shared

        // 1. isRectVisibleOnAnyScreen tests
        let offscreenRect = NSRect(x: 99999, y: 99999, width: 275, height: 116)
        assertTrue(!wlm.isRectVisibleOnAnyScreen(offscreenRect), "Offscreen rect must NOT be reported as visible")

        if let screen = NSScreen.main {
            let onscreenRect = NSRect(x: screen.visibleFrame.midX - 100, y: screen.visibleFrame.midY - 50, width: 200, height: 100)
            assertTrue(wlm.isRectVisibleOnAnyScreen(onscreenRect), "Onscreen rect inside visibleFrame must be reported as visible")
        }

        // 2. Simulate windows on a disconnected secondary monitor
        let offX: CGFloat = 88000
        let offY: CGFloat = 88000
        let winM = NSWindow(contentRect: NSRect(x: offX, y: offY + 116, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
        let winE = NSWindow(contentRect: NSRect(x: offX, y: offY, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)

        wlm.register(window: winM, for: .main)
        wlm.register(window: winE, for: .equalizer)
        winM.orderFront(nil)
        winE.orderFront(nil)
        wlm.updateAdjacencies()

        // 3. Screen parameters changed (monitor disconnect)
        wlm.handleScreenParametersChanged()

        // Verify savedExternalPositions was recorded
        assertTrue(wlm.savedExternalPositions != nil, "savedExternalPositions must be populated when windows were on a disconnected screen")
        assertEqual(wlm.savedExternalPositions?[.main]?.x, offX, "Saved external X matches original offscreen coordinate")
        assertEqual(wlm.savedExternalPositions?[.main]?.y, offY + 116, "Saved external Y matches original offscreen coordinate")

        // Verify windows were relocated onto the visible screen
        assertTrue(wlm.isRectVisibleOnAnyScreen(winM.frame), "Main window must now be visible on an active screen")
        assertTrue(wlm.isRectVisibleOnAnyScreen(winE.frame), "Equalizer window must now be visible on an active screen")

        // Verify relative docking offset is preserved
        let deltaY = round(winM.frame.minY - winE.frame.maxY)
        assertEqual(deltaY, 0.0, "Docked windows must preserve adjacency on relocation")
        assertEqual(winM.frame.minX, winE.frame.minX, "Docked windows must preserve X alignment on relocation")

        // 4. Manual drag should cancel pending external restore
        _ = wlm.startDrag(for: .main)
        assertTrue(wlm.hasUserMovedWindowsSinceRelocation, "User manual drag marks windows as moved")
        assertTrue(wlm.savedExternalPositions == nil, "User manual drag clears saved external positions")
    }
}
