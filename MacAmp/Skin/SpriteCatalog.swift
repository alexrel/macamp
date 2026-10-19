import Foundation
import CoreGraphics

public struct SpriteSlice {
    public let name: String
    public let sheet: String
    public let rect: CGRect
    
    public init(_ name: String, _ sheet: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        self.name = name
        self.sheet = sheet
        self.rect = CGRect(x: x, y: y, width: w, height: h)
    }
}

public enum SpriteCatalog {
    
    // MARK: - MAIN.BMP
    public static let mainWindowBackground = SpriteSlice("MAIN_BG", "MAIN", 0, 0, 275, 116)
    
    // MARK: - CBUTTONS.BMP (Transport buttons)
    public static let prevNormal = SpriteSlice("PREV", "CBUTTONS", 0, 0, 23, 18)
    public static let prevPressed = SpriteSlice("PREV_P", "CBUTTONS", 0, 18, 23, 18)
    
    public static let playNormal = SpriteSlice("PLAY", "CBUTTONS", 23, 0, 23, 18)
    public static let playPressed = SpriteSlice("PLAY_P", "CBUTTONS", 23, 18, 23, 18)
    
    public static let pauseNormal = SpriteSlice("PAUSE", "CBUTTONS", 46, 0, 23, 18)
    public static let pausePressed = SpriteSlice("PAUSE_P", "CBUTTONS", 46, 18, 23, 18)
    
    public static let stopNormal = SpriteSlice("STOP", "CBUTTONS", 69, 0, 23, 18)
    public static let stopPressed = SpriteSlice("STOP_P", "CBUTTONS", 69, 18, 23, 18)
    
    public static let nextNormal = SpriteSlice("NEXT", "CBUTTONS", 92, 0, 22, 18)
    public static let nextPressed = SpriteSlice("NEXT_P", "CBUTTONS", 92, 18, 22, 18)
    
    public static let ejectNormal = SpriteSlice("EJECT", "CBUTTONS", 114, 0, 22, 16)
    public static let ejectPressed = SpriteSlice("EJECT_P", "CBUTTONS", 114, 16, 22, 16)
    
    // MARK: - TITLEBAR.BMP
    public static let titleBarNormal = SpriteSlice("TITLEBAR", "TITLEBAR", 27, 15, 275, 14)
    public static let titleBarSelected = SpriteSlice("TITLEBAR_SEL", "TITLEBAR", 27, 0, 275, 14)
    
    public static let optionsNormal = SpriteSlice("OPTIONS", "TITLEBAR", 0, 0, 9, 9)
    public static let optionsPressed = SpriteSlice("OPTIONS_P", "TITLEBAR", 0, 9, 9, 9)
    
    public static let minimizeNormal = SpriteSlice("MINIMIZE", "TITLEBAR", 9, 0, 9, 9)
    public static let minimizePressed = SpriteSlice("MINIMIZE_P", "TITLEBAR", 9, 9, 9, 9)
    
    public static let shadeNormal = SpriteSlice("SHADE", "TITLEBAR", 0, 18, 9, 9)
    public static let shadePressed = SpriteSlice("SHADE_P", "TITLEBAR", 9, 18, 9, 9)
    
    public static let closeNormal = SpriteSlice("CLOSE", "TITLEBAR", 18, 0, 9, 9)
    public static let closePressed = SpriteSlice("CLOSE_P", "TITLEBAR", 18, 9, 9, 9)
    
    // ClutterBar (O, A, I, D, V)
    public static let clutterBarBg = SpriteSlice("CLUTTER_BG", "TITLEBAR", 304, 0, 8, 43)
    public static let clutterOActive = SpriteSlice("CLUTTER_O", "TITLEBAR", 304, 47, 8, 8)
    public static let clutterAActive = SpriteSlice("CLUTTER_A", "TITLEBAR", 312, 55, 8, 7)
    public static let clutterIActive = SpriteSlice("CLUTTER_I", "TITLEBAR", 320, 62, 8, 7)
    public static let clutterDActive = SpriteSlice("CLUTTER_D", "TITLEBAR", 328, 69, 8, 8)
    public static let clutterVActive = SpriteSlice("CLUTTER_V", "TITLEBAR", 336, 77, 8, 7)
    
