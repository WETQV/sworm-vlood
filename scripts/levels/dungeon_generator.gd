# ============================================================================
#  dungeon_generator.gd
#  Процедурная генерация этажа подземелья
#
#  Алгоритм:
#   1. Очистка сцены
#   2. Инициализация RNG
#   3. Размещение комнат (без пересечений) → блитирование в глобальные слои
#   4. Построение графа + MST (Крускал + Union-Find)
#   5. Отрисовка L-образных коридоров в глобальные слои
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

# Атлас-координаты тайлов (должны совпадать с TileSet в редакторе)
const FLOOR_ATLAS := Vector2i(0, 0)
const WALL_ATLAS := Vector2i(1, 0)

# ─── Глобальные слои (назначаются в редакторе!) ─────────────────────────────
@onready var global_floor: TileMapLayer = $GlobalFloor
@onready var global_wall:  TileMapLayer = $GlobalWall

# ─── Внутренние переменные ──────────────────────────────────────────────────
var _rng := RandomNumberGenerator.new()
var _rooms: Array = []             # Array[Room] — все размещённые комнаты
var _edges: Array = []             # Array[Dictionary] — рёбра графа {a, b, dist}
var _start_room: Room = null       # Ссылка на стартовую комнату
var _boss_room: Room = null        # Ссылка на босс-комнату

# Union-Find массив для Крускала
var _uf_parent: Array[int] = []

# ─── Пул комнат (веса для случайного выбора) ────────────────────────────────
var _random_room_pool: Array[Dictionary] = []

# ════════════════════════════════════════════════════════════════════════════
#  ТОЧКА ВХОДА
# ════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Создаём TileSet если не назначен
	_setup_tileset()
	generate()


func _setup_tileset() -> void:
	var ts := _create_dungeon_tileset()
	global_floor.tile_set = ts
	global_wall.tile_set = ts


func _create_dungeon_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# ── Физический слой 0 (стены) ──
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)  # слой "walls"
	ts.set_physics_layer_collision_mask(0, 0)

	# ── Навигационный слой 0 (пол) ──
	ts.add_navigation_layer()

	# ── Источник тайлов ──
	var src := TileSetAtlasSource.new()
	
	# Создаём текстуру: пол (серый) и стена (коричневый)
	var img := Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Color(0.23, 0.23, 0.29))   # пол
	img.fill_rect(Rect2i(TILE_SIZE, 0, TILE_SIZE, TILE_SIZE), Color(0.42, 0.42, 0.48))  # стена
	
	var tex := ImageTexture.create_from_image(img)
	src.texture = tex
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	ts.add_source(src, 0)
	
	# Создаём тайлы
	src.create_tile(FLOOR_ATLAS)  # (0,0) — пол
	src.create_tile(WALL_ATLAS)   # (1,0) — стена

	# ── Коллизия стены ──
	var half := float(TILE_SIZE) / 2.0
	var sq := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2( half,  half), Vector2(-half,  half),
	])
	
	var wall_data: TileData = src.get_tile_data(WALL_ATLAS, 0)
	if wall_data:
		wall_data.add_collision_polygon(0)
		wall_data.set_collision_polygon_points(0, 0, sq)

	# ── Навигация пола ──
	var floor_data: TileData = src.get_tile_data(FLOOR_ATLAS, 0)
	if floor_data:
		var nav := NavigationPolygon.new()
		nav.vertices = sq
		nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		floor_data.set_navigation_polygon(0, nav)

	return ts


func generate() -> void:
	print("═══ Начало генерации подземелья ═══")

	_clear()
	_init_rng()
	_build_room_pool()
	_place_rooms()

	if _rooms.size() < 2:
		push_error("Недостаточно комнат! Размещено: %d" % _rooms.size())
		return

	_build_graph_and_mst()
	_draw_all_corridors()
	_assign_special_rooms()
	_final_repair_room_walls()
	_validate_graph()

	print("═══ Генерация завершена! Комнат: %d, Рёбер: %d ═══" % [
		_rooms.size(), _edges.size()
	])


