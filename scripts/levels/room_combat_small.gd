extends Room


func _build_room() -> void:
	super._build_room()
	# Открытая площадка или две колонны: сохраняем центральные пути ко всем дверям.
	if posmod(encounter_seed, 2) == 1:
		_add_obstacles([Vector2i(4, 4), Vector2i(10, 6)], Vector2i(2, 2))
