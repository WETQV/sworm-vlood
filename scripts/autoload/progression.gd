extends Node
## Progression — прокачка забега: билды игроков, предметы на уровне и выбор в святилище.
##
## Хост — единственный источник правды: он выдаёт награды, проверяет допустимость и рассылает
## итоговый билд всем (_net_build). Клиент никогда не присылает эффект или числа — только
## выбор варианта (ID набора вариантов + номер), который хост сверяет со своим предложением.
## Подбор предметов и активация сундука/святилища определяются на хосте по пересечению
## тел — отдельного запроса от клиента нет, поэтому повторный/старый запрос невозможен.
## Каталог и правила допустимости — ProgressionCatalog, паспорта — docs/progression_catalog.md.

signal build_changed(peer_id: int)
## Хост выдал награду: для всплывающего текста у всех игроков
signal reward_granted(peer_id: int, text: String)
## Своему игроку пришли варианты выбора (святилище/фолиант)
signal offers_received(offer_key: String, offers: Array)
signal offers_closed(offer_key: String)

const Catalog := preload("res://scripts/progression/progression_catalog.gd")
const PICKUP_SCRIPT := preload("res://scripts/progression/reward_pickup.gd")
## Версия данных каталога входит в seed наград: изменение каталога — другая последовательность
const DATA_VERSION := 1

## peer_id → билд. Есть у всех участников (хост рассылает каждое изменение).
var builds: Dictionary = {}
## Хост: нераспределённые личные предметы текущего этажа: key → {item, owner, pos}
var _pickups: Dictionary = {}
## Хост: выданные варианты выбора: offer_key → {peer, offers, done}
var _offers: Dictionary = {}
## Хост: какие сундуки уже открыты (ключ источника), какие святилища использовал игрок
var _opened_chests: Dictionary = {}
## Все: узлы предметов на уровне (для удаления по ключу)
var _pickup_nodes: Dictionary = {}
## Клиент: показанные своему игроку варианты
var local_offers: Dictionary = {}


## Начало этажа у всех участников: первый этаж — новый забег (сброс билдов),
## иначе очищается только состояние прошлого этажа (предметы, варианты выбора).
func begin_floor(floor_num: int) -> void:
	if floor_num <= 1:
		reset_run()
	else:
		_clear_floor_state()
		local_offers.clear()


## Новый забег: сброс всего
func reset_run() -> void:
	builds.clear()
	_clear_floor_state()
	local_offers.clear()


func _clear_floor_state() -> void:
	_pickups.clear()
	_offers.clear()
	_opened_chests.clear()
	_pickup_nodes.clear()


func get_build(peer_id: int) -> Dictionary:
	return builds.get(peer_id, Catalog.empty_build())


func _player_class(peer_id: int) -> int:
	if NetworkManager.is_online():
		return NetworkManager.get_player_class(peer_id)
	return GameManager.selected_class


func _player_node(peer_id: int) -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		if node is Player and node.peer_id == peer_id:
			return node
	return null


func _is_host() -> bool:
	return NetworkManager.is_authority()


## Участники забега в стабильном порядке (для воспроизводимого RNG наград)
func _peer_slot(peer_id: int) -> int:
	if not NetworkManager.is_online():
		return 0
	var ids: Array = NetworkManager.players.keys()
	ids.sort()
	return maxi(ids.find(peer_id), 0)


