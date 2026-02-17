extends Node
class_name HurtboxComponent
## HurtboxComponent.gd
## Компонент для получения урона
## Привязывается к Area2D и определяет, кто получает урон

signal damage_received(amount: int, knockback_direction: Vector2)

@export var health_component_path: NodePath  # Путь к HealthComponent
@export var invincibility_time: float = 0.5  # Время неуязвимости после получения урона

var _health_component: HealthComponent = null
var _is_invincible: bool = false
var _area: Area2D = null
var _parent_node: Node = null


func _ready() -> void:
	_area = get_parent() as Area2D
	_parent_node = get_parent()
	
	if _area:
		_area.area_entered.connect(_on_area_entered)
	else:
		push_warning("HurtboxComponent: parent is not Area2D!")
	
	# Пытаемся найти HealthComponent на родительском узле
	_health_component = _parent_node.get_node_or_null(health_component_path)
	if not _health_component:
		_health_component = _parent_node.get_node_or_null("HealthComponent")


## Получить урон (вызывается из HitboxComponent)
func receive_damage(amount: int, knockback_force: float, attacker_position: Vector2) -> void:
	if _is_invincible or not _health_component:
		return
	
	# Наносим урон
	_health_component.take_damage(amount)
	
	# Вычисляем направление отбрасывания
	var direction = (_parent_node.global_position - attacker_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT  # Фолбек, если позиции совпадают
	
	# Применяем отбрасывание (если есть CharacterBody2D)
	var character = _parent_node as CharacterBody2D
	if character:
		character.velocity = direction * knockback_force
		character.move_and_slide()
	
	# Сигнал для визуальных эффектов
	damage_received.emit(amount, direction)
	
	# Запускаем неуязвимость
	_start_invincibility()


## Обработка входа в зону (своя зона hurtbox)
func _on_area_entered(_area: Area2D) -> void:
	# Здесь мы получаем урон от чужого hitbox
	# Но эта логика уже обработана в receive_damage
	pass


## Начать период неуязвимости
func _start_invincibility() -> void:
	_is_invincible = true
	await get_tree().create_timer(invincibility_time).timeout
	_is_invincible = false


## Включить/выключить hurtbox
func set_hurtbox_enabled(enabled: bool) -> void:
	if _area:
		_area.monitoring = enabled
		_area.monitorable = enabled


## Проверка — в данный момент неуязвим?
func is_invincible() -> bool:
	return _is_invincible


## Связать с HealthComponent (если не нашёл автоматически)
func set_health_component(component: HealthComponent) -> void:
	_health_component = component
