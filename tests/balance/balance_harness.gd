extends Node
## Балансный стенд (P0 баланса): TTK в контролируемой арене и встречи этажей 6–7.
##
##   godot --path . res://tests/balance/balance_harness.tscn -- mode=ttk class=0 out=C:/tmp/bal
##   godot --path . res://tests/balance/balance_harness.tscn -- mode=rooms class=0 floors=6,7 reps=5 out=C:/tmp/bal
##   … mode=rooms class=0 party=4 classes=0,1,2,3 ff=1 kill_mid=1 tag=coop4 — кооператив ботов без сети
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
	"necromancer": "res://scenes/enemies/necromancer.tscn",
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
	EnemyScaling.disabled = args.get("scaling", "1") == "0"
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
	_lines.append("## TTK: %s против неподвижной цели, этаж %s (%s)" % [_class_name(), args.get("ttk_floor", "1"), "вплотную" if melee else "с 220 px"])
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
			# Цель с характеристиками этажа ttk_floor (EnemyScaling), соло
			var scene: PackedScene = load(ENEMIES[enemy_key])
			var e: Node2D = scene.instantiate()
			EnemyScaling.apply(e, EnemyScaling.compute(scene, int(args.get("ttk_floor", "1")), 1))
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
	NetworkManager.friendly_fire = args.get("ff", "0") == "1"
	_rows.append("class,floor,seed,room,room_type,enemies,composition,result,time,hp_start,hp_lost,hits_taken,deaths,enemy_attacks,attacks_per_min,threat_share,party,team_damage,enemy_hp")
	for fl in floors:
		for rep in reps:
			var seed_value: int = 1000 * int(fl) + rep + 1
			var game := await _start_floor(int(fl), seed_value)
			if game == null:
				continue
			_spawn_team(game)
			# Все боевые комнаты этажа по очереди + выходная арена (на 7-м — финальный босс)
			var rooms: Array = []
			for r in game._dungeon.get_rooms():
				if r.room_type == Room.RoomType.FIGHT:
					rooms.append(r)
			if game._dungeon.get_boss_room() and args.get("arena", "1") == "1":
				rooms.append(game._dungeon.get_boss_room())
			for room in rooms:
				if _team_alive().is_empty():
					break # группа погибла — остаток этажа в этом повторе не играем
				var res := await _play_room(game, room)
				_rows.append("%d,%s,%d,%s,%s,%d,%s,%s,%.2f,%d,%d,%d,%d,%d,%.1f,%.3f,%d,%d,%d" % [player_class, fl, seed_value,
					room.name, "ARENA" if room.room_type == Room.RoomType.BOSS else "FIGHT", res["enemies"], res["composition"], res["result"],
					res["time"], res["hp_start"], res["hp_lost"], res["hits_taken"], res["deaths"], res["enemy_attacks"],
					res["attacks_per_min"], res["threat_share"], res["party"], res["team_damage"], res["enemy_hp"]])
				print("[BAL] %s ×%d этаж %s %s: %s за %.1f с, потеря HP %d/%d, смертей %d, атак врагов %d" % [_class_name(),
					res["party"], fl, room.name, res["result"], res["time"], res["hp_lost"], res["hp_start"], res["deaths"], res["enemy_attacks"]])
	_summarize_rooms()
	_write("rooms")


## Кооператив без сети: дополнительные герои (classes=1,2,3) в той же игре, каждым
## управляет свой бот через move_override/aim_override — общий Input делить нельзя
## Билды для сравнения (build=weak|typical|strong, только главный герой; контроль — без build):
## слабый — направление ранг 1 + 2 стака; типичный — ранг 2 + 6 стаков (ожидание к 4-му этажу);
## сильный — ранг 3 + 11 стаков (ожидание к 7-му этажу по экономике docs/progression_catalog.md)
func _test_build(style: String) -> Dictionary:
	var skill: String = ProgressionCatalog.class_skills(player_class)[0]
	match style:
		"weak": return {"skills": {skill: 1}, "upgrades": {"vitality": 1, "tempo": 1}, "items": {}}
		"typical": return {"skills": {skill: 2}, "upgrades": {"vitality": 2, "tempo": 2, "agility": 2}, "items": {}}
		"strong": return {"skills": {skill: 3}, "upgrades": {"vitality": 4, "tempo": 4, "agility": 3}, "items": {}}
	return ProgressionCatalog.empty_build()


