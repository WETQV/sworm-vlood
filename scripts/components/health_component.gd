extends Node
class_name HealthComponent
## HealthComponent — инкапсулирует здоровье, урон, лечение и смерть сущности.
## В сетевой игре здоровье считает только хост и рассылает результат остальным.

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
	if not NetworkManager.is_authority():
		return # на клиентах урон приходит от хоста через _net_sync_health

	current_health = max(0, current_health - amount)
	damage_taken.emit(amount, source)
	health_changed.emit(current_health, max_health)
	_broadcast_health()

	if current_health <= 0:
		die(source)


## Исцелить
func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	if not NetworkManager.is_authority():
		return

	current_health = min(max_health, current_health + amount)
	healed.emit(amount)
	health_changed.emit(current_health, max_health)
	_broadcast_health()


## Установить HP напрямую
func set_health(value: int) -> void:
	if is_dead:
		return
	if not NetworkManager.is_authority():
		return

	current_health = clamp(value, 0, max_health)
	health_changed.emit(current_health, max_health)
	_broadcast_health()
	if current_health <= 0:
		die(null)


## Смерть персонажа
func die(source: Node2D = null) -> void:
	if is_dead:
		return

	is_dead = true
	died.emit(source)
	if NetworkManager.is_online() and multiplayer.is_server():
		_net_die.rpc()


## Проверка — жив ли персонаж
func is_alive() -> bool:
	return not is_dead


## Получить процент HP (0.0 - 1.0)
func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return float(current_health) / float(max_health)


# ── Сеть ─────────────────────────────────────────────────────────────────────

func _broadcast_health() -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		_net_sync_health.rpc(current_health, max_health)


# "any_peer": у персонажа клиента authority — сам клиент, поэтому проверяем отправителя вручную
@rpc("any_peer", "reliable")
func _net_sync_health(cur: int, mx: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_dead:
		return
	max_health = mx
	current_health = cur
	health_changed.emit(current_health, max_health)


@rpc("any_peer", "reliable")
func _net_die() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	current_health = 0
	health_changed.emit(current_health, max_health)
	die(null)
