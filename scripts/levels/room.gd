extends Node2D
class_name Room
## Room — базовый класс для всех комнат подземелья.
## Управляет состоянием комнаты, спавном врагов и дверьми.

enum RoomType {
	START,   # Стартовая комната (игроки появляются тут)
	FIGHT,   # Боевая комната (враги)
	CHEST,   # Комната с сундуком / лутом
	SHRINE,  # Святилище (усиление, исцеление)
	BOSS,    # Арена с боссом
}

enum RoomState {
	SLEEP,
	FIGHT,
	CLEARED
}

const DOOR_SCENE = preload("res://scenes/levels/door.tscn")

@export var room_type: RoomType = RoomType.FIGHT
@export var room_size: Vector2i = Vector2i(15, 12)

# --- Данные, заполняемые при генерации ---
var spawn_data: Array[Dictionary] = [] # Массив словарей { type: SpawnType, map_pos: Vector2i, node: SpawnPoint }
var door_slots: Array[Vector2i]   = [] # Глобальные тайловые координаты дверей (заполняются в генераторе)
var grid_position: Vector2i       = Vector2i.ZERO
var room_id: int                  = -1

var current_state: RoomState = RoomState.SLEEP
var enemies_alive: int = 0
var spawned_doors: Array[Node2D] = []

# --- Ноды тайловых слоёв (подключаются в сценах-наследниках) ---
@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var wall_layer: TileMapLayer = $WallLayer
@onready var spawn_root: Node2D   = $SpawnPoints

# Автоматически создаём триггер-зону для комнаты
var activation_area: Area2D

func _ready() -> void:
	_build_room()
	_collect_spawn_points()
	_setup_activation_area()
	
	if room_type == RoomType.START or room_type == RoomType.SHRINE:
		# В стартовых и мирных комнатах не бывает боя
		call_deferred("set_state", RoomState.CLEARED)

## Строит тайловую геометрию комнаты (пол + стены по периметру).
func _build_room() -> void:
	var w := room_size.x
	var h := room_size.y

	for x in range(w):
		for y in range(h):
			var coord := Vector2i(x, y)
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				wall_layer.set_cell(coord, 0, Vector2i(1, 0))
			else:
				floor_layer.set_cell(coord, 0, Vector2i(0, 0))

## Собирает SpawnPoint'ы
func _collect_spawn_points() -> void:
	spawn_data.clear()
	for child in spawn_root.get_children():
		if child is SpawnPoint:
			spawn_data.append({
				"type": child.type,
				"map_pos": Vector2i(floor(child.position.x / 64.0), floor(child.position.y / 64.0)),
				"node": child
			})

## Зона входа в комнату
func _setup_activation_area() -> void:
	activation_area = Area2D.new()
	activation_area.collision_layer = 0
	activation_area.collision_mask = 2 # Слушаем только игроков
	
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	
	# Делаем зону активации чуть меньше визуального периметра комнаты 
	# (умножаем на 64 размер тайла, вычитаем по 1 тайлу с каждой стороны)
	var tw = (room_size.x - 2) * 64
	var th = (room_size.y - 2) * 64
	rect.size = Vector2(tw, th)
	col.shape = rect
	
	# Смещаем центр из (0,0) (левый верхний) в центр комнаты
	col.position = Vector2((room_size.x * 64) / 2.0, (room_size.y * 64) / 2.0)
	
	activation_area.add_child(col)
	add_child(activation_area)
	
	activation_area.body_entered.connect(_on_player_entered)

func _on_player_entered(body: Node2D) -> void:
	if current_state == RoomState.SLEEP and body.is_in_group("player"):
		set_state(RoomState.FIGHT)

func set_state(new_state: RoomState) -> void:
	if current_state == new_state:
		return
		
	current_state = new_state
	match current_state:
		RoomState.FIGHT:
			_start_fight()
		RoomState.CLEARED:
			_end_fight()

func _start_fight() -> void:
	print("[Room %d] В СТАТУС FIGHT" % room_id)
	# 1. Закрываем двери
	_spawn_doors()
	
	# 2. Спавним врагов
	_spawn_enemies()

func _end_fight() -> void:
	print("[Room %d] В СТАТУС CLEARED" % room_id)
	# 1. Открываем двери
	for d in spawned_doors:
		d.queue_free()
	spawned_doors.clear()
	
	# 2. Спавним лут/портал по точкам, заготовленным заранее
	_spawn_loot()

