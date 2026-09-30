extends Node
## Навигация и безопасность боевых комнат в реальной физике.
## - Досягаемость: каждый тип врага из дальней точки добирается до неподвижного героя
##   в углу, у двери и за каждым препятствием всех четырёх конфигураций.
## - Кайтинг: герой бегает по кругу; враги в погоне не упираются в колонны/углы.
## - Двери: снаряды игрока снаружи и стрелы врагов изнутри не проходят сквозь закрытую дверь.
## - Перенос: при входе с любой стороны три отставших героя попадают на свободный пол,
##   не друг в друга и не рядом с появившимися врагами.
## godot --headless --fixed-fps 60 --path . res://tests/rooms/nav_checks.tscn

const SMALL := preload("res://scenes/levels/rooms/room_combat_small.tscn")
const LARGE := preload("res://scenes/levels/rooms/room_combat_large.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")
const ENEMIES := {
	"slime": preload("res://scenes/enemies/slime.tscn"),
	"skeleton": preload("res://scenes/enemies/skeleton.tscn"),
	"bat": preload("res://scenes/enemies/bat.tscn"),
	"archer": preload("res://scenes/enemies/archer.tscn"),
	"boss": preload("res://scenes/enemies/slime_boss.tscn"),
}
const PROJECTILES := {
	"arrow": preload("res://scenes/items/arrow.tscn"),
	"fireball": preload("res://scenes/items/fireball.tscn"),
	"enemy_arrow": preload("res://scenes/items/enemy_arrow.tscn"),
}
const TILE := 64.0
const DT := 1.0 / 60.0
const REACH_TIMEOUT := 6.0 # сверх времени пути
const KITE_TIME := 24.0
const KITE_SPEED := 280.0
const STUCK_WINDOW := 1.0
const STUCK_DISTANCE := 10.0
const STUCK_LIMIT := 3.0
const SIDES := ["north", "south", "west", "east"]
const INWARD := {"north": Vector2.DOWN, "south": Vector2.UP, "west": Vector2.RIGHT, "east": Vector2.LEFT}

var failures := 0
var cases := 0
var _hits := 0
var _game: Node
var _player: Player
var _rooms_parent: Node
var _report: Array[String] = []
var _args: Dictionary = {}
var _shots := 0
## Разброс испытаний: смещение точки появления и сторона обхода (seed= для повтора)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if name != "NavChecks":
		var runner := Node.new()
		runner.name = "NavChecks"
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var tests: String = _args.get("tests", "reach,kite,doors,lead,pull")
	_rng.seed = int(_args.get("seed", str(Time.get_ticks_usec())))
	print("NAV_CHECKS seed=%d" % _rng.seed)
	GameManager.start_floor(4, 4242)
	for i in 4:
		await get_tree().process_frame
	_game = get_tree().current_scene
	_player = _game._player
	_rooms_parent = _game._dungeon.get_start_room().get_parent()
	_player.set_physics_process(false)
	_player.health_component.max_health = 1000000
	_player.health_component.current_health = 1000000
	_player.health_component.damage_taken.connect(func(_a: int, _s: Node2D) -> void: _hits += 1)

	get_tree().node_added.connect(func(n: Node) -> void:
		if n is EnemyArrow:
			_shots += 1)
	var index := 0
	for scene in [SMALL, LARGE]:
		for variant in [0, 1]:
			var room := await _make_room(scene, variant, index, true)
			var label := "%s/%d" % ["large" if scene == LARGE else "small", variant]
			if _args.has("only") and _args["only"] != label:
				room.queue_free()
				index += 1
				continue
			if "reach" in tests:
				await _check_reach(room, label)
			if "kite" in tests:
				await _check_kiting(room, label)
			if "doors" in tests:
				await _check_doors(room, label)
			if "lead" in tests and label == "small/0":
				await _check_archer_lead(room, label)
			room.queue_free()
			await get_tree().process_frame
			if "pull" in tests:
				await _check_pull(scene, variant, index, label)
			index += 1
	for line in _report:
		print(line)
	print("NAV_CHECKS: %d cases, %d failures" % [cases, failures])
	get_tree().current_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)


