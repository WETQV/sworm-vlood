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

const DOOR_SCENE   := preload("res://scenes/levels/door.tscn")
const ALTAR_SCRIPT := preload("res://scripts/progression/reward_altar.gd")
const PORTAL_SCENE := preload("res://scenes/levels/portal.tscn")

const SLIME_SCENE      := preload("res://scenes/enemies/slime.tscn")
const SKELETON_SCENE   := preload("res://scenes/enemies/skeleton.tscn")
const ARCHER_SCENE     := preload("res://scenes/enemies/archer.tscn")
const BAT_SCENE        := preload("res://scenes/enemies/bat.tscn")
const SLIME_BOSS_SCENE := preload("res://scenes/enemies/slime_boss.tscn")

const ENCOUNTER_PLANNER := preload("res://scripts/levels/encounter_planner.gd")
const ENEMY_SCENES := {
	"slime": SLIME_SCENE, "skeleton": SKELETON_SCENE,
	"archer": ARCHER_SCENE, "bat": BAT_SCENE,
}
const SPAWN_PLAYER_DISTANCE := 192.0
const SPAWN_ENEMY_DISTANCE := 64.0

var room_id:         int            = -1
var encounter_seed: int = 0
var encounter_plan: Dictionary = {}
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
var _living_enemies: Dictionary = {}

# ── Слои создаём программно, чтобы не было конфликта с @onready ─────────────
var floor_layer: TileMapLayer = null
var wall_layer:  TileMapLayer = null
var spawn_root:  Node2D       = null
var _activation_area: Area2D  = null

# ════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_create_layers()
	_build_room()
	update_autotiles()
	_collect_spawn_points()
	_setup_activation_area()
	if room_type == RoomType.SHRINE:
		_spawn_altar(RewardAltar.Kind.SHRINE) # святилище безопасно и доступно сразу

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

	# TileSet берем из единого ресурса или генерируем
	if floor_layer.tile_set == null:
		if ResourceLoader.exists("res://tilesets/dungeon_tileset.tres"):
			floor_layer.tile_set = load("res://tilesets/dungeon_tileset.tres")
		else:
			floor_layer.tile_set = _make_tileset()
	if wall_layer.tile_set == null:
		wall_layer.tile_set = floor_layer.tile_set  # общий TileSet!

	# Процедурные шейдеры для объёма каменных плит и кладки
	if floor_layer.material == null:
		floor_layer.material = preload("res://resources/shaders/dungeon_floor_material.tres")
	if wall_layer.material == null:
		wall_layer.material = preload("res://resources/shaders/dungeon_wall_material.tres")


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
	img.fill_rect(Rect2i(TILE_SIZE, 0, TILE_SIZE, TILE_SIZE), Color.WHITE)             # стена (белая, чтобы modulate передавался без искажений)
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

	# 16 вариантов альтернативных тайлов стены: битовая маска N(1) | S(2) | W(4) | E(8)
	for mask in range(16):
		var td: TileData
		if mask == 0:
			td = src.get_tile_data(WALL_ATLAS, 0)
		else:
			src.create_alternative_tile(WALL_ATLAS, mask)
			td = src.get_tile_data(WALL_ATLAS, mask)
		
		td.modulate = Color(float(mask) / 15.0, 0.0, 0.0, 1.0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, sq)

	# ── Навигация пола и 8 альтернативных тайлов для контактных теней ──
	var nav := NavigationPolygon.new()
	nav.vertices = sq
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))

	for mask in range(8):
		var fd: TileData
		if mask == 0:
			fd = src.get_tile_data(FLOOR_ATLAS, 0)
		else:
			src.create_alternative_tile(FLOOR_ATLAS, mask)
			fd = src.get_tile_data(FLOOR_ATLAS, mask)
		
		fd.modulate = Color(float(mask) / 7.0, 0.0, 0.0, 1.0)
		fd.set_navigation_polygon(0, nav)

	return ts

## Обновление автотайлов стен и теней пола с учетом соседей
func update_autotiles() -> void:
	if wall_layer == null:
		return
	var used_walls: Array[Vector2i] = wall_layer.get_used_cells()
	var wall_dict: Dictionary = {}
	for c in used_walls:
		wall_dict[c] = true

	for c in used_walls:
		var n: int = 1 if wall_dict.has(c + Vector2i(0, -1)) else 0
		var s: int = 2 if wall_dict.has(c + Vector2i(0, 1)) else 0
		var w: int = 4 if wall_dict.has(c + Vector2i(-1, 0)) else 0
		var e: int = 8 if wall_dict.has(c + Vector2i(1, 0)) else 0
		wall_layer.set_cell(c, 0, WALL_ATLAS, n | s | w | e)

	if floor_layer:
		pass

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


