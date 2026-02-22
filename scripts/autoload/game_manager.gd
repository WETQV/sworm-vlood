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
		"stats": {"hp": 120, "damage": 25, "speed": 200}
	},
	PlayerClass.RANGER: {
		"name": "Лучник",
		"description": "Дальний бой. Быстрый и ловкий.",
		"color": Color(0.2, 0.7, 0.3),
		"stats": {"hp": 80, "damage": 20, "speed": 260}
	},
	PlayerClass.MAGE: {
		"name": "Маг",
		"description": "Мощная магия. Хрупкий, но смертоносный.",
		"color": Color(0.3, 0.5, 0.9),
		"stats": {"hp": 70, "damage": 35, "speed": 200}
	},
	PlayerClass.PALADIN: {
		"name": "Паладин",
		"description": "Щит и вера. Защищает союзников.",
		"color": Color(0.9, 0.8, 0.2),
		"stats": {"hp": 150, "damage": 15, "speed": 170}
	}
}

## Текущее состояние
var selected_class: PlayerClass = PlayerClass.WARRIOR
var is_multiplayer: bool = false
var current_floor: int = 1
var difficulty_multiplier: float = 1.0

## Сменить сцену
func change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

## Начать новую игру (с первого этажа)
func start_new_game() -> void:
	current_floor = 1
	difficulty_multiplier = 1.0
	change_scene("res://scenes/game/game.tscn")

## Переход на следующий этаж
func next_floor() -> void:
	if current_floor >= 7:
		# ПОБЕДА! Вместо перехода на 8 этаж, выходим в меню или показываем экран
		print("[GameManager] ПОБЕДА! 7 этажей зачищено.")
		# В идеале тут вызвать show_victory_screen(), но для MVP вернемся в меню
		go_to_menu()
		return
		
	current_floor += 1
	difficulty_multiplier = 1.0 + (current_floor - 1) * 0.25 # +25% статов за каждый этаж
	print("[GameManager] Переход на этаж %d, Сложность: %.2f" % [current_floor, difficulty_multiplier])
	get_tree().reload_current_scene()

## Вернуться в меню
func go_to_menu() -> void:
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