func _spawn_team(game: Node) -> void:
	var party: int = int(args.get("party", "1"))
	var classes: PackedStringArray = args.get("classes", str(player_class)).split(",")
	var me: Player = game._player
	me.move_override = Vector2.ZERO
	if args.has("build"):
		Progression.builds[me.peer_id] = _test_build(args["build"])
		me.apply_build(Progression.builds[me.peer_id], true)
	for i in range(1, party):
		var mate: Player = load("res://scenes/player/player.tscn").instantiate()
		mate.peer_id = 100 + i
		mate.player_class = int(classes[i % classes.size()])
		mate.name = "Bot_%d" % i
		game.player_container.add_child(mate)
		mate.global_position = me.global_position + Vector2(48 * i, 0)
		mate.apply_build(Progression.get_build(mate.peer_id), true)
		mate.move_override = Vector2.ZERO
		mate.get_node("Camera2D").enabled = false


func _team() -> Array[Player]:
	var result: Array[Player] = []
	for node in get_tree().get_nodes_in_group("player"):
		if node is Player:
			result.append(node)
	return result


func _team_alive() -> Array[Player]:
	return _team().filter(func(p: Player) -> bool: return p.health_component.is_alive())


func _play_room(game: Node, room: Room) -> Dictionary:
	var me: Player = game._player
	var team := _team_alive()
	# Полное здоровье перед каждой комнатой: сравниваем встречи, а не накопленный урон
	var hp_start := 0
	for p in team:
		p.health_component.set_health(p.health_component.max_health)
		hp_start += p.health_component.max_health
	var center: Vector2 = room.global_position + Vector2(room.room_size) * 32.0
	var lead: Player = me if me.health_component.is_alive() else team[0]
	lead.teleport_to_position(center + Vector2(0, room.room_size.y * 32.0 * 0.6))
	var res := {"enemies": 0, "composition": "", "result": "timeout", "time": 0.0, "hp_start": hp_start,
		"hp_lost": 0, "hits_taken": 0, "deaths": 0, "enemy_attacks": 0, "attacks_per_min": 0.0, "threat_share": 0.0,
		"party": team.size(), "team_damage": 0, "enemy_hp": 0}
	var hits := {"n": 0, "dmg": 0, "team": 0}
	var by_source := {} # разбивка урона по источнику (dmg_sources=1)
	var handlers: Array = []
	for p in team:
		var on_hit := func(amount: int, source: Node2D) -> void:
			hits["n"] += 1
			hits["dmg"] += amount
			var src := "?"
			if source:
				src = source.scene_file_path.get_file().get_basename() if source.scene_file_path != "" else source.name
			by_source[src] = int(by_source.get(src, 0)) + amount
			if source is Player or (source and source.get("attacker") is Player):
				hits["team"] += amount
		p.health_component.damage_taken.connect(on_hit)
		handlers.append([p, on_hit])

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
			res["enemy_hp"] += e.health_component.max_health
			var k: String = e.scene_file_path.get_file().get_basename()
			composition[k] = composition.get(k, 0) + 1
	var comp_parts: PackedStringArray = []
	for k in composition:
		comp_parts.append("%s×%d" % [k, composition[k]])
	res["composition"] = " ".join(comp_parts)

	var last_states := {}
	var threat_time := 0.0
	var dash_cd := {}
	var killed_mid := false
	var deadline := game_time + float(args.get("room_timeout", "90"))
	while room.current_state != Room.RoomState.CLEARED and game_time < deadline:
		var alive := _team_alive()
		if alive.is_empty():
			res["result"] = "death"
			break
		# Правило смерти участника посреди встречи: через 2 с погибает второй герой
		if args.get("kill_mid", "0") == "1" and not killed_mid and game_time - t0 > 2.0 and alive.size() > 1:
			killed_mid = true
			var hp_before := _enemy_hp_total()
			alive[1].health_component.take_damage(100000)
			print("[BAL] kill_mid: врагов HP %d → %d (пересчёта нет)" % [hp_before, _enemy_hp_total()])
		var dt: float = 1.0 / Engine.physics_ticks_per_second
		var threat := false
		for e in get_tree().get_nodes_in_group("enemy"):
			if not e.health_component.is_alive():
				continue
			for ch in e.get_children():
				if ch is SlimeAI:
					var st: int = ch.current_state
					if last_states.get(ch.get_instance_id(), -1) != st and st == SlimeAI.State.LUNGE:
						res["enemy_attacks"] += 1
					last_states[ch.get_instance_id()] = st
					if st in [SlimeAI.State.WINDUP, SlimeAI.State.LUNGE] and (e.global_position.distance_to(lead.global_position) < 150.0 or ch is ArcherAI):
						threat = true
		if threat:
			threat_time += dt
		for p in alive:
			_bot_step(p, dash_cd, dt)
		await get_tree().physics_frame

	for p in _team():
		p.move_override = Vector2.ZERO
		p.aim_override = Vector2.INF
	_release()
	var t: float = game_time - t0
	if room.current_state == Room.RoomState.CLEARED:
		res["result"] = "cleared"
	for p in team:
		if not p.health_component.is_alive():
			res["deaths"] += 1
	res["time"] = t
	if args.get("dmg_sources", "0") == "1":
		print("[BAL] урон по источникам %s: %s" % [room.name, by_source])
	res["hp_lost"] = hits["dmg"]
	res["hits_taken"] = hits["n"]
	res["team_damage"] = hits["team"]
	res["attacks_per_min"] = res["enemy_attacks"] / maxf(t, 0.001) * 60.0
	res["threat_share"] = threat_time / maxf(t, 0.001)
	for h in handlers:
		if is_instance_valid(h[0]) and h[0].health_component.damage_taken.is_connected(h[1]):
			h[0].health_component.damage_taken.disconnect(h[1])
	# Убираем остатки (если таймаут/смерть), чтобы следующая комната начиналась чисто
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	get_tree().paused = false # экран смерти мог поставить паузу
	await wait_game(0.5)
	return res


