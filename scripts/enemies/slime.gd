extends CharacterBody2D
## Slime.gd
## Простой враг — идёт к игроку и атакует

@onready var health_component: HealthComponent = $HealthComponent
@onready var attack_area: Area2D = $Attack
@onready var body_color: ColorRect = $Visuals/Body
@onready var body: ColorRect = $Visuals/Body

# Настройки
@export var speed: float = 80.0
@export var detection_range: float = 200.0
@export var attack_range: float = 35.0
@export var attack_cooldown: float = 1.5

var _player: Node2D = null
var _can_attack: bool = true
var _is_moving: bool = false


func _ready() -> void:
	# Подключаем сигнал смерти
	if health_component:
		health_component.died.connect(_on_died)
	
	# Подключаем сигнал получения урона
	var hurtbox = $Hurtbox/HurtboxComponent
	if hurtbox:
		hurtbox.damage_received.connect(_on_damage_received)
	
	# Ищем игрока
	_get_player_reference()


func _get_player_reference() -> void:
	# Ищем игрока по группе
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
	else:
		# Пробуем найти по имени
		_player = get_tree().get_first_node_in_group("player")


func _physics_process(_delta: float) -> void:
	if health_component and not health_component.is_alive():
		return
	
	if not _player:
		_get_player_reference()
		return
	
	# Проверяем расстояние до игрока
	var distance_to_player = global_position.distance_to(_player.global_position)
	
	if distance_to_player <= attack_range:
		# Атакуем, если в зоне
		if _can_attack:
			perform_attack()
	elif distance_to_player <= detection_range:
		# Преследуем игрока
		_move_toward_player()
	else:
		# Останавливаемся
		_is_moving = false


func _move_toward_player() -> void:
	if not _player:
		return
	
	var direction = (_player.global_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()
	
	# Поворачиваем лицом к игроку (через визуал)
	if direction.x < 0:
		scale.x = -1
	else:
		scale.x = 1
	
	_is_moving = true


func perform_attack() -> void:
	if not _can_attack:
		return
	
	_can_attack = false
	
	# Включаем атаку
	attack_area.monitoring = true
	
	# Меняем цвет
	body_color.color = Color(0.8, 0.3, 0.3)
	
	# Ждём немного
	await get_tree().create_timer(0.2).timeout
	
	# Выключаем
	attack_area.monitoring = false
	body_color.color = Color(0.3, 0.8, 0.3)
	
	# Кулдаун
	await get_tree().create_timer(attack_cooldown - 0.2).timeout
	_can_attack = true


func _on_died() -> void:
	set_physics_process(false)
	
	# Эффект смерти — исчезаем
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


func _on_damage_received(_amount: int, _direction: Vector2) -> void:
	# Мигание при уроне
	var tween = create_tween()
	tween.tween_property(body, "modulate", Color(1, 0, 0, 1), 0.05)
	tween.tween_property(body, "modulate", Color.WHITE, 0.1)
