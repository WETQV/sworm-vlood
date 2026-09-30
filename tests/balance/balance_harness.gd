extends Node
## Балансный стенд (P0 баланса): TTK в контролируемой арене и встречи этажей 6–7.
##
##   godot --path . res://tests/balance/balance_harness.tscn -- mode=ttk class=0 out=C:/tmp/bal
##   godot --path . res://tests/balance/balance_harness.tscn -- mode=rooms class=0 floors=6,7 reps=5 out=C:/tmp/bal
##
## Одиночная игра, один класс на процесс. Результат — <out>/<mode>_<class>.csv (сырые строки)
## и <out>/<mode>_<class>.md (сводка). Время — игровое (сумма delta физических кадров).
##
## Ограничения бота (указаны в отчёте): прицел идеальный (aim_override на цель), рывок —
## по замаху ближайшего врага в радиусе 90 px (бот «видит» состояние ИИ), движение без поиска
## пути (к цели по прямой с обходом через скольжение по стенам).

const ENEMIES := {
	"slime": "res://scenes/enemies/slime.tscn",
	"skeleton": "res://scenes/enemies/skeleton.tscn",
	"archer": "res://scenes/enemies/archer.tscn",
	"bat": "res://scenes/enemies/bat.tscn",
	"boss": "res://scenes/enemies/slime_boss.tscn",
}
const MELEE_CLASSES := [GameManager.PlayerClass.WARRIOR, GameManager.PlayerClass.PALADIN]

var args: Dictionary = {}
var out_dir: String
var player_class: int = 0
var _rows: PackedStringArray = []
var _lines: PackedStringArray = []

# Игровое время (сумма delta физики) — не зависит от просадок кадра
var game_time: float = 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if name != "BalanceHarness":
		var h := Node.new()
		h.set_script(get_script())
		h.name = "BalanceHarness"
		h.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child.call_deferred(h)
		return
	out_dir = args.get("out", OS.get_user_data_dir().path_join("balance"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	player_class = int(args.get("class", "0"))
	GameManager.selected_class = player_class as GameManager.PlayerClass
	await get_tree().process_frame
	if args.get("mode", "ttk") == "ttk":
		await _run_ttk()
	else:
		await _run_rooms()
	get_tree().quit()


func _physics_process(delta: float) -> void:
	game_time += delta


func wait_game(seconds: float) -> void:
	var until := game_time + seconds
	while game_time < until:
		await get_tree().physics_frame


func _class_name() -> String:
	return GameManager.CLASS_DATA[player_class]["name"]


func _start_floor(floor_num: int, seed_value: int) -> Node:
	get_tree().paused = false
	GameManager.start_floor(floor_num, seed_value)
	for i in 400:
		await get_tree().physics_frame
		var g := get_tree().current_scene
		if g and g.get("_player") != null and is_instance_valid(g._player):
			await wait_game(0.5)
			return g
	return null


func _pct(values: Array, p: float) -> float:
	if values.is_empty():
		return NAN
	var s := values.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(s.size() * p))]


# ════════════════════════════════════════════════════════════════════════════
#  TTK: один класс против неподвижной цели каждого типа
# ════════════════════════════════════════════════════════════════════════════

