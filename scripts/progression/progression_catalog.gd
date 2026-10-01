extends RefCounted
class_name ProgressionCatalog
## Каталог прокачки забега: классовые навыки (по два направления на класс), общие улучшения,
## предметы и правила допустимости. Только данные и чистые функции — состояние хранит
## автозагрузка Progression. Паспорта и экономика — docs/progression_catalog.md.
##
## Билд игрока: {"skills": {skill_id: ранг}, "upgrades": {upgrade_id: стаки}}.
## Итоговые характеристики всегда пересчитываются из базовых значений класса и билда
## (Player.apply_build), поэтому повторное применение не умножает статы дважды.

## Значения GameManager.PlayerClass (константа должна быть известна при компиляции)
const W := 0 # WARRIOR
const R := 1 # RANGER
const M := 2 # MAGE
const P := 3 # PALADIN

## Классовые навыки. Два навыка класса — конкурирующие направления: первый ранг в одном
## закрывает другое до конца забега (так билды расходятся, а не сливаются в «всё сразу»).
## values[r] — параметр на ранге r (0 — навыка нет).
const SKILLS := {
	"cleave": {
		"class": W, "name": "Вихрь клинка", "item": "rune_blade", "max": 3,
		"summary": "Зачистка: шире удар, сильнее отбрасывание",
		"ranks": ["", "Радиус удара +20%", "Радиус удара +40%", "Радиус удара +40%, отбрасывание +50%"],
		"radius": [1.0, 1.2, 1.4, 1.4], "knockback": [1.0, 1.0, 1.0, 1.5],
	},
	"duelist": {
		"class": W, "name": "Выпад дуэлянта", "item": "duelist_mark", "max": 3,
		"summary": "Дуэль: удар сразу после рывка сильнее",
		"ranks": ["", "Удар в течение 0,8 с после рывка: +35% урона", "…: +60% урона", "…: +90% урона"],
		"bonus": [0.0, 0.35, 0.6, 0.9], "window": 0.8,
	},
	"ricochet": {
		"class": R, "name": "Рикошет", "item": "ricochet_tip", "max": 3,
		"summary": "Стрела пробивает врагов",
		"ranks": ["", "Пробивает 1 врага", "Пробивает 2 врагов", "Пробивает 3 врагов"],
		"pierce": [0, 1, 2, 3], "pierce_damage": 0.6,
	},
	"sniper": {
		"class": R, "name": "Меткий выстрел", "item": "eagle_eye", "max": 3,
		"summary": "Снайпер: первый выстрел по целому врагу",
		"ranks": ["", "+40% урона по врагу с полным здоровьем", "+70%", "+100%"],
		"bonus": [0.0, 0.4, 0.7, 1.0],
	},
	"blast": {
		"class": M, "name": "Огненный взрыв", "item": "volcano_heart", "max": 3,
		"summary": "Взрыв: шар задевает соседей",
		"ranks": ["", "Взрыв радиусом 48 px: 50% урона остальным", "Радиус 64 px", "Радиус 80 px"],
		"radius": [0.0, 48.0, 64.0, 80.0], "splash": 0.5,
	},
	"burn": {
		"class": M, "name": "Горение", "item": "fire_seal", "max": 3,
		"summary": "Горение: урон со временем",
		"ranks": ["", "Поджог на 3 с: 4 урона каждые 0,5 с", "6 урона", "8 урона"],
		"tick": [0, 4, 6, 8], "duration": 3.0, "interval": 0.5, "boss_factor": 0.5,
	},
	"bastion": {
		"class": P, "name": "Бастион", "item": "bastion_sigil", "max": 3,
		"summary": "Защита: меньше урона себе и союзникам рядом",
		"ranks": ["", "Входящий урон −8%, союзникам в 150 px −4%", "−12% / −6%", "−16% / −8%"],
		"reduction": [0.0, 0.08, 0.12, 0.16], "aura_radius": 150.0, "aura_share": 0.5,
	},
	"thunder": {
		"class": P, "name": "Громовая волна", "item": "thunder_sigil", "max": 3,
		"summary": "Волна: шире и сильнее священная волна",
		"ranks": ["", "Радиус и урон волны +25%", "+50%", "+75%"],
		"wave": [1.0, 1.25, 1.5, 1.75],
	},
}

