extends Node2D

# DungeonGenerator — процедурно генерирует этаж подземелья.
# Алгоритм:
# 1. Случайно разбрасываем комнаты на сетке (без пересечений).
# 2. Строим полный граф по центрам комнат.
# 3. MST алгоритмом Крускала (Union-Find) — оставляем только нужные рёбра.
# 4. Часть «лишних» рёбер оставляем для кольцевых путей.
# 5. Рисуем L-образные коридоры шириной CORRIDOR_WIDTH тайлов.
# 6. Назначаем СТАРТ и БОСС-комнаты по пространственному принципу.

# ── Константы ────────────────────────────────────────────────────────────────
const TILE_SIZE       := 64
const CORRIDOR_WIDTH  := 3   # Должно быть нечётным для идеального центрирования
const FLOOR_ATLAS     := Vector2i(0, 0)
const WALL_ATLAS      := Vector2i(1, 0)

# Прелоад для доступа к RoomType
const RoomScript := preload("res://scripts/levels/room.gd")

# ── Параметры генерации ───────────────────────────────────────────────────────
@export var seed_value: int = 0
@export var room_count: int = 10
@export var room_attempts: int = 30
@export var map_width: int = 120
@export var map_height: int = 90

@export_range(0.0, 1.0) var extra_edge_chance: float = 0.12

@export var room_start_scene: PackedScene
@export var room_combat_small_scene: PackedScene
@export var room_combat_large_scene: PackedScene
@export var room_chest_scene: PackedScene
@export var room_shrine_scene: PackedScene
@export var room_boss_scene: PackedScene

# ── Ноды ──────────────────────────────────────────────────────────────────────
@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var wall_layer:  TileMapLayer = $WallLayer
@onready var rooms_root:  Node2D       = $Rooms

# ── Внутренние данные ─────────────────────────────────────────────────────────
var _rng:   RandomNumberGenerator
var _rooms: Array   # Array[Room]
var _edges: Array   # Array[{a, b, dist}]

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	call_deferred("generate")

func generate() -> void:
	_clear()
	_init_rng()
	_setup_tileset()
	_place_rooms()
	_build_graph_and_mst()
	_draw_corridors()
	_assign_special_rooms()
	print("[DungeonGenerator] Готово! Комнат: %d, Коридоров: %d" % [_rooms.size(), _edges.size()])

# ── Очистка ───────────────────────────────────────────────────────────────────
func _clear() -> void:
	floor_layer.clear()
	wall_layer.clear()
	# Сначала отключаем TileSet, чтобы физический сервер не пытался обращаться к ячейкам
	floor_layer.tile_set = null
	wall_layer.tile_set  = null
	
	for child in rooms_root.get_children():
		child.queue_free()
	_rooms = []
	_edges = []

# ── RNG ───────────────────────────────────────────────────────────────────────
func _init_rng() -> void:
	_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

# ── TileSet ───────────────────────────────────────────────────────────────────
func _setup_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# 1. Сначала создаём слои в TileSet
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1) # Стены на 1 слое
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_navigation_layer()

	# 2. Создаём источник
	var src := TileSetAtlasSource.new()
	var img := Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0,         0, TILE_SIZE, TILE_SIZE), Color(0.23, 0.23, 0.29))
	img.fill_rect(Rect2i(TILE_SIZE, 0, TILE_SIZE, TILE_SIZE), Color(0.42, 0.42, 0.48))
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# 3. ВАЖНО: Добавляем источник в TileSet ДО создания тайлов и настройки данных
	ts.add_source(src, 0)
	
	# 4. Теперь создаём тайлы — они сразу увидят структуру слоёв TileSet
	src.create_tile(Vector2i(0, 0))  # Floor
	src.create_tile(Vector2i(1, 0))  # Wall

	# 5. Настраиваем данные тайлов
	var half    := float(TILE_SIZE) / 2.0
	var sq_poly := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2( half,  half), Vector2(-half, half),
	])
	
	# Стены (коллизия)
	var wall_data: TileData = src.get_tile_data(Vector2i(1, 0), 0)
	if wall_data:
		wall_data.add_collision_polygon(0)
		wall_data.set_collision_polygon_points(0, 0, sq_poly)

	# Пол (навигация)
	var floor_data: TileData = src.get_tile_data(Vector2i(0, 0), 0)
	if floor_data:
		var nav_poly := NavigationPolygon.new()
		nav_poly.vertices = sq_poly
		nav_poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		floor_data.set_navigation_polygon(0, nav_poly)

	# 6. Назначаем готовый TileSet слоям
	floor_layer.tile_set = ts
	wall_layer.tile_set  = ts

# ── Размещение комнат ─────────────────────────────────────────────────────────
func _place_rooms() -> void:
	var pool: Array = _build_room_pool()
	for scene in pool:
		if scene == null:
			push_warning("[DungeonGenerator] Сцена комнаты не назначена в инспекторе!")
			continue
		_try_place_room(scene)

