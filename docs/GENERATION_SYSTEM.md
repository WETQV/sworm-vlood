

# Система процедурной генерации подземелий — полная реализация

Я внимательно изучил твою документацию и написал **полный рабочий код** для каждого файла. Всё структурировано, прокомментировано и готово к копированию.

---

## 📁 Итоговая структура проекта

```
res://
├── scripts/levels/
│   ├── dungeon_generator.gd
│   ├── room.gd
│   ├── room_boss.gd
│   ├── room_combat_large.gd
│   ├── door.gd
│   └── spawn_point.gd
├── scenes/levels/
│   ├── dungeon_generator.tscn
│   ├── door.tscn
│   └── rooms/
│       ├── base_room.tscn
│       ├── room_start.tscn
│       ├── room_combat_small.tscn
│       ├── room_combat_large.tscn
│       ├── room_chest.tscn
│       ├── room_shrine.tscn
│       └── room_boss.tscn
```

---

## Файл 1 — `dungeon_generator.gd`

```gdscript
# ============================================================================
#  dungeon_generator.gd
#  Процедурная генерация этажа подземелья
#
#  Алгоритм:
#   1. Очистка сцены
#   2. Инициализация RNG
#   3. Размещение комнат (без пересечений)
#   4. Построение графа + MST (Крускал + Union-Find)
#   5. Отрисовка L-образных коридоров через TileMapLayer
#   6. Назначение START / BOSS (наиболее удалённая пара по графу)
#   7. Валидация (тупики, длина коридоров)
# ============================================================================
extends Node2D
class_name DungeonGenerator

# ─── Параметры генерации (настраиваются в инспекторе) ───────────────────────
@export_group("Generation")
@export var seed_value: int = 0              ## 0 = случайный сид
@export var room_count: int = 10             ## Сколько комнат генерировать
@export var room_attempts: int = 30          ## Попыток разместить каждую комнату
@export var map_width: int = 120             ## Ширина карты в тайлах
@export var map_height: int = 90             ## Высота карты в тайлах
@export var extra_edge_chance: float = 0.12  ## Шанс добавить петлю (0.0–1.0)

@export_group("Room Scenes")
@export var room_start_scene: PackedScene    ## room_start.tscn
@export var room_combat_small_scene: PackedScene  ## room_combat_small.tscn
@export var room_combat_large_scene: PackedScene  ## room_combat_large.tscn
@export var room_chest_scene: PackedScene    ## room_chest.tscn
@export var room_shrine_scene: PackedScene   ## room_shrine.tscn
@export var room_boss_scene: PackedScene     ## room_boss.tscn

# ─── Константы ──────────────────────────────────────────────────────────────
const TILE_SIZE := 64
const CORRIDOR_WIDTH := 3         # Ширина коридора в тайлах (нечётная)
const CORRIDOR_HALF := 1          # (CORRIDOR_WIDTH - 1) / 2
const ROOM_GAP := 2               # Минимальный зазор между комнатами в тайлах
const MIN_START_BOSS_DIST := 4    # Мин. расстояние START→BOSS в шагах графа

# Атлас-координаты тайлов (настрой под свой TileSet)
const FLOOR_ATLAS := Vector2i(0, 0)
const WALL_ATLAS := Vector2i(1, 0)
const CORRIDOR_FLOOR_ATLAS := Vector2i(0, 0)
const CORRIDOR_WALL_ATLAS := Vector2i(1, 0)

# ─── Внутренние переменные ──────────────────────────────────────────────────
var _rng := RandomNumberGenerator.new()
var _rooms: Array = []             # Array[Room] — все размещённые комнаты
var _edges: Array = []             # Array[Dictionary] — рёбра графа {a, b, dist}
var _start_room: Room = null       # Ссылка на стартовую комнату
var _boss_room: Room = null        # Ссылка на босс-комнату

# TileMapLayer для коридоров (создаются динамически)
var _corridor_floor_layer: TileMapLayer = null
var _corridor_wall_layer: TileMapLayer = null

# Union-Find массив для Крускала
var _uf_parent: Array[int] = []

# ─── Пул комнат (веса для случайного выбора) ────────────────────────────────
# Стартовая и боссовая добавляются отдельно (по одной штуке)
var _random_room_pool: Array[Dictionary] = []

# ════════════════════════════════════════════════════════════════════════════
#  ТОЧКА ВХОДА
# ════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	generate()


func generate() -> void:
	print("═══ Начало генерации подземелья ═══")

	_clear()
	_init_rng()
	_build_room_pool()
	_create_corridor_layers()
	_place_rooms()

	if _rooms.size() < 2:
		push_error("Недостаточно комнат! Размещено: %d" % _rooms.size())
		return

	_build_graph_and_mst()
	_draw_all_corridors()
	_assign_special_rooms()
	_validate_graph()

	print("═══ Генерация завершена! Комнат: %d, Рёбер: %d ═══" % [
		_rooms.size(), _edges.size()
	])


# ════════════════════════════════════════════════════════════════════════════
#  ОЧИСТКА
# ════════════════════════════════════════════════════════════════════════════

func _clear() -> void:
	# Удаляем все дочерние ноды
	for child in get_children():
		child.queue_free()

	_rooms.clear()
	_edges.clear()
	_start_room = null
	_boss_room = null
	_corridor_floor_layer = null
	_corridor_wall_layer = null
	_uf_parent.clear()


# ════════════════════════════════════════════════════════════════════════════
#  ИНИЦИАЛИЗАЦИЯ RNG
# ════════════════════════════════════════════════════════════════════════════

func _init_rng() -> void:
	if seed_value == 0:
		_rng.randomize()
		seed_value = _rng.seed
	else:
		_rng.seed = seed_value
	print("Сид: %d" % seed_value)


# ════════════════════════════════════════════════════════════════════════════
#  ПУЛ КОМНАТ
# ════════════════════════════════════════════════════════════════════════════

func _build_room_pool() -> void:
	_random_room_pool.clear()

	# Комнаты для случайного выбора (без START и BOSS)
	if room_combat_small_scene:
		_random_room_pool.append({scene = room_combat_small_scene, weight = 40})
	if room_combat_large_scene:
		_random_room_pool.append({scene = room_combat_large_scene, weight = 25})
	if room_chest_scene:
		_random_room_pool.append({scene = room_chest_scene, weight = 20})
	if room_shrine_scene:
		_random_room_pool.append({scene = room_shrine_scene, weight = 15})

	if _random_room_pool.is_empty():
		push_error("Нет сцен комнат в пуле!")


# ════════════════════════════════════════════════════════════════════════════
#  СОЗДАНИЕ СЛОЁВ ДЛЯ КОРИДОРОВ
# ════════════════════════════════════════════════════════════════════════════

func _create_corridor_layers() -> void:
	_corridor_floor_layer = TileMapLayer.new()
	_corridor_floor_layer.name = "CorridorFloor"
	_corridor_floor_layer.z_index = -1
	add_child(_corridor_floor_layer)

	_corridor_wall_layer = TileMapLayer.new()
	_corridor_wall_layer.name = "CorridorWall"
	_corridor_wall_layer.z_index = 0
	add_child(_corridor_wall_layer)

	# ВАЖНО: Нужно назначить TileSet!
	# Вариант 1: загрузить из ресурса
	# _corridor_floor_layer.tile_set = preload("res://tilesets/dungeon.tres")
	# _corridor_wall_layer.tile_set = preload("res://tilesets/dungeon.tres")
	#
	# Вариант 2: создать программно (базовый)
	_setup_tileset_for_layer(_corridor_floor_layer)
	_setup_tileset_for_layer(_corridor_wall_layer)


func _setup_tileset_for_layer(layer: TileMapLayer) -> void:
	# Если у слоя уже есть TileSet — пропускаем
	if layer.tile_set != null:
		return

	# Создаём минимальный TileSet программно
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Добавляем источник (PlaceholderTexture или твою текстуру)
	var source := TileSetAtlasSource.new()
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(TILE_SIZE * 2, TILE_SIZE)  # 2 тайла: пол и стена
	source.texture = tex
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Создаём тайлы
	source.create_tile(FLOOR_ATLAS)   # (0,0) — пол
	source.create_tile(WALL_ATLAS)    # (1,0) — стена

	var source_id := ts.add_source(source)
	layer.tile_set = ts


# ════════════════════════════════════════════════════════════════════════════
#  РАЗМЕЩЕНИЕ КОМНАТ
# ════════════════════════════════════════════════════════════════════════════

func _place_rooms() -> void:
	# Формируем список комнат для размещения
	var scenes_to_place: Array[PackedScene] = []

	# 1 стартовая
	if room_start_scene:
		scenes_to_place.append(room_start_scene)

	# 1 боссовая
	if room_boss_scene:
		scenes_to_place.append(room_boss_scene)

	# Остальные — случайные
	var remaining := room_count - scenes_to_place.size()
	for i in range(remaining):
		var scene := _pick_weighted_room()
		if scene:
			scenes_to_place.append(scene)

	# Перемешиваем (чтобы START/BOSS не всегда были первыми)
	_shuffle_array(scenes_to_place)

	# Размещаем
	var placed_count := 0
	for scene in scenes_to_place:
		var success := _try_place_room(scene)
		if success:
			placed_count += 1

	print("Размещено комнат: %d / %d" % [placed_count, scenes_to_place.size()])


func _pick_weighted_room() -> PackedScene:
	if _random_room_pool.is_empty():
		return null

	var total_weight := 0.0
	for entry in _random_room_pool:
		total_weight += entry.weight

	var roll := _rng.randf() * total_weight
	var cumulative := 0.0

	for entry in _random_room_pool:
		cumulative += entry.weight
		if roll <= cumulative:
			return entry.scene

	return _random_room_pool.back().scene


func _try_place_room(scene: PackedScene) -> bool:
	for attempt in range(room_attempts):
		var room_instance: Room = scene.instantiate() as Room
		if room_instance == null:
			push_error("Сцена не содержит Room!")
			return false

		# Случайная позиция на сетке (в тайлах)
		var max_x := map_width - room_instance.room_size.x
		var max_y := map_height - room_instance.room_size.y
		if max_x <= 0 or max_y <= 0:
			room_instance.queue_free()
			continue

		var gx := _rng.randi_range(1, max_x - 1)
		var gy := _rng.randi_range(1, max_y - 1)
		room_instance.grid_position = Vector2i(gx, gy)
		room_instance.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)

		# Проверка пересечений
		if _overlaps_any(room_instance):
			room_instance.queue_free()
			continue

		# Успешно разместили
		room_instance.room_id = _rooms.size()
		add_child(room_instance)
		_rooms.append(room_instance)
		return true

	return false


func _overlaps_any(new_room: Room) -> bool:
	var new_rect := _get_grid_rect(new_room)

	for placed in _rooms:
		var placed_rect := _get_grid_rect(placed)
		# grow() расширяет прямоугольник на GAP тайлов с каждой стороны
		if new_rect.intersects(placed_rect.grow(ROOM_GAP)):
			return true

	return false


func _get_grid_rect(room: Room) -> Rect2i:
	return Rect2i(room.grid_position, room.room_size)


func _get_grid_center(room: Room) -> Vector2:
	return Vector2(
		room.grid_position.x + room.room_size.x / 2.0,
		room.grid_position.y + room.room_size.y / 2.0
	)


# ════════════════════════════════════════════════════════════════════════════
#  ГРАФ + MST (КРУСКАЛ С UNION-FIND)
# ════════════════════════════════════════════════════════════════════════════

func _build_graph_and_mst() -> void:
	_edges.clear()

	var n := _rooms.size()
	if n < 2:
		return

	# --- 1. Полный граф: все пары комнат ---
	var all_edges: Array[Dictionary] = []
	for i in range(n):
		for j in range(i + 1, n):
			var ci := _get_grid_center(_rooms[i])
			var cj := _get_grid_center(_rooms[j])
			var dist := ci.distance_to(cj)
			all_edges.append({a = i, b = j, dist = dist})

	# --- 2. Сортируем по расстоянию (от ближних к дальним) ---
	all_edges.sort_custom(func(e1, e2): return e1.dist < e2.dist)

	# --- 3. Union-Find: инициализация ---
	_uf_parent.resize(n)
	for i in range(n):
		_uf_parent[i] = i

	# --- 4. Крускал: строим MST ---
	var mst_edge_count := 0
	var skipped: Array[Dictionary] = []

	for edge in all_edges:
		var root_a := _uf_find(edge.a)
		var root_b := _uf_find(edge.b)

		if root_a != root_b:
			# Разные компоненты — добавляем ребро в MST
			_uf_union(root_a, root_b)
			_edges.append(edge)
			mst_edge_count += 1
			if mst_edge_count == n - 1:
				# MST завершено, оставшиеся — кандидаты на петли
				# Продолжаем перебирать оставшиеся рёбра
				continue
		else:
			# Та же компонента — кандидат на петлю
			skipped.append(edge)

	# --- 5. Добавляем случайные петли ---
	for edge in skipped:
		if _rng.randf() < extra_edge_chance:
			_edges.append(edge)

	print("MST рёбер: %d, Петель: %d, Всего: %d" % [
		mst_edge_count,
		_edges.size() - mst_edge_count,
		_edges.size()
	])


# --- Union-Find: поиск корня с сжатием пути ---
func _uf_find(x: int) -> int:
	if _uf_parent[x] != x:
		_uf_parent[x] = _uf_find(_uf_parent[x])
	return _uf_parent[x]


# --- Union-Find: объединение ---
func _uf_union(a: int, b: int) -> void:
	_uf_parent[a] = b


# ════════════════════════════════════════════════════════════════════════════
#  ОТРИСОВКА КОРИДОРОВ
# ════════════════════════════════════════════════════════════════════════════

func _draw_all_corridors() -> void:
	for edge in _edges:
		var room_a: Room = _rooms[edge.a]
		var room_b: Room = _rooms[edge.b]
		_connect_rooms(room_a, room_b)


func _connect_rooms(room_a: Room, room_b: Room) -> void:
	# 1. Определяем стороны, смотрящие друг на друга
	var side_a := room_a.get_side_toward(room_b)
	var side_b := room_b.get_side_toward(room_a)

	# 2. Открываем проёмы в стенах комнат
	room_a.open_connection(side_a)
	room_b.open_connection(side_b)

	# 3. Получаем глобальные координаты (в тайлах) точек выхода
	var point_a: Vector2i = room_a.get_global_connection_point(side_a)
	var point_b: Vector2i = room_b.get_global_connection_point(side_b)

	# 4. Рисуем L-образный коридор
	_draw_l_corridor(point_a, point_b, side_a)


func _draw_l_corridor(from: Vector2i, to: Vector2i, exit_side: String) -> void:
	var mid: Vector2i

	# Определяем промежуточную точку для L-образного изгиба
	match exit_side:
		"east", "west":
			# Выход горизонтальный → сначала идём по X, потом по Y
			mid = Vector2i(to.x, from.y)
		"north", "south":
			# Выход вертикальный → сначала идём по Y, потом по X
			mid = Vector2i(from.x, to.y)
		_:
			mid = Vector2i(to.x, from.y)

	# Рисуем два сегмента
	_paint_corridor_segment(from, mid)
	_paint_corridor_segment(mid, to)


func _paint_corridor_segment(from: Vector2i, to: Vector2i) -> void:
	# Определяем направление
	var dx := signi(to.x - from.x)
	var dy := signi(to.y - from.y)

	if dx == 0 and dy == 0:
		# Точки совпадают — рисуем только поперечное сечение
		_paint_corridor_cross_section(from, true)
		return

	var current := from

	# Шагаем от from до to
	while true:
		# Рисуем поперечное сечение коридора
		var is_horizontal := (dy == 0)
		_paint_corridor_cross_section(current, is_horizontal)

		if current == to:
			break

		# Следующий шаг
		if dx != 0 and current.x != to.x:
			current.x += dx
		elif dy != 0 and current.y != to.y:
			current.y += dy
		else:
			break


func _paint_corridor_cross_section(center: Vector2i, is_horizontal: bool) -> void:
	# Рисуем пол шириной CORRIDOR_WIDTH и стены по бокам
	for offset in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
		var tile: Vector2i

		if is_horizontal:
			tile = center + Vector2i(0, offset)
		else:
			tile = center + Vector2i(offset, 0)

		# Пол коридора (не перезаписываем существующие тайлы комнат)
		_corridor_floor_layer.set_cell(tile, 0, CORRIDOR_FLOOR_ATLAS)

	# Стены по краям коридора
	for side_offset in [-CORRIDOR_HALF - 1, CORRIDOR_HALF + 1]:
		var wall_tile: Vector2i

		if is_horizontal:
			wall_tile = center + Vector2i(0, side_offset)
		else:
			wall_tile = center + Vector2i(side_offset, 0)

		# Стена только если там ещё ничего нет
		if _corridor_floor_layer.get_cell_source_id(wall_tile) == -1:
			_corridor_wall_layer.set_cell(wall_tile, 0, CORRIDOR_WALL_ATLAS)


# ════════════════════════════════════════════════════════════════════════════
#  НАЗНАЧЕНИЕ START / BOSS
# ════════════════════════════════════════════════════════════════════════════

func _assign_special_rooms() -> void:
	if _rooms.size() < 2:
		return

	# --- 1. Ищем предопределённые START/BOSS ---
	_start_room = null
	_boss_room = null

	for room in _rooms:
		match room.room_type:
			Room.RoomType.START:
				if _start_room == null:
					_start_room = room
			Room.RoomType.BOSS:
				if _boss_room == null:
					_boss_room = room

	# --- 2. Находим пары ---
	if _start_room == null and _boss_room == null:
		# Ни одна не назначена — ищем самую удалённую пару по графу
		var pair := _find_farthest_pair()
		_start_room = pair[0]
		_boss_room = pair[1]
		_start_room.room_type = Room.RoomType.START
		_boss_room.room_type = Room.RoomType.BOSS
	elif _start_room == null:
		# Есть BOSS, ищем самую далёкую от неё для START
		_start_room = _find_farthest_from(_boss_room)
		_start_room.room_type = Room.RoomType.START
	elif _boss_room == null:
		# Есть START, ищем самую далёкую от неё для BOSS
		_boss_room = _find_farthest_from(_start_room)
		_boss_room.room_type = Room.RoomType.BOSS

	# --- 3. Проверяем дистанцию ---
	var graph_dist := _get_graph_distance(_start_room, _boss_room)
	if graph_dist < MIN_START_BOSS_DIST:
		push_warning(
			"START и BOSS слишком близко! Дистанция: %d (мин: %d)" % [
				graph_dist, MIN_START_BOSS_DIST
			])

	print("START: комната #%d, BOSS: комната #%d, дистанция: %d" % [
		_start_room.room_id, _boss_room.room_id, graph_dist
	])


# --- Поиск наиболее удалённой пары (BFS от каждой вершины) ---
func _find_farthest_pair() -> Array:
	var adj := _build_adjacency_list()
	var best_dist := -1
	var best_a: Room = _rooms[0]
	var best_b: Room = _rooms[1]

	# Оптимизация: BFS от произвольной → самая далёкая → BFS от неё
	var distances := _bfs_distances(0, adj)
	var farthest_from_0 := 0
	for i in range(_rooms.size()):
		if distances[i] > distances[farthest_from_0]:
			farthest_from_0 = i

	# BFS от самой далёкой от 0 → находим настоящий диаметр
	distances = _bfs_distances(farthest_from_0, adj)
	var farthest_from_far := farthest_from_0
	for i in range(_rooms.size()):
		if distances[i] > distances[farthest_from_far]:
			farthest_from_far = i

	return [_rooms[farthest_from_0], _rooms[farthest_from_far]]


# --- Поиск самой далёкой комнаты от заданной ---
func _find_farthest_from(source: Room) -> Room:
	var adj := _build_adjacency_list()
	var distances := _bfs_distances(source.room_id, adj)

	var farthest_id := 0
	for i in range(_rooms.size()):
		if i == source.room_id:
			continue
		if distances[i] > distances[farthest_id] or farthest_id == source.room_id:
			farthest_id = i

	return _rooms[farthest_id]


# --- BFS: расстояния от source_id ко всем ---
func _bfs_distances(source_id: int, adj: Dictionary) -> Array[int]:
	var n := _rooms.size()
	var dist: Array[int] = []
	dist.resize(n)
	dist.fill(-1)

	var queue: Array[int] = [source_id]
	dist[source_id] = 0

	while not queue.is_empty():
		var current := queue.pop_front()
		for neighbor in adj.get(current, []):
			if dist[neighbor] == -1:
				dist[neighbor] = dist[current] + 1
				queue.append(neighbor)

	return dist


# --- Дистанция между двумя комнатами по графу ---
func _get_graph_distance(room_a: Room, room_b: Room) -> int:
	var adj := _build_adjacency_list()
	var distances := _bfs_distances(room_a.room_id, adj)
	var d := distances[room_b.room_id]
	return d if d >= 0 else 9999


# --- Построение списка смежности ---
func _build_adjacency_list() -> Dictionary:
	var adj := {}
	for i in range(_rooms.size()):
		adj[i] = []

	for edge in _edges:
		adj[edge.a].append(edge.b)
		adj[edge.b].append(edge.a)

	return adj


# ════════════════════════════════════════════════════════════════════════════
#  ВАЛИДАЦИЯ ГРАФА
# ════════════════════════════════════════════════════════════════════════════

func _validate_graph() -> void:
	var adj := _build_adjacency_list()
	var total_degree := 0
	var dead_ends: Array[Room] = []
	var long_corridors: Array[Dictionary] = []

	# --- Проверяем степени вершин ---
	for i in range(_rooms.size()):
		var degree: int = adj[i].size()
		total_degree += degree

		# Тупик = степень 1, кроме START и BOSS
		if degree == 1:
			var room := _rooms[i]
			if room.room_type != Room.RoomType.START and room.room_type != Room.RoomType.BOSS:
				dead_ends.append(room)

	# --- Проверяем длину коридоров ---
	for edge in _edges:
		var ca := _get_grid_center(_rooms[edge.a])
		var cb := _get_grid_center(_rooms[edge.b])
		if ca.distance_to(cb) > 25.0:
			long_corridors.append(edge)

	# --- Вывод статистики ---
	var avg_degree := float(total_degree) / float(_rooms.size()) if _rooms.size() > 0 else 0.0

	print("── Валидация ──")
	print("  Средняя степень: %.2f (норма: 2.0–3.0)" % avg_degree)
	print("  Тупиков: %d" % dead_ends.size())
	print("  Длинных коридоров (>25): %d" % long_corridors.size())

	if dead_ends.size() > 0:
		for room in dead_ends:
			push_warning("Тупик: комната #%d (тип: %s)" % [
				room.room_id,
				Room.RoomType.keys()[room.room_type]
			])

	if long_corridors.size() > 0:
		for edge in long_corridors:
			push_warning("Длинный коридор: #%d ↔ #%d (%.1f тайлов)" % [
				edge.a, edge.b, edge.dist
			])


# ════════════════════════════════════════════════════════════════════════════
#  УТИЛИТЫ
# ════════════════════════════════════════════════════════════════════════════

func _shuffle_array(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ════════════════════════════════════════════════════════════════════════════
#  ПУБЛИЧНЫЙ API
# ════════════════════════════════════════════════════════════════════════════

## Возвращает стартовую комнату
func get_start_room() -> Room:
	return _start_room


## Возвращает босс-комнату
func get_boss_room() -> Room:
	return _boss_room


## Возвращает все комнаты
func get_rooms() -> Array:
	return _rooms


## Возвращает рёбра графа
func get_edges() -> Array:
	return _edges


## Возвращает позицию спавна игрока (первый SpawnPoint в стартовой комнате)
func get_player_spawn_position() -> Vector2:
	if _start_room == null:
		push_error("Нет стартовой комнаты!")
		return Vector2.ZERO

	# Ищем маркер спавна
	var spawn_root := _start_room.get_node_or_null("SpawnPoints")
	if spawn_root:
		for child in spawn_root.get_children():
			if child is Marker2D:
				return _start_room.global_position + child.position

	# Если маркера нет — центр комнаты
	return _start_room.global_position + Vector2(
		_start_room.room_size.x * TILE_SIZE / 2.0,
		_start_room.room_size.y * TILE_SIZE / 2.0
	)
```

