extends RefCounted
## Состав встречи определяется отдельным RNG, без влияния на граф подземелья.

const ENEMIES := {
	"slime": {"cost": 2, "floor": 1},
	"skeleton": {"cost": 3, "floor": 2},
	"bat": {"cost": 1, "floor": 3},
	"archer": {"cost": 4, "floor": 4},
	"necromancer": {"cost": 6, "floor": 5},
}
## Элитный «Страж этажа» выходной арены 1–6: надбавка к цене основы сценария
const ELITE_SURCHARGE := 3
## Выходная арена 1–6 идёт двумя волнами: доля состава в первой волне
const FIRST_WAVE_SHARE := 0.6
const PARTY_BUDGET := 3
const SCENARIOS := [
	{"id": "pursuit", "floor": 1, "core": ["slime", "slime"], "pool": ["slime", "skeleton"]},
	{"id": "swarm", "floor": 3, "core": ["skeleton", "bat", "bat"], "pool": ["skeleton", "bat", "slime"]},
	{"id": "crossfire", "floor": 4, "core": ["archer", "slime", "slime"], "pool": ["archer", "slime", "skeleton"]},
	# Некромант за спинами скелетов: прорваться к нему, пока не поднялись прислужники
	{"id": "ritual", "floor": 5, "core": ["necromancer", "skeleton", "skeleton"], "pool": ["skeleton", "slime", "bat"], "large_only": true},
]


static func build(seed_value: int, floor_num: int, players: int, large: bool,
		exit_arena: bool, slots: int, final_boss: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var floor_index := clampi(floor_num, 1, 7)
	var party := clampi(players, 1, 4)
	# Группа: +3 угрозы за каждого героя сверх первого (P1 TTK: +2 оставляло co-op слишком лёгким)
	var budget := 6 + (floor_index - 1) * 2 + (4 if large else 0) + (party - 1) * PARTY_BUDGET
	if exit_arena:
		budget += 4
	if final_boss:
		budget = 6 + (party - 1) * PARTY_BUDGET # Босс имеет отдельную стоимость: только ограниченная свита.
	var cap := mini(slots, (10 if large else 6) + mini(party - 1, 2))
	if final_boss:
		cap = mini(cap, 2 + party)
	var archer_cap := 2 if large and floor_index >= 5 else 1
	var bat_cap := 4 if large else 2
	# До трёх активных ближних угроз на игрока + ограниченная очередь подхода.
	# Это ограничение состава; фактические разрешения атак остаются у SwarmManager/AI.
	var melee_cap := mini(cap, party * 3 + (5 if large else 3))
	var available: Array = []
	for scenario in SCENARIOS:
		if floor_index >= scenario["floor"] and (large or not scenario.get("large_only", false)):
			available.append(scenario)
	var chosen: Dictionary = available[rng.randi_range(0, available.size() - 1)]
	var roster: Array[String] = []
	var spent := 0
	# Выходная арена 1–6: элитная версия основной роли сценария во второй волне
	var elite := ""
	if exit_arena and not final_boss:
		elite = chosen["core"][0]
		spent += ELITE_SURCHARGE
	# Сначала роль, определяющая сценарий; затем дополнение в оставшийся бюджет.
	for kind in chosen["core"]:
		if _allowed(kind, roster, floor_index, budget - spent, cap, archer_cap, bat_cap, melee_cap, large):
			roster.append(kind)
			spent += int(ENEMIES[kind]["cost"])
	if elite != "" and not roster.has(elite):
		elite = ""
		spent -= ELITE_SURCHARGE # основа не поместилась — элиты нет
	while roster.size() < cap:
		var candidates: Array[String] = []
		for kind in chosen["pool"]:
			if _allowed(kind, roster, floor_index, budget - spent, cap, archer_cap, bat_cap, melee_cap, large):
				candidates.append(kind)
		if candidates.is_empty():
			break
		var kind: String = candidates[rng.randi_range(0, candidates.size() - 1)]
		roster.append(kind)
		spent += int(ENEMIES[kind]["cost"])
	var plan := {"scenario": chosen["id"], "enemies": roster, "budget": budget, "spent": spent, "cap": cap,
		"elite": -1, "elite_cost": 0, "waves": [roster.size()]}
	if elite != "" and roster.size() >= 2:
		# Вторая волна: элита (основа сценария) и хвост состава
		var elite_index := roster.find(elite)
		roster.remove_at(elite_index)
		var first := clampi(int(ceil(roster.size() * FIRST_WAVE_SHARE)), 1, roster.size())
		roster.insert(first, elite)
		plan["elite"] = first
		plan["elite_cost"] = ELITE_SURCHARGE
		plan["waves"] = [first, roster.size() - first]
	elif elite != "":
		spent -= ELITE_SURCHARGE
		plan["spent"] = spent
	return plan


static func _allowed(kind: String, roster: Array[String], floor_num: int, remaining: int,
		cap: int, archer_cap: int, bat_cap: int, melee_cap: int, large: bool = false) -> bool:
	if roster.size() >= cap or int(ENEMIES[kind]["floor"]) > floor_num or int(ENEMIES[kind]["cost"]) > remaining:
		return false
	if kind == "archer":
		return roster.count(kind) < archer_cap
	if kind == "necromancer":
		return large and roster.count(kind) == 0 # один, и только в большой комнате
	if kind == "bat" and roster.count(kind) >= bat_cap:
		return false
	return roster.size() - roster.count("archer") - roster.count("necromancer") < melee_cap
