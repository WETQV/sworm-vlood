extends "res://scripts/levels/room.gd"
## RoomCombatLarge — большая боевая комната 22x18.
## Добавляет 4 колонны-препятствия (2x2 тайла) симметрично,
## чтобы у врагов была тактическая позиция, а игрокам было интереснее.

func _build_room() -> void:
	super._build_room()  # Базовый пол + стены по периметру
	_add_columns()


func _add_columns() -> void:
	# Позиции левых-верхних углов колонн (в тайлах относительно комнаты)
	# Сетка 22x18: колонны на ~1/4 и ~3/4 ширины, ~1/3 и ~2/3 высоты
	var column_positions: Array[Vector2i] = [
		Vector2i(5,  4),  # верхняя левая
		Vector2i(15, 4),  # верхняя правая
		Vector2i(5,  12), # нижняя левая
		Vector2i(15, 12), # нижняя правая
	]

	for col_pos: Vector2i in column_positions:
		# 2x2 блока стены = колонна
		for dx in range(2):
			for dy in range(2):
				var tile: Vector2i = col_pos + Vector2i(dx, dy)
				wall_layer.set_cell(tile, 0, Vector2i(1, 0))
				floor_layer.erase_cell(tile)