func _check(condition: bool, message: String) -> void:
	cases += 1
	if not condition:
		failures += 1
		push_error(message)


func _make_room(scene: PackedScene, variant: int, index: int, doors: bool) -> Room:
	var room: Room = scene.instantiate()
	room.encounter_seed = variant
	room.room_id = 900 + index
	room.name = "NavRoom_%d" % index
	room.position = Vector2(40000 + index * 4000, 40000)
	_rooms_parent.add_child(room)
	for side in SIDES:
		room.open_connection(side)
	if doors:
		room.current_state = Room.RoomState.CLEARED # без активации встречи
		room._spawn_doors()
	var center := _center(room)
	var map_rid := room.floor_layer.get_navigation_map()
	for i in 60:
		await get_tree().physics_frame
		if NavigationServer2D.map_get_closest_point(map_rid, center).distance_to(center) < 1.0:
			break
	return room


func _center(room: Room) -> Vector2:
	return room.global_position + Vector2(room.room_size) * TILE / 2.0


func _tile_global(room: Room, tile: Vector2i) -> Vector2:
	return room.floor_layer.to_global(room.floor_layer.map_to_local(tile))


func _is_floor(room: Room, tile: Vector2i) -> bool:
	return room.floor_layer.get_cell_source_id(tile) != -1 and room.wall_layer.get_cell_source_id(tile) == -1


## Углы, клетки у дверей и середины сторон каждого препятствия.
func _player_spots(room: Room) -> Array[Vector2i]:
	var w := room.room_size.x
	var h := room.room_size.y
	var spots: Array[Vector2i] = [Vector2i(1, 1), Vector2i(w - 2, 1), Vector2i(1, h - 2), Vector2i(w - 2, h - 2)]
	for side in SIDES:
		spots.append(room.connection_points[side] + Vector2i(INWARD[side]))
	var seen: Dictionary = {}
	for x in range(1, w - 1):
		for y in range(1, h - 1):
			var start := Vector2i(x, y)
			if seen.has(start) or room.wall_layer.get_cell_source_id(start) == -1:
				continue
			var block := Rect2i(start, Vector2i.ONE)
			var queue: Array[Vector2i] = [start]
			seen[start] = true
			while not queue.is_empty():
				var tile: Vector2i = queue.pop_back()
				block = block.expand(tile)
				for step in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var next: Vector2i = tile + step
					if next.x > 0 and next.y > 0 and next.x < w - 1 and next.y < h - 1 \
							and not seen.has(next) and room.wall_layer.get_cell_source_id(next) != -1:
						seen[next] = true
						queue.append(next)
			var last := block.position + block.size # expand() не включает правый/нижний край
			var mid := block.position + (last - block.position) / 2
			spots.append(Vector2i(mid.x, block.position.y - 1))
			spots.append(Vector2i(mid.x, last.y + 1))
			spots.append(Vector2i(block.position.x - 1, mid.y))
			spots.append(Vector2i(last.x + 1, mid.y))
	var result: Array[Vector2i] = []
	for t in spots:
		if _is_floor(room, t) and not result.has(t):
			result.append(t)
	return result


## Самая дальняя от героя безопасная точка появления (как в реальной встрече).
func _far_spawn(room: Room, player_local: Vector2) -> Vector2:
	var players: Array[Vector2] = [player_local]
	var none: Array[Vector2] = []
	var best := Vector2.ZERO
	var best_distance := -1.0
	for x in range(2, room.room_size.x - 2):
		for y in range(2, room.room_size.y - 2):
			var pos := room.floor_layer.map_to_local(Vector2i(x, y))
			if room._is_safe_enemy_position(pos, players, none) and pos.distance_to(player_local) > best_distance:
				best = pos
				best_distance = pos.distance_to(player_local)
	return best