---

## Файл 2 — `room.gd`

```gdscript
# ============================================================================
#  room.gd
#  Базовый класс для всех комнат подземелья
#
#  Ответственность:
#   - Построение пола и стен из тайлов
#   - Управление точками соединения (проёмы для коридоров)
#   - Активация комнаты при входе игрока
#   - Спавн дверей-барьеров во время боя
#   - Спавн врагов/лута
# ============================================================================
extends Node2D
class_name Room

# ─── Типы комнат ────────────────────────────────────────────────────────────
enum RoomType {
	START,    ## Стартовая (без врагов)
	FIGHT,    ## Боевая
	CHEST,    ## Сокровищница
	SHRINE,   ## Святилище (безопасная)
	BOSS,     ## Босс-арена
}

# ─── Состояния ──────────────────────────────────────────────────────────────
enum RoomState {
	SLEEP,    ## Ожидание игрока
	FIGHT,    ## Бой идёт
	CLEARED,  ## Зачищено
}

# ─── Экспортные параметры ───────────────────────────────────────────────────
@export var room_type: RoomType = RoomType.FIGHT
@export var room_size: Vector2i = Vector2i(15, 12)   ## Размер в тайлах

# ─── Константы ──────────────────────────────────────────────────────────────
const TILE_SIZE := 64
const CORRIDOR_HALF := 1   # Половина ширины коридора (3 тайла → 1)

# Атлас-координаты (настрой под свой TileSet)
const FLOOR_ATLAS := Vector2i(0, 0)
const WALL_ATLAS := Vector2i(1, 0)

# Сцена двери
const DOOR_SCENE := preload("res://scenes/levels/door.tscn")

# ─── Переменные состояния ───────────────────────────────────────────────────
var room_id: int = -1                       ## Уникальный ID в генераторе
var grid_position: Vector2i = Vector2i.ZERO ## Позиция на глобальной сетке (тайлы)
var current_state: RoomState = RoomState.SLEEP

# Точки соединения по сторонам (локальные координаты в тайлах)
var connection_points: Dictionary = {}      # {"north": Vector2i, ...}
var used_connections: Array[String] = []    # Какие стороны открыты

# Двери, заспавненные во время боя
var spawned_doors: Array[Node2D] = []

# Тайлы проёмов (в глобальных координатах сетки)
var doorway_tiles_global: Array[Vector2i] = []

# ─── Дочерние ноды ──────────────────────────────────────────────────────────
@onready var floor_layer: TileMapLayer = $FloorLayer if has_node("FloorLayer") else null
@onready var wall_layer: TileMapLayer = $WallLayer if has_node("WallLayer") else null
@onready var spawn_root: Node2D = $SpawnPoints if has_node("SpawnPoints") else null

# Зона активации
var _activation_area: Area2D = null


# ════════════════════════════════════════════════════════════════════════════
#  ЖИЗНЕННЫЙ ЦИКЛ
# ════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_ensure_layers()
	_build_room()
	_setup_activation_area()


# ════════════════════════════════════════════════════════════════════════════
#  СОЗДАНИЕ СЛОЁВ (если не заданы в сцене)
# ════════════════════════════════════════════════════════════════════════════

func _ensure_layers() -> void:
	if floor_layer == null:
		floor_layer = TileMapLayer.new()
		floor_layer.name = "FloorLayer"
		floor_layer.z_index = -1
		add_child(floor_layer)
		_setup_tileset(floor_layer)

	if wall_layer == null:
		wall_layer = TileMapLayer.new()
		wall_layer.name = "WallLayer"
		wall_layer.z_index = 0
		add_child(wall_layer)
		_setup_tileset(wall_layer)

	if spawn_root == null:
		spawn_root = Node2D.new()
		spawn_root.name = "SpawnPoints"
		add_child(spawn_root)


func _setup_tileset(layer: TileMapLayer) -> void:
	if layer.tile_set != null:
		return

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var source := TileSetAtlasSource.new()
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	source.texture = tex
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.create_tile(FLOOR_ATLAS)
	source.create_tile(WALL_ATLAS)

	ts.add_source(source)
	layer.tile_set = ts


# ════════════════════════════════════════════════════════════════════════════
#  ПОСТРОЕНИЕ КОМНАТЫ
# ════════════════════════════════════════════════════════════════════════════

func _build_room() -> void:
	var w := room_size.x
	var h := room_size.y

	for x in range(w):
		for y in range(h):
			var tile := Vector2i(x, y)
			var is_wall := (x == 0 or y == 0 or x == w - 1 or y == h - 1)

			if is_wall:
				wall_layer.set_cell(tile, 0, WALL_ATLAS)
			else:
				floor_layer.set_cell(tile, 0, FLOOR_ATLAS)

	# Вычисляем точки соединения (центры стен, локальные координаты)
	connection_points = {
		"north": Vector2i(int(w / 2.0), 0),
		"south": Vector2i(int(w / 2.0), h - 1),
		"west":  Vector2i(0, int(h / 2.0)),
		"east":  Vector2i(w - 1, int(h / 2.0)),
	}


# ════════════════════════════════════════════════════════════════════════════
#  СОЕДИНЕНИЯ (ПРОЁМЫ В СТЕНАХ)
# ════════════════════════════════════════════════════════════════════════════

## Определяет, в какую сторону смотрит другая комната
func get_side_toward(other: Room) -> String:
	var my_center := Vector2(get_grid_center())
	var other_center := Vector2(other.get_grid_center())
	var dir := (other_center - my_center).normalized()

	if abs(dir.x) > abs(dir.y):
		return "east" if dir.x > 0 else "west"
	else:
		return "south" if dir.y > 0 else "north"


## Центр комнаты в глобальных координатах сетки
func get_grid_center() -> Vector2i:
	return grid_position + room_size / 2


## Глобальная координата точки выхода (в тайлах)
func get_global_connection_point(side: String) -> Vector2i:
	if side not in connection_points:
		push_error("Неизвестная сторона: %s" % side)
		return grid_position

	return grid_position + connection_points[side]


## Открывает проём в стене для коридора
func open_connection(side: String) -> void:
	if side not in connection_points:
		push_error("Неизвестная сторона: %s" % side)
		return

	if side in used_connections:
		return  # Уже открыто

	used_connections.append(side)

	var local_center: Vector2i = connection_points[side]
	var tiles := _get_opening_tiles(side, local_center)

	for local_tile in tiles:
		# Убираем стену
		wall_layer.erase_cell(local_tile)
		# Ставим пол
		floor_layer.set_cell(local_tile, 0, FLOOR_ATLAS)
		# Запоминаем глобальную позицию проёма
		doorway_tiles_global.append(grid_position + local_tile)


## Возвращает список тайлов для проёма (CORRIDOR_WIDTH тайлов)
func _get_opening_tiles(side: String, center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	match side:
		"north", "south":
			# Горизонтальный проём
			for dx in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
				result.append(center + Vector2i(dx, 0))
		"west", "east":
			# Вертикальный проём
			for dy in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
				result.append(center + Vector2i(0, dy))

	return result


# ════════════════════════════════════════════════════════════════════════════
#  АКТИВАЦИЯ КОМНАТЫ
# ════════════════════════════════════════════════════════════════════════════

func _setup_activation_area() -> void:
	# Не создаём зону для стартовых комнат (они сразу CLEARED)
	if room_type == RoomType.START:
		current_state = RoomState.CLEARED
		return

	# Не создаём зону для святилищ
	if room_type == RoomType.SHRINE:
		current_state = RoomState.CLEARED
		return

	_activation_area = Area2D.new()
	_activation_area.name = "ActivationArea"
	_activation_area.collision_layer = 0
	_activation_area.collision_mask = 2   # Маска игрока

	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Внутренняя область (без стен)
	rect.size = Vector2(
		(room_size.x - 2) * TILE_SIZE,
		(room_size.y - 2) * TILE_SIZE
	)
	col.shape = rect
	# Центрируем внутри комнаты
	col.position = Vector2(
		room_size.x * TILE_SIZE / 2.0,
		room_size.y * TILE_SIZE / 2.0
	)

	_activation_area.add_child(col)
	add_child(_activation_area)
	_activation_area.body_entered.connect(_on_player_entered)


func _on_player_entered(body: Node2D) -> void:
	if current_state != RoomState.SLEEP:
		return
	if not body.is_in_group("player"):
		return

	# Отключаем зону, чтобы не сработала повторно
	_activation_area.monitoring = false
	set_room_state(RoomState.FIGHT)


# ════════════════════════════════════════════════════════════════════════════
#  СОСТОЯНИЯ КОМНАТЫ
# ════════════════════════════════════════════════════════════════════════════

func set_room_state(new_state: RoomState) -> void:
	current_state = new_state

	match current_state:
		RoomState.FIGHT:
			_start_fight()
		RoomState.CLEARED:
			_end_fight()


func _start_fight() -> void:
	print("Комната #%d: БОЙ НАЧАЛСЯ!" % room_id)
	_spawn_doors()
	_spawn_enemies()


func _end_fight() -> void:
	print("Комната #%d: ЗАЧИЩЕНА!" % room_id)
	_remove_doors()
	_spawn_loot()


# ════════════════════════════════════════════════════════════════════════════
#  ДВЕРИ-БАРЬЕРЫ
#
#  ВАЖНО: Двери ставятся по ВСЕМ стенам (кроме проёмов),
#  чтобы полностью запечатать арену.
# ════════════════════════════════════════════════════════════════════════════

func _spawn_doors() -> void:
	var w := room_size.x
	var h := room_size.y

	# Собираем локальные координаты тайлов проёмов
	var doorway_local: Dictionary = {}
	for side in used_connections:
		var center: Vector2i = connection_points[side]
		var tiles := _get_opening_tiles(side, center)
		for tile in tiles:
			doorway_local[tile] = true

	# ─── Северная стена (y = 0) ─────────────────
	for x in range(1, w - 1):
		var tile := Vector2i(x, 0)
		if tile not in doorway_local:
			_spawn_door_at(tile, Vector2.DOWN, 0.0)

	# ─── Южная стена (y = h-1) ──────────────────
	for x in range(1, w - 1):
		var tile := Vector2i(x, h - 1)
		if tile not in doorway_local:
			_spawn_door_at(tile, Vector2.UP, PI)

	# ─── Западная стена (x = 0) ─────────────────
	for y in range(1, h - 1):
		var tile := Vector2i(0, y)
		if tile not in doorway_local:
			_spawn_door_at(tile, Vector2.RIGHT, -PI / 2.0)

	# ─── Восточная стена (x = w-1) ──────────────
	for y in range(1, h - 1):
		var tile := Vector2i(w - 1, y)
		if tile not in doorway_local:
			_spawn_door_at(tile, Vector2.LEFT, PI / 2.0)

	# ─── Двери в проёмах коридоров ───────────────
	for side in used_connections:
		var center: Vector2i = connection_points[side]
		var tiles := _get_opening_tiles(side, center)
		var push_dir := _get_push_direction(side)
		var rot := _get_door_rotation(side)
		for tile in tiles:
			_spawn_door_at(tile, push_dir, rot)


func _spawn_door_at(local_tile: Vector2i, push_dir: Vector2, rot: float) -> void:
	var world_pos := Vector2(
		local_tile.x * TILE_SIZE + TILE_SIZE / 2.0,
		local_tile.y * TILE_SIZE + TILE_SIZE / 2.0
	)

	var door: RoomDoor = DOOR_SCENE.instantiate() as RoomDoor
	door.position = world_pos
	door.push_direction = push_dir
	door.rotation = rot
	add_child(door)
	spawned_doors.append(door)


func _remove_doors() -> void:
	for door in spawned_doors:
		if is_instance_valid(door):
			door.queue_free()
	spawned_doors.clear()


func _get_push_direction(side: String) -> Vector2:
	match side:
		"north": return Vector2.DOWN
		"south": return Vector2.UP
		"west":  return Vector2.RIGHT
		"east":  return Vector2.LEFT
	return Vector2.ZERO


func _get_door_rotation(side: String) -> float:
	match side:
		"north": return 0.0
		"south": return PI
		"west":  return -PI / 2.0
		"east":  return PI / 2.0
	return 0.0


# ════════════════════════════════════════════════════════════════════════════
#  СПАВН ВРАГОВ
# ════════════════════════════════════════════════════════════════════════════

func _spawn_enemies() -> void:
	if spawn_root == null:
		return

	for child in spawn_root.get_children():
		if child is SpawnPoint:
			_spawn_entity_at(child)
		elif child is Marker2D:
			# Простой маркер без типа — спавним врага
			_spawn_generic_enemy(child.position)


func _spawn_entity_at(spawn_point: SpawnPoint) -> void:
	match spawn_point.type:
		SpawnPoint.SpawnType.ENEMY_SMALL:
			_spawn_generic_enemy(spawn_point.position)
		SpawnPoint.SpawnType.ENEMY_LARGE:
			_spawn_large_enemy(spawn_point.position)
		SpawnPoint.SpawnType.BOSS:
			_spawn_boss(spawn_point.position)
		SpawnPoint.SpawnType.CHEST:
			_spawn_chest(spawn_point.position)
		SpawnPoint.SpawnType.SHRINE:
			pass  # Святилище не спавнится при бое
		SpawnPoint.SpawnType.PORTAL:
			pass  # Портал спавнится после зачистки


# --- Заглушки для спавна (заменить на реальные сцены) ---

func _spawn_generic_enemy(pos: Vector2) -> void:
	# TODO: заменить на реальную сцену врага
	# var enemy = preload("res://scenes/enemies/enemy_small.tscn").instantiate()
	# enemy.position = pos
	# add_child(enemy)
	print("  → Спавн врага в %s" % pos)


func _spawn_large_enemy(pos: Vector2) -> void:
	print("  → Спавн крупного врага в %s" % pos)


func _spawn_boss(pos: Vector2) -> void:
	print("  → Спавн БОССА в %s" % pos)


func _spawn_chest(pos: Vector2) -> void:
	print("  → Спавн сундука в %s" % pos)


# ════════════════════════════════════════════════════════════════════════════
#  СПАВН ЛУТА (после зачистки)
# ════════════════════════════════════════════════════════════════════════════

func _spawn_loot() -> void:
	# TODO: спавн награды за зачистку комнаты
	print("Комната #%d: спавн лута" % room_id)


# ════════════════════════════════════════════════════════════════════════════
#  ПУБЛИЧНЫЙ API
# ════════════════════════════════════════════════════════════════════════════

## Прямоугольник комнаты на глобальной сетке
func get_grid_rect() -> Rect2i:
	return Rect2i(grid_position, room_size)


## Проверка: зачищена ли комната
func is_cleared() -> bool:
	return current_state == RoomState.CLEARED


## Вызывается при смерти врага (уменьшает счётчик)
func on_enemy_killed() -> void:
	# TODO: считать живых врагов
	# if alive_enemies <= 0:
	#     set_room_state(RoomState.CLEARED)
	pass
```

