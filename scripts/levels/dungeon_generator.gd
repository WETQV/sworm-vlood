extends Node2D
## Dungeon Generator
## Генерирует подземелье с комнатами и коридорами

# Параметры генерации
@export_category("Generation Settings")
@export var room_count_min: int = 15
@export var room_count_max: int = 40
@export var room_size_min: Vector2i = Vector2i(6, 6)  # в тайлах
@export var room_size_max: Vector2i = Vector2i(12, 12)
@export var corridor_width: int = 6  # в тайлах
@export var grid_size: Vector2i = Vector2i(20, 20)  # размер сетки для размещения

# Тайл
@export_category("Tile Settings")
@export var tile_size: int = 64

# Типы комнат
enum RoomType { START, FIGHT, CHEST, BOSS }

# Класс данных комнаты
class Room:
	var position: Vector2i       # позиция на сетке (в комнатах)
	var grid_position: Vector2i  # позиция в пикселях (в тайлах)
	var size: Vector2i           # размер комнаты в тайлах
	var type: RoomType           # тип комнаты
	var exits: Array[Vector2i]   # направления выходов (0=верх, 1=право, 2=низ, 3=лево)
	var rect: Rect2i             # прямоугольник комнаты (в тайлах)
	var connected: bool = false  # соединена с другими комнатами
	
	func _init(pos: Vector2i, sz: Vector2i, rt: RoomType):
		position = pos
		size = sz
		type = rt
		# Центрируем позицию на сетке
		grid_position = pos * Vector2i(10, 10)  # расстояние между комнатами
	
	func get_center() -> Vector2:
		return Vector2(
			grid_position.x * 64 + size.x * 32,
			grid_position.y * 64 + size.y * 32
		)
	
	func get_rect() -> Rect2i:
		return Rect2i(grid_position, size)

# Массив комнат
var rooms: Array[Room] = []
var room_grid: Dictionary = {}  # сетка занятых позиций

# Ссылки на ноды
@onready var floor_layer: TileMap = $Floor
@onready var walls_layer: TileMap = $Walls

# Текстуры для тайлов (создаются программно)
var floor_texture: ImageTexture
var wall_texture: ImageTexture
var corridor_texture: ImageTexture


func _ready() -> void:
	# Создаем текстуры для тайлов
	_create_tile_textures()
	# Создаем тайлсет
	_create_tileset()
	# Генерируем подземелье
	generate_dungeon()


func _create_tile_textures() -> void:
	"""Создает текстуры для тайлов"""
	floor_texture = ImageTexture.create_from_image(_create_colored_square(Color(0.3, 0.3, 0.35), tile_size))
	wall_texture = ImageTexture.create_from_image(_create_colored_square(Color(0.15, 0.15, 0.2), tile_size))
	corridor_texture = ImageTexture.create_from_image(_create_colored_square(Color(0.25, 0.25, 0.28), tile_size))


func _create_tileset() -> TileSet:
	"""Создает тайлсет с цветными квадратами"""
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(tile_size, tile_size)
	
	# Floor (пол) - источник 0
	tileset.add_source(_create_atlas_source(floor_texture, 0), 0)
	
	# Walls (стены) - источник 1
	tileset.add_source(_create_atlas_source(wall_texture, 1), 1)
	
	# Corridors (коридоры) - источник 2
	tileset.add_source(_create_atlas_source(corridor_texture, 2), 2)
	
	floor_layer.tile_set = tileset
	walls_layer.tile_set = tileset
	
	return tileset


func _create_atlas_source(texture: ImageTexture, source_id: int) -> TileSetAtlasSource:
	"""Создает TileSetAtlasSource с текстурой"""
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = texture
	# tile_size задаётся на уровне TileSet, не источника
	# Добавляем один тайл по умолчанию
	atlas_source.create_tile(Vector2i(0, 0))
	return atlas_source


func _create_colored_square(color: Color, size: int) -> Image:
	"""Создает изображение с цветным квадратом"""
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	# Добавляем рамку для красоты
	for i in range(size):
		image.set_pixel(i, 0, color.darkened(0.3))
		image.set_pixel(i, size-1, color.darkened(0.3))
		image.set_pixel(0, i, color.darkened(0.3))
		image.set_pixel(size-1, i, color.darkened(0.3))
	return image


func generate_dungeon() -> void:
	"""Основная функция генерации подземелья"""
	# Очищаем предыдущее
	rooms.clear()
	room_grid.clear()
	floor_layer.clear()
	walls_layer.clear()
	
	# 1. Генерируем комнаты
	_generate_rooms()
	
	# 2. Соединяем коридорами (MST)
	_connect_rooms_with_corridors()
	
	# 3. Рендерим всё на тайлмапе
	_render_dungeon()
	
	print("Dungeon generated: %d rooms" % rooms.size())