# ════════════════════════════════════════════════════════════════════════════
#  ОЧИСТКА
# ════════════════════════════════════════════════════════════════════════════

func _clear() -> void:
	global_floor.clear()
	global_wall.clear()

	var rooms_root := get_node_or_null("Rooms")
	if rooms_root:
		for child in rooms_root.get_children():
			child.queue_free()

	_rooms.clear()
	_edges.clear()
	_start_room = null
	_boss_room = null
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
#  РАЗМЕЩЕНИЕ КОМНАТ + БЛИТИРОВАНИЕ
# ════════════════════════════════════════════════════════════════════════════

func _place_rooms() -> void:
	var scenes_to_place: Array[PackedScene] = []

	if room_start_scene: scenes_to_place.append(room_start_scene)
	if room_boss_scene:  scenes_to_place.append(room_boss_scene)

	var remaining := room_count - scenes_to_place.size()
	for i in range(remaining):
		var scene := _pick_weighted_room()
		if scene: scenes_to_place.append(scene)

	_shuffle_array(scenes_to_place)

	for scene in scenes_to_place:
		_try_place_room(scene)

	print("Размещено комнат: %d / %d" % [_rooms.size(), scenes_to_place.size()])


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
	for _attempt in range(room_attempts):
		var room: Room = scene.instantiate() as Room
		if room == null:
			push_error("Сцена не является Room: %s" % scene.resource_path)
			return false

		var max_x := map_width  - room.room_size.x - 1
		var max_y := map_height - room.room_size.y - 1
		if max_x <= 1 or max_y <= 1:
			room.queue_free()
			continue

		var gx := _rng.randi_range(1, max_x)
		var gy := _rng.randi_range(1, max_y)
		room.grid_position = Vector2i(gx, gy)
		room.position      = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)

		if _overlaps_any(room):
			room.queue_free()
			continue

		room.room_id = _rooms.size()

		var rooms_root := get_node_or_null("Rooms")
		if rooms_root:
			rooms_root.add_child(room)
		else:
			add_child(room)

		# ── Блитируем тайлы комнаты в глобальные слои ──
		_blit_room(room)

		_rooms.append(room)
		return true

	push_warning("Не удалось разместить: %s" % scene.resource_path)
	return false


func _blit_room(room: Room) -> void:
	var offset := room.grid_position

	# Копируем пол
	var r_floor: TileMapLayer = room.floor_layer
	if r_floor:
		for cell in r_floor.get_used_cells():
			global_floor.set_cell(offset + cell, 0, FLOOR_ATLAS)
			global_wall.erase_cell(offset + cell)

	# Копируем стены
	var r_wall: TileMapLayer = room.wall_layer
	if r_wall:
		for cell in r_wall.get_used_cells():
			# Не перезаписываем пол (floor приоритетнее)
			if global_floor.get_cell_source_id(offset + cell) == -1:
				global_wall.set_cell(offset + cell, 0, WALL_ATLAS)

	# Полностью отключаем локальные слои — они больше не нужны, всё в глобальных
	if r_floor: r_floor.enabled = false
	if r_wall:  r_wall.enabled  = false


func _overlaps_any(new_room: Room) -> bool:
	var new_rect := _get_grid_rect(new_room)

	for placed in _rooms:
		var placed_rect := _get_grid_rect(placed)
		if new_rect.intersects(placed_rect.grow(ROOM_GAP)):
			return true

	return false


func _get_grid_rect(room: Room) -> Rect2i:
	return Rect2i(room.grid_position, room.room_size)


# ════════════════════════════════════════════════════════════════════════════
#  ГРАФ + MST (КРУСКАЛ С UNION-FIND)
# ════════════════════════════════════════════════════════════════════════════