## Общие улучшения: подходят всем классам, у каждого — предел стаков.
## Слотов (3 ранга навыка + 13 стаков) больше, чем гарантированных наград за забег (14):
## к финалу билды различаются тем, что игрок выбрал, а не заполняются целиком.
const UPGRADES := {
	"vitality": {"name": "Живучесть", "item": "vitality_stone", "max": 5,
		"desc": "Макс. здоровье +10% от базы класса (до +50%); прибавка сразу лечит", "hp": 0.10},
	"tempo": {"name": "Темп", "item": "tempo_charm", "max": 4,
		"desc": "Откат атаки ×0,94 (на пределе — 78% базового)", "cooldown": 0.94},
	"agility": {"name": "Проворство", "item": "agility_boots", "max": 4,
		"desc": "Скорость +5%, откат рывка −7% (до +20% / −28%)", "speed": 0.05, "dash": 0.07},
}

## Благословение — замена, когда допустимых улучшений не осталось: лечит, слот не занимает
const BLESSING := {"name": "Благословение", "desc": "Восстановить 50% макс. здоровья", "heal": 0.5}

## Предметы, найденные на уровне (сундук). Предмет навыка открывает навык на ранге 0
## и повышает его на ранг до предела.
const ITEMS := {
	"rune_blade": {"name": "Рунический клинок", "skill": "cleave"},
	"duelist_mark": {"name": "Метка дуэлянта", "skill": "duelist"},
	"ricochet_tip": {"name": "Наконечник рикошета", "skill": "ricochet"},
	"eagle_eye": {"name": "Орлиный глаз", "skill": "sniper"},
	"volcano_heart": {"name": "Сердце вулкана", "skill": "blast"},
	"fire_seal": {"name": "Огненная печать", "skill": "burn"},
	"bastion_sigil": {"name": "Символ бастиона", "skill": "bastion"},
	"thunder_sigil": {"name": "Печать грома", "skill": "thunder"},
	"vitality_stone": {"name": "Камень жизненной силы", "upgrade": "vitality"},
	"tempo_charm": {"name": "Оберег темпа", "upgrade": "tempo"},
	"agility_boots": {"name": "Сапоги проворства", "upgrade": "agility"},
	"health_potion": {"name": "Зелье здоровья", "consumable": "health_potion"},
	"speed_potion": {"name": "Зелье скорости", "consumable": "speed_potion"},
}

## Расходники: носятся в сумке (до max), применяются клавишей, тратятся только при пользе.
## Хранятся в билде ("items") и переживают смену этажа; новый забег их сбрасывает.
const CONSUMABLES := {
	"health_potion": {"name": "Зелье здоровья", "max": 2, "key": "Q",
		"desc": "Восстанавливает 35% макс. здоровья (не меньше 30). При полном здоровье не тратится",
		"heal": 0.35, "heal_min": 30},
	"speed_potion": {"name": "Зелье скорости", "max": 2, "key": "E",
		"desc": "+30% скорости на 6 с; повторное применение обновляет время, а не складывает эффект",
		"speed": 0.3, "duration": 6.0},
}
## Зачищенная боевая комната роняет общий расходник с этой вероятностью;
## выходная арена 1–6 — всегда зелье здоровья
const ROOM_DROP_CHANCE := 0.35
const HEALTH_POTION_SHARE := 0.65

## Доля наград сундука: предмет навыка своего направления либо общий предмет
const CHEST_SKILL_CHANCE := 0.6
## Сколько вариантов предлагает святилище
const SHRINE_OFFERS := 3


static func empty_build() -> Dictionary:
	return {"skills": {}, "upgrades": {}, "items": {}}


static func item_count(build: Dictionary, consumable_id: String) -> int:
	return int(build.get("items", {}).get(consumable_id, 0))