func _build_room_pool() -> Array:
	var pool := []
	pool.append(room_start_scene)
	pool.append(room_boss_scene)
	var n := room_count - 2
	for i in range(n):
		match _rng.randi_range(0, 3):
			0: pool.append(room_combat_small_scene)
			1: pool.append(room_combat_large_scene)
			2: pool.append(room_chest_scene)
			3: pool.append(room_shrine_scene)
	return pool

func _try_place_room(scene: PackedScene) -> void:
	var room: Node2D = scene.instantiate()
	rooms_root.add_child(room)

	if not room.has_method("get_grid_rect"):
		push_error("[DungeonGenerator] %s не наследует Room!" % scene.resource_path)
		room.queue_free()
		return

	for _attempt in range(room_attempts):
		var pos := Vector2i(
			_rng.randi_range(1, map_width  - room.room_size.x - 1),
			_rng.randi_range(1, map_height - room.room_size.y - 1)
		)
		room.grid_position = pos

		if not _overlaps_any(room):
			room.room_id = _rooms.size()
			_rooms.append(room)
			_blit_room(room)
			return

	room.queue_free()

# ИСПРАВЛЕНИЕ: grow применяется только к одному из прямоугольников.
# Прежде оба rect росли на GAP — итоговый зазор был 4 тайла вместо 2.
func _overlaps_any(new_room: Node2D) -> bool:
	const GAP := 2
	var new_rect: Rect2i = new_room.get_grid_rect()
	for placed in _rooms:
		# Расширяем уже размещённую комнату на GAP — это и даёт отступ GAP тайлов
		if new_rect.intersects(placed.get_grid_rect().grow(GAP)):
			return true
	return false

func _blit_room(room: Node2D) -> void:
	var pos: Vector2i = room.grid_position

	var r_floor: TileMapLayer = room.get_node("FloorLayer")
	var r_wall:  TileMapLayer = room.get_node("WallLayer")

	for cell in r_floor.get_used_cells():
		var g := pos + cell
		floor_layer.set_cell(g, 0, FLOOR_ATLAS)
		wall_layer.erase_cell(g)

	for cell in r_wall.get_used_cells():
		var g := pos + cell
		wall_layer.set_cell(g, 0, WALL_ATLAS)
		floor_layer.erase_cell(g)

	# ВАЖНО: устанавливаем world-позицию ДО удаления слоёв,
	# чтобы room.position всегда был корректен для get_world_center().
	room.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)

	r_floor.queue_free()
	r_wall.queue_free()

# ── Граф + MST (Крускал + Union-Find) ────────────────────────────────────────
func _build_graph_and_mst() -> void:
	if _rooms.size() < 2:
		return

	# Полный граф по центрам комнат
	var all_edges: Array = []
	for i in range(_rooms.size()):
		for j in range(i + 1, _rooms.size()):
			var ca := Vector2(_rooms[i].get_grid_center())
			var cb := Vector2(_rooms[j].get_grid_center())
			all_edges.append({ "a": i, "b": j, "dist": ca.distance_to(cb) })

	all_edges.sort_custom(func(e1, e2): return e1["dist"] < e2["dist"])

	# Union-Find
	var parent: Array[int] = []
	for i in range(_rooms.size()):
		parent.append(i)

	var skipped: Array = []

	for edge in all_edges:
		var ra := _find(parent, edge["a"])
		var rb := _find(parent, edge["b"])
		if ra != rb:
			parent[ra] = rb
			_edges.append(edge)
		else:
			skipped.append(edge)

	# Дополнительные рёбра для кольцевых маршрутов
	for edge in skipped:
		if _rng.randf() < extra_edge_chance:
			_edges.append(edge)

# ИСПРАВЛЕНИЕ: сигнатура теперь явно Array[int], как и переданный аргумент.
func _find(parent: Array[int], i: int) -> int:
	if parent[i] != i:
		parent[i] = _find(parent, parent[i])   # сжатие пути
	return parent[i]

# ── Коридоры ──────────────────────────────────────────────────────────────────
func _draw_corridors() -> void:
	for edge in _edges:
		var ca: Vector2i = _rooms[edge["a"]].get_grid_center()
		var cb: Vector2i = _rooms[edge["b"]].get_grid_center()
		_draw_l_corridor(ca, cb, edge)

func _draw_l_corridor(a: Vector2i, b: Vector2i, edge: Dictionary) -> void:
	# Точка излома: сначала по X, потом по Y
	var mid := Vector2i(b.x, a.y)
	_draw_corridor_segment(a,   mid, true,  edge)
	_draw_corridor_segment(mid, b,   false, edge)