func _enemy_hp_total() -> int:
	var total := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.health_component.is_alive():
			total += e.health_component.max_health
	return total


## Один шаг бота за героя: ближайшая цель, движение по роли, атака, рывок от замаха
func _bot_step(me: Player, dash_cd: Dictionary, dt: float) -> void:
	var target: Node2D = null
	var threat_from := Vector2.INF # замахивающийся враг, который достанет: отходим от него
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e.health_component.is_alive():
			continue
		var d: float = e.global_position.distance_to(me.global_position)
		if target == null or d < target.global_position.distance_to(me.global_position):
			target = e
		for ch in e.get_children():
			if ch is SlimeAI and ch.current_state == SlimeAI.State.WINDUP and d < ch.attack_range + 30.0 and not (ch is ArcherAI):
				threat_from = e.global_position
			# Рывок от замаха врага, который достанет: дальность его атаки + запас
			if ch is SlimeAI and ch.current_state == SlimeAI.State.WINDUP and d < ch.attack_range + 30.0 and not (ch is ArcherAI) \
					and dash_cd.get(me, 0.0) <= 0.0:
				var away: Vector2 = (me.global_position - e.global_position).normalized()
				if me.try_dash(away.orthogonal() if randf() < 0.5 else -away.orthogonal()):
					dash_cd[me] = 0.8
			if ch is BossAI and ch._pattern == "slam" and not ch._pattern_fired and d < ch.slam_radius + 20.0 \
					and dash_cd.get(me, 0.0) <= 0.0 and ch._pattern_timer < 0.3:
				if me.try_dash((me.global_position - e.global_position).normalized()):
					dash_cd[me] = 0.8
	dash_cd[me] = dash_cd.get(me, 0.0) - dt
	if target == null:
		me.move_override = Vector2.ZERO
		return
	me.move_override = _bot_dir(me, target)
	if threat_from.is_finite():
		me.move_override = (me.global_position - threat_from).normalized() # шаг из-под замаха
	me.aim_override = target.global_position
	me.try_attack((target.global_position - me.global_position).normalized(), target.global_position)


