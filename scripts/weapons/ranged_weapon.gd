extends BaseWeapon
class_name RangedWeapon
## RangedWeapon — оружие дальнего боя (лук лучника, посох мага).

@export var projectile_scene: PackedScene
@export var projectile_speed: float = 450.0
@export var recoil_distance: float = 6.0

var _initial_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	_initial_pos = position


func attack(aim_direction: Vector2, target_position: Vector2) -> void:
	if not can_attack():
		return
	super.attack(aim_direction, target_position)

	if projectile_scene:
		_spawn_projectile(aim_direction, target_position)

	# Небольшая отдача оружия при выстреле
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", _initial_pos.x - recoil_distance, 0.05).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:x", _initial_pos.x, 0.1).set_ease(Tween.EASE_IN)


func _spawn_projectile(aim_dir: Vector2, _target_pos: Vector2) -> void:
	var projectile: Node2D = projectile_scene.instantiate() as Node2D
	if not projectile:
		return

	# В сети — точка выстрела у владельца, чтобы снаряд у всех летел из одного места
	projectile.global_position = origin_override if origin_override.is_finite() else global_position
	if "direction" in projectile:
		projectile.direction = aim_dir
	if "damage" in projectile:
		projectile.damage = damage
	if "knockback_force" in projectile:
		projectile.knockback_force = knockback_force
	if "attacker" in projectile:
		projectile.attacker = wielder

	# Безопасное добавление снаряда в корень сцены/уровня
	var world_root: Node = get_tree().current_scene
	if not world_root:
		world_root = get_parent()
	world_root.add_child(projectile)
