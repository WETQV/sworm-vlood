extends Node
class_name PlayerInfo

# ── Классы игрока ──
enum PlayerClass {
	WARRIOR,   # ближний бой, танковый
	RANGER,    # дальний бой, мобильный
	MAGE,      # дальний бой, стеклянный
	PALADIN    # ближний бой, поддержка
}

# ── Экспортируемые параметры ──
## Класс персонажа — задаётся внешне скриптом
@export var player_class: PlayerClass = PlayerClass.WARRIOR
## Ссылка на HealthComponent (для чтения текущего HP)
@export var health_component_path: NodePath = "../HealthComponent"

# ── Состояние способностей ──
## Активна ли сейчас какая-то опасная способность?
var is_ability_active: bool = false
## Центр опасной зоны (мировые координаты)
var ability_zone_center: Vector2 = Vector2.ZERO
## Радиус опасной зоны (0 = нет зоны)
var ability_zone_radius: float = 0.0
## Тип опасности: "melee_aoe", "ranged_aoe", "shield", "projectile"
var ability_type: String = ""

# ── Счётчик убийств (для оценки угрозы) ──
var recent_kills: int = 0
var _kill_timestamps: Array[float] = []
## Окно подсчёта (секунды)
@export var kill_window: float = 10.0

var _health: Node = null

func _ready() -> void:
	if has_node(health_component_path):
		_health = get_node(health_component_path)

func _process(_delta: float) -> void:
	_update_recent_kills()

# ─────────────────────────────────────────────
# ПУБЛИЧНЫЕ МЕТОДЫ (читает SwarmManager / SlimeAI)
# ─────────────────────────────────────────────

func is_melee() -> bool:
	return player_class in [PlayerClass.WARRIOR, PlayerClass.PALADIN]

func is_ranged() -> bool:
	return player_class in [PlayerClass.RANGER, PlayerClass.MAGE]

func get_hp_ratio() -> float:
	if _health and _health.has_method("get_health_percent"):
		return _health.get_health_percent()
	if _health and "current_health" in _health and "max_health" in _health:
		if _health.max_health > 0:
			return float(_health.current_health) / float(_health.max_health)
	return 1.0

func get_position() -> Vector2:
	return get_parent().global_position

func register_kill() -> void:
	_kill_timestamps.append(Time.get_ticks_msec() / 1000.0)

func _update_recent_kills() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_kill_timestamps = _kill_timestamps.filter(
		func(t): return now - t < kill_window
	)
	recent_kills = _kill_timestamps.size()

# ─────────────────────────────────────────────
# МЕТОДЫ ДЛЯ СКРИПТА ИГРОКА
# ─────────────────────────────────────────────

func activate_danger_zone(center: Vector2, radius: float, type: String = "melee_aoe") -> void:
	is_ability_active = true
	ability_zone_center = center
	ability_zone_radius = radius
	ability_type = type

func deactivate_danger_zone() -> void:
	is_ability_active = false
	ability_zone_radius = 0.0
	ability_type = ""