func _add_obstacles(positions: Array[Vector2i], size: Vector2i) -> void:
	for pos in positions:
		for dx in size.x:
			for dy in size.y:
				var tile := pos + Vector2i(dx, dy)
				wall_layer.set_cell(tile, 0, WALL_ATLAS)
				floor_layer.erase_cell(tile)
	update_autotiles()


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
	_activation_area.set_deferred("collision_layer", 0)
	_activation_area.set_deferred("collision_mask", 2)  # слой игрока

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
	if not NetworkManager.is_authority():
		return # бой в комнате запускает хост
	if not body.is_in_group("player"):
		return
	call_deferred("_begin_fight", body)


func _physics_process(_delta: float) -> void:
	if current_state != RoomState.SLEEP or _activation_area == null or not NetworkManager.is_authority():
		return
	# body_entered приходит при касании краем коллизии, до входа центра игрока.
	# Повторяем проверку внутри зоны: второй сигнал body_entered уже не придёт.
	for body in _activation_area.get_overlapping_bodies():
		_begin_fight(body)
		if current_state != RoomState.SLEEP:
			break


func _begin_fight(entering_player: Node2D) -> void:
	if not NetworkManager.is_authority() or current_state != RoomState.SLEEP or not is_instance_valid(entering_player):
		return
	var player := entering_player as Player
	if player == null or not player.health_component.is_alive():
		return
	var interior := Rect2(global_position + Vector2.ONE * TILE_SIZE,
		Vector2(room_size - Vector2i(2, 2)) * TILE_SIZE)
	# Отложенный вход мог устареть: другая комната уже собрала команду.
	if not interior.has_point(player.global_position):
		return
	for sibling in get_parent().get_children():
		if sibling is Room and sibling != self and sibling.current_state == RoomState.FIGHT:
			return
	if _activation_area:
		_activation_area.set_deferred("monitoring", false)
	var occupied: Array[Vector2] = [entering_player.global_position]
	for node in get_tree().get_nodes_in_group("player"):
		var teammate := node as Player
		if teammate == null or teammate == entering_player or interior.has_point(teammate.global_position):
			continue
		if teammate.health_component.is_alive():
			var target := _find_pull_position(entering_player.global_position, occupied, interior)
			teammate.teleport_to_position(target)
			occupied.append(target)
	set_room_state(RoomState.FIGHT)


func _find_pull_position(anchor: Vector2, occupied: Array[Vector2], interior: Rect2) -> Vector2:
	var center := global_position + Vector2(room_size) * TILE_SIZE / 2.0
	var inward := (center - anchor).normalized()
	if inward.is_zero_approx():
		inward = Vector2.DOWN
	var side := inward.orthogonal()
	var directions: Array[Vector2] = [side, -side, inward,
		(side + inward).normalized(), (-side + inward).normalized(),
		-side + inward * 0.5, side + inward * 0.5]
	for radius in [48.0, 72.0, 96.0, 128.0, 160.0]:
		for direction in directions:
			var candidate: Vector2 = anchor + direction.normalized() * radius
			if _is_safe_pull_position(candidate, occupied, interior):
				return candidate
	# Если вокруг входа тесно, берём ближайшую свободную клетку комнаты.
	var nearest := anchor
	var nearest_distance := INF
	for x in range(1, room_size.x - 1):
		for y in range(1, room_size.y - 1):
			var candidate: Vector2 = floor_layer.to_global(floor_layer.map_to_local(Vector2i(x, y)))
			var distance := anchor.distance_squared_to(candidate)
			if distance < nearest_distance and _is_safe_pull_position(candidate, occupied, interior):
				nearest = candidate
				nearest_distance = distance
	return nearest


func _is_safe_pull_position(candidate: Vector2, occupied: Array[Vector2], interior: Rect2) -> bool:
	# Учитываем радиус персонажа: точка у края пола или колонны не подходит.
	for offset in [Vector2.ZERO, Vector2(18, 0), Vector2(-18, 0), Vector2(0, 18), Vector2(0, -18)]:
		var sample: Vector2 = candidate + offset
		if not interior.has_point(sample):
			return false
		var cell := floor_layer.local_to_map(floor_layer.to_local(sample))
		if floor_layer.get_cell_source_id(cell) == -1:
			return false
	for occupied_position in occupied:
		if candidate.distance_squared_to(occupied_position) < 40.0 * 40.0:
			return false
	for point in _enemy_points + _boss_points:
		if candidate.distance_squared_to(point.global_position) < 80.0 * 80.0:
			return false
	return true


# ── Состояния ────────────────────────────────────────────────────────────────
func set_room_state(new_state: RoomState) -> void:
	if current_state == new_state or current_state == RoomState.CLEARED or new_state == RoomState.SLEEP:
		return
	if new_state == RoomState.CLEARED and NetworkManager.is_authority() and not _living_enemies.is_empty():
		return
	current_state = new_state
	if NetworkManager.is_online() and multiplayer.is_server():
		_net_set_room_state.rpc(new_state)
	match current_state:
		RoomState.FIGHT:   _start_fight()
		RoomState.CLEARED: _end_fight()


