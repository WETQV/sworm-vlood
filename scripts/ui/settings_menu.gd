extends CanvasLayer

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider

@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var vsync_check: CheckBox = %VSyncCheck

@onready var mouse_slider: HSlider = %MouseSlider

@onready var name_edit: LineEdit = %NameEdit
@onready var port_spinbox: SpinBox = %PortSpinBox

@onready var apply_button: Button = %ApplyButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	_load_ui_from_settings()
	_connect_signals()


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
	# Аудио применяем прозрачно, на лету
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vsync_check.toggled.connect(_on_vsync_toggled)
	
	mouse_slider.value_changed.connect(_on_mouse_changed)
	
	name_edit.text_changed.connect(_on_name_changed)
	port_spinbox.value_changed.connect(_on_port_changed)
	
	apply_button.pressed.connect(_on_apply_pressed)
	back_button.pressed.connect(_on_back_pressed)


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

func _on_mouse_changed(value: float) -> void:
	SettingsManager.mouse_sensitivity = value

func _on_name_changed(new_text: String) -> void:
	SettingsManager.player_name = new_text

func _on_port_changed(value: float) -> void:
	SettingsManager.port = int(value)


func _on_apply_pressed() -> void:
	SettingsManager.apply_settings()
	SettingsManager.save_settings()

func _on_back_pressed() -> void:
	# При закрытии тоже сохраняем на всякий случай,
	# но игрок может не нажать "Применить", а просто "Назад".
	# Сохраняем текущий state, который он уже изменил:
	SettingsManager.save_settings()
	queue_free()