func _generate_rooms() -> void:
	"""Генерирует комнаты на сетке"""
	var target_rooms := randi_range(room_count_min, room_count_max)
	var attempts := 0
	var max_attempts := 1000
	
	# Первая комната - стартовая (в центре/снизу)
	var start_room := Room.new(
		Vector2i(grid_size.x / 2, grid_size.y - 2),
		Vector2i(8, 8),
		RoomType.START
	)
	_add_room(start_room)
	
	# Генерируем остальные комнаты
	while rooms.size() < target_rooms and attempts < max_attempts:
		attempts += 1
		
		# Случайная позиция
		var pos := Vector2i(
			randi_range(1, grid_size.x - 2),
			randi_range(1, grid_size.y - 2)
		)
		
		# Проверяем, что место свободно (с запасом)
		if _is_area_free(pos, room_size_max + Vector2i(2, 2)):
			# Случайный размер комнаты (вариативность!)
			var room_size := Vector2i(
				randi_range(room_size_min.x, room_size_max.x),
				randi_range(room_size_min.y, room_size_max.y)
			)
			
			# Определяем тип
			var room_type: RoomType
			if rooms.size() == target_rooms - 1:
				room_type = RoomType.BOSS  # Последняя - босс
			elif randf() < 0.3:
				room_type = RoomType.CHEST
			else:
				room_type = RoomType.FIGHT
			
			var new_room := Room.new(pos, room_size, room_type)
			_add_room(new_room)


func _is_area_free(pos: Vector2i, size: Vector2i) -> bool:
	"""Проверяет, свободна ли область на сетке"""
	for x in range(pos.x - size.x/2 - 1, pos.x + size.x/2 + 2):
		for y in range(pos.y - size.y/2 - 1, pos.y + size.y/2 + 2):
			if room_grid.has(Vector2i(x, y)):
				return false
	return true


func _add_room(room: Room) -> void:
	rooms.append(room)
	room_grid[room.position] = room
	
	# Отмечаем занятые ячейки
	var half_size := room.size / 2
	for x in range(room.position.x - half_size.x - 1, room.position.x + half_size.x + 2):
		for y in range(room.position.y - half_size.y - 1, room.position.y + half_size.y + 2):
			room_grid[Vector2i(x, y)] = room


func _connect_rooms_with_corridors() -> void:
	"""Соединяет комнаты коридорами с использованием MST"""
	if rooms.size() < 2:
		return
	
	# Сортируем комнаты: стартовая первая, босс последняя
	rooms.sort_custom(func(a, b):
		if a.type == RoomType.START: return true
		if b.type == RoomType.START: return false
		if a.type == RoomType.BOSS: return false
		if b.type == RoomType.BOSS: return true
		return a.position.distance_to(Vector2i(0, grid_size.y)) < b.position.distance_to(Vector2i(0, grid_size.y))
	)
	
	# MST через алгоритм Прима
	var mst: Array[Room] = [rooms[0]]
	rooms[0].connected = true
	
	while mst.size() < rooms.size():
		var min_dist := INF
		var best_room: Room = null
		var best_target: Room = null
		
		for room in mst:
			for other in rooms:
				if other.connected:
					continue
				
				var dist := _get_room_distance(room, other)
				if dist < min_dist:
					min_dist = dist
					best_room = room
					best_target = other
		
		if best_room and best_target:
			best_target.connected = true
			mst.append(best_target)
			
			# Определяем направление коридора
			var direction := _get_corridor_direction(best_room.position, best_target.position)
			best_room.exits.append(direction)
			best_target.exits.append(_get_opposite_direction(direction))


func _get_room_distance(a: Room, b: Room) -> float:
	"""Вычисляет расстояние между комнатами"""
	return a.position.distance_to(b.position)


func _get_corridor_direction(from: Vector2i, to: Vector2i) -> Vector2i:
	"""Определяет направление коридора от a к b"""
	if to.x > from.x:
		return Vector2i(1, 0)  # право
	elif to.x < from.x:
		return Vector2i(-1, 0)  # лево
	elif to.y > from.y:
		return Vector2i(0, 1)  # низ
	else:
		return Vector2i(0, -1)  # верх


func _get_opposite_direction(dir: Vector2i) -> Vector2i:
	"""Возвращает противоположное направление"""
	return Vector2i(-dir.x, -dir.y)


func _render_dungeon() -> void:
	"""Рендерит подземелье на тайлмапе"""
	# Рендерим комнаты
	for room in rooms:
		_render_room(room)
	
	# Рендерим коридоры
	_render_corridors()


