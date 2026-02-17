extends CharacterBody2D
## Slime.gd — простой враг, идёт к игроку и бьёт контактом

@onready var health_component: HealthComponent = $HealthComponent
@onready var attack_area: Area2D = $AttackArea
@onready var body_sprite: ColorRect = $Visuals/Body
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hp_bar: ProgressBar = $HPBar

# --- Настройки ---
@export var speed: float = 70.0
@export var contact_damage: int = 10
@export var attack_cooldown: float = 1.0
@export var stop_distance: float = 20.0
@export var detection_range: float = 250.0

# --- Внутреннее состояние ---
var _target: CharacterBody2D = null
var _knockback_velocity: Vector2 = Vector2.ZERO
var _attack_timer: float = 0.0

# --- Цвета ---
var _color_normal: Color = Color("44cc44")
var _color_angry: Color = Color("ff6644")


func _ready() -> void:
	add_to_group("enemy")

	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	hurtbox.damage_received.connect(_on_damage_received)

	# HP бар
	hp_bar.max_value = health_component.max_health
	hp_bar.value = health_component.current_health

	body_sprite.color = _color_normal


func _physics_process(delta: float) -> void:
	if not health_component.is_alive():
		return

	# --- Поиск цели ---
	_find_target()

	# --- Движение ---
	var move_velocity: Vector2 = Vector2.ZERO

	if _target and is_instance_valid(_target):
		var distance: float = global_position.distance_to(_target.global_position)

		if distance <= detection_range:
			body_sprite.color = _color_angry

			if distance > stop_distance:
				var direction: Vector2 = (_target.global_position - global_position).normalized()
				move_velocity = direction * speed
			else:
				move_velocity = Vector2.ZERO
		else:
			body_sprite.color = _color_normal
	else:
		body_sprite.color = _color_normal

	# Отбрасывание затухает
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 600.0 * delta)

	velocity = move_velocity + _knockback_velocity
	move_and_slide()

	# --- Контактный урон ---
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_try_contact_damage()


## Найти ближайшего игрока
func _find_target() -> void:
	if _target and is_instance_valid(_target):
		return

	var players: Array = get_tree().get_nodes_in_group("player")
	var min_dist: float = INF
	for p in players:
		var dist: float = global_position.distance_to(p.global_position)
		if dist < min_dist:
			min_dist = dist
			_target = p


## Попытка нанести контактный урон
func _try_contact_damage() -> void:
	var areas: Array = attack_area.get_overlapping_areas()
	for area in areas:
		if area.has_method("receive_damage"):
			area.receive_damage(contact_damage, 150.0, global_position)
			_attack_timer = attack_cooldown
			print("%s бьёт игрока на %d урона!" % [name, contact_damage])
			return


## Получил урон — отбрасывание
func _on_damage_received(_amount: int, knockback: Vector2) -> void:
	_knockback_velocity = knockback


## HP изменилось
func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current


## Смерть
func _on_died() -> void:
	set_physics_process(false)

	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)

	print("%s убит!" % name)
