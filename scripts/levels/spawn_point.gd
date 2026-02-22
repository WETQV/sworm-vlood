# ============================================================================
#  spawn_point.gd
#  Маркер для спавна объектов внутри комнаты
# ============================================================================
extends Marker2D
class_name SpawnPoint

enum SpawnType {
	ENEMY_SMALL,  ## 0: Обычный враг
	ENEMY_LARGE,  ## 1: Крупный враг
	CHEST,        ## 2: Сундук
	SHRINE,       ## 3: Святилище
	BOSS,         ## 4: Босс
	PORTAL,       ## 5: Портал выхода
}

@export var type: SpawnType = SpawnType.ENEMY_SMALL
@export var radius_in_tiles: int = 1  ## Размер объекта для проверки коллизий

func _ready() -> void:
	visible = false  # Скрыт в игре
