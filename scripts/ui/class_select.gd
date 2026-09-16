extends Control

## ClassSelect — экран выбора класса в органическом/ликвид стиле
## Стиль: Sworm Vlood Liquid Forms

const WARRIOR_WEAPON = preload("res://scenes/player/weapons/warrior_weapon.tscn")
const RANGER_WEAPON = preload("res://scenes/player/weapons/ranger_weapon.tscn")
const MAGE_WEAPON = preload("res://scenes/player/weapons/mage_weapon.tscn")
const PALADIN_WEAPON = preload("res://scenes/player/weapons/paladin_weapon.tscn")

@onready var cards_container: HBoxContainer = $CenterContainer/VBoxContainer/CardsContainer
@onready var play_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/PlayButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/BackButton
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleSection/Title
@onready var subtitle_label: Label = $CenterContainer/VBoxContainer/TitleSection/Subtitle

var _class_cards: Array[PanelContainer] = []
var _selected_index: int = 0

# Конфигурация оружия внутри сферических витрин
const WEAPON_CONFIGS: Array[Dictionary] = [
	{
		"scene": WARRIOR_WEAPON,
		"rot": -40.0,
		"scale": 1.35,
		"offset": Vector2(-3.0, 0.0),
		"color": Color(0.88, 0.22, 0.25)
	},
	{
		"scene": RANGER_WEAPON,
		"rot": -15.0,
		"scale": 1.15,
		"offset": Vector2(-2.0, 0.0),
		"color": Color(0.22, 0.82, 0.45)
	},
	{
		"scene": MAGE_WEAPON,
		"rot": -40.0,
		"scale": 1.35,
		"offset": Vector2(-3.0, 0.0),
		"color": Color(0.35, 0.55, 0.95)
	},
	{
		"scene": PALADIN_WEAPON,
		"rot": 0.0,
		"scale": 1.6,
		"offset": Vector2(-3.0, 0.0),
		"color": Color(0.95, 0.82, 0.25)
	}
]

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
			if child.has_signal("card_clicked"):
				child.card_clicked.connect(_on_card_clicked)
			else:
				child.gui_input.connect(_on_card_input.bind(child))
	
	if not _class_cards.is_empty():
		_select_card(0)


func _setup_ui() -> void:
	title_label.text = "ВЫБЕРИТЕ КЛАСС"
	subtitle_label.text = "Каждый герой обладает уникальным стилем боя и боевыми навыками"
	play_button.text = "В БОЙ"
	back_button.text = "НАЗАД"

	var class_keys = [
		GameManager.PlayerClass.WARRIOR,
		GameManager.PlayerClass.RANGER,
		GameManager.PlayerClass.MAGE,
		GameManager.PlayerClass.PALADIN
	]

	for i in range(mini(_class_cards.size(), class_keys.size())):
		var card: PanelContainer = _class_cards[i]
		
		# Оружие в сфере
		if card.has_method("setup_weapon") and i < WEAPON_CONFIGS.size():
			var cfg = WEAPON_CONFIGS[i]
			card.setup_weapon(cfg["scene"], cfg["rot"], cfg["scale"], cfg["offset"], cfg["color"])
		
		var key = class_keys[i]
		if not GameManager.CLASS_DATA.has(key):
			continue
		var data: Dictionary = GameManager.CLASS_DATA[key]
		var stats: Dictionary = data["stats"]

		var hp_val = float(stats["hp"])
		var dmg_val = float(stats["damage"])
		var spd_val = float(stats["speed"])

		if card.has_method("update_stat_bar"):
			card.update_stat_bar("HPBar", hp_val, 200.0)
			card.update_stat_bar("DamageBar", dmg_val, 50.0)
			card.update_stat_bar("SpeedBar", spd_val, 350.0)

		var hp_lbl = card.find_child("HPLabel", true, false) as Label
		var dmg_lbl = card.find_child("DamageLabel", true, false) as Label
		var spd_lbl = card.find_child("SpeedLabel", true, false) as Label

		if hp_lbl:
			hp_lbl.text = "HP: %d" % stats["hp"]
		if dmg_lbl:
			dmg_lbl.text = "Урон: %d" % stats["damage"]
		if spd_lbl:
			spd_lbl.text = "Скорость: %d" % stats["speed"]


func _connect_signals() -> void:
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_setup_button_hover(play_button)
	_setup_button_hover(back_button)


func _setup_button_hover(btn: Button) -> void:
	btn.pivot_offset = Vector2(90.0, 24.0)
	var on_focus = func():
		var snd = get_node_or_null("/root/SoundManager")
		if snd and snd.has_method("play_ui_hover"):
			snd.play_ui_hover()
		var t = create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.16)
	
	var on_unfocus = func():
		var t = create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.16)

	btn.mouse_entered.connect(on_focus)
	btn.focus_entered.connect(on_focus)
	btn.mouse_exited.connect(on_unfocus)
	btn.focus_exited.connect(on_unfocus)


func _start_entrance_animation() -> void:
	var tween = create_tween()
	tween.tween_property(_transition_overlay, "modulate:a", 0.0, 0.3)


func _select_card(index: int) -> void:
	if index < 0 or index >= _class_cards.size():
		return
	
	_selected_index = index
	
	for i in range(_class_cards.size()):
		var card = _class_cards[i]
		var is_sel = (i == _selected_index)
		if card.has_method("set_selected"):
			card.set_selected(is_sel)


func _on_card_clicked(card: PanelContainer) -> void:
	var index = _class_cards.find(card)
	if index != -1 and index != _selected_index:
		var snd = get_node_or_null("/root/SoundManager")
		if snd:
			snd.play_ui_click()
		_select_card(index)


func _on_card_input(event: InputEvent, card: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_card_clicked(card)


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		var count = _class_cards.size()
		if count > 0:
			var next = (_selected_index - 1 + count) % count
			var snd = get_node_or_null("/root/SoundManager")
			if snd: snd.play_ui_click()
			_select_card(next)
			var focused = get_viewport().gui_get_focus_owner()
			if focused:
				focused.release_focus()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		var count = _class_cards.size()
		if count > 0:
			var next = (_selected_index + 1) % count
			var snd = get_node_or_null("/root/SoundManager")
			if snd: snd.play_ui_click()
			_select_card(next)
			var focused = get_viewport().gui_get_focus_owner()
			if focused:
				focused.release_focus()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if not play_button.has_focus() and not back_button.has_focus():
			play_button.grab_focus()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if play_button.has_focus() or back_button.has_focus():
			play_button.release_focus()
			back_button.release_focus()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if not play_button.has_focus() and not back_button.has_focus():
			_on_play_pressed()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
