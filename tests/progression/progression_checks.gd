extends Node
## Прокачка забега: правила каталога, пересчёт характеристик, эффекты навыков в бою,
## сундук/святилище и сохранение билда между этажами.
## godot --headless --fixed-fps 60 --path . res://tests/progression/progression_checks.tscn

const Catalog := preload("res://scripts/progression/progression_catalog.gd")
const SLIME := preload("res://scenes/enemies/slime.tscn")
const ARROW := preload("res://scenes/items/arrow.tscn")
const FIREBALL := preload("res://scenes/items/fireball.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")
const DT := 1.0 / 60.0

var failures := 0
var cases := 0
var _report: Array[String] = []
var _game: Node
var _player: Player


func _ready() -> void:
	if name != "ProgressionChecks":
		var runner := Node.new()
		runner.name = "ProgressionChecks"
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	_check_catalog()
	_check_economy()
	for player_class in [0, 1, 2, 3]:
		await _start(player_class, 2)
		_check_apply_build(player_class)
	await _check_skill_effects()
	await _check_rooms_and_floors()
	await _check_consumables()
	for line in _report:
		print(line)
	print("PROGRESSION_CHECKS: %d cases, %d failures" % [cases, failures])
	get_tree().current_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)


func _check(condition: bool, message: String) -> void:
	cases += 1
	if not condition:
		failures += 1
		push_error(message)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Этаж с героем выбранного класса (одиночная игра). Первый этаж сбрасывает забег.
func _start(player_class: int, floor_num: int, seed_value: int = 5150) -> void:
	GameManager.selected_class = player_class
	GameManager.start_floor(floor_num, seed_value)
	for i in 4:
		await get_tree().process_frame
	_game = get_tree().current_scene
	_player = _game._player
	_player.set_physics_process(false)


# ── Каталог: ранги, классы, направления, исчерпание ───────────────────────────

func _check_catalog() -> void:
	var rng := RandomNumberGenerator.new()
	for player_class in [0, 1, 2, 3]:
		var empty := Catalog.empty_build()
		var skills := Catalog.class_skills(player_class)
		_check(skills.size() == 2, "class %d must have two skill branches" % player_class)
		_check(Catalog.legal_rewards(empty, player_class).size() == 2 + Catalog.UPGRADES.size(), "rank 0: all class skills and upgrades legal")
		# Первый ранг направления закрывает второе
		var build := Catalog.applied(empty, player_class, {"kind": "skill", "id": skills[0]})
		_check(Catalog.rank(build, skills[0]) == 1, "skill rank 0 -> 1")
		_check(Catalog.skill_block_reason(build, player_class, skills[1]) == "branch", "second branch locked")
		var other_item: String = Catalog.SKILLS[skills[1]]["item"]
		var converted := Catalog.item_reward(other_item, build, player_class, rng)
		_check(converted == {"kind": "skill", "id": skills[0]}, "conflicting branch item converts to own branch rank")
		# Предмет чужого класса не пропадает
		var foreign: String = Catalog.SKILLS[Catalog.class_skills((player_class + 1) % 4)[0]]["item"]
		_check(Catalog.reward_block_reason(build, player_class, Catalog.item_reward(foreign, build, player_class, rng)) == "", "foreign item converts to legal reward")
		# Предел ранга и недопустимые применения
		for i in 5:
			build = Catalog.applied(build, player_class, {"kind": "skill", "id": skills[0]})
		_check(Catalog.rank(build, skills[0]) == 3, "rank capped at max")
		_check(Catalog.skill_block_reason(build, player_class, skills[0]) == "max", "max rank blocked")
		_check(Catalog.applied(build, player_class, {"kind": "skill", "id": skills[1]}) == build, "illegal reward does not change build")
		# Исчерпанный пул: всё на пределе — благословение, пустых вариантов нет
		for id in Catalog.UPGRADES:
			for i in int(Catalog.UPGRADES[id]["max"]) + 2:
				build = Catalog.applied(build, player_class, {"kind": "upgrade", "id": id})
			_check(Catalog.stacks(build, id) == int(Catalog.UPGRADES[id]["max"]), "upgrade stacks capped")
		_check(Catalog.legal_rewards(build, player_class).is_empty(), "pool exhausted")
		_check(Catalog.roll_chest_item(build, player_class, rng) == "", "exhausted chest gives no item")
		_check(Catalog.item_reward("rune_blade", build, player_class, rng)["kind"] == "blessing", "exhausted item -> blessing")
		var offers := Catalog.roll_offers(build, player_class, rng)
		_check(offers.size() == 1 and offers[0]["kind"] == "blessing", "exhausted shrine offers only blessing")
		# Варианты: три разных допустимых, навык направления всегда среди них
		for seed_value in 50:
			rng.seed = seed_value
			var partial := Catalog.applied(empty, player_class, {"kind": "skill", "id": skills[1]})
			var picks := Catalog.roll_offers(partial, player_class, rng)
			_check(picks.size() == Catalog.SHRINE_OFFERS, "three offers")
			_check(picks.has({"kind": "skill", "id": skills[1]}), "own branch skill offered")
			var unique: Dictionary = {}
			for reward in picks:
				unique[str(reward)] = true
				_check(Catalog.reward_block_reason(partial, player_class, reward) == "", "offer legal")
			_check(unique.size() == picks.size(), "offers unique")
			rng.seed = seed_value
			_check(Catalog.roll_offers(partial, player_class, rng) == picks, "offers reproducible")
			var item := Catalog.roll_chest_item(partial, player_class, rng)
			_check(item != "" and Catalog.reward_block_reason(partial, player_class, Catalog.item_reward(item, partial, player_class, rng)) == "", "chest item legal")