func _run_ttk() -> void:
	var game := await _start_floor(1, 424242)
	var me: Player = game._player
	var room: Room = game._dungeon.get_start_room()
	var center: Vector2 = room.global_position + Vector2(room.room_size) * 32.0
	var melee: bool = player_class in MELEE_CLASSES
	_rows.append("class,enemy,rep,hp,hits,dmg,overkill,ttk_input,ttk_hit")
	_lines.append("## TTK: %s против неподвижной цели (%s)" % [_class_name(), "вплотную" if melee else "с 220 px"])
	_lines.append("")
	_lines.append("| Цель | HP | Попаданий (медиана) | Перебор урона | TTK от ввода, с (p50 / p90) | TTK от попадания, с (p50 / p90) | Аналитика: попаданий / с |")
	_lines.append("| --- | --- | --- | --- | --- | --- | --- |")

	for enemy_key in ENEMIES:
		var reps: int = 3 if enemy_key == "boss" else int(args.get("reps", "10"))
		var ttk_in: Array = []
		var ttk_hit: Array = []
		var hits_all: Array = []
		var over_all: Array = []
		var hp := 0
		for rep in reps:
			me.teleport_to_position(center)
			me.health_component.set_health(me.health_component.max_health)
			await wait_game(0.3)
			var e: Node2D = load(ENEMIES[enemy_key]).instantiate()
			var spawn_pos: Vector2 = center + Vector2.RIGHT * (34.0 if melee else 220.0)
			e.position = room.spawn_root.to_local(spawn_pos)
			room.spawn_root.add_child(e)
			await wait_game(0.3) # анимация появления
			for c in e.get_children():
				if c is SlimeAI:
					c.set_physics_process(false) # цель стоит и не атакует
			e.knockback_resistance = 100000.0
			e.global_position = spawn_pos
			var hc: HealthComponent = e.health_component
			hp = hc.max_health
			var stats := {"hits": 0, "dmg": 0, "first_hit": -1.0, "death": -1.0}
			hc.damage_taken.connect(func(amount: int, _s) -> void:
				stats["hits"] += 1
				stats["dmg"] += amount
				if stats["first_hit"] < 0.0:
					stats["first_hit"] = game_time)
			hc.died.connect(func(_k) -> void: stats["death"] = game_time)
			var first_input := -1.0
			var deadline := game_time + 60.0
			while stats["death"] < 0.0 and game_time < deadline:
				me.aim_override = e.global_position
				me.health_component.set_health(me.health_component.max_health)
				if me.try_attack((e.global_position - me.global_position).normalized(), e.global_position):
					if first_input < 0.0:
						first_input = game_time
				await get_tree().physics_frame
			var t_in: float = stats["death"] - first_input
			var t_hit: float = stats["death"] - stats["first_hit"]
			ttk_in.append(t_in)
			ttk_hit.append(t_hit)
			hits_all.append(stats["hits"])
			over_all.append(stats["dmg"] - hp)
			_rows.append("%d,%s,%d,%d,%d,%d,%d,%.3f,%.3f" % [player_class, enemy_key, rep, hp, stats["hits"],
				stats["dmg"], stats["dmg"] - hp, t_in, t_hit])
			await wait_game(0.6)
		var dmg: int = me.current_weapon.damage
		var analytic_hits := ceili(float(hp) / dmg)
		_lines.append("| %s | %d | %d | %d | %.2f / %.2f | %.2f / %.2f | %d / %.2f |" % [enemy_key, hp,
			_pct(hits_all, 0.5), _pct(over_all, 0.5), _pct(ttk_in, 0.5), _pct(ttk_in, 0.9),
			_pct(ttk_hit, 0.5), _pct(ttk_hit, 0.9), analytic_hits, (analytic_hits - 1) * me.current_weapon.attack_cooldown])
	me.aim_override = Vector2.INF
	_write("ttk")


# ════════════════════════════════════════════════════════════════════════════
#  Встречи: бот проходит боевые комнаты (и босса на 7-м) без предметов
# ════════════════════════════════════════════════════════════════════════════

func _run_rooms() -> void:
	var floors: PackedStringArray = args.get("floors", "6,7").split(",")
	var reps: int = int(args.get("reps", "5"))
	_rows.append("class,floor,seed,room,room_type,enemies,composition,result,time,hp_start,hp_lost,hits_taken,deaths,enemy_attacks,attacks_per_min,threat_share")
	for fl in floors:
		for rep in reps:
			var seed_value: int = 1000 * int(fl) + rep + 1
			var game := await _start_floor(int(fl), seed_value)
			if game == null:
				continue
			# Все боевые комнаты этажа по очереди + арена босса (только на 7-м — там босс)
			var rooms: Array = []
			for r in game._dungeon.get_rooms():
				if r.room_type == Room.RoomType.FIGHT:
					rooms.append(r)
			if int(fl) == GameManager.LAST_FLOOR and game._dungeon.get_boss_room():
				rooms.append(game._dungeon.get_boss_room())
			for room in rooms:
				if not game._player.health_component.is_alive():
					break # бот погиб — остаток этажа в этом повторе не играем
				var res := await _play_room(game, room)
				_rows.append("%d,%s,%d,%s,%s,%d,%s,%s,%.2f,%d,%d,%d,%d,%d,%.1f,%.3f" % [player_class, fl, seed_value,
					room.name, Room.RoomType.keys()[room.room_type], res["enemies"], res["composition"], res["result"],
					res["time"], res["hp_start"], res["hp_lost"], res["hits_taken"], res["deaths"], res["enemy_attacks"],
					res["attacks_per_min"], res["threat_share"]])
				print("[BAL] %s этаж %s %s: %s за %.1f с, потеря HP %d, атак врагов %d" % [_class_name(), fl, room.name,
					res["result"], res["time"], res["hp_lost"], res["enemy_attacks"]])
	_summarize_rooms()
	_write("rooms")


