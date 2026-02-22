extends CanvasLayer

## Credits — экран "Об игре" с анимацией
## Стиль: Фэнтези/Подземелье

@onready var panel: PanelContainer = %PanelContainer
@onready var title_label: Label = %Title
@onready var back_button: Button = %BackButton
@onready var background: ColorRect = $Background


func _ready() -> void:
	_setup_ui()
	_connect_signals()
	_start_animation()


func _setup_ui() -> void:
	# Начальное состояние для анимации
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	background.modulate.a = 0.0
	
	# Pivot для кнопки (центр)
	back_button.pivot_offset = Vector2(100, 22)


func _connect_signals() -> void:
	back_button.pressed.connect(_on_back_pressed)
	
	# Hover эффекты для кнопки
	back_button.mouse_entered.connect(_on_button_hover)
	back_button.mouse_exited.connect(_on_button_exit)
	back_button.button_down.connect(_on_button_press)
	back_button.button_up.connect(_on_button_release)


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


func _on_back_pressed() -> void:
	_close_animation()


func _on_button_hover() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(back_button, "scale", Vector2(1.05, 1.05), 0.15)
	tween.tween_property(back_button, "modulate", Color(1.1, 1.05, 0.95, 1.0), 0.15)


func _on_button_exit() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(back_button, "scale", Vector2.ONE, 0.15)
	tween.tween_property(back_button, "modulate", Color.WHITE, 0.15)


func _on_button_press() -> void:
	var tween = create_tween()
	tween.tween_property(back_button, "scale", Vector2(0.95, 0.95), 0.08)


func _on_button_release() -> void:
	var tween = create_tween()
	tween.tween_property(back_button, "scale", Vector2(1.05, 1.05), 0.1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_animation()
		get_viewport().set_input_as_handled()