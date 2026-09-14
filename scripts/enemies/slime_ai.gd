extends Node
class_name SlimeAI
## SlimeAI — конечный автомат (FSM) поведения слайма:
## IDLE -> CHASE (NavMesh + Whiskers) -> ENCIRCLE -> WINDUP -> LUNGE -> RECOVER.

enum State { IDLE, CHASE, ENCIRCLE, WINDUP, LUNGE, RECOVER }

@export var base_speed: float = 95.0
@export var lunge_speed: float = 260.0
@export var attack_range: float = 125.0
@export var encircle_distance: float = 105.0
@export var windup_time: float = 0.18
@export var lunge_duration: float = 0.28
@export var recover_time: float = 0.35
@export var max_encircle_time: float = 1.8  # Максимальное время кружения перед принудительной атакой

var current_state: State = State.IDLE
var target_player: CharacterBody2D = null

var _body: CharacterBody2D
var _nav_agent: NavigationAgent2D
var _swarm: SwarmManager
var _hitbox: HitboxComponent
var _state_timer: float = 0.0
var _lunge_dir: Vector2 = Vector2.ZERO
var _nav_update_timer: float = 0.0
var _encircle_timer: float = 0.0
var _circumnavigate_side: int = 1  # 1 = clockwise, -1 = counter-clockwise


func _ready() -> void:
	_body = get_parent() as CharacterBody2D
	_nav_agent = _body.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	_circumnavigate_side = 1 if (_body.get_instance_id() % 2 == 0) else -1

	_hitbox = _body.get_node_or_null("AttackArea") as HitboxComponent
	if not _hitbox:
		_hitbox = _body.get_node_or_null("HitboxComponent") as HitboxComponent

	_find_swarm_manager()
	if _swarm:
		_swarm.register_enemy(_body)

	if _hitbox:
		_hitbox.set_active(false)


func _exit_tree() -> void:
	if _swarm and is_instance_valid(_body):
		_swarm.unregister_enemy(_body)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_body):
		return

	var hc := _body.get_node_or_null("HealthComponent") as HealthComponent
	if hc and not hc.is_alive():
		set_physics_process(false)
		if _hitbox and is_instance_valid(_hitbox):
			_hitbox.set_active(false)
		return

	_nav_update_timer += delta
	if _nav_update_timer >= 0.2:
		_nav_update_timer = 0.0
		_update_target()

	match current_state:
		State.IDLE:
			_process_idle()
		State.CHASE:
			_process_chase(delta)
		State.ENCIRCLE:
			_process_encircle(delta)
		State.WINDUP:
			_process_windup(delta)
		State.LUNGE:
			_process_lunge(delta)
		State.RECOVER:
			_process_recover(delta)


func _update_target() -> void:
	if not is_instance_valid(target_player):
		if _swarm:
			target_player = _swarm.get_best_target_for(_body)
		else:
			var players: Array[Node] = get_tree().get_nodes_in_group("player")
			if not players.is_empty():
				target_player = players[0] as CharacterBody2D


func _process_idle() -> void:
	_body.velocity = _body.velocity.move_toward(Vector2.ZERO, 400.0 * get_physics_process_delta_time())
	_body.move_and_slide()
	if is_instance_valid(target_player):
		_change_state(State.CHASE)


func _process_chase(delta: float) -> void:
	if not is_instance_valid(target_player):
		_change_state(State.IDLE)
		return

	var dist: float = _body.global_position.distance_to(target_player.global_position)
	if dist <= encircle_distance:
		_change_state(State.ENCIRCLE)
		return

	var move_dir: Vector2 = (target_player.global_position - _body.global_position).normalized()
	if _nav_agent:
		_nav_agent.target_position = target_player.global_position
		if not _nav_agent.is_navigation_finished():
			var next_path_pos: Vector2 = _nav_agent.get_next_path_position()
			var nav_dir: Vector2 = (next_path_pos - _body.global_position).normalized()
			if nav_dir != Vector2.ZERO:
				move_dir = nav_dir

	# Обход стен и углов (усики и тангенциальное скольжение)
	move_dir = _avoid_obstacles(move_dir)

	_body.velocity = _body.velocity.move_toward(move_dir * base_speed, 450.0 * delta)
	_body.move_and_slide()


