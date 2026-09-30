# ============================================================================
#  room_combat_large.gd
#  Большая боевая комната 22×16: колонны или вытянутые укрытия
# ============================================================================
extends Room

func _build_room() -> void:
	super._build_room()
	if posmod(encounter_seed, 2) == 0:
		_add_columns()
	else:
		# Два вертикальных укрытия: центральная линия и обходы с обоих краёв.
		_add_obstacles([Vector2i(6, 5), Vector2i(14, 8)], Vector2i(2, 3))


func _add_columns() -> void:
	# Колонны 2×2 с отступом 4 тайла от стен
	var column_positions: Array[Vector2i] = [
		Vector2i(4, 4),      # верх-лево
		Vector2i(16, 4),     # верх-право
		Vector2i(4, 12),     # низ-лево
		Vector2i(16, 12),    # низ-право
	]

	_add_obstacles(column_positions, Vector2i(2, 2))
