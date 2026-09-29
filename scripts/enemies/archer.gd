extends Slime
class_name Archer
## Archer.gd — враг-лучник: хрупкий, держит дистанцию и стреляет.
## contact_damage задаёт урон стрелы. Поведение — в ArcherAI.


func _get_particle_color() -> Color:
	return Color("6f8a4a") # болотно-зелёный плащ


func _on_died(killed_by: Node2D) -> void:
	var aim_line := get_node_or_null("AimLine") as Line2D
	if aim_line:
		aim_line.visible = false
	super._on_died(killed_by)