    // Shade mode sprites
    public static let mainShadeBg = SpriteSlice("MAIN_SHADE_BG", "TITLEBAR", 27, 42, 275, 14)
    public static let mainShadeBgSelected = SpriteSlice("MAIN_SHADE_BG_SEL", "TITLEBAR", 27, 29, 275, 14)
    public static let mainShadeButtonSelected = SpriteSlice("MAIN_SHADE_BTN_SEL", "TITLEBAR", 0, 27, 9, 9)
    public static let mainShadeButtonSelectedDepressed = SpriteSlice("MAIN_SHADE_BTN_SEL_P", "TITLEBAR", 9, 27, 9, 9)
    public static let mainShadePosBg = SpriteSlice("MAIN_SHADE_POS_BG", "TITLEBAR", 0, 36, 17, 7)
    public static let mainShadePosThumb = SpriteSlice("MAIN_SHADE_POS_THUMB", "TITLEBAR", 20, 36, 3, 7)
    public static let mainShadePosThumbLeft = SpriteSlice("MAIN_SHADE_POS_THUMB_L", "TITLEBAR", 17, 36, 3, 7)
    public static let mainShadePosThumbRight = SpriteSlice("MAIN_SHADE_POS_THUMB_R", "TITLEBAR", 23, 36, 3, 7)
    
    // MARK: - VOLUME.BMP (68 x 420, 28 vertical frames of 68x13 with 15px pitch, thumb at y=422)
    public static func volumeBg(frame: Int) -> SpriteSlice {
        let clamped = max(0, min(27, frame))
        return SpriteSlice("VOL_BG_\(clamped)", "VOLUME", 0, CGFloat(clamped * 15), 68, 13)
    }
    public static let volumeThumb = SpriteSlice("VOL_THUMB", "VOLUME", 15, 422, 14, 11)
    public static let volumeThumbPressed = SpriteSlice("VOL_THUMB_P", "VOLUME", 0, 422, 14, 11)
    
    // MARK: - BALANCE.BMP (38 x 420, 28 vertical frames of 38x13 with 15px pitch, thumb at y=422)
    public static func balanceBg(frame: Int) -> SpriteSlice {
        let clamped = max(0, min(27, frame))
        return SpriteSlice("BAL_BG_\(clamped)", "BALANCE", 9, CGFloat(clamped * 15), 38, 13)
    }
    public static let balanceThumb = SpriteSlice("BAL_THUMB", "BALANCE", 15, 422, 14, 11)
    public static let balanceThumbPressed = SpriteSlice("BAL_THUMB_P", "BALANCE", 0, 422, 14, 11)
    
    // MARK: - POSBAR.BMP (Position seek bar)
    public static let posBarBg = SpriteSlice("POS_BG", "POSBAR", 0, 0, 248, 10)
    public static let posBarThumb = SpriteSlice("POS_THUMB", "POSBAR", 248, 0, 29, 10)
    public static let posBarThumbPressed = SpriteSlice("POS_THUMB_P", "POSBAR", 278, 0, 29, 10)
    
    // MARK: - SHUFREP.BMP (Shuffle, Repeat, EQ, Playlist toggles)
    public static let shuffleOff = SpriteSlice("SHUF_OFF", "SHUFREP", 28, 0, 47, 15)
    public static let shuffleOffPressed = SpriteSlice("SHUF_OFF_P", "SHUFREP", 28, 15, 47, 15)
    public static let shuffleOn = SpriteSlice("SHUF_ON", "SHUFREP", 28, 30, 47, 15)
    public static let shuffleOnPressed = SpriteSlice("SHUF_ON_P", "SHUFREP", 28, 45, 47, 15)
    
    public static let repeatOff = SpriteSlice("REP_OFF", "SHUFREP", 0, 0, 28, 15)
    public static let repeatOffPressed = SpriteSlice("REP_OFF_P", "SHUFREP", 0, 15, 28, 15)
    public static let repeatOn = SpriteSlice("REP_ON", "SHUFREP", 0, 30, 28, 15)
    public static let repeatOnPressed = SpriteSlice("REP_ON_P", "SHUFREP", 0, 45, 28, 15)
    
