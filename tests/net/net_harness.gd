extends Node
## Сетевой тестовый стенд SwormVlood (P0: замеры и воспроизведение).
##
## Запуск (каждая роль — отдельный процесс Godot):
##   godot --path . res://tests/net/net_harness.tscn -- role=host players=2 scenario=walk out=C:/tmp/run
##   godot --path . res://tests/net/net_harness.tscn -- role=client port=7011 tag=c1 out=C:/tmp/run
##   godot --path . res://tests/net/net_harness.tscn -- role=proxy listen=7011 target=7010 latency=50 jitter=10 loss=1
##
## Хост ждёт players участников, запускает забег, боты ходят через настоящий Input,
## каждый процесс пишет <out>/<tag>.csv (позиции всех игроков каждый кадр) и <tag>_stats.csv
## (RTT, трафик, время кадра раз в секунду). Анализ: tests/net/analyze.py.
##
## Сценарии:
##   walk   — все ходят по стартовой комнате (рывки/ошибка позиции удалённых игроков)
##   pull   — хост входит в боевую комнату, остальные стоят снаружи (подтягивание в комнату)
##   combat — все в боевой комнате, атакуют и делают рывки (урон, смерть, события AI)

const HOST_PORT := 7010

var args: Dictionary = {}
var role: String = "host"
var tag: String = "host"
var out_dir: String = ""
var scenario: String = "walk"
var duration: float = 12.0

var _rows: PackedStringArray = []
var _stats: PackedStringArray = []
var _events: PackedStringArray = []
var _running: bool = false
var _stat_timer: float = 0.0
var _frame_times: Array[float] = []
var _rng := RandomNumberGenerator.new()
var _bot_dir: Vector2 = Vector2.ZERO
var _bot_timer: float = 0.0
var _bot_anchor: Vector2 = Vector2.ZERO
var _attack_timer: float = 0.0
var _last_frame_usec: int = 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	role = args.get("role", "host")
	tag = args.get("tag", role)
	out_dir = args.get("out", OS.get_user_data_dir().path_join("net_logs"))
	scenario = args.get("scenario", "walk")
	duration = float(args.get("duration", "12"))
	_rng.seed = hash(tag)

	# Узел должен пережить смену сцен (меню → игра → следующий этаж)
	if name != "NetHarness":
		var h := Node.new()
		h.set_script(get_script())
		h.name = "NetHarness"
		h.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child.call_deferred(h)
		return

	DirAccess.make_dir_recursive_absolute(out_dir)
	# Сравнительные замеры: align=0 — чужие действия без выравнивания по задержке показа тела
	NetworkManager.align_remote_actions = args.get("align", "1") != "0"
	# Медленная загрузка: этот клиент сообщает о готовности сцены с задержкой
	NetworkManager.debug_scene_ready_delay = float(args.get("ready_delay", "0"))
	NetworkManager.server_disconnected.connect(_on_session_ended)
	# Аварийный выход, если сценарий завис (не мешает нормальному завершению)
	get_tree().create_timer(float(args.get("timeout", "100"))).timeout.connect(func() -> void:
		log_event("TIMEOUT")
		_write_files()
		get_tree().quit(2))
	await get_tree().process_frame
	match role:
		"proxy": _run_proxy()
		"solo": _run_solo()
		"host": _run_host()
		_: _run_client()


## Системные часы в мс — общие для всех процессов на одной машине (сравнение позиций)
func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func log_event(text: String) -> void:
	var line := "%d,%s" % [now_ms(), text]
	_events.append(line)
	print("[HARNESS %s] %s" % [tag, text])


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


# ════════════════════════════════════════════════════════════════════════════
#  Роли
# ════════════════════════════════════════════════════════════════════════════

func _run_host() -> void:
	var need: int = int(args.get("players", "2"))
	GameManager.selected_class = int(args.get("class", "0")) as GameManager.PlayerClass
	var err := NetworkManager.host_game(args.get("name", "Host"), HOST_PORT)
	log_event("host_game err=%d" % err)
	var deadline := Time.get_ticks_msec() + 30000
	while NetworkManager.players.size() < need and Time.get_ticks_msec() < deadline:
		await wait(0.2)
	log_event("lobby players=%d" % NetworkManager.players.size())
	await wait(0.5)
	NetworkManager.start_game()
	await _wait_for_players(need)
	await _run_scenario()
	await _finish()


