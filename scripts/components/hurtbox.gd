extends Area2D
class_name Hurtbox
## Hurtbox — зона получения урона.
## Размещается дочерним узлом сущности (Player, Slime, Boss).

signal damage_received(amount: int, knockback: Vector2)
signal invincibility_started
signal invincibility_ended

@export var invincibility_time: float = 0.25
@export var damage_reduction: float = 0.0
@export var health_component: HealthComponent
@export var visual_target: CanvasItem

var _is_invincible: bool = false
var _invincibility_timer: Timer

var is_invincible: bool:
	get: return _is_invincible
	set(val):
		_is_invincible = val
		if val:
			invincibility_started.emit()
		else:
			invincibility_ended.emit()


func set_invincible_for(duration: float) -> void:
	_is_invincible = true
	_invincibility_timer.start(max(0.01, duration))
	invincibility_started.emit()


func _ready() -> void:
	# Настройка таймера неуязвимости
	_invincibility_timer = Timer.new()
	_invincibility_timer.one_shot = true
	_invincibility_timer.wait_time = max(0.01, invincibility_time)
	_invincibility_timer.timeout.connect(_on_invincibility_timeout)
	add_child(_invincibility_timer)

	# Автопоиск HealthComponent на родителе, если не назначен в инспекторе
	if not health_component:
		health_component = get_parent().get_node_or_null("HealthComponent") as HealthComponent

	# Автопоиск визуального узла для эффекта вспышки
	if not visual_target:
		var parent_node: Node = get_parent()
		if parent_node.has_node("Visuals/Body"):
			visual_target = parent_node.get_node("Visuals/Body") as CanvasItem
		elif parent_node.has_node("Visuals"):
			visual_target = parent_node.get_node("Visuals") as CanvasItem
		elif parent_node is CanvasItem:
			visual_target = parent_node as CanvasItem


## Дружественный огонь: союзник получает эту долю урона героя (P1 TTK: полный урон по своим
## убивал группы ботов уже на 1-м этаже — игроку тоже трудно не задевать союзников в толпе)
const FRIENDLY_FIRE_FACTOR := 0.5


## Получить урон (вызывается хитбоксом или атакующей стороной).
## start_iframes = false — периодический/вторичный урон (поджог, взрыв), не дающий цели
## неуязвимость: иначе он гасил бы прямые попадания в следующие 0,25 с.
func receive_damage(amount: int, knockback_force: float, attacker_position: Vector2, attacker: Node2D = null, ignore_invincibility: bool = false, start_iframes: bool = true) -> void:
	# В сети попадания считает только хост; клиенты получают результат через _net_hit_fx
	if not NetworkManager.is_authority():
		return
	if _is_invincible and not ignore_invincibility:
		return
	if health_component and not health_component.is_alive():
		return

	var entity: Node2D = get_parent() as Node2D
	if not entity:
		return
	if attacker and entity.is_in_group("player") and attacker.is_in_group("player"):
		if attacker == entity or not NetworkManager.friendly_fire:
			return

	# Наносим урон через HealthComponent с учетом снижения урона
	var final_amount: int = amount
	if attacker and attacker.is_in_group("player") and entity.is_in_group("player"):
		final_amount = maxi(1, int(round(amount * FRIENDLY_FIRE_FACTOR)))
	var reduction := damage_reduction
	if entity is Player:
		reduction = minf(0.6, reduction + Progression.ally_damage_reduction(entity))
	if reduction > 0.0:
		final_amount = max(1, int(round(float(final_amount) * (1.0 - reduction))))

	if health_component:
		health_component.take_damage(final_amount, attacker)

	# Направление отбрасывания от позиции атакующего
	var direction: Vector2 = (entity.global_position - attacker_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	damage_received.emit(final_amount, direction * knockback_force)
	_play_hit_fx()

	# Запуск i-frames
	if start_iframes:
		_start_invincibility()

	if NetworkManager.is_online():
		_net_hit_fx.rpc(final_amount, direction * knockback_force)


## Частицы попадания и вспышка (Hit Flash)
func _play_hit_fx() -> void:
	var entity: Node2D = get_parent() as Node2D
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_hit_particles") and entity:
		var part_color: Color = Color("44cc44") if entity.is_in_group("enemy") else Color("cc2233")
		vfx.spawn_hit_particles(global_position, part_color)
	_trigger_hit_flash()


## Хост сообщает клиентам о попадании: отбрасывание (для своего персонажа), звук и эффекты
@rpc("any_peer", "reliable")
func _net_hit_fx(amount: int, knockback: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	damage_received.emit(amount, knockback)
	_play_hit_fx()


func _start_invincibility() -> void:
	if invincibility_time <= 0.0:
		return
	_is_invincible = true
	_invincibility_timer.start(invincibility_time)
	invincibility_started.emit()


func _on_invincibility_timeout() -> void:
	_is_invincible = false
	invincibility_ended.emit()


func _trigger_hit_flash() -> void:
	if not visual_target:
		return

	# Если на материале есть instance uniform 'flash_modifier'
	visual_target.set_instance_shader_parameter("flash_modifier", 1.0)
	var tween: Tween = create_tween()
	tween.tween_method(
		func(val: float) -> void:
			if is_instance_valid(visual_target):
				visual_target.set_instance_shader_parameter("flash_modifier", val),
		1.0, 0.0, 0.12
	)
