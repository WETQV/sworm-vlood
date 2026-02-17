extends Area2D
class_name Hurtbox
## Hurtbox — зона получения урона
## Вешается НАПРЯМУЮ на Area2D
## Родитель (get_parent()) должен быть CharacterBody2D

signal damage_received(amount: int, knockback: Vector2)

@export var invincibility_time: float = 0.3

var _is_invincible: bool = false


## Получить урон — вызывается атакующей стороной
func receive_damage(amount: int, knockback_force: float, attacker_position: Vector2) -> void:
	if _is_invincible:
		return

	var entity = get_parent()

	# Наносим урон через HealthComponent
	var health = entity.get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.take_damage(amount)

	# Считаем направление отбрасывания
	var direction: Vector2 = (entity.global_position - attacker_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	# Отправляем сигнал — entity сам решит что делать
	damage_received.emit(amount, direction * knockback_force)

	# Неуязвимость
	_is_invincible = true

	# Мигание
	var tween = create_tween()
	tween.tween_property(entity, "modulate", Color(1, 0.3, 0.3), 0.05)
	tween.tween_property(entity, "modulate", Color.WHITE, 0.15)

	await get_tree().create_timer(invincibility_time).timeout
	_is_invincible = false
