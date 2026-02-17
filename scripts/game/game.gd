extends Node2D

## Game — основная игровая сцена

@onready var info_label: Label = $CanvasLayer/InfoLabel
@onready var player_container: Node2D = $PlayerContainer


func _ready() -> void:
	var class_data := GameManager.get_selected_class_data()
	info_label.text = "Игра началась!\nКласс: %s\nHP: %d | DMG: %d" % [
		class_data["name"],
		class_data["stats"]["hp"],
		class_data["stats"]["damage"]
	]
	print("Запуск игры. Класс: ", class_data["name"])
	
	# Создаём игрока
	_spawn_player(class_data)


func _spawn_player(class_data: Dictionary) -> void:
	# Загружаем сцену игрока
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = PlayerScene.instantiate()
	player_container.add_child(player)
	
	# Применяем статы класса
	player.get_node("HealthComponent").max_health = class_data["stats"]["hp"]
	player.get_node("HealthComponent").current_health = class_data["stats"]["hp"]
	player.speed = class_data["stats"]["speed"]
	
	# Цвет персонажа — по классу
	player.get_node("Visuals/Body").color = class_data["color"]


func _input(event: InputEvent) -> void:
	# ESC → назад в меню
	if event.is_action_pressed("ui_cancel"):
		GameManager.go_to_menu()
