extends Slime
class_name Skeleton
## Skeleton.gd — средний враг: скелет-мечник.
## Здоровье, отбрасывание, смерть и растворение наследуются от Slime.
## Поведение — в SkeletonAI (замах и удар мечом по дуге).


func _get_particle_color() -> Color:
	return Color("d8d0bc") # костяная пыль
