extends Area2D
class_name HitboxComponent
## HitboxComponent (Area2D) — зона нанесения урона.
## При соприкосновении с Hurtbox передает урон и импульс отбрасывания.

signal hit_dealt(target: Hurtbox, damage_amount: int)

@export var damage: int = 20
@export var knockback_force: float = 140.0
@export var attacker: Node2D
## Бить каждую цель не больше одного раза за активацию (одну атаку)
@export var hit_once_per_activation: bool = false

var is_active: bool = true
var _hit_targets: Array[Area2D] = []


func _ready() -> void:
	if not attacker:
		attacker = get_parent() as Node2D
	area_entered.connect(_on_area_entered)


func set_damage(amount: int) -> void:
	damage = amount


func set_active(active: bool) -> void:
	is_active = active
	set_deferred("monitoring", active)
	set_deferred("monitorable", active)
	if active:
		_hit_targets.clear()
		call_deferred("check_overlapping_now")


func check_overlapping_now() -> void:
	if not is_active:
		return
	for area in get_overlapping_areas():
		if area is Area2D:
			_on_area_entered(area as Area2D)


func _on_area_entered(area: Area2D) -> void:
	if not is_active:
		return

	if area.has_method("receive_damage"):
		if hit_once_per_activation:
			if _hit_targets.has(area):
				return
			_hit_targets.append(area)
		var source_attacker: Node2D = attacker if attacker else (get_parent() as Node2D)
		area.receive_damage(damage, knockback_force, global_position, source_attacker)
		if area is Hurtbox:
			hit_dealt.emit(area as Hurtbox, damage)
