extends Control
## Lobby — экран кооператива по локальной сети.
## 1) Подключение: имя, IP хоста, «Создать сервер» / «Подключиться».
## 2) Лобби: IP для друзей, список игроков с классами, выбор класса, «Начать» (хост).

const CLASS_ORDER := [
	GameManager.PlayerClass.WARRIOR,
	GameManager.PlayerClass.RANGER,
	GameManager.PlayerClass.MAGE,
	GameManager.PlayerClass.PALADIN,
]

@onready var connect_panel: Control = %ConnectPanel
@onready var lobby_panel: Control = %LobbyPanel
@onready var name_edit: LineEdit = %NameEdit
@onready var ip_edit: LineEdit = %IPEdit
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var back_button: Button = %BackButton
@onready var status_label: Label = %StatusLabel
@onready var address_label: Label = %AddressLabel
@onready var players_list: VBoxContainer = %PlayersList
@onready var class_buttons: HBoxContainer = %ClassButtons
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton
@onready var hint_label: Label = %HintLabel

var _class_group := ButtonGroup.new()


func _ready() -> void:
	name_edit.text = SettingsManager.player_name if SettingsManager.player_name != "Player" else ""
	name_edit.placeholder_text = "Имя героя"
	ip_edit.text = "127.0.0.1"

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	for i in CLASS_ORDER.size():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = _class_group
		btn.text = GameManager.CLASS_DATA[CLASS_ORDER[i]]["name"].to_upper()
		btn.custom_minimum_size = Vector2(0, 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_pressed_color", GameManager.CLASS_DATA[CLASS_ORDER[i]]["color"].lightened(0.35))
		btn.pressed.connect(_on_class_pressed.bind(CLASS_ORDER[i]))
		class_buttons.add_child(btn)

	NetworkManager.players_changed.connect(_refresh_players)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# Уже в сети (например, вернулись из меню паузы) — сразу в лобби
	if NetworkManager.is_online():
		_show_lobby()
	else:
		_show_connect()

	if GameManager.lobby_intent == "join":
		ip_edit.grab_focus()
	else:
		name_edit.grab_focus()


func _get_player_name() -> String:
	var n := name_edit.text.strip_edges()
	if n.is_empty():
		n = "Игрок %d" % (randi() % 90 + 10)
	SettingsManager.player_name = n
	if SettingsManager.has_method("save_settings"):
		SettingsManager.save_settings()
	return n


# ── Подключение ──────────────────────────────────────────────────────────────

func _show_connect() -> void:
	connect_panel.visible = true
	lobby_panel.visible = false
	_set_connect_enabled(true)


func _set_connect_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	name_edit.editable = enabled
	ip_edit.editable = enabled


func _on_host_pressed() -> void:
	_click()
	var err := NetworkManager.host_game(_get_player_name(), SettingsManager.port)
	if err != OK:
		status_label.text = "Не удалось создать сервер (порт %d занят?)" % SettingsManager.port
		return
	_show_lobby()


func _on_join_pressed() -> void:
	_click()
	var ip := ip_edit.text.strip_edges()
	if not ip.is_valid_ip_address():
		status_label.text = "Введите IP хоста, например 192.168.1.5"
		return
	var err := NetworkManager.join_game(ip, _get_player_name(), SettingsManager.port)
	if err != OK:
		status_label.text = "Ошибка подключения"
		return
	status_label.text = "Подключение к %s..." % ip
	_set_connect_enabled(false)


func _on_connected() -> void:
	_show_lobby()


func _on_connection_failed() -> void:
	status_label.text = "Не удалось подключиться. Проверьте IP и что хост создал сервер."
	_set_connect_enabled(true)


func _on_back_pressed() -> void:
	_click()
	NetworkManager.leave_game()
	GameManager.go_to_menu()


# ── Лобби ────────────────────────────────────────────────────────────────────

func _show_lobby() -> void:
	connect_panel.visible = false
	lobby_panel.visible = true

	var is_host := multiplayer.is_server()
	start_button.visible = is_host
	if is_host:
		var ips := NetworkManager.get_local_ips()
		var ip_text := ", ".join(ips) if not ips.is_empty() else "127.0.0.1"
		address_label.text = "Ваш IP для друзей: %s   (порт %d)" % [ip_text, SettingsManager.port]
		hint_label.text = "Друзья вводят этот IP в «Подключиться». Все должны быть в одной сети."
	else:
		address_label.text = "Подключено к хосту"
		hint_label.text = "Выберите класс. Игру запускает хост."

	var my_class: int = NetworkManager.get_player_class(NetworkManager.get_my_id())
	var idx := CLASS_ORDER.find(my_class)
	if idx >= 0:
		(class_buttons.get_child(idx) as Button).button_pressed = true
	_refresh_players()


func _refresh_players() -> void:
	if not is_inside_tree():
		return
	for child in players_list.get_children():
		child.queue_free()

	var ids: Array = NetworkManager.players.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = NetworkManager.players[id]
		var cls: int = info["class"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = GameManager.CLASS_DATA[cls]["color"]
		row.add_child(swatch)

		var name_lbl := Label.new()
		name_lbl.text = info["name"] + ("  (хост)" if id == 1 else "") + ("  — вы" if id == NetworkManager.get_my_id() else "")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var class_lbl := Label.new()
		class_lbl.text = GameManager.CLASS_DATA[cls]["name"]
		class_lbl.add_theme_color_override("font_color", GameManager.CLASS_DATA[cls]["color"].lightened(0.3))
		row.add_child(class_lbl)

		players_list.add_child(row)

	if multiplayer.is_server():
		start_button.text = "НАЧАТЬ (%d/%d)" % [ids.size(), NetworkManager.MAX_PLAYERS]


func _on_class_pressed(player_class: int) -> void:
	_click()
	NetworkManager.set_my_class(player_class)


func _on_start_pressed() -> void:
	_click()
	start_button.disabled = true
	NetworkManager.start_game()


func _on_leave_pressed() -> void:
	_click()
	NetworkManager.leave_game()
	_show_connect()
	status_label.text = ""


func _click() -> void:
	var snd = get_node_or_null("/root/SoundManager")
	if snd:
		snd.play_ui_click()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