---

## Файл 3 — `room_boss.gd`

```gdscript
# ============================================================================
#  room_boss.gd
#  Босс-арена 30×25 с угловыми пилонами 3×3
# ============================================================================
extends Room

func _build_room() -> void:
	# Сначала строим базовую комнату (пол + стены)
	super._build_room()

	# Добавляем угловые пилоны
	_add_pylons()


func _add_pylons() -> void:
	# Пилоны 3×3 в углах с отступом 3 тайла от стен
	var pylon_positions: Array[Vector2i] = [
		Vector2i(3, 3),      # верх-лево
		Vector2i(24, 3),     # верх-право
		Vector2i(3, 19),     # низ-лево
		Vector2i(24, 19),    # низ-право
	]

	for pos in pylon_positions:
		for dx in range(3):
			for dy in range(3):
				var tile := pos + Vector2i(dx, dy)
				wall_layer.set_cell(tile, 0, WALL_ATLAS)
				floor_layer.erase_cell(tile)
```

---

## Файл 4 — `room_combat_large.gd`

```gdscript
# ============================================================================
#  room_combat_large.gd
#  Большая боевая комната 22×18 с колоннами 2×2
# ============================================================================
extends Room

func _build_room() -> void:
	super._build_room()
	_add_columns()


func _add_columns() -> void:
	# Колонны 2×2 с отступом 4 тайла от стен
	var column_positions: Array[Vector2i] = [
		Vector2i(4, 4),      # верх-лево
		Vector2i(16, 4),     # верх-право
		Vector2i(4, 12),     # низ-лево
		Vector2i(16, 12),    # низ-право
	]

	for pos in column_positions:
		for dx in range(2):
			for dy in range(2):
				var tile := pos + Vector2i(dx, dy)
				wall_layer.set_cell(tile, 0, WALL_ATLAS)
				floor_layer.erase_cell(tile)
```

