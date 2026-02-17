extends CharacterBody2D
## Player.gd
## Базовый игрок — движение, поворот за мышью, атака

@onready var health_component: HealthComponent = $HealthComponent
@onready var direction_node: Node2D = $Visuals/Direction
@onready var attack_area: Area2D = $Attack
@onready var hitbox_component: Node = $Attack/HitboxComponent
@onready var visuals: Node2D = $Visuals
@onready var body_color: ColorRect = $Visuals/Body

# Настройки движения
@export var speed: float = 200.0
@export var body_color_normal: Color = Color(0.2, 0.6, 1)  # Синий
@export var body_color_attack: Color = Color(1, 0.3, 0.3)  # Красный при атаке

var _is_attacking: bool = false
var _mouse_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Добавляем в группу "player" для поиска врагами
	add_to_group("player")
	
	# Подключаем сигнал смерти
	if health_component:
		health_component.died.connect(_on_died)
	
	# Подключаем сигнал получения урона для визуала
	var hurtbox = $Hurtbox/HurtboxComponent
	if hurtbox:
		hurtbox.damage_received.connect(_on_damage_received)


func _physics_process(_delta: float) -> void:
	# Если мёртв — ничего не делаем
	if health_component and not health_component.is_alive():
		return
	
	# Движение
	_move()
	
	# Поворот за мышью
	_rotate_toward_mouse()
	
	# Атака
	if Input.is_action_pressed("attack") and not _is_attacking:
		perform_attack()


func _move() -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir.normalized() * speed if input_dir != Vector2.ZERO else Vector2.ZERO
	move_and_slide()


func _rotate_toward_mouse() -> void:
	# Получаем глобальную позицию мыши
	_mouse_position = get_global_mouse_position()
	
	# Вычисляем направление
	var direction = (_mouse_position - global_position).normalized()
	
	# Поворачиваем персонажа
	if direction != Vector2.ZERO:
		direction_node.rotation = direction.angle()


func perform_attack() -> void:
	if _is_attacking:
		return
	
	_is_attacking = true
	
	# Меняем цвет при атаке
	body_color.color = body_color_attack
	
	# Включаем хитбокс
	attack_area.monitoring = true
	
	# Ждём длительность атаки
	await get_tree().create_timer(0.15).timeout
	
	# Выключаем хитбокс
	attack_area.monitoring = false
	
	# Возвращаем цвет
	body_color.color = body_color_normal
	
	_is_attacking = false


func _on_died() -> void:
	# Игрок умер — можно добавить эффекты
	set_physics_process(false)
	modulate = Color(0.5, 0.5, 0.5, 0.5)  # Полупрозрачный


func _on_damage_received(_amount: int, _direction: Vector2) -> void:
	# Мигание при получении урона
	var tween = create_tween()
	tween.tween_property(body_color, "modulate", Color(1, 0, 0, 1), 0.05)
	tween.tween_property(body_color, "modulate", Color.WHITE, 0.1)