## Одиночная игра: регрессия после сетевых изменений (бой, урон в обе стороны, зачистка)
func _run_solo() -> void:
	GameManager.selected_class = int(args.get("class", "1")) as GameManager.PlayerClass
	GameManager.start_new_game()
	await _wait_for_players(1)
	var room := _nearest_room(Room.RoomType.FIGHT)
	var me := _my_player()
	me.teleport_to_position(room.global_position + Vector2(room.room_size) * 32.0)
	await wait(1.0)
	var enemies_start: int = get_tree().get_nodes_in_group("enemy").size()
	var hp_sum_start := 0
	for e in get_tree().get_nodes_in_group("enemy"): hp_sum_start += e.health_component.current_health
	var shots := 0
	for i in 12:
		var best: Node2D = null
		for e in get_tree().get_nodes_in_group("enemy"):
			if e.health_component.is_alive() and (best == null or e.global_position.distance_to(me.global_position) < best.global_position.distance_to(me.global_position)):
				best = e
		if best and me.health_component.is_alive():
			me.current_weapon.force_ready()
			me.current_weapon.attack((best.global_position - me.global_position).normalized(), best.global_position)
			shots += 1
		me.health_component.heal(5)
		await wait(0.35)
	var hp_sum_end := 0
	for e in get_tree().get_nodes_in_group("enemy"): hp_sum_end += e.health_component.current_health
	var took: int = me.health_component.max_health - me.health_component.current_health
	for e in get_tree().get_nodes_in_group("enemy"):
		e.get_node("Hurtbox").receive_damage(9999, 0.0, e.global_position, me, true)
	await wait(1.0)
	log_event("SOLO online=%s enemies=%d shots=%d enemy_hp %d->%d player_damaged=%s room=%s" % [NetworkManager.is_online(), enemies_start, shots, hp_sum_start, hp_sum_end, took > 0 or me.health_component.current_health < me.health_component.max_health, Room.RoomState.keys()[room.current_state]])
	await _finish()


func _run_client() -> void:
	await wait(float(args.get("delay", "1.0")))
	GameManager.selected_class = int(args.get("class", "2")) as GameManager.PlayerClass
	var port: int = int(args.get("port", str(HOST_PORT)))
	var err := NetworkManager.join_game(args.get("ip", "127.0.0.1"), args.get("name", tag), port)
	log_event("join err=%d port=%d" % [err, port])
	await NetworkManager.connection_succeeded
	log_event("connected id=%d" % multiplayer.get_unique_id())
	NetworkManager.set_my_class(GameManager.selected_class)
	_clock_sync_loop()
	if args.has("leave_on"):
		_watch_leave()
	await _wait_for_players(int(args.get("players", "2")))
	await _run_scenario()
	await _finish()


func _wait_for_players(need: int) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await wait(0.2)
		# если кто-то вышел во время ожидания — ждём оставшихся
		var n: int = mini(need, NetworkManager.players.size()) if NetworkManager.is_online() else need
		if get_tree().get_nodes_in_group("player").size() >= n and _my_player():
			break
	await wait(1.0)
	log_event("in_game floor=%d players=%d seed=%d" % [GameManager.current_floor,
		get_tree().get_nodes_in_group("player").size(), GameManager.dungeon_seed])


func _finish() -> void:
	_running = false
	_release_all()
	if role == "client":
		log_event("CLOCK_OFFSET %d rtt %d" % [_clock_offset, _clock_rtt])
	if "net_stats" in NetworkManager:
		log_event("NETSTATS %s" % JSON.stringify(NetworkManager.net_stats).replace(",", ";"))
	_write_files()
	log_event("DONE")
	await wait(0.5)
	get_tree().quit()


# ════════════════════════════════════════════════════════════════════════════
#  Сценарии
# ════════════════════════════════════════════════════════════════════════════

func _run_scenario() -> void:
	var me := _my_player()
	_bot_anchor = me.global_position if me else Vector2.ZERO
	_running = true
	log_event("scenario=%s start" % scenario)
	match scenario:
		"pull":
			await _scenario_pull()
		"combat":
			await _scenario_combat()
		"floors":
			await _scenario_floors()
		"integrity":
			await _scenario_integrity()
		"hostleave":
			await _scenario_host_leave()
		"showcase":
			await _scenario_showcase()
		"loot":
			await _scenario_loot()
		"roles":
			await _scenario_roles()
		_:
			await wait(duration)
	log_event("scenario=%s end" % scenario)


