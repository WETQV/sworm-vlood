extends SlimeAI
class_name BatAI
## BatAI — ИИ летучей мыши.
## Быстрый хаотичный полёт (волнистая траектория), пике на игрока и отлёт после укуса:
## CHASE -> ENCIRCLE (дёрганое кружение) -> WINDUP (зависание) -> LUNGE (пике) -> RECOVER (отлёт).

@export var wobble_strength: float = 0.55   ## Сила «рыскания» в полёте
@export var wobble_speed: float = 7.0
@export var flap_speed: float = 18.0        ## Частота взмахов крыльев

var _time: float = 0.0
var _wing_left: Node2D
var _wing_right: Node2D
var _retreat_dir: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	_wing_left = _body.get_node_or_null("Visuals/WingLeft") as Node2D
	_wing_right = _body.get_node_or_null("Visuals/WingRight") as Node2D
	_time = randf() * TAU # чтобы мыши в стае махали не синхронно


func _physics_process(delta: float) -> void:
	_time += delta
	super._physics_process(delta)
	_flap_wings()


func _wobble(dir: Vector2) -> Vector2:
	var side: Vector2 = Vector2(-dir.y, dir.x)
	return (dir + side * sin(_time * wobble_speed) * wobble_strength).normalized()


func _process_chase(delta: float) -> void:
	if not is_instance_valid(target_player):
		_change_state(State.IDLE)
		return

	var dist: float = _body.global_position.distance_to(target_player.global_position)
	if dist <= encircle_distance:
		_change_state(State.ENCIRCLE)
		return

	var move_dir: Vector2 = _unstick(_avoid_obstacles(_wobble(_get_chase_direction(delta))), delta)
	_body.velocity = _body.velocity.move_toward(move_dir * base_speed, 700.0 * delta)
	_body.move_and_slide()


func _process_encircle(delta: float) -> void:
	if not is_instance_valid(target_player):
		_change_state(State.IDLE)
		return

	var to_target: Vector2 = target_player.global_position - _body.global_position
	var dist: float = to_target.length()
	_encircle_timer += delta

	if dist > encircle_distance + 60.0:
		_change_state(State.CHASE)
		return

	var has_token: bool = _swarm != null and _swarm.request_attack_token(_body, target_player)
	var force_attack: bool = _encircle_timer >= max_encircle_time
	if dist <= attack_range and (has_token or force_attack or _swarm == null):
		_change_state(State.WINDUP)
		return

	# Дёрганое кружение: радиус «дышит», направление рыщет
	var tangent: Vector2 = Vector2(-to_target.y, to_target.x).normalized() * _circumnavigate_side
	var radial: float = (dist - encircle_distance * (0.8 + 0.2 * sin(_time * 2.3))) / encircle_distance
	var desired_dir: Vector2 = (tangent + to_target.normalized() * radial * 1.5).normalized()
	desired_dir = _avoid_obstacles(_wobble(desired_dir))

	_body.velocity = _body.velocity.move_toward(desired_dir * base_speed, 700.0 * delta)
	_body.move_and_slide()


## Отлёт после укуса: в сторону от игрока, с рысканием
func _process_recover(delta: float) -> void:
	_state_timer -= delta
	var dir: Vector2 = _steer_clear_of_nearby_walls(_wobble(_retreat_dir), _body.get_world_2d().direct_space_state, _body.global_position)
	_body.velocity = _body.velocity.move_toward(dir * base_speed * 0.9, 900.0 * delta)
	_body.move_and_slide()
	if _state_timer <= 0.0:
		_change_state(State.CHASE)


func _change_state(new_state: State) -> void:
	if new_state == State.RECOVER:
		# Улетаем назад, слегка вбок
		var back: Vector2 = -_lunge_dir if _lunge_dir != Vector2.ZERO else Vector2.UP
		_retreat_dir = back.rotated(randf_range(-0.6, 0.6))
	super._change_state(new_state)


func _flap_wings() -> void:
	var flap_mult: float = 1.8 if current_state == State.LUNGE else 1.0
	var s: float = 0.35 + 0.65 * absf(sin(_time * flap_speed * flap_mult))
	if _wing_left:
		_wing_left.scale.y = s
	if _wing_right:
		_wing_right.scale.y = s
