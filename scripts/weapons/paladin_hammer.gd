extends "res://scripts/weapons/melee_weapon.gd"
class_name PaladinHammer
## PaladinHammer — Священный щит-бастион Паладина.
## Наносит сокрушительный урон вблизи ударом щита и порождает золотую священную волну (AoE).

@export var shockwave_radius: float = 46.0
@export var shockwave_damage: int = 22
@export var shockwave_knockback: float = 240.0

var _pending_shockwave: bool = false
var _shockwave_delay_timer: float = 0.0
var _shockwave_aim_dir: Vector2 = Vector2.ZERO


func _init() -> void:
	damage = 38
	knockback_force = 280.0
	attack_cooldown = 0.40
	swing_distance = 28.0
	attack_duration = 0.15


var _hit_targets: Dictionary = {}


func attack(aim_direction: Vector2, target_position: Vector2) -> void:
	if not can_attack():
		return
	_hit_targets.clear()
	if hitbox and not hitbox.hit_dealt.is_connected(_on_hitbox_hit):
		hitbox.hit_dealt.connect(_on_hitbox_hit)
	super.attack(aim_direction, target_position)

	# Запуск физического таймера для удара священной волны
	_pending_shockwave = true
	_shockwave_delay_timer = attack_duration * 0.45
	_shockwave_aim_dir = aim_direction


func _on_hitbox_hit(target: Hurtbox, _damage_amount: int) -> void:
	_hit_targets[target] = true


func _physics_process(delta: float) -> void:
	if _pending_shockwave:
		_shockwave_delay_timer -= delta
		if _shockwave_delay_timer <= 0.0:
			_pending_shockwave = false
			_trigger_holy_shockwave(_shockwave_aim_dir)


func _trigger_holy_shockwave(aim_direction: Vector2) -> void:
	var world_2d: World2D = get_world_2d()
	if not world_2d:
		return
	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	if not space_state:
		return

	# Точка эпицентра удара перед щитом
	var impact_pos: Vector2 = global_position + aim_direction * (swing_distance + 14.0)

	# Спавн визуального эффекта золотой волны и искр
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_holy_nova"):
		vfx.spawn_holy_nova(impact_pos, shockwave_radius)

	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_holy_shockwave"):
		snd.play_holy_shockwave()

	# Запрос круговой области поражения (Слой 64 = Hurtbox врагов)
	var shape := CircleShape2D.new()
	shape.radius = shockwave_radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, impact_pos)
	query.collision_mask = 64 | (32 if NetworkManager.friendly_fire else 0)
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var hits: Array[Dictionary] = space_state.intersect_shape(query, 32)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider and collider.get_parent() != wielder:
			# Если враг УЖЕ получил прямой удар щитом, не наносим повторный урон волной
			if _hit_targets.has(collider):
				continue
			_hit_targets[collider] = true
			if collider.has_method("receive_damage"):
				collider.receive_damage(shockwave_damage, shockwave_knockback, impact_pos, wielder, false)