## Хост идёт в ближайшую боевую комнату; клиенты бродят у старта и должны быть подтянуты
func _scenario_pull() -> void:
	await wait(2.0)
	if role == "host":
		var room := _nearest_room(Room.RoomType.FIGHT)
		log_event("pull target=%s" % room.name)
		# Хост переносит СВОЕГО персонажа в комнату (он им владеет) — это запускает бой и подтягивание остальных
		_bot_anchor = room.global_position + Vector2(room.room_size) * 32.0
		_my_player().teleport_to_position(_bot_anchor + Vector2(0, 64))
		var deadline := Time.get_ticks_msec() + 15000
		while room.current_state == Room.RoomState.SLEEP and Time.get_ticks_msec() < deadline:
			await wait(0.1)
		log_event("pull room_state=%s" % Room.RoomState.keys()[room.current_state])
	await wait(duration)


## Все в боевой комнате: хост телепортирует группу, дальше боты атакуют ближайших врагов
func _scenario_combat() -> void:
	var room := _nearest_room(Room.RoomType.FIGHT)
	_bot_anchor = room.global_position + Vector2(room.room_size) * 32.0
	await wait(duration)


## Многократные переходы этажей: хост зачищает комнату босса и переносит всех в портал.
## Лог: этаж, число узлов и «сирот» (узлы вне дерева) — не должны расти от этажа к этажу.
func _scenario_floors() -> void:
	var transitions: int = int(args.get("floors", "3"))
	for n in transitions:
		var floor_before: int = GameManager.current_floor
		var transition_before: int = NetworkManager._transition_id
		var scene_before: Node = get_tree().current_scene
		await wait(2.0)
		log_event("FLOOR %d transition=%d nodes=%d orphans=%d players=%d" % [floor_before, transition_before,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			get_tree().get_nodes_in_group("player").size()])
		if role == "host":
			if floor_before >= GameManager.LAST_FLOOR:
				log_event("RESTART run (последний этаж)")
				GameManager.start_new_game() # как «Начать заново» у хоста
			else:
				var boss: Room = get_tree().current_scene._dungeon.get_boss_room()
				boss.set_room_state(Room.RoomState.CLEARED)
				await wait(0.8)
				var portal: Node2D = boss.get_node("Portal")
				for p in get_tree().get_nodes_in_group("player"):
					(p as Player).teleport_to_position(portal.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20)))
		var deadline := Time.get_ticks_msec() + 40000
		while NetworkManager._transition_id == transition_before and Time.get_ticks_msec() < deadline:
			await wait(0.2)
		if NetworkManager._transition_id == transition_before:
			log_event("FLOOR_STUCK %d" % floor_before)
			return
		# ждём именно новую сцену: номер перехода меняется ещё на старом этаже (подготовка)
		while get_tree().current_scene == scene_before and Time.get_ticks_msec() < deadline:
			await wait(0.1)
		# после ухода игрока ждём столько, сколько осталось в сессии
		await _wait_for_players(NetworkManager.players.size() if NetworkManager.is_online() else 1)
	log_event("FLOOR %d transitions_done=%d nodes=%d orphans=%d" % [GameManager.current_floor, transitions,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])

# ════════════════════════════════════════════════════════════════════════════
#  Награды в кооперативе: сундук, личные предметы, святилище, переход этажа
# ════════════════════════════════════════════════════════════════════════════

func _scenario_loot() -> void:
	_running = false # героев расставляет хост
	_release_all()
	var offers_got: Array = []
	Progression.offers_received.connect(func(key: String, offers: Array) -> void:
		offers_got.append([key, offers])
		log_event("OFFERS %s %d" % [key, offers.size()]))
	Progression.reward_granted.connect(func(peer_id: int, text: String) -> void:
		log_event("REWARD %d %s" % [peer_id, text.replace(",", ";")]))
	if role == "host":
		var chest_room := _nearest_room(Room.RoomType.CHEST)
		chest_room.set_room_state(Room.RoomState.CLEARED) # охрана «зачищена» — сундук появляется у всех
		await wait(0.6)
		var chest: Node2D = chest_room.get_node("RewardAltar")
		var players := get_tree().get_nodes_in_group("player")
		for i in players.size():
			(players[i] as Player).teleport_to_position(chest.global_position + Vector2(-30 + 20 * i, -20))
		await wait(1.2)
		var pickups := get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n.has_method("collect"))
		log_event("PICKUPS %d" % pickups.size())
		# Каждого героя — на чужой предмет (не подбирается), затем на свой
		for pickup in pickups:
			for p in players:
				if p.peer_id != pickup.owner_id:
					(p as Player).teleport_to_position(pickup.global_position)
		await wait(1.0)
		for pickup in pickups:
			if is_instance_valid(pickup):
				Progression._player_node(pickup.owner_id).teleport_to_position(pickup.global_position)
		await wait(1.5)
		var shrine: Node2D = _nearest_room(Room.RoomType.SHRINE).get_node("RewardAltar")
		for i in players.size():
			(players[i] as Player).teleport_to_position(shrine.global_position + Vector2(-30 + 20 * i, -20))
	var deadline := Time.get_ticks_msec() + 12000
	while offers_got.is_empty() and Time.get_ticks_msec() < deadline:
		await wait(0.2)
	var old_key := ""
	if not offers_got.is_empty():
		old_key = offers_got[0][0]
		var choice: int = Progression._peer_slot(multiplayer.get_unique_id()) % offers_got[0][1].size()
		Progression.choose_offer(old_key, choice)
		log_event("CHOSE %s %d" % [old_key, choice])
		await wait(1.0)
		Progression.choose_offer(old_key, 0) # повтор — хост должен отклонить
	await wait(2.0)
	_log_builds("before")
	var scene_before := get_tree().current_scene
	if role == "host":
		GameManager.next_floor()
	while get_tree().current_scene == scene_before and Time.get_ticks_msec() < deadline + 30000:
		await wait(0.2)
	await _wait_for_players(NetworkManager.players.size())
	if role != "host" and old_key != "":
		Progression._req_choose.rpc_id(1, old_key, 0) # выбор с прошлого этажа — отказ
	await wait(1.5)
	_log_builds("after")