func _build_graph_and_mst() -> void:
	_edges.clear()

	var n := _rooms.size()
	if n < 2:
		return

	var all_edges: Array[Dictionary] = []
	for i in range(n):
		for j in range(i + 1, n):
			var ca := Vector2(_rooms[i].get_grid_center())
			var cb := Vector2(_rooms[j].get_grid_center())
			var dist := ca.distance_to(cb)
			all_edges.append({a = i, b = j, dist = dist})

	all_edges.sort_custom(func(e1, e2): return e1.dist < e2.dist)

	_uf_parent.resize(n)
	for i in range(n):
		_uf_parent[i] = i

	var mst_edge_count := 0
	var skipped: Array[Dictionary] = []

	for edge in all_edges:
		var root_a := _uf_find(edge.a)
		var root_b := _uf_find(edge.b)

		if root_a != root_b:
			_uf_union(root_a, root_b)
			_edges.append(edge)
			mst_edge_count += 1
		else:
			skipped.append(edge)

	for edge in skipped:
		if _rng.randf() < extra_edge_chance:
			_edges.append(edge)

	print("MST рёбер: %d, Петель: %d, Всего: %d" % [
		mst_edge_count,
		_edges.size() - mst_edge_count,
		_edges.size()
	])


func _uf_find(x: int) -> int:
	if _uf_parent[x] != x:
		_uf_parent[x] = _uf_find(_uf_parent[x])
	return _uf_parent[x]


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
	var side_a := room_a.get_side_toward(room_b)
	var side_b := room_b.get_side_toward(room_a)

	# Сначала открываем проёмы в стенах
	_open_and_blit_connection(room_a, side_a)
	_open_and_blit_connection(room_b, side_b)

	# Точки соединения - на стенах комнат
	var point_a: Vector2i = room_a.get_global_connection_point(side_a)
	var point_b: Vector2i = room_b.get_global_connection_point(side_b)

	# Сдвигаем точки на 2 тайла НАРУЖУ от комнаты, чтобы поворот коридора не задевал углы
	var outer_a := _get_outer_point(side_a, point_a, 2)
	var outer_b := _get_outer_point(side_b, point_b, 2)

	# 1. Рисуем прямой выход из комнаты А до outer_a
	_paint_segment(point_a, outer_a)
	# 2. Рисуем прямой выход из комнаты Б до outer_b
	_paint_segment(point_b, outer_b)
	# 3. Соединяем внешние точки L-образным коридором
	_draw_l_corridor(outer_a, outer_b, side_a)


func _get_outer_point(side: String, wall_point: Vector2i, offset: int) -> Vector2i:
	match side:
		"north": return wall_point + Vector2i(0, -offset) # вверх (наружу)
		"south": return wall_point + Vector2i(0, offset)  # вниз (наружу)
		"west":  return wall_point + Vector2i(-offset, 0) # влево (наружу)
		"east":  return wall_point + Vector2i(offset, 0)  # вправо (наружу)
	return wall_point


func _open_and_blit_connection(room: Room, side: String) -> void:
	if side in room.used_connections:
		return
	room.used_connections.append(side)

	var center: Vector2i = room.connection_points[side]
	var tiles := _get_opening_tiles(side, center)

	for local_tile in tiles:
		var global_tile := room.grid_position + local_tile
		global_wall.erase_cell(global_tile)
		global_floor.set_cell(global_tile, 0, FLOOR_ATLAS)


