extends CanvasLayer
## DeathScreen — экран гибели игрока в стиле Dark Roguelike.

@onready var panel: PanelContainer = $PanelContainer
@onready var floor_label: Label = $PanelContainer/MarginContainer/VBoxContainer/FloorLabel
@onready var restart_button: Button = $PanelContainer/MarginContainer/VBoxContainer/RestartButton
@onready var menu_button: Button = $PanelContainer/MarginContainer/VBoxContainer/MenuButton
@onready var backdrop: ColorRect = $Background


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Подключение кнопок
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)


## Вызов при гибели игрока
func show_death() -> void:
	visible = true

	if floor_label:
		floor_label.text = "ЭТАЖ %d" % GameManager.current_floor

	# Анимация появления
	if backdrop:
		backdrop.modulate.a = 0.0
		var bg_tween: Tween = create_tween()
		bg_tween.tween_property(backdrop, "modulate:a", 1.0, 0.3)

	if panel:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(0.88, 0.88)
		panel.modulate.a = 0.0
		var panel_tween: Tween = create_tween().set_parallel(true)
		panel_tween.tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		panel_tween.tween_property(panel, "modulate:a", 1.0, 0.2)

	# Захват фокуса на первой кнопке (клавиатура / геймпад)
	if restart_button:
		restart_button.grab_focus()


func _on_restart_pressed() -> void:
	var snd = get_node_or_null("/root/SoundManager")
	if snd:
		snd.play_ui_click()
	get_tree().paused = false
	GameManager.start_new_game()


func _on_menu_pressed() -> void:
	var snd = get_node_or_null("/root/SoundManager")
	if snd:
		snd.play_ui_click()
	get_tree().paused = false
	GameManager.go_to_menu()
