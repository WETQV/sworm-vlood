extends "res://scripts/enemies/slime.gd"

## Босс Слизень. Наследует всё поведение обычного слизня,
## но мы масштабируем его в размерах и усиливаем.

func _ready() -> void:
	super._ready()
	
	print("[DEBUG] Boss Spawned! Local pos: ", position, " Global: ", global_position)
	if get_parent() and get_parent() is Room:
		print("[DEBUG] Parent Room: ", get_parent().name, " Size: ", get_parent().room_size, " Pos: ", get_parent().position)
		
	speed = 40.0 # босс огромный и медленный
	contact_damage = 30
	detection_range = 1000.0 # видит на всю комнату
	
	hp_bar.position.y -= 30 # поднимаем бар над большим телом
