# 🎨 Настройка TileSet для генератора подземелий

## Проблема
Раньше каждый `TileMapLayer` создавал свой собственный `TileSet` программно. Это приводило к:
- ❌ Разным тайлам в комнатах и коридорах
- ❌ Дырам на стыках слоёв (нет коллизии)
- ❌ Игрок проваливался между комнатой и коридором

## Решение
**Единый глобальный TileSet** для всего уровня:
- ✅ `GlobalFloor` и `GlobalWall` используют **один и тот же** ресурс `dungeon_tileset.tres`
- ✅ Комнаты блитируются в глобальные слои → нет стыков
- ✅ Коллизия работает везде

---

## 📋 Инструкция по настройке

### Шаг 1: Создай TileSet ресурс

**Вариант А: Автоматически (рекомендуется)**

1. Открой Godot Editor
2. В панели **FileSystem** найди `scripts/editor/create_tileset.gd`
3. Нажми **правой кнопкой** → **Run** (или Ctrl+Shift+X)
4. В консоли появится: `✅ TileSet создан: res://tilesets/dungeon_tileset.tres`

**Вариант Б: Вручную в редакторе**

1. В панели **FileSystem** нажми **правой кнопкой** → **Create New** → **Resource**
2. Выбери `TileSet`
3. Назови `dungeon_tileset.tres`, сохрани в `res://tilesets/`
4. Настрой:
   - **Tile Size**: `64x64`
   - **Add Physics Layer** → Collision Layer: `1` (walls)
   - **Add Navigation Layer**
   - Добавь **TileSetAtlasSource**
   - Создай текстуру 128x64 (пол 64x64 серый, стена 64x64 коричневый)
   - Создай тайлы `(0,0)` и `(1,0)`
   - Для стены добавь **Collision Polygon** (квадрат 64x64)
   - Для пола добавь **Navigation Polygon** (квадрат 64x64)

---

### Шаг 2: Настрой сцену DungeonGenerator

1. Открой `scenes/levels/dungeon_generator.tscn`
2. Выбери ноду `GlobalFloor`
3. В инспекторе найди **Tile Set**
4. Перетащи `res://tilesets/dungeon_tileset.tres`
5. Повтори для `GlobalWall`

**Проверка:**
- ✅ У обоих слоёв **одинаковый** TileSet
- ✅ У `GlobalFloor` z_index = `-1`
- ✅ У `GlobalWall` z_index = `0`

---

### Шаг 3: Проверь сцены комнат

1. Открой `scenes/levels/rooms/base_room.tscn`
2. Убедись что `FloorLayer` и `WallLayer` имеют **тот же TileSet**
3. Если нет — перетащи `dungeon_tileset.tres`

**Повтори для всех комнат:**
- `room_start.tscn`
- `room_combat_small.tscn`
- `room_combat_large.tscn`
- `room_chest.tscn`
- `room_shrine.tscn`
- `room_boss.tscn`

---

## 🔍 Проверка работы

### Тест 1: Запуск генерации
1. Открой `scenes/levels/main.tscn` или `scenes/game/game.tscn`
2. Запусти сцену (F6)
3. В консоли должно быть:
   ```
   ═══ Начало генерации подземелья ═══
   Сид: 12345
   Размещено комнат: 10 / 10
   MST рёбер: 9, Петель: 1, Всего: 10
   START: комната #3, BOSS: комната #7, дистанция: 5
   ═══ Генерация завершена! ═══
   ```

### Тест 2: Коллизия стен
1. Запусти игру
2. Походи к краю комнаты
3. Игрок **не должен** проходить сквозь стены
4. Походи в коридор между комнатами
5. На стыке комната-коридор **не должно** быть дыр

### Тест 3: Визуальная проверка
1. Пол должен быть **серым** `Color(0.23, 0.23, 0.29)`
2. Стены должны быть **коричневыми** `Color(0.42, 0.42, 0.48)`
3. **Не должно** быть розово-фиолетовых `PlaceholderTexture`

---

## 🐛 Возможные проблемы

### Ошибка: "TileSet not found"
**Симптомы:** Розовые квадраты вместо тайлов

**Решение:**
```gdscript
# В dungeon_generator.tscn проверь:
[node name="GlobalFloor" type="TileMapLayer"]
tile_set = ExtResource("1_tileset")  # Должен быть!

[node name="GlobalWall" type="TileMapLayer"]
tile_set = ExtResource("1_tileset")  # Тот же самый!
```

### Ошибка: "Игрок проваливается между комнатой и коридором"
**Симптомы:** На стыке комнат и коридора нет коллизии

**Причина:** `GlobalFloor` и `GlobalWall` используют **разные** TileSet

**Решение:** Убедись что оба слоя используют `res://tilesets/dungeon_tileset.tres`

### Ошибка: "Двери не закрывают проёмы"
**Симптомы:** После зачистки комнаты двери исчезают, но проход остаётся закрытым

**Причина:** Дверь имеет размер 64x64, а проём 192x64 (3 тайла)

**Решение:** Проверь `scenes/levels/door.tscn`:
```gdscript
[sub_resource type="RectangleShape2D" id="shape_collision"]
size = Vector2(192, 64)  # 3 тайла!
```

---

## 📁 Итоговая структура

```
res://
├── tilesets/
│   └── dungeon_tileset.tres      # ← Единый TileSet для всего
├── scenes/levels/
│   ├── dungeon_generator.tscn    # GlobalFloor + GlobalWall (один TileSet)
│   └── rooms/
│       ├── base_room.tscn        # FloorLayer + WallLayer (тот же TileSet)
│       ├── room_start.tscn
│       └── ...
└── scripts/
    ├── levels/
    │   ├── dungeon_generator.gd  # Блитирование в глобальные слои
    │   └── room.gd               # Локальные слои → блитирование
    └── editor/
        └── create_tileset.gd     # Скрипт создания TileSet
```

---

## ✅ Чеклист готовности

- [ ] `dungeon_tileset.tres` создан в `res://tilesets/`
- [ ] `GlobalFloor` использует `dungeon_tileset.tres`
- [ ] `GlobalWall` использует `dungeon_tileset.tres`
- [ ] Все комнаты используют `dungeon_tileset.tres`
- [ ] Запуск генерации работает без ошибок
- [ ] Игрок не проходит сквозь стены
- [ ] Нет дыр на стыке комната-коридор
- [ ] Нет розово-фиолетовых текстур

**Если всё отмечено ✅ — готово! Можно играть!** 🎮
