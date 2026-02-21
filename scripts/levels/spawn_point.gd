extends Marker2D
class_name SpawnPoint
## Маркер для спавна объектов в комнате.
## Позволяет легко задавать радиус (размер) моба или объекта.

enum SpawnType {
	ENEMY_SMALL,
	ENEMY_LARGE,
	CHEST,
	SHRINE,
	BOSS,
	PORTAL
}

@export var type: SpawnType = SpawnType.ENEMY_SMALL
## Сколько тайлов занимает объект. Полезно для боссов (например, радиус 2 или 3).
@export var radius_in_tiles: int = 1

func _ready() -> void:
	# Скрываем маркер в игре (он нужен только для редактора и логики спавна)
	visible = false
