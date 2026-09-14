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
	# Пилоны 2×2 в углах с симметричным отступом 3 тайла от стен
	var pylon_size := 2
	var pad := 3
	var pylon_positions: Array[Vector2i] = [
		Vector2i(pad, pad),                                                      # верх-лево
		Vector2i(room_size.x - pad - pylon_size, pad),                           # верх-право
		Vector2i(pad, room_size.y - pad - pylon_size),                           # низ-лево
		Vector2i(room_size.x - pad - pylon_size, room_size.y - pad - pylon_size) # низ-право
	]

	for pos in pylon_positions:
		for dx in range(pylon_size):
			for dy in range(pylon_size):
				var tile := pos + Vector2i(dx, dy)
				wall_layer.set_cell(tile, 0, WALL_ATLAS)
				floor_layer.erase_cell(tile)

	update_autotiles()
