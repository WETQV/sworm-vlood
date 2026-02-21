extends Room
## RoomBoss — арена с боссом 30x25.
## Добавляет декоративные угловые пилоны (3x3 тайла),
## чтобы у босса и игроков было пространство для манёвра,
## но арена не выглядела пустой коробкой.

func _ready() -> void:
	room_type = RoomType.BOSS
	super._ready()

func _build_room() -> void:
	super._build_room()  # Базовый пол + стены
	_add_pylons()


func _add_pylons() -> void:
	# Угловые пилоны 3x3 на небольшом расстоянии от стен (чтобы не перекрывать входы)
	# Комната 30x25: пилоны в углах, отступ 3 тайла от краёв
	var pylon_positions: Array[Vector2i] = [
		Vector2i(3, 3),     # верхний левый
		Vector2i(24, 3),    # верхний правый
		Vector2i(3, 19),    # нижний левый
		Vector2i(24, 19),   # нижний правый
	]

	for pyl_pos: Vector2i in pylon_positions:
		for dx in range(3):
			for dy in range(3):
				var tile: Vector2i = pyl_pos + Vector2i(dx, dy)
				wall_layer.set_cell(tile, 0, Vector2i(1, 0))
				floor_layer.erase_cell(tile)