func _play_room(game: Node, room: Room) -> Dictionary:
	var me: Player = game._player
	# Полное здоровье перед каждой комнатой: сравниваем встречи, а не накопленный урон
	me.health_component.set_health(me.health_component.max_health)
	var hp_start: int = me.health_component.current_health
	var center: Vector2 = room.global_position + Vector2(room.room_size) * 32.0
	me.teleport_to_position(center + Vector2(0, room.room_size.y * 32.0 * 0.6))
	var res := {"enemies": 0, "composition": "", "result": "timeout", "time": 0.0, "hp_start": hp_start,
		"hp_lost": 0, "hits_taken": 0, "deaths": 0, "enemy_attacks": 0, "attacks_per_min": 0.0, "threat_share": 0.0}
	var hits := {"n": 0, "dmg": 0}
	var on_hit := func(amount: int, _s) -> void:
		hits["n"] += 1
		hits["dmg"] += amount
	me.health_component.damage_taken.connect(on_hit)

	# Ждём начала боя
	var wait_deadline := game_time + 5.0
	while room.current_state == Room.RoomState.SLEEP and game_time < wait_deadline:
		await get_tree().physics_frame
	var t0 := game_time
	await wait_game(0.1)
	var composition := {}
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.health_component.is_alive():
			res["enemies"] += 1
			var k: String = e.scene_file_path.get_file().get_basename()
			composition[k] = composition.get(k, 0) + 1
	var comp_parts: PackedStringArray = []
	for k in composition:
		comp_parts.append("%s×%d" % [k, composition[k]])
	res["composition"] = " ".join(comp_parts)

	var last_states := {}
	var threat_time := 0.0
	var dash_cd := 0.0
	var deadline := game_time + float(args.get("room_timeout", "90"))
	while room.current_state != Room.RoomState.CLEARED and game_time < deadline:
		if not me.health_component.is_alive():
			res["deaths"] = 1
			res["result"] = "death"
			break
		var dt: float = 1.0 / Engine.physics_ticks_per_second
		var target: Node2D = null
		var threat := false
		for e in get_tree().get_nodes_in_group("enemy"):
			if not e.health_component.is_alive():
				continue
			if target == null or e.global_position.distance_to(me.global_position) < target.global_position.distance_to(me.global_position):
				target = e
			for c in e.get_children():
				if c is SlimeAI:
					var st: int = c.current_state
					if last_states.get(c.get_instance_id(), -1) != st and st == SlimeAI.State.LUNGE:
						res["enemy_attacks"] += 1
					last_states[c.get_instance_id()] = st
					var dist: float = e.global_position.distance_to(me.global_position)
					if st in [SlimeAI.State.WINDUP, SlimeAI.State.LUNGE] and (dist < 150.0 or c is ArcherAI):
						threat = true
					# Рывок от замаха ближнего врага
					if st == SlimeAI.State.WINDUP and dist < 90.0 and not (c is ArcherAI) and dash_cd <= 0.0:
						var away: Vector2 = (me.global_position - e.global_position).normalized()
						if me.try_dash(away.orthogonal() if randf() < 0.5 else -away.orthogonal()):
							dash_cd = 0.8
		if threat:
			threat_time += dt
		dash_cd -= dt
		if target:
			_bot_move(me, target)
			me.aim_override = target.global_position
			me.try_attack((target.global_position - me.global_position).normalized(), target.global_position)
		await get_tree().physics_frame

	_release()
	me.aim_override = Vector2.INF
	var t: float = game_time - t0
	if room.current_state == Room.RoomState.CLEARED:
		res["result"] = "cleared"
	res["time"] = t
	res["hp_lost"] = hits["dmg"]
	res["hits_taken"] = hits["n"]
	res["attacks_per_min"] = res["enemy_attacks"] / maxf(t, 0.001) * 60.0
	res["threat_share"] = threat_time / maxf(t, 0.001)
	me.health_component.damage_taken.disconnect(on_hit)
	# Убираем остатки (если таймаут/смерть), чтобы следующая комната начиналась чисто
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	get_tree().paused = false # экран смерти мог поставить паузу
	await wait_game(0.5)
	return res


