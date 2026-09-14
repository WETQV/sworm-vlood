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
var _normal_style: StyleBoxFlat
var _selected_styles: Array[StyleBoxFlat] = []

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
	_create_styles()
	_create_transition_overlay()
	_find_class_cards()
	_setup_ui()
	_connect_signals()
	_start_entrance_animation()


func _create_styles() -> void:
	# Базовый стиль карточки (темный обсидиан с состаренной бронзой)
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = Color(0.08, 0.06, 0.11, 0.95)
	_normal_style.corner_radius_top_left = 2
	_normal_style.corner_radius_top_right = 2
	_normal_style.corner_radius_bottom_left = 2
	_normal_style.corner_radius_bottom_right = 2
	_normal_style.border_width_left = 2
	_normal_style.border_width_top = 2
	_normal_style.border_width_right = 2
	_normal_style.border_width_bottom = 2
	_normal_style.border_color = Color(0.35, 0.28, 0.18, 0.8)
	_normal_style.shadow_color = Color(0, 0, 0, 0.6)
	_normal_style.shadow_size = 8

	# Стиль выделенной карточки (благородная золотая 2px окантовка)
	for color in CLASS_COLORS:
		var style = _normal_style.duplicate()
		style.bg_color = Color(0.14, 0.11, 0.19, 0.98)
		style.border_color = Color(0.95, 0.82, 0.45, 1.0)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.shadow_color = Color(0.95, 0.82, 0.45, 0.2)
		style.shadow_size = 8
		_selected_styles.append(style)


func _create_transition_overlay() -> void:
	_transition_overlay = ColorRect.new()
	_transition_overlay.color = Color.BLACK
	_transition_overlay.modulate.a = 1.0
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_transition_overlay)
	move_child(_transition_overlay, get_child_count() - 1)


func _find_class_cards() -> void:
	_class_cards.clear()
	for child in cards_container.get_children():
		if child is PanelContainer:
			_class_cards.append(child)
			child.gui_input.connect(_on_card_input.bind(child))
	
	if not _class_cards.is_empty():
		_select_card(0)


func _setup_ui() -> void:
	title_label.text = "ВЫБЕРИТЕ КЛАСС"
	subtitle_label.text = "Каждый герой обладает уникальным стилем боя и боевыми навыками"
	play_button.text = "В БОЙ"
	back_button.text = "НАЗАД"

	# Динамически синхронизируем карточки с GameManager.CLASS_DATA
	var class_keys = [
		GameManager.PlayerClass.WARRIOR,
		GameManager.PlayerClass.RANGER,
		GameManager.PlayerClass.MAGE,
		GameManager.PlayerClass.PALADIN
	]

	for i in range(mini(_class_cards.size(), class_keys.size())):
		var card: PanelContainer = _class_cards[i]
		var key = class_keys[i]
		if not GameManager.CLASS_DATA.has(key):
			continue
		var data: Dictionary = GameManager.CLASS_DATA[key]
		var stats: Dictionary = data["stats"]

		var hp_bar = card.find_child("HPBar", true, false) as ProgressBar
		var hp_lbl = card.find_child("HPLabel", true, false) as Label
		var dmg_bar = card.find_child("DamageBar", true, false) as ProgressBar
		var dmg_lbl = card.find_child("DamageLabel", true, false) as Label
		var spd_bar = card.find_child("SpeedBar", true, false) as ProgressBar
		var spd_lbl = card.find_child("SpeedLabel", true, false) as Label

		if hp_bar and hp_lbl:
			hp_bar.max_value = 200.0
			hp_bar.value = float(stats["hp"])
			hp_lbl.text = "HP: %d" % stats["hp"]

		if dmg_bar and dmg_lbl:
			dmg_bar.max_value = 50.0
			dmg_bar.value = float(stats["damage"])
			dmg_lbl.text = "Урон: %d" % stats["damage"]

		if spd_bar and spd_lbl:
			spd_bar.max_value = 350.0
			spd_bar.value = float(stats["speed"])
			spd_lbl.text = "Скорость: %d" % stats["speed"]


func _connect_signals() -> void:
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _start_entrance_animation() -> void:
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 0.0, 0.3)


func _select_card(index: int) -> void:
	if index < 0 or index >= _class_cards.size():
		return
	
	_selected_index = index
	
	for i in range(_class_cards.size()):
		var card = _class_cards[i]
		if i == _selected_index:
			card.add_theme_stylebox_override("panel", _selected_styles[i])
		else:
			card.add_theme_stylebox_override("panel", _normal_style)


func _on_card_input(event: InputEvent, card: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index = _class_cards.find(card)
		if index != -1:
			var snd = get_node_or_null("/root/SoundManager")
			if snd:
				snd.play_ui_click()
			_select_card(index)


func _on_play_pressed() -> void:
	var snd = get_node_or_null("/root/SoundManager")
	if snd:
		snd.play_ui_click()
	GameManager.selected_class = _selected_index as GameManager.PlayerClass
	_transition_out()


func _on_back_pressed() -> void:
	var snd = get_node_or_null("/root/SoundManager")
	if snd:
		snd.play_ui_click()
	_transition_to_menu()


func _transition_out() -> void:
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 1.0, 0.25)
	tween.tween_callback(func(): GameManager.start_new_game())


func _transition_to_menu() -> void:
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 1.0, 0.25)
	tween.tween_callback(func(): GameManager.go_to_menu())
