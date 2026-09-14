extends CharacterBody2D
class_name Player
## Player.gd — движение, прицеливание и модульное оружие персонажа.

@onready var health_component: HealthComponent = $HealthComponent
@onready var player_info: PlayerInfo = $PlayerInfo
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_holder: Node2D = $WeaponPivot/Weapon
@onready var wall_raycast: RayCast2D = $WeaponPivot/WallRaycast
@onready var visuals: Node2D = $Visuals
@onready var body_sprite: ColorRect = $Visuals/Body
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hp_bar: ProgressBar = $HPBar

const PALADIN_HAMMER_SCRIPT = preload("res://scripts/weapons/paladin_hammer.gd")

# --- Сигналы ---
signal dash_cooldown_updated(current: float, max_time: float)

# --- Настройки движения ---
@export var speed: float = 280.0
@export var rotation_smoothing: float = 20.0
@export var dash_speed: float = 780.0
@export var dash_duration: float = 0.26
@export var dash_cooldown: float = 0.75
@export var attack_damage: int = 25:
	set(val):
		attack_damage = val
		if current_weapon:
			current_weapon.damage = val

# --- Оружие ---
var current_weapon: BaseWeapon = null
var _weapon_offset: float = 46.0

# --- Внутреннее состояние ---
var _knockback_velocity: Vector2 = Vector2.ZERO
var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO
var _dashed_hit_targets: Array[Node2D] = []

# --- Анимации сочности и визуализации ---
var _anim_time: float = 0.0
var _step_timer: float = 0.0
var _dash_ghost_timer: float = 0.0
var _ground_shadow: Polygon2D = null


func _ready() -> void:
	add_to_group("player")

	_create_ground_shadow()
	_apply_class_stats()
	_setup_weapon()

	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	hurtbox.damage_received.connect(_on_damage_received)

	hp_bar.max_value = health_component.max_health
	hp_bar.value = health_component.current_health


func _create_ground_shadow() -> void:
	if _ground_shadow != null:
		return
	_ground_shadow = Polygon2D.new()
	_ground_shadow.name = "GroundShadow"
	_ground_shadow.color = Color(0.02, 0.02, 0.05, 0.45)
	_ground_shadow.z_index = -1
	var pts := PackedVector2Array()
	var segs := 16
	for i in range(segs):
		var ang := float(i) / float(segs) * TAU
		pts.append(Vector2(cos(ang) * 16.0, sin(ang) * 7.5))
	_ground_shadow.polygon = pts
	_ground_shadow.position = Vector2(0.0, 14.0)
	add_child(_ground_shadow)
	move_child(_ground_shadow, 0)


## Применить статы выбранного класса
func _apply_class_stats() -> void:
	if not GameManager.CLASS_DATA.has(GameManager.selected_class):
		return

	var data: Dictionary = GameManager.CLASS_DATA[GameManager.selected_class]
	var stats: Dictionary = data["stats"]

	speed = float(stats["speed"])
	health_component.max_health = stats["hp"]
	health_component.current_health = stats["hp"]
	body_sprite.color = data["color"]
	if body_sprite.material and body_sprite.material is ShaderMaterial:
		var sm := body_sprite.material as ShaderMaterial
		sm.set_shader_parameter("base_color", data["color"])
		var aura_col: Color = Color(0.96, 0.85, 0.3) if GameManager.selected_class == GameManager.PlayerClass.PALADIN else Color(data["color"]).lightened(0.4)
		sm.set_shader_parameter("aura_color", aura_col)

		var class_idx: int = -1
		match GameManager.selected_class:
			GameManager.PlayerClass.WARRIOR: class_idx = 0
			GameManager.PlayerClass.RANGER:  class_idx = 1
			GameManager.PlayerClass.MAGE:    class_idx = 2
			GameManager.PlayerClass.PALADIN: class_idx = 3
		sm.set_shader_parameter("class_type", class_idx)

	match GameManager.selected_class:
		GameManager.PlayerClass.WARRIOR:
			player_info.player_class = PlayerInfo.PlayerClass.WARRIOR
		GameManager.PlayerClass.RANGER:
			player_info.player_class = PlayerInfo.PlayerClass.RANGER
		GameManager.PlayerClass.MAGE:
			player_info.player_class = PlayerInfo.PlayerClass.MAGE
		GameManager.PlayerClass.PALADIN:
			player_info.player_class = PlayerInfo.PlayerClass.PALADIN

	if GameManager.selected_class == GameManager.PlayerClass.PALADIN:
		hurtbox.damage_reduction = 0.25
	else:
		hurtbox.damage_reduction = 0.0