## Новые роли по сети: босс (удар, плевки, деление), некромант (призыв), элитный враг.
## Хост ставит их рядом с героями; все процессы логируют, что видят (типы, элиту, приёмы).
func _scenario_roles() -> void:
	_running = false
	_release_all()
	var game := get_tree().current_scene
	var start_room: Room = game._dungeon.get_start_room()
	var center: Vector2 = start_room.global_position + Vector2(start_room.room_size) * 32.0
	if role == "host":
		game.spawn_network_enemy(load("res://scenes/enemies/slime_boss.tscn"), center + Vector2(0, -150))
		game.spawn_network_enemy(load("res://scenes/enemies/necromancer.tscn"), center + Vector2(250, 0))
		var skeleton := load("res://scenes/enemies/skeleton.tscn")
		game.spawn_network_enemy(skeleton, center + Vector2(-250, 0), EnemyScaling.compute(skeleton, 7, 2, true))
		for p in get_tree().get_nodes_in_group("player"):
			(p as Player).health_component.max_health = 100000
			(p as Player).health_component.set_health(100000)
	var patterns: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 14000
	while Time.get_ticks_msec() < deadline:
		await wait(0.1)
		for e in get_tree().get_nodes_in_group("enemy"):
			var ai := e.get_node_or_null("SlimeAI")
			if ai is BossAI and ai._pattern != "":
				patterns[ai._pattern] = true
	if role == "host":
		var boss: Node2D = null
		for e in get_tree().get_nodes_in_group("enemy"):
			if e.scene_file_path.contains("slime_boss"):
				boss = e
		if boss:
			boss.health_component.take_damage(int(boss.health_component.max_health * 0.5))
	await wait(1.5)
	var kinds: Dictionary = {}
	var elites := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.health_component.is_alive():
			var kind: String = e.scene_file_path.get_file().get_basename()
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			if e.has_meta("elite"):
				elites += 1
	log_event("ROLES patterns=%s enemies=%s elites=%d" % [";".join(patterns.keys()), JSON.stringify(kinds).replace(",", ";"), elites])


func _log_builds(stage: String) -> void:
	var ids: Array = Progression.builds.keys()
	ids.sort()
	var parts: Array[String] = []
	for id in ids:
		parts.append("%d:%s" % [id, JSON.stringify(Progression.builds[id])])
	log_event("BUILDS %s %s" % [stage, " | ".join(parts).replace(",", ";")])
	for node in get_tree().get_nodes_in_group("player"):
		var p := node as Player
		log_event("STATS %s peer=%d hp=%d/%d speed=%.1f cd=%.3f" % [stage, p.peer_id,
			p.health_component.current_health, p.health_component.max_health, p.speed, p.current_weapon.attack_cooldown])


# ════════════════════════════════════════════════════════════════════════════
#  Целостность боя: двойное/пропущенное применение, спам и повтор запросов, одна смерть
# ════════════════════════════════════════════════════════════════════════════

var _dummy: Node2D = null
var _died_count: int = 0

