extends Camera2D
## Custom Smooth Camera
## To avoid physics jitter, this camera detaches from the parent's transform (top_level = true)
## and manually interpolates its position towards the target in _physics_process.

@export var smooth_speed: float = 12.0

var _target: Node2D

func _ready() -> void:
	# Отвязываемся от трансформации родителя, чтобы двигаться независимо
	set_as_top_level(true)
	
	_target = get_parent() as Node2D
	if _target:
		global_position = _target.global_position


func _physics_process(delta: float) -> void:
	if _target and is_instance_valid(_target):
		# Плавное следование за целью в физическом кадре
		global_position = global_position.lerp(_target.global_position, smooth_speed * delta)
