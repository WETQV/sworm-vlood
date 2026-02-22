# ============================================================================
#  room.gd — Базовый класс для всех комнат подземелья
# ============================================================================
extends Node2D
class_name Room

enum RoomType { START, FIGHT, CHEST, SHRINE, BOSS }
enum RoomState { SLEEP, FIGHT, CLEARED }

@export var room_type: RoomType = RoomType.FIGHT
@export var room_size: Vector2i = Vector2i(15, 12)

const TILE_SIZE      := 64
const CORRIDOR_HALF  := 1
const FLOOR_ATLAS    := Vector2i(0, 0)
const WALL_ATLAS     := Vector2i(1, 0)

const DOOR_SCENE := preload("res://scenes/levels/door.tscn")

var room_id:         int            = -1
var grid_position:   Vector2i       = Vector2i.ZERO
var current_state:   RoomState      = RoomState.SLEEP

# Точки соединения (локальные тайловые координаты)
var connection_points:  Dictionary    = {}  # {"north": Vector2i, ...}
var used_connections:   Array[String] = []  # Открытые стороны

var spawned_doors: Array[Node2D] = []
var _enemy_points: Array[Marker2D] = []
var _loot_points:  Array[Marker2D] = []
var _boss_points:  Array[Marker2D] = []
var _spawned_enemies_count: int = 0

# ── Слои создаём программно, чтобы не было конфликта с @onready ─────────────
var floor_layer: TileMapLayer = null
var wall_layer:  TileMapLayer = null
var spawn_root:  Node2D       = null
var _activation_area: Area2D  = null

# ════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_create_layers()
	_build_room()
	_collect_spawn_points()
	_setup_activation_area()

# ── Создание слоёв ──────────────────────────────────────────────────────────
func _create_layers() -> void:
	# Используем уже существующие ноды из сцены, если они там есть
	floor_layer = get_node_or_null("FloorLayer")
	wall_layer  = get_node_or_null("WallLayer")
	spawn_root  = get_node_or_null("SpawnPoints")

	if floor_layer == null:
		floor_layer = TileMapLayer.new()
		floor_layer.name = "FloorLayer"
		floor_layer.z_index = -1
		add_child(floor_layer)

	if wall_layer == null:
		wall_layer = TileMapLayer.new()
		wall_layer.name = "WallLayer"
		wall_layer.z_index = 0
		add_child(wall_layer)

	if spawn_root == null:
		spawn_root = Node2D.new()
		spawn_root.name = "SpawnPoints"
		add_child(spawn_root)

	# TileSet нужен только если не назначен через редактор
	if floor_layer.tile_set == null:
		floor_layer.tile_set = _make_tileset()
	if wall_layer.tile_set == null:
		wall_layer.tile_set = floor_layer.tile_set  # общий TileSet!


func _make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# ── ВАЖНО: сначала добавляем слои, потом создаём тайлы ──
	ts.add_physics_layer()                          # физслой 0 — стены
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_navigation_layer()                       # навслой 0 — пол

	var src := TileSetAtlasSource.new()
	var img := Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0,         0, TILE_SIZE, TILE_SIZE), Color(0.23, 0.23, 0.29))  # пол
	img.fill_rect(Rect2i(TILE_SIZE, 0, TILE_SIZE, TILE_SIZE), Color(0.42, 0.42, 0.48))  # стена
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_source(src, 0)  # источник добавляем ДО создания тайлов

	src.create_tile(FLOOR_ATLAS)
	src.create_tile(WALL_ATLAS)

	# Коллизия стены
	var half := float(TILE_SIZE) / 2.0
	var sq   := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2( half,  half), Vector2(-half,  half),
	])
	var wall_data: TileData = src.get_tile_data(WALL_ATLAS, 0)
	if wall_data:
		wall_data.add_collision_polygon(0)
		wall_data.set_collision_polygon_points(0, 0, sq)

	# Навигация пола
	var floor_data: TileData = src.get_tile_data(FLOOR_ATLAS, 0)
	if floor_data:
		var nav := NavigationPolygon.new()
		nav.vertices = sq
		nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		floor_data.set_navigation_polygon(0, nav)

	return ts

# ── Построение геометрии комнаты ────────────────────────────────────────────
func _build_room() -> void:
	var w := room_size.x
	var h := room_size.y

	for x in range(w):
		for y in range(h):
			var tile := Vector2i(x, y)
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				wall_layer.set_cell(tile, 0, WALL_ATLAS)
			else:
				floor_layer.set_cell(tile, 0, FLOOR_ATLAS)

	# Центры каждой стены (локальные координаты)
	connection_points = {
		"north": Vector2i(int(w / 2.0), 0),
		"south": Vector2i(int(w / 2.0), h - 1),
		"west":  Vector2i(0,     int(h / 2.0)),
		"east":  Vector2i(w - 1, int(h / 2.0)),
	}

func _collect_spawn_points() -> void:
	_enemy_points.clear()
	_loot_points.clear()
	_boss_points.clear()
	
	if spawn_root == null: return
	
	for child in spawn_root.get_children():
		if child is SpawnPoint:
			match child.type:
				SpawnPoint.SpawnType.ENEMY_SMALL, SpawnPoint.SpawnType.ENEMY_LARGE:
					_enemy_points.append(child)
				SpawnPoint.SpawnType.CHEST:
					_loot_points.append(child)
				SpawnPoint.SpawnType.BOSS:
					_boss_points.append(child)
	
	print("[Room %d] Собрано точек: Врагов: %d, Боссов: %d, Лута: %d" % [
		room_id, _enemy_points.size(), _boss_points.size(), _loot_points.size()
	])


