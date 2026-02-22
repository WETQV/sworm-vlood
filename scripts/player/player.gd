extends CharacterBody2D
## Player.gd — движение, поворот за мышью, атака с уникальным оружием для каждого класса

@onready var health_component: HealthComponent = $HealthComponent
@onready var player_info: PlayerInfo = $PlayerInfo
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon: Node2D = $WeaponPivot/Weapon
@onready var wall_raycast: RayCast2D = $WeaponPivot/WallRaycast
@onready var attack_area: Area2D = $WeaponPivot/Weapon/AttackArea
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
var _target_rotation: float = 0.0
var _weapon_offset: float = 50.0  # Расстояние оружия от центра игрока (орбита)

# --- Путь к оружию для каждого класса ---
const WEAPON_PATHS: Dictionary = {
	GameManager.PlayerClass.WARRIOR: "res://scenes/player/weapons/warrior_weapon.tscn",
	GameManager.PlayerClass.RANGER: "res://scenes/player/weapons/ranger_weapon.tscn",
	GameManager.PlayerClass.MAGE: "res://scenes/player/weapons/mage_weapon.tscn",
	GameManager.PlayerClass.PALADIN: "res://scenes/player/weapons/paladin_weapon.tscn"
}


func _ready() -> void:
	add_to_group("player")

	# Применяем статы класса и назначаем оружие
	_apply_class_stats()
	_equip_weapon()

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


## Назначить оружие для текущего класса
func _equip_weapon() -> void:
	# Очищаем текущее оружие
	for child in weapon.get_children():
		if child != attack_area:
			child.queue_free()
	
	# Загружаем и добавляем новое оружие
	var class_id = GameManager.selected_class
	if WEAPON_PATHS.has(class_id):
		var weapon_scene = load(WEAPON_PATHS[class_id]).instantiate()
		weapon.add_child(weapon_scene)


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
			player_info.player_class = PlayerInfo.PlayerClass.WARRIOR
			attack_cooldown = 0.4
			attack_knockback = 250.0
		GameManager.PlayerClass.RANGER:
			player_info.player_class = PlayerInfo.PlayerClass.RANGER
			attack_cooldown = 0.5
			attack_knockback = 150.0
		GameManager.PlayerClass.MAGE:
			player_info.player_class = PlayerInfo.PlayerClass.MAGE
			attack_cooldown = 0.6
			attack_knockback = 100.0
		GameManager.PlayerClass.PALADIN:
			player_info.player_class = PlayerInfo.PlayerClass.PALADIN
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

	# --- Поворот оружия за мышью с плавной интерполяцией ---
	var mouse_pos: Vector2 = get_global_mouse_position()
	var dir := mouse_pos - global_position
	_target_rotation = (dir * SettingsManager.mouse_sensitivity).angle()
	
	# Плавный поворот WeaponPivot (орбита оружия)
	weapon_pivot.rotation = lerp_angle(weapon_pivot.rotation, _target_rotation, 0.3)
	
	# --- Проверка стен для оружия ---
	# WallRaycast — дочерний узел WeaponPivot, поэтому его локальная ось X
	# уже смотрит в нужную сторону. Просто задаём длину луча.
	wall_raycast.target_position = Vector2(_weapon_offset, 0.0)

	if wall_raycast.is_colliding():
		var collision_point: Vector2 = wall_raycast.get_collision_point()
		# Считаем расстояние от origin рейкаста, а не от центра игрока
		var distance_to_wall: float = wall_raycast.global_position.distance_to(collision_point) - 20.0
		weapon.position.x = clamp(distance_to_wall, 10.0, _weapon_offset)
	else:
		# move_toward вместо lerp — стабильно на любом FPS
		weapon.position.x = move_toward(weapon.position.x, _weapon_offset, 400.0 * delta)

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
	player_info.activate_danger_zone(global_position, 80.0, "melee_aoe")

	# Включаем зону урона
	attack_area.monitoring = true

	# Анимация оружия — замах и удар
	var tween := create_tween()
	# Замах назад (к игроку)
	tween.tween_property(weapon, "position:x", _weapon_offset - 15.0, 0.08).set_ease(Tween.EASE_OUT)
	# Удар вперёд
	tween.tween_property(weapon, "position:x", _weapon_offset + 20.0, 0.05).set_ease(Tween.EASE_IN)
	# Возврат к орбите
	tween.tween_property(weapon, "position:x", _weapon_offset, 0.1).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(attack_duration).timeout

	attack_area.monitoring = false
	player_info.deactivate_danger_zone()

	await get_tree().create_timer(attack_cooldown - attack_duration).timeout
	_is_attacking = false


## Выстрел стрелой (лучник)
func _shoot_arrow() -> void:
	var arrow = preload("res://scenes/items/arrow.tscn").instantiate()
	# Спавним стрелу из позиции оружия
	var weapon_global_pos = weapon_pivot.global_position + (weapon_pivot.transform.x * _weapon_offset)
	arrow.global_position = weapon_global_pos
	arrow.direction = (get_global_mouse_position() - weapon_global_pos).normalized()
	arrow.damage = attack_damage
	get_parent().add_child(arrow)

	await get_tree().create_timer(attack_cooldown).timeout
	_is_attacking = false


## Огненный шар (маг)
func _shoot_fireball() -> void:
	var target_pos = get_global_mouse_position()
	player_info.activate_danger_zone(target_pos, 120.0, "ranged_aoe")

	var fireball = preload("res://scenes/items/fireball.tscn").instantiate()
	# Спавняем файербол из позиции оружия
	var weapon_global_pos = weapon_pivot.global_position + (weapon_pivot.transform.x * _weapon_offset)
	fireball.global_position = weapon_global_pos
	fireball.direction = (target_pos - weapon_global_pos).normalized()
	fireball.damage = attack_damage
	get_parent().add_child(fireball)

	await get_tree().create_timer(0.3).timeout
	player_info.deactivate_danger_zone()

	await get_tree().create_timer(attack_cooldown - 0.3).timeout
	_is_attacking = false


## Удар щитом (паладин)
func _perform_shield_bash() -> void:
	player_info.activate_danger_zone(global_position, 100.0, "shield")

	# Рывок вперёд
	var dash_dir = (get_global_mouse_position() - global_position).normalized()
	_knockback_velocity = dash_dir * 400.0

	# Удар с анимацией оружия
	attack_area.monitoring = true
	
	var tween := create_tween()
	tween.tween_property(weapon, "position:x", _weapon_offset + 15.0, 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(weapon, "position:x", _weapon_offset, 0.1).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.2).timeout

	attack_area.monitoring = false
	player_info.deactivate_danger_zone()

	await get_tree().create_timer(attack_cooldown - 0.2).timeout
	_is_attacking = false


## Атака попала по врагу
func _on_attack_hit(area: Area2D) -> void:
	# Защита: бьём только врагов
	if not area.get_parent().is_in_group("enemy"):
		return
	
	if area.has_method("receive_damage"):
		area.receive_damage(attack_damage, attack_knockback, global_position, self)
		print("Попал по: ", area.get_parent().name)


## Получил урон
func _on_damage_received(_amount: int, knockback: Vector2) -> void:
	_knockback_velocity = knockback


## HP изменилось
func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current


## Смерть
func _on_died(_killed_by: Node2D) -> void:
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	
	# Скрываем HP бар
	hp_bar.visible = false
