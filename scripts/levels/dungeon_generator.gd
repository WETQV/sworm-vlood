extends Node2D
## Dungeon Generator - Упрощённая версия
## Генерирует подземелье с комнатами и коридорами

# Параметры генерации
@export_category("Generation Settings")
@export var room_count_min: int = 15
@export var room_count_max: int = 40
@export var room_size_min: int = 6
@export var room_size_max: int = 12
@export var corridor_width: int = 6

# Тайл
@export_category("Tile Settings")
@export var tile_size: Vector2i = Vector2i(64, 64)

# Типы комнат
enum RoomType { START, FIGHT, CHEST, BOSS }

# Класс данных комнаты
class Room:
	var grid_x: int          # позиция на сетке (в условных единицах)
	var grid_y: int
	var size: int            # размер (квадратная)
	var type: RoomType
	var rect: Rect2i         # прямоугольник в координатах тайлов
	var center: Vector2i     # центр в координатах тайлов
	var connected: bool = false
	var exits: Array[Vector2i] = []
	
	func _init(x: int, y: int, sz: int, rt: RoomType):
		grid_x = x
		grid_y = y
		size = sz
		type = rt
		# Комната занимает область вокруг своей позиции
		rect = Rect2i(x - sz/2, y - sz/2, sz, sz)
		center = Vector2i(x, y)

# Массив комнат
var rooms: Array[Room] = []

# TileMap
@onready var floor_tilemap: TileMapLayer = $Floor
@onready var walls_tilemap: TileMapLayer = $Walls

# Текстуры
var floor_tex: ImageTexture
var wall_tex: ImageTexture
var corridor_tex: ImageTexture


func _ready() -> void:
	_create_textures()
	_create_tileset()
	generate_dungeon()


func _create_textures() -> void:
	"""Создаёт текстуры для тайлов"""
	var size := tile_size.x
	var floor_img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	floor_img.fill(Color(0.35, 0.35, 0.4))  # серый пол
	floor_tex = ImageTexture.create_from_image(floor_img)
	
	var wall_img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	wall_img.fill(Color(0.15, 0.15, 0.2))  # тёмные стены
	wall_tex = ImageTexture.create_from_image(wall_img)
	
	var corr_img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	corr_img.fill(Color(0.28, 0.28, 0.32))  # чуть светлее - коридор
	corridor_tex = ImageTexture.create_from_image(corr_img)


func _create_tileset() -> void:
	"""Создаёт тайлсет"""
	var ts := TileSet.new()
	ts.tile_size = tile_size
	
	# Source 0 - Floor
	var floor_src := TileSetAtlasSource.new()
	floor_src.texture = floor_tex
	floor_src.tile_size = tile_size
	floor_src.create_tile(Vector2i(0, 0))
	ts.add_source(floor_src, 0)
	
	# Source 1 - Wall
	var wall_src := TileSetAtlasSource.new()
	wall_src.texture = wall_tex
	wall_src.tile_size = tile_size
	wall_src.create_tile(Vector2i(0, 0))
	ts.add_source(wall_src, 1)
	
	# Source 2 - Corridor
	var corr_src := TileSetAtlasSource.new()
	corr_src.texture = corridor_tex
	corr_src.tile_size = tile_size
	corr_src.create_tile(Vector2i(0, 0))
	ts.add_source(corr_src, 2)
	
	floor_tilemap.tile_set = ts
	walls_tilemap.tile_set = ts


func generate_dungeon() -> void:
	"""Основная функция генерации"""
	rooms.clear()
	floor_tilemap.clear()
	walls_tilemap.clear()
	
	# Генерируем комнаты
	_generate_rooms()
	
	# Соединяем коридорами
	_connect_rooms()
	
	# Рендерим
	_render_dungeon()
	
	print("Generated %d rooms" % rooms.size())


func _generate_rooms() -> void:
	"""Генерирует комнаты"""
	var target := randi_range(room_count_min, room_count_max)
	var attempts := 0
	
	# Стартовая комната в центре
	var start := Room.new(50, 50, 8, RoomType.START)
	_add_room(start)
	
	# Генерируем остальные
	while rooms.size() < target and attempts < 2000:
		attempts += 1
		
		# Случайная позиция
		var gx := randi_range(10, 90)
		var gy := randi_range(10, 90)
		var sz := randi_range(room_size_min, room_size_max)
		
		# Проверяем перекрытие
		var new_room := Room.new(gx, gy, sz, RoomType.FIGHT)
		if _can_place_room(new_room):
			# Определяем тип
			if rooms.size() == target - 1:
				new_room.type = RoomType.BOSS
			elif randf() < 0.25:
				new_room.type = RoomType.CHEST
			else:
				new_room.type = RoomType.FIGHT
			_add_room(new_room)


func _can_place_room(room: Room) -> bool:
	"""Проверяет, можно ли разместить комнату"""
	for r in rooms:
		# Проверяем расстояние
		var dist := Vector2(room.grid_x, room.grid_y).distance_to(Vector2(r.grid_x, r.grid_y))
		if dist < (room.size + r.size) / 2 + 3:
			return false
	return true


func _add_room(room: Room) -> void:
	rooms.append(room)


