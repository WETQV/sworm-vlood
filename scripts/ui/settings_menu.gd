extends CanvasLayer

## SettingsMenu — меню настроек с красивыми вкладками
## Стиль: Фэнтези/Подземелье

# --- Ноды ---
@onready var panel: PanelContainer = %PanelContainer
@onready var title_label: Label = %Title

# Вкладки
@onready var tab_sound: Button = %TabSound
@onready var tab_video: Button = %TabVideo
@onready var tab_controls: Button = %TabControls
@onready var tab_network: Button = %TabNetwork

# Контент
@onready var sound_content: VBoxContainer = %SoundContent
@onready var video_content: VBoxContainer = %VideoContent
@onready var controls_content: VBoxContainer = %ControlsContent
@onready var network_content: VBoxContainer = %NetworkContent

# Звук
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider

# Видео
@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var vsync_check: CheckBox = %VSyncCheck
@onready var borderless_check: CheckBox = %BorderlessCheck

# Управление
@onready var mouse_slider: HSlider = %MouseSlider
@onready var camera_zoom_slider: HSlider = %CameraZoomSlider

# Сеть
@onready var name_edit: LineEdit = %NameEdit
@onready var port_spinbox: SpinBox = %PortSpinBox

# Кнопки
@onready var apply_button: Button = %ApplyButton
@onready var back_button: Button = %BackButton

# Фон
@onready var background: ColorRect = $Background

# Текущая вкладка
var _current_tab: int = 0

# Стили для вкладок
var _tab_style_active: StyleBoxFlat
var _tab_style_inactive: StyleBoxFlat


func _ready() -> void:
	_create_tab_styles()
	_setup_ui()
	_load_ui_from_settings()
	_connect_signals()
	_start_animation()


func _create_tab_styles() -> void:
	# Активная вкладка
	_tab_style_active = StyleBoxFlat.new()
	_tab_style_active.bg_color = Color(0.15, 0.12, 0.18, 1)
	_tab_style_active.border_width_left = 2
	_tab_style_active.border_width_top = 2
	_tab_style_active.border_width_right = 2
	_tab_style_active.border_width_bottom = 2
	_tab_style_active.border_color = Color(0.85, 0.68, 0.35, 1)
	_tab_style_active.corner_radius_top_left = 6
	_tab_style_active.corner_radius_top_right = 6
	_tab_style_active.corner_radius_bottom_left = 6
	_tab_style_active.corner_radius_bottom_right = 6
	_tab_style_active.shadow_color = Color(0.85, 0.68, 0.35, 0.3)
	_tab_style_active.shadow_size = 6
	
	# Неактивная вкладка
	_tab_style_inactive = StyleBoxFlat.new()
	_tab_style_inactive.bg_color = Color(0.1, 0.08, 0.12, 0.6)
	_tab_style_inactive.border_width_left = 1
	_tab_style_inactive.border_width_top = 1
	_tab_style_inactive.border_width_right = 1
	_tab_style_inactive.border_width_bottom = 1
	_tab_style_inactive.border_color = Color(0.4, 0.35, 0.25, 0.5)
	_tab_style_inactive.corner_radius_top_left = 6
	_tab_style_inactive.corner_radius_top_right = 6
	_tab_style_inactive.corner_radius_bottom_left = 6
	_tab_style_inactive.corner_radius_bottom_right = 6


func _setup_ui() -> void:
	# Начальное состояние для анимации
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	background.modulate.a = 0.0
	
	# Pivot для кнопок
	apply_button.pivot_offset = Vector2(70, 21)
	back_button.pivot_offset = Vector2(70, 21)
	
	# Применяем стили к вкладкам
	_update_tab_styles()


func _update_tab_styles() -> void:
	var tabs = [tab_sound, tab_video, tab_controls, tab_network]
	
	for i in range(tabs.size()):
		var tab = tabs[i]
		if i == _current_tab:
			tab.add_theme_stylebox_override("normal", _tab_style_active)
			tab.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 1))
		else:
			tab.add_theme_stylebox_override("normal", _tab_style_inactive)
			tab.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55, 1))


