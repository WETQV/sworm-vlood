extends Slime
class_name Bat
## Bat.gd — летучая мышь: хрупкая, быстрая, нападает стаями.
## Поведение — в BatAI (хаотичный полёт, пике и отлёт).


func _get_particle_color() -> Color:
	return Color("7a4fa0") # фиолетовый пух