## Отдельный поток RNG наград: seed подземелья, этаж, источник, слот игрока, версия данных.
## Не зависит от RNG генерации карты и встреч.
func _reward_rng(source_key: String, peer_id: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([GameManager.dungeon_seed, GameManager.current_floor, source_key, _peer_slot(peer_id), DATA_VERSION])
	return rng


# ════════════════════════════════════════════════════════════════════════════
#  Выдача награды (только хост)
# ════════════════════════════════════════════════════════════════════════════

## Применить награду герою и разослать новый билд. Возвращает текст для игроков.
func grant(peer_id: int, reward: Dictionary, source_name: String = "") -> String:
	if not _is_host():
		return ""
	var build := get_build(peer_id)
	var player_class := _player_class(peer_id)
	if Catalog.reward_block_reason(build, player_class, reward) != "":
		reward = {"kind": "blessing", "id": "blessing"} # хост никогда не применяет недопустимое
	var title := Catalog.reward_title(build, reward)
	if reward["kind"] == "blessing":
		var player := _player_node(peer_id)
		if player and player.health_component.is_alive():
			var hc := player.health_component
			hc.heal(int(ceil(hc.max_health * Catalog.BLESSING["heal"])))
	else:
		_set_build(peer_id, Catalog.applied(build, player_class, reward), true)
	var text := "%s: %s" % [source_name, title] if source_name != "" else title
	if NetworkManager.is_online():
		_net_reward_text.rpc(peer_id, text)
	else:
		_net_reward_text(peer_id, text)
	return text


func _set_build(peer_id: int, build: Dictionary, gained: bool) -> void:
	if NetworkManager.is_online():
		_net_build.rpc(peer_id, build, gained)
	else:
		_net_build(peer_id, build, gained)


@rpc("authority", "call_local", "reliable")
func _net_build(peer_id: int, build: Dictionary, gained: bool) -> void:
	builds[peer_id] = build
	var player := _player_node(peer_id)
	if player:
		player.apply_build(build, false, gained)
	build_changed.emit(peer_id)


@rpc("authority", "call_local", "reliable")
func _net_reward_text(peer_id: int, text: String) -> void:
	reward_granted.emit(peer_id, text)


## «Бастион» паладина: снижение урона герою от ближайшего союзного паладина.
## Ауры не складываются — берётся сильнейшая (несколько паладинов не дают неуязвимость).
func ally_damage_reduction(target: Node2D) -> float:
	var best := 0.0
	var radius: float = Catalog.SKILLS["bastion"]["aura_radius"]
	for node in get_tree().get_nodes_in_group("player"):
		var paladin := node as Player
		if paladin == null or paladin == target or paladin.bastion_aura <= 0.0 \
				or not paladin.health_component.is_alive():
			continue
		if paladin.global_position.distance_to(target.global_position) <= radius:
			best = maxf(best, paladin.bastion_aura)
	return best


# ════════════════════════════════════════════════════════════════════════════
#  Сундук: личный предмет каждому живому участнику
# ════════════════════════════════════════════════════════════════════════════

## Хост: открыть сундук (однократно). Предмет каждому живому герою — свой, допустимый
## для его класса и направления; подобрать его может только владелец.
func open_chest(chest_key: String, center: Vector2) -> bool:
	if not _is_host() or _opened_chests.has(chest_key):
		return false
	_opened_chests[chest_key] = true
	var owners: Array[int] = []
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Player
		if player and player.health_component.is_alive():
			owners.append(player.peer_id)
	owners.sort()
	for i in owners.size():
		var peer_id := owners[i]
		var rng := _reward_rng(chest_key, peer_id)
		var item := Catalog.roll_chest_item(get_build(peer_id), _player_class(peer_id), rng)
		var angle := TAU * i / maxf(owners.size(), 1) - PI / 2.0
		var pos := center + Vector2.RIGHT.rotated(angle) * (0.0 if owners.size() == 1 else 72.0) + Vector2(0, 56)
		var key := "%s#%d" % [chest_key, peer_id]
		_pickups[key] = {"item": item, "owner": peer_id, "pos": pos}
		if NetworkManager.is_online():
			_net_spawn_pickup.rpc(key, item, peer_id, pos)
		else:
			_net_spawn_pickup(key, item, peer_id, pos)
	return true


@rpc("authority", "call_local", "reliable")
func _net_spawn_pickup(key: String, item: String, owner_id: int, pos: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null or _pickup_nodes.has(key):
		return
	var pickup: Area2D = PICKUP_SCRIPT.new()
	pickup.name = "Pickup_%s" % key.validate_node_name()
	pickup.setup(key, item, owner_id)
	pickup.global_position = pos
	scene.add_child(pickup)
	_pickup_nodes[key] = pickup


@rpc("authority", "call_local", "reliable")
func _net_remove_pickup(key: String) -> void:
	var node: Node = _pickup_nodes.get(key)
	_pickup_nodes.erase(key)
	if is_instance_valid(node):
		node.collect()


## Хост: герой коснулся предмета. Подбирает только владелец (или кто угодно, если владелец
## отключился); одновременные касания разрешает первый обработанный — второй уже не найдёт ключ.
func try_collect(key: String, player: Player) -> bool:
	if not _is_host() or not _pickups.has(key) or player == null or not player.health_component.is_alive():
		return false
	var entry: Dictionary = _pickups[key]
	var owner_id: int = entry["owner"]
	if owner_id != player.peer_id and _player_node(owner_id) != null:
		return false # чужой личный предмет
	_pickups.erase(key)
	var rng := _reward_rng(key, player.peer_id)
	var reward := Catalog.item_reward(entry["item"], get_build(player.peer_id), _player_class(player.peer_id), rng)
	var item_name: String = Catalog.ITEMS.get(entry["item"], {}).get("name", Catalog.BLESSING["name"])
	grant(player.peer_id, reward, item_name)
	if NetworkManager.is_online():
		_net_remove_pickup.rpc(key)
	else:
		_net_remove_pickup(key)
	return true


## Владелец отключился: его предмет становится общим (подберёт любой, с заменой под класс)
func on_peer_left(peer_id: int) -> void:
	if not _is_host():
		return
	for key in _pickups:
		if _pickups[key]["owner"] == peer_id:
			_pickups[key]["owner"] = 0
			if NetworkManager.is_online():
				_net_pickup_owner.rpc(key, 0)


@rpc("authority", "call_local", "reliable")
func _net_pickup_owner(key: String, owner_id: int) -> void:
	var node: Node = _pickup_nodes.get(key)
	if is_instance_valid(node):
		node.set_owner_id(owner_id)


# ════════════════════════════════════════════════════════════════════════════
#  Святилище: выбор одного из трёх вариантов (свой набор у каждого героя)
# ════════════════════════════════════════════════════════════════════════════

## Хост: герой коснулся святилища — показать ему его варианты (те же при повторном касании)
func request_offers(source_key: String, peer_id: int) -> void:
	if not _is_host():
		return
	var offer_key := "%s#%d" % [source_key, peer_id]
	if not _offers.has(offer_key):
		var rng := _reward_rng(source_key, peer_id)
		_offers[offer_key] = {"peer": peer_id, "done": false,
			"offers": Catalog.roll_offers(get_build(peer_id), _player_class(peer_id), rng)}
	var entry: Dictionary = _offers[offer_key]
	if entry["done"]:
		return
	_send_offers(peer_id, offer_key, entry["offers"])


func _send_offers(peer_id: int, offer_key: String, offers: Array) -> void:
	if NetworkManager.is_online() and peer_id != multiplayer.get_unique_id():
		_net_offers.rpc_id(peer_id, offer_key, offers)
	else:
		_net_offers(offer_key, offers)


@rpc("authority", "reliable")
func _net_offers(offer_key: String, offers: Array) -> void:
	local_offers[offer_key] = offers
	offers_received.emit(offer_key, offers)


## Игрок выбрал вариант (вызывает UI своего игрока)
func choose_offer(offer_key: String, index: int) -> void:
	if NetworkManager.is_online() and not multiplayer.is_server():
		_req_choose.rpc_id(1, offer_key, index)
	else:
		_apply_choice(1 if not NetworkManager.is_online() else multiplayer.get_unique_id(), offer_key, index)


@rpc("any_peer", "reliable")
func _req_choose(offer_key: String, index: int) -> void:
	if multiplayer.is_server():
		_apply_choice(multiplayer.get_remote_sender_id(), offer_key, index)


## Хост: вариант принадлежит отправителю, ещё не выбран, номер в пределах набора.
## Повтор, чужой ключ или ключ прошлого этажа (набор уже удалён) отклоняются.
func _apply_choice(sender: int, offer_key: String, index: int) -> void:
	var entry: Dictionary = _offers.get(offer_key, {})
	if entry.is_empty() or entry["peer"] != sender or entry["done"]:
		NetworkManager.count_stat("offer_rejected")
		return
	var offers: Array = entry["offers"]
	if index < 0 or index >= offers.size():
		NetworkManager.count_stat("offer_rejected")
		return
	var player := _player_node(sender)
	if player == null or not player.health_component.is_alive():
		NetworkManager.count_stat("offer_rejected")
		return
	entry["done"] = true
	grant(sender, offers[index], "Святилище")
	if NetworkManager.is_online() and sender != multiplayer.get_unique_id():
		_net_offers_closed.rpc_id(sender, offer_key)
	else:
		_net_offers_closed(offer_key)


@rpc("authority", "reliable")
func _net_offers_closed(offer_key: String) -> void:
	local_offers.erase(offer_key)
	offers_closed.emit(offer_key)


## Святилище уже использовано этим героем (хост)
func offer_done(source_key: String, peer_id: int) -> bool:
	return _offers.get("%s#%d" % [source_key, peer_id], {}).get("done", false)


# ════════════════════════════════════════════════════════════════════════════
#  Переход этажа: ничего не пропадает молча
# ════════════════════════════════════════════════════════════════════════════

## Хост перед сменой этажа: неподобранные личные предметы выдаются владельцам,
## незавершённый выбор — первым вариантом (навык направления идёт первым). Игроки видят
## сообщение. Затем состояние этажа очищается.
func settle_floor() -> void:
	if _is_host():
		for key in _pickups.keys():
			var entry: Dictionary = _pickups[key]
			var owner := _player_node(entry["owner"])
			if owner:
				var rng := _reward_rng(key, owner.peer_id)
				var reward := Catalog.item_reward(entry["item"], get_build(owner.peer_id), _player_class(owner.peer_id), rng)
				grant(owner.peer_id, reward, "%s (не подобран)" % Catalog.ITEMS.get(entry["item"], {}).get("name", ""))
		for offer_key in _offers:
			var entry: Dictionary = _offers[offer_key]
			if not entry["done"] and _player_node(entry["peer"]):
				entry["done"] = true
				grant(entry["peer"], entry["offers"][0], "Святилище (выбор не сделан)")
	_clear_floor_state()
