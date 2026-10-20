# WinAmp Classic Skin Specifications (v1.2 - Verified)

Этот документ содержит проверенную техническую спецификацию, соответствующую эталонному расположению спрайтов и элементов интерфейса.

---

## 1. Главное окно (main.bmp - 275x116)

| Элемент | X | Y | Width | Height | Комментарии |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Title Bar** | 0 | 0 | 275 | 14 | |
| **Clutterbar** | 10 | 22 | 8 | 43 | |
| **Playback Indicator** | 24 | 28 | 11 | 9 | (playpaus.bmp) |
| **Time Minus Sign** | 40 | 32 | 5 | 1 | |
| **Time Minute 1** | 48 | 26 | 9 | 13 | |
| **Time Minute 2** | 60 | 26 | 9 | 13 | |
| **Time Second 1** | 78 | 26 | 9 | 13 | |
| **Time Second 2** | 90 | 26 | 9 | 13 | |
| **Visualization Area** | 24 | 43 | 76 | 16 | |
| **Song Title Display** | 112 | 27 | 152 | 6 | (text.bmp) |
| **Bitrate Display** | 111 | 43 | 15 | 6 | |
| **Sample Rate Display** | 156 | 43 | 10 | 6 | |
| **Mono Indicator** | 212 | 41 | 27 | 12 | |
| **Stereo Indicator** | 239 | 41 | 29 | 12 | |
| **Volume Slidebar** | 107 | 57 | 68 | 12(13) | (volume.bmp) |
| **Panning Slidebar** | 177 | 57 | 38 | 13 | |
| **Equalizer Button** | 219 | 58 | 23 | 13 | (shufrep.bmp) |
| **Playlist Button** | 242 | 58 | 23 | 12 | (shufrep.bmp) |
| **Position Slidebar** | 16 | 72 | 248 | 10 | (posbar.bmp) |
| **Control Buttons** | 16 | 88 | 114 | 18 | (cbuttons.bmp) |
| **Eject Button** | 136 | 89 | 22 | 16 | |
| **Shuffle Button** | 164 | 89 | 46 | 15 | |
| **Repeat Button** | 210 | 89 | 28 | 15 | |
| **About WinAmp (Z)** | 253 | 91 | 13 | 15 | |

---

## 2. Заголовок и Clutterbar (titlebar.bmp)
**Размер**: 344 × 87 px

| Элемент | X (Src) | Y (Src) | Width | Height | Target (X, Y) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Option Button** | 0 | 0 | 9 | 9 | (6, 3) |
| **Minimize Button** | 9 | 0 | 9 | 9 | (244, 3) |
| **Close Button** | 18 | 0 | 9 | 9 | (264, 3) |
| **Shade Button** | 0 | 18 | 9 | 9 | (254, 3) |
| **Active Titlebar** | 27 | 0 | 275 | 14 | (0, 0) |

---

## 3. Слайдеры (Sliders)

### Position Bar (posbar.bmp)
- **Background**: (0, 0), 248x10
- **Knob (Norm)**: (248, 0), 29x10
- **Target Location**: (16, 72)

### Volume & Panning (volume.bmp)
- **Volume Frames**: (0, n*15), 68x13
- **Panning Frames**: (9, n*15), 38x13
- **Knob (Norm)**: (15, 422), 14x11
- **Target Volume**: (107, 57)
- **Target Balance**: (177, 57)

---

## 4. Дисплей (Display)

### Текст (text.bmp)
- **Сетка**: 5x6 px
- **Target Title**: (112, 27)
- **Target Bitrate**: (111, 43)
- **Target SampleRate**: (156, 43)

### Цифры времени (numbers.bmp)
- **Target Time**: (48, 26) - Ссылка на minute/second digits выше.
