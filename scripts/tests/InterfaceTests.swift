import Cocoa
import Foundation
import AVFoundation
import CoreMedia
import Network
import UniformTypeIdentifiers
import SwiftUI
import CGoom
@testable import MacAmp

func interfaceTests() {
    // 8. ClutterBar (O, A, I, D, V) Controls Tests
    testGroup("ClutterBar 100% (O, A, I, D, V) Controls") {
        typealias Layout = AppConstants.MainWindow.Layout

        // 1. Verify layout geometry
        assertEqual(Layout.clutterBarBg, NSRect(x: 10, y: 22, width: 8, height: 43), "clutterBarBg rect")
        assertEqual(Layout.clutterOptionsButton, NSRect(x: 10, y: 25, width: 8, height: 8), "clutterOptionsButton rect")
        assertEqual(Layout.clutterAlwaysOnTopButton, NSRect(x: 10, y: 33, width: 8, height: 7), "clutterAlwaysOnTopButton rect")
        assertEqual(Layout.clutterFileInfoButton, NSRect(x: 10, y: 40, width: 8, height: 7), "clutterFileInfoButton rect")
        assertEqual(Layout.clutterDoubleSizeButton, NSRect(x: 10, y: 47, width: 8, height: 8), "clutterDoubleSizeButton rect")
        assertEqual(Layout.clutterVisualizerButton, NSRect(x: 10, y: 55, width: 8, height: 7), "clutterVisualizerButton rect")

        // 2. Verify MainWindowView subviews & initial states
        let mainView = MainWindowView()
        assertTrue(mainView.clutterOptionsButton != nil, "clutterOptionsButton exists")
        assertTrue(mainView.alwaysOnTopButton != nil, "alwaysOnTopButton exists")
        assertTrue(mainView.clutterFileInfoButton != nil, "clutterFileInfoButton exists")
        assertTrue(mainView.doubleSizeButton != nil, "doubleSizeButton exists")
        assertTrue(mainView.clutterVisualizerButton != nil, "clutterVisualizerButton exists")

        // Normal mode: all 5 are visible
        assertTrue(!mainView.clutterOptionsButton.isHidden, "Options visible in normal mode")
        assertTrue(!mainView.alwaysOnTopButton.isHidden, "AlwaysOnTop visible in normal mode")
        assertTrue(!mainView.clutterFileInfoButton.isHidden, "FileInfo visible in normal mode")
        assertTrue(!mainView.doubleSizeButton.isHidden, "DoubleSize visible in normal mode")
        assertTrue(!mainView.clutterVisualizerButton.isHidden, "Visualizer button visible in normal mode")

        // Shade mode: all 5 must be hidden
        mainView.isShadeMode = true
        assertTrue(mainView.clutterOptionsButton.isHidden, "Options hidden in shade mode")
        assertTrue(mainView.alwaysOnTopButton.isHidden, "AlwaysOnTop hidden in shade mode")
        assertTrue(mainView.clutterFileInfoButton.isHidden, "FileInfo hidden in shade mode")
        assertTrue(mainView.doubleSizeButton.isHidden, "DoubleSize hidden in shade mode")
        assertTrue(mainView.clutterVisualizerButton.isHidden, "Visualizer button hidden in shade mode")

        // 3. Test Visualizer Mode Cycling
        mainView.visualizer.mode = .spectrum
        assertEqual(mainView.visualizer.mode.next, .oscilloscope, "Spectrum -> Oscilloscope")
        assertEqual(VisualizerMode.oscilloscope.next, .off, "Oscilloscope -> Off")
        assertEqual(VisualizerMode.off.next, .spectrum, "Off -> Spectrum")
    }

    testGroup("TrueType Title Fits the LCD") {
        let state = PersistenceManager.shared.state
        defer {
            PersistenceManager.shared.state.marqueeFontMode = state.marqueeFontMode
            PersistenceManager.shared.state.desktopFontSize = state.desktopFontSize
            PersistenceManager.shared.state.desktopFontFamily = state.desktopFontFamily
        }
        PersistenceManager.shared.state.marqueeFontMode = .bitmap
        assertEqual(MarqueeView.preferredFrame.height, 6, "Bitmap font keeps the 6 px TEXT.BMP row")
        PersistenceManager.shared.state.marqueeFontMode = .desktop
        assertEqual(MarqueeView.preferredFrame, NSRect(x: 112, y: 24, width: 152, height: 12), "TrueType uses the whole LCD box")
        PersistenceManager.shared.state.desktopFontFamily = "Helvetica"
        let marquee = MarqueeView()
        marquee.fontSettingsChanged()
        for size in [8.0, 10.0, 14.0] {
            PersistenceManager.shared.state.desktopFontSize = size
            let font = marquee.trueTypeFont()
            assertTrue(font.ascender - font.descender <= marquee.bounds.height - 1, "\(Int(size)) pt: whole letters fit (glyph box \(font.ascender - font.descender) in \(marquee.bounds.height))")
        }
        PersistenceManager.shared.state.desktopFontSize = 8
        assertEqual(marquee.trueTypeFont().pointSize, 8, "A size that fits is not shrunk")
    }

    testGroup("Status Bar Menu Title") {
        let font = [NSAttributedString.Key.font: NSFont.menuFont(ofSize: 0)]
        let long = "▶ Шок видео! Гитара с одной наклейкой! Эксклюзив (нет) 2016 год [cdJzZETdxYY]"
        let cut = StatusBarManager.truncated(long, toWidth: 300)
        assertTrue(cut.hasSuffix("…") && cut.hasPrefix("▶ Шок видео!"), "Long title is cut at the end (\(cut))")
        assertTrue((cut as NSString).size(withAttributes: font).width <= 300, "Cut title fits the width")
        assertEqual(StatusBarManager.truncated("▶ Кино - Кукушка", toWidth: 300), "▶ Кино - Кукушка", "Short title unchanged")

        // In the menu bar menu a long title scrolls instead; a short one stands still and keeps the menu narrow
        let title = MenuTitleView()
        title.show(prefix: "▶ ", name: "Шок видео! Гитара с одной наклейкой! Эксклюзив (нет) 2016 год [cdJzZETdxYY]")
        assertTrue(title.scrolls, "Long title scrolls")
        assertEqual(title.frame.width, 300 + 2 * MenuTitleView.inset, "And takes the fixed width")
        title.offset = 40
        title.show(prefix: "❚❚ ", name: "Шок видео! Гитара с одной наклейкой! Эксклюзив (нет) 2016 год [cdJzZETdxYY]")
        assertEqual(title.offset, 40, "Pausing does not restart the scroll")
        title.show(prefix: "▶ ", name: "Кино - Кукушка")
        assertTrue(!title.scrolls && title.offset == 0 && title.frame.width < 200, "Short title stands still (\(title.frame.width))")
    }

    testGroup("ID3v1 '?' Placeholders") {
        var meta = AudioFileMetadata(url: URL(fileURLWithPath: "/tmp/Дилер.mp3"))
        meta.id3v2.title = "Дилер"
        meta.id3v2.album = "Не в фокусе"
        meta.id3v2.trackNumber = "1/10"
        meta.id3v1.hasTag = true
        meta.id3v1.title = "?????"           // what that file's v1 tag holds
        meta.id3v1.album = "?? ? ??????"
        meta.id3v1.artist = "Dolphin"
        meta.id3v1.year = "1997"
        meta.copyFromID3v1()
        assertEqual(meta.id3v2.title, "Дилер", "'?????' doesn't overwrite the real title")
        assertEqual(meta.id3v2.album, "Не в фокусе", "'?? ? ??????' doesn't overwrite the real album")
        assertEqual(meta.id3v2.artist, "Dolphin", "Real v1 text is still copied")
        assertEqual(meta.id3v2.year, "1997", "Year copied")
        assertEqual(meta.id3v2.trackNumber, "1/10", "Track 0 in v1 keeps the v2 track")
    }

    testGroup("Winamp 2.95 Menus and Shortcuts") {
        let c = PlayerCoordinator.shared
        if c.mainView == nil { c.start() }
        func titles(_ menu: NSMenu) -> [String] { menu.items.map { $0.isSeparatorItem ? "-" : $0.title } }
        func sub(_ menu: NSMenu, _ title: String) -> NSMenu { menu.items.first { $0.title == title }!.submenu! }
        @MainActor func key(_ chars: String, _ mods: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> Bool {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)!
            return c.handleKeyDown(event)
        }

        // Order and names as in docs/UI-screens/menu*.png
        let menu = c.buildWinampMenu()
        assertEqual(titles(menu), ["MacAmp...", "-", "Play", "View file info", "Bookmarks", "-", "Main Window", "Playlist Editor", "Equalizer",
                                   "Library", "Minibrowser", "Video", "-", "Options", "Playback", "Visualization", "Skins", "-", "Exit"], "Main menu order")
        assertEqual(Array(titles(sub(menu, "Play")).prefix(4)), ["File...", "Location...", "Directory...", "-"], "Play menu")
        assertTrue(titles(sub(menu, "Play")).contains("Bookmark"), "Play ▸ Bookmark")
        assertEqual(titles(sub(menu, "Options")), ["Preferences...", "Skins", "-", "Time elapsed (⌃T toggles)", "Time remaining (⌃T toggles)", "-",
                                                   "Always On Top", "Double Size", "EasyMove", "-", "Repeat", "Shuffle", "-", "Audio Output"],
                    "Options menu (Audio Output = MacAmp addition at the end)")
        assertEqual(titles(sub(menu, "Playback")), ["Previous", "Play", "Pause", "Stop", "Next", "-", "Stop w/ fadeout", "Stop after current",
                                                    "Back 5 seconds", "Fwd 5 seconds", "Start of list", "10 tracks back", "10 tracks fwd", "-",
                                                    "Jump to time", "Jump to file"], "Playback menu")
        assertEqual(titles(sub(menu, "Visualization")), ["Visualization options...", "-", "Start/Stop plug-in", "Configure plug-in...", "Select plug-in..."], "Visualization menu")
        let skins = titles(sub(menu, "Skins"))
        assertEqual(Array(skins.prefix(3)), ["Skin Browser...", "-", "<Base Skin>"], "Skins menu starts like 2.95")
        assertTrue(skins.contains("<< Get more skins! >>"), "Get more skins")
        let mainWindowItem = menu.items.first { $0.title == "Main Window" }!
        assertEqual(mainWindowItem.keyEquivalent, "w", "Main Window shows ⌥W")
        assertEqual(mainWindowItem.keyEquivalentModifierMask, [.option], "Main Window shows ⌥W")

        // Shortcuts shown in the menu work with the menu closed
        let mode = c.mainView.timeDisplay.mode
        assertTrue(key("t", [.control]), "⌃T handled")
        assertTrue(c.mainView.timeDisplay.mode != mode, "⌃T toggles elapsed / remaining")
        _ = key("t", [.control])
        let easy = PersistenceManager.shared.state.easyMove
        assertTrue(key("e", [.control]) && PersistenceManager.shared.state.easyMove != easy, "⌃E toggles EasyMove")
        _ = key("e", [.control])
        let eqOn = c.mainView.eqToggle.isOn
        assertTrue(key("g", [.option]) && c.mainView.eqToggle.isOn != eqOn, "⌥G toggles the equalizer")
        _ = key("g", [.option])
        assertTrue(key("w", [.option]) && c.mainWindow.isVisible == false, "⌥W hides the main window")
        assertTrue(key("w", [.option]) && c.mainWindow.isVisible, "⌥W shows it again")

        // Start of list, 10 tracks back / fwd (clamped at the ends)
        let wav = try makeTestWAV(named: "menu-jump.wav", seconds: 3.0)
        let saved = c.playlist.tracks
        defer { c.audioEngine.stop(); c.playlist.clear(); c.playlist.add(tracks: saved) }
        c.playlist.clear()
        c.playlist.add(tracks: (0..<15).map { TrackItem(url: wav, title: "t\($0)", duration: 3) })
        c.playlist.currentIndex = 3
        c.handleTenTracksForward()
        assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 13 }, timeout: 3), "10 tracks fwd: 3 -> 13")
        c.handleTenTracksForward()
        assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 14 }, timeout: 3), "10 tracks fwd stops at the last track")
        c.handleTenTracksBack()
        assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 4 }, timeout: 3), "10 tracks back: 14 -> 4")
        assertTrue(key("z", [.control]), "⌃Z handled")
        assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 0 }, timeout: 3), "⌃Z: start of list")

        // Playlist item menu (docs/UI-screens/playlist item menu.png)
        let pl = c.plView!
        let rowPoint = pl.convert(NSPoint(x: 40, y: AppConstants.Playlist.Layout.topBarHeight + 4), to: nil)
        let click = NSEvent.mouseEvent(with: .rightMouseDown, location: rowPoint, modifierFlags: [], timestamp: 0,
                                       windowNumber: pl.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let itemMenu = pl.menu(for: click)!
        assertEqual(titles(itemMenu), ["Play item(s)", "-", "Remove item(s)", "Crop files", "-", "File info", "Playlist entry", "Bookmark item(s)"],
                    "Playlist item menu order")
        assertEqual(PlayerCoordinator.mountedAudioCDs().filter { !FileManager.default.fileExists(atPath: $0.appendingPathComponent(".TOC.plist").path) }, [],
                    "Only volumes with a CD table of contents count as audio CDs")
    }

    testGroup("Track Info: Winamp 2.95 Single Screen") {
        // "?" placeholders that broken taggers leave in ID3v1 instead of Cyrillic
        assertTrue(ID3v1Tag.isPlaceholder("?????") && ID3v1Tag.isPlaceholder("?? ? ??????"), "'?' runs are placeholders")
        assertTrue(!ID3v1Tag.isPlaceholder("Dolphin") && !ID3v1Tag.isPlaceholder("") && !ID3v1Tag.isPlaceholder("Why? Because"), "Real text is not")

        // Frame count like Winamp's "56kbit, 205 frames"
        var tech = AudioTechnicalInfo()
        tech.duration = 5.0; tech.sampleRate = 22050; tech.samplesPerFrame = 576 // MPEG 2.0 layer 3
        assertEqual(tech.frameCount, 191, "Frames = length x rate / samples per frame")
        tech.samplesPerFrame = 0
        assertEqual(tech.frameCount, 0, "No MPEG header: no frame count")

        // MP3 shows ID3v1 + MPEG info; other formats only the tag group, and the box fits its content
        var mp3 = AudioFileMetadata(url: URL(fileURLWithPath: "/tmp/x.mp3"))
        mp3.techInfo.isMPEG = true
        let flac = AudioFileMetadata(url: URL(fileURLWithPath: "/tmp/x.flac"))
        func fitting(_ meta: AudioFileMetadata) -> NSSize {
            let host = NSHostingView(rootView: TrackInfoView(viewModel: TrackInfoViewModel(metadata: meta)))
            return host.fittingSize
        }
        let mp3Size = fitting(mp3), flacSize = fitting(flac)
        assertTrue(mp3Size.width >= 600 && mp3Size.height > 380 && mp3Size.height < 520, "MP3 box is compact like 2.95 (\(mp3Size))")
        assertTrue(flacSize.height <= mp3Size.height, "Non-MP3 box has no ID3v1 group (\(flacSize))")
        var deep = AudioFileMetadata(url: URL(fileURLWithPath: "/Volumes/share/" + String(repeating: "long folder name/", count: 20) + "x.mp3"))
        deep.techInfo.isMPEG = true
        assertEqual(fitting(deep), mp3Size, "A long path does not widen the box")

        // A genre picked from the list replaces the text even while the genre field has the keyboard focus
        let genreModel = TrackInfoViewModel(metadata: mp3)
        let genreHost = NSHostingView(rootView: TrackInfoView(viewModel: genreModel))
        let genreWindow = NSWindow(contentRect: NSRect(origin: .zero, size: genreHost.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
        genreWindow.contentView = genreHost
        genreHost.layoutSubtreeIfNeeded()
        func textFields(in view: NSView) -> [NSTextField] { view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? textFields(in: $0) } }
        genreModel.metadata.id3v2.hasTag = true
        genreModel.metadata.id3v2.genre = "Punk"
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if let field = textFields(in: genreHost).first(where: { $0.stringValue == "Punk" }) {
            genreWindow.makeFirstResponder(field)
            assertTrue(field.currentEditor() != nil, "Genre field is being edited")
            genreModel.metadata.id3v2.genre = "Rock"
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            assertEqual(field.stringValue, "Rock", "Picked genre shown in the focused field")
        } else {
            assertTrue(false, "Genre field found")
        }

        // The ID3v2 genre arrow shows no text, but its list must still name every genre (was a list of blank rows)
        var genre = "Rock"
        let arrow = Win32ComboBox(selection: Binding(get: { genre }, set: { genre = $0 }),
                                  options: ID3Genre.allGenres.map { (value: $0, title: $0) }, label: "")
        let list = arrow.buildMenu()
        assertEqual(list.items.count, ID3Genre.allGenres.count, "Every genre listed")
        assertTrue(list.items.allSatisfy { !$0.title.isEmpty }, "No blank rows in the genre list")
        assertEqual(list.items.first { $0.state == .on }?.title, "Rock", "Current genre checked")
    }

    testGroup("Preferences Tree as in Winamp 2.95") {
        assertEqual(PrefTreeItem.topLevel.map(\.title), ["Setup", "Options", "Plug-ins", "Skins", "Bookmarks"], "Top-level nodes, each a page")
        assertEqual(PrefTreeItem.setup.children.map(\.title), ["File types", "Agent"], "Setup children")
        assertEqual(PrefTreeItem.options.children.map(\.title), ["Display", "Visualization", "Shuffle", "Video", "Library", "CD Ripping"], "Options children, as in 2.95")
        assertEqual(PrefTreeItem.plugins.children.map(\.title), ["Input", "Output", "Visualization", "DSP/Effect", "General Purpose"], "Plug-ins children")
        // Every page renders
        let vm = PreferencesViewModel()
        for item in PrefTreeItem.allCases {
            vm.selectedTreeItem = item
            let host = NSHostingView(rootView: PreferencesView(viewModel: vm))
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 440)
            host.layoutSubtreeIfNeeded()
            assertTrue(host.fittingSize.width > 0, "\(item.title) page renders")
        }

        // Options ▸ Convert %20 / underscore (titles that are file names)
        let state = PersistenceManager.shared.state
        defer { PersistenceManager.shared.state.convertPercent20 = state.convertPercent20; PersistenceManager.shared.state.convertUnderscore = state.convertUnderscore }
        PersistenceManager.shared.state.convertPercent20 = true
        PersistenceManager.shared.state.convertUnderscore = true
        assertEqual(TrackItem.displayName(artist: "", title: "My_Song%20Live"), "My Song Live", "File-name titles get spaces")
        assertEqual(TrackItem.displayName(artist: "AC_DC", title: "Back_In"), "AC_DC - Back_In", "Tagged titles are left alone")
        PersistenceManager.shared.state.convertUnderscore = false
        assertEqual(TrackItem.displayName(artist: "", title: "My_Song%20Live"), "My_Song Live", "Underscore conversion can be turned off")
    }

    testGroup("Winamp 2.95 Hotkeys: Playlist, Equalizer, Keypad") {
        let c = PlayerCoordinator.shared
        if c.mainView == nil { c.start() }
        let saved = c.playlist.tracks
        defer { c.audioEngine.stop(); c.playlist.clear(); c.playlist.add(tracks: saved) }
        @MainActor func names() -> [String] { c.playlist.tracks.map(\.title) }
        c.playlist.clear()
        c.playlist.add(tracks: ["c", "a", "e", "b", "d"].map { TrackItem(url: URL(fileURLWithPath: "/tmp/\($0).mp3"), title: $0) })

        // ⌥↑ / ⌥↓ move the selection with the current track
        c.playlist.selectedIndices = [1, 2]
        c.playlist.currentIndex = 2
        let pl = c.plView!
        assertTrue(pl.handlePlaylistKey(keyCode: AppConstants.KeyCodes.upArrow, characters: "", flags: [.option]), "⌥↑ handled")
        assertEqual(names(), ["a", "e", "c", "b", "d"], "⌥↑ moves the selected block up")
        assertEqual(c.playlist.selectedIndices, [0, 1], "Selection follows")
        assertEqual(c.playlist.currentTrack?.title, "e", "Current track follows")
        _ = pl.handlePlaylistKey(keyCode: AppConstants.KeyCodes.upArrow, characters: "", flags: [.option])
        assertEqual(names(), ["a", "e", "c", "b", "d"], "Already at the top: nothing moves")
        _ = pl.handlePlaylistKey(keyCode: AppConstants.KeyCodes.downArrow, characters: "", flags: [.option])
        assertEqual(names(), ["c", "a", "e", "b", "d"], "⌥↓ moves it back down")

        // Sorting and order keys
        assertTrue(pl.handlePlaylistKey(keyCode: AppConstants.KeyCodes.digit1, characters: "!", flags: [.control, .shift]), "⌃⇧1 handled")
        assertEqual(names(), ["a", "b", "c", "d", "e"], "⌃⇧1 sorts by title")
        _ = pl.handlePlaylistKey(keyCode: 15, characters: "r", flags: [.control])
        assertEqual(names(), ["e", "d", "c", "b", "a"], "⌃R reverses")
        c.playlist.selectedIndices = [0]
        _ = pl.handlePlaylistKey(keyCode: 34, characters: "i", flags: [.control])
        assertEqual(c.playlist.selectedIndices, [1, 2, 3, 4], "⌃I inverts the selection")

        // Equalizer keys
        let eq = c.eqView!
        let band = eq.bandSliders[0].value, lowBand = eq.bandSliders[9].value, preamp = eq.preampSlider.value
        assertTrue(eq.handleEqualizerKey(characters: "1", keyCode: 18, flags: []), "1 handled in the equalizer")
        assertEqual(eq.bandSliders[0].value, min(12, band + 1), "1 raises the 60 Hz band")
        _ = eq.handleEqualizerKey(characters: "p", keyCode: 35, flags: [])
        assertEqual(eq.bandSliders[9].value, max(-12, lowBand - 1), "P lowers the 16 kHz band")
        _ = eq.handleEqualizerKey(characters: "`", keyCode: 50, flags: [])
        assertEqual(eq.preampSlider.value, min(12, preamp + 1), "` raises the preamp")
        _ = eq.handleEqualizerKey(characters: "\t", keyCode: AppConstants.KeyCodes.tab, flags: [])
        assertEqual(eq.preampSlider.value, preamp, "Tab lowers it again")
        let eqOn = eq.onToggle.isOn
        _ = eq.handleEqualizerKey(characters: "n", keyCode: 45, flags: [])
        assertTrue(eq.onToggle.isOn != eqOn, "N toggles the equalizer")
        _ = eq.handleEqualizerKey(characters: "n", keyCode: 45, flags: [])  // back on
        // Put the curve back as it was
        for (slider, value) in [(eq.bandSliders[0], band), (eq.bandSliders[9], lowBand)] {
            slider.value = value
            slider.onValueChanged?(value)
        }
        assertTrue(!eq.handleEqualizerKey(characters: "x", keyCode: 7, flags: []), "Other keys fall through to playback (X = Play)")

        // Keypad
        let wav = try makeTestWAV(named: "keypad.wav", seconds: 3.0)
        c.playlist.clear()
        c.playlist.add(tracks: (0..<12).map { TrackItem(url: wav, title: "k\($0)", duration: 3) })
        c.playlist.currentIndex = 0
        assertTrue(c.handleWinampGlobalKey(keyCode: AppConstants.KeyCodes.keypad3, flags: [.numericPad]), "Num 3 handled")
        assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 10 }, timeout: 3), "Num 3: ten tracks forward")
        assertTrue(c.handleWinampGlobalKey(keyCode: AppConstants.KeyCodes.keypad6, flags: [.numericPad]), "Num 6 handled")
        assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 11 }, timeout: 3), "Num 6: next track")
        assertTrue(!c.handleWinampGlobalKey(keyCode: 0, flags: []), "Plain A isn't a global key")
    }

    testGroup("Winamp 2.95 Main Window Controls and Small Options") {
        let c = PlayerCoordinator.shared
        if c.mainView == nil { c.start() }
        func items(_ view: WinampControlView) -> [String] {
            (view.contextMenuProvider?().items ?? []).map { $0.attributedTitle?.string ?? $0.title }
        }
        // Right-click menus of the transport buttons, as in 2.95 (strings from winamp.exe)
        assertEqual(items(c.mainView.prevButton), ["Previous\t(Click)", "Start of list\t(⌃Click)", "Rewind 5 seconds\t(⇧Click)"], "Previous button menu")
        assertEqual(items(c.mainView.stopButton), ["Stop\t(Click)", "Stop w/ fadeout\t(⇧Click)", "Stop after current\t(⌃Click)"], "Stop button menu")
        assertEqual(items(c.mainView.nextButton), ["Next\t(Click)", "Fastforward 5 seconds\t(⇧Click)", "End of list\t(⌃Click)"], "Next button menu")
        assertEqual(items(c.mainView.ejectButton), ["Open file...\t(Click)", "Open directory...\t(⇧Click)", "Open location...\t(⌃Click)"], "Eject button menu")
        assertEqual(items(c.mainView.timeDisplay), ["Time elapsed\t(⌃T toggles)", "Time remaining\t(⌃T toggles)"], "Time display menu")
        assertEqual(items(c.mainView.marquee).last, "Autoscroll songname", "Song title menu ends with Autoscroll songname")

        // Tooltips and title dimming switches
        let state = PersistenceManager.shared.state
        defer {
            PersistenceManager.shared.state.mainWindowTooltips = state.mainWindowTooltips
            PersistenceManager.shared.state.dimTitlebars = state.dimTitlebars
            c.applyMainWindowTooltips()
        }
        PersistenceManager.shared.state.mainWindowTooltips = true
        c.applyMainWindowTooltips()
        assertEqual(c.mainView.prevButton.toolTip, "Previous", "Tooltip on")
        PersistenceManager.shared.state.mainWindowTooltips = false
        c.applyMainWindowTooltips()
        assertTrue(c.mainView.prevButton.toolTip == nil, "Tooltips off")
        PersistenceManager.shared.state.dimTitlebars = false
        assertTrue(c.mainView.drawsActiveTitleBar, "No dimming: title bar always drawn active")

        // Shuffle morph rate: same tracks every pass; slow keeps most of the order, fast reshuffles
        let ids = (0..<50).map { _ in UUID() }
        let fast = PlaylistModel.morphedOrder(ids, rate: 1)
        assertEqual(Set(fast), Set(ids), "Fast pass has every track once")
        let slow = PlaylistModel.morphedOrder(ids, rate: 0)
        assertEqual(Set(slow), Set(ids), "Slow pass has every track once")
        let unchanged = zip(slow, ids).filter { $0 == $1 }.count
        assertTrue(unchanged >= 48, "Slow morph: a slight variation (\(unchanged)/50 in place)")

        // End of list (⌃-click Next)
        let wav = try makeTestWAV(named: "endlist.wav", seconds: 3.0)
        let saved = c.playlist.tracks
        defer { c.audioEngine.stop(); c.playlist.clear(); c.playlist.add(tracks: saved) }
        c.playlist.clear()
        c.playlist.add(tracks: (0..<5).map { TrackItem(url: wav, title: "e\($0)", duration: 3) })
        c.playlist.currentIndex = 0
        c.handleEndOfList()
        assertTrue(spinRunLoop(until: { c.playlist.currentIndex == 4 }, timeout: 3), "End of list plays the last track")
    }

    testGroup("Preferences ▸ Skins (2.95 page)") {
        assertTrue(SkinManager.skinDescription(of: nil).contains("base skin"), "Base skin described")
        // A skin archive with its author's readme and a config .txt
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macamp-tests/skins-\(UUID().uuidString)", isDirectory: true)
        let src = dir.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "Cool Skin v1.0 by Someone".write(to: src.appendingPathComponent("README.TXT"), atomically: true, encoding: .utf8)
        try "[Text]\nNormal=#00FF00".write(to: src.appendingPathComponent("pledit.txt"), atomically: true, encoding: .utf8)
        let skin = dir.appendingPathComponent("Cool.wsz")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = src
        zip.arguments = ["-q", skin.path, "README.TXT", "pledit.txt"]
        try zip.run(); zip.waitUntilExit()
        assertEqual(SkinManager.skinDescription(of: skin), "Cool Skin v1.0 by Someone", "Description is the skin's readme, not its config")
        // "Set skins directory...": the list comes from that folder
        let previous = PersistenceManager.shared.state.skinsDirectoryPath
        PersistenceManager.shared.state.skinsDirectoryPath = dir.path
        assertEqual(SkinManager.shared.installedSkins().map(\.lastPathComponent), ["Cool.wsz"], "Skins listed from the chosen folder")
        PersistenceManager.shared.state.skinsDirectoryPath = previous
    }

    testGroup("About: Keyboard shortcuts tab") {
        let all = AboutShortcuts.sections.flatMap(\.rows)
        assertEqual(AboutShortcuts.sections.count, 7, "2.95 sections plus Library and Video")
        for keys in ["⌥L", "⌥T", "⌥V", "⌃Tab", "F1", "⌥3"] { assertTrue(all.contains { $0.keys == keys || $0.keys.hasPrefix(keys + " ") }, "\(keys) listed") }
        assertTrue(!all.contains { $0.keys.contains("Ctrl") || $0.keys.contains("Alt+") }, "Mac notation only")
    }

    testGroup("MacAmp page links, CD Ripping AAC bitrate") {
        assertEqual(AppConstants.App.pluginsPage.absoluteString, "https://alexrel.com/macamp#plugins", "Get plug-ins goes to the MacAmp page")

        // CD Ripping ▸ AAC bitrate: a lower bitrate gives a smaller file
        let wav = try makeTestWAV(named: "aac-src.wav", seconds: 3.0)
        let folder = wav.deletingLastPathComponent().appendingPathComponent("aac-quality", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        @MainActor func size(_ kbps: Int) -> Int {
            let out = awaitValue { try? await DiskWriter.write(TrackItem(url: wav, title: "Q"), to: folder, name: "q\(kbps)", format: .aac, aacKbps: kbps) }
            return (out.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }) ?? 0
        }
        let low = size(128), high = size(320)
        assertTrue(low > 0 && high > low, "AAC 320 kbps file bigger than 128 kbps (\(high) > \(low))")
        assertEqual(PersistenceManager.shared.state.cdRipAACKbps, 256, "AAC default stays 256 kbps")
    }

    testGroup("Options and Display leftovers of 2.95: sort on load, Clutterbar, playlist font size") {
        let state = PersistenceManager.shared.state
        defer { PersistenceManager.shared.state = state }
        let wav = try makeTestWAV(named: "aac-src.wav", seconds: 3.0)
        let folder = wav.deletingLastPathComponent().appendingPathComponent("sort-on-load", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Display ▸ Playlist font size: rows follow it, within limits
        assertEqual(AppConstants.Playlist.trackRowHeight, 13, "2.95 default 10 → 13 px rows")
        PersistenceManager.shared.state.playlistFontSize = 12
        assertEqual(AppConstants.Playlist.trackRowHeight, 15, "Font 12 → 15 px rows")
        PersistenceManager.shared.state.playlistFontSize = 100
        assertEqual(PersistenceManager.shared.state.playlistFontSize, 24, "Font size capped")
        PersistenceManager.shared.state.playlistFontSize = 10

        // Display ▸ Always show Clutterbar off: the buttons appear only under the mouse
        let main = MainWindowView()
        assertTrue(main.clutterbarShown && !main.doubleSizeButton.isHidden, "Shown by default, as in 2.95")
        PersistenceManager.shared.state.alwaysShowClutterbar = false
        main.updateClutterbar()
        assertTrue(!main.clutterbarShown && main.doubleSizeButton.isHidden && main.clutterOptionsButton.isHidden, "Hidden away from the mouse")
        assertTrue(SkinManager.shared.image(for: SpriteCatalog.clutterBarHidden) != nil, "Empty strip from TITLEBAR.BMP")
        PersistenceManager.shared.state.alwaysShowClutterbar = true
        main.updateClutterbar()
        assertTrue(!main.doubleSizeButton.isHidden, "Shown again")

        // Options ▸ Sort files on load
        let b = folder.appendingPathComponent("b.wav"), a = folder.appendingPathComponent("a10.wav"), c = folder.appendingPathComponent("a9.wav")
        for f in [b, a, c] { try? FileManager.default.copyItem(at: wav, to: f) }
        @MainActor func loaded() -> [String] { awaitValue { await PlayerCoordinator.shared.collectTracks(fromPaths: [b, a, c].map(\.path)) }.map(\.url.lastPathComponent) }
        assertEqual(loaded(), ["b.wav", "a10.wav", "a9.wav"], "Off: the order given")
        PersistenceManager.shared.state.sortFilesOnLoad = true
        assertEqual(loaded(), ["a9.wav", "a10.wav", "b.wav"], "On: by name, numbers as numbers")
    }

    testGroup("Options: Equalizer doublesize linked, Single-click playlist buttons; Display: Show MacAmp in") {
        let state = PersistenceManager.shared.state
        defer { PersistenceManager.shared.state = state }

        // Equalizer doublesize linked off: the EQ stays 275x116 under a doubled main window, still docked
        assertTrue(!WindowID.equalizer.keepsOwnSize, "Linked by default, as in 2.95")
        let wlm = WindowLayoutManager.shared
        wlm.setScale(1)
        let main = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
        let eq = NSWindow(contentRect: NSRect(x: 100, y: 184, width: 275, height: 116), styleMask: .borderless, backing: .buffered, defer: false)
        wlm.register(window: main, for: .main)
        wlm.register(window: eq, for: .equalizer)
        main.orderFront(nil); eq.orderFront(nil)
        wlm.updateAdjacencies()
        PersistenceManager.shared.state.eqDoubleSizeLinked = false
        wlm.setScale(2)
        assertEqual(main.frame.size, NSSize(width: 550, height: 232), "Main doubled")
        assertEqual(eq.frame.size, NSSize(width: 275, height: 116), "EQ stays at 1x")
        assertTrue(abs(eq.frame.maxY - main.frame.minY) <= 1 && abs(eq.frame.minX - main.frame.minX) <= 1, "EQ still docked under the main window")
        wlm.setScale(1)
        PersistenceManager.shared.state.eqDoubleSizeLinked = true
        wlm.setScale(2)
        assertEqual(eq.frame.size, NSSize(width: 550, height: 232), "Linked: EQ doubles with the main window")
        wlm.setScale(1)
        main.orderOut(nil); eq.orderOut(nil)

        // Playlist button menus: press, drag to an item, release runs it; release on the button keeps the menu open
        var ran: [String] = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        let button = NSView(frame: NSRect(x: 0, y: 0, width: 25, height: 18))
        window.contentView?.addSubview(button)
        func popup() -> SkinnedPopupMenuView {
            let p = SkinnedPopupMenuView(bar: SpriteCatalog.plAddMenuBar, items: ["URL", "DIR", "FILE"].map { name in
                SkinnedMenuItem(normal: SpriteCatalog.plAddUrl, selected: SpriteCatalog.plAddUrlSelected) { ran.append(name) } })
            p.frame = NSRect(x: 0, y: 30, width: 25, height: 54)
            window.contentView?.addSubview(p)
            return p
        }
        func event(_ type: NSEvent.EventType, _ view: NSView, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let menu = popup()
        let dir = NSPoint(x: 10, y: 27) // the middle row, flipped or not
        menu.track(event(.leftMouseDragged, menu, dir), from: button)
        assertEqual(menu.hoveredIndex, 1, "Dragging over an item lights it")
        menu.track(event(.leftMouseUp, menu, dir), from: button)
        assertTrue(ran == ["DIR"] && menu.superview == nil, "Release on the item runs it and closes the menu")
        let kept = popup()
        kept.track(event(.leftMouseUp, button, NSPoint(x: 5, y: 5)), from: button)
        assertTrue(kept.superview != nil && ran.count == 1, "Release on the button: menu stays open for a click")
        kept.track(event(.leftMouseUp, button, NSPoint(x: 90, y: 5)), from: button)
        assertTrue(kept.superview == nil && ran.count == 1, "Release elsewhere closes it, nothing runs")
        assertEqual(kept.itemIndex(at: NSPoint(x: 10, y: -1)), nil, "Just above the menu isn't the first item")

        let pl = PlaylistWindowView(playlist: PlaylistModel())
        assertTrue(pl.addButton.dragAfterPress != nil && pl.listButton.dragAfterPress != nil, "2.95: menus open on press")
        PersistenceManager.shared.state.playlistSingleClickButtons = true
        pl.applyMenuButtonMode()
        assertTrue(pl.addButton.dragAfterPress == nil && pl.listButton.dragAfterPress == nil, "Old-school: click to open, click to pick")

        // Show MacAmp in: Dock and menu bar by default (what MacAmp did before the option)
        assertTrue(state.showDockIcon && PersistenceManager.shared.state.showMenuBarIcon, "Dock and menu bar by default")
    }
}