    public static let eqToggleOff = SpriteSlice("EQ_OFF", "SHUFREP", 0, 61, 23, 12)
    public static let eqToggleOn = SpriteSlice("EQ_ON", "SHUFREP", 0, 73, 23, 12)
    public static let eqToggleOffPressed = SpriteSlice("EQ_OFF_P", "SHUFREP", 46, 61, 23, 12)
    public static let eqToggleOnPressed = SpriteSlice("EQ_ON_P", "SHUFREP", 46, 73, 23, 12)
    
    public static let plToggleOff = SpriteSlice("PL_OFF", "SHUFREP", 23, 61, 23, 12)
    public static let plToggleOn = SpriteSlice("PL_ON", "SHUFREP", 23, 73, 23, 12)
    public static let plToggleOffPressed = SpriteSlice("PL_OFF_P", "SHUFREP", 69, 61, 23, 12)
    public static let plToggleOnPressed = SpriteSlice("PL_ON_P", "SHUFREP", 69, 73, 23, 12)
    
    // MARK: - MONOSTER.BMP
    public static let stereoOff = SpriteSlice("STEREO_OFF", "MONOSTER", 0, 12, 29, 12)
    public static let stereoOn = SpriteSlice("STEREO_ON", "MONOSTER", 0, 0, 29, 12)
    public static let monoOff = SpriteSlice("MONO_OFF", "MONOSTER", 29, 12, 27, 12)
    public static let monoOn = SpriteSlice("MONO_ON", "MONOSTER", 29, 0, 27, 12)
    
    // MARK: - PLAYPAUS.BMP (Status indicator)
    public static let indicatorPlaying = SpriteSlice("IND_PLAY", "PLAYPAUS", 0, 0, 9, 9)
    public static let indicatorPaused = SpriteSlice("IND_PAUSE", "PLAYPAUS", 9, 0, 9, 9)
    public static let indicatorStopped = SpriteSlice("IND_STOP", "PLAYPAUS", 18, 0, 9, 9)
    public static let indicatorWorkingBlank = SpriteSlice("IND_WORK_BLANK", "PLAYPAUS", 27, 0, 3, 9)
    public static let indicatorWorking = SpriteSlice("IND_WORK", "PLAYPAUS", 36, 0, 3, 9)
    public static let indicatorWorkingAlt = SpriteSlice("IND_WORK_ALT", "PLAYPAUS", 39, 0, 3, 9)
    
    // MARK: - NUMBERS.BMP (Digits 0..9 and minus sign)
    public static func digit(_ n: Int) -> SpriteSlice {
        let d = max(0, min(9, n))
        return SpriteSlice("DIGIT_\(d)", "NUMBERS", CGFloat(d * 9), 0, 9, 13)
    }
    public static let minusSign = SpriteSlice("MINUS", "NUMBERS", 20, 6, 5, 1)
    public static let noMinusSign = SpriteSlice("NO_MINUS", "NUMBERS", 9, 6, 5, 1)
    
    // MARK: - EQUALIZER (EQMAIN.BMP & EQ_EX.BMP)
    public static let eqWindowBg = SpriteSlice("EQ_BG", "EQMAIN", 0, 0, 275, 116)
    public static let eqTitleBar = SpriteSlice("EQ_TITLE", "EQMAIN", 0, 149, 275, 14)
    public static let eqTitleBarSelected = SpriteSlice("EQ_TITLE_SEL", "EQMAIN", 0, 134, 275, 14)
    public static let eqCloseNormal = SpriteSlice("EQ_CLOSE", "EQMAIN", 0, 116, 9, 9)
    public static let eqClosePressed = SpriteSlice("EQ_CLOSE_P", "EQMAIN", 0, 125, 9, 9)
    
    public static let eqOnButtonOff = SpriteSlice("EQ_ON_OFF", "EQMAIN", 10, 119, 26, 12)
    public static let eqOnButtonOffPressed = SpriteSlice("EQ_ON_OFF_P", "EQMAIN", 128, 119, 26, 12)
    public static let eqOnButtonOn = SpriteSlice("EQ_ON_ON", "EQMAIN", 69, 119, 26, 12)
    public static let eqOnButtonOnPressed = SpriteSlice("EQ_ON_ON_P", "EQMAIN", 187, 119, 26, 12)
    
