# MacAmp Implementation Plan

## Overview
MacAmp — музыкальный плеер для macOS в стиле Winamp с ретро-интерфейсом на SwiftUI.

## Current State
- ✅ Core Architecture (Models, Services, ViewModels)
- ✅ Main Player UI (Main & Shade modes stabilized)
- ✅ Audio Engine (AVFoundation, FFT Analysis)
- ✅ Interactive Components (Balance, Volume, Seek, Visualizer)
- ❌ Playlist Window UI (PlaylistView.swift)
- ❌ Equalizer Window UI (EqualizerView.swift)

---

## Phase 1: Core Architecture & Audio Engine ✅
- [x] `Models/Track.swift` — модель трека
- [x] `Models/Playlist.swift` — модель плейлиста
- [x] `Models/PlayerState.swift` — состояние плеера (playing, paused, stopped)
- [x] `Services/AudioPlayerService.swift` — сервис на базе AVFoundation
- [x] `Services/FilePickerService.swift` — выбор аудиофайлов через NSOpenPanel

---

## Phase 2: UI Components (Winamp Style)

### 2.1 Main Window Layout
- [ ] `Views/MainPlayerView.swift` — основной вид плеера
  - Отображение скина (MAIN.png как фон)
  - Дисплей: трек, время, битрейт
  - Полоса прокрутки (seek bar)
  - Громкость (volume slider)

### 2.2 Playlist Window
- [ ] `Views/PlaylistView.swift` — окно плейлиста
  - Список треков
  - Drag & drop поддержка
  - Контекстное меню

### 2.3 Equalizer Window
- [ ] `Views/EqualizerView.swift` — эквалайзер
  - Полосы частот (EQ sliders)
  - Пресеты (Rock, Pop, Jazz, Classical и др.)

### 2.4 Visualizer
- [ ] `Views/VisualizerView.swift` — аудиовизуализатор
  - Анализ частот через FFT
  - Визуальные эффекты

---

## Phase 3: State Management

### 3.1 Player ViewModel
- [ ] `ViewModels/PlayerViewModel.swift` — основной ViewModel
  - @Published properties для состояния
  - Привязка к AudioPlayerService
  - Обновление UI

### 3.2 Playlist ViewModel
- [ ] `ViewModels/PlaylistViewModel.swift` — управление плейлистом
  - Добавление/удаление треков
  - Сохранение/загрузка плейлистов

---

## Phase 4: Skin System

### 4.1 Skin Manager
- [ ] `skin/SkinManager.swift` — загрузка и применение скинов
- [ ] `skin/SkinConfig.swift` — конфигурация скина (цвета, шрифты, позиции элементов)

### 4.2 Default Skin
- [ ] Использование существующих ассетов из Assets.xcassets
- [ ] Позиционирование элементов UI поверх MAIN.png

---

## Phase 5: Persistence

### 5.1 Settings Storage
- [ ] `Services/SettingsService.swift` — сохранение настроек через UserDefaults
  - Последний плейлист
  - Громкость
  - Shuffle/Repeat
  - Выбранный скин
  - Режим шрифта бегущей строки (Bitmap Font vs Desktop Font)

### 5.2 Recent Files
- [ ] История открытых файлов/папок

---

## Phase 6: Additional Features

### 6.1 Keyboard Shortcuts
- [ ] Space — Play/Pause
- [ ] Left/Right — Seek
- [ ] Up/Down — Volume
- [ ] N — Next track
- [ ] P — Previous track

### 6.2 System Integration
- [ ] Now Playing в центре уведомлений
- [ ] Контролы в Dock/Menu Bar
- [ ] Поддержка медиа-клавиш

### 6.3 Menu Bar
- [ ] `Views/MenuBarExtraView.swift` — компактный контрол из меню-бара