## Настроить модульное оружие под выбранный класс
func _setup_weapon() -> void:
	for child in weapon_holder.get_children():
		child.queue_free()

	match GameManager.selected_class:
		GameManager.PlayerClass.WARRIOR:
			var weapon := MeleeWeapon.new()
			weapon.name = "WarriorSword"
			weapon.damage = 25
			weapon.knockback_force = 140.0
			weapon.attack_cooldown = 0.35
			weapon_holder.add_child(weapon)
			current_weapon = weapon
			_add_weapon_visual(weapon, "res://scenes/player/weapons/warrior_weapon.tscn")
			_attach_melee_hitbox(weapon, 64)

		GameManager.PlayerClass.PALADIN:
			var weapon = PALADIN_HAMMER_SCRIPT.new()
			weapon.name = "PaladinHammer"
			weapon_holder.add_child(weapon)
			current_weapon = weapon
			_add_weapon_visual(weapon, "res://scenes/player/weapons/paladin_weapon.tscn")
			_attach_melee_hitbox(weapon, 64)

		GameManager.PlayerClass.RANGER:
			var weapon := RangedWeapon.new()
			weapon.name = "RangerBow"
			weapon.damage = 18
			weapon.knockback_force = 110.0
			weapon.attack_cooldown = 0.4
			weapon.projectile_scene = preload("res://scenes/items/arrow.tscn")
			weapon_holder.add_child(weapon)
			current_weapon = weapon
			_add_weapon_visual(weapon, "res://scenes/player/weapons/ranger_weapon.tscn")

		GameManager.PlayerClass.MAGE:
			var weapon := RangedWeapon.new()
			weapon.name = "MageStaff"
			weapon.damage = 32
			weapon.knockback_force = 100.0
			weapon.attack_cooldown = 0.55
			weapon.projectile_scene = preload("res://scenes/items/fireball.tscn")
			weapon_holder.add_child(weapon)
			current_weapon = weapon
			_add_weapon_visual(weapon, "res://scenes/player/weapons/mage_weapon.tscn")


func _add_weapon_visual(weapon_node: Node2D, scene_path: String) -> void:
	if ResourceLoader.exists(scene_path):
		var visual = load(scene_path).instantiate()
		weapon_node.add_child(visual)


func _attach_melee_hitbox(weapon: MeleeWeapon, target_mask: int) -> void:
	var hitbox := HitboxComponent.new()
	hitbox.name = "HitboxComponent"
	hitbox.collision_mask = target_mask
	hitbox.attacker = self

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 28.0
	col.shape = shape
	col.position = Vector2(10.0, 0.0)

	hitbox.add_child(col)
	weapon.add_child(hitbox)
	weapon.hitbox = hitbox