func _draw_corridor_segment(from: Vector2i, to: Vector2i, horizontal: bool, edge: Dictionary) -> void:
	# Для CORRIDOR_WIDTH = 3: half = 1, range(-1, 2) → [-1, 0, 1] — ровно 3 тайла с центром на оси.
	# Формула корректна для любого нечётного CORRIDOR_WIDTH.
	var half  := int(float(CORRIDOR_WIDTH) / 2.0)
	var x_min := mini(from.x, to.x)
	var x_max := maxi(from.x, to.x)
	var y_min := mini(from.y, to.y)
	var y_max := maxi(from.y, to.y)

	var room_a: Node2D = _rooms[edge["a"]]
	var room_b: Node2D = _rooms[edge["b"]]

	if horizontal:
		for x in range(x_min, x_max + 1):
			for dy in range(-half, half + 1):
				_carve(Vector2i(x, from.y + dy), room_a, room_b)
	else:
		for y in range(y_min, y_max + 1):
			for dx in range(-half, half + 1):
				_carve(Vector2i(from.x + dx, y), room_a, room_b)

func _carve(tile: Vector2i, room_a: Node2D, room_b: Node2D) -> void:
	if tile.x < 0 or tile.y < 0 or tile.x >= map_width or tile.y >= map_height:
		return

	# ИСПРАВЛЕНИЕ: точная проверка границы комнаты, а не нечёткий grow(1).
	# Стена принадлежит комнате, если тайл лежит ровно на её периметре.
	if wall_layer.get_cell_source_id(tile) != -1:
		if _is_room_border_tile(room_a, tile):
			if tile not in room_a.door_slots:
				room_a.door_slots.append(tile)
		elif _is_room_border_tile(room_b, tile):
			if tile not in room_b.door_slots:
				room_b.door_slots.append(tile)

	floor_layer.set_cell(tile, 0, FLOOR_ATLAS)
	wall_layer.erase_cell(tile)

	# Обрамляем пустые соседние тайлы стеной (граница коридора)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nb := tile + Vector2i(dx, dy)
			if nb.x < 0 or nb.y < 0 or nb.x >= map_width or nb.y >= map_height:
				continue
			if floor_layer.get_cell_source_id(nb) == -1:
				wall_layer.set_cell(nb, 0, WALL_ATLAS)

# Возвращает true, если тайл tile находится ровно на периметре комнаты room.
func _is_room_border_tile(room: Node2D, tile: Vector2i) -> bool:
	var local: Vector2i = tile - room.grid_position
	var w: int = room.get("room_size").x
	var h: int = room.get("room_size").y
	# Тайл должен быть внутри расширенного прямоугольника (±1 от стены)
	if local.x < -1 or local.y < -1 or local.x > w or local.y > h:
		return false
	# И находиться на одной из четырёх сторон периметра (включая внешний контур ±1)
	return local.x <= 0 or local.y <= 0 or local.x >= w - 1 or local.y >= h - 1

# ── Назначение специальных комнат ─────────────────────────────────────────────
# ИСПРАВЛЕНИЕ: реальное пространственное назначение.
# START = самая левая комната, BOSS = самая правая.
# Если в пуле уже есть START/BOSS-комнаты, просто проверяем их позиции.
func _assign_special_rooms() -> void:
	if _rooms.size() == 0:
		return

	# Ищем уже назначенные специальные комнаты
	var start_room: Node2D = null
	var boss_room:  Node2D = null
	var other_rooms: Array = []

	for room in _rooms:
		if room.room_type == RoomScript.RoomType.START:
			start_room = room
		elif room.room_type == RoomScript.RoomType.BOSS:
			boss_room = room
		else:
			other_rooms.append(room)

	# Если обе специальные комнаты размещены — убеждаемся что они далеко друг от друга.
	# Если нет — переназначаем из обычных комнат по принципу «крайние по X».
	if start_room == null or boss_room == null:
		push_warning("[DungeonGenerator] START или BOSS комната не была размещена. Переназначаю из обычных.")
		# Сортируем все комнаты по X-центру
		var sorted := _rooms.duplicate()
		sorted.sort_custom(func(a, b): return a.get_grid_center().x < b.get_grid_center().x)
		if start_room == null and sorted.size() > 0:
			start_room = sorted[0]
			start_room.room_type = RoomScript.RoomType.START
		if boss_room == null and sorted.size() > 1:
			boss_room = sorted[-1]
			boss_room.room_type = RoomScript.RoomType.BOSS
	else:
		# Оба размещены — проверяем, не стоят ли они слишком близко
		var dist: float = Vector2(start_room.get_grid_center()).distance_to(
			Vector2(boss_room.get_grid_center()))
		if dist < 20.0:
			push_warning("[DungeonGenerator] START и BOSS слишком близко (%.1f тайлов). Рассмотри больший map_width." % dist)

	if start_room:
		print("[DungeonGenerator] Старт: тайл %s" % start_room.grid_position)
	if boss_room:
		print("[DungeonGenerator] Босс:  тайл %s" % boss_room.grid_position)
