extends "res://scripts/enemies/slime.gd"

## Босс Слизень. Наследует всё поведение обычного слизня,
## но крупнее, медленнее и бьёт сильнее.
## Статы (HP, урон, скорость, параметры атаки) настраиваются в slime_boss.tscn.

func _ready() -> void:
	super._ready()
	hp_bar.position.y -= 30 # поднимаем бар над большим телом
