extends Node
## Быстрая проверка ограничений встреч, связности геометрии и цикла зачистки.
## godot --headless --path . res://tests/rooms/room_checks.tscn

const PLANNER := preload("res://scripts/levels/encounter_planner.gd")
const SMALL := preload("res://scenes/levels/rooms/room_combat_small.tscn")
const LARGE := preload("res://scenes/levels/rooms/room_combat_large.tscn")
const DUNGEON := preload("res://scenes/levels/dungeon_generator.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")
var failures := 0
var cases := 0


func _ready() -> void:
	# Проверяющий узел переживает смену игровых сцен.
	if name != "RoomChecks":
		var runner := Node.new()
		runner.name = "RoomChecks"
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	await get_tree().process_frame
	_check_plans()
	_check_generation()
	_check_layouts()
	await _check_first_entry()
	for floor_num in [1, 4, 7]:
		await _check_floor(floor_num)
	print("ROOM_CHECKS: %d cases, %d failures" % [cases, failures])
	# Дать сцене и эффектам освободиться до остановки движка.
	get_tree().current_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _check_plans() -> void:
	for floor_num in range(1, 8):
		for party in range(1, 5):
			for large in [false, true]:
				for slots in [0, 2, 20]:
					for seed_value in range(12):
						for arena in [false, true]:
							var plan := PLANNER.build(seed_value, floor_num, party, large, arena, slots, arena and floor_num == 7)
							_check(plan == PLANNER.build(seed_value, floor_num, party, large, arena, slots, arena and floor_num == 7), "Non-deterministic encounter")
							var roster: Array = plan["enemies"]
							_check(roster.size() <= slots and roster.size() <= plan["cap"], "Enemy cap exceeded")
							var cost := 0
							for kind in roster:
								cost += int(PLANNER.ENEMIES[kind]["cost"])
								_check(int(PLANNER.ENEMIES[kind]["floor"]) <= floor_num, "Role introduced too early")
							cost += int(plan.get("elite_cost", 0)) # надбавка за «Стража» выходной арены
							_check(cost == plan["spent"] and cost <= plan["budget"], "Threat budget exceeded")
							_check(roster.count("archer") <= (2 if large and floor_num >= 5 else 1), "Archer cap exceeded")
							_check(roster.count("bat") <= (4 if large else 2), "Bat cap exceeded")
							cases += 1


func _check_layouts() -> void:
	for scene in [SMALL, LARGE]:
		for variant in [0, 1]:
			var room: Room = scene.instantiate()
			room.encounter_seed = variant
			add_child(room)
			var cells := room.floor_layer.get_used_cells()
			var visited: Dictionary = {cells[0]: true}
			var queue: Array[Vector2i] = [cells[0]]
			var index := 0
			while index < queue.size():
				var tile := queue[index]
				index += 1
				for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var next: Vector2i = tile + step
					if room.floor_layer.get_cell_source_id(next) != -1 and not visited.has(next):
						visited[next] = true
						queue.append(next)
			_check(visited.size() == cells.size(), "Disconnected room floor")
			for tile in room.connection_points.values():
				var inward := Vector2i(Vector2(Vector2i(room.room_size / 2) - tile).normalized().round())
				_check(visited.has(tile + inward), "Blocked doorway approach")
			var players: Array[Vector2] = [Vector2(192, 320), Vector2(256, 384), Vector2(320, 384), Vector2(384, 384)]
			var rng := RandomNumberGenerator.new()
			rng.seed = 42
			var positions := room._encounter_positions(players, rng)
			_check(positions.size() >= 8, "Insufficient safe spawn space")
			var occupied: Array[Vector2] = []
			for pos in positions:
				_check(room._is_safe_enemy_position(pos, players, occupied), "Unsafe spawn")
				occupied.append(pos)
			room.free()
			cases += 1


