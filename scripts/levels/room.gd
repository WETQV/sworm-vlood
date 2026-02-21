extends Node2D
## Room — базовый класс для всех комнат подземелья.
## Хранит тип, размер, точки спавна врагов/лута и слоты дверей (проходов).

# --- Тип комнаты ---
enum RoomType {
	START,   # Стартовая комната (игроки появляются тут)
	FIGHT,   # Боевая комната (враги)
	CHEST,   # Комната с сундуком / лутом
	SHRINE,  # Святилище (усиление, исцеление)
	BOSS,    # Арена с боссом
}

# --- Экспортируемые параметры ---
@export var room_type: RoomType = RoomType.FIGHT
## Размер комнаты в тайлах (ширина x высота)
@export var room_size: Vector2i = Vector2i(15, 12)

# --- Данные, заполняемые при генерации ---

## Позиции (в тайлах) для спавна врагов или лута
var spawn_points: Array[Vector2i] = []

## Слоты, с которых может «выходить» коридор (в тайлах, в системе генератора)
## Заполняется DungeonGenerator после размещения комнаты
var door_slots: Array[Vector2i] = []

## Позиция комнаты в тайловой сетке генератора (левый верхний угол)
var grid_position: Vector2i = Vector2i.ZERO

## Уникальный id комнаты (задаётся генератором)
var room_id: int = -1

# --- Ноды тайловых слоёв (подключаются в сценах-наследниках) ---
@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var wall_layer: TileMapLayer = $WallLayer
@onready var spawn_root: Node2D   = $SpawnPoints


func _ready() -> void:
	_build_room()
	_collect_spawn_points()


## Строит тайловую геометрию комнаты (пол + стены по периметру).
## Переопределяй в наследниках для добавления колонн, препятствий и т.д.
func _build_room() -> void:
	var w := room_size.x
	var h := room_size.y

	for x in range(w):
		for y in range(h):
			var coord := Vector2i(x, y)
			# Стена — периметр
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				wall_layer.set_cell(coord, 0, Vector2i(1, 0))  # source_id=0, atlas_coord стены
			else:
				floor_layer.set_cell(coord, 0, Vector2i(0, 0)) # atlas_coord пола


## Собирает все Marker2D из SpawnPoints в массив spawn_points.
func _collect_spawn_points() -> void:
	spawn_points.clear()
	for child in spawn_root.get_children():
		if child is Marker2D:
			# Конвертируем мировую позицию в тайловую
			spawn_points.append(floor_layer.local_to_map(child.position))


## Возвращает Rect2i этой комнаты в тайловой сетке генератора.
func get_grid_rect() -> Rect2i:
	return Rect2i(grid_position, room_size)


## Возвращает центр комнаты в тайловой сетке.
func get_grid_center() -> Vector2i:
	return grid_position + room_size / 2


## Возвращает мировую позицию центра комнаты.
func get_world_center() -> Vector2:
	if floor_layer:
		return floor_layer.map_to_local(get_grid_center())
	return Vector2.ZERO
