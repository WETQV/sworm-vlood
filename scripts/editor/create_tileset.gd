@tool
extends EditorScript

# Скрипт для создания TileSet ресурса
# Запустить через Editor → Run

func _run() -> void:
	var ts := _create_dungeon_tileset()
	var err := ResourceSaver.save(ts, "res://tilesets/dungeon_tileset.tres")
	if err == OK:
		print("✅ TileSet создан: res://tilesets/dungeon_tileset.tres")
	else:
		print("❌ Ошибка сохранения: %d" % err)


func _create_dungeon_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(64, 64)

	# ── Физический слой 0 (стены) ──
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)  # слой "walls"
	ts.set_physics_layer_collision_mask(0, 0)

	# ── Навигационный слой 0 (пол) ──
	ts.add_navigation_layer()

	# ── Источник тайлов ──
	var src := TileSetAtlasSource.new()
	
	# Создаём текстуру: пол (серый) и стена (коричневый)
	var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, 64, 64), Color(0.23, 0.23, 0.29))   # пол
	img.fill_rect(Rect2i(64, 0, 64, 64), Color(0.42, 0.42, 0.48))  # стена
	
	var tex := ImageTexture.create_from_image(img)
	src.texture = tex
	src.texture_region_size = Vector2i(64, 64)
	
	ts.add_source(src, 0)
	
	# Создаём тайлы
	src.create_tile(Vector2i(0, 0))  # пол
	src.create_tile(Vector2i(1, 0))  # стена

	# ── Коллизия стены ──
	var half := 32.0
	var sq := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2( half,  half), Vector2(-half,  half),
	])
	
	var wall_data: TileData = src.get_tile_data(Vector2i(1, 0), 0)
	if wall_data:
		wall_data.add_collision_polygon(0)
		wall_data.set_collision_polygon_points(0, 0, sq)

	# ── Навигация пола ──
	var floor_data: TileData = src.get_tile_data(Vector2i(0, 0), 0)
	if floor_data:
		var nav := NavigationPolygon.new()
		nav.vertices = sq
		nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		floor_data.set_navigation_polygon(0, nav)

	return ts
