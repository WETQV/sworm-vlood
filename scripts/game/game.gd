extends Node2D
## Game — основная игровая сцена
## Запускает генерацию подземелья, потом спавнит игрока в стартовой комнате.

const DUNGEON_SCENE := preload("res://scenes/levels/dungeon_generator.tscn")

@onready var info_label: Label = get_node_or_null("CanvasLayer/InfoLabel")
@onready var player_container: Node2D = $PlayerContainer
@onready var enemy_container: Node2D  = $EnemyContainer
@onready var death_screen: CanvasLayer = $DeathScreen

var _dungeon: DungeonGenerator  # DungeonGenerator instance
var _player: CharacterBody2D

# Overlay для transition на отдельном CanvasLayer
var _transition_layer: CanvasLayer
var _transition_overlay: ColorRect
var _transition_label: Label

# Меню паузы
var _pause_layer: CanvasLayer
var _pause_overlay: Control


func _ready() -> void:
	_create_transition_overlay()
	_setup_pause_menu()
	_generate_dungeon()


func _create_transition_overlay() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "TransitionLayer"
	_transition_layer.layer = 100
	add_child(_transition_layer)

	_transition_overlay = ColorRect.new()
	_transition_overlay.color = Color.BLACK
	_transition_overlay.modulate.a = 1.0  # Начинаем с чёрного
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_layer.add_child(_transition_overlay)

	_transition_label = Label.new()
	_transition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transition_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_transition_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_label.theme = load("res://resources/themes/gothic_theme.tres")
	_transition_label.add_theme_font_override("font", load("res://resources/fonts/RuslanDisplay-Regular.ttf"))
	_transition_label.add_theme_font_size_override("font_size", 36)
	_transition_label.add_theme_color_override("font_color", Color(0.96, 0.85, 0.52, 1.0))
	_transition_label.text = "ЭТАЖ %d" % GameManager.current_floor
	_transition_overlay.add_child(_transition_label)

	# Плавное проявление из темноты с комфортной паузой для чтения
	var tween = create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(_transition_overlay, "modulate:a", 0.0, 0.7)


func _generate_dungeon() -> void:
	# Создаём и добавляем генератор
	_dungeon = DUNGEON_SCENE.instantiate()
	add_child(_dungeon)

	# Ждём пока генератор завершит генерацию в _ready()
	await get_tree().process_frame

	var class_data := GameManager.get_selected_class_data()
	if info_label:
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

	# Подключение внутриигрового HUD
	var hud: GameHUD = get_node_or_null("HUD") as GameHUD
	if hud:
		hud.setup_player(_player)


## Обработка смерти игрока
func _on_player_died(_killed_by: Node2D) -> void:
	if death_screen and death_screen.has_method("show_death"):
		death_screen.show_death()
	elif death_screen:
		death_screen.show()


## Публичный метод для плавного выхода / перехода между этажами
func fade_out(duration: float = 0.6, next_floor: int = -1) -> Tween:
	if _transition_overlay == null:
		return null
	if _transition_label:
		if next_floor > 0:
			_transition_label.text = "СПУСК В БЕЗДНУ...\nЭТАЖ %d" % next_floor
		else:
			_transition_label.text = ""
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 1.0, duration)
	return tween


var _btn_resume: Button = null


