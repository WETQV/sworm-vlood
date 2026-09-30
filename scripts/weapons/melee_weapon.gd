extends BaseWeapon
class_name MeleeWeapon
## MeleeWeapon — оружие ближнего боя (меч, щит паладина).

@export var hitbox: HitboxComponent
@export var attack_duration: float = 0.12
@export var swing_distance: float = 24.0

var _initial_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	_initial_pos = position
	if not hitbox:
		hitbox = get_node_or_null("HitboxComponent") as HitboxComponent
	if hitbox:
		hitbox.set_active(false)


func attack(aim_direction: Vector2, target_position: Vector2) -> void:
	if not can_attack():
		return
	super.attack(aim_direction, target_position)

	if hitbox:
		hitbox.damage = damage
		hitbox.knockback_force = knockback_force
		hitbox.set_active(true)
		# Сеть: хост проверяет удар там, где его сделал владелец (компенсация задержки)
		if origin_override.is_finite():
			hitbox.top_level = true
			hitbox.global_position = origin_override
			hitbox.global_rotation = aim_direction.angle()

	# Звук взмаха клинка / удара
	var snd = get_node_or_null("/root/SoundManager")
	if snd:
		if self is PaladinHammer:
			snd.play_shield_bash()
		else:
			snd.play_sword_swing()

	# Визуальный дуговой след взмаха клинка
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_slash_arc"):
		var slash_pos: Vector2 = global_position + aim_direction * (swing_distance * 0.8)
		vfx.spawn_slash_arc(slash_pos, aim_direction.angle())

	# Анимация выпада / удара вперед и плавный возврат
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", _initial_pos.x + swing_distance, attack_duration * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:x", _initial_pos.x, attack_duration * 0.6).set_ease(Tween.EASE_IN)

	# Таймер деактивации хитбокса (метод, а не лямбда: при удалении оружия связь рвётся сама)
	get_tree().create_timer(attack_duration).timeout.connect(_end_attack_window)


func _end_attack_window() -> void:
	if hitbox and is_instance_valid(hitbox):
		hitbox.set_active(false)
		if hitbox.top_level:
			hitbox.top_level = false
			hitbox.position = Vector2.ZERO
			hitbox.rotation = 0.0
