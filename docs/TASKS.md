# MacAmp Implementation Tasks

## Sprint 1: Foundation (v0.1 — Basic Player)

### T1.1 — Track Model ✅
**Приоритет**: Высокий
**Статус**: ✅ Done
**Описание**: Создать модель данных для трека

```swift
struct Track {
    let id: UUID
    let title: String
    let artist: String
    let duration: TimeInterval
    let url: URL
    let artwork: Data?
}
```

**Acceptance Criteria**:
- [ ] Track инициализируется из URL
- [ ] Метаданные извлекаются через AVAsset
- [ ] artwork опционален

---

### T1.2 — AudioPlayerService ✅
**Приоритет**: Высокий
**Статус**: ✅ Done
**Описание**: Базовый аудио сервис на AVFoundation

**Функции**:
- [ ] play(url: URL) — загрузить и воспроизвести
- [ ] pause() — пауза
- [ ] stop() — остановить
- [ ] seek(to: TimeInterval) — перемотка
- [ ] @Published currentTime, duration, isPlaying

**Acceptance Criteria**:
- [ ] Воспроизводит mp3, aac, wav, aiff
- [ ] Корректно обновляет currentTime каждые 0.1s
- [ ] isPlaying обновляется при play/pause/stop

---

### T1.3 — FilePickerService
**Приоритет**: Высокий
**Описание**: Диалог выбора аудиофайлов

**Функции**:
- [ ] openFile() → URL?
- [ ] allowedTypes: [.mp3, .aac, .wav, .aiff, .flac, .alac]

**Acceptance Criteria**:
- [ ] Открывает NSOpenPanel
- [ ] Фильтрует только аудио файлы
- [ ] Возвращает nil при отмене

---

### T1.4 — PlayerViewModel
**Приоритет**: Высокий
**Описание**: ViewModel для плеера

**Функции**:
- [ ] @Published currentTrack: Track?
- [ ] @Published playerState: PlayerState (.idle, .playing, .paused, .stopped)
- [ ] openFile() — вызов FilePickerService
- [ ] togglePlayPause()
- [ ] stop()

**Acceptance Criteria**:
- [ ] Открытие файла обновляет currentTrack
- [ ] Play/Pause переключает состояние
- [ ] Stop сбрасывает на начало

---

### T1.5 — MainPlayerView
**Приоритет**: Высокий
**Статус**: ✅ In Progress
**Описание**: Основной вид плеера

**Элементы**:
- [x] Фон: MAIN.png
- [x] Кнопки: Previous, Play, Pause, Stop, Next, Eject (по координатам из CBUTTONS.BMP)
- [x] Заголовок с кнопками Min/Shade/Close
- [x] Time Display (LCD стиль)
- [x] Масштабирование 1x/2x

**Acceptance Criteria**:
- [x] Фон отображается корректно
- [x] Кнопки вызывают соответствующие действия
- [x] Визуальное состояние кнопок отражает playerState

---

### T1.6 — Update ContentView
**Приоритет**: Средний
**Статус**: ✅ Done
**Описание**: Интеграция MainPlayerView в ContentView

**Changes**:
- [x] Удалить текущий хардкод в ContentView
- [x] Добавить MainPlayerView
- [ ] Использовать PlayerViewModel

---

## Sprint 2: Playlist (v0.2)

### T2.1 — Playlist Model
**Приоритет**: Высокий
**Описание**: Модель плейлиста

```swift
class Playlist: ObservableObject {
    @Published tracks: [Track]
    @Published currentIndex: Int
    
    var currentTrack: Track? { ... }
    func add(_ track: Track) { ... }
    func remove(at index: Int) { ... }
    func next() -> Track? { ... }
    func previous() -> Track? { ... }
}
```

**Acceptance Criteria**:
- [ ] Добавление/удаление треков
- [ ] Навигация next/previous
- [ ] currentTrack всегда валиден

---

### T2.2 — Update FilePickerService
**Приоритет**: Высокий
**Описание**: Добавить выбор нескольких файлов

**Функции**:
- [ ] openFiles() → [URL]
- [ ] canChooseDirectories = true (опционально)

---

### T2.3 — PlaylistViewModel
**Приоритет**: Высокий
**Описание**: ViewModel для плейлиста

**Функции**:
- [ ] @Published playlist: Playlist
- [ ] @Published isExpanded: Bool
- [ ] addTracks(_ urls: [URL])
- [ ] removeTrack(at: IndexSet)
- [ ] moveToNext()
- [ ] moveToPrevious()

---

### T2.4 — PlaylistView
**Приоритет**: Высокий
**Описание**: Вид плейлиста

**Элементы**:
- [ ] List с треками
- [ ] Выделение текущего трека
- [ ] Кнопки: Prev, Next
- [ ] Кнопка свернуть/развернуть

**Acceptance Criteria**:
- [ ] Список отображает треки
- [ ] Клик по треку начинает воспроизведение
- [ ] Prev/Next работают корректно

---

### T2.5 — Integrate Playlist into MainPlayerView
**Приоритет**: Средний
**Описание**: Объединить плеер и плейлист

**Changes**:
- [ ] Добавить PlaylistView в MainPlayerView
- [ ] Подключить PlaylistViewModel
- [ ] Кнопки Prev/Next в плеере

---

## Sprint 3: Player UI (v0.3)

### T3.1 — Time Display
**Приоритет**: Высокий
**Описание**: Отображение времени на дисплее