## Движение бота: ближний бой — вплотную, дальний — держим 170–260 px
func _bot_dir(me: Player, target: Node2D) -> Vector2:
	var to_t: Vector2 = target.global_position - me.global_position
	var dist: float = to_t.length()
	if me.player_class in MELEE_CLASSES:
		return to_t.normalized() if dist > 36.0 else Vector2.ZERO
	if dist < 170.0:
		# Отход: прямо назад, а у стены — вдоль неё (бот не загоняет себя в угол)
		var away := -to_t.normalized()
		var space := me.get_world_2d().direct_space_state
		for dir: Vector2 in [away, (away + away.orthogonal()).normalized(), (away - away.orthogonal()).normalized(), away.orthogonal(), -away.orthogonal()]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(me.global_position, me.global_position + dir * 80.0, 1))
			if hit.is_empty():
				return dir
		return away.orthogonal()
	if dist > 260.0:
		return to_t.normalized()
	return to_t.normalized().orthogonal() * 0.6 # стрейф


func _release() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "attack", "dash"]:
		Input.action_release(a)


func _summarize_rooms() -> void:
	# Группируем по этажу и типу комнаты
	var groups := {}
	for i in range(1, _rows.size()):
		var c := _rows[i].split(",")
		var key := "%s|%s|%s" % [c[1], c[4], c[16]]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(c)
	_lines.append("## Встречи: %s (группа: %s), без предметов, полное HP перед каждой комнатой%s" % [_class_name(),
		args.get("classes", str(player_class)), ", friendly fire" if args.get("ff", "0") == "1" else ""])
	_lines.append("")
	_lines.append("| Этаж | Комната | Героев | Встреч | Зачищено | Смертей | Время, с (p50 / p90) | Потеря HP группы, % (p50 / p90) | Попаданий по героям (p50) | Атак врагов/мин (p50) | Под угрозой (p50) | HP врагов (p50) | Урон по своим |")
	_lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for key: String in groups:
		var rows: Array = groups[key]
		var times: Array = []
		var loss: Array = []
		var hits: Array = []
		var apm: Array = []
		var thr: Array = []
		var cleared := 0
		var deaths := 0
		var ehp: Array = []
		var team_dmg := 0
		for c in rows:
			times.append(float(c[8]))
			loss.append(100.0 * float(c[10]) / maxf(1.0, float(c[9])))
			hits.append(int(c[11]))
			apm.append(float(c[14]))
			thr.append(float(c[15]))
			if c[7] == "cleared":
				cleared += 1
			deaths += int(c[12])
			ehp.append(int(c[18]))
			team_dmg += int(c[17])
		var parts: PackedStringArray = key.split("|")
		_lines.append("| %s | %s | %s | %d | %d | %d | %.1f / %.1f | %.0f / %.0f | %d | %.0f | %.0f%% | %d | %d |" % [parts[0], parts[1], parts[2],
			rows.size(), cleared, deaths, _pct(times, 0.5), _pct(times, 0.9), _pct(loss, 0.5), _pct(loss, 0.9), _pct(hits, 0.5),
			_pct(apm, 0.5), _pct(thr, 0.5) * 100.0, _pct(ehp, 0.5), team_dmg])


func _write(mode: String) -> void:
	var suffix: String = args.get("tag", str(player_class))
	var f := FileAccess.open(out_dir.path_join("%s_%s.csv" % [mode, suffix]), FileAccess.WRITE)
	f.store_string("\n".join(_rows) + "\n")
	f.close()
	f = FileAccess.open(out_dir.path_join("%s_%s.md" % [mode, suffix]), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
