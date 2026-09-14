# ============================================================================
#  door.gd
#  Дверь-барьер (StaticBody2D)
#  Блокирует проход во время боя, исчезает после зачистки
# ============================================================================
extends StaticBody2D
class_name RoomDoor

## Направление «внутрь» арены (для отталкивания)
var push_direction: Vector2 = Vector2.ZERO

## Размер двери (3 тайла = 192 пикселя)
const DOOR_WIDTH := 192
const DOOR_HEIGHT := 64

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: ColorRect = $Sprite


func _ready() -> void:
	pass


## Анимация и эффект захлопывания ворот арены при входе
func play_appear(play_sound: bool = true) -> void:
	scale = Vector2(1.0, 0.05)
	modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)

	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_door_slam_dust"):
		vfx.spawn_door_slam_dust(global_position, rotation)

	if play_sound:
		var snd = get_node_or_null("/root/SoundManager")
		if snd and snd.has_method("play_door_slam"):
			snd.play_door_slam()


## Анимация и эффект открытия / опускания решетки после зачистки арены
func play_disappear(play_sound: bool = true) -> void:
	# Сразу освобождаем проход для игрока
	if collision_shape and is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", true)

	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_door_slam_dust"):
		vfx.spawn_door_slam_dust(global_position, rotation)

	if play_sound:
		var snd = get_node_or_null("/root/SoundManager")
		if snd and snd.has_method("play_door_open"):
			snd.play_door_open()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale:y", 0.05, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.28)
	tween.chain().tween_callback(queue_free)