func _physics_process(delta: float) -> void:
	if not health_component.is_alive():
		return

	# --- 0. Кулдаун рывка ---
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer = max(0.0, _dash_cooldown_timer - delta)
		dash_cooldown_updated.emit(dash_cooldown - _dash_cooldown_timer, dash_cooldown)

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var mouse_pos: Vector2 = get_global_mouse_position()
	var aim_vector: Vector2 = mouse_pos - global_position

	# --- 1. Активация рывка / уклонения ---
	var wants_dash: bool = Input.is_action_just_pressed("dash") or Input.is_action_just_pressed("ability")
	if wants_dash and not _is_dashing and _dash_cooldown_timer <= 0.0:
		_start_dash(input_dir, aim_vector)

	_anim_time += delta

	if _is_dashing:
		_dash_timer -= delta
		# Плавная кривая затухания скорости (snappy burst с мягким переходом в бег)
		var dash_progress: float = 1.0 - clampf(_dash_timer / dash_duration, 0.0, 1.0)
		var cur_speed: float = lerpf(dash_speed, speed, dash_progress * dash_progress)
		velocity = _dash_direction * cur_speed
		move_and_slide()

		# Легкое аэродинамическое сжатие только во время рывка
		visuals.scale = Vector2(1.15, 0.88)
		if _ground_shadow:
			_ground_shadow.scale = Vector2(1.25, 0.80)

		# Энергетический след строго ПОЗАДИ персонажа (не внутри него)
		_dash_ghost_timer -= delta
		if _dash_ghost_timer <= 0.0:
			_dash_ghost_timer = 0.05
			if Engine.has_singleton("VFXManager") or get_node_or_null("/root/VFXManager"):
				var trail_pos: Vector2 = global_position - _dash_direction * 22.0
				VFXManager.spawn_dash_ghost_streak(trail_pos, body_sprite.color)

		# Легкий наклон в сторону направления рывка
		var dash_tilt: float = clamp(_dash_direction.x, -1.0, 1.0) * deg_to_rad(9.0)
		visuals.rotation = lerp_angle(visuals.rotation, dash_tilt, 18.0 * delta)

		# Таран священным щитом для Паладина
		if GameManager.selected_class == GameManager.PlayerClass.PALADIN:
			_process_paladin_shield_charge()

		if _dash_timer <= 0.0:
			_is_dashing = false
			hurtbox.is_invincible = false
			_dashed_hit_targets.clear()
			visuals.modulate.a = 1.0
			visuals.scale = Vector2.ONE
			visuals.rotation = 0.0
			if _ground_shadow:
				_ground_shadow.scale = Vector2.ONE
	else:
		# Обычное движение с отзывчивой инерцией (без рывков и тряски спрайта)
		var target_vel: Vector2 = input_dir.normalized() * speed
		velocity = velocity.move_toward(target_vel, 3500.0 * delta)
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 1500.0 * delta)
		velocity += _knockback_velocity
		move_and_slide()

		# Мягкий, естественный наклон корпуса при движении (lean в сторону бега)
		var target_tilt: float = 0.0
		if velocity.length_squared() > 100.0:
			target_tilt = clamp(velocity.x / speed, -1.0, 1.0) * deg_to_rad(6.5)
			visuals.rotation = lerp_angle(visuals.rotation, target_tilt, 12.0 * delta)
		else:
			visuals.rotation = lerp_angle(visuals.rotation, 0.0, 14.0 * delta)

		body_sprite.position = Vector2(-16.0, -16.0)

		if velocity.length_squared() > 100.0:
			visuals.scale = Vector2.ONE
			if _ground_shadow:
				_ground_shadow.scale = Vector2.ONE

			# Аккуратная пыль позади при беге
			_step_timer -= delta
			if _step_timer <= 0.0:
				_step_timer = 0.20
				if Engine.has_singleton("VFXManager") or get_node_or_null("/root/VFXManager"):
					VFXManager.spawn_footstep_dust(global_position + Vector2(0, 14), velocity.normalized())
		else:
			# Очень мягкое естественное дыхание в покое (едва заметное, 1.5%)
			var breath: float = sin(_anim_time * 2.6) * 0.018
			visuals.scale = Vector2(1.0 + breath, 1.0 - breath)
			if _ground_shadow:
				_ground_shadow.scale = Vector2(1.0 + breath, 1.0 + breath)

	# --- 2. Плавный поворот оружия к курсору ---
	if aim_vector.length_squared() > 1.0:
		var target_angle: float = aim_vector.angle()
		weapon_pivot.rotation = lerp_angle(weapon_pivot.rotation, target_angle, 1.0 - exp(-rotation_smoothing * delta))
		weapon_pivot.rotation = wrapf(weapon_pivot.rotation, -PI, PI)

		# Стабильный флип по горизонтальному положению курсора относительно игрока (с гистерезисом)
		if aim_vector.x < -3.0:
			weapon_pivot.scale.y = -1.0
		elif aim_vector.x > 3.0:
			weapon_pivot.scale.y = 1.0

	# --- 3. Динамическая дистанция до стен ---
	wall_raycast.target_position = Vector2(_weapon_offset, 0.0)
	if wall_raycast.is_colliding():
		var collision_pt: Vector2 = wall_raycast.get_collision_point()
		var dist: float = wall_raycast.global_position.distance_to(collision_pt) - 16.0
		weapon_holder.position.x = clamp(dist, 10.0, _weapon_offset)
	else:
		weapon_holder.position.x = move_toward(weapon_holder.position.x, _weapon_offset, 400.0 * delta)

	# --- 4. Атака ---
	if Input.is_action_just_pressed("attack") and current_weapon and current_weapon.can_attack() and not _is_dashing:
		var aim_dir: Vector2 = aim_vector.normalized()
		current_weapon.attack(aim_dir, mouse_pos)


