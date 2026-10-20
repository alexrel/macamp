# 0. Твой текущий scope (зафиксируем)

Окна:

1. **Main**
2. **Playlist**
3. **Equalizer**

👉 Видео окна пока нет, но архитектура должна позволить:

* добавить `VideoWindow` без переписывания логики
* просто как ещё один участник snapping/grouping

---

# 1. Ключевое решение (очень важно)

👉 НЕ делай special-case под Main
👉 НЕ делай “parent-child”

Сделай так:

> Все окна = одинаковые draggable entities
> Main — просто одно из них (с UX-ролью, но не архитектурной)

Это спасёт тебя позже.

---

# 2. Минимальная модель данных (то, что должен понять агент)

```ts
type WindowId = 'main' | 'playlist' | 'equalizer'

type WinampWindow = {
  id: WindowId

  x: number
  y: number

  width: number
  height: number

  isShade: boolean
  isVisible: boolean

  scale: 1 | 2
}
```

Глобально:

```ts
type LayoutState = {
  windows: Record<WindowId, WinampWindow>
  snapThreshold: number // ~10px
}
```

---

# 3. Snap Engine (ядро)

## 3.1. Проверка прилипания

Псевдокод:

```ts
function getSnapOffset(a: Rect, b: Rect): Offset | null {
  // horizontal snap
  if (abs(a.right - b.left) < threshold && verticalOverlap(a, b)) {
    return { x: b.left - a.width - a.x, y: 0 }
  }

  if (abs(a.left - b.right) < threshold && verticalOverlap(a, b)) {
    return { x: b.right - a.x, y: 0 }
  }

  // vertical snap
  if (abs(a.bottom - b.top) < threshold && horizontalOverlap(a, b)) {
    return { x: 0, y: b.top - a.height - a.y }
  }

  if (abs(a.top - b.bottom) < threshold && horizontalOverlap(a, b)) {
    return { x: 0, y: b.bottom - a.y }
  }

  return null
}
```

---

## 3.2. Важный момент

👉 Проверяешь ВСЕ пары:

* main ↔ playlist
* main ↔ eq
* playlist ↔ eq

---

# 4. Group Movement (самое критичное)

## 4.1. Алгоритм

При drag окна:

```ts
function getConnectedGroup(startWindowId) {
  visited = new Set()
  stack = [startWindowId]

  while (stack not empty):
    current = stack.pop()

    for each otherWindow:
      if isSnapped(current, otherWindow):
        add to stack

  return visited
}
```

---

## 4.2. Движение

```ts
function moveGroup(group, dx, dy) {
  for each window in group:
    window.x += dx
    window.y += dy
}
```

---

## 4.3. Пересчёт каждый frame

👉 Это важно:

* group не кешируется
* считается заново при каждом движении

---

# 5. Поведение drag (как должно ощущаться)

Когда пользователь тянет:

1. Начал drag на одном окне
2. На каждом frame:

   * считаем group
   * двигаем group
   * применяем snap

👉 Важный UX нюанс:

Сначала движение → потом snap коррекция
НЕ наоборот

---

# 6. Double Size (кнопка D)

## 6.1. Что должен сделать агент

```ts
function toggleScale() {
  for each window:
    window.scale = window.scale === 1 ? 2 : 1

    window.width *= 2 or /2
    window.height *= 2 or /2
}
```

---

## 6.2. Критический нюанс

👉 НЕ трогай x/y

Это автоматически сохранит layout.

---

## 6.3. После scaling

* НЕ пересобирай layout
* НЕ пересчитывай snap вручную
* всё должно “сохраниться визуально”

---

# 7. Shade Mode

## 7.1. Что меняется

```ts
if (isShade):
  height = SHADE_HEIGHT
else:
  height = NORMAL_HEIGHT
```

---

## 7.2. Что НЕ меняется

* x / y
* snapping
* grouping

👉 Это ключевая идея:

> Shade mode = только изменение размера, не поведения

---

## 7.3. UX нюанс (очень важный)

Когда окно сворачивается:

👉 верхний левый угол остаётся тем же

НЕ центр
НЕ bottom

---

# 8. Как это должно ощущаться (UX чеклист)

Вот это прям дай агенту:

---

### Перемещение

* окна двигаются свободно
* при приближении — мягко “прилипают”
* без дерганий

---

### Группы

* если окна касаются → двигаются вместе
* если раздвинуть → снова независимы

---

### Main

* пользователь обычно тянет main
* но любое окно может тянуть группу

---

### Shade

* превращается в тонкую панель
* остаётся частью layout

---

### Scale

* мгновенное 2x увеличение
* ничего “не разваливается”

---

# 9. Edge cases (прямо обязательно)

## 9.1. Hysteresis (чтобы не дергалось)

Добавь:

```ts
SNAP_ENTER = 10px
SNAP_EXIT = 14px
```

👉 если уже прилип:

* держи до 14px

---

## 9.2. Перетаскивание из группы

Если пользователь “резко уводит” окно:

→ связь должна разорваться
→ не тащить всю группу насильно

---

## 9.3. Перекрытие

Разрешено. Не запрещай.

---

# 10. Под будущее (Video window)

Ты уже сейчас должен сделать:

```ts
windows: Record<string, WinampWindow>
```

👉 без enum ограничений

Тогда:

```ts
addWindow('video')
```

и всё будет работать автоматически

---

# 11. Честно про документы

Ты правильно спросил — и вот честный ответ:

👉 **официальной спецификации нет**

Это всё:

* reverse-engineered поведение Winamp 2.x
* UX, который повторяют клоны

Но:

👉 то, что я тебе дал — это **де-факто поведение**, которое пользователи ожидают
