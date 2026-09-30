extends Node
## NetworkManager — сетевой кооператив по локальной сети (ENet, 2–4 игрока).
##
## Модель: хост-авторитет. Хост (peer 1) симулирует ИИ врагов, урон, комнаты и портал.
## Каждый клиент управляет только своим персонажем, а позицию шлёт через MultiplayerSynchronizer.
## Одиночная игра работает как раньше: is_online() == false, все проверки пропускаются.

signal players_changed
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal lobby_settings_changed
## Все игроки загрузили игровую сцену (только на хосте)
signal all_players_in_game

const DEFAULT_PORT := 7000
const MAX_PLAYERS := 4
## Пауза между подтверждением остановки снимков и сменой этажа, сек (≥ джиттер сети)
const FLOOR_CHANGE_GRACE := 0.25

## peer_id -> { "name": String, "class": int }
var players: Dictionary = {}
var friendly_fire: bool = false

var _players_in_game: Array[int] = []
var _floor_change_pending: bool = false
var _floor_prepare_acks: Array[int] = []
## Номер перехода между этажами: подтверждения/готовность со старым номером игнорируются
var _transition_id: int = 0
## Счётчики сетевых событий (принятые/отклонённые запросы, отброшенные снимки) — для замеров
var net_stats: Dictionary = {}


func count_stat(key: String, amount: int = 1) -> void:
	net_stats[key] = net_stats.get(key, 0) + amount


## Идёт смена этажа — боевые запросы не принимаются
func is_transitioning() -> bool:
	return _floor_change_pending


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ════════════════════════════════════════════════════════════════════════════
#  Состояние
# ════════════════════════════════════════════════════════════════════════════

## Идёт ли сетевая игра
func is_online() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Этот экземпляр игры принимает решения (хост или одиночная игра)
func is_authority() -> bool:
	return not is_online() or multiplayer.is_server()


func get_my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func get_player_class(peer_id: int) -> int:
	if players.has(peer_id):
		return players[peer_id]["class"]
	return GameManager.selected_class


## Локальные IPv4-адреса — хост сообщает их друзьям для подключения
func get_local_ips() -> Array[String]:
	var result: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			result.append(ip)
	return result


# ════════════════════════════════════════════════════════════════════════════
#  Хост / подключение / выход
# ════════════════════════════════════════════════════════════════════════════

