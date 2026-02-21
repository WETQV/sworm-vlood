extends Control

## MainMenu — главное меню

@onready var play_button: Button = %PlayButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var title_label: Label = %Title


func _ready() -> void:
	_setup_ui()
	_connect_signals()
	play_button.grab_focus()


func _setup_ui() -> void:
	title_label.text = "DUNGEON CRAWL"
	play_button.text = "⚔️  Играть"
	host_button.text = "🌐  Создать сервер"
	join_button.text = "🔗  Подключиться"
	quit_button.text = "🚪  Выход"
	
	# Пока мультиплеер не готов — прячем кнопки
	host_button.visible = false
	join_button.visible = false


func _connect_signals() -> void:
	play_button.pressed.connect(_on_play_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_play_pressed() -> void:
	GameManager.is_multiplayer = false
	GameManager.change_scene("res://scenes/ui/class_select.tscn")


func _on_host_pressed() -> void:
	GameManager.is_multiplayer = true
	GameManager.change_scene("res://scenes/ui/class_select.tscn")


func _on_join_pressed() -> void:
	GameManager.is_multiplayer = true
	# TODO: показать окно ввода IP
	pass


func _on_settings_pressed() -> void:
	var settings = preload("res://scenes/ui/settings_menu.tscn").instantiate()
	add_child(settings)


func _on_quit_pressed() -> void:
	get_tree().quit()
