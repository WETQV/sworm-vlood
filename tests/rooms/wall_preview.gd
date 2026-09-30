extends Node2D
## Стенд стен: камера движется с дробным зумом, без боя.
## godot --path . res://tests/rooms/wall_preview.tscn -- seconds=8

var camera: Camera2D
var anchor: Vector2
var elapsed := 0.0
var duration := 8.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			duration = float(arg.trim_prefix("seconds="))
		if arg == "snap=0":
			RenderingServer.viewport_set_snap_2d_transforms_to_pixel(get_viewport().get_viewport_rid(), false)
			RenderingServer.viewport_set_snap_2d_vertices_to_pixel(get_viewport().get_viewport_rid(), false)
	var room: Room = preload("res://scenes/levels/rooms/room_combat_large.tscn").instantiate()
	room.encounter_seed = 1
	room.room_type = Room.RoomType.START
	room.position = Vector2(3328, 2560)
	add_child(room)
	room.open_connection("east")
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	anchor = room.position + Vector2(704, 512)
	camera.position = anchor
	camera.zoom = Vector2.ONE * 1.13
	add_child(camera)
	DisplayServer.window_set_title("SwormVlood — wall preview")


func _physics_process(delta: float) -> void:
	elapsed += delta
	if camera:
		camera.position = anchor + Vector2(sin(elapsed) * 100.0, cos(elapsed * 0.8) * 80.0)
	if elapsed >= duration:
		get_tree().quit()
