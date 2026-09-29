extends Node2D
class_name BaseWeapon
## BaseWeapon — базовый класс для всех типов оружия в игре.

signal attacked
signal cooldown_finished

@export var weapon_name: String = "Weapon"
@export var damage: int = 25
@export var knockback_force: float = 200.0
@export var attack_cooldown: float = 0.4

var is_attacking: bool = false
var wielder: Node2D = null
var _cooldown_timer: Timer


func _ready() -> void:
	_setup_timer()


func _setup_timer() -> void:
	_cooldown_timer = Timer.new()
	_cooldown_timer.one_shot = true
	_cooldown_timer.wait_time = max(0.01, attack_cooldown)
	_cooldown_timer.timeout.connect(_on_cooldown_timeout)
	add_child(_cooldown_timer)


func can_attack() -> bool:
	return not is_attacking and _cooldown_timer.is_stopped()


## Сбросить кулдаун (для сетевых копий персонажа, повторяющих атаку владельца)
func force_ready() -> void:
	is_attacking = false
	if _cooldown_timer:
		_cooldown_timer.stop()


## Виртуальный метод: должен быть переопределен в дочерних классах
func attack(_aim_direction: Vector2, _target_position: Vector2) -> void:
	if not can_attack():
		return
	is_attacking = true
	attacked.emit()
	_cooldown_timer.start(attack_cooldown)


func _on_cooldown_timeout() -> void:
	is_attacking = false
	cooldown_finished.emit()