## Экономика: 2 гарантированные награды на этаж (сундук + святилище) × 7 этажей.
## В святилище игрок берёт навык направления (skill-first) или общее улучшение
## (upgrade-first: навык растёт только от сундуков).
func _check_economy() -> void:
	for player_class in [0, 1, 2, 3]:
		for style in ["skill-first", "upgrade-first"]:
			var main_rank_by_floor: Array = []
			var totals: Array = []
			for seed_value in 200:
				var rng := RandomNumberGenerator.new()
				rng.seed = seed_value * 31 + player_class
				var build := Catalog.empty_build()
				var ranks: Array = []
				for floor_num in range(1, 8):
					var item := Catalog.roll_chest_item(build, player_class, rng)
					build = Catalog.applied(build, player_class, Catalog.item_reward(item, build, player_class, rng))
					var offers := Catalog.roll_offers(build, player_class, rng)
					var choice: Dictionary = offers[0]
					if style == "upgrade-first":
						for reward in offers:
							if reward["kind"] == "upgrade":
								choice = reward
								break
					build = Catalog.applied(build, player_class, choice)
					var main := Catalog.branch(build, player_class)
					ranks.append(Catalog.rank(build, main) if main != "" else 0)
				main_rank_by_floor.append(ranks)
				var total := 0
				for id in Catalog.UPGRADES:
					total += Catalog.stacks(build, id)
				totals.append(total)
			var at4 := main_rank_by_floor.map(func(r: Array) -> int: return r[3])
			var at7 := main_rank_by_floor.map(func(r: Array) -> int: return r[6])
			if style == "skill-first":
				_check(at4.min() >= 3, "skill-first path: main skill maxed by floor 4 (class %d)" % player_class)
			_check(at7.min() >= 1, "every path unlocks a class skill by floor 7 (class %d, %s)" % [player_class, style])
			_report.append("economy class %d %-13s: skill rank at floor 4 min/avg/max %d/%.1f/%d, floor 7 %d/%.1f/%d, upgrade stacks at 7 avg %.1f" % [
				player_class, style, at4.min(), _avg(at4), at4.max(), at7.min(), _avg(at7), at7.max(), _avg(totals)])


func _avg(values: Array) -> float:
	var sum := 0.0
	for v in values:
		sum += v
	return sum / maxf(values.size(), 1)


# ── Пересчёт характеристик ───────────────────────────────────────────────────