    public static let eqAutoButtonOff = SpriteSlice("EQ_AUTO_OFF", "EQMAIN", 36, 119, 32, 12)
    public static let eqAutoButtonOffPressed = SpriteSlice("EQ_AUTO_OFF_P", "EQMAIN", 154, 119, 32, 12)
    public static let eqAutoButtonOn = SpriteSlice("EQ_AUTO_ON", "EQMAIN", 95, 119, 32, 12)
    public static let eqAutoButtonOnPressed = SpriteSlice("EQ_AUTO_ON_P", "EQMAIN", 213, 119, 32, 12)
    
    public static let eqPresetsNormal = SpriteSlice("EQ_PRESETS", "EQMAIN", 224, 164, 44, 12)
    public static let eqPresetsPressed = SpriteSlice("EQ_PRESETS_P", "EQMAIN", 224, 176, 44, 12)
    
    public static let eqSliderThumbNormal = SpriteSlice("EQ_SLID_THUMB", "EQMAIN", 0, 164, 11, 11)
    public static let eqSliderThumbPressed = SpriteSlice("EQ_SLID_THUMB_P", "EQMAIN", 0, 176, 11, 11)
    
    // MARK: - EQ Sliders Background in EQMAIN.BMP (28 frames of 14x63 each, starting at x=13, y=164, 14 per row)
    public static func eqSliderBg(frame: Int) -> SpriteSlice {
        let clamped = max(0, min(27, frame))
        let col = clamped % 14
        let row = clamped / 14
        let x = 13 + (col * 15)
        let y = 164 + (row * 65)
        return SpriteSlice("EQ_SLIDER_BG_\(clamped)", "EQMAIN", CGFloat(x), CGFloat(y), 14, 63)
    }
    
    public static let eqGraphBg = SpriteSlice("EQ_GRAPH_BG", "EQMAIN", 0, 294, 113, 19)
    public static let eqGraphColors = SpriteSlice("EQ_GRAPH_COLORS", "EQMAIN", 115, 294, 1, 19)
    public static let eqPreampLine = SpriteSlice("EQ_PREAMP_LINE", "EQMAIN", 0, 314, 113, 1)
    
    // EQ Shade (EQ_EX.BMP)
    public static let eqShadeBg = SpriteSlice("EQ_SHADE_BG", "EQ_EX", 0, 15, 275, 14)
    public static let eqShadeBgSelected = SpriteSlice("EQ_SHADE_BG_SEL", "EQ_EX", 0, 0, 275, 14)
    public static let eqShadeCloseNormal = SpriteSlice("EQ_SHADE_CLOSE", "EQ_EX", 11, 38, 9, 9)
    public static let eqShadeClosePressed = SpriteSlice("EQ_SHADE_CLOSE_P", "EQ_EX", 11, 47, 9, 9)
    public static let eqShadeVolThumb = SpriteSlice("EQ_SHADE_VOL_THUMB", "EQ_EX", 4, 30, 3, 7)
    public static let eqShadeBalThumb = SpriteSlice("EQ_SHADE_BAL_THUMB", "EQ_EX", 14, 30, 3, 7)
    
    // MARK: - PLAYLIST (PLEDIT.BMP)
    public static let plTopLeft = SpriteSlice("PL_TOP_LEFT", "PLEDIT", 0, 21, 25, 20)
    public static let plTopLeftSel = SpriteSlice("PL_TOP_LEFT_S", "PLEDIT", 0, 0, 25, 20)
    public static let plTopTitle = SpriteSlice("PL_TOP_TITLE", "PLEDIT", 26, 21, 100, 20)
    public static let plTopTitleSel = SpriteSlice("PL_TOP_TITLE_S", "PLEDIT", 26, 0, 100, 20)
    public static let plTopTile = SpriteSlice("PL_TOP_TILE", "PLEDIT", 127, 21, 25, 20)
    public static let plTopTileSel = SpriteSlice("PL_TOP_TILE_S", "PLEDIT", 127, 0, 25, 20)
    public static let plTopRight = SpriteSlice("PL_TOP_RIGHT", "PLEDIT", 153, 21, 25, 20)
    public static let plTopRightSel = SpriteSlice("PL_TOP_RIGHT_S", "PLEDIT", 153, 0, 25, 20)
    