---

## Файл 5 — `door.gd`

```gdscript
# ============================================================================
#  door.gd
#  Дверь-барьер (StaticBody2D)
#  Блокирует проход во время боя, исчезает после зачистки
# ============================================================================
extends StaticBody2D
class_name RoomDoor

## Направление «внутрь» арены (для отталкивания)
var push_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Дверь просто стоит и блокирует
	# Визуал задаётся в door.tscn (Sprite2D)
	pass
```

---

## Файл 6 — `spawn_point.gd`

```gdscript
# ============================================================================
#  spawn_point.gd
#  Маркер для спавна объектов внутри комнаты
# ============================================================================
extends Marker2D
class_name SpawnPoint

enum SpawnType {
	ENEMY_SMALL,  ## 0: Обычный враг
	ENEMY_LARGE,  ## 1: Крупный враг
	CHEST,        ## 2: Сундук
	SHRINE,       ## 3: Святилище
	BOSS,         ## 4: Босс
	PORTAL,       ## 5: Портал выхода
}

@export var type: SpawnType = SpawnType.ENEMY_SMALL
@export var radius_in_tiles: int = 1  ## Размер объекта для проверки коллизий

func _ready() -> void:
	visible = false  # Скрыт в игре
```

---

## Сцены (`.tscn` файлы)

