extends Node2D
## DungeonGenerator — процедурно генерирует этаж подземелья.
##
## Алгоритм:
##   1. Случайно разбрасываем комнаты на сетке (без пересечений).
##   2. Строим граф «ближайших соседей» (упрощённая триангуляция).
##   3. MST алгоритмом Прима — оставляем только нужные рёбра.
##   4. Часть «лишних» рёбер оставляем для кольцевых путей.
##   5. Рисуем L-образные коридоры шириной CORRIDOR_WIDTH тайлов.
##   6. Назначаем СТАРТ и БОСС-комнаты.
##

# ── Константы ────────────────────────────────────────────────────────────────
const TILE_SIZE      := 64
const CORRIDOR_WIDTH := 3
const FLOOR_ATLAS    := Vector2i(0, 0)
const WALL_ATLAS     := Vector2i(1, 0)
## Прелоад для доступа к RoomType изнутри DungeonGenerator
const RoomScript := preload("res://scripts/levels/room.gd")

# ── Параметры генерации (можно менять в инспекторе) ──────────────────────────
@export var seed_value: int   = 0    ## 0 = случайный
@export var room_count: int   = 10   ## Сколько комнат пытаемся разместить
@export var room_attempts: int = 30  ## Попыток на каждую комнату
@export var map_width:  int   = 120  ## Размер рабочей зоны в тайлах
@export var map_height: int   = 90
## Шанс (0..1) вернуть «срезанное» MST-ребро для кольцевых путей
@export_range(0.0, 1.0) var extra_edge_chance: float = 0.12

# Сцены комнат
@export var room_start_scene:        PackedScene
@export var room_combat_small_scene: PackedScene
@export var room_combat_large_scene: PackedScene
@export var room_chest_scene:        PackedScene
@export var room_shrine_scene:       PackedScene
@export var room_boss_scene:         PackedScene

# ── Ноды ─────────────────────────────────────────────────────────────────────
@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var wall_layer:  TileMapLayer = $WallLayer
@onready var rooms_root:  Node2D       = $Rooms

# ── Внутренние данные ─────────────────────────────────────────────────────────
var _rng: RandomNumberGenerator
var _rooms: Array         # Array[Room]
var _edges: Array         # Array[{a, b, dist}] — выбранные рёбра MST

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	generate()


## Запускает полную генерацию этажа. Можно вызывать повторно для реролла.
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


# ── TileSet (цветные заглушки, без внешнего арта) ────────────────────────────
func _setup_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# 1. Создаём физический слой ДО добавления тайлов
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)   # бит 1 → "walls"
	ts.set_physics_layer_collision_mask(0, 0)

	# 2. Создаём картинку
	var src := TileSetAtlasSource.new()
	var img := Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Color(0.23, 0.23, 0.29))
	img.fill_rect(Rect2i(TILE_SIZE, 0, TILE_SIZE, TILE_SIZE), Color(0.42, 0.42, 0.48))
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# 3. ДОБАВЛЯЕМ SOURCE В TILESET
	# Сначала добавляем, чтобы тайлы "знали" про физический слой
	ts.add_source(src, 0)

	# 4. Регистрируем тайлы
	src.create_tile(Vector2i(0, 0))  # Floor
	src.create_tile(Vector2i(1, 0))  # Wall

	# 5. Привязываем коллизию к стене
	var wall_data: TileData = src.get_tile_data(Vector2i(1, 0), 0)
	var half := float(TILE_SIZE) / 2.0
	var wall_polygon := PackedVector2Array([
		Vector2(-half, -half),
		Vector2( half, -half),
		Vector2( half,  half),
		Vector2(-half,  half),
	])
	wall_data.add_collision_polygon(0)
	wall_data.set_collision_polygon_points(0, 0, wall_polygon)

	floor_layer.tile_set = ts
	wall_layer.tile_set  = ts


# ── Размещение комнат ─────────────────────────────────────────────────────────
func _place_rooms() -> void:
	# Порядок и количество типов комнат
	var pool: Array = _build_room_pool()

	for scene in pool:
		if scene == null:
			push_warning("[DungeonGenerator] Сцена комнаты не назначена в инспекторе!")
			continue
		_try_place_room(scene)


## Возвращает список сцен комнат в нужном составе
func _build_room_pool() -> Array:
	var pool := []
	# Стартовая и босс-комнаты — всегда одна
	pool.append(room_start_scene)
	pool.append(room_boss_scene)

	# Остальные — случайный микс
	var n := room_count - 2
	for i in range(n):
		var r := _rng.randi_range(0, 3)
		match r:
			0: pool.append(room_combat_small_scene)
			1: pool.append(room_combat_large_scene)
			2: pool.append(room_chest_scene)
			3: pool.append(room_shrine_scene)
	return pool


func _try_place_room(scene: PackedScene) -> void:
	var room: Node2D = scene.instantiate()
	rooms_root.add_child(room)

	# Нужен доступ к room_size — ищем скрипт
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
			# Место найдено — рисуем комнату на общем тайлмапе и регистрируем
			room.room_id = _rooms.size()
			_rooms.append(room)
			_blit_room(room)
			return

	# Не удалось разместить — убираем
	room.queue_free()


## Проверяет, пересекается ли новая комната с уже размещёнными (с зазором 2 тайла)
func _overlaps_any(new_room: Node2D) -> bool:
	var GAP := 2
	var new_rect: Rect2i = new_room.get_grid_rect().grow(GAP)
	for placed in _rooms:
		if new_rect.intersects(placed.get_grid_rect().grow(GAP)):
			return true
	return false


