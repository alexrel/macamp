# TASK: MainPlayerView — Основной вид плеера

## Цель
Переработать текущий ContentView в полноценный MainPlayerView, соответствующий оригинальному WinAmp 2.91, с поддержкой масштабирования 1x/2x.

## Текущее состояние
- [x] MAIN.BMP отображается как фон
- [x] 6 кнопок управления откалиброваны и функциональны
- [x] Time display (NUMBERS.BMP) — Готово
- [x] Title Bar (TITLEBAR.BMP) — Готово со всеми кнопками (Min/Shade/Close)
- [x] Volume/Balance/Position слайдеры — Готово
- [x] Битрейт и Частота (TEXT.BMP) — Готово
- [x] Индикаторы Mono/Stereo — Готово
- [x] Кнопки Shuffle/Repeat — Готово
- [x] Кнопки EQ/Playlist — Готово

## Требования

### 1. Базовый layout
- [x] MAIN.BMP как фон (275×116 px @ 1x)
- [x] Размер окна фиксирован: 275×116 @ 1x, 550×232 @ 2x
- [x] Убрать VStack/HStack с логотипом — оставить только плеер

### 2. Кнопки управления (из CBUTTONS.BMP)
- [x] Все 6 кнопок на позициях:
  - Previous (16, 88)
  - Play (39, 88)
  - Pause (62, 88)
  - Stop (85, 88)
  - Next (108, 88)
  - Eject (136, 89)

### 3. Заголовок (TITLEBAR.BMP)
- [x] Позиция: (0, 0), размер 275×14 @1x
- [x] Кнопки: Minimize, Shade, Close
- [x] Drag area (через SwiftUI WindowDragArea)
- [x] Clutterbar (O, P, I, D, V) кнопки

### 4. Дисплей времени (NUMBERS.BMP)
- [x] Позиция: (48, 26) @1x
- [x] Формат: `MM:SS`
- [x] LCD-стиль, цифры из спрайта (9x13)
- [x] Мигание при паузе

### 5. Бегущая строка (TEXT.BMP)
- [x] Позиция: (112, 27) @1x
- [x] Отображает: Song Title
- [x] Анимация прокрутки (loop)

### 6. Volume/Position слайдеры
- [x] Volume: (107, 57) @1x
- [x] Balance: (177, 57) @1x
- [x] Position: (16, 72) @1x

### 7. Масштабирование 2x
- [x] Toggle работает (кнопка D в Clutterbar)
- [x] Все координаты и размеры масштабируются (Global scaleEffect)
- [x] `.interpolation(.none)` для пиксельного стиля

## Acceptance Criteria
- [x] MAIN.BMP отображается как фон
- [x] 6 кнопок на своих позициях (не SF Symbols)
- [x] Заголовок с кнопками Min/Shade/Close
- [x] Time display показывает реальное время (из NUMBERS.BMP)
- [x] Toggle 1x/2x работает
- [x] Окно не ресайзится (фиксированный размер)
- [x] Пиксельный стиль при 2x (без сглаживания)

## Оценка
✅ Основной интерфейс полностью завершен.
Next Step: Реализация Shade Mode и Визуализатора.