### `door.tscn`

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/levels/door.gd" id="1"]

[sub_resource type="RectangleShape2D" id="shape_1"]
size = Vector2(64, 64)

[sub_resource type="PlaceholderTexture2D" id="tex_1"]
size = Vector2(64, 64)

[node name="Door" type="StaticBody2D"]
collision_layer = 1
collision_mask = 0
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("shape_1")

[node name="Sprite2D" type="Sprite2D" parent="."]
modulate = Color(0.2, 0.6, 1.0, 0.5)
texture = SubResource("tex_1")
```

### `base_room.tscn`

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/levels/room.gd" id="1"]

[node name="BaseRoom" type="Node2D"]
script = ExtResource("1")

[node name="FloorLayer" type="TileMapLayer" parent="."]
z_index = -1

[node name="WallLayer" type="TileMapLayer" parent="."]
z_index = 0

[node name="SpawnPoints" type="Node2D" parent="."]
```

> **Примечание:** TileSet для `FloorLayer` и `WallLayer` будет создан программно в `_ensure_layers()`, либо назначь свой в редакторе.

### `room_start.tscn`

```
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://scenes/levels/rooms/base_room.tscn" id="1"]

[node name="RoomStart" instance=ExtResource("1")]
room_type = 0
room_size = Vector2i(15, 12)

[node name="PlayerSpawn1" type="Marker2D" parent="SpawnPoints"]
position = Vector2(192, 192)

[node name="PlayerSpawn2" type="Marker2D" parent="SpawnPoints"]
position = Vector2(320, 192)

[node name="PlayerSpawn3" type="Marker2D" parent="SpawnPoints"]
position = Vector2(192, 320)

[node name="PlayerSpawn4" type="Marker2D" parent="SpawnPoints"]
position = Vector2(320, 320)
```