func _check_generation() -> void:
	# Только граф и назначение типов, без рендера/спавна 700 этажей.
	for floor_num in range(1, 8):
		for index in range(1, 101):
			var dungeon: DungeonGenerator = DUNGEON.instantiate()
			dungeon.seed_value = floor_num * 1000 + index
			dungeon._init_rng()
			dungeon._generate_grid_layout()
			dungeon._assign_room_types()
			var distances := dungeon._compute_bfs_distances(Vector2i(2, 2))
			_check(distances.size() == dungeon._grid.size(), "Disconnected dungeon graph")
			var counts: Dictionary = {}
			for coord in dungeon._grid:
				var type: int = dungeon._grid[coord]["type"]
				counts[type] = int(counts.get(type, 0)) + 1
				_check(dungeon._grid[coord]["scene"] != null, "Room scene missing")
			_check(counts.get(Room.RoomType.START, 0) == 1 and counts.get(Room.RoomType.BOSS, 0) == 1, "Start/exit missing")
			_check(counts.get(Room.RoomType.CHEST, 0) == 1 and counts.get(Room.RoomType.SHRINE, 0) == 1, "Reward room missing")
			dungeon.free()
			cases += 1
	# Отдельный граф без тупиков: квадрат с двумя незанятыми комнатами.
	var dungeon: DungeonGenerator = DUNGEON.instantiate()
	for coord in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3), Vector2i(2, 3)]:
		dungeon._grid[coord] = {"type": Room.RoomType.FIGHT, "scene": null, "connections": []}
	dungeon._grid[Vector2i(2, 2)] = {"type": Room.RoomType.START, "scene": dungeon.room_start_scene, "connections": ["east", "south"]}
	dungeon._grid[Vector2i(3, 2)]["connections"] = ["west", "south"]
	dungeon._grid[Vector2i(3, 3)]["connections"] = ["north", "west"]
	dungeon._grid[Vector2i(2, 3)]["connections"] = ["north", "east"]
	dungeon._assign_room_types()
	var rewards := 0
	for data in dungeon._grid.values():
		if data["type"] in [Room.RoomType.CHEST, Room.RoomType.SHRINE]:
			rewards += 1
	_check(rewards == 2, "No reward fallback on cyclic graph")
	dungeon.free()
	cases += 1


func _check_first_entry() -> void:
	# Реальное пересечение Area2D, а не прямой вызов _begin_fight из центра.
	for side: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var room: Room = SMALL.instantiate()
		add_child(room)
		var player: Player = PLAYER.instantiate()
		var center := Vector2(room.room_size) * 32.0
		var boundary := center + side * Vector2(room.room_size - Vector2i(2, 2)) * 32.0
		player.position = boundary + side * 13.0
		add_child(player)
		player.set_physics_process(false)
		for i in 4:
			await get_tree().physics_frame
			await get_tree().process_frame
		_check(room._activation_area.overlaps_body(player), "Player edge did not enter activation area")
		_check(room.current_state == Room.RoomState.SLEEP, "Room activated before player center entered")
		# Пересечение области непрерывно: второго body_entered здесь не будет.
		player.teleport_to_position(boundary - side * 2.0)
		for i in 4:
			await get_tree().physics_frame
			await get_tree().process_frame
		_check(room.current_state == Room.RoomState.FIGHT, "First continuous entry did not activate room")
		_check(room._spawned_enemies_count > 0, "No enemies on first entry")
		player.queue_free()
		room.queue_free()
		await get_tree().process_frame
		cases += 1


