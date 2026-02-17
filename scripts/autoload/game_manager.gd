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

## Сменить сцену
func change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

## Начать новую игру
func start_new_game() -> void:
	current_floor = 1
	change_scene("res://scenes/game/game.tscn")

## Вернуться в меню
func go_to_menu() -> void:
	change_scene("res://scenes/ui/main_menu.tscn")

## Получить данные выбранного класса
func get_selected_class_data() -> Dictionary:
	return CLASS_DATA[selected_class]
