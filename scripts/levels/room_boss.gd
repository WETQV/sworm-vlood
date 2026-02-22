# ============================================================================
#  room_boss.gd
#  Босс-арена 30×25 с угловыми пилонами 3×3
# ============================================================================
extends Room

func _build_room() -> void:
	# Сначала строим базовую комнату (пол + стены)
	super._build_room()

	# Добавляем угловые пилоны
	_add_pylons()


func _add_pylons() -> void:
	# Пилоны 3×3 в углах с отступом 3 тайла от стен
	var pylon_positions: Array[Vector2i] = [
		Vector2i(3, 3),      # верх-лево
		Vector2i(24, 3),     # верх-право
		Vector2i(3, 19),     # низ-лево
		Vector2i(24, 19),    # низ-право
	]

	for pos in pylon_positions:
		for dx in range(3):
			for dy in range(3):
				var tile := pos + Vector2i(dx, dy)
				wall_layer.set_cell(tile, 0, WALL_ATLAS)
				floor_layer.erase_cell(tile)
