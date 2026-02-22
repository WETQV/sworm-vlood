extends Control

## ClassSelect — экран выбора класса
## Стиль: Фэнтези/Подземелье

@onready var cards_container: HBoxContainer = $CenterContainer/VBoxContainer/CardsContainer
@onready var play_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/PlayButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/BackButton
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleSection/Title
@onready var subtitle_label: Label = $CenterContainer/VBoxContainer/TitleSection/Subtitle

var _class_cards: Array[PanelContainer] = []
var _selected_index: int = 0

# Цвета для классов
const CLASS_COLORS: Array[Color] = [
	Color(0.8, 0.2, 0.2),   # Warrior - красный
	Color(0.2, 0.7, 0.3),   # Ranger - зелёный
	Color(0.3, 0.5, 0.9),   # Mage - синий
	Color(0.9, 0.8, 0.2)    # Paladin - жёлтый
]

# Overlay для переходов
var _transition_overlay: ColorRect


func _ready() -> void:
	_create_transition_overlay()
	_find_class_cards()
	_setup_ui()
	_connect_signals()
	_start_entrance_animation()


func _create_transition_overlay() -> void:
	_transition_overlay = ColorRect.new()
	_transition_overlay.color = Color.BLACK
	_transition_overlay.modulate.a = 1.0  # Начинаем с чёрного для fade-in
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_transition_overlay)
	move_child(_transition_overlay, get_child_count() - 1)


func _find_class_cards() -> void:
	_class_cards.clear()
	for child in cards_container.get_children():
		if child is PanelContainer:
			_class_cards.append(child)
			# Добавляем обработку клика
			child.gui_input.connect(_on_card_input.bind(child))
	
	# Выбираем первую карточку по умолчанию
	if not _class_cards.is_empty():
		_select_card(0)


func _setup_ui() -> void:
	title_label.text = "⚔ ВЫБЕРИ КЛАСС ⚔"
	subtitle_label.text = "Каждый класс имеет уникальные способности и стиль игры"


func _connect_signals() -> void:
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _start_entrance_animation() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade in от чёрного
	tween.tween_property(_transition_overlay, "modulate:a", 0.0, 0.3)


func _select_card(index: int) -> void:
	if index < 0 or index >= _class_cards.size():
		return
	
	_selected_index = index
	
	# Визуальное выделение карточек
	for i in range(_class_cards.size()):
		var card = _class_cards[i]
		var style: StyleBoxFlat
		
		# Создаём новый стиль
		style = StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.1, 0.14, 0.9)
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		style.shadow_color = Color(0, 0, 0, 0.5)
		style.shadow_size = 8
		
		if i == _selected_index:
			# Выбранная карточка — золотая рамка
			style.border_color = CLASS_COLORS[i]
			style.border_width_left = 4
			style.border_width_top = 4
			style.border_width_right = 4
			style.border_width_bottom = 4
			style.shadow_color = CLASS_COLORS[i]
			style.shadow_size = 15
		else:
			# Обычная карточка
			style.border_color = Color(0.4, 0.35, 0.25, 1)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
		
		card.add_theme_stylebox_override("panel", style)


func _on_card_input(event: InputEvent, card: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index = _class_cards.find(card)
		if index != -1:
			_select_card(index)


func _on_play_pressed() -> void:
	# Сохраняем выбранный класс
	GameManager.selected_class = _selected_index as GameManager.PlayerClass
	_transition_out()


func _on_back_pressed() -> void:
	_transition_to_menu()


func _transition_out() -> void:
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 1.0, 0.25)
	tween.tween_callback(func(): GameManager.start_new_game())


func _transition_to_menu() -> void:
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 1.0, 0.25)
	tween.tween_callback(func(): GameManager.go_to_menu())