func _check_apply_build(player_class: int) -> void:
	var base: Dictionary = GameManager.CLASS_DATA[player_class]["stats"]
	var build := {"skills": {}, "upgrades": {"vitality": 2, "tempo": 3, "agility": 1}}
	var skill: String = Catalog.class_skills(player_class)[0]
	build["skills"][skill] = 2
	var base_cooldown := _player._base_attack_cooldown
	for i in 2: # второй вызов не должен ничего умножать повторно
		_player.apply_build(build, true)
		var up: Dictionary = Catalog.UPGRADES
		_check(_player.health_component.max_health == int(round(base["hp"] * (1.0 + 2 * up["vitality"]["hp"]))), "vitality max hp (class %d)" % player_class)
		_check(_player.health_component.current_health == _player.health_component.max_health, "fresh hero at full hp")
		_check(is_equal_approx(_player.current_weapon.attack_cooldown, base_cooldown * pow(up["tempo"]["cooldown"], 3)), "tempo cooldown")
		_check(is_equal_approx(_player.speed, base["speed"] * (1.0 + up["agility"]["speed"])), "agility speed")
		_check(is_equal_approx(_player.dash_cooldown, 0.75 * (1.0 - up["agility"]["dash"])), "agility dash")
		_check(_player.attack_damage == int(base["damage"]), "base damage kept")
	match player_class:
		0:
			var shape := (_player.current_weapon as MeleeWeapon).hitbox.get_child(0).shape as CircleShape2D
			_check(is_equal_approx(shape.radius, 28.0 * 1.4), "cleave radius rank 2")
		1:
			_check((_player.current_weapon as RangedWeapon).projectile_mods["pierce"] == 2, "ricochet pierce rank 2")
		2:
			_check((_player.current_weapon as RangedWeapon).projectile_mods["blast_radius"] == 64.0, "blast radius rank 2")
		3:
			_check(is_equal_approx(_player.hurtbox.damage_reduction, Player.PALADIN_BASE_REDUCTION + 0.12), "bastion reduction rank 2")
			_check(is_equal_approx(_player.bastion_aura, 0.06), "bastion aura rank 2")
	# Получение живучести посреди этажа лечит на прибавку, а не до полного
	_player.apply_build(Catalog.empty_build(), true)
	_player.health_component.current_health = 10
	_player.apply_build({"skills": {}, "upgrades": {"vitality": 1}}, false, true)
	var gain := int(round(base["hp"] * (1.0 + Catalog.UPGRADES["vitality"]["hp"]))) - int(base["hp"])
	_check(_player.health_component.current_health == 10 + gain, "vitality gain heals the increase only")


# ── Эффекты навыков в бою (урон считается как на хосте) ──────────────────────

func _dummy(pos: Vector2, hp: int = 1000) -> Node2D:
	var enemy: Node2D = SLIME.instantiate()
	enemy.global_position = pos
	_game.add_child(enemy)
	for child in enemy.get_children():
		if child is SlimeAI:
			child.set_physics_process(false)
			child.process_mode = Node.PROCESS_MODE_DISABLED
	var health := enemy.get_node("HealthComponent") as HealthComponent
	health.max_health = hp
	health.current_health = hp
	return enemy


func _hp(enemy: Node2D) -> int:
	return (enemy.get_node("HealthComponent") as HealthComponent).current_health


func _shoot(scene: PackedScene, from: Vector2, dir: Vector2, damage: int, mods: Dictionary) -> void:
	var shot: Node2D = scene.instantiate()
	shot.direction = dir
	shot.damage = damage
	shot.mods = mods
	shot.attacker = _player
	shot.global_position = from
	_game.add_child(shot)


