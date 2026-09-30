extends Area2D
class_name Arrow
## Стрела — снаряд лучника.

var direction: Vector2 = Vector2.RIGHT
var damage: int = 20
var speed: float = 450.0
var lifetime: float = 3.0
var knockback_force: float = 160.0
var attacker: Node2D = null

var _elapsed_time: float = 0.0


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	if direction != Vector2.ZERO:
		rotation = direction.angle()

	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_bow_shoot"):
		snd.play_bow_shoot()


## Движение в физическом кадре (фиксированный шаг ~7 px): в _process при просадке кадра
## снаряд перепрыгивал маленькие хитбоксы и пролетал сквозь врагов
func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_elapsed_time += delta
	if _elapsed_time >= lifetime:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	var target: Node = area.get_parent()
	if area.has_method("receive_damage") and (target.is_in_group("enemy") or (NetworkManager.friendly_fire and target.is_in_group("player") and target != attacker)):
		area.receive_damage(damage, knockback_force, global_position, attacker)
		var vfx = get_node_or_null("/root/VFXManager")
		if vfx and vfx.has_method("spawn_pierce_spark"):
			vfx.spawn_pierce_spark(global_position, direction)
		var snd = get_node_or_null("/root/SoundManager")
		if snd and snd.has_method("play_arrow_hit"):
			snd.play_arrow_hit()
		queue_free()


func _on_body_entered(_body: Node2D) -> void:
	# Столкновение со стеной
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_pierce_spark"):
		vfx.spawn_pierce_spark(global_position, direction)
	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_arrow_hit"):
		snd.play_arrow_hit()
	queue_free()
