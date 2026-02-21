extends Node2D
class_name Room

# Room — базовый класс для всех комнат подземелья.

enum RoomType {
	START,
	FIGHT,
	CHEST,
	SHRINE,
	BOSS,
}

enum RoomState {
	SLEEP,
	FIGHT,
	CLEARED
}

const DOOR_SCENE = preload("res://scenes/levels/door.tscn")

@export var room_type: RoomType = RoomType.FIGHT
@export var room_size: Vector2i = Vector2i(15, 12)

var spawn_data:   Array[Dictionary] = []
var door_slots:   Array[Vector2i]   = []
var grid_position: Vector2i         = Vector2i.ZERO
var room_id: int                    = -1

var current_state: RoomState = RoomState.SLEEP
var enemies_alive: int       = 0
var spawned_doors: Array[Node2D] = []

@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var wall_layer:  TileMapLayer = $WallLayer
@onready var spawn_root:  Node2D       = $SpawnPoints

var activation_area: Area2D

func _ready() -> void:
	_build_room()
	_collect_spawn_points()
	_setup_activation_area()

	if room_type == RoomType.START or room_type == RoomType.SHRINE:
		call_deferred("set_state", RoomState.CLEARED)

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

func _collect_spawn_points() -> void:
	spawn_data.clear()
	for child in spawn_root.get_children():
		if child is SpawnPoint:
			spawn_data.append({
				"type":    child.type,
				"map_pos": Vector2i(floor(child.position.x / 64.0), floor(child.position.y / 64.0)),
				"node":    child
			})

func _setup_activation_area() -> void:
	activation_area = Area2D.new()
	activation_area.collision_layer = 0
	activation_area.collision_mask  = 2

	var col  := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size   = Vector2((room_size.x - 2) * 64, (room_size.y - 2) * 64)
	col.shape    = rect
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
		RoomState.FIGHT:   _start_fight()
		RoomState.CLEARED: _end_fight()

func _start_fight() -> void:
	print("[Room %d] В СТАТУС FIGHT" % room_id)
	_spawn_doors()
	_spawn_enemies()

func _end_fight() -> void:
	print("[Room %d] В СТАТУС CLEARED" % room_id)
	for d in spawned_doors:
		d.queue_free()
	spawned_doors.clear()
	_spawn_loot()

# ── Размещение дверей ─────────────────────────────────────────────────────────
func _spawn_doors() -> void:
	if door_slots.is_empty():
		return

	var rx_min := grid_position.x
	var rx_max := grid_position.x + room_size.x - 1
	var ry_min := grid_position.y
	var ry_max := grid_position.y + room_size.y - 1

	for slot_map_pos in door_slots:
		var local_tile := slot_map_pos - grid_position
		var world_pos  := Vector2(local_tile.x * 64 + 32, local_tile.y * 64 + 32)

		var door = DOOR_SCENE.instantiate()
		door.position = world_pos

		var push_dir := Vector2.ZERO
		if   slot_map_pos.x <= rx_min: push_dir = Vector2.RIGHT
		elif slot_map_pos.x >= rx_max: push_dir = Vector2.LEFT
		elif slot_map_pos.y <= ry_min: push_dir = Vector2.DOWN
		elif slot_map_pos.y >= ry_max: push_dir = Vector2.UP
		else:
			push_dir = door.position.direction_to(get_local_center()).normalized()

		door.push_direction = push_dir
		door.rotation       = push_dir.angle() - PI / 2

		add_child(door)
		spawned_doors.append(door)

# ── Спавн сущностей ───────────────────────────────────────────────────────────
func _spawn_enemies() -> void:
	enemies_alive = 0
	var slime_scene = preload("res://scenes/enemies/slime.tscn")
	var boss_scene  = preload("res://scenes/enemies/slime_boss.tscn")

	for s in spawn_data:
		var enemy = null
		if   s["type"] == SpawnPoint.SpawnType.ENEMY_SMALL: enemy = slime_scene.instantiate()
		elif s["type"] == SpawnPoint.SpawnType.ENEMY_LARGE: enemy = slime_scene.instantiate()
		elif s["type"] == SpawnPoint.SpawnType.BOSS:         
			enemy = boss_scene.instantiate()
			print("[Room %d] Спавн БОССА в точке %s" % [room_id, s["node"].position])

		if enemy:
			add_child(enemy)
			# Используем глобальную позицию маркера, чтобы избежать смещений 
			# из-за контейнера SpawnPoints
			enemy.global_position = s["node"].global_position

			var hp_comp = enemy.get_node_or_null("HealthComponent")
			if hp_comp != null:
				enemies_alive += 1
				hp_comp.max_health     = int(hp_comp.max_health * GameManager.difficulty_multiplier)
				# Босса можно усилить дополнительно
				if s["type"] == SpawnPoint.SpawnType.BOSS:
					hp_comp.max_health *= 2 
				
				hp_comp.current_health = hp_comp.max_health
				hp_comp.died.connect(_on_enemy_died)

			if "contact_damage" in enemy:
				var damage_mult = 1.0
				if s["type"] == SpawnPoint.SpawnType.BOSS: damage_mult = 1.5
				enemy.contact_damage = int(enemy.contact_damage * GameManager.difficulty_multiplier * damage_mult)

	if enemies_alive == 0:
		print("[Room %d] Врагов для спавна не найдено, зачистка." % room_id)
		call_deferred("set_state", RoomState.CLEARED)

func _on_enemy_died(_killed_by: Node2D) -> void:
	enemies_alive -= 1
	print("[Room %d] Враг погиб. Осталось: %d" % [room_id, enemies_alive])
	if enemies_alive <= 0:
		set_state(RoomState.CLEARED)

func _spawn_loot() -> void:
	for s in spawn_data:
		if s["type"] == SpawnPoint.SpawnType.PORTAL:
			var portal_scene = load("res://scenes/levels/portal.tscn")
			var p = portal_scene.instantiate()
			p.position = s["node"].position
			add_child(p)

# ── Вспомогательные методы ────────────────────────────────────────────────────
func get_grid_rect() -> Rect2i:
	return Rect2i(grid_position, room_size)

func get_grid_center() -> Vector2i:
	return grid_position + room_size / 2

func get_local_center() -> Vector2:
	return Vector2(room_size.x * 64, room_size.y * 64) * 0.5

# ВАЖНО: Используем global_position, так как position комнаты устанавливается 
# генератором в координатах тайлмапа.
func get_world_center() -> Vector2:
	return global_position + get_local_center()