func _check_skill_effects() -> void:
	var origin := Vector2(90000, 90000) # вдали от карты: только наши цели
	# Рикошет: стрела ранга 2 проходит сквозь двух врагов и останавливается на третьем
	await _start(1, 2)
	var line: Array[Node2D] = []
	for i in 4:
		line.append(_dummy(origin + Vector2(80 + i * 60, 0)))
	await _frames(2)
	_shoot(ARROW, origin, Vector2.RIGHT, 20, {"pierce": 2, "pierce_damage": 0.6, "sniper": 0.0})
	await _frames(90)
	var losses := line.map(func(e: Node2D) -> int: return 1000 - _hp(e))
	_check(losses == [20, 12, 12, 0], "ricochet: 20, then 60%% x2, stops (got %s)" % [losses])
	# Меткий выстрел: +70% по целому врагу, обычный урон по раненому
	for e in line:
		e.queue_free()
	var fresh := _dummy(origin + Vector2(100, 200))
	var hurt := _dummy(origin + Vector2(100, 300))
	(hurt.get_node("HealthComponent") as HealthComponent).current_health = 900
	await _frames(2)
	_shoot(ARROW, origin + Vector2(0, 200), Vector2.RIGHT, 20, {"pierce": 0, "sniper": 0.7})
	_shoot(ARROW, origin + Vector2(0, 300), Vector2.RIGHT, 20, {"pierce": 0, "sniper": 0.7})
	await _frames(40)
	_check(1000 - _hp(fresh) == 34 and 900 - _hp(hurt) == 20, "sniper bonus only vs full hp (%d, %d)" % [1000 - _hp(fresh), 900 - _hp(hurt)])

	# Огненный взрыв и горение
	await _start(2, 2)
	var target := _dummy(origin + Vector2(120, 0))
	var near := _dummy(origin + Vector2(150, 40))
	var far := _dummy(origin + Vector2(120, 200))
	await _frames(2)
	_shoot(FIREBALL, origin, Vector2.RIGHT, 35, {"blast_radius": 64.0, "splash": 0.5, "burn_tick": 6,
		"burn_duration": 3.0, "burn_interval": 0.5, "boss_factor": 0.5})
	await _frames(30)
	var after_hit := 1000 - _hp(target)
	_check(after_hit >= 35 and 1000 - _hp(near) == 18 and _hp(far) == 1000, "blast: splash 50%% to neighbour only (%d/%d/%d)" % [after_hit, 1000 - _hp(near), 1000 - _hp(far)])
	await _frames(int(3.2 / DT))
	var burned := 1000 - _hp(target) - 35
	_check(burned == 36, "burn: 6 dmg x 6 ticks over 3 s (got %d)" % burned)
	# Повторный поджог обновляет длительность, но не складывает тики
	var before := _hp(target)
	var burn := target.get_node("Burn")
	burn.ignite(6, 1.0, 0.5, _player)
	burn.ignite(6, 1.0, 0.5, _player)
	await _frames(int(1.2 / DT))
	_check(before - _hp(target) == 12, "burn refresh does not stack (got %d)" % (before - _hp(target)))

	# Выпад дуэлянта: удар сразу после рывка сильнее, позже — обычный
	await _start(0, 2)
	_player.apply_build({"skills": {"duelist": 3}, "upgrades": {}}, true)
	_player.global_position = origin
	await _frames(2)
	var duel_shape := (_player.current_weapon as MeleeWeapon).hitbox.get_child(0) as CollisionShape2D
	var duel := _dummy(duel_shape.global_position + Vector2(20, 0))
	await _frames(3)
	_player._last_dash_start_msec = Time.get_ticks_msec()
	_player._prepare_attack_damage(false)
	var boosted := _player.current_weapon.damage
	_player._last_dash_start_msec = Time.get_ticks_msec() - 5000
	_player._prepare_attack_damage(false)
	_check(boosted == int(round(25 * 1.9)) and _player.current_weapon.damage == 25, "duelist +90%% only right after dash (%d/%d)" % [boosted, _player.current_weapon.damage])
	_player._last_dash_start_msec = Time.get_ticks_msec()
	_player.try_attack(Vector2.RIGHT, duel.global_position)
	await _frames(20)
	_check(1000 - _hp(duel) == 48, "duelist swing damage applied (got %d)" % (1000 - _hp(duel)))

	# Вихрь клинка: цель за краем обычного удара задевается только расширенным
	duel.queue_free()
	_player.apply_build(Catalog.empty_build(), true)
	await _frames(2)
	var swing_shape := (_player.current_weapon as MeleeWeapon).hitbox.get_child(0) as CollisionShape2D
	var edge := _dummy(swing_shape.global_position + Vector2(28.0 + 16.0 + 6.0, 0))
	await _frames(40)
	_player.try_attack(Vector2.RIGHT, edge.global_position)
	await _frames(40)
	var plain_loss := 1000 - _hp(edge)
	_player.apply_build({"skills": {"cleave": 3}, "upgrades": {}}, true)
	_player.try_attack(Vector2.RIGHT, edge.global_position)
	await _frames(20)
	_check(plain_loss == 0 and _hp(edge) < 1000, "cleave: only the wider swing reaches the edge target (%d, %d)" % [plain_loss, 1000 - _hp(edge)])

	# Бастион: союзник рядом с паладином получает меньше урона, далеко — обычный
	await _start(3, 2)
	_player.apply_build({"skills": {"bastion": 3}, "upgrades": {}}, true)
	_player.global_position = origin
	var ally: Player = PLAYER.instantiate()
	ally.player_class = 0
	ally.peer_id = 2
	_game.add_child(ally)
	ally.set_physics_process(false)
	ally.global_position = origin + Vector2(100, 0)
	await _frames(2)
	var ahc := ally.health_component
	ahc.current_health = ahc.max_health
	ally.hurtbox.receive_damage(100, 0.0, ally.global_position, null, true)
	var near_loss := ahc.max_health - ahc.current_health
	ally.global_position = origin + Vector2(400, 0)
	ahc.current_health = ahc.max_health
	ally.hurtbox.receive_damage(100, 0.0, ally.global_position, null, true)
	var far_loss := ahc.max_health - ahc.current_health
	_check(near_loss == 92 and far_loss == 100, "bastion aura -8%% near paladin only (%d/%d)" % [near_loss, far_loss])
	var phc := _player.health_component
	_player.hurtbox.receive_damage(100, 0.0, _player.global_position, null, true)
	var expected_loss := int(round(100 * (1.0 - Player.PALADIN_BASE_REDUCTION - 0.16)))
	_check(phc.max_health - phc.current_health == expected_loss, "paladin own reduction base + 16%% (got %d)" % (phc.max_health - phc.current_health))
	ally.queue_free()
	# Громовая волна: радиус волны растёт
	_player.apply_build({"skills": {"thunder": 3}, "upgrades": {}}, true)
	var hammer := _player.current_weapon as PaladinHammer
	_check(is_equal_approx(hammer.shockwave_radius, 46.0 * 1.75) and hammer.shockwave_damage == 39, "thunder wave radius/damage")