    public static let plLeftTile = SpriteSlice("PL_LEFT_TILE", "PLEDIT", 0, 42, 12, 29)
    public static let plRightTile = SpriteSlice("PL_RIGHT_TILE", "PLEDIT", 31, 42, 20, 29)
    
    public static let plBottomLeft = SpriteSlice("PL_BOT_LEFT", "PLEDIT", 0, 72, 125, 38)
    public static let plBottomTile = SpriteSlice("PL_BOT_TILE", "PLEDIT", 179, 0, 25, 38)
    public static let plBottomRight = SpriteSlice("PL_BOT_RIGHT", "PLEDIT", 126, 72, 150, 38)
    
    public static let plCloseNormal = SpriteSlice("PL_CLOSE", "PLEDIT", 52, 42, 9, 9)
    public static let plClosePressed = SpriteSlice("PL_CLOSE_P", "PLEDIT", 52, 42, 9, 9)
    public static let plShadeNormal = SpriteSlice("PL_SHADE", "PLEDIT", 62, 42, 9, 9)
    public static let plShadePressed = SpriteSlice("PL_SHADE_P", "PLEDIT", 62, 42, 9, 9)
    public static let plExpandPressed = SpriteSlice("PL_EXPAND_P", "PLEDIT", 150, 42, 9, 9)
    
    // Playlist Windowshade (PLEDIT.BMP)
    public static let plShadeLeft = SpriteSlice("PL_SHADE_LEFT", "PLEDIT", 72, 42, 25, 14)
    public static let plShadeMiddle = SpriteSlice("PL_SHADE_MID", "PLEDIT", 72, 57, 25, 14)
    public static let plShadeRightSel = SpriteSlice("PL_SHADE_RIGHT_S", "PLEDIT", 99, 42, 50, 14)
    public static let plShadeRight = SpriteSlice("PL_SHADE_RIGHT", "PLEDIT", 99, 57, 50, 14)
    
    public static let plScrollHandle = SpriteSlice("PL_SCROLL_THUMB", "PLEDIT", 52, 53, 8, 18)
    public static let plScrollHandleSelected = SpriteSlice("PL_SCROLL_THUMB_S", "PLEDIT", 61, 53, 8, 18)
    public static let plScrollUp = SpriteSlice("PL_SCROLL_UP", "PLEDIT", 0, 42, 8, 5) // or subrect
    public static let plScrollDown = SpriteSlice("PL_SCROLL_DOWN", "PLEDIT", 0, 47, 8, 5)
    
    // Bottom toolbar buttons (Row 4: 0, 54, 104, 154, 204 are unpressed; 23, 77, 127, 177, 227 are pressed)
    public static let plAddFile = SpriteSlice("PL_ADD_FILE", "PLEDIT", 0, 149, 22, 18)
    public static let plAddPressed = SpriteSlice("PL_ADD_P", "PLEDIT", 23, 149, 22, 18)
    public static let plAddDir = SpriteSlice("PL_ADD_DIR", "PLEDIT", 0, 130, 22, 18)
    public static let plAddUrl = SpriteSlice("PL_ADD_URL", "PLEDIT", 0, 111, 22, 18)
    
    public static let plRemoveSel = SpriteSlice("PL_REM_SEL", "PLEDIT", 54, 149, 22, 18)
    public static let plRemovePressed = SpriteSlice("PL_REM_P", "PLEDIT", 77, 149, 22, 18)
    public static let plRemoveAll = SpriteSlice("PL_REM_ALL", "PLEDIT", 54, 111, 22, 18)
    public static let plCrop = SpriteSlice("PL_CROP", "PLEDIT", 54, 130, 22, 18)
    
    public static let plSelectAll = SpriteSlice("PL_SEL_ALL", "PLEDIT", 104, 149, 22, 18)
    public static let plSelectPressed = SpriteSlice("PL_SEL_P", "PLEDIT", 127, 149, 22, 18)
    public static let plSelectZero = SpriteSlice("PL_SEL_ZERO", "PLEDIT", 104, 130, 22, 18)
    public static let plInvertSelection = SpriteSlice("PL_INV_SEL", "PLEDIT", 104, 111, 22, 18)
    
