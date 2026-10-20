# MacAmp Roadmap

## Project Vision
Порт легендарного WinAmp 2.9 на macOS с сохранением оригинальной эстетики и функциональности.

## Key Features

### Core Audio
- [ ] Воспроизведение MP3, AAC, WAV, AIFF
- [ ] Расширенные форматы: FLAC, ALAC
- [ ] Определение метаданных (ID3, metadata)

### WinAmp Structure
- [ ] Три секции: Player / Equalizer / Playlist
- [ ] Возможность свернуть/закрыть Playlist и Equalizer
- [ ] Оригинальное расположение элементов

### Skin System
- [ ] Поддержка стандартных скинов WinAmp 2.9
- [ ] Установка скинов из файла (.wsz)
- [ ] Переключение скинов на лету

---

## Milestones

### v0.1 — Basic Player (Базовый плеер)
**Цель**: Воспроизведение одного файла
- [ ] Открытие файла через диалог
- [ ] Play / Pause / Stop
- [ ] Базовый UI на основе скина MAIN.png

### v0.2 — Playlist (Плейлист)
**Цель**: Несколько треков
- [ ] Загрузка нескольких файлов
- [ ] Prev / Next навигация
- [ ] Отображение списка треков
- [ ] Секция Playlist (свернуть/развернуть)

### v0.3 — Player UI (Интерфейс плеера)
**Цель**: Полноценный дисплей
- [ ] Отображение времени (текущее / общее)
- [ ] Progress bar (seek)
- [ ] Volume control
- [ ] Track info (название, артист)

### v0.4 — Equalizer (Эквалайзер)
**Цель**: Настройка звука
- [ ] Секция Equalizer (свернуть/развернуть)
- [ ] Полосы частот
- [ ] Пресеты

### v0.5 — Skin System (Система скинов)
**Цель**: Кастомизация
- [ ] Загрузка .wsz скинов
- [ ] Переключение на лету
- [ ] Встроенные скины

### v1.0 — Release (Релиз)
**Цель**: Готовый продукт
- [ ] Keyboard shortcuts
- [ ] System integration (Now Playing, Dock)
- [ ] Menu Bar controls
- [ ] Покупка через App Store / прямая дистрибуция

---

## Technical Decisions

### Architecture
- **Pattern**: MVVM (Model-View-ViewModel)
- **State Management**: @Observable / @StateObject
- **Audio Engine**: AVFoundation (AVAudioPlayer / AVPlayer)

### Skin Compatibility
- Парсинг skin.xml / region.txt из .wsz архивов
- Координатная система элементов из оригинала
- Image slicing из BMP/PNG спрайтов

### File Structure
```
docs/
├── ROADMAP.md      ← этот файл
├── CHECKLIST.md    ← чеклист по фазам
├── TASKS.md        ← детальные задачи
└── PLAN.md         ← технический план

MacAmp/
├── Models/         ← данные
├── Services/       ← бизнес-логика
├── ViewModels/     ← привязка к UI
├── Views/          ← SwiftUI views
├── skin/           ← скин-система
└── Assets.xcassets ← ассеты