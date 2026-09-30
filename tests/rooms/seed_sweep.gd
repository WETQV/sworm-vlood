extends Node
## Полная геометрия подземелий на фиксированных seed: по 100 на каждый этаж (1001–1100, …,
## 7001–7100 — те же, что в room_checks). Строятся настоящие комнаты с колоннами/укрытиями
## и коридорами, затем обход клеток пола от центра стартовой комнаты:
## - каждая клетка пола каждой комнаты достижима (нет замкнутых карманов за колоннами);
## - достижимы выход (центр арены — место портала), сундук и святилище (точки их появления);
## - на этаже ровно по одному START, BOSS, CHEST, SHRINE — гарантированный путь прокачки
##   (сундук + святилище = две награды на этаж, см. docs/progression_catalog.md).
## godot --headless --path . res://tests/rooms/seed_sweep.tscn

const DUNGEON := preload("res://scenes/levels/dungeon_generator.tscn")

var failures := 0
var cases := 0
var _bad_seeds: Array[String] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()
	for floor_num in range(1, 8):
		GameManager.current_floor = floor_num
		for index in range(1, 101):
			var seed_value := floor_num * 1000 + index
			var dungeon: DungeonGenerator = DUNGEON.instantiate()
			dungeon.seed_value = seed_value
			add_child(dungeon)
			var problems := _check_dungeon(dungeon)
			cases += 1
			if not problems.is_empty():
				failures += 1
				_bad_seeds.append("%d: %s" % [seed_value, ", ".join(problems)])
				push_error("seed %d: %s" % [seed_value, problems])
			dungeon.free()
	for line in _bad_seeds:
		print("BAD ", line)
	print("SEED_SWEEP: %d floors, %d failures, %.1f s" % [cases, failures, (Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(1 if failures else 0)


func _check_dungeon(dungeon: DungeonGenerator) -> Array[String]:
	var problems: Array[String] = []
	var walkable: Dictionary = {}
	for cell in dungeon.global_floor.get_used_cells():
		if dungeon.global_wall.get_cell_source_id(cell) == -1:
			walkable[cell] = true
	var counts: Dictionary = {}
	for room in dungeon._rooms:
		counts[room.room_type] = int(counts.get(room.room_type, 0)) + 1
		for cell in room.floor_layer.get_used_cells():
			if room.wall_layer.get_cell_source_id(cell) == -1:
				walkable[room.grid_position + cell] = true
	for type in [Room.RoomType.START, Room.RoomType.BOSS, Room.RoomType.CHEST, Room.RoomType.SHRINE]:
		if counts.get(type, 0) != 1:
			problems.append("%s x%d" % [Room.RoomType.keys()[type], counts.get(type, 0)])

	var start := dungeon.get_start_room()
	var origin := start.grid_position + start.room_size / 2
	if not walkable.has(origin):
		return problems + ["start center blocked"]
	var reached: Dictionary = {origin: true}
	var queue: Array[Vector2i] = [origin]
	var i := 0
	while i < queue.size():
		var tile := queue[i]
		i += 1
		for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = tile + step
			if walkable.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)

	for room in dungeon._rooms:
		var unreachable := 0
		for cell in room.floor_layer.get_used_cells():
			if room.wall_layer.get_cell_source_id(cell) == -1 and not reached.has(room.grid_position + cell):
				unreachable += 1
		if unreachable > 0:
			problems.append("%s %s: %d unreachable floor tiles" % [room.name, Room.RoomType.keys()[room.room_type], unreachable])
		var key_tile := Vector2i(-9999, -9999)
		match room.room_type:
			Room.RoomType.BOSS:
				key_tile = room.grid_position + room.floor_layer.local_to_map(Vector2(room.room_size) * Room.TILE_SIZE / 2.0)
			Room.RoomType.CHEST, Room.RoomType.SHRINE:
				var wanted := SpawnPoint.SpawnType.CHEST if room.room_type == Room.RoomType.CHEST else SpawnPoint.SpawnType.SHRINE
				for child in room.spawn_root.get_children():
					if child is SpawnPoint and child.type == wanted:
						key_tile = room.grid_position + room.floor_layer.local_to_map(room.spawn_root.position + child.position)
				if key_tile.x == -9999:
					problems.append("%s: no reward marker" % room.name)
		if key_tile.x != -9999 and not reached.has(key_tile):
			problems.append("%s %s: key point unreachable" % [room.name, Room.RoomType.keys()[room.room_type]])
	return problems