func _connect_rooms() -> void:
	"""Соединяет комнаты коридорами"""
	if rooms.size() < 2:
		return
	
	# Сортируем: старт первым, босс последним
	rooms.sort_custom(func(a, b):
		if a.type == RoomType.START: return true
		if b.type == RoomType.START: return false
		if a.type == RoomType.BOSS: return false
		if b.type == RoomType.BOSS: return true
		return a.grid_x < b.grid_x
	)
	
	# Соединяем последовательно (упрощённый MST)
	for i in range(1, rooms.size()):
		var prev := rooms[i - 1]
		var curr := rooms[i]
		
		curr.connected = true
		prev.connected = true
		
		# Добавляем выходы
		if curr.grid_x > prev.grid_x:
			prev.exits.append(Vector2i(1, 0))
			curr.exits.append(Vector2i(-1, 0))
		elif curr.grid_x < prev.grid_x:
			prev.exits.append(Vector2i(-1, 0))
			curr.exits.append(Vector2i(1, 0))
		
		if curr.grid_y > prev.grid_y:
			prev.exits.append(Vector2i(0, 1))
			curr.exits.append(Vector2i(0, -1))
		elif curr.grid_y < prev.grid_y:
			prev.exits.append(Vector2i(0, -1))
			curr.exits.append(Vector2i(0, 1))


func _render_dungeon() -> void:
	"""Рендерит подземелье"""
	# Рендерим все комнаты
	for room in rooms:
		_render_room(room)
	
	# Рендерим коридоры
	for i in range(1, rooms.size()):
		_render_corridor(rooms[i-1], rooms[i])


func _render_room(room: Room) -> void:
	"""Рендерит одну комнату"""
	var rx := room.rect.position.x
	var ry := room.rect.position.y
	var rw := room.rect.size.x
	var rh := room.rect.size.y
	
	# Пол комнаты
	for x in range(rx, rx + rw):
		for y in range(ry, ry + rh):
			floor_tilemap.set_cell(0, Vector2i(x, y), 0, Vector2i(0, 0))
	
	# Стены (рамка)
	# Верхняя и нижняя
	for x in range(rx - 1, rx + rw + 1):
		walls_tilemap.set_cell(0, Vector2i(x, ry - 1), 1, Vector2i(0, 0))
		walls_tilemap.set_cell(0, Vector2i(x, ry + rh), 1, Vector2i(0, 0))
	
	# Левая и правая
	for y in range(ry - 1, ry + rh + 1):
		walls_tilemap.set_cell(0, Vector2i(rx - 1, y), 1, Vector2i(0, 0))
		walls_tilemap.set_cell(0, Vector2i(rx + rw, y), 1, Vector2i(0, 0))
	
	# Проходы (выходы)
	for exit in room.exits:
		_create_passage(room, exit)


func _create_passage(room: Room, direction: Vector2i) -> void:
	"""Создаёт проход в стене"""
	var cx := room.center.x
	var cy := room.center.y
	var half := room.size / 2
	
	var wall_pos: Vector2i
	
	match direction:
		Vector2i(1, 0):   # право
			wall_pos = Vector2i(cx + half, cy)
		Vector2i(-1, 0):  # лево
			wall_pos = Vector2i(cx - half - 1, cy)
		Vector2i(0, 1):   # низ
			wall_pos = Vector2i(cx, cy + half)
		Vector2i(0, -1):  # верх
			wall_pos = Vector2i(cx, cy - half - 1)
	
	# Убираем стену
	walls_tilemap.set_cell(0, wall_pos, -1, Vector2i(-1, -1))
	# Добавляем пол
	floor_tilemap.set_cell(0, wall_pos, 2, Vector2i(0, 0))


func _render_corridor(a: Room, b: Room) -> void:
	"""Рендерит коридор между комнатами"""
	var start := Vector2i(a.center.x, a.center.y)
	var end := Vector2i(b.center.x, b.center.y)
	
	# L-образный коридор
	var corner := Vector2i(end.x, start.y)
	
	# Рендерим сегменты
	_render_corridor_segment(start, corner)
	_render_corridor_segment(corner, end)


func _render_corridor_segment(from: Vector2i, to: Vector2i) -> void:
	"""Рендерит сегмент коридора"""
	var min_x := min(from.x, to.x)
	var max_x := max(from.x, to.x)
	var min_y := min(from.y, to.y)
	var max_y := max(from.y, to.y)
	
	var half_w := corridor_width / 2
	
	# Пол коридора
	for x in range(min_x - half_w, max_x + half_w + 1):
		for y in range(min_y - half_w, max_y + half_w + 1):
			floor_tilemap.set_cell(0, Vector2i(x, y), 2, Vector2i(0, 0))
	
	# Стены коридора
	for x in [min_x - half_w - 1, max_x + half_w]:
		for y in range(min_y - half_w, max_y + half_w + 1):
			walls_tilemap.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0))
	
	for y in [min_y - half_w - 1, max_y + half_w]:
		for x in range(min_x - half_w, max_x + half_w + 1):
			walls_tilemap.set_cell(0, Vector2i(x, y), 1, Vector2i(0, 0))


func regenerate() -> void:
	"""Перегенерирует подземелье"""
	generate_dungeon()


# Публичные методы
func get_start_room() -> Room:
	for r in rooms:
		if r.type == RoomType.START:
			return r
	return null


func get_boss_room() -> Room:
	for r in rooms:
		if r.type == RoomType.BOSS:
			return r
	return null


func get_fight_rooms() -> Array[Room]:
	var result: Array[Room] = []
	for r in rooms:
		if r.type == RoomType.FIGHT:
			result.append(r)
	return result


func get_all_rooms() -> Array[Room]:
	return rooms