**Элементы**:
- [ ] Текущее время (MM:SS)
- [ ] Общее время (MM:SS)
- [ ] Стиль как NUMBERS.png

---

### T3.2 — Progress Bar (Seek Bar)
**Приоритет**: Высокий
**Описание**: Полоса прокрутки трека

**Элементы**:
- [ ] Slider для seek
- [ ] Позиция на основе currentTime
- [ ] Drag для перемотки

---

### T3.3 — Volume Control
**Приоритет**: Средний
**Описание**: Управление громкостью

**Элементы**:
- [ ] Slider для громкости
- [ ] range: 0.0...1.0
- [ ] Иконка громкости

---

### T3.4 — Track Info Display ✅
**Приоритет**: Средний
**Статус**: ✅ Done
**Описание**: Информация о треке (ScrollingTextView)

---

### T3.5 — Balance Control ✅
**Приоритет**: Низкий
**Статус**: ✅ Done
**Описание**: Баланс звука (с эффектом магнита в центре)

---

## Sprint 4: Equalizer (v0.4)

### T4.1 — EQPreset Model
**Приоритет**: Средний
**Описание**: Модель пресета эквалайзера

```swift
struct EQPreset: Identifiable {
    let id: String
    let name: String
    let bands: [Float] // 10 полос
    let preamp: Float
}
```

---

### T4.2 — EqualizerService
**Приоритет**: Средний
**Описание**: Сервис эквалайзера

**Функции**:
- [ ] @Published bands: [Float]
- [ ] @Published preamp: Float
- [ ] @Published isEnabled: Bool
- [ ] apply(to player: AVAudioPlayer)
- [ ] loadPreset(_ preset: EQPreset)

---

### T4.3 — EqualizerView
**Приоритет**: Средний
**Описание**: Вид эквалайзера

**Элементы**:
- [ ] 10 вертикальных слайдеров
- [ ] Preamp слайдер
- [ ] On/Off переключатель
- [ ] ComboBox с пресетами
- [ ] Кнопка свернуть/развернуть

---

## Sprint 5: Skin System (v0.5)

### T5.1 — Skin Models
**Приоритет**: Средний
**Описание**: Модели системы скинов

```swift
struct Skin {
    let name: String
    let mainImage: Image
    let elements: [SkinElement]
    let colors: SkinColors
}

struct SkinElement {
    let type: ElementType
    let frame: CGRect
    let image: Image?
}
```

---

### T5.2 — SkinParser
**Приоритет**: Средний
**Описание**: Парсер .wsz скинов

**Функции**:
- [ ] parseWSZ(_ url: URL) → Skin
- [ ] parseRegion(_ url: URL) → [CGRect]
- [ ] extractImages(_ url: URL) → [String: Image]

---

### T5.3 — SkinManager
**Приоритет**: Средний
**Описание**: Менеджер скинов

**Функции**:
- [ ] @Published currentSkin: Skin
- [ ] @Published availableSkins: [Skin]
- [ ] loadSkin(from url: URL)
- [ ] switchSkin(_ skin: Skin)

---

### T5.4 — Skin Switching UI
**Приоритет**: Низкий
**Описание**: Интерфейс выбора скинов

**Элементы**:
- [ ] Picker для выбора скина
- [ ] Preview скина
- [ ] Import .wsz кнопка

---

## Sprint 6: Polish (v1.0)

### T6.1 — Keyboard Shortcuts
**Приоритет**: Средний
**Описание**: Горячие клавиши

**Shortcuts**:
- [ ] Space — Play/Pause
- [ ] Arrow Left — Seek -5s
- [ ] Arrow Right — Seek +5s
- [ ] Arrow Up — Volume +5%
- [ ] Arrow Down — Volume -5%
- [ ] N — Next track
- [ ] P — Previous track
- [ ] O — Open file

---

### T6.2 — Now Playing Integration
**Приоритет**: Низкий
**Описание**: Интеграция с системным Now Playing

**Функции**:
- [ ] MPNowPlayingInfoCenter обновление
- [ ] Artwork в Control Center
- [ ] Track info в Dock

---

### T6.3 — Menu Bar Extra
**Приоритет**: Низкий
**Описание**: Контролы в меню-бар

**Элементы**:
- [ ] Play/Pause
- [ ] Next/Previous
- [ ] Track info
- [ ] Open MacAmp

---

### T6.4 — Settings Persistence
**Приоритет**: Средний
**Описание**: Сохранение настроек

**Settings**:
- [ ] Volume
- [ ] Last playlist
- [ ] Current skin
- [ ] EQ settings

---

## Dependencies
```
T1.1 → T1.2, T1.4
T1.2 → T1.4, T1.5
T1.3 → T1.4
T1.4 → T1.5, T1.6
T2.1 → T2.3, T2.4
T2.2 → T2.3
T2.3 → T2.4, T2.5
T1.5 + T2.4 → T2.5
T3.1, T3.2, T3.3, T3.4 → T1.5 (update)
T4.1 → T4.2
T4.2 → T4.3
T5.1 → T5.2, T5.3
T5.2 → T5.3
T5.3 → T5.4
```

## Estimated Timeline
- Sprint 1: 2-3 days
- Sprint 2: 2-3 days
- Sprint 3: 2-3 days
- Sprint 4: 1-2 days
- Sprint 5: 2-3 days
- Sprint 6: 2-3 days

**Total**: ~12-17 days