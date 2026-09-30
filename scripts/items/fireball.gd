extends Area2D
class_name Fireball
## Огненный шар — снаряд мага.

var direction: Vector2 = Vector2.RIGHT
var damage: int = 35
var speed: float = 340.0
var lifetime: float = 2.5
var knockback_force: float = 120.0
var attacker: Node2D = null
## Навыки мага (RangedWeapon.projectile_mods): blast_radius/splash — «Огненный взрыв»,
## burn_tick/burn_duration/burn_interval/boss_factor — «Горение»
var mods: Dictionary = {}

const BURN_SCRIPT := preload("res://scripts/progression/burn_effect.gd")

var _elapsed_time: float = 0.0
var _exploded: bool = false


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	if direction != Vector2.ZERO:
		rotation = direction.angle()

	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_fireball_cast"):
		snd.play_fireball_cast()


## Движение в физическом кадре (фиксированный шаг ~7 px): в _process при просадке кадра
## снаряд перепрыгивал маленькие хитбоксы и пролетал сквозь врагов
func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_elapsed_time += delta
	if _elapsed_time >= lifetime:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	var target: Node = area.get_parent()
	if _exploded:
		return
	if area.has_method("receive_damage") and (target.is_in_group("enemy") or (NetworkManager.friendly_fire and target.is_in_group("player") and target != attacker)):
		area.receive_damage(damage, knockback_force, global_position, attacker)
		_ignite(target)
		_explode(area)


func _on_body_entered(_body: Node2D) -> void:
	# Столкновение со стеной (взрыв «Огненного взрыва» задевает врагов и у стены)
	if not _exploded:
		_explode(null)


## Попадание/стена: эффект у всех, урон по соседям считает только хост (Hurtbox.receive_damage)
func _explode(primary: Area2D) -> void:
	_exploded = true
	var radius := float(mods.get("blast_radius", 0.0))
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_fire_explosion"):
		vfx.spawn_fire_explosion(global_position)
	if radius > 0.0:
		if vfx and vfx.has_method("spawn_holy_nova"):
			vfx.spawn_holy_nova(global_position, radius) # видимая зона совпадает с зоной урона
		var shape := CircleShape2D.new()
		shape.radius = radius
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, global_position)
		query.collision_mask = 64 # hurtbox врагов
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var splash := maxi(1, int(round(damage * float(mods.get("splash", 0.5)))))
		for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
			var hurtbox: Object = hit.get("collider")
			if hurtbox != primary and hurtbox is Hurtbox:
				(hurtbox as Hurtbox).receive_damage(splash, knockback_force * 0.5, global_position, attacker, true, false)
	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_fireball_explosion"):
		snd.play_fireball_explosion()
	queue_free()


## «Горение»: поджог цели (хост). Повторное попадание обновляет длительность, не складывается.
func _ignite(target: Node) -> void:
	var tick := int(mods.get("burn_tick", 0))
	if tick <= 0 or not NetworkManager.is_authority() or not target.is_in_group("enemy"):
		return
	var burn: Node = target.get_node_or_null("Burn")
	if burn == null:
		burn = BURN_SCRIPT.new()
		burn.name = "Burn"
		target.add_child(burn)
	var factor := float(mods.get("boss_factor", 0.5)) if target.scene_file_path.contains("boss") else 1.0
	burn.ignite(maxi(1, int(round(tick * factor))), float(mods.get("burn_duration", 3.0)),
		float(mods.get("burn_interval", 0.5)), attacker)
