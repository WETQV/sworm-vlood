extends Node
class_name HealthComponent
## HealthComponent — инкапсулирует здоровье, урон, лечение и смерть сущности.

signal health_changed(current_hp: int, max_hp: int)
signal damage_taken(amount: int, source: Node2D)
signal healed(amount: int)
signal died(killed_by: Node2D)

@export var max_health: int = 100
@export var current_health: int = 100

var is_dead: bool = false


func _ready() -> void:
	if current_health <= 0 or current_health > max_health:
		current_health = max_health


## Нанести урон
func take_damage(amount: int, source: Node2D = null) -> void:
	if is_dead or amount <= 0:
		return
	
	current_health = max(0, current_health - amount)
	damage_taken.emit(amount, source)
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		die(source)


## Исцелить
func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	
	current_health = min(max_health, current_health + amount)
	healed.emit(amount)
	health_changed.emit(current_health, max_health)


## Установить HP напрямую
func set_health(value: int) -> void:
	if is_dead:
		return
	
	current_health = clamp(value, 0, max_health)
	health_changed.emit(current_health, max_health)
	if current_health <= 0:
		die(null)


## Смерть персонажа
func die(source: Node2D = null) -> void:
	if is_dead:
		return
	
	is_dead = true
	died.emit(source)


## Проверка — жив ли персонаж
func is_alive() -> bool:
	return not is_dead


## Получить процент HP (0.0 - 1.0)
func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return float(current_health) / float(max_health)