# ── Сундук, святилище, переход этажа, новый забег ────────────────────────────

func _room_of(type: int) -> Room:
	for room in _game._dungeon._rooms:
		if room.room_type == type:
			return room
	return null


func _check_rooms_and_floors() -> void:
	await _start(0, 1, 777)
	_check(Progression.builds.is_empty(), "floor 1 starts a clean run")
	# Сундук: после зачистки охраны появляется, открывается касанием, даёт личный предмет
	var chest_room := _room_of(Room.RoomType.CHEST)
	_check(chest_room != null and not chest_room.has_node("RewardAltar"), "chest hidden until guards cleared")
	chest_room.current_state = Room.RoomState.FIGHT
	chest_room._living_enemies.clear()
	chest_room.set_room_state(Room.RoomState.CLEARED)
	var chest: RewardAltar = chest_room.get_node_or_null("RewardAltar")
	_check(chest != null, "chest appears after clearing")
	_player.global_position = chest.global_position
	await _frames(4)
	var pickups := get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n.has_method("collect"))
	_check(pickups.size() == 1, "one personal item per living hero")
	_check(not Progression.open_chest(chest.source_key, chest.global_position), "chest opens once")
	var got: Array[String] = []
	Progression.reward_granted.connect(func(_p: int, text: String) -> void: got.append(text))
	_player.global_position = pickups[0].global_position
	await _frames(4)
	var build := Progression.get_build(1)
	_check(got.size() == 1 and (build["skills"].size() + build["upgrades"].size()) == 1, "item picked up once, build changed (%s)" % [got])
	_check(_game.get_node("HUD")._build_label.text != "", "HUD shows build")
	await _frames(20)
	_check(not is_instance_valid(pickups[0]), "pickup removed after collection")

	# Святилище: варианты своему герою, один выбор, повтор и чужой ключ отклоняются
	var shrine: RewardAltar = _room_of(Room.RoomType.SHRINE).get_node("RewardAltar")
	var offers_seen: Array = []
	Progression.offers_received.connect(func(key: String, offers: Array) -> void: offers_seen.append([key, offers]))
	_player.global_position = shrine.global_position
	await _frames(4)
	_check(offers_seen.size() == 1 and offers_seen[0][1].size() == 3, "shrine sends three offers once while touching")
	_player.global_position = shrine.global_position + Vector2(300, 0)
	await _frames(3)
	_player.global_position = shrine.global_position
	await _frames(3)
	_check(offers_seen.size() == 2 and offers_seen[1][1] == offers_seen[0][1], "re-touch shows the same offers (no reroll)")
	var key: String = offers_seen[0][0]
	var before := JSON.stringify(Progression.get_build(1))
	Progression.choose_offer(key, 1)
	var after := JSON.stringify(Progression.get_build(1))
	_check(before != after, "shrine choice applied")
	var rejected: int = NetworkManager.net_stats.get("offer_rejected", 0)
	Progression.choose_offer(key, 0)
	Progression.choose_offer("f1:Room_99#1", 0)
	_check(JSON.stringify(Progression.get_build(1)) == after and NetworkManager.net_stats.get("offer_rejected", 0) == rejected + 2, "repeat/foreign choice rejected")

	# Общий предмет (владелец ушёл): два героя касаются одновременно — выдача ровно одна
	var mate: Player = PLAYER.instantiate()
	mate.player_class = 1
	mate.peer_id = 2
	_game.get_node("PlayerContainer").add_child(mate)
	mate.set_physics_process(false)
	var spot := shrine.global_position + Vector2(0, 250)
	Progression._pickups["f1:shared#0"] = {"item": "vitality_stone", "owner": 0, "pos": spot}
	Progression._net_spawn_pickup("f1:shared#0", "vitality_stone", 0, spot)
	var granted_before := got.size()
	_player.global_position = spot
	mate.global_position = spot + Vector2(4, 0)
	await _frames(4)
	_check(got.size() == granted_before + 1, "simultaneous touch grants the shared item once (%d)" % (got.size() - granted_before))
	mate.queue_free()
	await _frames(1)

	# Переход: неподобранное не пропадает; билд сохраняется и применяется к новому герою
	var chest_key := "f1:test"
	Progression.open_chest(chest_key, Vector2(-5000, -5000))
	var total_before := _ranks(Progression.get_build(1))
	GameManager.next_floor()
	for i in 4:
		await get_tree().process_frame
	_game = get_tree().current_scene
	_player = _game._player
	_check(_ranks(Progression.get_build(1)) == total_before + 1, "unclaimed personal item granted on floor change")
	var saved := Progression.get_build(1)
	var expected_hp := int(round(GameManager.CLASS_DATA[0]["stats"]["hp"] * (1.0 + Catalog.UPGRADES["vitality"]["hp"] * Catalog.stacks(saved, "vitality"))))
	_check(GameManager.current_floor == 2 and _player.health_component.max_health == expected_hp, "build persists to next floor hero")
	# Новый забег сбрасывает билд
	GameManager.start_new_game()
	for i in 4:
		await get_tree().process_frame
	_check(Progression.builds.is_empty() and get_tree().current_scene._player.health_component.max_health == GameManager.CLASS_DATA[0]["stats"]["hp"], "new run resets build")