# ── Зона активации ──────────────────────────────────────────────────────────
func _setup_activation_area() -> void:
	if room_type == RoomType.START or room_type == RoomType.SHRINE:
		current_state = RoomState.CLEARED
		return

	_activation_area = Area2D.new()
	_activation_area.collision_layer = 0
	_activation_area.collision_mask  = 2  # слой игрока

	var col  := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size    = Vector2((room_size.x - 2) * TILE_SIZE, (room_size.y - 2) * TILE_SIZE)
	col.shape    = rect
	col.position = Vector2(room_size.x * TILE_SIZE / 2.0, room_size.y * TILE_SIZE / 2.0)

	_activation_area.add_child(col)
	add_child(_activation_area)
	_activation_area.body_entered.connect(_on_player_entered)


func _on_player_entered(body: Node2D) -> void:
	if current_state != RoomState.SLEEP:
		return
	if not body.is_in_group("player"):
		return
	_activation_area.set_deferred("monitoring", false)
	set_room_state(RoomState.FIGHT)


# ── Состояния ────────────────────────────────────────────────────────────────
func set_room_state(new_state: RoomState) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	match current_state:
		RoomState.FIGHT:   _start_fight()
		RoomState.CLEARED: _end_fight()


func _start_fight() -> void:
	print("[Room %d] FIGHT" % room_id)
	_spawn_doors()
	_spawn_enemies()


func _end_fight() -> void:
	print("[Room %d] CLEARED" % room_id)
	_remove_doors()
	_spawn_loot()


# ── Двери ────────────────────────────────────────────────────────────────────
# Спавним ОДНУ дверь на каждый открытый проём.
# Дверной объект должен сам закрывать проём шириной CORRIDOR_WIDTH.
func _spawn_doors() -> void:
	print("[Room %d] Спавн дверей. Открытые стороны: %s" % [room_id, used_connections])
	for side in used_connections:
		var local_center: Vector2i = connection_points[side]
		var world_pos := Vector2(
			local_center.x * TILE_SIZE + TILE_SIZE / 2.0,
			local_center.y * TILE_SIZE + TILE_SIZE / 2.0
		)

		var door = DOOR_SCENE.instantiate()
		door.position       = world_pos
		door.push_direction = _get_push_dir(side)
		door.rotation       = _get_door_rot(side)
		
		# Убеждаемся, что дверь видна (на всякий случай)
		door.visible = true
		
		add_child(door)
		spawned_doors.append(door)


func _remove_doors() -> void:
	for door in spawned_doors:
		if is_instance_valid(door):
			door.queue_free()
	spawned_doors.clear()


func _get_push_dir(side: String) -> Vector2:
	match side:
		"north": return Vector2.DOWN
		"south": return Vector2.UP
		"west":  return Vector2.RIGHT
		"east":  return Vector2.LEFT
	return Vector2.ZERO


func _get_door_rot(side: String) -> float:
	match side:
		"north": return 0.0
		"south": return PI
		"west":  return -PI / 2.0
		"east":  return  PI / 2.0
	return 0.0


# ── Спавн врагов / лута ──────────────────────────────────────────────────────
func _spawn_enemies() -> void:
	_spawned_enemies_count = 0
	
	# Спавним обычных врагов
	var slime_scene = load("res://scenes/enemies/slime.tscn")
	for p in _enemy_points:
		_spawn_enemy_at(slime_scene, p.position)
	
	# Спавним босса
	var boss_scene = load("res://scenes/enemies/slime_boss.tscn")
	for p in _boss_points:
		_spawn_enemy_at(boss_scene, p.position)
	
	# Если врагов нет, сразу завершаем бой
	if _spawned_enemies_count == 0:
		set_room_state(RoomState.CLEARED)


func _spawn_enemy_at(scene: PackedScene, local_pos: Vector2) -> void:
	if scene == null: return
	
	var enemy = scene.instantiate()
	enemy.position = local_pos
	
	# Враги — дети spawn_root (так удобнее по координатам)
	spawn_root.add_child(enemy)
	_spawned_enemies_count += 1
	
	# Следим за смертью врага через HealthComponent
	var health = enemy.get_node_or_null("HealthComponent")
	if health:
		health.died.connect(_on_enemy_died)


func _on_enemy_died(_killer) -> void:
	_spawned_enemies_count -= 1
	if _spawned_enemies_count <= 0:
		set_room_state(RoomState.CLEARED)


func _spawn_loot() -> void:
	# Пока просто логируем, так как нет сцены сундука под рукой
	print("[Room %d] Спавн лута в %d точках" % [room_id, _loot_points.size()])
	# Здесь будет инстантиация сундуков по _loot_points


# ── Соединения (вызывает генератор) ─────────────────────────────────────────
func get_side_toward(other: Room) -> String:
	var dir := (Vector2(other.get_grid_center()) - Vector2(get_grid_center())).normalized()
	if abs(dir.x) > abs(dir.y):
		return "east" if dir.x > 0 else "west"
	else:
		return "south" if dir.y > 0 else "north"


func get_grid_center() -> Vector2i:
	return grid_position + room_size / 2


func get_global_connection_point(side: String) -> Vector2i:
	return grid_position + connection_points.get(side, Vector2i.ZERO)


func open_connection(side: String) -> void:
	if side in used_connections:
		return
	used_connections.append(side)

	var center: Vector2i = connection_points[side]
	for tile in _get_opening_tiles(side, center):
		wall_layer.erase_cell(tile)
		floor_layer.set_cell(tile, 0, FLOOR_ATLAS)


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


# ── Публичный API ────────────────────────────────────────────────────────────
func get_grid_rect() -> Rect2i:
	return Rect2i(grid_position, room_size)


func is_cleared() -> bool:
	return current_state == RoomState.CLEARED
