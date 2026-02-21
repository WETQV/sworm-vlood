extends Node2D
## Game — основная игровая сцена
## Запускает генерацию подземелья, потом спавнит игрока в стартовой комнате.

const DUNGEON_SCENE := preload("res://scenes/levels/dungeon_generator.tscn")

@onready var info_label: Label     = $CanvasLayer/InfoLabel
@onready var player_container: Node2D = $PlayerContainer
@onready var enemy_container: Node2D  = $EnemyContainer

var _dungeon: Node2D  # DungeonGenerator instance


func _ready() -> void:
	_generate_dungeon()


func _generate_dungeon() -> void:
	# Создаём и добавляем генератор
	_dungeon = DUNGEON_SCENE.instantiate()
	add_child(_dungeon)

	# Ждём один кадр — генератор выполняется в _ready(),
	# нам нужно дождаться пока все комнаты появятся в дереве
	await get_tree().process_frame

	var class_data := GameManager.get_selected_class_data()
	info_label.text = "Класс: %s | WASD — движение | ЛКМ — атака | ESC — меню" % class_data["name"]

	_spawn_player(class_data)


## Находит стартовую комнату и спавнит игрока в её центре.
## Если стартовой комнаты нет — фоллбэк на центр экрана.
func _spawn_player(class_data: Dictionary) -> void:
	var spawn_pos := Vector2(640, 360)  # Фоллбэк

	# Ищем стартовую комнату среди дочерних нод генератора
	var rooms_root := _dungeon.get_node_or_null("Rooms")
	if rooms_root:
		for room in rooms_root.get_children():
			if room.get("room_type") == 0:  # RoomType.START = 0
				# room.position уже в пикселях (grid_pos * 64)
				# room_size — в тайлах, поэтому * 64 / 2 = центр
				var room_size: Vector2i = room.room_size
				spawn_pos = room.position + Vector2(room_size.x * 32.0, room_size.y * 32.0)
				break

	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: CharacterBody2D  = player_scene.instantiate()

	player.position = spawn_pos
	player_container.add_child(player)

	# Настройка камеры для корректной работы с интерполяцией
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	if cam:
		cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS

	# Применяем статы класса
	var health: HealthComponent = player.get_node("HealthComponent")
	health.max_health = class_data["stats"]["hp"]
	player.speed         = class_data["stats"]["speed"]
	player.attack_damage = class_data["stats"]["damage"]

	# Цвет тела
	player.get_node("Visuals/Body").color = class_data["color"]


## Тестовый спавн врагов удалён — враги будут спавниться
## через систему комнат (когда игрок входит в FIGHT-комнату).
## Пока для теста можно раскомментировать:
#func _spawn_enemies() -> void:
#	var slime_scene = load("res://scenes/enemies/slime.tscn")
#	for pos in [Vector2(500,200), Vector2(600,400), Vector2(350,500)]:
#		var slime = slime_scene.instantiate()
#		slime.position = pos
#		enemy_container.add_child(slime)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameManager.go_to_menu()
