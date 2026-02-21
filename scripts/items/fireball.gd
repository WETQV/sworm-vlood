extends Area2D
class_name Fireball
## Огненный шар — снаряд мага

var direction: Vector2 = Vector2.RIGHT
var damage: int = 35
var speed: float = 300.0
var lifetime: float = 2.5


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# Повернуть по направлению
	rotation = direction.angle()
	
	# Уничтожить через время
	await get_tree().create_timer(lifetime).timeout
	queue_free()


func _process(delta: float) -> void:
	global_position += direction * speed * delta


func _on_area_entered(area: Area2D) -> void:
	# Защита: бьём только врагов
	if not area.get_parent().is_in_group("enemy"):
		return
	
	if area.has_method("receive_damage"):
		area.receive_damage(damage, 200.0, global_position)
		print("Фаербол попал в: ", area.get_parent().name)
		queue_free()


func _on_body_entered(_body: Node2D) -> void:
	# Попали в физическое тело (стену)
	queue_free()
