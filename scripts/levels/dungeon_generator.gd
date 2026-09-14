extends Node2D
class_name DungeonGenerator
## DungeonGenerator — компактная процедурная генерация подземелья по сеточному графу
## в стиле The Binding of Isaac и Enter the Gungeon.
## Исключает километровые пустые коридоры, комната сразу переходит в соседнюю через короткий проём.

@export_group("Generation")
@export var seed_value: int = 0
@export var room_count: int = 8
@export var extra_edge_chance: float = 0.15

@export_group("Room Scenes")
@export var room_start_scene: PackedScene
@export var room_combat_small_scene: PackedScene
@export var room_combat_large_scene: PackedScene
@export var room_chest_scene: PackedScene
@export var room_shrine_scene: PackedScene
@export var room_boss_scene: PackedScene

const TILE_SIZE := 64
const CELL_WIDTH := 26    # Размер ячейки сетки в тайлах (ширина)
const CELL_HEIGHT := 20   # Размер ячейки сетки в тайлах (высота)
const CORRIDOR_WIDTH := 3 # Ширина дверного прохода

const FLOOR_ATLAS := Vector2i(0, 0)
const WALL_ATLAS := Vector2i(1, 0)

@onready var global_floor: TileMapLayer = $GlobalFloor
@onready var global_wall: TileMapLayer = $GlobalWall
@onready var rooms_container: Node2D = $Rooms

var _rng := RandomNumberGenerator.new()
var _rooms: Array[Room] = []
var _start_room: Room = null
var _boss_room: Room = null

# Сеточные структуры
# Vector2i (сетка 5x5) -> Dictionary { type, scene, connections: Array[String], room_inst: Room }
var _grid: Dictionary = {}
var _grid_edges: Array[Dictionary] = [] # { from: Vector2i, to: Vector2i, dir: String }


func _ready() -> void:
	_setup_tileset()
	generate()


func _setup_tileset() -> void:
	if ResourceLoader.exists("res://tilesets/dungeon_tileset.tres"):
		var ts := load("res://tilesets/dungeon_tileset.tres") as TileSet
		global_floor.tile_set = ts
		global_wall.tile_set = ts

	global_floor.material = preload("res://resources/shaders/dungeon_floor_material.tres")
	global_wall.material = preload("res://resources/shaders/dungeon_wall_material.tres")


func generate() -> void:
	_clear()
	_init_rng()
	_generate_grid_layout()
	_assign_room_types()
	_instantiate_rooms()
	_connect_doors_and_corridors()
	_update_global_autotiles()

	print("═══ Сеточная генерация завершена: комнат %d, связей %d ═══" % [_rooms.size(), _grid_edges.size()])


func _clear() -> void:
	global_floor.clear()
	global_wall.clear()
	for child in rooms_container.get_children():
		child.queue_free()
	_rooms.clear()
	_grid.clear()
	_grid_edges.clear()
	_start_room = null
	_boss_room = null


func _init_rng() -> void:
	if seed_value == 0:
		_rng.randomize()
		seed_value = _rng.seed
	else:
		_rng.seed = seed_value


## 1. Построение связанного сеточного графа (4x4 или 5x5)
func _generate_grid_layout() -> void:
	var start_coord := Vector2i(2, 2)
	_grid[start_coord] = {
		"coord": start_coord,
		"type": Room.RoomType.START,
		"scene": room_start_scene,
		"connections": []
	}

	var queue: Array[Vector2i] = [start_coord]
	var directions := {
		"north": Vector2i(0, -1),
		"south": Vector2i(0, 1),
		"west": Vector2i(-1, 0),
		"east": Vector2i(1, 0)
	}
	var opposite := {
		"north": "south",
		"south": "north",
		"west": "east",
		"east": "west"
	}

	var placed: int = 1
	var attempts: int = 0

	while placed < room_count and attempts < 100:
		attempts += 1
		var current_cell: Vector2i = queue[_rng.randi_range(0, queue.size() - 1)]
		var dir_names: Array = directions.keys()
		dir_names.shuffle()

		for dir_name in dir_names:
			var offset: Vector2i = directions[dir_name]
			var neighbor: Vector2i = current_cell + offset

			# Ограничение сетки 0..4
			if neighbor.x < 0 or neighbor.x > 4 or neighbor.y < 0 or neighbor.y > 4:
				continue

			if not _grid.has(neighbor):
				# Создаем новую комнату
				_grid[neighbor] = {
					"coord": neighbor,
					"type": Room.RoomType.FIGHT,
					"scene": null,
					"connections": []
				}
				_add_edge(current_cell, neighbor, dir_name, opposite[dir_name])
				queue.append(neighbor)
				placed += 1
				break
			elif _rng.randf() < extra_edge_chance and not _has_edge(current_cell, neighbor):
				# Добавляем альтернативный проход (петлю)
				_add_edge(current_cell, neighbor, dir_name, opposite[dir_name])


