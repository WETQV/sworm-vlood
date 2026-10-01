extends RefCounted
class_name EnemyScaling
## Скейлинг врагов — единственный источник кривых (docs/balance_reports/2026-10-01_p1_ttk.md).
##
## Порядок расчёта: база типа (сцена) × кривая этажа × поправка на группу × элита;
## округление один раз в конце. Параметры разделены: здоровье, урон, темп (замах и
## восстановление ИИ). У каждого — предел: телеграф не короче TEMPO_MIN от базового
## и не короче MIN_WINDUP секунд, чтобы атаку можно было прочитать.
##
## Применяется ДО добавления врага в дерево (до _ready) ровно один раз. Хост считает
## итоговые числа (compute) и передаёт их клиентам в данных сетевого спавнера — клиенты
## не пересчитывают их из своего состояния. Состав и численность встречи — отдельно
## (EncounterPlanner), элитный вид — scripts/enemies/elite.gd.

const ELITE := preload("res://scripts/enemies/elite.gd")

## Этаж 1 — базовые значения; рост за каждый следующий этаж
const HP_PER_FLOOR := 0.12
const DAMAGE_PER_FLOOR := 0.06
const TEMPO_PER_FLOOR := 0.03
## Пределы темпа: замах/восстановление не быстрее 80% базового и замах не короче 0,15 с
const TEMPO_MIN := 0.8
const MIN_WINDUP := 0.15
## Поправка на размер группы (индекс — число живых героев при старте встречи).
## Численность врагов уже растёт в бюджете встречи; здесь — только здоровье.
const PARTY_HP := [1.0, 1.0, 1.2, 1.4, 1.6]
## Финальный босс: своя кривая группы и множитель здоровья; этажные кривые здоровья, урона
## и темпа его не трогают (урон и телеграфы заданы в slime_boss.tscn / boss_ai.gd)
const BOSS_HP := 1.6
const BOSS_PARTY_HP := [1.0, 1.0, 1.5, 1.9, 2.3]

static var _base_cache: Dictionary = {}
## Только для замеров «до» (tests/balance scaling=0): кривые этажа и группы выключены
static var disabled: bool = false


static func _is_boss(path: String) -> bool:
	return path.contains("slime_boss")


## Базовые значения типа из сцены (кэшируются)
static func base_stats(scene: PackedScene) -> Dictionary:
	var path := scene.resource_path
	if not _base_cache.has(path):
		var probe: Node = scene.instantiate()
		var health := probe.get_node_or_null("HealthComponent") as HealthComponent
		var ai: Node = null
		for child in probe.get_children():
			if child is SlimeAI:
				ai = child
		_base_cache[path] = {
			"hp": health.max_health if health else 1,
			"damage": int(probe.get("contact_damage")) if "contact_damage" in probe else 0,
			"windup": ai.windup_time if ai else 0.0,
			"recover": ai.recover_time if ai else 0.0,
		}
		probe.free()
	return _base_cache[path]


static func floor_hp(floor_num: int) -> float:
	return 1.0 + HP_PER_FLOOR * (clampi(floor_num, 1, 7) - 1)


static func floor_damage(floor_num: int) -> float:
	return 1.0 + DAMAGE_PER_FLOOR * (clampi(floor_num, 1, 7) - 1)


static func floor_tempo(floor_num: int) -> float:
	return maxf(TEMPO_MIN, 1.0 - TEMPO_PER_FLOOR * (clampi(floor_num, 1, 7) - 1))


## Итоговые характеристики врага (хост). party — живые герои при старте встречи.
static func compute(scene: PackedScene, floor_num: int, party: int, elite: bool = false) -> Dictionary:
	var base := base_stats(scene)
	var size := clampi(party, 1, 4)
	var hp_mult: float
	if disabled:
		var flat := {"hp": base["hp"], "damage": base["damage"], "tempo": 1.0, "windup": base["windup"],
			"recover": base["recover"], "damage_mult": 1.0, "elite": elite}
		if elite:
			flat["hp"] = int(round(base["hp"] * ELITE.HP_FACTOR))
			flat["damage"] = int(round(base["damage"] * ELITE.DAMAGE_FACTOR))
			flat["damage_mult"] = ELITE.DAMAGE_FACTOR
		return flat
	if _is_boss(scene.resource_path):
		hp_mult = BOSS_HP * BOSS_PARTY_HP[size]
	else:
		hp_mult = floor_hp(floor_num) * PARTY_HP[size]
	var dmg_mult := floor_damage(floor_num)
	var tempo := floor_tempo(floor_num)
	if _is_boss(scene.resource_path):
		# Босс бывает только на 7-м этаже: урон и телеграфы настроены в его сцене/ИИ напрямую
		dmg_mult = 1.0
		tempo = 1.0
	if elite:
		hp_mult *= ELITE.HP_FACTOR
		dmg_mult *= ELITE.DAMAGE_FACTOR
	return {
		"hp": maxi(1, int(round(base["hp"] * hp_mult))),
		"damage": int(round(base["damage"] * dmg_mult)),
		"tempo": tempo,
		"windup": maxf(MIN_WINDUP, base["windup"] * tempo) if base["windup"] > 0.0 else 0.0,
		"recover": base["recover"] * tempo,
		"damage_mult": dmg_mult,
		"elite": elite,
	}


## Применить итоговые характеристики к экземпляру до _ready (у всех участников)
static func apply(enemy: Node, stats: Dictionary) -> void:
	if stats.is_empty():
		return
	enemy.set_meta("scaled", stats)
	var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.max_health = int(stats["hp"])
		health.current_health = health.max_health
	if "contact_damage" in enemy:
		enemy.contact_damage = int(stats["damage"])
	for child in enemy.get_children():
		if child is SlimeAI:
			if float(stats.get("windup", 0.0)) > 0.0:
				child.windup_time = float(stats["windup"])
			child.recover_time = float(stats["recover"])
			if child is BossAI:
				# Урон паттернов босса — по той же кривой урона
				child.slam_damage = int(round(child.slam_damage * float(stats["damage_mult"])))
				child.spit_damage = int(round(child.spit_damage * float(stats["damage_mult"])))
	if stats.get("elite", false):
		ELITE.apply_look(enemy)


## Создать врага с характеристиками этажа: в сети — через спавнер игры (числа уходят
## клиентам), в одиночной игре — в parent. global_pos — мировые координаты.
static func spawn(scene: PackedScene, global_pos: Vector2, parent: Node, floor_num: int, party: int, elite: bool = false) -> Node2D:
	var stats := compute(scene, floor_num, party, elite)
	var tree := parent.get_tree()
	var game := tree.current_scene if tree else null
	if NetworkManager.is_online() and game and game.has_method("spawn_network_enemy"):
		return game.spawn_network_enemy(scene, global_pos, stats)
	var enemy: Node2D = scene.instantiate()
	apply(enemy, stats)
	parent.add_child(enemy)
	enemy.global_position = global_pos
	return enemy


## Живые герои сейчас (для врагов, призванных посреди встречи)
static func alive_party(tree: SceneTree) -> int:
	var n := 0
	for node in tree.get_nodes_in_group("player"):
		var player := node as Player
		if player and player.health_component.is_alive():
			n += 1
	return maxi(n, 1)