func _scenario_integrity() -> void:
	var attacks: int = int(args.get("attacks", "15"))
	var game := get_tree().current_scene
	_running = false # боты стоят там, куда их поставит хост
	_release_all()
	if role == "host":
		var start_room: Room = game._dungeon.get_start_room()
		var center: Vector2 = start_room.global_position + Vector2(start_room.room_size) * 32.0 + Vector2(0, -96)
		var dummy: Node2D = game.spawn_network_enemy(load("res://scenes/enemies/slime.tscn"), center)
		await wait(0.3)
		dummy.get_node("SlimeAI").set_physics_process(false) # манекен стоит и не атакует
		dummy.knockback_resistance = 100000.0
		dummy.health_component.max_health = 1000000
		dummy.health_component.set_health(1000000)
		# i-frames манекена выключены: иначе удары разных игроков в пределах 0.25 с
		# «теряются» по правилам игры, и отличить это от сетевой потери нельзя
		dummy.get_node("Hurtbox").invincibility_time = 0.0
		dummy.health_component.damage_taken.connect(func(amount: int, source: Node2D) -> void:
			log_event("HIT %d %d" % [_owner_peer(source), amount]))
		var players := get_tree().get_nodes_in_group("player")
		players.sort_custom(func(a, b): return a.peer_id < b.peer_id)
		for i in players.size():
			var p: Player = players[i]
			var melee: bool = p.player_class in [GameManager.PlayerClass.WARRIOR, GameManager.PlayerClass.PALADIN]
			var dir := Vector2.RIGHT.rotated(TAU * i / players.size())
			p.teleport_to_position(center + dir * (34.0 if melee else 160.0))
		log_event("DUMMY ready players=%d" % players.size())
	await wait(2.5)
	_dummy = null
	for e in get_tree().get_nodes_in_group("enemy"):
		_dummy = e
	if _dummy == null:
		log_event("NO_DUMMY")
		return
	_dummy.health_component.died.connect(func(_k) -> void: _died_count += 1)
	var me := _my_player()
	me.aim_override = _dummy.global_position # оружие смотрит на манекен, как при наведении мышью
	await wait(0.3)
	var sent := 0
	for k in attacks:
		await wait(me.current_weapon.attack_cooldown + 0.08)
		var aim: Vector2 = (_dummy.global_position - me.global_position).normalized()
		if me.try_attack(aim, _dummy.global_position):
			sent += 1
	log_event("INTEGRITY_SENT %d %d %d dist=%.0f" % [me.peer_id, me.player_class, sent, me.global_position.distance_to(_dummy.global_position)])
	var legit_seq: int = me._action_seq
	if role != "host":
		await wait(0.3) # оружие вернулось из анимации удара — точка атаки как у честного игрока
		# Спам в обход локального кулдауна + повтор последнего номера
		var aim: Vector2 = (_dummy.global_position - me.global_position).normalized()
		for k in 20:
			me._action_seq += 1
			me._net_request_attack.rpc_id(1, me._action_seq, aim, _dummy.global_position, me.current_weapon.global_position)
			await get_tree().physics_frame
		# Повтор уже принятого номера (после паузы, чтобы кулдаун не маскировал отказ)
		await wait(1.0)
		me._net_request_attack.rpc_id(1, legit_seq, aim, _dummy.global_position, me.current_weapon.global_position)
		log_event("SPAM_SENT %d 20 replay 1" % me.peer_id)
	await wait(8.0 if role == "host" else 3.0) # хост ждёт, пока все закончат серии
	if role == "host":
		_dummy.get_node("Hurtbox").receive_damage(2000000, 0.0, _dummy.global_position, null, true)
	# ждём смерти манекена (приходит от хоста), потом ещё немного — вдруг придёт повторная
	var deadline := Time.get_ticks_msec() + 15000
	while _died_count == 0 and Time.get_ticks_msec() < deadline:
		await wait(0.2)
	await wait(1.5)
	log_event("DIED_COUNT %d" % _died_count)


## Игрок-владелец источника урона (оружие/снаряд → персонаж)
func _owner_peer(source: Node) -> int:
	var n: Node = source
	while n:
		if n is Player:
			return (n as Player).peer_id
		n = n.get_parent()
	return -1


# ════════════════════════════════════════════════════════════════════════════
#  Разрывы: выход клиента во время перехода, выход хоста, медленная загрузка
# ════════════════════════════════════════════════════════════════════════════

## Клиент уходит на N-м переходе: leave_on=prepare — сразу после команды подготовки,
## leave_on=loading — когда начал грузить новый этаж (сцена ещё не готова)
func _watch_leave() -> void:
	var at: int = int(args.get("leave_at", "2"))
	var seen := 0
	var last_id: int = NetworkManager._transition_id
	var last_floor: int = GameManager.current_floor
	while true:
		await get_tree().process_frame
		var changed := false
		if args["leave_on"] == "prepare" and NetworkManager._transition_id != last_id:
			last_id = NetworkManager._transition_id
			changed = true
		elif args["leave_on"] == "loading" and GameManager.current_floor != last_floor:
			last_floor = GameManager.current_floor
			changed = true
		if changed:
			seen += 1
			if seen >= at + (1 if args["leave_on"] == "prepare" else 0):
				log_event("LEAVING on=%s transition=%d floor=%d" % [args["leave_on"], NetworkManager._transition_id, GameManager.current_floor])
				_running = false
				_write_files()
				NetworkManager.leave_game()
				await wait(1.0) # даём уйти уведомлению о выходе (NetworkManager закрывает через 0.3 с)
				get_tree().quit()
				return