static func rank(build: Dictionary, skill_id: String) -> int:
	return int(build.get("skills", {}).get(skill_id, 0))


static func stacks(build: Dictionary, upgrade_id: String) -> int:
	return int(build.get("upgrades", {}).get(upgrade_id, 0))


## Навыки класса по порядку (стабильный порядок нужен для воспроизводимости)
static func class_skills(player_class: int) -> Array[String]:
	var result: Array[String] = []
	for id in SKILLS:
		if int(SKILLS[id]["class"]) == player_class:
			result.append(id)
	return result


## Выбранное направление класса ("" — ещё не выбрано)
static func branch(build: Dictionary, player_class: int) -> String:
	for id in class_skills(player_class):
		if rank(build, id) > 0:
			return id
	return ""


## Причина, по которой навык нельзя повысить ("" — можно)
static func skill_block_reason(build: Dictionary, player_class: int, skill_id: String) -> String:
	if not SKILLS.has(skill_id):
		return "unknown"
	var data: Dictionary = SKILLS[skill_id]
	if int(data["class"]) != player_class:
		return "class"
	var chosen := branch(build, player_class)
	if chosen != "" and chosen != skill_id:
		return "branch"
	if rank(build, skill_id) >= int(data["max"]):
		return "max"
	return ""


static func upgrade_block_reason(build: Dictionary, upgrade_id: String) -> String:
	if not UPGRADES.has(upgrade_id):
		return "unknown"
	if stacks(build, upgrade_id) >= int(UPGRADES[upgrade_id]["max"]):
		return "max"
	return ""


## Награда — {"kind": "skill"|"upgrade"|"blessing", "id": String}
static func reward_block_reason(build: Dictionary, player_class: int, reward: Dictionary) -> String:
	match reward.get("kind", ""):
		"skill": return skill_block_reason(build, player_class, reward.get("id", ""))
		"upgrade": return upgrade_block_reason(build, reward.get("id", ""))
		"blessing": return ""
	return "unknown"


