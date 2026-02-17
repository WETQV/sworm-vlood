extends Control

## ClassSelect — экран выбора класса

@onready var cards_container: HBoxContainer = %ClassCardsContainer
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton
@onready var selected_label: Label = %SelectedIndicator
@onready var header_label: Label = %HeaderLabel

var _class_cards: Array[PanelContainer] = []
var _selected_class: GameManager.PlayerClass = GameManager.PlayerClass.WARRIOR


func _ready() -> void:
	header_label.text = "ВЫБЕРИ СВОЙ КЛАСС"
	_create_class_cards()
	_connect_signals()
	_select_class(GameManager.PlayerClass.WARRIOR)


func _create_class_cards() -> void:
	for child in cards_container.get_children():
		child.queue_free()
	
	for class_id in GameManager.CLASS_DATA:
		var data: Dictionary = GameManager.CLASS_DATA[class_id]
		var card := _build_card(class_id, data)
		cards_container.add_child(card)
		_class_cards.append(card)


func _build_card(class_id: GameManager.PlayerClass, data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 300)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	# Иконка (цветной квадрат)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(80, 80)
	icon.color = data["color"]
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon)
	
	# Название класса
	var name_label := Label.new()
	name_label.text = data["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(name_label)
	
	# Описание
	var desc_label := Label.new()
	desc_label.text = data["description"]
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.custom_minimum_size.x = 180
	desc_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc_label)
	
	# Статы
	var stats: Dictionary = data["stats"]
	var stats_label := Label.new()
	stats_label.text = "HP: %d | DMG: %d | SPD: %d" % [stats["hp"], stats["damage"], stats["speed"]]
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	vbox.add_child(stats_label)
	
	# Обработка клика
	panel.gui_input.connect(_on_card_input.bind(class_id, panel))
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	return panel


func _connect_signals() -> void:
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _on_card_input(event: InputEvent, class_id: GameManager.PlayerClass, panel: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_class(class_id)


func _select_class(class_id: GameManager.PlayerClass) -> void:
	_selected_class = class_id
	var data: Dictionary = GameManager.CLASS_DATA[class_id]
	selected_label.text = "Выбран: %s" % data["name"]
	
	var index := 0
	for card in _class_cards:
		if index == class_id:
			card.modulate = Color.WHITE
			card.self_modulate = Color(1.2, 1.2, 1.2)
		else:
			card.modulate = Color(0.6, 0.6, 0.6)
			card.self_modulate = Color.WHITE
		index += 1


func _on_start_pressed() -> void:
	GameManager.selected_class = _selected_class
	GameManager.start_new_game()


func _on_back_pressed() -> void:
	GameManager.go_to_menu()
