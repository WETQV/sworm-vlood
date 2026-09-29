extends Area2D
class_name EnemyArrow
## Вражеская стрела — снаряд врага-лучника. Ранит только игроков.

var direction: Vector2 = Vector2.RIGHT
var damage: int = 12
var speed: float = 340.0
var lifetime: float = 3.0
var knockback_force: float = 140.0
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


func _process(delta: float) -> void:
	global_position += direction * speed * delta
	_elapsed_time += delta
	if _elapsed_time >= lifetime:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Наносим урон только игрокам
	if area.has_method("receive_damage") and area.get_parent().is_in_group("player"):
		var source: Node2D = attacker if is_instance_valid(attacker) else null
		area.receive_damage(damage, knockback_force, global_position, source)
		_impact()


func _on_body_entered(_body: Node2D) -> void:
	# Столкновение со стеной
	_impact()


func _impact() -> void:
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_pierce_spark"):
		vfx.spawn_pierce_spark(global_position, direction)
	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_arrow_hit"):
		snd.play_arrow_hit()
	queue_free()
