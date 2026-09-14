extends CharacterBody2D
class_name Slime
## Slime.gd — базовый противник (слайм).

@onready var health_component: HealthComponent = $HealthComponent
@onready var body_sprite: ColorRect = $Visuals/Body
@onready var visuals: Node2D = $Visuals
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hp_bar: ProgressBar = $HPBar

@export var speed: float = 70.0
@export var detection_range: float = 1000.0
@export var contact_damage: int = 10
@export var knockback_resistance: float = 1.0

var _knockback_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("enemy")

	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	hurtbox.damage_received.connect(_on_damage_received)

	hp_bar.max_value = health_component.max_health
	hp_bar.value = health_component.current_health

	# Эффект материализации слизи при появлении
	_play_spawn_animation()


func _play_spawn_animation() -> void:
	visuals.scale = Vector2(0.1, 0.1)
	visuals.modulate.a = 0.0
	hp_bar.modulate.a = 0.0

	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_enemy_spawn_burst"):
		var part_col: Color = Color("ee3333") if name.contains("Boss") else Color("44cc44")
		vfx.spawn_enemy_spawn_burst(global_position, part_col)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visuals, "modulate:a", 1.0, 0.22)
	tween.tween_property(hp_bar, "modulate:a", 1.0, 0.22)
	tween.tween_property(visuals, "scale", Vector2(1.25, 0.75), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(visuals, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)


func _physics_process(delta: float) -> void:
	if not health_component.is_alive():
		return

	# Четкое затухание отбрасывания без накопления скорости
	if _knockback_velocity.length_squared() > 1.0:
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
		velocity = _knockback_velocity
		move_and_slide()


func _on_damage_received(_amount: int, knockback: Vector2) -> void:
	# Ограничиваем силу импульса, чтобы мобы не улетали в космос
	var impulse: Vector2 = knockback * (1.0 / max(0.2, knockback_resistance))
	_knockback_velocity = impulse.limit_length(220.0)

	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_enemy_hit"):
		snd.play_enemy_hit()


func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current


func _on_died(killed_by: Node2D) -> void:
	set_physics_process(false)
	set_process(false)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	hp_bar.visible = false

	# 1. Мгновенно отключаем и удаляем боевой хитбокс, чтобы мёртвый моб не мог бить игрока
	var attack_area := get_node_or_null("AttackArea") as HitboxComponent
	if attack_area:
		attack_area.is_active = false
		attack_area.set_deferred("monitoring", false)
		attack_area.set_deferred("monitorable", false)
		attack_area.queue_free()

	# 2. Мгновенно отключаем получение урона (Hurtbox)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
		hurtbox.set_deferred("collision_layer", 0)
		hurtbox.set_deferred("collision_mask", 0)

	# 3. Мгновенно останавливаем контроллер ИИ
	var ai := get_node_or_null("SlimeAI") as SlimeAI
	if ai:
		ai.set_physics_process(false)
		ai.set_process(false)

	if is_instance_valid(killed_by) and killed_by.has_node("PlayerInfo"):
		killed_by.get_node("PlayerInfo").register_kill()

	# Всплеск частиц смерти
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_death_burst"):
		var part_col: Color = Color("ee3333") if name.contains("Boss") else Color("44cc44")
		vfx.spawn_death_burst(global_position, part_col)

	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_enemy_death"):
		snd.play_enemy_death()

	# Эффект растворения (Dissolve)
	var tween: Tween = create_tween()
	body_sprite.set_instance_shader_parameter("dissolve_amount", 0.0)
	tween.tween_method(
		func(val: float) -> void:
			if is_instance_valid(body_sprite):
				body_sprite.set_instance_shader_parameter("dissolve_amount", val),
		0.0, 1.0, 0.35
	)
	tween.parallel().tween_property(visuals, "scale", Vector2(1.3, 0.4), 0.35)
	tween.tween_callback(queue_free)
