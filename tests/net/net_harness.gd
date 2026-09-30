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
	var err := NetworkManager.host_game("Host", HOST_PORT)
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
	var err := NetworkManager.join_game(args.get("ip", "127.0.0.1"), tag, port)
	log_event("join err=%d port=%d" % [err, port])
	await NetworkManager.connection_succeeded
	log_event("connected id=%d" % multiplayer.get_unique_id())
	NetworkManager.set_my_class(GameManager.selected_class)
	await _wait_for_players(int(args.get("players", "2")))
	await _run_scenario()
	await _finish()


func _wait_for_players(need: int) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await wait(0.2)
		if get_tree().get_nodes_in_group("player").size() >= need and _my_player():
			break
	await wait(1.0)
	log_event("in_game floor=%d players=%d seed=%d" % [GameManager.current_floor,
		get_tree().get_nodes_in_group("player").size(), GameManager.dungeon_seed])


func _finish() -> void:
	_running = false
	_release_all()
	if "net_stats" in NetworkManager:
		log_event("NETSTATS %s" % JSON.stringify(NetworkManager.net_stats))
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
		await _wait_for_players(int(args.get("players", "2")))
	log_event("FLOOR %d transitions_done=%d nodes=%d orphans=%d" % [GameManager.current_floor, transitions,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])

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
