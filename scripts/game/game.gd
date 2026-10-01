extends Node2D
## Game — основная игровая сцена
## Запускает генерацию подземелья, потом спавнит игрока в стартовой комнате.

const DUNGEON_SCENE := preload("res://scenes/levels/dungeon_generator.tscn")
## Сколько хост ждёт загрузки уровня у клиентов, сек
const SCENE_READY_TIMEOUT := 20.0

@onready var info_label: Label = get_node_or_null("CanvasLayer/InfoLabel")
@onready var player_container: Node2D = $PlayerContainer
@onready var enemy_container: Node2D  = $EnemyContainer
@onready var death_screen: CanvasLayer = $DeathScreen
@onready var spectator_layer: CanvasLayer = $SpectatorLayer
@onready var spectator_label: Label = $SpectatorLayer/StatusLabel

var _dungeon: DungeonGenerator  # DungeonGenerator instance
var _player: CharacterBody2D
var _spectating: bool = false

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
	var reward_ui := CanvasLayer.new()
	reward_ui.name = "RewardUI"
	reward_ui.set_script(preload("res://scripts/ui/reward_ui.gd"))
	add_child(reward_ui)
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
	# Создаём и добавляем генератор (seed от хоста — одинаковое подземелье у всех)
	_dungeon = DUNGEON_SCENE.instantiate()
	_dungeon.seed_value = GameManager.dungeon_seed
	add_child(_dungeon)

	# Ждём пока генератор завершит генерацию в _ready()
	await get_tree().process_frame

	var class_data := GameManager.get_selected_class_data()
	if info_label:
		info_label.text = "Класс: %s | WASD — движение | ЛКМ — атака | ESC — меню | Колесо — зум" % class_data["name"]

	if NetworkManager.is_online():
		_setup_network_spawners()
		if multiplayer.is_server():
			NetworkManager.all_players_in_game.connect(_spawn_all_network_players, CONNECT_ONE_SHOT)
			# Ограниченное ожидание: кто не загрузился за SCENE_READY_TIMEOUT, отключается,
			# остальные начинают игру (без вечного ожидания и без запуска без готовности)
			get_tree().create_timer(SCENE_READY_TIMEOUT).timeout.connect(_on_scene_ready_timeout)
		NetworkManager.notify_game_scene_ready()
	else:
		_spawn_player_node(1, GameManager.selected_class, _get_player_spawn_pos(0))


# ════════════════════════════════════════════════════════════════════════════
#  Игроки
# ════════════════════════════════════════════════════════════════════════════

## Точка появления i-го игрока в стартовой комнате
func _get_player_spawn_pos(index: int) -> Vector2:
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

	# Игроки встают полукругом, чтобы не спавниться друг в друге
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(56, 0), Vector2(-56, 0), Vector2(0, 56)]
	return spawn_pos + offsets[index % offsets.size()]


## Создание персонажа (одиночная игра или spawn_function сетевого спавнера — на всех машинах)
func _spawn_player_node(peer_id: int, player_class: int, pos: Vector2) -> CharacterBody2D:
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.position = pos
	player.peer_id = peer_id
	player.player_class = player_class
	if NetworkManager.is_online():
		player.prepare_network(peer_id)

	player.ready.connect(_on_player_node_ready.bind(player), CONNECT_ONE_SHOT)
	# В одиночной игре добавляем сами; в сети — MultiplayerSpawner
	if not NetworkManager.is_online():
		player_container.add_child(player)
	return player


func _on_player_node_ready(player: CharacterBody2D) -> void:
	# Применяем статы класса (урон оружия — после создания оружия в _ready)
	var class_data: Dictionary = GameManager.CLASS_DATA[player.player_class]
	player.speed = class_data["stats"]["speed"]
	player.attack_damage = class_data["stats"]["damage"]
	player.get_node("Visuals/Body").color = class_data["color"]

	# Билд забега (навыки и улучшения прошлых этажей) — от базовых значений класса
	player.apply_build(Progression.get_build(player.peer_id), true)

	var health: HealthComponent = player.get_node("HealthComponent")
	health.died.connect(_on_player_died.bind(player))

	if not player.is_local():
		return
	_player = player

	# Настройка камеры для корректной работы с интерполяцией
	var cam: Camera2D = _player.get_node_or_null("Camera2D")
	if cam:
		cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		# Применяем зум из настроек
		cam.zoom = Vector2(SettingsManager.camera_zoom, SettingsManager.camera_zoom)
		cam.make_current()

	# Подключение внутриигрового HUD
	var hud: GameHUD = get_node_or_null("HUD") as GameHUD
	if hud:
		hud.setup_player(_player)