## Хост сообщает клиентам о смене состояния комнаты (двери, портал)
@rpc("authority", "reliable")
func _net_set_room_state(new_state: RoomState) -> void:
	set_room_state(new_state)


func _start_fight() -> void:
	print("[Room %d] FIGHT" % room_id)
	_spawn_doors()
	if NetworkManager.is_authority():
		_spawn_enemies() # врагов создаёт только хост, клиентам они приходят через спавнер


func _end_fight() -> void:
	print("[Room %d] CLEARED" % room_id)
	var snd = get_node_or_null("/root/SoundManager")
	if snd:
		snd.play_room_cleared()
	_remove_doors()
	_spawn_loot()
	
	# Если это комната босса — спавним портал в центре
	if room_type == RoomType.BOSS:
		var portal = PORTAL_SCENE.instantiate()
		portal.name = "Portal" # одинаковое имя у всех игроков — для сетевых RPC портала
		# Позиция в центре комнаты (пиксельные координаты)
		portal.position = Vector2(room_size) * TILE_SIZE / 2.0
		add_child(portal)
		print("[Room %d] Портал заспавнен в позиции: %s" % [room_id, portal.position])


# ── Двери ────────────────────────────────────────────────────────────────────
# Спавним ОДНУ дверь на каждый открытый проём.
# Дверной объект должен сам закрывать проём шириной CORRIDOR_WIDTH.
func _spawn_doors() -> void:
	print("[Room %d] Спавн дверей. Открытые стороны: %s" % [room_id, used_connections])
	var is_first: bool = true
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
		
		door.visible = true
		add_child(door)
		spawned_doors.append(door)
		if door.has_method("play_appear"):
			door.play_appear(is_first)
			is_first = false


func _remove_doors() -> void:
	var is_first: bool = true
	for door in spawned_doors:
		if is_instance_valid(door):
			if door.has_method("play_disappear"):
				door.play_disappear(is_first)
				is_first = false
			else:
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
	_living_enemies.clear()
	var floor_num: int = GameManager.current_floor
	var alive_players: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Player
		if player and player.health_component.is_alive():
			alive_players.append(spawn_root.to_local(player.global_position))
	var rng := RandomNumberGenerator.new()
	rng.seed = encounter_seed
	var positions := _encounter_positions(alive_players, rng)
	var final_boss := room_type == RoomType.BOSS and floor_num == GameManager.LAST_FLOOR
	# Резервируем безопасную позицию босса до размещения свиты.
	if final_boss and not positions.is_empty():
		var boss_pos: Vector2 = positions[0]
		var center := Vector2(room_size) * TILE_SIZE / 2.0
		for candidate in positions:
			if candidate.distance_squared_to(center) < boss_pos.distance_squared_to(center):
				boss_pos = candidate
		_spawn_enemy_at(SLIME_BOSS_SCENE, boss_pos)
		positions = positions.filter(func(p: Vector2) -> bool: return p.distance_to(boss_pos) >= 128.0)
	encounter_plan = ENCOUNTER_PLANNER.build(encounter_seed, floor_num, alive_players.size(),
		room_size.x >= 20, room_type == RoomType.BOSS, positions.size(), final_boss)
	var roster: Array = encounter_plan["enemies"]
	for i in roster.size():
		_spawn_enemy_at(ENEMY_SCENES[roster[i]], positions[i])
	print("[Room %d] Встреча %s: %d врагов, угроза %d/%d" % [room_id,
		encounter_plan["scenario"], _spawned_enemies_count, encounter_plan["spent"], encounter_plan["budget"]])

	# Если врагов нет, сразу завершаем бой
	if _spawned_enemies_count == 0:
		set_room_state(RoomState.CLEARED)


