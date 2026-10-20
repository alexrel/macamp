# MacAmp Implementation Checklist

## Phase 1: Basic Player (v0.1) ✅
- [x] `Track.swift`
- [x] `AudioPlayerService.swift`
- [x] `FilePickerService.swift`
- [x] `PlayerViewModel.swift`
- [x] `MainPlayerView.swift` (Shade Mode stabilized)
- [x] `ContentView.swift`

## Phase 2: Playlist (v0.2)
- [x] `Playlist.swift`
- [x] `FilePickerService.swift` (Multiple files)
- [x] `PlayerViewModel.swift` (Playlist logic)
- [ ] `PlaylistView.swift` (Missing standalone window)

## Phase 3: Player UI (v0.3) ✅
- [x] `MainPlayerView.swift` — полный UI
- [x] Track Info (Scrolling)
- [x] Time Display (LCD style)
- [x] Progress Bar
- [x] Volume Slider
- [x] Balance Slider (with center snap)
- [x] Assets Mapping

---

## Phase 4: Equalizer (v0.4)

### Views
- [ ] `EqualizerView.swift`
  - [ ] 10 полос эквалайзера
  - [ ] Preamp слайдер
  - [ ] On/Off переключатель
  - [ ] Пресеты (ComboBox)
  - [ ] Свернуть/развернуть

### Services
- [ ] `EqualizerService.swift`
  - [ ] bands: [Float] (10 полос)
  - [ ] preamp: Float
  - [ ] apply(to player: AVAudioPlayer)
  - [ ] loadPreset(_ preset: EQPreset)

### Models
- [ ] `EQPreset.swift`
  - name: String
  - bands: [Float]
  - preamp: Float

---

## Phase 5: Skin System (v0.5)

### Services
- [ ] `SkinManager.swift`
  - [ ] loadSkin(from url: URL)
  - [ ] currentSkin: Skin
  - [ ] availableSkins: [Skin]
  - [ ] switchSkin(_ skin: Skin)

### Models
- [ ] `Skin.swift`
  - name: String
  - mainImage: Image
  - elements: [SkinElement]
  - colors: SkinColors

- [ ] `SkinElement.swift`
  - type: ElementType
  - frame: CGRect
  - image: Image?

### Parsing
- [ ] `SkinParser.swift`
  - [ ] parseWSZ(_ url: URL) → Skin
  - [ ] parseRegion(_ url: URL) → [CGRect]
  - [ ] extractImages(_ url: URL) → [String: Image]

---

## Phase 6: Polish (v1.0)

### Keyboard Shortcuts
- [ ] Space — Play/Pause
- [ ] Left — Seek -5s
- [ ] Right — Seek +5s
- [ ] Up — Volume +5%
- [ ] Down — Volume -5%
- [ ] N — Next
- [ ] P — Previous
- [ ] O — Open file

### System Integration
- [ ] Now Playing (MPNowPlayingInfoCenter)
- [ ] Remote Command Center
- [ ] Dock icon menu

### Menu Bar
- [ ] `MenuBarExtraView.swift`
  - [ ] Play/Pause
  - [ ] Next/Previous
  - [ ] Track info
  - [ ] Open MacAmp

### Settings
- [ ] `SettingsService.swift`
  - [ ] Save/Load volume
  - [ ] Save/Load last playlist
  - [ ] Save/Load current skin
  - [ ] Save/Load EQ settings

---

## Testing

### Unit Tests
- [ ] Track model tests
- [ ] Playlist model tests
- [ ] AudioPlayerService tests
- [ ] FilePickerService tests

### UI Tests
- [ ] Play/Pause flow
- [ ] Open file flow
- [ ] Playlist navigation
- [ ] Volume control

---

## Done Definition
Задача считается выполненной когда:
1. Код написан и компилируется
2. Функциональность протестирована вручную
3. Нет критических багов
4. UI соответствует дизайну WinAmp