func _start_dash(input_dir: Vector2, aim_vector: Vector2) -> void:
	_is_dashing = true
	_dash_timer = dash_duration
	_dash_cooldown_timer = dash_cooldown
	_dashed_hit_targets.clear()
	_dash_ghost_timer = 0.0

	if input_dir.length_squared() > 0.01:
		_dash_direction = input_dir.normalized()
	elif aim_vector.length_squared() > 0.01:
		_dash_direction = aim_vector.normalized()
	else:
		_dash_direction = Vector2.RIGHT

	hurtbox.set_invincible_for(dash_duration + 0.05)

	# Полупрозрачность и фазирование (четкая индикация неуязвимости без искажения формы)
	visuals.modulate.a = 0.65

	# Запуск аэродинамических скоростных линий (speed lines) и пылевого импульса
	if Engine.has_singleton("VFXManager") or get_node_or_null("/root/VFXManager"):
		var trail_col: Color = body_sprite.color.lightened(0.35)
		trail_col.a = 0.85
		VFXManager.spawn_dash_lines(global_position, _dash_direction, trail_col)

	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_dash"):
		snd.play_dash()

	dash_cooldown_updated.emit(0.0, dash_cooldown)


func _process_paladin_shield_charge() -> void:
	var world_2d: World2D = get_world_2d()
	if not world_2d:
		return
	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	if not space_state:
		return

	var shape := CircleShape2D.new()
	shape.radius = 32.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + _dash_direction * 16.0)
	query.collision_mask = 64
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var hits: Array[Dictionary] = space_state.intersect_shape(query, 16)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider and collider is Hurtbox and not _dashed_hit_targets.has(collider):
			_dashed_hit_targets.append(collider)
			var target_hurtbox := collider as Hurtbox
			target_hurtbox.receive_damage(35, 340.0, global_position, self, true)
			if Engine.has_singleton("VFXManager") or get_node_or_null("/root/VFXManager"):
				VFXManager.spawn_spark(target_hurtbox.global_position, Color(1.0, 0.9, 0.35))


func _on_damage_received(_amount: int, knockback: Vector2) -> void:
	# Ограничение отбрасывания игрока до умеренного импульса
	_knockback_velocity = knockback.limit_length(200.0)

	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_player_hurt"):
		snd.play_player_hurt()


func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current


func _on_died(_killed_by: Node2D) -> void:
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	hp_bar.visible = false
