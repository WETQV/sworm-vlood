extends Node
class_name HitboxComponent
## HitboxComponent.gd
## Компонент для нанесения урона
## Привязывается к Area2D и определяет, сколько урона наносит атака

signal hit_detected(target: Node)

@export var damage: int = 25
@export var knockback_force: float = 200.0
@export var cooldown: float = 0.3  # Задержка между ударами

var _can_hit: bool = true
var _area: Area2D = null
var _parent_node: Node = null


func _ready() -> void:
	_area = get_parent() as Area2D
	_parent_node = get_parent()
	if _area:
		_area.area_entered.connect(_on_area_entered)
	else:
		push_warning("HitboxComponent: parent is not Area2D!")


## Включить/выключить возможность удара
func set_hit_enabled(enabled: bool) -> void:
	_can_hit = enabled
	if _area:
		_area.monitoring = enabled
		_area.monitorable = enabled


## Установить урон
func set_damage(amount: int) -> void:
	damage = amount


## Обработка входа в зону поражения
func _on_area_entered(area: Area2D) -> void:
	if not _can_hit:
		return
	
	# Проверяем, что это hurtbox (другой объект)
	if area.has_method("receive_damage"):
		# Наносим урон, передаём свою позицию
		area.receive_damage(damage, knockback_force, _parent_node.global_position, _parent_node)
		hit_detected.emit(area.get_parent())
		
		# Запускаем кулдаун
		_start_cooldown()


## Кулдаун между ударами
func _start_cooldown() -> void:
	_can_hit = false
	await get_tree().create_timer(cooldown).timeout
	_can_hit = true
