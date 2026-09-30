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
## Сеть (для замеров): владелец отправил действие / наблюдатель проиграл чужое действие.
## origin_offset — расстояние от показанного тела до точки, где действие сделал владелец.
signal action_sent(kind: String, seq: int)
signal remote_action_played(kind: String, seq: int, origin_offset: float)

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

# --- Сеть ---
## peer_id игрока-владельца (1 в одиночной игре). Задаётся до добавления в дерево.
var peer_id: int = 1
## Класс этого персонажа (у каждого игрока свой). -1 = взять из GameManager.
var player_class: int = -1

# --- Сетевая модель движения (см. docs/network_contract.md) ---
## Частота снимков движения владельца, Гц
const NET_SEND_HZ := 60.0
## Снимок владельца: [seq, epoch, x, y, vx, vy, aim_angle, flags]. flags: 1 = рывок.
## Владелец пишет, остальные получают через NetSync и кладут в буфер интерполяции.
var net_state: PackedFloat32Array = PackedFloat32Array():
	set(value):
		net_state = value
		if is_inside_tree() and not is_local() and value.size() >= 8:
			_on_net_state(value)
## Номер «эпохи» позиции: растёт при каждом телепорте от хоста. Снимки старой эпохи
## (отправленные до телепорта) отбрасываются — персонаж не откатывается назад.
var teleport_epoch: int = 0
## Тестовый хук: если задано — прицел сюда вместо курсора мыши (боты в tests/net)
var aim_override: Vector2 = Vector2.INF
var _net_seq: int = 0
var _interp := NetInterpolator.new()
var _net_aim: float = 0.0
var _last_net_pos: Vector2 = Vector2.INF   # хост: последняя принятая позиция владельца
var _last_net_seq: int = -1
# Боевые запросы: порядковые номера и время последнего принятого действия (проверка на хосте)
var _action_seq: int = 0
var _last_attack_seq: int = 0
var _last_dash_seq: int = 0
var _last_attack_msec: int = -100000
var _last_dash_msec: int = -100000

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

# --- Прокачка забега (Progression): базовые значения оружия и эффекты навыков ---
const BASE_DASH_COOLDOWN := 0.75
const BASE_MELEE_RADIUS := 28.0
## Запас окна «Выпада дуэлянта» у хоста для чужого героя: рывок и удар приходят по сети
const DUELIST_NET_LEEWAY := 0.15
var _base_attack_cooldown: float = 0.4
var _base_knockback: float = 140.0
var _duelist_bonus: float = 0.0
var _last_dash_start_msec: int = -100000
## Паладин «Бастион»: снижение урона союзникам рядом (доля его собственного бонуса)
var bastion_aura: float = 0.0


func _ready() -> void:
	add_to_group("player")
	if player_class < 0:
		player_class = GameManager.selected_class

	_create_ground_shadow()
	_apply_class_stats()
	_setup_weapon()
	_setup_network()
	_interp.tick_ms = 1000.0 / Engine.physics_ticks_per_second
	_interp.send_interval_ms = 1000.0 / NET_SEND_HZ
	_interp.reset(global_position, 0)

	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	hurtbox.damage_received.connect(_on_damage_received)

	hp_bar.max_value = health_component.max_health
	hp_bar.value = health_component.current_health


## Этим персонажем управляет игрок за этим компьютером
func is_local() -> bool:
	return not NetworkManager.is_online() or peer_id == multiplayer.get_unique_id()


## Сеть (вызывает спавнер ДО добавления в дерево): синхронизатор позиции и authority владельца.
## Если менять authority в _ready, Godot не успевает зарегистрировать синхронизатор.
func prepare_network(owner_peer_id: int) -> void:
	peer_id = owner_peer_id
	# Один компактный снимок (net_state) вместо позиции/скорости/визуальных свойств каждый кадр.
	# ALWAYS = ненадёжная доставка: потерянный снимок заменяет следующий, старые отбрасываются по seq.
	var config := SceneReplicationConfig.new()
	var path := NodePath(":net_state")
	config.add_property(path)
	config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "NetSync"
	sync.root_path = NodePath("..")
	sync.replication_config = config
	sync.replication_interval = 1.0 / NET_SEND_HZ
	add_child(sync)
	set_multiplayer_authority(peer_id) # рекурсивно, вместе с NetSync