func _render_room(room: Room) -> void:
	"""Рендерит одну комнату"""
	var room_pixel_pos := room.grid_position * (tile_size / 2)  # масштабирование
	
	# Рендерим пол комнаты
	for x in range(room.size.x):
		for y in range(room.size.y):
			var world_x := room.grid_position.x * 10 * tile_size + x
			var world_y := room.grid_position.y * 10 * tile_size + y
			floor_layer.set_cell(0, Vector2i(x, y), 0, Vector2i(0, 0))
			floor_layer.set_cell(0, Vector2i(world_x, world_y), 0, Vector2i(0, 0))
	
	# Рендерим стены вокруг комнаты
	for x in range(-1, room.size.x + 1):
		var world_x := room.grid_position.x * 10 * tile_size + x
		var world_y_top := room.grid_position.y * 10 * tile_size - 1
		var world_y_bottom := room.grid_position.y * 10 * tile_size + room.size.y
		
		# Верхняя стена
		floor_layer.set_cell(0, Vector2i(world_x, world_y_top), 1, Vector2i(0, 0))
		# Нижняя стена
		floor_layer.set_cell(0, Vector2i(world_x, world_y_bottom), 1, Vector2i(0, 0))
	
	for y in range(-1, room.size.y + 1):
		var world_x_left := room.grid_position.x * 10 * tile_size - 1
		var world_x_right := room.grid_position.x * 10 * tile_size + room.size.x
		var world_y := room.grid_position.y * 10 * tile_size + y
		
		# Левая стена
		floor_layer.set_cell(0, Vector2i(world_x_left, world_y), 1, Vector2i(0, 0))
		# Правая стена
		floor_layer.set_cell(0, Vector2i(world_x_right, world_y), 1, Vector2i(0, 0))
	
	# Добавляем выходы (удаляем стены)
	for exit_dir in room.exits:
		_remove_walls_for_exit(room, exit_dir)


func _remove_walls_for_exit(room: Room, direction: Vector2i) -> void:
	"""Удаляет стены для выхода из комнаты"""
	var exit_pos: Vector2i
	
	match direction:
		Vector2i(0, -1):  # верх
			exit_pos = Vector2i(room.size.x / 2, -1)
		Vector2i(0, 1):   # низ
			exit_pos = Vector2i(room.size.x / 2, room.size.y)
		Vector2i(-1, 0):  # лево
			exit_pos = Vector2i(-1, room.size.y / 2)
		Vector2i(1, 0):   # право
			exit_pos = Vector2i(room.size.x, room.size.y / 2)
	
	# Удаляем стену в месте выхода
	var world_x := room.grid_position.x * 10 * tile_size + exit_pos.x
	var world_y := room.grid_position.y * 10 * tile_size + exit_pos.y
	floor_layer.set_cell(0, Vector2i(world_x, world_y), -1, Vector2i(-1, -1))


func _render_corridors() -> void:
	"""Рендерит коридоры между комнатами"""
	# Для каждой пары соединенных комнат
	for i in range(rooms.size() - 1):
		var room_a := rooms[i]
		var room_b := rooms[i + 1]
		
		if not room_b.connected:
			continue
		
		# Рисуем коридор
		_draw_corridor(room_a, room_b)


func _draw_corridor(from: Room, to: Room) -> void:
	"""Рисует коридор между двумя комнатами"""
	var start := from.get_center()
	var end := to.get_center()
	
	# Рисуем L-образный коридор
	var corner: Vector2
	
	if randf() < 0.5:
		# Сначала горизонтально, потом вертикально
		corner = Vector2(end.x, start.y)
	else:
		# Сначала вертикально, потом горизонтально
		corner = Vector2(start.x, end.y)
	
	# Рендерим сегменты коридора
	_render_corridor_segment(start, corner)
	_render_corridor_segment(corner, end)


func _render_corridor_segment(from: Vector2, to: Vector2) -> void:
	"""Рендерит один сегмент коридора"""
	var min_x := int(min(from.x, to.x)) / tile_size
	var max_x := int(max(from.x, to.x)) / tile_size
	var min_y := int(min(from.y, to.y)) / tile_size
	var max_y := int(max(from.y, to.y)) / tile_size
	
	# Расширяем коридор (6 тайлов шириной)
	var half_width := corridor_width / 2
	
	for x in range(min_x - half_width, max_x + half_width + 1):
		for y in range(min_y - half_width, max_y + half_width + 1):
			# Пол коридора
			floor_layer.set_cell(0, Vector2i(x, y), 2, Vector2i(0, 0))
	
	# Стены коридора (только по краям)
	for x in [min_x - half_width - 1, max_x + half_width]:
		for y in range(min_y - half_width, max_y + half_width + 1):
			floor_layer.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0))
	
	for y in [min_y - half_width - 1, max_y + half_width]:
		for x in range(min_x - half_width, max_x + half_width + 1):
			floor_layer.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0))


func regenerate() -> void:
	"""Перегенерирует подземелье"""
	generate_dungeon()


# === Публичные методы для получения данных ===

func get_start_room() -> Room:
	"""Возвращает стартовую комнату"""
	for room in rooms:
		if room.type == RoomType.START:
			return room
	return null


func get_boss_room() -> Room:
	"""Возвращает комнату босса"""
	for room in rooms:
		if room.type == RoomType.BOSS:
			return room
	return null


func get_fight_rooms() -> Array[Room]:
	"""Возвращает все боевые комнаты"""
	var result: Array[Room] = []
	for room in rooms:
		if room.type == RoomType.FIGHT:
			result.append(room)
	return result


func get_chest_rooms() -> Array[Room]:
	"""Возвращает все комнаты с сундуками"""
	var result: Array[Room] = []
	for room in rooms:
		if room.type == RoomType.CHEST:
			result.append(room)
	return result


func get_all_rooms() -> Array[Room]:
	"""Возвращает все комнаты"""
	return rooms
