extends CanvasLayer

## DeathScreen — экран смерти игрока

var floor_label: Label
var retry_button: Button
var menu_button: Button


func _ready() -> void:
	# Скрываем экран смерти по умолчанию
	hide()
	
	# Получаем узлы после загрузки сцены
	floor_label = get_node_or_null("%FloorLabel")
	retry_button = get_node_or_null("%RetryButton")
	menu_button = get_node_or_null("%MenuButton")
	
	# Подключаем кнопки если они существуют
	if retry_button:
		retry_button.pressed.connect(_on_retry_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	
	# Обновляем номер этажа
	_update_floor_label()


func _update_floor_label() -> void:
	if floor_label:
		floor_label.text = "Этаж: %d" % GameManager.current_floor


func update_floor() -> void:
	_update_floor_label()


func _on_retry_pressed() -> void:
	GameManager.start_new_game()


func _on_menu_pressed() -> void:
	GameManager.go_to_menu()
