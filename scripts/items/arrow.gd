extends Area2D
class_name Arrow
## Стрела — снаряд лучника

var direction: Vector2 = Vector2.RIGHT
var damage: int = 20
var speed: float = 400.0
var lifetime: float = 3.0


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	
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
		area.receive_damage(damage, 150.0, global_position)
		print("Стрела попала в: ", area.get_parent().name)
		queue_free()