## Движение бота: ближний бой — вплотную, дальний — держим 180–260 px
func _bot_move(me: Player, target: Node2D) -> void:
	var to_t: Vector2 = target.global_position - me.global_position
	var dist: float = to_t.length()
	var dir := Vector2.ZERO
	if player_class in MELEE_CLASSES:
		if dist > 36.0:
			dir = to_t.normalized()
	else:
		if dist < 170.0:
			dir = -to_t.normalized()
		elif dist > 260.0:
			dir = to_t.normalized()
		else:
			dir = to_t.normalized().orthogonal() * 0.6 # стрейф
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	if dir.x < -0.3: Input.action_press("move_left", minf(1.0, -dir.x * 1.5))
	if dir.x > 0.3: Input.action_press("move_right", minf(1.0, dir.x * 1.5))
	if dir.y < -0.3: Input.action_press("move_up", minf(1.0, -dir.y * 1.5))
	if dir.y > 0.3: Input.action_press("move_down", minf(1.0, dir.y * 1.5))


func _release() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "attack", "dash"]:
		Input.action_release(a)


func _summarize_rooms() -> void:
	# Группируем по этажу и типу комнаты
	var groups := {}
	for i in range(1, _rows.size()):
		var c := _rows[i].split(",")
		var key := "%s|%s" % [c[1], c[4]]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(c)
	_lines.append("## Встречи: %s, без предметов, полное HP перед каждой комнатой" % _class_name())
	_lines.append("")
	_lines.append("| Этаж | Комната | Встреч | Зачищено | Смертей | Время, с (p50 / p90) | Потеря HP, % (p50 / p90) | Попаданий по игроку (p50) | Атак врагов/мин (p50) | Доля времени под угрозой (p50) |")
	_lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for key: String in groups:
		var rows: Array = groups[key]
		var times: Array = []
		var loss: Array = []
		var hits: Array = []
		var apm: Array = []
		var thr: Array = []
		var cleared := 0
		var deaths := 0
		for c in rows:
			times.append(float(c[8]))
			loss.append(100.0 * float(c[10]) / maxf(1.0, float(c[9])))
			hits.append(int(c[11]))
			apm.append(float(c[14]))
			thr.append(float(c[15]))
			if c[7] == "cleared":
				cleared += 1
			deaths += int(c[12])
		var parts: PackedStringArray = key.split("|")
		_lines.append("| %s | %s | %d | %d | %d | %.1f / %.1f | %.0f / %.0f | %d | %.0f | %.0f%% |" % [parts[0], parts[1], rows.size(),
			cleared, deaths, _pct(times, 0.5), _pct(times, 0.9), _pct(loss, 0.5), _pct(loss, 0.9), _pct(hits, 0.5),
			_pct(apm, 0.5), _pct(thr, 0.5) * 100.0])


func _write(mode: String) -> void:
	var f := FileAccess.open(out_dir.path_join("%s_%d.csv" % [mode, player_class]), FileAccess.WRITE)
	f.store_string("\n".join(_rows) + "\n")
	f.close()
	f = FileAccess.open(out_dir.path_join("%s_%d.md" % [mode, player_class]), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