func _process_encircle(delta: float) -> void:
	if not is_instance_valid(target_player):
		_change_state(State.IDLE)
		return

	var to_target: Vector2 = target_player.global_position - _body.global_position
	var dist: float = to_target.length()
	_encircle_timer += delta

	# Если игрок оторвался — переходим в погоню
	if dist > encircle_distance + 50.0:
		_change_state(State.CHASE)
		return

	var has_token: bool = _swarm != null and _swarm.request_attack_token(_body, target_player)
	var force_attack: bool = _encircle_timer >= max_encircle_time

	if dist <= attack_range and (has_token or force_attack or _swarm == null):
		_change_state(State.WINDUP)
		return

	# Кружение вокруг цели со сближением
	var tangent: Vector2 = Vector2(-to_target.y, to_target.x).normalized()
	var desired_vel: Vector2 = tangent * (base_speed * 0.75)
	if dist > encircle_distance:
		desired_vel += to_target.normalized() * (base_speed * 0.4)

	# Обход стен во время кружения
	var steer_dir: Vector2 = _avoid_obstacles(desired_vel.normalized())
	desired_vel = steer_dir * desired_vel.length()

	_body.velocity = _body.velocity.move_toward(desired_vel, 400.0 * delta)
	_body.move_and_slide()


func _process_windup(delta: float) -> void:
	_state_timer -= delta
	_body.velocity = _body.velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	_body.move_and_slide()
	if _state_timer <= 0.0:
		_change_state(State.LUNGE)


func _process_lunge(delta: float) -> void:
	_state_timer -= delta
	_body.velocity = _lunge_dir * lunge_speed
	_body.move_and_slide()
	if _hitbox:
		_hitbox.check_overlapping_now()
	if _state_timer <= 0.0:
		_change_state(State.RECOVER)


func _process_recover(delta: float) -> void:
	_state_timer -= delta
	_body.velocity = _body.velocity.move_toward(Vector2.ZERO, 500.0 * delta)
	_body.move_and_slide()
	if _state_timer <= 0.0:
		_change_state(State.CHASE)


func _change_state(new_state: State) -> void:
	current_state = new_state
	match new_state:
		State.ENCIRCLE:
			_encircle_timer = 0.0

		State.WINDUP:
			_state_timer = windup_time
			if is_instance_valid(target_player):
				_lunge_dir = (target_player.global_position - _body.global_position).normalized()
			_play_squash_tween(Vector2(1.25, 0.75), windup_time)

		State.LUNGE:
			_state_timer = lunge_duration
			if _hitbox:
				_hitbox.set_active(true)
			_play_squash_tween(Vector2(0.8, 1.3), lunge_duration * 0.5)
			var snd = get_node_or_null("/root/SoundManager")
			if snd and snd.has_method("play_slime_lunge"):
				snd.play_slime_lunge()

		State.RECOVER:
			_state_timer = recover_time
			if _hitbox:
				_hitbox.set_active(false)
			if _swarm and is_instance_valid(target_player):
				_swarm.release_attack_token(_body, target_player)
			_play_squash_tween(Vector2(1.0, 1.0), 0.15)


