extends SlimeAI
class_name BossAI
## BossAI — слайм-босс 7-го этажа. Базовый рывок (SlimeAI) плюс отдельные паттерны:
## - Удар о землю («slam»): ответ на ближний бой. Красный круг 0,9 с, затем волна по
##   радиусу; контригра — выйти из круга или рывок (неуязвимость). После удара босс
##   долго приходит в себя — окно для урона.
## - Веер плевков («spit»): ответ на кайтинг издалека. Замах 0,7 с, 5 сгустков веером
##   50°; контригра — пройти между сгустками или укрыться за колонной.
## - Деление: на 66% и 33% здоровья отпочковываются 2 слайма (одновременно живых
##   прислужников не больше 4). Со смертью босса прислужники гибнут.
## Решения и урон — на хосте; клиенты получают паттерн надёжным событием и рисуют
## телеграф/снаряды с той же задержкой, что и тело (как _net_ai_event).

const GLOB_SCENE := preload("res://scenes/items/enemy_arrow.tscn")
const ADD_SCENE := preload("res://scenes/enemies/slime.tscn")

@export var slam_radius: float = 150.0
@export var slam_damage: int = 22
@export var slam_windup: float = 0.9
@export var slam_recover: float = 1.1
@export var slam_cooldown: float = 5.0
@export var slam_trigger_distance: float = 175.0
@export var spit_windup: float = 0.7
@export var spit_recover: float = 0.6
@export var spit_cooldown: float = 4.0
@export var spit_min_distance: float = 260.0
@export var spit_count: int = 5
@export var spit_spread_deg: float = 50.0
@export var spit_speed: float = 260.0
@export var spit_damage: int = 12
@export var max_adds: int = 4

var _pattern: String = ""
var _pattern_timer: float = 0.0
var _pattern_fired: bool = false
var _pattern_dir: Vector2 = Vector2.RIGHT
var _pattern_origin: Vector2 = Vector2.ZERO
var _slam_cd: float = 2.0
var _spit_cd: float = 2.0
var _split_thresholds: Array[float] = [0.66, 0.33]
var _adds: Array[Node2D] = []
var _ring: Polygon2D


func _ready() -> void:
	super._ready()
	var hc := _body.get_node_or_null("HealthComponent") as HealthComponent
	if hc:
		hc.died.connect(_on_boss_died)


func _is_host() -> bool:
	return not NetworkManager.is_online() or multiplayer.is_server()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_body):
		return
	var hc := _body.get_node_or_null("HealthComponent") as HealthComponent
	if hc and not hc.is_alive():
		super._physics_process(delta)
		return
	if _is_host():
		_slam_cd -= delta
		_spit_cd -= delta
		_check_split(hc)
	if _pattern != "":
		_process_pattern(delta)
		return
	if _is_host() and _choose_pattern():
		return
	super._physics_process(delta)


func _choose_pattern() -> bool:
	if not current_state in [State.CHASE, State.ENCIRCLE]:
		return false
	_update_target()
	if not is_instance_valid(target_player):
		return false
	var to_target := target_player.global_position - _body.global_position
	var dist := to_target.length()
	if dist <= slam_trigger_distance and _slam_cd <= 0.0:
		_start_pattern("slam", to_target.normalized(), _body.global_position)
		return true
	if dist >= spit_min_distance and _spit_cd <= 0.0 and _has_clear_line():
		_start_pattern("spit", to_target.normalized(), _body.global_position)
		return true
	return false


func _has_clear_line() -> bool:
	var query := PhysicsRayQueryParameters2D.create(_body.global_position, target_player.global_position, 1)
	return _body.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _start_pattern(kind: String, dir: Vector2, origin: Vector2) -> void:
	if _is_host():
		if kind == "slam":
			_slam_cd = slam_cooldown
		else:
			_spit_cd = spit_cooldown
		if NetworkManager.is_online():
			_net_boss_pattern.rpc(kind, dir, origin)
	_pattern = kind
	_pattern_dir = dir
	_pattern_origin = origin
	_pattern_fired = false
	_pattern_timer = slam_windup if kind == "slam" else spit_windup
	if _swarm and is_instance_valid(target_player):
		_swarm.release_attack_token(_body, target_player)
	if _hitbox:
		_hitbox.set_active(false)
	if kind == "slam":
		_show_ring(true)
		_play_squash_tween(Vector2(1.3, 0.7), slam_windup)
	else:
		_play_squash_tween(Vector2(0.85, 1.2), spit_windup)


## Клиент: паттерн хоста — с задержкой показа тела (как атаки в _net_ai_event)
@rpc("authority", "reliable")
func _net_boss_pattern(kind: String, dir: Vector2, origin: Vector2) -> void:
	var delay: float = 0.0
	if "_interp" in _body and NetworkManager.align_remote_actions:
		delay = _body._interp.interp_delay_ms / 1000.0
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(_start_pattern.bind(kind, dir, origin))
	else:
		_start_pattern(kind, dir, origin)


