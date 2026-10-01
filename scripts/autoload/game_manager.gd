extends Node

## GameManager — глобальный менеджер игры
## Хранит выбранный класс, настройки, состояние между сценами

## Перечисление классов персонажей
enum PlayerClass {
	WARRIOR,
	RANGER,
	MAGE,
	PALADIN
}

## Данные каждого класса для отображения в UI
const CLASS_DATA: Dictionary = {
	PlayerClass.WARRIOR: {
		"name": "Мечник",
		"description": "Ближний бой. Высокий урон и крепкое здоровье.",
		"color": Color(0.8, 0.2, 0.2),
		"stats": {"hp": 150, "damage": 25, "speed": 280}
	},
	PlayerClass.RANGER: {
		"name": "Лучник",
		"description": "Дальний бой. Быстрый и ловкий.",
		"color": Color(0.2, 0.7, 0.3),
		"stats": {"hp": 80, "damage": 20, "speed": 340}
	},
	PlayerClass.MAGE: {
		"name": "Маг",
		"description": "Мощная магия. Хрупкий, но смертоносный.",
		"color": Color(0.3, 0.5, 0.9),
		"stats": {"hp": 70, "damage": 35, "speed": 270}
	},
	PlayerClass.PALADIN: {
		"name": "Паладин",
		"description": "Священный джаггернаут. Молот со взрывной волной, таран щитом при рывке и -20% к урону.",
		"color": Color(0.95, 0.82, 0.25),
		"stats": {"hp": 160, "damage": 32, "speed": 260}
	}
}

## Текущее состояние
var selected_class: PlayerClass = PlayerClass.WARRIOR
var is_multiplayer: bool = false
var current_floor: int = 1
var difficulty_multiplier: float = 1.0
## Seed генерации подземелья. 0 = случайный. В сети хост раздаёт его всем,
## чтобы у всех игроков построилось одинаковое подземелье.
var dungeon_seed: int = 0

const LAST_FLOOR := 7

## Сменить сцену
func change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

## Начать новую игру (с первого этажа)
func start_new_game() -> void:
	# В сети новый забег запускает только хост — сразу у всех
	if NetworkManager.is_online():
		if multiplayer.is_server():
			NetworkManager.start_game()
		return
	start_floor(1, 0)

## Переход на следующий этаж
func next_floor() -> void:
	# Хост: неподобранные предметы и несделанный выбор выдаются, а не пропадают
	Progression.settle_floor()
	if NetworkManager.is_online():
		NetworkManager.start_next_floor()
		return
	start_floor(current_floor + 1, 0)

## Запуск этажа (одиночная игра или по команде хоста)
func start_floor(floor_num: int, seed_value: int) -> void:
	if floor_num > LAST_FLOOR:
		# ПОБЕДА! В идеале тут вызвать show_victory_screen(), но для MVP вернемся в меню
		print("[GameManager] ПОБЕДА! %d этажей зачищено." % LAST_FLOOR)
		go_to_menu()
		return

	current_floor = floor_num
	dungeon_seed = seed_value
	Progression.begin_floor(floor_num)
	# Для логов/интерфейса: множитель здоровья обычных врагов этажа. Сам скейлинг
	# применяется к каждому врагу при появлении — EnemyScaling (здоровье, урон, темп раздельно)
	difficulty_multiplier = EnemyScaling.floor_hp(current_floor)
	print("[GameManager] Этаж %d, Сложность: %.2f" % [current_floor, difficulty_multiplier])
	change_scene("res://scenes/game/game.tscn")

## Вернуться в меню (из сетевой игры — с отключением)
func go_to_menu() -> void:
	NetworkManager.leave_game()
	change_scene("res://scenes/ui/main_menu.tscn")

## Получить данные выбранного класса
func get_selected_class_data() -> Dictionary:
	return CLASS_DATA[selected_class]


## Показать экран смерти
func show_death_screen() -> void:
	# Получаем текущую сцену игры и показываем экран смерти
	var game_scene = get_tree().current_scene
	if game_scene and game_scene.has_node("DeathScreen"):
		var death_screen = game_scene.get_node("DeathScreen")
		death_screen.show()
		# Обновляем номер этажа
		if death_screen.has_method("update_floor"):
			death_screen.update_floor()
