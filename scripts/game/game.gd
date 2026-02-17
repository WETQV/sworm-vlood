extends Node2D

## Game — основная игровая сцена

@onready var info_label: Label = $CanvasLayer/InfoLabel
@onready var player_container: Node2D = $PlayerContainer
@onready var enemy_container: Node2D = $EnemyContainer


func _ready() -> void:
	var class_data := GameManager.get_selected_class_data()
	info_label.text = "Класс: %s\nHP: %d | DMG: %d\nWASD — движение, ЛКМ — атака" % [
		class_data["name"],
		class_data["stats"]["hp"],
		class_data["stats"]["damage"]
	]
	
	# Создаём игрока
	_spawn_player(class_data)
	
	# Создаём врагов для теста
	_spawn_enemies()


func _spawn_player(class_data: Dictionary) -> void:
	# СНАЧАЛА загружаем сцену
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	# ПОТОМ создаём экземпляр
	var player: CharacterBody2D = PlayerScene.instantiate()
	
	player.position = Vector2(200, 300)
	player_container.add_child(player)
	
	# Применяем статы класса
	player.get_node("HealthComponent").max_health = class_data["stats"]["hp"]
	player.get_node("HealthComponent").current_health = class_data["stats"]["hp"]
	player.speed = class_data["stats"]["speed"]
	
	# Цвет персонажа — по классу
	player.get_node("Visuals/Body").color = class_data["color"]


func _spawn_enemies() -> void:
	# СНАЧАЛА загружаем
	var SlimeScene: PackedScene = load("res://scenes/enemies/slime.tscn")
	
	# Позиции для врагов
	var positions := [
		Vector2(500, 200),
		Vector2(600, 400),
		Vector2(300, 500)
	]
	
	# Создаём врагов
	for pos in positions:
		var slime = SlimeScene.instantiate()
		slime.position = pos
		enemy_container.add_child(slime)


func _input(event: InputEvent) -> void:
	# ESC → назад в меню
	if event.is_action_pressed("ui_cancel"):
		GameManager.go_to_menu()