func _process_pattern(delta: float) -> void:
	_pattern_timer -= delta
	if _is_host():
		_body.velocity = _body.velocity.move_toward(Vector2.ZERO, 800.0 * delta)
		_body.move_and_slide()
	if not _pattern_fired:
		if _pattern == "slam" and _ring:
			_ring.scale = Vector2.ONE * (0.3 + 0.7 * (1.0 - clampf(_pattern_timer / slam_windup, 0.0, 1.0)))
		if _pattern_timer <= 0.0:
			_pattern_fired = true
			if _pattern == "slam":
				_fire_slam()
				_pattern_timer = slam_recover
			else:
				_fire_spit()
				_pattern_timer = spit_recover
		return
	if _pattern_timer <= 0.0:
		_pattern = ""
		_show_ring(false)
		_play_squash_tween(Vector2.ONE, 0.15)
		current_state = State.CHASE


func _fire_slam() -> void:
	_show_ring(false)
	var center: Vector2 = _body.global_position if _is_host() else _pattern_origin
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_holy_nova"):
		vfx.spawn_holy_nova(center, slam_radius)
	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_holy_shockwave"):
		snd.play_holy_shockwave()
	_play_squash_tween(Vector2(1.4, 0.6), 0.1)
	if not _is_host():
		return
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Player
		if player and player.health_component.is_alive() and player.global_position.distance_to(center) <= slam_radius:
			player.hurtbox.receive_damage(slam_damage, 260.0, center, _body) # рывок (i-frames) спасает


func _fire_spit() -> void:
	var from: Vector2 = _pattern_origin if not _is_host() else _body.global_position
	var world_root: Node = get_tree().current_scene if get_tree().current_scene else _body.get_parent()
	for i in spit_count:
		var t := 0.0 if spit_count == 1 else float(i) / (spit_count - 1) - 0.5
		var dir := _pattern_dir.rotated(deg_to_rad(spit_spread_deg) * t)
		var glob := GLOB_SCENE.instantiate() as EnemyArrow
		glob.direction = dir
		glob.speed = spit_speed
		glob.damage = spit_damage
		glob.attacker = _body
		glob.modulate = Color(0.95, 0.35, 0.3)
		glob.scale = Vector2(1.6, 1.6)
		glob.global_position = from + dir * 40.0
		world_root.add_child(glob)
	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_slime_lunge"):
		snd.play_slime_lunge()


## Хост: деление на порогах здоровья
func _check_split(hc: HealthComponent) -> void:
	if hc == null or _split_thresholds.is_empty():
		return
	if hc.get_health_percent() > _split_thresholds[0]:
		return
	_split_thresholds.pop_front()
	_adds = _adds.filter(func(a: Node2D) -> bool: return is_instance_valid(a) and a.health_component.is_alive())
	var space_state := _body.get_world_2d().direct_space_state
	var game := get_tree().current_scene
	for side in [-1.0, 1.0]:
		if _adds.size() >= max_adds:
			break
		var dir: Vector2 = _pattern_dir.orthogonal() * side if _pattern_dir != Vector2.ZERO else Vector2.RIGHT * side
		var pos: Vector2 = _body.global_position + dir * 70.0
		if not space_state.intersect_ray(PhysicsRayQueryParameters2D.create(_body.global_position, pos + dir * 16.0, 1)).is_empty():
			pos = _body.global_position - dir * 70.0
		var add: Node2D
		if NetworkManager.is_online() and game and game.has_method("spawn_network_enemy"):
			add = game.spawn_network_enemy(ADD_SCENE, pos)
		else:
			add = ADD_SCENE.instantiate()
			_body.get_parent().add_child(add)
			add.global_position = pos # после добавления: у родителя-комнаты своё смещение
		_adds.append(add)


func _on_boss_died(_killer: Node2D) -> void:
	_show_ring(false)
	_pattern = ""
	if not _is_host():
		return
	for add in _adds:
		if is_instance_valid(add) and add.health_component.is_alive():
			add.health_component.take_damage(add.health_component.current_health)
	_adds.clear()


func _show_ring(on: bool) -> void:
	if on:
		if _ring == null:
			_ring = Polygon2D.new()
			var points := PackedVector2Array()
			for i in 32:
				points.append(Vector2.RIGHT.rotated(TAU * i / 32.0) * slam_radius)
			_ring.polygon = points
			_ring.color = Color(1.0, 0.2, 0.15, 0.22)
			_ring.z_index = -1
			_ring.top_level = true
			_body.add_child(_ring)
		_ring.global_position = _body.global_position
		_ring.visible = true
	elif _ring:
		_ring.visible = false