## Все допустимые сейчас награды (без благословения), в стабильном порядке
static func legal_rewards(build: Dictionary, player_class: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in class_skills(player_class):
		if skill_block_reason(build, player_class, id) == "":
			result.append({"kind": "skill", "id": id})
	for id in UPGRADES:
		if upgrade_block_reason(build, id) == "":
			result.append({"kind": "upgrade", "id": id})
	return result


## Применить награду к копии билда. Недопустимая награда не меняет билд.
static func applied(build: Dictionary, player_class: int, reward: Dictionary) -> Dictionary:
	var result: Dictionary = build.duplicate(true)
	if reward_block_reason(build, player_class, reward) != "":
		return result
	match reward["kind"]:
		"skill":
			result["skills"][reward["id"]] = rank(build, reward["id"]) + 1
		"upgrade":
			result["upgrades"][reward["id"]] = stacks(build, reward["id"]) + 1
	return result


## Предмет → награда для конкретного героя. Предмет чужого класса, закрытого направления
## или на пределе не пропадает: превращается в допустимую награду (см. политику в документе).
static func item_reward(item_id: String, build: Dictionary, player_class: int, rng: RandomNumberGenerator) -> Dictionary:
	var item: Dictionary = ITEMS.get(item_id, {})
	var direct := {}
	if item.has("skill"):
		direct = {"kind": "skill", "id": item["skill"]}
	elif item.has("upgrade"):
		direct = {"kind": "upgrade", "id": item["upgrade"]}
	if not direct.is_empty() and reward_block_reason(build, player_class, direct) == "":
		return direct
	# Замена: сначала навык своего направления, затем любое допустимое улучшение
	var chosen := branch(build, player_class)
	if chosen != "" and skill_block_reason(build, player_class, chosen) == "":
		return {"kind": "skill", "id": chosen}
	var legal := legal_rewards(build, player_class)
	if legal.is_empty():
		return {"kind": "blessing", "id": "blessing"}
	return legal[rng.randi_range(0, legal.size() - 1)]


## Предмет сундука для героя: навык своего направления (или любого, пока не выбрано)
## с вероятностью CHEST_SKILL_CHANCE, иначе общий предмет. Только допустимые варианты.
static func roll_chest_item(build: Dictionary, player_class: int, rng: RandomNumberGenerator) -> String:
	var skill_items: Array[String] = []
	for id in class_skills(player_class):
		if skill_block_reason(build, player_class, id) == "":
			skill_items.append(SKILLS[id]["item"])
	var upgrade_items: Array[String] = []
	for id in UPGRADES:
		if upgrade_block_reason(build, id) == "":
			upgrade_items.append(UPGRADES[id]["item"])
	var roll := rng.randf()
	if not skill_items.is_empty() and (roll < CHEST_SKILL_CHANCE or upgrade_items.is_empty()):
		return skill_items[rng.randi_range(0, skill_items.size() - 1)]
	if not upgrade_items.is_empty():
		return upgrade_items[rng.randi_range(0, upgrade_items.size() - 1)]
	return "" # всё на пределе — сундук даст благословение


## Варианты святилища: до SHRINE_OFFERS разных допустимых наград; навык своего направления
## (или оба навыка, пока направление не выбрано) предлагается всегда, если он доступен.
## Меньше вариантов, чем нужно, — дополняется благословением, пустых карточек нет.
static func roll_offers(build: Dictionary, player_class: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var skills: Array[Dictionary] = []
	var upgrades: Array[Dictionary] = []
	for reward in legal_rewards(build, player_class):
		if reward["kind"] == "skill":
			skills.append(reward)
		else:
			upgrades.append(reward)
	var offers: Array[Dictionary] = []
	offers.append_array(skills)
	while offers.size() < SHRINE_OFFERS and not upgrades.is_empty():
		offers.append(upgrades.pop_at(rng.randi_range(0, upgrades.size() - 1)))
	if offers.size() < SHRINE_OFFERS:
		offers.append({"kind": "blessing", "id": "blessing"})
	return offers.slice(0, SHRINE_OFFERS)


## Название награды для интерфейса: «Вихрь клинка → II», «Живучесть 2/4»
static func reward_title(build: Dictionary, reward: Dictionary) -> String:
	match reward.get("kind", ""):
		"skill":
			var r := rank(build, reward["id"])
			return "%s: ранг %d → %d" % [SKILLS[reward["id"]]["name"], r, r + 1]
		"upgrade":
			var s := stacks(build, reward["id"])
			return "%s: %d → %d из %d" % [UPGRADES[reward["id"]]["name"], s, s + 1, UPGRADES[reward["id"]]["max"]]
		"blessing":
			return BLESSING["name"]
	return "?"


## Эффект следующего ранга/стака — для карточки выбора
static func reward_effect(build: Dictionary, reward: Dictionary) -> String:
	match reward.get("kind", ""):
		"skill":
			var data: Dictionary = SKILLS[reward["id"]]
			return "%s. %s" % [data["summary"], data["ranks"][rank(build, reward["id"]) + 1]]
		"upgrade":
			return UPGRADES[reward["id"]]["desc"]
		"blessing":
			return BLESSING["desc"]
	return ""


## Короткая строка билда для HUD: «Вихрь клинка II · Живучесть 2»
static func build_summary(build: Dictionary) -> String:
	var parts: Array[String] = []
	var numerals := ["", "I", "II", "III"]
	for id in SKILLS:
		var r := rank(build, id)
		if r > 0:
			parts.append("%s %s" % [SKILLS[id]["name"], numerals[mini(r, 3)]])
	for id in UPGRADES:
		var s := stacks(build, id)
		if s > 0:
			parts.append("%s %d" % [UPGRADES[id]["name"], s])
	var bag: Array[String] = []
	for id in CONSUMABLES:
		bag.append("[%s] %s ×%d" % [CONSUMABLES[id]["key"], CONSUMABLES[id]["name"], item_count(build, id)])
	var text := " · ".join(parts)
	return (text + "
" if text != "" else "") + "   ".join(bag)
