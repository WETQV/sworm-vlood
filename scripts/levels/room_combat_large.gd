# ============================================================================
#  room_combat_large.gd
#  Большая боевая комната 22×18 с колоннами 2×2
# ============================================================================
extends Room

func _build_room() -> void:
	super._build_room()
	_add_columns()


func _add_columns() -> void:
	# Колонны 2×2 с отступом 4 тайла от стен
	var column_positions: Array[Vector2i] = [
		Vector2i(4, 4),      # верх-лево
		Vector2i(16, 4),     # верх-право
		Vector2i(4, 12),     # низ-лево
		Vector2i(16, 12),    # низ-право
	]

	for pos in column_positions:
		for dx in range(2):
			for dy in range(2):
				var tile := pos + Vector2i(dx, dy)
				wall_layer.set_cell(tile, 0, WALL_ATLAS)
				floor_layer.erase_cell(tile)
