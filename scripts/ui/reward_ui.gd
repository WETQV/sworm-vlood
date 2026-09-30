extends CanvasLayer
## Интерфейс наград: выбор дара святилища (не ставит игру на паузу) и сообщения о полученных
## наградах. Выбор отправляется хосту; до подтверждения карточки только блокируются —
## билд меняется лишь по принятому хостом результату (Progression._net_build).

const Catalog := preload("res://scripts/progression/progression_catalog.gd")
const THEME := preload("res://resources/themes/gothic_theme.tres")

var _panel: PanelContainer
var _title: Label
var _cards: VBoxContainer
var _toasts: VBoxContainer
var _offer_key: String = ""
var _buttons: Array[Button] = []


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = THEME
	add_child(root)

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.position = Vector2(-260, 84)
	_toasts.custom_minimum_size = Vector2(520, 0)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_toasts)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.visible = false
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	_title = Label.new()
	_title.text = "Дар святилища"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(0.96, 0.85, 0.52))
	box.add_child(_title)
	var hint := Label.new()
	hint.text = "Выберите один дар (1, 2, 3). Игра не на паузе."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 8)
	box.add_child(_cards)
	var later := Button.new()
	later.text = "Позже (подойдите к святилищу снова)"
	later.pressed.connect(_hide_panel)
	box.add_child(later)

	Progression.offers_received.connect(_on_offers_received)
	Progression.offers_closed.connect(_on_offers_closed)
	Progression.reward_granted.connect(_on_reward_granted)


func _on_offers_received(offer_key: String, offers: Array) -> void:
	_offer_key = offer_key
	for child in _cards.get_children():
		child.queue_free()
	_buttons.clear()
	var build := Progression.get_build(_my_peer())
	for i in offers.size():
		var reward: Dictionary = offers[i]
		var button := Button.new()
		button.text = "%d. %s\n%s" % [i + 1, Catalog.reward_title(build, reward), Catalog.reward_effect(build, reward)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(420, 56)
		button.pressed.connect(_choose.bind(i))
		_cards.add_child(button)
		_buttons.append(button)
	_panel.visible = true


func _choose(index: int) -> void:
	if _offer_key == "" or index >= _buttons.size():
		return
	for button in _buttons:
		button.disabled = true # ждём подтверждения хоста
	Progression.choose_offer(_offer_key, index)


func _on_offers_closed(offer_key: String) -> void:
	if offer_key == _offer_key:
		_hide_panel()
		_offer_key = ""


func _hide_panel() -> void:
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var index := [KEY_1, KEY_2, KEY_3].find(event.keycode)
	if index >= 0 and index < _buttons.size() and not _buttons[index].disabled:
		_choose(index)
		get_viewport().set_input_as_handled()


func _my_peer() -> int:
	return multiplayer.get_unique_id() if NetworkManager.is_online() else 1


## Сообщение о награде: своя — ярко, союзника — приглушённо с именем
func _on_reward_granted(peer_id: int, text: String) -> void:
	var label := Label.new()
	var mine := peer_id == _my_peer()
	var who := "" if mine else "%s: " % NetworkManager.players.get(peer_id, {}).get("name", "Союзник")
	label.text = who + text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16 if mine else 12)
	label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5) if mine else Color(0.75, 0.8, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(label)
	var tween := label.create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)
