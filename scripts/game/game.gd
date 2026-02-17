extends Node2D
## Game — тестовая сцена

@onready var info_label: Label = $CanvasLayer/InfoLabel
@onready var player_container: Node2D = $PlayerContainer
@onready var enemy_container: Node2D = $EnemyContainer


func _ready() -> void:
	var class_data := GameManager.get_selected_class_data()
	info_label.text = "Класс: %s | WASD — движение | ЛКМ — атака | ESC — меню" % class_data["name"]

	_spawn_player(class_data)
	_spawn_enemies()


func _spawn_player(class_data: Dictionary) -> void:
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = player_scene.instantiate()

	player.position = Vector2(200, 300)
	player_container.add_child(player)

	# Применяем статы класса
	var health: HealthComponent = player.get_node("HealthComponent")
	health.max_health = class_data["stats"]["hp"]
	player.speed = class_data["stats"]["speed"]
	player.attack_damage = class_data["stats"]["damage"]

	# Цвет тела
	player.get_node("Visuals/Body").color = class_data["color"]


func _spawn_enemies() -> void:
	var slime_scene: PackedScene = load("res://scenes/enemies/slime.tscn")

	var positions := [
		Vector2(500, 200),
		Vector2(600, 400),
		Vector2(350, 500),
	]

	for pos in positions:
		var slime: CharacterBody2D = slime_scene.instantiate()
		slime.position = pos
		enemy_container.add_child(slime)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameManager.go_to_menu()