## Обработка смерти игрока
func _on_player_died(_killed_by: Node2D, player: CharacterBody2D) -> void:
	if NetworkManager.is_online() and player == _player and not death_screen.visible:
		_spectating = true
		_refresh_spectator_target()
	elif _spectating:
		_refresh_spectator_target()

	# В кооперативе забег проигран, только когда погибли все
	if NetworkManager.is_online():
		if not multiplayer.is_server():
			return
		for p in get_tree().get_nodes_in_group("player"):
			var hc := p.get_node_or_null("HealthComponent") as HealthComponent
			if hc and hc.is_alive():
				return
		_net_show_death.rpc()
		return

	if player == _player:
		_show_death()


@rpc("authority", "call_local", "reliable")
func _net_show_death() -> void:
	_show_death()


func _show_death() -> void:
	_spectating = false
	spectator_layer.visible = false
	if death_screen and death_screen.has_method("show_death"):
		death_screen.show_death()
	elif death_screen:
		death_screen.show()


func _refresh_spectator_target() -> void:
	if not _spectating or not is_instance_valid(_player):
		return
	for node in player_container.get_children():
		var teammate := node as Player
		if teammate and teammate != _player and teammate.health_component.is_alive():
			var cam := _player.get_node_or_null("Camera2D") as Camera2D
			if cam:
				cam.call("follow_target", teammate)
			spectator_label.text = "ВЫ ПОГИБЛИ\nНаблюдение за %s\nВозрождение на следующем этаже" % NetworkManager.players.get(teammate.peer_id, {}).get("name", "союзником")
			spectator_layer.visible = true
			return
	spectator_layer.visible = false


# ════════════════════════════════════════════════════════════════════════════
#  Сеть: спавнеры игроков и врагов (хост создаёт, клиентам приходит автоматически)
# ════════════════════════════════════════════════════════════════════════════

var _player_spawner: MultiplayerSpawner
var _enemy_spawner: MultiplayerSpawner
var _enemy_counter: int = 0


func _setup_network_spawners() -> void:
	_player_spawner = MultiplayerSpawner.new()
	_player_spawner.name = "PlayerSpawner"
	add_child(_player_spawner)
	_player_spawner.spawn_path = _player_spawner.get_path_to(player_container)
	_player_spawner.spawn_function = func(data: Array) -> Node:
		return _spawn_player_node(data[0], data[1], data[2])

	_enemy_spawner = MultiplayerSpawner.new()
	_enemy_spawner.name = "EnemySpawner"
	add_child(_enemy_spawner)
	_enemy_spawner.spawn_path = _enemy_spawner.get_path_to(enemy_container)
	_enemy_spawner.spawn_function = func(data: Array) -> Node:
		var enemy: Node2D = load(data[0]).instantiate()
		enemy.name = data[1]
		enemy.position = data[2]
		if data.size() > 3 and data[3] is Dictionary:
			EnemyScaling.apply(enemy, data[3]) # числа хоста, до _ready — одинаковы у всех
		enemy.prepare_network()
		return enemy


## Хост: не все загрузились за SCENE_READY_TIMEOUT — отключаем опоздавших, остальные играют
func _on_scene_ready_timeout() -> void:
	if player_container.get_child_count() == 0:
		NetworkManager.drop_players_not_in_game()


## Хост: все загрузились — создаём персонажей
func _spawn_all_network_players() -> void:
	var ids: Array = NetworkManager.players.keys()
	ids.sort()
	for i in ids.size():
		var id: int = ids[i]
		_player_spawner.spawn([id, NetworkManager.get_player_class(id), _get_player_spawn_pos(i)])


## Хост: игрок отключился посреди забега
func remove_network_player(peer_id: int) -> void:
	var p := player_container.get_node_or_null("Player_%d" % peer_id)
	if p:
		p.queue_free()
		call_deferred("_refresh_spectator_target")


## Хост: перед сменой этажа убрать сетевые объекты (их удаление разошлётся клиентам)
func stop_local_synchronization() -> void:
	for player in player_container.get_children():
		var sync := player.get_node_or_null("NetSync") as MultiplayerSynchronizer
		if sync and sync.is_multiplayer_authority():
			sync.queue_free()


func clear_network_entities() -> void:
	for container in [player_container, enemy_container]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()


## Хост: создать врага для всех игроков. Возвращает созданный узел.
## stats — итоговые характеристики (EnemyScaling.compute); пустой словарь — базовые из сцены
func spawn_network_enemy(scene: PackedScene, global_pos: Vector2, stats: Dictionary = {}) -> Node2D:
	_enemy_counter += 1
	return _enemy_spawner.spawn([scene.resource_path, "Enemy_%d" % _enemy_counter, global_pos, stats]) as Node2D

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
	btn_restart.visible = NetworkManager.is_authority() # в сети перезапуск — только у хоста
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
	# В сети игру на паузу не ставим — мир живёт у всех игроков
	get_tree().paused = do_pause and not NetworkManager.is_online()
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
