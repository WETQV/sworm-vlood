extends Node2D
## Game — основная игровая сцена
## Запускает генерацию подземелья, потом спавнит игрока в стартовой комнате.

const DUNGEON_SCENE := preload("res://scenes/levels/dungeon_generator.tscn")

@onready var info_label: Label     = $CanvasLayer/InfoLabel
@onready var player_container: Node2D = $PlayerContainer
@onready var enemy_container: Node2D  = $EnemyContainer
@onready var death_screen: CanvasLayer = $DeathScreen

var _dungeon: DungeonGenerator  # DungeonGenerator instance
var _player: CharacterBody2D

# Overlay для transition
var _transition_overlay: ColorRect


func _ready() -> void:
	_create_transition_overlay()
	_generate_dungeon()


func _create_transition_overlay() -> void:
	_transition_overlay = ColorRect.new()
	_transition_overlay.color = Color.BLACK
	_transition_overlay.modulate.a = 1.0  # Начинаем с чёрного
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_transition_overlay)
	move_child(_transition_overlay, get_child_count() - 1)
	
	# Fade from black
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 0.0, 0.5).set_delay(0.3)


func _generate_dungeon() -> void:
	# Создаём и добавляем генератор
	_dungeon = DUNGEON_SCENE.instantiate()
	add_child(_dungeon)

	# Ждём пока генератор завершит генерацию в _ready()
	await get_tree().process_frame

	var class_data := GameManager.get_selected_class_data()
	info_label.text = "Класс: %s | WASD — движение | ЛКМ — атака | ESC — меню | Колесо — зум" % class_data["name"]

	_spawn_player(class_data)


## Спавнит игрока в стартовой комнате через API генератора.
## Если стартовой комнаты нет — фоллбэк на центр экрана.
func _spawn_player(class_data: Dictionary) -> void:
	var spawn_pos := Vector2(640, 360)  # Фоллбэк

	# Используем публичный API генератора
	if _dungeon and _dungeon.get_start_room():
		var start_room: Room = _dungeon.get_start_room()
		# Ищем первый SpawnPoint в стартовой комнате
		var spawn_root := start_room.get_node_or_null("SpawnPoints")
		if spawn_root and spawn_root.get_child_count() > 0:
			var spawn_point: Marker2D = spawn_root.get_child(0)
			spawn_pos = start_room.global_position + spawn_point.position
		else:
			# Если нет SpawnPoint — центр комнаты
			spawn_pos = start_room.global_position + Vector2(
				start_room.room_size.x * 32.0,
				start_room.room_size.y * 32.0
			)

	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	_player = player_scene.instantiate()

	_player.position = spawn_pos
	player_container.add_child(_player)

	# Настройка камеры для корректной работы с интерполяцией
	var cam: Camera2D = _player.get_node_or_null("Camera2D")
	if cam:
		cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		# Применяем зум из настроек
		cam.zoom = Vector2(SettingsManager.camera_zoom, SettingsManager.camera_zoom)

	# Применяем статы класса
	var health: HealthComponent = _player.get_node("HealthComponent")
	health.max_health = class_data["stats"]["hp"]
	health.died.connect(_on_player_died)
	_player.speed = class_data["stats"]["speed"]
	_player.attack_damage = class_data["stats"]["damage"]

	# Цвет тела
	_player.get_node("Visuals/Body").color = class_data["color"]


## Обработка смерти игрока
func _on_player_died(_killed_by: Node2D) -> void:
	if death_screen:
		death_screen.show()


## Публичный метод для плавного выхода
func fade_out(duration: float = 0.5) -> Tween:
	if _transition_overlay == null:
		return null
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 1.0, duration)
	return tween


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameManager.go_to_menu()
	
	# Зум камеры колесиком мыши
	if event is InputEventMouseButton:
		var zoom_change := 0.1
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_change_camera_zoom(zoom_change)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_change_camera_zoom(-zoom_change)


func _change_camera_zoom(delta: float) -> void:
	if _player == null:
		return
	var cam: Camera2D = _player.get_node_or_null("Camera2D")
	if cam == null:
		return
	
	# Изменяем зум
	var new_zoom := cam.zoom.x + delta
	# Ограничиваем от 0.5 до 2.0
	new_zoom = clampf(new_zoom, 0.5, 2.0)
	cam.zoom = Vector2(new_zoom, new_zoom)
	
	# Сохраняем в настройки
	SettingsManager.camera_zoom = new_zoom