# --- Размещение дверей ---
func _spawn_doors() -> void:
	if door_slots.is_empty():
		return
	
	# Координаты комнаты в глобальном тайлмапе генератора
	var base_x = grid_position.x
	var base_y = grid_position.y
	
	# Ищем границы комнаты в тайлах (включая стены генератора)
	var rx_min = base_x
	var rx_max = base_x + room_size.x - 1
	var ry_min = base_y
	var ry_max = base_y + room_size.y - 1

	for slot_map_pos in door_slots:
		# slot_map_pos — глобальная координата вырезанного коридора
		# Создаём инстанс двери (локально для комнаты, поэтому вычитаем grid_position)
		var local_tile = slot_map_pos - grid_position
		
		# Центр тайла
		var world_pos = Vector2(local_tile.x * 64 + 32, local_tile.y * 64 + 32)
		
		var door = DOOR_SCENE.instantiate()
		door.position = world_pos
		
		# Вычисляем вектор "вталкивания" направленный к центру комнаты
		var push_dir := Vector2.ZERO
		if slot_map_pos.x <= rx_min: push_dir = Vector2.RIGHT        # дверь слева, толкаем вправо
		elif slot_map_pos.x >= rx_max: push_dir = Vector2.LEFT     # дверь справа, толкаем влево
		elif slot_map_pos.y <= ry_min: push_dir = Vector2.DOWN       # дверь сверху, толкаем вниз
		elif slot_map_pos.y >= ry_max: push_dir = Vector2.UP         # дверь снизу, толкаем вверх
		else:
			# Фолбэк к центру
			push_dir = (door.position.direction_to(get_world_center())).normalized()
		
		door.push_direction = push_dir
		
		# Вращаем дверь визуально: one_way_collision смотрит "вверх" по локальным координатам, 
		# так что нужно повернуть коллизию так, чтобы "вверх" смотрел наружу (т.е. зайти можно СНАРУЖИ -> ВНУТРЬ)
		# В платформерах One-Way пускает снизу вверх. Сверху вниз падать нельзя.
		# В Top-Down One-Way пускает со стороны противопожной локальному "Up".
		# Поэтому мы направляем "Down" двери вглубь комнаты.
		door.rotation = push_dir.angle() - PI/2

		add_child(door)
		spawned_doors.append(door)

# --- Спавн сущностей ---
func _spawn_enemies() -> void:
	enemies_alive = 0
	var slime_scene = preload("res://scenes/enemies/slime.tscn")
	var boss_scene = preload("res://scenes/enemies/slime_boss.tscn")
	
	for s in spawn_data:
		var enemy = null
		if s["type"] == SpawnPoint.SpawnType.ENEMY_SMALL:
			enemy = slime_scene.instantiate()
		elif s["type"] == SpawnPoint.SpawnType.BOSS:
			enemy = boss_scene.instantiate()
			
		if enemy:
			enemy.position = s["node"].position
			add_child(enemy)
			enemies_alive += 1
			
			var hp_comp = enemy.get_node_or_null("HealthComponent")
			if hp_comp != null:
				hp_comp.max_health = int(hp_comp.max_health * GameManager.difficulty_multiplier)
				hp_comp.current_health = hp_comp.max_health
				hp_comp.died.connect(_on_enemy_died)
				
			if "contact_damage" in enemy:
				enemy.contact_damage = int(enemy.contact_damage * GameManager.difficulty_multiplier)
			
	if enemies_alive == 0:
		call_deferred("set_state", RoomState.CLEARED)

func _on_enemy_died() -> void:
	enemies_alive -= 1
	if enemies_alive <= 0:
		set_state(RoomState.CLEARED)

func _spawn_loot() -> void:
	# Спавнит сундуки или порталы после зачистки
	for s in spawn_data:
		if s["type"] == SpawnPoint.SpawnType.PORTAL:
			var portal_scene = load("res://scenes/levels/portal.tscn")
			var p = portal_scene.instantiate()
			p.position = s["node"].position
			add_child(p)


## Возвращает Rect2i этой комнаты в тайловой сетке генератора.
func get_grid_rect() -> Rect2i:
	return Rect2i(grid_position, room_size)

## Возвращает центр комнаты в тайловой сетке.
func get_grid_center() -> Vector2i:
	return grid_position + room_size / 2

## Возвращает мировую позицию центра комнаты.
func get_world_center() -> Vector2:
	if floor_layer:
		return floor_layer.map_to_local(get_grid_center())
	return Vector2.ZERO
