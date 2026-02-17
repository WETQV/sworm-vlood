extends CharacterBody2D
## Player.gd — движение, поворот за мышью, атака

@onready var health_component: HealthComponent = $HealthComponent
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: ColorRect = $WeaponPivot/WeaponSprite
@onready var attack_area: Area2D = $WeaponPivot/AttackArea
@onready var body_sprite: ColorRect = $Visuals/Body
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hp_bar: ProgressBar = $HPBar

# --- Настройки (по умолчанию для воина) ---
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
	
	# Применяем статы класса
	_apply_class_stats()
	
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


## Применить статы выбранного класса
func _apply_class_stats() -> void:
	var data = GameManager.CLASS_DATA[GameManager.selected_class]
	var stats = data["stats"]
	
	speed = float(stats["speed"])
	attack_damage = stats["damage"]
	health_component.max_health = stats["hp"]
	health_component.current_health = stats["hp"]
	body_sprite.color = data["color"]
	
	# Настройка в зависимости от класса
	match GameManager.selected_class:
		GameManager.PlayerClass.WARRIOR:
			attack_cooldown = 0.4
			attack_knockback = 250.0
		GameManager.PlayerClass.RANGER:
			attack_cooldown = 0.5
			attack_knockback = 150.0
		GameManager.PlayerClass.MAGE:
			attack_cooldown = 0.6
			attack_knockback = 100.0
		GameManager.PlayerClass.PALADIN:
			attack_cooldown = 0.5
			attack_knockback = 300.0


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


## Выполнить атаку
func _perform_attack() -> void:
	_is_attacking = true
	
	match GameManager.selected_class:
		GameManager.PlayerClass.WARRIOR:
			_perform_melee_attack()
		GameManager.PlayerClass.RANGER:
			_shoot_arrow()
		GameManager.PlayerClass.MAGE:
			_shoot_fireball()
		GameManager.PlayerClass.PALADIN:
			_perform_shield_bash()


## Ближняя атака (воин)
func _perform_melee_attack() -> void:
	# Включаем зону урона
	attack_area.monitoring = true
	weapon_sprite.color = _weapon_color_attack

	# Выдвижение оружия
	var tween := create_tween()
	tween.tween_property(weapon_sprite, "position:x", 22.0, 0.05)
	tween.tween_property(weapon_sprite, "position:x", 16.0, 0.1)

	await get_tree().create_timer(attack_duration).timeout

	attack_area.monitoring = false
	weapon_sprite.color = _weapon_color_idle

	await get_tree().create_timer(attack_cooldown - attack_duration).timeout
	_is_attacking = false


## Выстрел стрелой (лучник)
func _shoot_arrow() -> void:
	var arrow = preload("res://scenes/items/arrow.tscn").instantiate()
	arrow.global_position = global_position
	arrow.direction = (get_global_mouse_position() - global_position).normalized()
	arrow.damage = attack_damage
	get_parent().add_child(arrow)
	
	await get_tree().create_timer(attack_cooldown).timeout
	_is_attacking = false


## Огненный шар (маг)
func _shoot_fireball() -> void:
	var fireball = preload("res://scenes/items/fireball.tscn").instantiate()
	fireball.global_position = global_position
	fireball.direction = (get_global_mouse_position() - global_position).normalized()
	fireball.damage = attack_damage
	get_parent().add_child(fireball)
	
	await get_tree().create_timer(attack_cooldown).timeout
	_is_attacking = false


## Удар щитом (паладин)
func _perform_shield_bash() -> void:
	# Рывок вперёд
	var dash_dir = (get_global_mouse_position() - global_position).normalized()
	_knockback_velocity = dash_dir * 400.0
	
	# Удар
	attack_area.monitoring = true
	weapon_sprite.color = _weapon_color_attack
	
	await get_tree().create_timer(0.2).timeout
	
	attack_area.monitoring = false
	weapon_sprite.color = _weapon_color_idle
	
	await get_tree().create_timer(attack_cooldown - 0.2).timeout
	_is_attacking = false


## Атака попала по врагу
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
