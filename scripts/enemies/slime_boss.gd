extends "res://scripts/enemies/slime.gd"

## Босс Слизень. Наследует всё поведение обычного слизня,
## но мы масштабируем его в размерах и усиливаем.

func _ready() -> void:
	super._ready()
	# Увеличиваем радиус
	$Visuals/Body.scale = Vector2(2.5, 2.5)
	$BodyCollision.scale = Vector2(2.5, 2.5)
	$AttackArea.scale = Vector2(2.5, 2.5)
	$Hurtbox.scale = Vector2(2.5, 2.5)
	
	speed = 40.0 # босс огромный и медленный
	contact_damage = 30
	detection_range = 1000.0 # видит на всю комнату
	
	hp_bar.position.y -= 30 # поднимаем бар над большим телом