## Хост переносит персонажа на каждой машине, включая его владельца.
func teleport_to_position(target: Vector2) -> void:
	if not NetworkManager.is_authority():
		return
	if NetworkManager.is_online():
		_net_teleport.rpc(target, teleport_epoch + 1)
	else:
		_apply_teleport(target)


@rpc("any_peer", "call_local", "reliable")
func _net_teleport(target: Vector2, new_epoch: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if new_epoch <= teleport_epoch:
		return # повтор или устаревший телепорт
	teleport_epoch = new_epoch
	_apply_teleport(target)
	if not is_local():
		_interp.reset(target, new_epoch)
		_last_net_pos = target
		_last_net_seq = -1


func _apply_teleport(target: Vector2) -> void:
	global_position = target
	velocity = Vector2.ZERO
	_knockback_velocity = Vector2.ZERO
	reset_physics_interpolation()
	if is_local():
		var cam := get_node_or_null("Camera2D") as Camera2D
		if cam:
			cam.global_position = target
			cam.reset_physics_interpolation()


## Сетевая настройка: камера только у своего персонажа, имя над головой
func _setup_network() -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.enabled = is_local()

	if not NetworkManager.is_online():
		return

	# Имя игрока над головой
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	var label := Label.new()
	label.name = "NameLabel"
	label.text = info.get("name", "Игрок")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75) if is_local() else Color(0.8, 0.85, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(120, 16)
	label.position = Vector2(-60, -44)
	add_child(label)


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
	if not GameManager.CLASS_DATA.has(player_class):
		return

	var data: Dictionary = GameManager.CLASS_DATA[player_class]
	var stats: Dictionary = data["stats"]

	speed = float(stats["speed"])
	health_component.max_health = stats["hp"]
	health_component.current_health = stats["hp"]
	body_sprite.color = data["color"]
	if body_sprite.material and body_sprite.material is ShaderMaterial:
		# Своя копия материала: иначе все персонажи в кооперативе получат цвет последнего
		body_sprite.material = body_sprite.material.duplicate()
		var sm := body_sprite.material as ShaderMaterial
		sm.set_shader_parameter("base_color", data["color"])
		var aura_col: Color = Color(0.96, 0.85, 0.3) if player_class == GameManager.PlayerClass.PALADIN else Color(data["color"]).lightened(0.4)
		sm.set_shader_parameter("aura_color", aura_col)

		var class_idx: int = -1
		match player_class:
			GameManager.PlayerClass.WARRIOR: class_idx = 0
			GameManager.PlayerClass.RANGER:  class_idx = 1
			GameManager.PlayerClass.MAGE:    class_idx = 2
			GameManager.PlayerClass.PALADIN: class_idx = 3
		sm.set_shader_parameter("class_type", class_idx)

	match player_class:
		GameManager.PlayerClass.WARRIOR:
			player_info.player_class = PlayerInfo.PlayerClass.WARRIOR
		GameManager.PlayerClass.RANGER:
			player_info.player_class = PlayerInfo.PlayerClass.RANGER
		GameManager.PlayerClass.MAGE:
			player_info.player_class = PlayerInfo.PlayerClass.MAGE
		GameManager.PlayerClass.PALADIN:
			player_info.player_class = PlayerInfo.PlayerClass.PALADIN

	if player_class == GameManager.PlayerClass.PALADIN:
		hurtbox.damage_reduction = 0.25
	else:
		hurtbox.damage_reduction = 0.0


## Настроить модульное оружие под выбранный класс
func _setup_weapon() -> void:
	for child in weapon_holder.get_children():
		child.queue_free()

	match player_class:
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

	if current_weapon:
		current_weapon.wielder = self
		_base_attack_cooldown = current_weapon.attack_cooldown
		_base_knockback = current_weapon.knockback_force


## Пересчитать характеристики из базовых значений класса и билда забега.
## fresh — новый герой (полное здоровье); gained — билд вырос, прибавку максимума лечим (хост).
## Всегда от базы: повторный вызов не умножает статы второй раз.
func apply_build(build: Dictionary, fresh: bool = false, gained: bool = false) -> void:
	if not GameManager.CLASS_DATA.has(player_class) or not current_weapon:
		return
	var base: Dictionary = GameManager.CLASS_DATA[player_class]["stats"]
	var vitality := ProgressionCatalog.stacks(build, "vitality")
	var tempo := ProgressionCatalog.stacks(build, "tempo")
	var agility := ProgressionCatalog.stacks(build, "agility")

	var old_max := health_component.max_health
	var new_max := int(round(float(base["hp"]) * (1.0 + ProgressionCatalog.UPGRADES["vitality"]["hp"] * vitality)))
	health_component.max_health = new_max
	if fresh:
		health_component.current_health = new_max
	elif gained and new_max > old_max and NetworkManager.is_authority():
		health_component.heal(new_max - old_max) # рассылает здоровье клиентам
	health_component.current_health = mini(health_component.current_health, new_max)
	health_component.health_changed.emit(health_component.current_health, new_max)

	speed = float(base["speed"]) * (1.0 + ProgressionCatalog.UPGRADES["agility"]["speed"] * agility)
	dash_cooldown = BASE_DASH_COOLDOWN * (1.0 - ProgressionCatalog.UPGRADES["agility"]["dash"] * agility)
	attack_damage = int(base["damage"])
	current_weapon.attack_cooldown = _base_attack_cooldown * pow(ProgressionCatalog.UPGRADES["tempo"]["cooldown"], tempo)
	current_weapon.knockback_force = _base_knockback

	_duelist_bonus = 0.0
	bastion_aura = 0.0
	match player_class:
		GameManager.PlayerClass.WARRIOR:
			var cleave := ProgressionCatalog.rank(build, "cleave")
			var melee := current_weapon as MeleeWeapon
			var hit_shape := melee.hitbox.get_child(0) as CollisionShape2D if melee and melee.hitbox else null
			if hit_shape and hit_shape.shape is CircleShape2D:
				(hit_shape.shape as CircleShape2D).radius = BASE_MELEE_RADIUS * ProgressionCatalog.SKILLS["cleave"]["radius"][cleave]
			current_weapon.knockback_force = _base_knockback * ProgressionCatalog.SKILLS["cleave"]["knockback"][cleave]
			_duelist_bonus = ProgressionCatalog.SKILLS["duelist"]["bonus"][ProgressionCatalog.rank(build, "duelist")]
		GameManager.PlayerClass.RANGER:
			var ricochet: Dictionary = ProgressionCatalog.SKILLS["ricochet"]
			(current_weapon as RangedWeapon).projectile_mods = {
				"pierce": ricochet["pierce"][ProgressionCatalog.rank(build, "ricochet")], "pierce_damage": ricochet["pierce_damage"],
				"sniper": ProgressionCatalog.SKILLS["sniper"]["bonus"][ProgressionCatalog.rank(build, "sniper")]}
		GameManager.PlayerClass.MAGE:
			var blast: Dictionary = ProgressionCatalog.SKILLS["blast"]
			var burn: Dictionary = ProgressionCatalog.SKILLS["burn"]
			var burn_rank := ProgressionCatalog.rank(build, "burn")
			(current_weapon as RangedWeapon).projectile_mods = {
				"blast_radius": blast["radius"][ProgressionCatalog.rank(build, "blast")], "splash": blast["splash"],
				"burn_tick": burn["tick"][burn_rank], "burn_duration": burn["duration"],
				"burn_interval": burn["interval"], "boss_factor": burn["boss_factor"]}
		GameManager.PlayerClass.PALADIN:
			var bastion: Dictionary = ProgressionCatalog.SKILLS["bastion"]
			var reduction: float = bastion["reduction"][ProgressionCatalog.rank(build, "bastion")]
			hurtbox.damage_reduction = 0.25 + reduction
			bastion_aura = reduction * bastion["aura_share"]
			var wave: float = ProgressionCatalog.SKILLS["thunder"]["wave"][ProgressionCatalog.rank(build, "thunder")]
			var hammer := current_weapon as PaladinHammer
			hammer.shockwave_radius = PaladinHammer.BASE_SHOCKWAVE_RADIUS * wave
			hammer.shockwave_damage = int(round(PaladinHammer.BASE_SHOCKWAVE_DAMAGE * wave))


## «Выпад дуэлянта»: урон удара сразу после рывка (считается там же, где атака —
## у хоста это определяет итоговый урон; у остальных только отображение)
func _prepare_attack_damage(remote: bool) -> void:
	current_weapon.damage = attack_damage
	if _duelist_bonus <= 0.0:
		return
	var window: float = dash_duration + ProgressionCatalog.SKILLS["duelist"]["window"] + (DUELIST_NET_LEEWAY if remote else 0.0)
	if Time.get_ticks_msec() - _last_dash_start_msec <= window * 1000.0:
		current_weapon.damage = int(round(attack_damage * (1.0 + _duelist_bonus)))
		if get_node_or_null("/root/VFXManager"):
			VFXManager.spawn_spark(current_weapon.global_position, Color(1.0, 0.85, 0.4))


func _add_weapon_visual(weapon_node: Node2D, scene_path: String) -> void:
	if ResourceLoader.exists(scene_path):
		var visual = load(scene_path).instantiate()
		weapon_node.add_child(visual)


func _attach_melee_hitbox(weapon: MeleeWeapon, target_mask: int) -> void:
	var hitbox := HitboxComponent.new()
	hitbox.name = "HitboxComponent"
	hitbox.collision_mask = target_mask | (32 if NetworkManager.friendly_fire else 0)
	hitbox.attacker = self
	# Одна цель — одно попадание за удар: иначе за окно удара (0.12 с) срабатывали и вход в зону,
	# и повторная проверка перекрытий, и урон удваивался (его маскировали только i-frames цели)
	hitbox.hit_once_per_activation = true
	# Хитбокс создаётся после _ready оружия, поэтому оружие не успевало его выключить:
	# до первой атаки меч/щит наносили 20 урона всему, чего касались
	hitbox.is_active = false
	hitbox.monitoring = false
	hitbox.monitorable = false

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

	# Чужой персонаж: позиция из буфера интерполяции, визуальные эффекты считаются локально
	if not is_local():
		_process_remote(delta)
		return

	# --- 0. Кулдаун рывка ---
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer = max(0.0, _dash_cooldown_timer - delta)
		dash_cooldown_updated.emit(dash_cooldown - _dash_cooldown_timer, dash_cooldown)

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# aim_override — тестовый хук (tests/net): точка прицела вместо мыши
	var mouse_pos: Vector2 = aim_override if aim_override.is_finite() else get_global_mouse_position()
	var aim_vector: Vector2 = mouse_pos - global_position

	# --- 1. Активация рывка / уклонения ---
	var wants_dash: bool = Input.is_action_just_pressed("dash") or Input.is_action_just_pressed("ability")
	if wants_dash:
		try_dash(_get_dash_direction(input_dir, aim_vector))

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
		if player_class == GameManager.PlayerClass.PALADIN:
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

		_update_move_visuals(delta, velocity)

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
	if Input.is_action_just_pressed("attack"):
		try_attack(aim_vector.normalized(), mouse_pos)

	if NetworkManager.is_online():
		_write_net_state(aim_vector)


## Атака своего персонажа (ввод игрока или тестовый бот). Владелец видит её сразу,
## в сети — запрос хосту; урон считает только хост. Возвращает false, если атаковать нельзя.
func try_attack(aim_dir: Vector2, target_pos: Vector2) -> bool:
	if not is_local() or not current_weapon or not current_weapon.can_attack() or _is_dashing \
			or not health_component.is_alive():
		return false
	var origin: Vector2 = current_weapon.global_position
	_prepare_attack_damage(false)
	current_weapon.attack(aim_dir, target_pos) # мгновенный отзыв; урон на клиенте не применяется
	if NetworkManager.is_online():
		_action_seq += 1
		action_sent.emit("attack", _action_seq)
		if multiplayer.is_server():
			_last_attack_seq = _action_seq
			_net_attack_confirmed.rpc(_action_seq, aim_dir, target_pos, origin)
		else:
			_net_request_attack.rpc_id(1, _action_seq, aim_dir, target_pos, origin)
	return true


## Рывок своего персонажа (ввод игрока или тестовый бот)
func try_dash(dash_dir: Vector2) -> bool:
	if not is_local() or _is_dashing or _dash_cooldown_timer > 0.0 or not health_component.is_alive():
		return false
	_start_dash(dash_dir) # мгновенный отзыв у владельца
	if NetworkManager.is_online():
		_action_seq += 1
		action_sent.emit("dash", _action_seq)
		if multiplayer.is_server():
			_last_dash_seq = _action_seq
			_net_dash_confirmed.rpc(_action_seq, dash_dir)
		else:
			_net_request_dash.rpc_id(1, _action_seq, dash_dir)
	return true


# ════════════════════════════════════════════════════════════════════════════
#  Сеть: снимки движения (владелец → все, через хост)
# ════════════════════════════════════════════════════════════════════════════

func _write_net_state(aim_vector: Vector2) -> void:
	_net_seq += 1
	var aim: float = aim_vector.angle() if aim_vector.length_squared() > 1.0 else weapon_pivot.rotation
	net_state = PackedFloat32Array([_net_seq, teleport_epoch, global_position.x, global_position.y,
		velocity.x, velocity.y, aim, 1.0 if _is_dashing else 0.0])


func _on_net_state(v: PackedFloat32Array) -> void:
	var seq: int = int(v[0])
	var ep: int = int(v[1])
	var pos := Vector2(v[2], v[3])
	var vel := Vector2(v[4], v[5])
	if seq == _interp.last_seq and ep == _interp.epoch:
		return # повтор того же снимка (владелец стоит в портале/мёртв) — не потеря

	# Хост проверяет, что перемещение владельца физически возможно (скорость рывка + запас)
	if multiplayer.is_server() and ep == teleport_epoch and _last_net_seq >= 0 and seq > _last_net_seq:
		var dt: float = (seq - _last_net_seq) / float(Engine.physics_ticks_per_second)
		if pos.distance_to(_last_net_pos) > dash_speed * 1.3 * dt + 48.0:
			NetworkManager.count_stat("move_rejected")
			teleport_to_position(_last_net_pos) # возвращаем в последнюю допустимую точку
			return

	if _interp.push(seq, ep, pos, vel, [v[6], v[7]]):
		if ep == teleport_epoch:
			_last_net_pos = pos
			_last_net_seq = seq
	else:
		NetworkManager.count_stat("snapshot_dropped")


## Чужой персонаж: позиция из буфера интерполяции, эффекты движения считаются локально
func _process_remote(delta: float) -> void:
	_anim_time += delta
	_process_remote_dash(delta)
	var s: Dictionary = _interp.sample()
	if s.is_empty():
		return
	global_position = s["pos"]
	velocity = s["vel"]

	var extra: Array = s["extra"]
	if extra.size() >= 1:
		var aim: float = extra[0]
		weapon_pivot.rotation = lerp_angle(weapon_pivot.rotation, aim, 1.0 - exp(-rotation_smoothing * delta))
		if cos(aim) < -0.05:
			weapon_pivot.scale.y = -1.0
		elif cos(aim) > 0.05:
			weapon_pivot.scale.y = 1.0

	if _is_dashing:
		visuals.scale = Vector2(1.15, 0.88)
		visuals.rotation = lerp_angle(visuals.rotation, clamp(_dash_direction.x, -1.0, 1.0) * deg_to_rad(9.0), 18.0 * delta)
	else:
		_update_move_visuals(delta, velocity)


## Рывок чужого персонажа: хосту нужен для неуязвимости и тарана паладина
func _process_remote_dash(delta: float) -> void:
	if not _is_dashing:
		return
	_dash_timer -= delta
	if player_class == GameManager.PlayerClass.PALADIN and NetworkManager.is_authority():
		_process_paladin_shield_charge()
	if _dash_timer <= 0.0:
		_is_dashing = false
		hurtbox.is_invincible = false
		_dashed_hit_targets.clear()
		visuals.modulate.a = 1.0
		visuals.scale = Vector2.ONE
		visuals.rotation = 0.0


## Наклон корпуса, пыль от шагов и «дыхание» в покое (свой и чужой персонаж)
func _update_move_visuals(delta: float, vel: Vector2) -> void:
	if vel.length_squared() > 100.0:
		var target_tilt: float = clamp(vel.x / speed, -1.0, 1.0) * deg_to_rad(6.5)
		visuals.rotation = lerp_angle(visuals.rotation, target_tilt, 12.0 * delta)
	else:
		visuals.rotation = lerp_angle(visuals.rotation, 0.0, 14.0 * delta)

	body_sprite.position = Vector2(-16.0, -16.0)

	if vel.length_squared() > 100.0:
		visuals.scale = Vector2.ONE
		if _ground_shadow:
			_ground_shadow.scale = Vector2.ONE

		# Аккуратная пыль позади при беге
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.20
			if Engine.has_singleton("VFXManager") or get_node_or_null("/root/VFXManager"):
				VFXManager.spawn_footstep_dust(global_position + Vector2(0, 14), vel.normalized())
	else:
		# Очень мягкое естественное дыхание в покое (едва заметное, 1.5%)
		var breath: float = sin(_anim_time * 2.6) * 0.018
		visuals.scale = Vector2(1.0 + breath, 1.0 - breath)
		if _ground_shadow:
			_ground_shadow.scale = Vector2(1.0 + breath, 1.0 + breath)


# ════════════════════════════════════════════════════════════════════════════
#  Сеть: боевые запросы. Владелец сразу показывает действие у себя и просит хоста;
#  хост проверяет и рассылает подтверждение остальным. Урон считается только на хосте.
# ════════════════════════════════════════════════════════════════════════════

## Проверка запроса на хосте. Пустая строка — запрос допустим, иначе причина отказа.
func _validate_action(seq: int, last_seq: int, last_msec: int, cooldown: float, dir: Vector2, origin: Vector2) -> String:
	if multiplayer.get_remote_sender_id() != peer_id:
		return "owner"
	if seq <= last_seq:
		return "replay"
	if not health_component.is_alive():
		return "dead"
	if NetworkManager.is_transitioning():
		return "phase"
	if not dir.is_finite() or dir.length() < 0.5 or dir.length() > 1.5:
		return "params"
	if origin != Vector2.INF and (not origin.is_finite() or origin.distance_to(global_position) > 260.0):
		return "origin"
	# Запас 40% на джиттер: два честных запроса могут прийти ближе друг к другу, чем были отправлены
	if Time.get_ticks_msec() - last_msec < cooldown * 1000.0 * 0.6:
		return "cooldown"
	return ""


@rpc("any_peer", "reliable")
func _net_request_attack(seq: int, aim_dir: Vector2, target_pos: Vector2, origin: Vector2) -> void:
	if not multiplayer.is_server() or not current_weapon:
		return
	var reason := _validate_action(seq, _last_attack_seq, _last_attack_msec, current_weapon.attack_cooldown, aim_dir, origin)
	if reason != "":
		NetworkManager.count_stat("attack_rejected_" + reason)
		return
	_last_attack_seq = seq
	_last_attack_msec = Time.get_ticks_msec()
	NetworkManager.count_stat("attack_accepted")
	var dir := aim_dir.normalized()
	_perform_remote_attack(dir, target_pos, origin, seq)
	_net_attack_confirmed.rpc(seq, dir, target_pos, origin)


@rpc("any_peer", "reliable")
func _net_attack_confirmed(seq: int, aim_dir: Vector2, target_pos: Vector2, origin: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_local() or seq <= _last_attack_seq:
		return
	_last_attack_seq = seq
	# Тело чужого персонажа показано с задержкой интерполяции — атаку проигрываем с той же
	# задержкой, чтобы удар начинался там, где сейчас видно тело (урон уже посчитан хостом)
	_play_delayed(_perform_remote_attack.bind(_finite_dir(aim_dir), target_pos, origin, seq))


## Атака чужого персонажа из точки, где её сделал владелец
func _perform_remote_attack(dir: Vector2, target_pos: Vector2, origin: Vector2, seq: int = 0) -> void:
	if not current_weapon or not health_component.is_alive():
		return
	weapon_pivot.rotation = dir.angle()
	# Для замеров: насколько показанное оружие разошлось с точкой, где ударил владелец
	remote_action_played.emit("attack", seq, current_weapon.global_position.distance_to(origin))
	current_weapon.force_ready() # кулдаун уже проверен хостом в _validate_action
	_prepare_attack_damage(true)
	current_weapon.origin_override = origin
	current_weapon.attack(dir, target_pos)
	current_weapon.origin_override = Vector2.INF


@rpc("any_peer", "reliable")
func _net_request_dash(seq: int, dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var reason := _validate_action(seq, _last_dash_seq, _last_dash_msec, dash_cooldown, dir, Vector2.INF)
	if reason != "":
		NetworkManager.count_stat("dash_rejected_" + reason)
		return
	_last_dash_seq = seq
	_last_dash_msec = Time.get_ticks_msec()
	NetworkManager.count_stat("dash_accepted")
	_start_dash(dir.normalized())
	_net_dash_confirmed.rpc(seq, dir.normalized())


@rpc("any_peer", "reliable")
func _net_dash_confirmed(seq: int, dir: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_local() or seq <= _last_dash_seq:
		return
	_last_dash_seq = seq
	_play_delayed(_perform_remote_dash.bind(dir, seq))


func _perform_remote_dash(dir: Vector2, seq: int) -> void:
	if not health_component.is_alive():
		return
	remote_action_played.emit("dash", seq, 0.0)
	_start_dash(dir)


## Наблюдатель: действие чужого персонажа — с задержкой показа его тела (см. NetInterpolator)
func _play_delayed(action: Callable) -> void:
	var delay: float = _interp.interp_delay_ms / 1000.0 if NetworkManager.align_remote_actions else 0.0
	if delay <= 0.0:
		action.call()
	else:
		# Связь с методом (а не лямбда): если персонаж исчезнет раньше, связь порвётся сама
		get_tree().create_timer(delay).timeout.connect(action)


func _finite_dir(v: Vector2) -> Vector2:
	return v if v.is_finite() else Vector2.RIGHT


func _get_dash_direction(input_dir: Vector2, aim_vector: Vector2) -> Vector2:
	if SettingsManager.dash_direction == SettingsManager.DashDirection.MOVEMENT and input_dir.length_squared() > 0.01:
		return input_dir.normalized()
	# Если в режиме движения игрок стоит, используем курсор.
	if aim_vector.length_squared() > 0.01:
		return aim_vector.normalized()
	elif input_dir.length_squared() > 0.01:
		return input_dir.normalized()
	return Vector2.RIGHT


func _start_dash(dash_dir: Vector2) -> void:
	_is_dashing = true
	_last_dash_start_msec = Time.get_ticks_msec()
	_dash_timer = dash_duration
	_dash_cooldown_timer = dash_cooldown
	_dashed_hit_targets.clear()
	_dash_ghost_timer = 0.0
	_dash_direction = dash_dir

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
	query.collision_mask = 64 | (32 if NetworkManager.friendly_fire else 0)
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var hits: Array[Dictionary] = space_state.intersect_shape(query, 16)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider and collider is Hurtbox and collider.get_parent() != self and not _dashed_hit_targets.has(collider):
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
	hurtbox.set_deferred("collision_layer", 0)
	hurtbox.set_deferred("monitorable", false)
	hp_bar.visible = false