## Витрина для скриншотов: хост входит в самую большую боевую комнату (остальных подтягивает),
## все сражаются (бой в _physics_process), хост снимает кадры в shots=t1,t2,... секунд → shot_dir.
func _scenario_showcase() -> void:
	if role == "host":
		var room: Room = null
		for r in get_tree().current_scene._dungeon.get_rooms():
			if r.room_type == Room.RoomType.FIGHT and (room == null or r.room_size.x * r.room_size.y > room.room_size.x * room.room_size.y):
				room = r
		var c: Vector2 = room.global_position + Vector2(room.room_size) * 32.0
		_my_player().teleport_to_position(c + Vector2(0, room.room_size.y * 32.0 * 0.4))
		var t0 := Time.get_ticks_msec()
		var i := 0
		for s in args.get("shots", "3").split(","):
			while Time.get_ticks_msec() - t0 < float(s) * 1000.0:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(args.get("shot_dir", out_dir).path_join("coop_%d.png" % i))
			log_event("SHOT coop_%d" % i)
			i += 1
	else:
		await wait(duration)


## Хост выходит в меню посреди игры (как «В ГЛАВНОЕ МЕНЮ»): клиенты должны получить причину
func _scenario_host_leave() -> void:
	await wait(duration)
	if role == "host":
		log_event("HOST_LEAVING")
		GameManager.go_to_menu()
		await wait(1.5)
	else:
		await wait(5.0) # клиенту должен прийти разрыв — см. _on_session_ended


func _on_session_ended() -> void:
	log_event("SESSION_END message=%s" % NetworkManager.session_end_message.replace(",", ";"))
	await wait(1.5)
	var scene := get_tree().current_scene
	log_event("SESSION_END scene=%s" % (scene.name if scene else "null"))
	_running = false
	_write_files()
	get_tree().quit()


# ════════════════════════════════════════════════════════════════════════════
#  Синхронизация часов (для игры на разных компьютерах): сдвиг часов клиента к часам хоста
#  по пингу с минимальным RTT. Анализатор прибавляет сдвиг ко всем временам клиента.
# ════════════════════════════════════════════════════════════════════════════

var _clock_offset: int = 0
var _clock_rtt: int = 1000000

func _clock_sync_loop() -> void:
	while NetworkManager.is_online():
		_clock_ping.rpc_id(1, now_ms())
		await wait(1.0)


@rpc("any_peer", "unreliable")
func _clock_ping(client_t: int) -> void:
	if multiplayer.is_server():
		_clock_pong.rpc_id(multiplayer.get_remote_sender_id(), client_t, now_ms())


@rpc("authority", "unreliable")
func _clock_pong(client_t: int, host_t: int) -> void:
	var t := now_ms()
	var rtt := t - client_t
	if rtt < _clock_rtt:
		_clock_rtt = rtt
		_clock_offset = host_t - (client_t + t) / 2


# ════════════════════════════════════════════════════════════════════════════
#  Журнал сетевых действий: отправка, приём хостом, показ у наблюдателей
# ════════════════════════════════════════════════════════════════════════════

func _hook_net_signals() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_meta("harness_hooked"):
			continue
		p.set_meta("harness_hooked", true)
		var pl := p as Player
		pl.action_sent.connect(func(kind: String, seq: int) -> void:
			log_event("SENT %s %d %d" % [kind, pl.peer_id, seq]))
		pl.remote_action_played.connect(func(kind: String, seq: int, offset: float) -> void:
			var delay: float = pl._interp.interp_delay_ms if (NetworkManager.align_remote_actions and not multiplayer.is_server()) else 0.0
			log_event("PLAYED %s %d %d %.1f %.1f" % [kind, pl.peer_id, seq, offset, delay]))
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.has_meta("harness_hooked"):
			continue
		e.set_meta("harness_hooked", true)
		for c in e.get_children():
			if c is SlimeAI:
				c.net_event_played.connect(func(state: int, offset: float) -> void:
					log_event("AIEV %d %.1f" % [state, offset]))