func _add_edge(from_c: Vector2i, to_c: Vector2i, dir: String, opp_dir: String) -> void:
	_grid[from_c]["connections"].append(dir)
	_grid[to_c]["connections"].append(opp_dir)
	_grid_edges.append({ "from": from_c, "to": to_c, "dir": dir })


func _has_edge(a: Vector2i, b: Vector2i) -> bool:
	for edge in _grid_edges:
		if (edge["from"] == a and edge["to"] == b) or (edge["from"] == b and edge["to"] == a):
			return true
	return false


## 2. Назначение типов (БОСС — самый дальний, ТУПИКИ — сундук/святилище)
func _assign_room_types() -> void:
	var start_coord := Vector2i(2, 2)
	var distances := _compute_bfs_distances(start_coord)

	var max_dist: int = -1
	var boss_coord := Vector2i(-1, -1)

	for coord in distances.keys():
		if distances[coord] > max_dist:
			max_dist = distances[coord]
			boss_coord = coord

	# Назначаем босса
	if boss_coord != Vector2i(-1, -1) and boss_coord != start_coord:
		_grid[boss_coord]["type"] = Room.RoomType.BOSS
		_grid[boss_coord]["scene"] = room_boss_scene

	# Ищем тупиковые комнаты для сокровищницы и святилища
	var leaves: Array[Vector2i] = []
	for coord in _grid.keys():
		if coord == start_coord or coord == boss_coord:
			continue
		if _grid[coord]["connections"].size() == 1:
			leaves.append(coord)

	leaves.shuffle()
	if leaves.size() > 0 and room_chest_scene:
		var chest_coord: Vector2i = leaves.pop_back()
		_grid[chest_coord]["type"] = Room.RoomType.CHEST
		_grid[chest_coord]["scene"] = room_chest_scene

	if leaves.size() > 0 and room_shrine_scene:
		var shrine_coord: Vector2i = leaves.pop_back()
		_grid[shrine_coord]["type"] = Room.RoomType.SHRINE
		_grid[shrine_coord]["scene"] = room_shrine_scene

	# Все остальные — боевые комнаты
	for coord in _grid.keys():
		if _grid[coord]["scene"] == null:
			if _rng.randf() < 0.4 and room_combat_large_scene:
				_grid[coord]["scene"] = room_combat_large_scene
			else:
				_grid[coord]["scene"] = room_combat_small_scene


func _compute_bfs_distances(start_c: Vector2i) -> Dictionary:
	var dist: Dictionary = { start_c: 0 }
	var q: Array[Vector2i] = [start_c]

	while not q.is_empty():
		var curr: Vector2i = q.pop_front()
		var d: int = dist[curr]

		for dir_name in _grid[curr]["connections"]:
			var n: Vector2i = curr + _get_dir_vector(dir_name)
			if _grid.has(n) and not dist.has(n):
				dist[n] = d + 1
				q.append(n)
	return dist


func _get_dir_vector(dir_name: String) -> Vector2i:
	match dir_name:
		"north": return Vector2i(0, -1)
		"south": return Vector2i(0, 1)
		"west": return Vector2i(-1, 0)
		"east": return Vector2i(1, 0)
	return Vector2i.ZERO


## 3. Спавн сцен комнат на сетке
func _instantiate_rooms() -> void:
	var id := 0
	for coord in _grid.keys():
		var data: Dictionary = _grid[coord]
		var scene: PackedScene = data["scene"]
		if not scene:
			scene = room_combat_small_scene

		var room: Room = scene.instantiate() as Room
		room.room_id = id
		id += 1

		# Вычисляем мировую позицию комнаты
		var tile_offset := Vector2i(coord.x * CELL_WIDTH, coord.y * CELL_HEIGHT)
		# Центрируем комнату внутри ячейки сетки
		var inner_offset := (Vector2i(CELL_WIDTH, CELL_HEIGHT) - room.room_size) / 2
		var final_tile_pos := tile_offset + inner_offset

		room.grid_position = final_tile_pos
		room.position = Vector2(final_tile_pos * TILE_SIZE)

		rooms_container.add_child(room)
		_rooms.append(room)
		data["room_inst"] = room

		if data["type"] == Room.RoomType.START:
			_start_room = room
		elif data["type"] == Room.RoomType.BOSS:
			_boss_room = room


## 4. Открытие дверей и короткие аккуратные коридоры (без пустых тоннелей)
func _connect_doors_and_corridors() -> void:
	for edge in _grid_edges:
		var room_a: Room = _grid[edge["from"]]["room_inst"]
		var room_b: Room = _grid[edge["to"]]["room_inst"]
		var dir_from: String = edge["dir"]
		var dir_to: String = _get_opposite_dir(dir_from)

		# Открываем двери у самих комнат
		room_a.open_connection(dir_from)
		room_b.open_connection(dir_to)

		# Соединяем точки дверей коротким прямым проёмом
		var door_a_world_tile: Vector2i = room_a.get_global_connection_point(dir_from)
		var door_b_world_tile: Vector2i = room_b.get_global_connection_point(dir_to)

		_carve_short_passage(room_a, room_b, door_a_world_tile, door_b_world_tile, dir_from)