## Маркеры имеют приоритет; дополнительные места берём только из свободного пола.
func _encounter_positions(players: Array[Vector2], rng: RandomNumberGenerator) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	for point in _enemy_points:
		candidates.append(point.position)
	for point in _boss_points:
		candidates.append(point.position)
	var fallback: Array[Vector2] = []
	for x in range(2, room_size.x - 2):
		for y in range(2, room_size.y - 2):
			fallback.append(floor_layer.map_to_local(Vector2i(x, y)))
	for i in range(fallback.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := fallback[i]
		fallback[i] = fallback[j]
		fallback[j] = temp
	candidates.append_array(fallback)
	var positions: Array[Vector2] = []
	for candidate in candidates:
		if not _is_safe_enemy_position(candidate, players, positions):
			continue
		positions.append(candidate)
	return positions


func _is_safe_enemy_position(pos: Vector2, players: Array[Vector2], occupied: Array[Vector2]) -> bool:
	var tile := floor_layer.local_to_map(pos)
	# Запас по радиусу тела, включая увеличенного босса и границы колонн.
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var neighbor := tile + Vector2i(dx, dy)
			if floor_layer.get_cell_source_id(neighbor) == -1 or wall_layer.get_cell_source_id(neighbor) != -1:
				return false
	for player_pos in players:
		if pos.distance_to(player_pos) < SPAWN_PLAYER_DISTANCE:
			return false
	for other in occupied:
		if pos.distance_to(other) < SPAWN_ENEMY_DISTANCE:
			return false
	return true


func _spawn_enemy_at(scene: PackedScene, local_pos: Vector2) -> void:
	if scene == null: return

	# --- ПРОВЕРКА БЕЗОПАСНОСТИ СПАВНА ---
	# Проверяем по тайлам: есть ли в этой точке пол?
	var map_pos := floor_layer.local_to_map(local_pos)
	
	if floor_layer.get_cell_source_id(map_pos) == -1:
		# Точка в стене/колонне — сдвигаем к центру на 1.5 тайла
		var center := Vector2(room_size) * TILE_SIZE / 2.0
		var dir_to_center := (center - local_pos).normalized()
		local_pos += dir_to_center * TILE_SIZE * 1.5
		print("[Room %d] Спавн в препятствии! Сдвинуто к центру: %s" % [room_id, local_pos])

	var enemy: Node2D
	var game := get_tree().current_scene
	if NetworkManager.is_online() and game and game.has_method("spawn_network_enemy"):
		# В сети враг создаётся через спавнер игры — и сразу появляется у всех игроков
		enemy = game.spawn_network_enemy(scene, spawn_root.to_global(local_pos))
	else:
		enemy = scene.instantiate()
		enemy.position = local_pos
		# Враги — дети spawn_root (так удобнее по координатам)
		spawn_root.add_child(enemy)
	var enemy_id := enemy.get_instance_id()
	_living_enemies[enemy_id] = true
	_spawned_enemies_count = _living_enemies.size()

	# Следим за смертью врага через HealthComponent
	var health = enemy.get_node_or_null("HealthComponent")
	if health:
		health.died.connect(_on_enemy_died.bind(enemy_id))


func _on_enemy_died(_killer, enemy_id: int) -> void:
	if current_state != RoomState.FIGHT or not _living_enemies.has(enemy_id):
		return
	_living_enemies.erase(enemy_id)
	_spawned_enemies_count = _living_enemies.size()
	if _spawned_enemies_count == 0:
		call_deferred("set_room_state", RoomState.CLEARED)


func _spawn_loot() -> void:
	# Сундук появляется после зачистки охраны у всех участников; открывает его хост
	if room_type == RoomType.CHEST:
		_spawn_altar(RewardAltar.Kind.CHEST)


## Сундук/святилище в точке маркера комнаты. Имя и ключ наград одинаковы у всех участников:
## ключ включает этаж и имя комнаты, поэтому награды не повторяются между комнатами/этажами.
func _spawn_altar(kind: RewardAltar.Kind) -> void:
	if has_node("RewardAltar"):
		return
	var pos := Vector2(room_size) * TILE_SIZE / 2.0
	var wanted := SpawnPoint.SpawnType.CHEST if kind == RewardAltar.Kind.CHEST else SpawnPoint.SpawnType.SHRINE
	if spawn_root:
		for child in spawn_root.get_children():
			if child is SpawnPoint and child.type == wanted:
				pos = spawn_root.position + child.position
				break
	var altar: RewardAltar = ALTAR_SCRIPT.new()
	altar.name = "RewardAltar"
	altar.setup(kind, "f%d:%s" % [GameManager.current_floor, name])
	altar.position = pos
	add_child(altar)


# ── Соединения (вызывает генератор) ─────────────────────────────────────────
func get_side_toward(other: Room) -> String:
	var dir := (Vector2(other.get_grid_center()) - Vector2(get_grid_center())).normalized()
	if abs(dir.x) > abs(dir.y):
		return "east" if dir.x > 0 else "west"
	else:
		return "south" if dir.y > 0 else "north"


func get_grid_center() -> Vector2i:
	return grid_position + (room_size / 2)


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
	update_autotiles()


func clear_wall_tiles(global_tiles: Array[Vector2i]) -> void:
	for g_tile in global_tiles:
		var local_tile: Vector2i = g_tile - grid_position
		if local_tile.x >= 0 and local_tile.x < room_size.x and local_tile.y >= 0 and local_tile.y < room_size.y:
			wall_layer.erase_cell(local_tile)
			floor_layer.set_cell(local_tile, 0, FLOOR_ATLAS)
	update_autotiles()


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