func _spawn(room: Room, kind: String, local_pos: Vector2) -> Node2D:
	var enemy: Node2D = ENEMIES[kind].instantiate()
	enemy.position = local_pos
	room.spawn_root.add_child(enemy)
	return enemy


func _ai(enemy: Node) -> SlimeAI:
	for child in enemy.get_children():
		if child is SlimeAI:
			return child
	return null


func _clear(room: Room) -> void:
	for enemy in room.spawn_root.get_children():
		if enemy.has_node("HealthComponent"):
			enemy.queue_free()
	for node in get_tree().get_nodes_in_group("enemy_projectile"):
		node.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _check_reach(room: Room, label: String) -> void:
	for kind in ENEMIES:
		if _args.has("kinds") and not kind in _args["kinds"].split(","):
			continue
		var worst := 0.0
		for tile in _player_spots(room):
			_player.global_position = _tile_global(room, tile)
			var player_local := room.spawn_root.to_local(_player.global_position)
			var enemy := _spawn(room, kind, _far_spawn(room, player_local) + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12)))
			_ai(enemy)._circumnavigate_side = 1 if _rng.randf() < 0.5 else -1
			_hits = 0
			var t := 0.0
			# Запас: путь по навигации со скоростью врага + время на кружение и замах.
			var path := NavigationServer2D.map_get_path(room.floor_layer.get_navigation_map(),
				enemy.global_position, _player.global_position, true)
			var length := 0.0
			for i in range(1, path.size()):
				length += path[i - 1].distance_to(path[i])
			# Первый запрос сразу после создания комнаты может вернуть вырожденный путь
			length = maxf(length, enemy.global_position.distance_to(_player.global_position) * 1.2)
			var timeout := length / _ai(enemy).base_speed * 1.25 + REACH_TIMEOUT
			while t < timeout and _hits == 0:
				await get_tree().physics_frame
				t += DT
				if _args.has("debug") and int(t / DT) % 30 == 0:
					var dbg := _ai(enemy)
					var nav := enemy.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
					print("  t=%.1f los=%s enemy=%s state=%d target=%s dist=%.0f nav_done=%s next=%s" % [t, dbg._has_line_of_sight() if dbg is ArcherAI else false,
						room.floor_layer.local_to_map(enemy.position), dbg.current_state,
						dbg.target_player.name if is_instance_valid(dbg.target_player) else "-",
						enemy.global_position.distance_to(_player.global_position),
						nav.is_navigation_finished(), nav.get_next_path_position() - enemy.global_position])
			worst = maxf(worst, t - length / _ai(enemy).base_speed)
			var ai := _ai(enemy)
			_check(_hits > 0, "%s: %s did not reach player at %s (enemy at %s, state %s)" % [
				label, kind, tile, room.floor_layer.local_to_map(enemy.position), ai.current_state if ai else -1])
			await _clear(room)
		_report.append("reach %-8s %-9s worst %.1f s over path time" % [label, kind, worst])