func _check_floor(floor_num: int) -> void:
	GameManager.start_floor(floor_num, 4000 + floor_num)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var game := get_tree().current_scene
	var navigation_map: RID = game._dungeon.global_floor.get_navigation_map()
	var start_room: Room = game._dungeon.get_start_room()
	var navigation_anchor := start_room.global_position + Vector2(start_room.room_size) * 32.0
	for i in 30:
		if NavigationServer2D.map_get_iteration_id(navigation_map) > 0 and NavigationServer2D.map_get_closest_point(navigation_map, navigation_anchor).distance_to(navigation_anchor) < 1.0:
			break
		await get_tree().physics_frame
	_check(NavigationServer2D.map_get_iteration_id(navigation_map) > 0, "Navigation map did not synchronize")
	_check_dungeon_tiles(game._dungeon)
	var player: Player = game._player
	_check(player != null, "Player did not spawn")
	if player == null:
		return
	for room in game._dungeon._rooms:
		if room.room_type not in [Room.RoomType.FIGHT, Room.RoomType.BOSS, Room.RoomType.CHEST]:
			continue
		player.teleport_to_position(room.global_position + Vector2(128, room.room_size.y * 32))
		player.health_component.is_dead = true
		room._begin_fight(player)
		_check(room.current_state == Room.RoomState.SLEEP, "Dead player activated room")
		player.health_component.is_dead = false
		room._begin_fight(player)
		_check(room.current_state == Room.RoomState.FIGHT and room._spawned_enemies_count > 0, "Encounter did not activate")
		var count: int = room._spawned_enemies_count
		room._begin_fight(player)
		_check(room._spawned_enemies_count == count, "Duplicate activation")
		room.set_room_state(Room.RoomState.CLEARED)
		_check(room.current_state == Room.RoomState.FIGHT, "Cleared while enemies still alive")
		# Даже реальный вход в соседнюю комнату не запускает второй бой.
		var original_position := player.global_position
		for other in game._dungeon._rooms:
			if other == room or other.current_state != Room.RoomState.SLEEP:
				continue
			player.teleport_to_position(other.global_position + Vector2(128, other.room_size.y * 32))
			other._begin_fight(player)
			_check(other.current_state == Room.RoomState.SLEEP, "Concurrent room activation")
			player.teleport_to_position(original_position)
			# Проверяем устаревший отложенный запрос после переноса команды.
			other._begin_fight(player)
			_check(other.current_state == Room.RoomState.SLEEP, "Stale room entry activated fight")
			break
		var boss_count := 0
		var waves := 0
		var elites := 0
		# Выходная арена 1–6 идёт двумя волнами: зачищаем каждую, пока волны не кончатся
		while waves < 4:
			waves += 1
			var enemies: Array[Node] = room.spawn_root.get_children()
			for enemy in enemies:
				var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
				if health == null or not health.is_alive():
					continue
				if enemy.scene_file_path == "res://scenes/enemies/slime_boss.tscn":
					boss_count += 1
				if enemy.has_meta("elite"):
					elites += 1
				_check(enemy.global_position.distance_to(player.global_position) >= Room.SPAWN_PLAYER_DISTANCE, "Enemy too close to player")
				var enemy_id := enemy.get_instance_id()
				health.take_damage(100000, player)
				var remaining: int = room._spawned_enemies_count
				room._on_enemy_died(player, enemy_id)
				_check(room._spawned_enemies_count == remaining, "Duplicate death changed count")
			if room._pending_wave.is_empty() and not room._wave_starting:
				break
			await get_tree().process_frame
			_check(room.current_state == Room.RoomState.FIGHT, "Cleared before the last wave")
			await get_tree().create_timer(Room.WAVE_WARNING + 0.1).timeout
		if room.room_type == Room.RoomType.BOSS and floor_num < 7:
			_check(waves == 2 and elites == 1, "Exit arena must have a second wave with one elite (waves %d, elites %d)" % [waves, elites])
		_check(boss_count == (1 if floor_num == 7 and room.room_type == Room.RoomType.BOSS else 0), "Wrong final boss count")
		await get_tree().process_frame
		_check(room.current_state == Room.RoomState.CLEARED and room._spawned_enemies_count == 0, "Encounter did not clear")
		_check(room.spawned_doors.is_empty(), "Doors did not open")
		room._begin_fight(player)
		room.set_room_state(Room.RoomState.FIGHT)
		room.set_room_state(Room.RoomState.SLEEP)
		room.set_room_state(Room.RoomState.CLEARED)
		_check(room.current_state == Room.RoomState.CLEARED and room._spawned_enemies_count == 0, "Cleared room restarted")
		if room.room_type == Room.RoomType.BOSS:
			_check(room.has_node("Portal"), "Exit portal missing")
			var portals := 0
			for child in room.get_children():
				if child.scene_file_path == "res://scenes/levels/portal.tscn":
					portals += 1
			_check(portals == 1, "Duplicate exit portal")
		cases += 1


func _check_dungeon_tiles(dungeon: DungeonGenerator) -> void:
	var owners: Dictionary = {}
	for layer in [dungeon.global_floor, dungeon.global_wall]:
		for tile in layer.get_used_cells():
			_check(not owners.has(tile), "Overlapping corridor floor/wall")
			owners[tile] = true
	for room in dungeon._rooms:
		for layer in [room.floor_layer, room.wall_layer]:
			for tile in layer.get_used_cells():
				var world_tile: Vector2i = room.grid_position + tile
				_check(not owners.has(world_tile), "Overlapping room/corridor tile")
				owners[world_tile] = true
		var map_rid := room.floor_layer.get_navigation_map()
		var center := room.global_position + Vector2(room.room_size) * 32.0
		for side in room.used_connections:
			var tile: Vector2i = room.connection_points[side]
			var inward := Vector2i(Vector2(Vector2i(room.room_size / 2) - tile).normalized().round())
			var start := room.floor_layer.to_global(room.floor_layer.map_to_local(tile + inward))
			var path := NavigationServer2D.map_get_path(map_rid, start, center, true)
			_check(not path.is_empty() and path[path.size() - 1].distance_to(center) < 1.0,
				"No navigation path: %s %s, iteration=%d" % [room.name, side, NavigationServer2D.map_get_iteration_id(map_rid)])
		cases += 1