    public static let plMiscOptions = SpriteSlice("PL_MISC_OPT", "PLEDIT", 154, 149, 22, 18)
    public static let plMiscPressed = SpriteSlice("PL_MISC_P", "PLEDIT", 177, 149, 22, 18)
    public static let plFileInfo = SpriteSlice("PL_FILE_INFO", "PLEDIT", 154, 130, 22, 18)
    public static let plSortList = SpriteSlice("PL_SORT", "PLEDIT", 154, 111, 22, 18)
    
    public static let plLoadList = SpriteSlice("PL_LOAD", "PLEDIT", 204, 149, 22, 18)
    public static let plListPressed = SpriteSlice("PL_LIST_P", "PLEDIT", 227, 149, 22, 18)
    public static let plSaveList = SpriteSlice("PL_SAVE", "PLEDIT", 204, 130, 22, 18)
    public static let plNewList = SpriteSlice("PL_NEW", "PLEDIT", 204, 111, 22, 18)
    
    // Playlist Popup Menus - Left Vertical Decorative Bars
    public static let plAddMenuBar = SpriteSlice("PL_ADD_BAR", "PLEDIT", 48, 111, 3, 54)
    public static let plRemoveMenuBar = SpriteSlice("PL_REM_BAR", "PLEDIT", 100, 111, 3, 72)
    public static let plSelectMenuBar = SpriteSlice("PL_SEL_BAR", "PLEDIT", 150, 111, 3, 54)
    public static let plMiscMenuBar = SpriteSlice("PL_MISC_BAR", "PLEDIT", 200, 111, 3, 54)
    public static let plListMenuBar = SpriteSlice("PL_LIST_BAR", "PLEDIT", 250, 111, 3, 54)
    
    // Playlist Popup Menus - Selected/Hovered States
    public static let plAddUrlSelected = SpriteSlice("PL_ADD_URL_S", "PLEDIT", 23, 111, 22, 18)
    public static let plAddDirSelected = SpriteSlice("PL_ADD_DIR_S", "PLEDIT", 23, 130, 22, 18)
    public static let plAddFileSelected = SpriteSlice("PL_ADD_FILE_S", "PLEDIT", 23, 149, 22, 18)
    
    public static let plRemoveMisc = SpriteSlice("PL_REM_MISC", "PLEDIT", 54, 168, 22, 18)
    public static let plRemoveMiscSelected = SpriteSlice("PL_REM_MISC_S", "PLEDIT", 77, 168, 22, 18)
    public static let plRemoveAllSelected = SpriteSlice("PL_REM_ALL_S", "PLEDIT", 77, 111, 22, 18)
    public static let plCropSelected = SpriteSlice("PL_CROP_S", "PLEDIT", 77, 130, 22, 18)
    public static let plRemoveSelSelected = SpriteSlice("PL_REM_SEL_S", "PLEDIT", 77, 149, 22, 18)
    
    public static let plInvertSelectionSelected = SpriteSlice("PL_INV_SEL_S", "PLEDIT", 127, 111, 22, 18)
    public static let plSelectZeroSelected = SpriteSlice("PL_SEL_ZERO_S", "PLEDIT", 127, 130, 22, 18)
    public static let plSelectAllSelected = SpriteSlice("PL_SEL_ALL_S", "PLEDIT", 127, 149, 22, 18)
    
    public static let plSortListSelected = SpriteSlice("PL_SORT_S", "PLEDIT", 177, 111, 22, 18)
    public static let plFileInfoSelected = SpriteSlice("PL_FILE_INFO_S", "PLEDIT", 177, 130, 22, 18)
    public static let plMiscOptionsSelected = SpriteSlice("PL_MISC_OPT_S", "PLEDIT", 177, 149, 22, 18)
    
    public static let plNewListSelected = SpriteSlice("PL_NEW_S", "PLEDIT", 227, 111, 22, 18)
    public static let plSaveListSelected = SpriteSlice("PL_SAVE_S", "PLEDIT", 227, 130, 22, 18)
    public static let plLoadListSelected = SpriteSlice("PL_LOAD_S", "PLEDIT", 227, 149, 22, 18)
}