## Герой бегает по кольцу вдоль стен; враг «застрял», если в погоне за секунду
## сдвинулся меньше STUCK_DISTANCE, находясь дальше дистанции атаки.
func _check_kiting(room: Room, label: String) -> void:
	var w := room.room_size.x
	var h := room.room_size.y
	var loop: Array[Vector2] = []
	for tile in [Vector2i(2, 2), Vector2i(w - 3, 2), Vector2i(w - 3, h - 3), Vector2i(2, h - 3)]:
		loop.append(_tile_global(room, tile))
	for kind in ENEMIES:
		_player.global_position = loop[0]
		var player_local := room.spawn_root.to_local(_player.global_position)
		var enemies: Array[Node2D] = []
		var used: Array[Vector2] = []
		var players: Array[Vector2] = [player_local]
		for i in (1 if kind == "boss" else 3):
			var pos := _far_spawn(room, player_local)
			for x in range(2, room.room_size.x - 2):
				if room._is_safe_enemy_position(pos, players, used):
					break
				pos = room.floor_layer.map_to_local(Vector2i(x, room.room_size.y / 2))
			used.append(pos)
			enemies.append(_spawn(room, kind, pos))
		var history: Array = []
		var streak: Array[float] = []
		for e in enemies:
			history.append([e.global_position])
			streak.append(0.0)
		var worst := 0.0
		var leg := 0
		var t := 0.0
		_hits = 0
		_shots = 0
		while t < KITE_TIME:
			var target: Vector2 = loop[(leg + 1) % loop.size()]
			_player.global_position = _player.global_position.move_toward(target, KITE_SPEED * DT)
			if _player.global_position.is_equal_approx(target):
				leg += 1
			await get_tree().physics_frame
			t += DT
			for i in enemies.size():
				var e := enemies[i]
				var samples: Array = history[i]
				samples.append(e.global_position)
				var window := int(STUCK_WINDOW / DT)
				if samples.size() <= window:
					continue
				samples.pop_front()
				var ai := _ai(e)
				var chasing := ai != null and (ai.current_state == SlimeAI.State.CHASE \
					or (ai.current_state == SlimeAI.State.ENCIRCLE and not ai is ArcherAI))
				var far := e.global_position.distance_to(_player.global_position) > ai.attack_range + 20.0
				var moved: float = (samples[samples.size() - 1] as Vector2).distance_to(samples[0])
				if chasing and far and moved < STUCK_DISTANCE:
					streak[i] += DT
				else:
					streak[i] = 0.0
				worst = maxf(worst, streak[i])
		_check(worst < STUCK_LIMIT, "%s: %s stuck for %.1f s while kiting" % [label, kind, worst])
		_report.append("kite  %-8s %-9s stuck max %.1f s, hits %d, enemy arrows %d" % [label, kind, worst, _hits, _shots])
		await _clear(room)


## Лучник стреляет с упреждением: герой бежит по длинной прямой мимо лучника на открытом
## месте (без стен, чтобы разворот у стены не смешивался с точностью упреждения).
## Ровный бег без смены направления после фиксации прицела должен наказываться.
func _check_archer_lead(room: Room, label: String) -> void:
	var origin := room.global_position + Vector2(0, 6000)
	var archer: Node2D = ENEMIES["archer"].instantiate()
	archer.get_node("NavigationAgent2D").free() # вне карты навигация уводила бы к ближайшей сетке
	archer.global_position = origin
	_game.add_child(archer)
	var shots_total := 0
	var hits_total := 0
	for run in 6:
		var side := -1.0 if run % 2 else 1.0
		var start := origin + Vector2(-1600 * side, 230)
		var finish := origin + Vector2(1600 * side, 230)
		archer.global_position = origin
		_player.global_position = start
		await get_tree().physics_frame
		_hits = 0
		_shots = 0
		var frame := 0
		while not _player.global_position.is_equal_approx(finish):
			_player.global_position = _player.global_position.move_toward(finish, KITE_SPEED * DT)
			await get_tree().physics_frame
			frame += 1
			if _args.has("debug") and frame % 30 == 0:
				var ai := _ai(archer)
				print("  lead t=%.1f state=%d dist=%.0f los=%s target=%s pos=%s" % [frame * DT, ai.current_state,
					archer.global_position.distance_to(_player.global_position), ai._has_line_of_sight(),
					ai.target_player.name if is_instance_valid(ai.target_player) else "-", (archer.global_position - origin).round()])
		for i in 90: # долёт последних стрел
			await get_tree().physics_frame
		shots_total += _shots
		hits_total += _hits
	archer.queue_free()
	var rate := float(hits_total) / maxf(shots_total, 1)
	_check(shots_total >= 4 and rate >= 0.5, "%s: archer lead %d/%d hits" % [label, hits_total, shots_total])
	_report.append("lead  archer hits %d of %d shots on a straight runner" % [hits_total, shots_total])