func _get_opposite_dir(dir: String) -> String:
	match dir:
		"north": return "south"
		"south": return "north"
		"west": return "east"
		"east": return "west"
	return "north"


## Пробивает короткий прямой переход между двумя соседними дверями
## Идеально ровный проход шириной 3 тайла со стенками по бокам
func _carve_short_passage(room_a: Room, room_b: Room, tile_a: Vector2i, tile_b: Vector2i, dir: String) -> void:
	var cleared_tiles: Array[Vector2i] = []

	if dir == "north" or dir == "south":
		# Вертикальный проход: X строго по оси дверей
		var door_x: int = tile_a.x
		var min_y: int = min(tile_a.y, tile_b.y)
		var max_y: int = max(tile_a.y, tile_b.y)

		for y in range(min_y, max_y + 1):
			for dx in range(-1, 2):
				var pos := Vector2i(door_x + dx, y)
				global_floor.set_cell(pos, 0, FLOOR_ATLAS)
				global_wall.erase_cell(pos)
				cleared_tiles.append(pos)
			# Стенки слева и справа от проема
			_place_wall_if_empty(Vector2i(door_x - 2, y))
			_place_wall_if_empty(Vector2i(door_x + 2, y))
	else:
		# Горизонтальный проход: Y строго по оси дверей
		var door_y: int = tile_a.y
		var min_x: int = min(tile_a.x, tile_b.x)
		var max_x: int = max(tile_a.x, tile_b.x)

		for x in range(min_x, max_x + 1):
			for dy in range(-1, 2):
				var pos := Vector2i(x, door_y + dy)
				global_floor.set_cell(pos, 0, FLOOR_ATLAS)
				global_wall.erase_cell(pos)
				cleared_tiles.append(pos)
			# Стенки сверху и снизу от проема
			_place_wall_if_empty(Vector2i(x, door_y - 2))
			_place_wall_if_empty(Vector2i(x, door_y + 2))

	# Гарантированно очищаем стены в обеих комнатах на границе перехода
	room_a.clear_wall_tiles(cleared_tiles)
	room_b.clear_wall_tiles(cleared_tiles)


func _place_wall_if_empty(pos: Vector2i) -> void:
	if global_floor.get_cell_source_id(pos) == -1:
		global_wall.set_cell(pos, 0, WALL_ATLAS)


func _update_global_autotiles() -> void:
	# 1. Собираем единую карту ВСЕХ стен подземелья в мировых тайловых координатах:
	var all_walls: Dictionary = {}

	# Стены коридоров (GlobalWall)
	if global_wall:
		for c in global_wall.get_used_cells():
			all_walls[c] = true

	# Стены из всех сгенерированных комнат
	for room in _rooms:
		if room and room.wall_layer:
			var r_pos: Vector2i = room.grid_position
			for local_c in room.wall_layer.get_used_cells():
				all_walls[r_pos + local_c] = true

	# 2. Обновляем маски соседства для стен коридоров (GlobalWall)
	if global_wall:
		for c in global_wall.get_used_cells():
			var n: int = 1 if all_walls.has(c + Vector2i(0, -1)) else 0
			var s: int = 2 if all_walls.has(c + Vector2i(0, 1)) else 0
			var w: int = 4 if all_walls.has(c + Vector2i(-1, 0)) else 0
			var e: int = 8 if all_walls.has(c + Vector2i(1, 0)) else 0
			global_wall.set_cell(c, 0, WALL_ATLAS, n | s | w | e)

	# 3. Обновляем маски соседства для стен всех комнат с учетом коридоров и стыков
	for room in _rooms:
		if room and room.wall_layer:
			var r_pos: Vector2i = room.grid_position
			for local_c in room.wall_layer.get_used_cells():
				var world_c: Vector2i = r_pos + local_c
				var n: int = 1 if all_walls.has(world_c + Vector2i(0, -1)) else 0
				var s: int = 2 if all_walls.has(world_c + Vector2i(0, 1)) else 0
				var w: int = 4 if all_walls.has(world_c + Vector2i(-1, 0)) else 0
				var e: int = 8 if all_walls.has(world_c + Vector2i(1, 0)) else 0
				room.wall_layer.set_cell(local_c, 0, WALL_ATLAS, n | s | w | e)




# ── Публичный API ────────────────────────────────────────────────────────────
func get_start_room() -> Room:
	return _start_room


func get_boss_room() -> Room:
	return _boss_room


func get_rooms() -> Array[Room]:
	return _rooms