func _setup_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseLayer"
	_pause_layer.layer = 95
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)

	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.add_child(_pause_overlay)

	# Полупрозрачная темная вуаль
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.04, 0.06, 0.85)
	_pause_overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 360)
	var empty_style := StyleBoxEmpty.new()
	panel.add_theme_stylebox_override("panel", empty_style)
	center.add_child(panel)

	# Ликвид-шейдер для фона паузы
	var shader_bg := ColorRect.new()
	shader_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://resources/shaders/liquid_card.gdshader")
	shader_mat.set_shader_parameter("bg_color", Color(0.08, 0.05, 0.11, 0.96))
	shader_mat.set_shader_parameter("border_color", Color(0.42, 0.32, 0.20, 0.85))
	shader_mat.set_shader_parameter("hover_border_color", Color(0.88, 0.68, 0.32, 1.0))
	shader_mat.set_shader_parameter("select_border_color", Color(1.0, 0.88, 0.46, 1.0))
	shader_mat.set_shader_parameter("accent_color", Color(0.85, 0.20, 0.22, 1.0))
	shader_mat.set_shader_parameter("card_size", Vector2(360, 360))
	shader_mat.set_shader_parameter("corner_radius_px", 18.0)
	shader_mat.set_shader_parameter("border_width_px", 2.5)
	shader_mat.set_shader_parameter("select_amount", 0.35)
	shader_bg.material = shader_mat
	panel.add_child(shader_bg)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load("res://resources/fonts/RuslanDisplay-Regular.ttf"))
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.96, 0.85, 0.52, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.7, 0.15, 0.15, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)

	_btn_resume = Button.new()
	_btn_resume.text = "ПРОДОЛЖИТЬ"
	_btn_resume.custom_minimum_size = Vector2(0, 46)
	_style_pause_button(_btn_resume, true)
	_btn_resume.pressed.connect(func():
		var snd = get_node_or_null("/root/SoundManager")
		if snd: snd.play_ui_click()
		_toggle_pause(false)
	)
	vbox.add_child(_btn_resume)

	var btn_settings := Button.new()
	btn_settings.text = "НАСТРОЙКИ"
	btn_settings.custom_minimum_size = Vector2(0, 44)
	_style_pause_button(btn_settings, false)
	btn_settings.pressed.connect(func():
		var snd = get_node_or_null("/root/SoundManager")
		if snd: snd.play_ui_click()
		_open_settings()
	)
	vbox.add_child(btn_settings)

	var btn_restart := Button.new()
	btn_restart.text = "НАЧАТЬ ЗАНОВО"
	btn_restart.custom_minimum_size = Vector2(0, 44)
	_style_pause_button(btn_restart, false)
	btn_restart.pressed.connect(func():
		var snd = get_node_or_null("/root/SoundManager")
		if snd: snd.play_ui_click()
		_toggle_pause(false)
		GameManager.start_new_game()
	)
	vbox.add_child(btn_restart)

	var btn_menu := Button.new()
	btn_menu.text = "В ГЛАВНОЕ МЕНЮ"
	btn_menu.custom_minimum_size = Vector2(0, 44)
	_style_pause_button(btn_menu, false)
	btn_menu.pressed.connect(func():
		var snd = get_node_or_null("/root/SoundManager")
		if snd: snd.play_ui_click()
		_toggle_pause(false)
		GameManager.go_to_menu()
	)
	vbox.add_child(btn_menu)


func _style_pause_button(btn: Button, is_primary: bool) -> void:
	btn.pivot_offset = Vector2(148, 22)
	var normal_style = StyleBoxFlat.new()
	normal_style.corner_radius_top_left = 12
	normal_style.corner_radius_top_right = 12
	normal_style.corner_radius_bottom_left = 12
	normal_style.corner_radius_bottom_right = 12
	normal_style.border_width_left = 2
	normal_style.border_width_top = 2
	normal_style.border_width_right = 2
	normal_style.border_width_bottom = 2
	
	if is_primary:
		normal_style.bg_color = Color(0.18, 0.08, 0.12, 0.96)
		normal_style.border_color = Color(0.85, 0.32, 0.25, 0.9)
		btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75, 1.0))
	else:
		normal_style.bg_color = Color(0.11, 0.08, 0.15, 0.95)
		normal_style.border_color = Color(0.42, 0.34, 0.22, 0.85)
		btn.add_theme_color_override("font_color", Color(0.85, 0.80, 0.75, 1.0))
	
	var hover_style = normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.22, 0.15, 0.26, 0.98)
	hover_style.border_color = Color(0.96, 0.85, 0.48, 1.0)
	hover_style.shadow_color = Color(0.96, 0.85, 0.48, 0.25)
	hover_style.shadow_size = 6
	
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	btn.add_theme_stylebox_override("focus", hover_style)
	
	var on_focus = func():
		var snd = get_node_or_null("/root/SoundManager")
		if snd and snd.has_method("play_ui_hover"):
			snd.play_ui_hover()
		var t = create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.15)
	
	var on_unfocus = func():
		var t = create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(btn, "scale", Vector2.ONE, 0.15)
	
	btn.mouse_entered.connect(on_focus)
	btn.focus_entered.connect(on_focus)
	btn.mouse_exited.connect(on_unfocus)
	btn.focus_exited.connect(on_unfocus)


func _open_settings() -> void:
	if _pause_layer and _pause_layer.has_node("SettingsMenu"):
		return
	var settings_scene = preload("res://scenes/ui/settings_menu.tscn").instantiate()
	settings_scene.name = "SettingsMenu"
	settings_scene.layer = 100
	if _pause_overlay:
		_pause_overlay.visible = false
	settings_scene.tree_exited.connect(func():
		if get_tree().paused and _pause_overlay:
			_pause_overlay.visible = true
			if _btn_resume:
				_btn_resume.grab_focus()
	)
	_pause_layer.add_child(settings_scene)


func _toggle_pause(do_pause: bool) -> void:
	if _pause_overlay:
		_pause_overlay.visible = do_pause
	get_tree().paused = do_pause
	if do_pause and _btn_resume:
		_btn_resume.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Если открыты настройки поверх паузы, пусть они сами обрабатывают ESC
		if _pause_layer and _pause_layer.has_node("SettingsMenu"):
			return
		_toggle_pause(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return
	
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