## Снаряд снаружи внутрь (игрок) и изнутри наружу (враг) не проходит закрытую дверь.
func _check_doors(room: Room, label: String) -> void:
	_player.global_position = _center(room) + Vector2(0, 5000) # вне траекторий
	await get_tree().physics_frame
	for side in SIDES:
		var local: Vector2i = room.connection_points[side]
		var door_pos := room.to_global(Vector2(local) * TILE + Vector2.ONE * TILE / 2.0)
		var inward: Vector2 = INWARD[side]
		for kind in PROJECTILES:
			var outgoing: bool = kind == "enemy_arrow"
			var direction: Vector2 = -inward if outgoing else inward
			var shot: Node2D = PROJECTILES[kind].instantiate()
			shot.direction = direction
			shot.global_position = door_pos - direction * 160.0
			_game.add_child(shot)
			var passed := -INF
			for i in 90:
				await get_tree().physics_frame
				if not is_instance_valid(shot):
					break
				passed = maxf(passed, (shot.global_position - door_pos).dot(direction))
			_check(not is_instance_valid(shot) and passed < 40.0,
				"%s: %s passed %s door (%.0f px)" % [label, kind, side, passed])
			if is_instance_valid(shot):
				shot.queue_free()


## Три героя вне комнаты переносятся внутрь при входе четвёртого с каждой стороны.
func _check_pull(scene: PackedScene, variant: int, index: int, label: String) -> void:
	var team: Array[Player] = [_player]
	for i in 3:
		var mate: Player = PLAYER.instantiate()
		_game.add_child(mate)
		mate.set_physics_process(false)
		team.append(mate)
	for side in SIDES:
		# Пока комната создаётся и ждёт навигацию, никто не должен стоять в её зоне входа
		for mate in team:
			mate.global_position = Vector2(-50000, -50000) + Vector2(team.find(mate) * 100, 0)
		var room := await _make_room(scene, variant, index, false)
		var inward: Vector2 = INWARD[side]
		var entry: Vector2i = room.connection_points[side] + Vector2i(inward)
		_player.global_position = _tile_global(room, entry)
		for i in range(1, team.size()):
			team[i].global_position = _tile_global(room, room.connection_points[side]) - inward * (200.0 + i * 50.0)
		room._begin_fight(_player) # сразу, до физического кадра: иначе комната сама среагирует на вход
		_check(room.current_state == Room.RoomState.FIGHT, "%s: entry from %s did not start fight" % [label, side])
		var interior := Rect2(room.global_position + Vector2.ONE * TILE, Vector2(room.room_size - Vector2i(2, 2)) * TILE)
		for i in team.size():
			var p := team[i].global_position
			_check(interior.has_point(p), "%s/%s: player %d left outside (%s)" % [label, side, i, p])
			for offset in [Vector2.ZERO, Vector2(18, 0), Vector2(-18, 0), Vector2(0, 18), Vector2(0, -18)]:
				var tile := room.floor_layer.local_to_map(room.floor_layer.to_local(p + offset))
				_check(_is_floor(room, tile), "%s/%s: player %d pulled into wall at %s" % [label, side, i, p])
			for j in range(i + 1, team.size()):
				_check(p.distance_to(team[j].global_position) >= 40.0, "%s/%s: players %d/%d overlap" % [label, side, i, j])
			for enemy in room.spawn_root.get_children():
				if not enemy.has_node("HealthComponent"):
					continue # маркеры точек появления лежат в том же узле
				_check(enemy.global_position.distance_to(p) >= Room.SPAWN_PLAYER_DISTANCE,
					"%s/%s: enemy spawned %.0f px from player %d (%s)" % [label, side,
					enemy.global_position.distance_to(p), i, enemy.scene_file_path.get_file()])
		_check(room._spawned_enemies_count > 0, "%s/%s: no enemies" % [label, side])
		room.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
	for i in range(1, team.size()):
		team[i].queue_free()
	await get_tree().physics_frame
