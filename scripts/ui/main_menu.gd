extends Control

## MainMenu — главное меню с анимациями
## Стиль: Фэнтези/Подземелье

# --- Экспортируемые параметры ---
@export var button_scale_hover: float = 1.05
@export var stagger_delay: float = 0.08

# --- Ноды ---
@onready var title_panel: PanelContainer = %TitlePanel
@onready var title_label: Label = %Title
@onready var subtitle_label: Label = %Subtitle
@onready var buttons_container: PanelContainer = %ButtonsContainer

@onready var play_button: Button = %PlayButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var settings_button: Button = %SettingsButton
@onready var credits_button: Button = %CreditsButton
@onready var quit_button: Button = %QuitButton

@onready var version_label: Label = $BottomBar/VersionLabel

# Список кнопок для анимации
var _all_buttons: Array[Button] = []

# Overlay для переходов
var _transition_overlay: ColorRect


func _ready() -> void:
	_create_transition_overlay()
	_setup_ui()
	_connect_signals()
	_start_entrance_animation()
	play_button.grab_focus()


func _create_transition_overlay() -> void:
	# Создаём чёрный overlay для плавных переходов
	_transition_overlay = ColorRect.new()
	_transition_overlay.color = Color.BLACK
	_transition_overlay.modulate.a = 0.0
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_transition_overlay)
	# Перемещаем на самый верх
	move_child(_transition_overlay, get_child_count() - 1)


func _setup_ui() -> void:
	# Текст кнопок
	play_button.text = "⚔  ИГРАТЬ"
	host_button.text = "🌐  Создать сервер"
	join_button.text = "🔗  Подключиться"
	settings_button.text = "⚙  Настройки"
	credits_button.text = "📜  Об игре"
	quit_button.text = "🚪  Выход"
	
	# Мультиплеер пока не готов
	host_button.visible = false
	join_button.visible = false
	
	# Версия
	version_label.text = "v0.1.0 Alpha"
	
	# Собираем кнопки для анимации
	_all_buttons = [play_button, settings_button, credits_button, quit_button]
	
	# Кнопки ВИДНЫ СРАЗУ (убираем modulate.a = 0)
	# Анимация только через scale
	
	# Устанавливаем pivot для красивого масштабирования
	for btn in _all_buttons:
		btn.pivot_offset = Vector2(140, 25)
		btn.scale = Vector2(0.9, 0.9)  # Начальный scale для анимации
	
	# Контейнер кнопок
	buttons_container.scale = Vector2(0.9, 0.9)
	buttons_container.modulate.a = 0.0
	
	# Заголовок
	title_panel.modulate.a = 0.0
	subtitle_label.modulate.a = 0.0


func _connect_signals() -> void:
	play_button.pressed.connect(_on_play_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Hover эффекты для всех кнопок
	for btn in _all_buttons:
		btn.mouse_entered.connect(_on_button_hover.bind(btn))
		btn.mouse_exited.connect(_on_button_exit.bind(btn))
		btn.button_down.connect(_on_button_press.bind(btn))
		btn.button_up.connect(_on_button_release.bind(btn))


# ==================== АНИМАЦИИ ====================

func _start_entrance_animation() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Заголовок
	tween.tween_property(title_panel, "modulate:a", 1.0, 0.4)
	
	# Подзаголовок
	tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.3).set_delay(0.15)
	
	# Контейнер кнопок
	tween.tween_property(buttons_container, "modulate:a", 1.0, 0.3).set_delay(0.2)
	tween.tween_property(buttons_container, "scale", Vector2.ONE, 0.3).set_delay(0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# Кнопки появляются по очереди (scale анимация)
	for i in range(_all_buttons.size()):
		var btn = _all_buttons[i]
		var delay = 0.25 + (i * stagger_delay)
		tween.tween_property(btn, "scale", Vector2.ONE, 0.2).set_delay(delay).set_ease(Tween.EASE_OUT)


func _on_button_hover(btn: Button) -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(btn, "scale", Vector2(button_scale_hover, button_scale_hover), 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "modulate", Color(1.1, 1.05, 0.95, 1.0), 0.15)


func _on_button_exit(btn: Button) -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(btn, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "modulate", Color.WHITE, 0.15)


func _on_button_press(btn: Button) -> void:
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.08).set_ease(Tween.EASE_IN)


func _on_button_release(btn: Button) -> void:
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(button_scale_hover, button_scale_hover), 0.1).set_ease(Tween.EASE_OUT)


# ==================== ПЕРЕХОДЫ ====================

func _fade_to_black(duration: float = 0.3) -> Tween:
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 1.0, duration)
	return tween


func _fade_from_black(duration: float = 0.3) -> Tween:
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 0.0, duration)
	return tween


# ==================== ОБРАБОТЧИКИ ====================

func _on_play_pressed() -> void:
	GameManager.is_multiplayer = false
	_transition_to("res://scenes/ui/class_select.tscn")


func _on_host_pressed() -> void:
	GameManager.is_multiplayer = true
	_transition_to("res://scenes/ui/class_select.tscn")


func _on_join_pressed() -> void:
	GameManager.is_multiplayer = true
	# TODO: показать окно ввода IP
	pass


func _on_settings_pressed() -> void:
	var settings = preload("res://scenes/ui/settings_menu.tscn").instantiate()
	add_child(settings)


func _on_credits_pressed() -> void:
	var credits = preload("res://scenes/ui/credits.tscn").instantiate()
	add_child(credits)


func _on_quit_pressed() -> void:
	var tween = _fade_to_black(0.3)
	tween.tween_callback(func(): get_tree().quit())


func _transition_to(scene_path: String) -> void:
	var tween = _fade_to_black(0.25)
	tween.tween_callback(func(): GameManager.change_scene(scene_path))
	tween.play()