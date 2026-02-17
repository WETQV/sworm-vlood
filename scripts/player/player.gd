extends CharacterBody2D
## Player.gd — движение, поворот за мышью, атака мечом

@onready var health_component: HealthComponent = $HealthComponent
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: ColorRect = $WeaponPivot/WeaponSprite
@onready var attack_area: Area2D = $WeaponPivot/AttackArea
@onready var body_sprite: ColorRect = $Visuals/Body
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hp_bar: ProgressBar = $HPBar

# --- Настройки ---
@export var speed: float = 200.0
@export var attack_damage: int = 25
@export var attack_knockback: float = 250.0
@export var attack_duration: float = 0.15
@export var attack_cooldown: float = 0.4

# --- Внутреннее состояние ---
var _is_attacking: bool = false
var _knockback_velocity: Vector2 = Vector2.ZERO

# --- Цвета оружия ---
var _weapon_color_idle: Color = Color.LIGHT_GRAY
var _weapon_color_attack: Color = Color.WHITE


func _ready() -> void:
	add_to_group("player")

	# Подключаем сигналы
	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	hurtbox.damage_received.connect(_on_damage_received)
	attack_area.area_entered.connect(_on_attack_hit)

	# Атака выключена по умолчанию
	attack_area.monitoring = false

	# HP бар
	hp_bar.max_value = health_component.max_health
	hp_bar.value = health_component.current_health

	# Цвет оружия
	weapon_sprite.color = _weapon_color_idle


func _physics_process(delta: float) -> void:
	if not health_component.is_alive():
		return

	# --- Движение ---
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_velocity: Vector2 = input_dir.normalized() * speed

	# Отбрасывание затухает
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 800.0 * delta)

	# Итоговая скорость = движение + отбрасывание
	velocity = move_velocity + _knockback_velocity
	move_and_slide()

	# --- Поворот оружия за мышью ---
	var mouse_pos: Vector2 = get_global_mouse_position()
	weapon_pivot.rotation = (mouse_pos - global_position).angle()

	# --- Атака ---
	if Input.is_action_just_pressed("attack") and not _is_attacking:
		_perform_attack()


## Выполнить атаку мечом
func _perform_attack() -> void:
	_is_attacking = true

	# Включаем зону урона
	attack_area.monitoring = true
	weapon_sprite.color = _weapon_color_attack

	# Небольшое "выдвижение" оружия вперёд
	var tween := create_tween()
	tween.tween_property(weapon_sprite, "position:x", 22.0, 0.05)
	tween.tween_property(weapon_sprite, "position:x", 16.0, 0.1)

	await get_tree().create_timer(attack_duration).timeout

	# Выключаем зону урона
	attack_area.monitoring = false
	weapon_sprite.color = _weapon_color_idle

	# Кулдаун до следующей атаки
	await get_tree().create_timer(attack_cooldown - attack_duration).timeout
	_is_attacking = false


## Атака попала по вражескому hurtbox
func _on_attack_hit(area: Area2D) -> void:
	if area.has_method("receive_damage"):
		area.receive_damage(attack_damage, attack_knockback, global_position)
		print("Попал по: ", area.get_parent().name)


## Получил урон
func _on_damage_received(_amount: int, knockback: Vector2) -> void:
	_knockback_velocity = knockback


## HP изменилось
func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current


## Смерть
func _on_died() -> void:
	set_physics_process(false)
	modulate = Color(0.5, 0.5, 0.5, 0.5)
	print("Игрок погиб!")