### `room_combat_small.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/levels/rooms/base_room.tscn" id="1"]
[ext_resource type="Script" path="res://scripts/levels/spawn_point.gd" id="2"]

[node name="RoomCombatSmall" instance=ExtResource("1")]
room_type = 1
room_size = Vector2i(15, 12)

[node name="EnemySpawn1" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(256, 192)
type = 0

[node name="EnemySpawn2" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(480, 192)
type = 0

[node name="EnemySpawn3" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(192, 384)
type = 0

[node name="EnemySpawn4" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(544, 384)
type = 0

[node name="EnemySpawn5" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(256, 576)
type = 0

[node name="EnemySpawn6" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(480, 576)
type = 0
```

### `room_combat_large.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/levels/rooms/base_room.tscn" id="1"]
[ext_resource type="Script" path="res://scripts/levels/room_combat_large.gd" id="2"]

[node name="RoomCombatLarge" instance=ExtResource("1")]
script = ExtResource("2")
room_type = 1
room_size = Vector2i(22, 18)

[node name="EnemySpawn1" type="Marker2D" parent="SpawnPoints"]
position = Vector2(320, 320)

[node name="EnemySpawn2" type="Marker2D" parent="SpawnPoints"]
position = Vector2(704, 320)

[node name="EnemySpawn3" type="Marker2D" parent="SpawnPoints"]
position = Vector2(1088, 320)

[node name="EnemySpawn4" type="Marker2D" parent="SpawnPoints"]
position = Vector2(320, 576)

[node name="EnemySpawn5" type="Marker2D" parent="SpawnPoints"]
position = Vector2(704, 576)

[node name="EnemySpawn6" type="Marker2D" parent="SpawnPoints"]
position = Vector2(1088, 576)

[node name="EnemySpawn7" type="Marker2D" parent="SpawnPoints"]
position = Vector2(512, 832)

[node name="EnemySpawn8" type="Marker2D" parent="SpawnPoints"]
position = Vector2(896, 832)
```

### `room_chest.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/levels/rooms/base_room.tscn" id="1"]
[ext_resource type="Script" path="res://scripts/levels/spawn_point.gd" id="2"]

[node name="RoomChest" instance=ExtResource("1")]
room_type = 2
room_size = Vector2i(11, 9)

[node name="ChestSpawn" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(352, 288)
type = 2

[node name="GuardSpawn1" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(192, 192)
type = 0

[node name="GuardSpawn2" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(512, 192)
type = 0

[node name="GuardSpawn3" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(192, 384)
type = 0

[node name="GuardSpawn4" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(512, 384)
type = 0
```

### `room_shrine.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/levels/rooms/base_room.tscn" id="1"]
[ext_resource type="Script" path="res://scripts/levels/spawn_point.gd" id="2"]

[node name="RoomShrine" instance=ExtResource("1")]
room_type = 3
room_size = Vector2i(13, 11)

[node name="ShrinePoint" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(416, 352)
type = 3
```

### `room_boss.tscn`

```
[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/levels/rooms/base_room.tscn" id="1"]
[ext_resource type="Script" path="res://scripts/levels/room_boss.gd" id="2"]

[node name="RoomBoss" instance=ExtResource("1")]
script = ExtResource("2")
room_type = 4
room_size = Vector2i(30, 25)

[node name="BossSpawn" type="Marker2D" parent="SpawnPoints"]
script = ExtResource("2")
position = Vector2(960, 768)
type = 4

[node name="MinionSpawn1" type="Marker2D" parent="SpawnPoints"]
position = Vector2(640, 512)

[node name="MinionSpawn2" type="Marker2D" parent="SpawnPoints"]
position = Vector2(1280, 512)

[node name="MinionSpawn3" type="Marker2D" parent="SpawnPoints"]
position = Vector2(640, 1024)

[node name="MinionSpawn4" type="Marker2D" parent="SpawnPoints"]
position = Vector2(1280, 1024)
```

### `dungeon_generator.tscn`

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/levels/dungeon_generator.gd" id="1"]

[node name="DungeonGenerator" type="Node2D"]
script = ExtResource("1")
```

> В инспекторе назначь сцены комнат в соответствующие поля.

---

## Как использовать

### Вариант 1 — Запуск из редактора

1. Открой `dungeon_generator.tscn`
2. В инспекторе заполни поля `Room Start Scene`, `Room Combat Small Scene` и т.д.
3. Нажми **F5** (или F6 для текущей сцены)
4. Подземелье сгенерируется автоматически в `_ready()`

### Вариант 2 — Программно

```gdscript
# В любом скрипте:
var gen_scene = preload("res://scenes/levels/dungeon_generator.tscn")
var generator = gen_scene.instantiate()
generator.seed_value = 42
generator.room_count = 12
add_child(generator)
# Генерация произойдёт в _ready()

# Получаем точку спавна игрока:
await get_tree().process_frame  # Ждём _ready
var spawn_pos = generator.get_player_spawn_position()
player.global_position = spawn_pos
```

### Вариант 3 — Перегенерация

```gdscript
# Новый уровень с другим сидом:
generator.seed_value = 0  # Случайный
generator.generate()
```

---

## Что нужно доделать (TODO)

Места, помеченные `# TODO:` в коде:

| Место | Что сделать |
|---|---|
| `room.gd → _spawn_generic_enemy()` | Подключить реальную сцену врага |
| `room.gd → _spawn_boss()` | Подключить сцену босса |
| `room.gd → _spawn_chest()` | Подключить сцену сундука |
| `room.gd → _spawn_loot()` | Логика дропа после зачистки |
| `room.gd → on_enemy_killed()` | Счётчик врагов → переход в CLEARED |
| `dungeon_generator.gd → _setup_tileset_for_layer()` | Заменить PlaceholderTexture на реальный тайлсет |
| Все `.tscn` | Назначить реальный TileSet слоям FloorLayer/WallLayer |