func _get_opening_tiles(side: String, center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	match side:
		"north", "south":
			for dx in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
				result.append(center + Vector2i(dx, 0))
		"west", "east":
			for dy in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
				result.append(center + Vector2i(0, dy))
	return result


func _draw_l_corridor(from: Vector2i, to: Vector2i, exit_side: String) -> void:
	var mid: Vector2i
	match exit_side:
		"east", "west": mid = Vector2i(to.x,   from.y)
		_:              mid = Vector2i(from.x,  to.y)

	# Рисуем коридор с перекрытием в 1 тайл для соединения
	_paint_segment(from, mid)
	_paint_segment(mid,  to)
	
	# Дополнительно соединяем с полом комнаты — рисуем тайл внутри комнаты
	_connect_to_room_floor(from, exit_side)
	_connect_to_room_floor(to, _get_opposite_side(exit_side))


func _connect_to_room_floor(wall_point: Vector2i, side: String) -> void:
	# Рисуем пол на 1 тайл внутрь комнаты от стены
	var inner_tile: Vector2i
	match side:
		"north": inner_tile = wall_point + Vector2i(0, 1)   # вниз внутрь
		"south": inner_tile = wall_point + Vector2i(0, -1)  # вверх внутрь
		"west":  inner_tile = wall_point + Vector2i(1, 0)   # вправо внутрь
		"east":  inner_tile = wall_point + Vector2i(-1, 0)  # влево внутрь
	
	global_floor.set_cell(inner_tile, 0, FLOOR_ATLAS)
	global_wall.erase_cell(inner_tile)


func _get_opposite_side(side: String) -> String:
	match side:
		"north": return "south"
		"south": return "north"
		"west":  return "east"
		"east":  return "west"
	return side


func _paint_segment(from: Vector2i, to: Vector2i) -> void:
	var x_min := mini(from.x, to.x)
	var x_max := maxi(from.x, to.x)
	var y_min := mini(from.y, to.y)
	var y_max := maxi(from.y, to.y)

	if from.y == to.y:  # горизонтальный
		for x in range(x_min, x_max + 1):
			for dy in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
				_carve_global(Vector2i(x, from.y + dy))
	else:               # вертикальный
		for y in range(y_min, y_max + 1):
			for dx in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
				_carve_global(Vector2i(from.x + dx, y))


func _carve_global(tile: Vector2i) -> void:
	if tile.x < 1 or tile.y < 1 or tile.x >= map_width - 1 or tile.y >= map_height - 1:
		return

	# Если в этой клетке уже есть ПОЛ комнаты (не коридора)
	# Мы можем это проверить по тому, есть ли в этой точке какая-то комната в _rooms
	# Но проще проверить, не является ли это внутренностью какой-то комнаты
	
	global_floor.set_cell(tile, 0, FLOOR_ATLAS)
	global_wall.erase_cell(tile)

	# Обрамляем коридор стенами, но НЕ трогаем пол комнат!
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nb := tile + Vector2i(dx, dy)
			if nb.x < 0 or nb.y < 0 or nb.x >= map_width or nb.y >= map_height:
				continue
				
			# Ставим стену только если там абсолютная пустота (нет ни пола, ни стены)
			# Это предотвратит "прорубание" углов комнат коридорами
			if global_floor.get_cell_source_id(nb) == -1 and global_wall.get_cell_source_id(nb) == -1:
				global_wall.set_cell(nb, 0, WALL_ATLAS)


# ════════════════════════════════════════════════════════════════════════════
#  НАЗНАЧЕНИЕ START / BOSS
# ════════════════════════════════════════════════════════════════════════════

func _assign_special_rooms() -> void:
	if _rooms.size() < 2:
		return

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

	if _start_room == null and _boss_room == null:
		var pair: Array[Room] = _find_farthest_pair()
		_start_room = pair[0]
		_boss_room = pair[1]
		_start_room.room_type = Room.RoomType.START
		_boss_room.room_type = Room.RoomType.BOSS
	elif _start_room == null:
		_start_room = _find_farthest_from(_boss_room)
		_start_room.room_type = Room.RoomType.START
	elif _boss_room == null:
		_boss_room = _find_farthest_from(_start_room)
		_boss_room.room_type = Room.RoomType.BOSS

	var graph_dist := _get_graph_distance(_start_room, _boss_room)
	if graph_dist < MIN_START_BOSS_DIST:
		push_warning(
			"START и BOSS слишком близко! Дистанция: %d (мин: %d)" % [
				graph_dist, MIN_START_BOSS_DIST
			])

	print("START: комната #%d, BOSS: комната #%d, дистанция: %d" % [
		_start_room.room_id, _boss_room.room_id, graph_dist
	])


func _find_farthest_pair() -> Array[Room]:
	var adj := _build_adjacency_list()

	var distances := _bfs_distances(0, adj)
	var farthest_from_0 := 0
	for i in range(_rooms.size()):
		if distances[i] > distances[farthest_from_0]:
			farthest_from_0 = i

	distances = _bfs_distances(farthest_from_0, adj)
	var farthest_from_far := farthest_from_0
	for i in range(_rooms.size()):
		if distances[i] > distances[farthest_from_far]:
			farthest_from_far = i

	return [_rooms[farthest_from_0], _rooms[farthest_from_far]]


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


func _bfs_distances(source_id: int, adj: Dictionary) -> Array[int]:
	var n: int = _rooms.size()
	var dist: Array[int] = []
	dist.resize(n)
	dist.fill(-1)

	var queue: Array[int] = [source_id]
	dist[source_id] = 0

	while not queue.is_empty():
		var current: int = queue.pop_front()
		var neighbors: Array = adj.get(current, [])
		for neighbor: int in neighbors:
			if dist[neighbor] == -1:
				dist[neighbor] = dist[current] + 1
				queue.append(neighbor)

	return dist


func _get_graph_distance(room_a: Room, room_b: Room) -> int:
	var adj := _build_adjacency_list()
	var distances := _bfs_distances(room_a.room_id, adj)
	var d := distances[room_b.room_id]
	return d if d >= 0 else 9999


func _build_adjacency_list() -> Dictionary:
	var adj: Dictionary = {}
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

	for i in range(_rooms.size()):
		var degree: int = adj[i].size()
		total_degree += degree

		if degree == 1:
			var room: Room = _rooms[i]
			if room.room_type != Room.RoomType.START and room.room_type != Room.RoomType.BOSS:
				dead_ends.append(room)

	for edge in _edges:
		var ca := Vector2(_rooms[edge.a].get_grid_center())
		var cb := Vector2(_rooms[edge.b].get_grid_center())
		if ca.distance_to(cb) > 25.0:
			long_corridors.append(edge)

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

func get_start_room() -> Room:
	return _start_room


func get_boss_room() -> Room:
	return _boss_room


func get_rooms() -> Array:
	return _rooms


func get_edges() -> Array:
	return _edges


func get_player_spawn_position() -> Vector2:
	if _start_room == null:
		push_error("Нет стартовой комнаты!")
		return Vector2.ZERO

	var spawn_root := _start_room.get_node_or_null("SpawnPoints")
	if spawn_root and spawn_root.get_child_count() > 0:
		var spawn_point: Marker2D = spawn_root.get_child(0)
		return _start_room.global_position + spawn_point.position

	return _start_room.global_position + Vector2(
		_start_room.room_size.x * TILE_SIZE / 2.0,
		_start_room.room_size.y * TILE_SIZE / 2.0
	)


# ── Восстановление целостности комнат ───────────────────────────────────────
func _final_repair_room_walls() -> void:
	print("── Восстановление стен комнат ──")
	for room in _rooms:
		var w: int = room.room_size.x
		var h: int = room.room_size.y
		var offset: Vector2i = room.grid_position
		
		# Перебираем периметр комнаты
		for x in range(w):
			for y in range(h):
				# Проверяем, крайний ли это тайл (стена)
				if x == 0 or y == 0 or x == w - 1 or y == h - 1:
					var local_tile := Vector2i(x, y)
					var glob_tile := offset + local_tile
					
					# Если это НЕ дверной проем, восстанавливаем стену
					if not _is_tile_in_doorway(room, local_tile):
						global_wall.set_cell(glob_tile, 0, WALL_ATLAS)
						global_floor.erase_cell(glob_tile)
					else:
						# Если это дверной проем, убеждаемся, что там ПОЛ
						global_floor.set_cell(glob_tile, 0, FLOOR_ATLAS)
						global_wall.erase_cell(glob_tile)


func _is_tile_in_doorway(room: Room, local_tile: Vector2i) -> bool:
	for side in room.used_connections:
		var center: Vector2i = room.connection_points[side]
		var tiles := _get_opening_tiles(side, center)
		if local_tile in tiles:
			return true
	return false