func _nearest_room(type: Room.RoomType) -> Room:
	var game := get_tree().current_scene
	var me := _my_player()
	var best: Room = null
	for r in game._dungeon.get_rooms():
		if r.room_type != type:
			continue
		var c: Vector2 = r.global_position + Vector2(r.room_size) * 32.0
		if best == null or c.distance_to(me.global_position) < (best.global_position + Vector2(best.room_size) * 32.0).distance_to(me.global_position):
			best = r
	return best


# ════════════════════════════════════════════════════════════════════════════
#  Бот: настоящий ввод через Input.action_press
# ════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if not _running:
		return
	var me := _my_player()
	if me == null or not me.health_component.is_alive():
		_release_all()
		return

	_bot_timer -= delta
	if me.global_position.distance_to(_bot_anchor) > 1200.0:
		_bot_anchor = me.global_position # новый этаж/телепорт — бродим вокруг новой точки
	var to_anchor: Vector2 = _bot_anchor - me.global_position
	if _bot_timer <= 0.0:
		_bot_timer = _rng.randf_range(0.4, 1.2)
		_bot_dir = Vector2.RIGHT.rotated(_rng.randi_range(0, 7) * PI / 4.0)
		if to_anchor.length() > 180.0:
			_bot_dir = to_anchor.normalized() # не уходим далеко от своей точки
	_apply_dir(_bot_dir)

	if scenario == "showcase":
		_showcase_fight(me)
		return
	if scenario == "combat":
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = _rng.randf_range(0.25, 0.6)
			Input.action_press("attack")
			if _rng.randf() < 0.15:
				Input.action_press("dash")
		else:
			Input.action_release("attack")
			Input.action_release("dash")


## Бот витрины: ближайший враг, ближний бой — вплотную, дальний — держит дистанцию
func _showcase_fight(me: Player) -> void:
	if role == "host":
		for p in get_tree().get_nodes_in_group("player"):
			p.health_component.heal(1000) # все живы до конца съёмки
	var target: Node2D = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.health_component.is_alive() and e.visible and (target == null or e.global_position.distance_to(me.global_position) < target.global_position.distance_to(me.global_position)):
			target = e
	if target == null:
		_apply_dir(Vector2.ZERO)
		return
	var to_t: Vector2 = target.global_position - me.global_position
	var melee: bool = me.player_class in [GameManager.PlayerClass.WARRIOR, GameManager.PlayerClass.PALADIN]
	var d := Vector2.ZERO
	if melee and to_t.length() > 40.0: d = to_t.normalized()
	elif not melee and to_t.length() < 170.0: d = -to_t.normalized()
	elif not melee and to_t.length() > 280.0: d = to_t.normalized()
	_apply_dir(d)
	me.aim_override = target.global_position
	me.try_attack(to_t.normalized(), target.global_position)


func _apply_dir(d: Vector2) -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	if d.x < -0.3: Input.action_press("move_left", minf(1.0, -d.x * 1.5))
	if d.x > 0.3: Input.action_press("move_right", minf(1.0, d.x * 1.5))
	if d.y < -0.3: Input.action_press("move_up", minf(1.0, -d.y * 1.5))
	if d.y > 0.3: Input.action_press("move_down", minf(1.0, d.y * 1.5))


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "attack", "dash"]:
		Input.action_release(a)


func _my_player() -> Player:
	for p in get_tree().get_nodes_in_group("player"):
		if p is Player and p.is_local():
			return p
	return null


# ════════════════════════════════════════════════════════════════════════════
#  Запись: позиции каждый кадр, статистика раз в секунду
# ════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if role == "proxy":
		_proxy_step()
		return
	if NetworkManager.is_online():
		_hook_net_signals()
	var now_usec := Time.get_ticks_usec()
	if _last_frame_usec > 0 and _running:
		_frame_times.append((now_usec - _last_frame_usec) / 1000.0)
	_last_frame_usec = now_usec
	if not _running:
		return

	var t := now_ms()
	for p in get_tree().get_nodes_in_group("player"):
		var pl := p as Player
		if pl == null:
			continue
		# t_ms, peer, local, x, y, hp, alive
		_rows.append("%d,%d,%d,%.2f,%.2f,%d,%d" % [t, pl.peer_id, int(pl.is_local()),
			pl.global_position.x, pl.global_position.y, pl.health_component.current_health,
			int(pl.health_component.is_alive())])

	_stat_timer += delta
	if _stat_timer >= 1.0:
		_stat_timer = 0.0
		_sample_stats()