func host_game(player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave_game()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	net_stats.clear()
	players[1] = {"name": player_name, "class": int(GameManager.selected_class)}
	GameManager.is_multiplayer = true
	players_changed.emit()
	return OK


func join_game(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave_game()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	net_stats.clear()
	GameManager.is_multiplayer = true
	_pending_name = player_name
	return OK


func leave_game() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_players_in_game.clear()
	_floor_prepare_acks.clear()
	_floor_change_pending = false
	friendly_fire = false
	GameManager.is_multiplayer = false


# ════════════════════════════════════════════════════════════════════════════
#  Лобби
# ════════════════════════════════════════════════════════════════════════════

var _pending_name: String = "Player"


## Сменить класс своего персонажа в лобби
func set_my_class(player_class: int) -> void:
	GameManager.selected_class = player_class as GameManager.PlayerClass
	if not is_online():
		return
	if multiplayer.is_server():
		_set_class(1, player_class)
	else:
		_request_class.rpc_id(1, player_class)


@rpc("any_peer", "reliable")
func _request_class(player_class: int) -> void:
	if multiplayer.is_server():
		_set_class(multiplayer.get_remote_sender_id(), player_class)


func _set_class(peer_id: int, player_class: int) -> void:
	if players.has(peer_id):
		players[peer_id]["class"] = clampi(player_class, 0, 3)
		_sync_players.rpc(players)
		players_changed.emit()


@rpc("any_peer", "reliable")
func _register_player(player_name: String, player_class: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"name": player_name.left(16), "class": clampi(player_class, 0, 3)}
	_sync_players.rpc(players)
	_sync_friendly_fire.rpc_id(id, friendly_fire)
	players_changed.emit()


## Менять правила забега может только хост.
func set_friendly_fire(enabled: bool) -> void:
	if not is_online() or not multiplayer.is_server():
		return
	friendly_fire = enabled
	_sync_friendly_fire.rpc(enabled)
	lobby_settings_changed.emit()


@rpc("authority", "reliable")
func _sync_friendly_fire(enabled: bool) -> void:
	friendly_fire = enabled
	lobby_settings_changed.emit()


@rpc("authority", "reliable")
func _sync_players(data: Dictionary) -> void:
	players = data
	players_changed.emit()


## Хост запускает забег для всех
func start_game() -> void:
	if not multiplayer.is_server():
		return
	# Новых игроков после старта не принимаем
	(multiplayer.multiplayer_peer as ENetMultiplayerPeer).refuse_new_connections = true
	_change_floor(1)


## Хост запускает следующий этаж (из портала)
func start_next_floor() -> void:
	_change_floor(GameManager.current_floor + 1)


## Общий путь смены этажа (следующий этаж или перезапуск забега).
## Если игра уже идёт — сначала клиенты прекращают слать снимки и подтверждают (ACK),
## иначе их снимки приходят к уже удалённым персонажам. Из лобби этот шаг не нужен.
func _change_floor(floor_num: int) -> void:
	if not multiplayer.is_server() or _floor_change_pending:
		return
	var game := get_tree().current_scene
	if not (game and game.has_method("clear_network_entities")):
		_transition_id += 1
		_start_floor.rpc(floor_num, randi_range(1, 2147483647), _transition_id)
		return
	_floor_change_pending = true
	_floor_prepare_acks.clear()
	_transition_id += 1
	_prepare_next_floor.rpc(_transition_id)
	var deadline := Time.get_ticks_msec() + 10000
	while not _all_clients_prepared() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not multiplayer.is_server() or not _floor_change_pending:
		return
	if not _all_clients_prepared():
		count_stat("floor_prepare_timeout")
	# Ненадёжные снимки не упорядочены относительно надёжного ACK: даём «долететь» тем,
	# что уже в пути (в т.ч. пересылаемым хостом другим клиентам), прежде чем удалять персонажей
	await get_tree().create_timer(FLOOR_CHANGE_GRACE).timeout
	if not multiplayer.is_server() or not _floor_change_pending:
		return
	_clear_current_game()
	_start_floor.rpc(floor_num, randi_range(1, 2147483647), _transition_id)
	_floor_change_pending = false


@rpc("authority", "reliable")
func _prepare_next_floor(transition_id: int) -> void:
	_transition_id = transition_id
	var game := get_tree().current_scene
	if game and game.has_method("stop_local_synchronization"):
		game.stop_local_synchronization()
	await get_tree().process_frame
	_next_floor_prepared.rpc_id(1, transition_id)


@rpc("any_peer", "reliable")
func _next_floor_prepared(transition_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if transition_id != _transition_id:
		count_stat("stale_floor_ack")
		return # подтверждение от прошлого перехода
	if multiplayer.is_server() and _floor_change_pending and players.has(sender) \
			and not _floor_prepare_acks.has(sender):
		_floor_prepare_acks.append(sender)


func _all_clients_prepared() -> bool:
	for id in players:
		if id != 1 and not _floor_prepare_acks.has(id):
			return false
	return true


## Хост убирает сетевых персонажей/врагов ДО команды на смену сцены —
## иначе сообщения об их удалении приходят клиентам, когда те уже на новом уровне.
func _clear_current_game() -> void:
	var game := get_tree().current_scene
	if game and game.has_method("clear_network_entities"):
		game.clear_network_entities()


@rpc("authority", "call_local", "reliable")
func _start_floor(floor_num: int, dungeon_seed: int, transition_id: int) -> void:
	_transition_id = transition_id
	_players_in_game.clear()
	GameManager.start_floor(floor_num, dungeon_seed)


# ════════════════════════════════════════════════════════════════════════════
#  Готовность игровой сцены (хост ждёт всех перед спавном игроков)
# ════════════════════════════════════════════════════════════════════════════

## Вызывается игровой сценой, когда она загрузилась и подземелье построено
func notify_game_scene_ready() -> void:
	if multiplayer.is_server():
		_mark_in_game(1)
	else:
		_client_in_game.rpc_id(1, _transition_id)


@rpc("any_peer", "reliable")
func _client_in_game(transition_id: int) -> void:
	if not multiplayer.is_server():
		return
	if transition_id != _transition_id:
		count_stat("stale_scene_ready")
		return # готовность к прошлому этажу
	_mark_in_game(multiplayer.get_remote_sender_id())


## Хост: сколько игроков уже загрузили сцену текущего этажа
func get_players_in_game() -> Array[int]:
	return _players_in_game.duplicate()


## Хост: отключить игроков, которые не загрузились за отведённое время (явный результат вместо вечного ожидания)
func drop_players_not_in_game() -> void:
	if not multiplayer.is_server():
		return
	for id in players.keys():
		if id != 1 and not _players_in_game.has(id):
			count_stat("dropped_slow_loader")
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)


func _mark_in_game(peer_id: int) -> void:
	if not _players_in_game.has(peer_id):
		_players_in_game.append(peer_id)
	if _all_in_game():
		all_players_in_game.emit()


func _all_in_game() -> bool:
	for id in players.keys():
		if not _players_in_game.has(id):
			return false
	return true


# ════════════════════════════════════════════════════════════════════════════
#  Сигналы сети
# ════════════════════════════════════════════════════════════════════════════

func _on_peer_connected(_id: int) -> void:
	pass # клиент сам присылает _register_player


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	_players_in_game.erase(id)
	_sync_players.rpc(players)
	players_changed.emit()
	# Убираем персонажа ушедшего игрока из текущей игры
	var game := get_tree().current_scene
	if game and game.has_method("remove_network_player"):
		game.remove_network_player(id)
	# Если ждали только его — продолжаем
	if not _players_in_game.is_empty() and _all_in_game():
		all_players_in_game.emit()


func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, _pending_name, int(GameManager.selected_class))
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	leave_game()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave_game()
	server_disconnected.emit()
	GameManager.go_to_menu()