## Обход препятствий и колонн (Line-of-Sight + Standoff) без застревания на углах
func _avoid_obstacles(desired_direction: Vector2) -> Vector2:
	if desired_direction == Vector2.ZERO or not is_instance_valid(_body):
		return desired_direction

	var world_2d: World2D = _body.get_world_2d()
	if not world_2d:
		return desired_direction

	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	if not space_state:
		return desired_direction

	var origin: Vector2 = _body.global_position

	# 1. Если есть игрок, проверяем прямую видимость (Слой 1 — стены)
	if is_instance_valid(target_player):
		var target_pos: Vector2 = target_player.global_position
		var los_query := PhysicsRayQueryParameters2D.create(origin, target_pos, 1)
		var los_hit: Dictionary = space_state.intersect_ray(los_query)

		if not los_hit:
			# Прямая видимость свободна! Идем прямо на игрока
			return _steer_clear_of_nearby_walls(desired_direction, space_state, origin)

		# Прямая видимость перекрыта колонной/стеной!
		var obs_norm: Vector2 = los_hit.normal
		var tangent: Vector2 = Vector2(-obs_norm.y, obs_norm.x) if _circumnavigate_side == 1 else Vector2(obs_norm.y, -obs_norm.x)

		# Проверяем, свободен ли путь вперед по тангенсу (34 px)
		var fwd_query := PhysicsRayQueryParameters2D.create(origin, origin + tangent * 34.0, 1)
		var fwd_hit: Dictionary = space_state.intersect_ray(fwd_query)
		if fwd_hit:
			# Впереди стена — огибаем угол по стороне обхода
			var fwd_n: Vector2 = fwd_hit.normal
			tangent = Vector2(-fwd_n.y, fwd_n.x) if _circumnavigate_side == 1 else Vector2(fwd_n.y, -fwd_n.x)

		# Держим отступ от стены (24 px standoff), чтобы не тереться о коллайдер
		var standoff_push := Vector2.ZERO
		var side_query := PhysicsRayQueryParameters2D.create(origin, origin - obs_norm * 26.0, 1)
		var side_hit: Dictionary = space_state.intersect_ray(side_query)
		if side_hit:
			standoff_push = side_hit.normal * 0.4

		# Если тело уже физически касается стены
		if _body.get_slide_collision_count() > 0:
			var col: KinematicCollision2D = _body.get_slide_collision(0)
			standoff_push += col.get_normal() * 0.5

		return (tangent * 0.85 + standoff_push).normalized()

	return _steer_clear_of_nearby_walls(desired_direction, space_state, origin)


func _steer_clear_of_nearby_walls(desired_dir: Vector2, space_state: PhysicsDirectSpaceState2D, origin: Vector2) -> Vector2:
	var fwd_query := PhysicsRayQueryParameters2D.create(origin, origin + desired_dir * 36.0, 1)
	var hit: Dictionary = space_state.intersect_ray(fwd_query)

	if not hit:
		if _body.get_slide_collision_count() > 0:
			var col: KinematicCollision2D = _body.get_slide_collision(0)
			var n: Vector2 = col.get_normal()
			var slide: Vector2 = desired_dir.slide(n).normalized()
			if slide != Vector2.ZERO:
				return (slide * 0.85 + n * 0.25).normalized()
		return desired_dir

	var normal: Vector2 = hit.normal
	var slide_dir: Vector2 = desired_dir.slide(normal).normalized()
	if slide_dir != Vector2.ZERO and desired_dir.dot(normal) > -0.65:
		return (slide_dir * 0.85 + normal * 0.2).normalized()

	var t: Vector2 = Vector2(-normal.y, normal.x) if _circumnavigate_side == 1 else Vector2(normal.y, -normal.x)
	return (t * 0.85 + normal * 0.3).normalized()


func _play_squash_tween(scale_target: Vector2, duration: float) -> void:
	var visuals: Node2D = _body.get_node_or_null("Visuals") as Node2D
	if visuals:
		var tween: Tween = create_tween()
		tween.tween_property(visuals, "scale", scale_target, duration).set_ease(Tween.EASE_OUT)


func _find_swarm_manager() -> void:
	var managers: Array[Node] = get_tree().get_nodes_in_group("swarm_manager")
	if not managers.is_empty():
		_swarm = managers[0] as SwarmManager