func _switch_tab(tab_index: int) -> void:
	if tab_index == _current_tab:
		return
	
	_current_tab = tab_index
	
	# Скрываем весь контент
	sound_content.visible = false
	video_content.visible = false
	controls_content.visible = false
	network_content.visible = false
	
	# Показываем нужный контент
	match tab_index:
		0: sound_content.visible = true
		1: video_content.visible = true
		2: controls_content.visible = true
		3: network_content.visible = true
	
	# Обновляем стили вкладок
	_update_tab_styles()
	
	# Обновляем кнопки toggle
	tab_sound.button_pressed = (tab_index == 0)
	tab_video.button_pressed = (tab_index == 1)
	tab_controls.button_pressed = (tab_index == 2)
	tab_network.button_pressed = (tab_index == 3)


func _load_ui_from_settings() -> void:
	# Грузим текущие значения из синглтона
	master_slider.value = SettingsManager.master_volume
	music_slider.value = SettingsManager.music_volume
	sfx_slider.value = SettingsManager.sfx_volume
	
	fullscreen_check.button_pressed = SettingsManager.fullscreen
	vsync_check.button_pressed = SettingsManager.vsync
	
	mouse_slider.value = SettingsManager.mouse_sensitivity
	
	name_edit.text = SettingsManager.player_name
	port_spinbox.value = float(SettingsManager.port)


func _connect_signals() -> void:
	# Вкладки
	tab_sound.pressed.connect(func(): _switch_tab(0))
	tab_video.pressed.connect(func(): _switch_tab(1))
	tab_controls.pressed.connect(func(): _switch_tab(2))
	tab_network.pressed.connect(func(): _switch_tab(3))
	
	# Аудио применяем прозрачно
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vsync_check.toggled.connect(_on_vsync_toggled)
	borderless_check.toggled.connect(_on_borderless_toggled)
	
	mouse_slider.value_changed.connect(_on_mouse_changed)
	camera_zoom_slider.value_changed.connect(_on_camera_zoom_changed)
	
	name_edit.text_changed.connect(_on_name_changed)
	port_spinbox.value_changed.connect(_on_port_changed)
	
	apply_button.pressed.connect(_on_apply_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# Hover эффекты для кнопок
	_setup_button_hover(apply_button)
	_setup_button_hover(back_button)


func _setup_button_hover(btn: Button) -> void:
	btn.mouse_entered.connect(func():
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.15)
		tween.tween_property(btn, "modulate", Color(1.1, 1.05, 0.95, 1.0), 0.15)
	)
	btn.mouse_exited.connect(func():
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(btn, "scale", Vector2.ONE, 0.15)
		tween.tween_property(btn, "modulate", Color.WHITE, 0.15)
	)
	btn.button_down.connect(func():
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.08)
	)
	btn.button_up.connect(func():
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.1)
	)


func _start_animation() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Фон
	tween.tween_property(background, "modulate:a", 1.0, 0.25)
	
	# Панель
	tween.tween_property(panel, "modulate:a", 1.0, 0.35).set_delay(0.1)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.35).set_delay(0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _close_animation() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.2)
	tween.tween_property(background, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free).set_delay(0.2)


# --- Обработчики ---
func _on_master_changed(value: float) -> void:
	SettingsManager.master_volume = value
	if AudioServer.bus_count > 0:
		AudioServer.set_bus_volume_db(0, linear_to_db(value))


func _on_music_changed(value: float) -> void:
	SettingsManager.music_volume = value
	if AudioServer.bus_count > 1:
		AudioServer.set_bus_volume_db(1, linear_to_db(value))


func _on_sfx_changed(value: float) -> void:
	SettingsManager.sfx_volume = value
	if AudioServer.bus_count > 2:
		AudioServer.set_bus_volume_db(2, linear_to_db(value))


func _on_fullscreen_toggled(pressed: bool) -> void:
	SettingsManager.fullscreen = pressed


func _on_vsync_toggled(pressed: bool) -> void:
	SettingsManager.vsync = pressed


func _on_borderless_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	else:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)


func _on_mouse_changed(value: float) -> void:
	SettingsManager.mouse_sensitivity = value


func _on_camera_zoom_changed(_value: float) -> void:
	pass


func _on_name_changed(new_text: String) -> void:
	SettingsManager.player_name = new_text


func _on_port_changed(value: float) -> void:
	SettingsManager.port = int(value)


func _on_apply_pressed() -> void:
	SettingsManager.apply_settings()
	SettingsManager.save_settings()
	
	# Визуальный фидбек
	var tween = create_tween()
	tween.tween_property(panel, "modulate", Color(0.5, 0.45, 0.35, 1.0), 0.1)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.15)


func _on_back_pressed() -> void:
	SettingsManager.save_settings()
	_close_animation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SettingsManager.save_settings()
		_close_animation()
		get_viewport().set_input_as_handled()