func _sample_stats() -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return
	var rtt := -1.0
	var loss := -1.0
	if not multiplayer.is_server():
		var server := peer.get_peer(1)
		if server:
			rtt = server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			loss = server.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE)
	var host := peer.host
	var sent := host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var recv := host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var sent_p := host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var recv_p := host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
	var ft := _frame_times.duplicate()
	ft.sort()
	var p50: float = ft[ft.size() / 2] if not ft.is_empty() else 0.0
	var p99: float = ft[mini(ft.size() - 1, int(ft.size() * 0.99))] if not ft.is_empty() else 0.0
	var mx: float = ft.max() if not ft.is_empty() else 0.0
	_frame_times.clear()
	# t_ms, rtt_ms, loss, sent_bytes, recv_bytes, sent_pkts, recv_pkts, frame_p50, frame_p99, frame_max, enemies, fps
	_stats.append("%d,%.1f,%.4f,%d,%d,%d,%d,%.2f,%.2f,%.2f,%d,%d" % [now_ms(), rtt, loss,
		sent, recv, sent_p, recv_p, p50, p99, mx,
		get_tree().get_nodes_in_group("enemy").size(), Engine.get_frames_per_second()])


func _write_files() -> void:
	var f := FileAccess.open(out_dir.path_join(tag + ".csv"), FileAccess.WRITE)
	f.store_line("t_ms,peer,local,x,y,hp,alive")
	for r in _rows: f.store_line(r)
	f.close()
	f = FileAccess.open(out_dir.path_join(tag + "_stats.csv"), FileAccess.WRITE)
	f.store_line("t_ms,rtt_ms,loss,sent_bytes,recv_bytes,sent_pkts,recv_pkts,frame_p50,frame_p99,frame_max,enemies,fps")
	for r in _stats: f.store_line(r)
	f.close()
	f = FileAccess.open(out_dir.path_join(tag + "_events.csv"), FileAccess.WRITE)
	f.store_line("t_ms,event")
	for r in _events: f.store_line(r)
	f.close()


# ════════════════════════════════════════════════════════════════════════════
#  UDP-прокси: задержка, джиттер и потери между клиентами и хостом
# ════════════════════════════════════════════════════════════════════════════

var _proxy_server := UDPServer.new()
var _proxy_links: Array[Dictionary] = [] # {client: PacketPeerUDP, upstream: PacketPeerUDP}
var _proxy_queue: Array[Dictionary] = [] # {due_usec, peer: PacketPeerUDP, data}
var _latency_ms: float = 0.0
var _jitter_ms: float = 0.0
var _loss: float = 0.0
var _target_port: int = HOST_PORT


func _run_proxy() -> void:
	Engine.max_fps = 1000 # точность задержки ~1 мс
	var listen: int = int(args.get("listen", "7011"))
	_target_port = int(args.get("target", str(HOST_PORT)))
	# latency — задержка в одну сторону (RTT ≈ 2 × latency)
	_latency_ms = float(args.get("latency", "0"))
	_jitter_ms = float(args.get("jitter", "0"))
	_loss = float(args.get("loss", "0")) / 100.0
	_proxy_server.listen(listen, "127.0.0.1")
	log_event("proxy listen=%d target=%d latency=%.0f jitter=%.0f loss=%.1f%%" % [listen, _target_port, _latency_ms, _jitter_ms, _loss * 100])
	await wait(float(args.get("lifetime", "120")))
	get_tree().quit()


func _proxy_step() -> void:
	_proxy_server.poll()
	while _proxy_server.is_connection_available():
		var client := _proxy_server.take_connection()
		var upstream := PacketPeerUDP.new()
		upstream.connect_to_host("127.0.0.1", _target_port)
		_proxy_links.append({"client": client, "upstream": upstream})
	for link in _proxy_links:
		var client: PacketPeerUDP = link["client"]
		var upstream: PacketPeerUDP = link["upstream"]
		while client.get_available_packet_count() > 0:
			_proxy_enqueue(upstream, client.get_packet())
		while upstream.get_available_packet_count() > 0:
			_proxy_enqueue(client, upstream.get_packet())
	var now := Time.get_ticks_usec()
	var i := 0
	while i < _proxy_queue.size():
		var item: Dictionary = _proxy_queue[i]
		if item["due"] <= now:
			(item["peer"] as PacketPeerUDP).put_packet(item["data"])
			_proxy_queue.remove_at(i)
		else:
			i += 1


func _proxy_enqueue(peer: PacketPeerUDP, data: PackedByteArray) -> void:
	if _loss > 0.0 and _rng.randf() < _loss:
		return
	var delay := maxf(0.0, _latency_ms + _rng.randf_range(-_jitter_ms, _jitter_ms))
	_proxy_queue.append({"due": Time.get_ticks_usec() + int(delay * 1000.0), "peer": peer, "data": data})