func _ranks(build: Dictionary) -> int:
	var total := 0
	for v in build["skills"].values():
		total += v
	for v in build["upgrades"].values():
		total += v
	return total


# ── Расходники: выпадение, сумка, применение, сохранение ─────────────────────

func _bag(id: String) -> int:
	return Catalog.item_count(Progression.get_build(1), id)


func _check_consumables() -> void:
	await _start(0, 1, 4242)
	# Выходная арена 1–6 всегда роняет зелье здоровья
	var boss_room := _room_of(Room.RoomType.BOSS)
	boss_room.current_state = Room.RoomState.FIGHT
	boss_room._living_enemies.clear()
	boss_room._pending_wave.clear()
	boss_room.set_room_state(Room.RoomState.CLEARED)
	var drops := get_tree().current_scene.get_children().filter(func(n: Node) -> bool:
		return n.has_method("collect") and n.item_id == "health_potion")
	_check(drops.size() == 1, "exit arena drops a health potion (%d)" % drops.size())
	_player.global_position = drops[0].global_position
	await _frames(4)
	_check(_bag("health_potion") == 1, "potion picked into the bag")
	# Предел сумки: третье зелье остаётся лежать
	for i in 2:
		var key := "f1:test_potion_%d" % i
		var spot := boss_room.global_position + Vector2(200 + i * 120, 200)
		Progression._pickups[key] = {"item": "health_potion", "owner": 0, "pos": spot}
		Progression._net_spawn_pickup(key, "health_potion", 0, spot)
		_player.global_position = spot
		await _frames(4)
	_check(_bag("health_potion") == 2 and Progression._pickups.has("f1:test_potion_1"), "bag cap 2: extra potion stays on the floor")
	# Отходим: иначе после выпитого зелья освободится место и лежащее подберётся (это верно)
	_player.global_position = boss_room.global_position + Vector2(100, 100)
	await _frames(2)
	# Полное здоровье — зелье не тратится; раненый лечится на 35% (не меньше 30)
	var hc := _player.health_component
	Progression.use_consumable("health_potion")
	_check(_bag("health_potion") == 2, "potion not wasted at full hp")
	hc.current_health = 20
	Progression.use_consumable("health_potion")
	_check(_bag("health_potion") == 1 and hc.current_health == 20 + maxi(30, int(ceil(hc.max_health * 0.35))), "health potion heals 35%% (hp %d)" % hc.current_health)
	# Зелье скорости: +30% и обновление времени без складывания
	var speed_key := "f1:test_speed"
	var speed_spot := boss_room.global_position + Vector2(200, 320)
	Progression._pickups[speed_key] = {"item": "speed_potion", "owner": 0, "pos": speed_spot}
	Progression._net_spawn_pickup(speed_key, "speed_potion", 0, speed_spot)
	_player.global_position = speed_spot
	await _frames(4)
	Progression.use_consumable("speed_potion")
	_check(is_equal_approx(_player.speed_boost_left, 6.0) and _bag("speed_potion") == 0, "speed potion 6 s")
	var rejected: int = NetworkManager.net_stats.get("consumable_rejected", 0)
	Progression.use_consumable("speed_potion")
	_check(NetworkManager.net_stats.get("consumable_rejected", 0) == rejected + 1, "empty bag use rejected")
	_player.set_physics_process(true)
	Input.action_press("move_right")
	await _frames(30)
	var boosted := _player.velocity.length()
	Input.action_release("move_right")
	_player.speed_boost_left = 0.0
	Input.action_press("move_right")
	await _frames(30)
	var normal := _player.velocity.length()
	Input.action_release("move_right")
	_player.set_physics_process(false)
	_check(is_equal_approx(boosted, normal * 1.3), "speed boost +30%% (%.0f vs %.0f)" % [boosted, normal])
	# Сумка переживает смену этажа и сбрасывается в новом забеге
	GameManager.next_floor()
	for i in 4:
		await get_tree().process_frame
	_check(_bag("health_potion") == 1, "potions persist to next floor (%s)" % [Progression.get_build(1)])
	GameManager.start_new_game()
	for i in 4:
		await get_tree().process_frame
	_check(_bag("health_potion") == 0, "new run empties the bag")