## Рисует тайлы одной комнаты на глобальных слоях (floor + wall)
func _blit_room(room: Node2D) -> void:
	var pos: Vector2i  = room.grid_position
	
	# Копируем локальный дизайн комнаты (пол, колонны, стены) в глобальный слой!
	var r_floor: TileMapLayer = room.get_node("FloorLayer")
	var r_wall: TileMapLayer = room.get_node("WallLayer")
	
	for cell in r_floor.get_used_cells():
		var global_cell: Vector2i = pos + cell
		floor_layer.set_cell(global_cell, 0, FLOOR_ATLAS)
		wall_layer.erase_cell(global_cell)

	for cell in r_wall.get_used_cells():
		var global_cell: Vector2i = pos + cell
		wall_layer.set_cell(global_cell, 0, WALL_ATLAS)
		floor_layer.erase_cell(global_cell)

	# Удаляем локальные TileMapLayers комнаты, чтобы сэкономить ресурсы 
	# и не рендерить тайлы дважды без коллизий.
	r_floor.queue_free()
	r_wall.queue_free()

	# Позиционируем саму комнату (для спавнов) 
	room.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)


# ── Граф + MST (алгоритм Прима) ──────────────────────────────────────────────
func _build_graph_and_mst() -> void:
	if _rooms.size() < 2:
		return

	# Все возможные рёбра (полный граф по центрам комнат)
	var all_edges: Array = []
	for i in range(_rooms.size()):
		for j in range(i + 1, _rooms.size()):
			var ca: Vector2 = Vector2(_rooms[i].get_grid_center())
			var cb: Vector2 = Vector2(_rooms[j].get_grid_center())
			all_edges.append({ "a": i, "b": j, "dist": ca.distance_to(cb) })

	# Сортируем по расстоянию
	all_edges.sort_custom(func(e1, e2): return e1["dist"] < e2["dist"])

	# MST через алгоритм Крускала на Union-Find
	var parent: Array[int] = []
	for i in range(_rooms.size()):
		parent.append(i)
	var mst_edges: Array = []
	var skipped:   Array = []

	for edge in all_edges:
		var ra := _find(parent, edge["a"])
		var rb := _find(parent, edge["b"])
		if ra != rb:
			# Ребро входит в MST
			parent[ra] = rb
			mst_edges.append(edge)
			_edges.append(edge)
		else:
			skipped.append(edge)

	# Возвращаем часть «срезанных» рёбер для петель
	for edge in skipped:
		if _rng.randf() < extra_edge_chance:
			_edges.append(edge)


func _find(parent: Array, i: int) -> int:
	if parent[i] != i:
		parent[i] = _find(parent, parent[i])
	return parent[i]


# ── Рисование коридоров ───────────────────────────────────────────────────────
func _draw_corridors() -> void:
	for edge in _edges:
		var ca: Vector2i = _rooms[edge["a"]].get_grid_center()
		var cb: Vector2i = _rooms[edge["b"]].get_grid_center()
		_draw_l_corridor(ca, cb)


## Рисует L-образный коридор шириной CORRIDOR_WIDTH между двумя центрами.
## Сначала идёт по X, потом по Y (mid-point = (bx, ay)).
func _draw_l_corridor(a: Vector2i, b: Vector2i) -> void:
	var mid := Vector2i(b.x, a.y)

	# горизонтальный отрезок a → mid
	_draw_corridor_segment(a, mid, true)
	# вертикальный отрезок mid → b
	_draw_corridor_segment(mid, b, false)


func _draw_corridor_segment(from: Vector2i, to: Vector2i, horizontal: bool) -> void:
	var half := CORRIDOR_WIDTH / 2

	var x_min := mini(from.x, to.x)
	var x_max := maxi(from.x, to.x)
	var y_min := mini(from.y, to.y)
	var y_max := maxi(from.y, to.y)

	if horizontal:
		# Расширяем вниз/вверх
		for x in range(x_min, x_max + 1):
			for dy in range(-half, CORRIDOR_WIDTH - half):
				_carve(Vector2i(x, from.y + dy))
	else:
		# Расширяем влево/вправо
		for y in range(y_min, y_max + 1):
			for dx in range(-half, CORRIDOR_WIDTH - half):
				_carve(Vector2i(from.x + dx, y))


## «Вырезает» одну тайловую позицию — ставит пол и убирает стену.
func _carve(tile: Vector2i) -> void:
	if tile.x < 0 or tile.y < 0 or tile.x >= map_width or tile.y >= map_height:
		return
	floor_layer.set_cell(tile, 0, FLOOR_ATLAS)
	wall_layer.erase_cell(tile)

	# Добавляем стены вокруг, только если там ещё нет пола (граница коридора)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var neighbor := tile + Vector2i(dx, dy)
			if neighbor.x < 0 or neighbor.y < 0:
				continue
			if neighbor.x >= map_width or neighbor.y >= map_height:
				continue
			# Ставим стену только там, где нет пола (-1 = пустая клетка)
			if floor_layer.get_cell_source_id(neighbor) == -1:
				wall_layer.set_cell(neighbor, 0, WALL_ATLAS)


# ── Назначение специальных комнат ─────────────────────────────────────────────
func _assign_special_rooms() -> void:
	if _rooms.size() == 0:
		return

	# Комнаты типа START и BOSS добавлялись первыми в пул (индексы 0 и 1)
	# Если они successfully сгенерированы — переназначаем их позиции:
	# СТАРТ = левее всего, БОСС = правее всего
	var start_room: Node2D = null
	var boss_room:  Node2D = null

	for room in _rooms:
		if room.room_type == RoomScript.RoomType.START:
			start_room = room
		if room.room_type == RoomScript.RoomType.BOSS:
			boss_room = room

	if start_room:
		print("[DungeonGenerator] Старт: тайл %s" % start_room.grid_position)
	if boss_room:
		print("[DungeonGenerator] Босс: тайл %s" % boss_room.grid_position)