### 6.4 Track Info & Metadata Editor (Alt+3)
- [x] **Шаг 1: Сервис чтения/записи тегов (`AudioMetadataService.swift`)**
  - [x] Чтение технических параметров аудиофайла (размер в байтах, смещение заголовка, точный битрейт, sample rate, каналы, кодек)
  - [x] Парсинг и запись стандартного блока ID3v1 (последние 128 байт файла, лимит 30 символов, 148 жанров)
  - [x] Чтение и запись расширенных тегов ID3v2 (Title, Artist, Album, Year, Track #, Genre, Composer, Copyright, Comment)
  - [x] Извлечение и внедрение обложки альбома (Artwork: APIC frame / MP4 covr) с загрузкой, сохранением и удалением
  - [x] Поддержка форматов помимо MP3 (M4A/AAC, FLAC, WAV)
- [x] **Шаг 2: Модель и состояние редактора (`TrackInfoModel` / `AudioFileMetadata`)**
  - [x] Структура `AudioFileMetadata` со всеми полями ID3v1, ID3v2, MPEG Info и Artwork
  - [x] Функции синхронизации `copyToID3v1()` и `copyFromID3v1()`
  - [x] Логика сохранения изменений и уведомления `PlaylistModel` / `PlayerCoordinator`
- [x] **Шаг 3: Окно Track Info (`TrackInfoWindow.swift` + `TrackInfoView.swift`)**
  - [x] Классический Winamp / Windows 2000 диалоговый UI (рамки, поля ввода, селектор жанров)
  - [x] Верхний технический блок MPEG Info (размер, заголовок, битрейт, частота, стерео режим)
  - [x] Блоки ID3v1 и ID3v2 с независимыми чекбоксами включения
  - [x] Блок Artwork с превью обложки и кнопками `Load...`, `Save...`, `Remove`
  - [x] Кнопки `Update`, `Cancel`, `Undo Changes`, `Copy to/from ID3v1`
  - [x] Кнопки навигации `< Prev` и `Next >` для перелистывания треков плейлиста без закрытия окна
- [x] **Шаг 4: Интеграция с плейлистом и шорткатами**
  - [x] Глобальный хоткей `Alt+3` (Option+3) для открытия окна выбранного/текущего трека
  - [x] Пункт меню `MISC -> File Info` в окне плейлиста
  - [x] Контекстное меню правого клика по треку: `View file info... (Alt+3)`
  - [x] Двойной клик на длительность трека в плейлисте (Winamp behavior)
- [ ] Quick Track Edit (`Ctrl+E`) в плейлисте
- [ ] Jump to File (`J` / `F3`) — быстрый поиск и переход к треку
- [ ] Jump to Time (`Ctrl+J`) — быстрый переход по времени трека

### 6.5 Preferences & Global Settings (Ctrl+P)
- [x] **Каркас окна Preferences (`PreferencesWindow.swift` + `PreferencesView.swift`)**
  - [x] Двухпанельный макет: левое дерево разделов (`PreferencesCategory`), правая панель настроек
  - [x] Хоткей вызова `Ctrl+P` (Cmd+P / Ctrl+P / Cmd+,), пункт в контекстном меню и в главном меню
- [x] **Панель Titles & Display**:
  - [x] Переключатель шрифта бегущей строки: `Bitmap Font` (пиксельный шрифт скина) vs `Desktop Font` (системный шрифт)
  - [x] Выбор системного шрифта (Monaco, Menlo, Geneva, SF Pro Display, Courier New, Helvetica) и размера (8–14 pt)
  - [x] Автоматическое наследование цвета текста из скина (`playlistStyle.normalColor` / `viscolor.txt` / `PLEDIT.TXT`)
  - [x] Опция плавной прокрутки бегущей строки и отображения номера трека
- [x] **Панель Skins**:
  - [x] Список установленных скинов с выбором в один клик и базовым скином Winamp 2.91
  - [x] Кнопка установки новых скинов (`.wsz` / `.zip`) и открытие папки скинов в Finder
  - [x] Переключатель масштаба 1x / 2x с моментальным применением
- [x] **Панель Audio & Playback**:
  - [x] Настройка плавного затухания (Fade out) при паузе и остановке (0–2000 мс)
  - [x] Авто-загрузка пресетов эквалайзера по жанру трека из ID3
- [x] **Панель Playlist Preferences**:
  - [x] Формат номеров треков (`01.` vs `1.`)
  - [x] Отображение расширений файлов (.mp3, .flac) при отсутствии названия
  - [x] Алгоритм shuffle (Authentic Winamp pseudo-random vs pure random)
- [x] Сохранение всех настроек через `PersistenceManager` / `AppState`

---

## Phase 7: Polish & Testing

### 7.1 Animations
- [ ] Плавные переходы между состояниями
- [ ] Анимация дисплея

### 7.2 Error Handling
- [ ] Обработка ошибок загрузки файлов
- [ ] Graceful degradation при отсутствии аудио

### 7.3 Testing
- [ ] Unit tests для моделей
- [ ] UI tests для основных сценариев

---

## Technical Stack
- **Language**: Swift 5.0+
- **UI Framework**: SwiftUI
- **Audio**: AVFoundation (AVAudioPlayer / AVPlayer)
- **Platform**: macOS 13.1+
- **Storage**: UserDefaults, FileManager

## Dependencies
- Нет внешних зависимостей (только Apple frameworks)

## File Structure
```
MacAmp/
├── MacAmp/
│   ├── MacAmpApp.swift
│   ├── ContentView.swift
│   ├── Models/
│   │   ├── Track.swift
│   │   ├── Playlist.swift
│   │   └── PlayerState.swift
│   ├── Services/
│   │   ├── AudioPlayerService.swift
│   │   ├── FilePickerService.swift
│   │   └── SettingsService.swift
│   ├── ViewModels/
│   │   ├── PlayerViewModel.swift
│   │   └── PlaylistViewModel.swift
│   ├── Views/
│   │   ├── MainPlayerView.swift
│   │   ├── PlaylistView.swift
│   │   ├── EqualizerView.swift
│   │   ├── VisualizerView.swift
│   │   └── MenuBarExtraView.swift
│   ├── skin/
│   │   ├── SkinManager.swift
│   │   └── SkinConfig.swift
│   └── Assets.xcassets/
└── build.sh
```

## Milestones
1. **v0.1** — Phase 1-2: Базовый плеер с воспроизведением и UI
2. **v0.2** — Phase 3: State management и привязка к UI
3. **v0.3** — Phase 4-5: Скин-система и персистентность
4. **v1.0** — Phase 6-7: Полнофункциональный релиз