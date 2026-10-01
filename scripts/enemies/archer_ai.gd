extends SlimeAI
class_name ArcherAI
## ArcherAI — ИИ врага-лучника.
## Держит дистанцию, отступает от игрока, стреляет при прямой видимости:
## CHASE (подойти на дистанцию выстрела) -> ENCIRCLE (держать дистанцию, стрейф)
## -> WINDUP (натяжение тетивы + линия прицела) -> LUNGE (выстрел) -> RECOVER.
## Токены атаки роя не используются: лучник не занимает места у ближников.

const ARROW_SCENE := preload("res://scenes/items/enemy_arrow.tscn")

@export var preferred_distance: float = 230.0  ## Комфортная дистанция стрельбы
@export var min_distance: float = 150.0        ## Ближе — отступаем
@export var shoot_range: float = 380.0         ## Дальше — идём ближе
@export var arrow_speed: float = 340.0
@export var aim_lock_ratio: float = 0.75       ## После этой доли замаха прицел фиксируется
@export var shot_interval_min: float = 0.7     ## Пауза между выстрелами (случайная)
@export var shot_interval_max: float = 1.4

var _bow_pivot: Node2D
var _aim_line: Line2D
var _next_shot_delay: float = 1.0
var _aim_locked: bool = false
var _bow: Node2D
var _bow_rest_x: float = 0.0
var _los_lost_time: float = 0.0

const ARROW_HALF_WIDTH := 5.0 ## Стрела задевает угол колонны раньше, чем луч из центра
const LOS_GRACE := 0.35       ## Кратковременная потеря видимости у угла не сбрасывает прицел
## Упреждение: стрела летит в точку, где цель окажется. Без него бег по кругу делал героя
## неуязвимым для лучников (стенд tests/rooms/nav_checks: 0 попаданий за 24 с кайтинга).
## Контригра — сменить направление после фиксации прицела.
const LEAD_FACTOR := 1.0
const MAX_TARGET_SPEED := 420.0

var _target_prev_pos: Vector2 = Vector2.INF
var _target_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	_bow_pivot = _body.get_node_or_null("Visuals/BowPivot") as Node2D
	_aim_line = _body.get_node_or_null("AimLine") as Line2D
	if _bow_pivot:
		_bow = _bow_pivot.get_node_or_null("Bow") as Node2D
		if _bow:
			_bow_rest_x = _bow.position.x
	if _aim_line:
		_aim_line.visible = false
	_roll_shot_delay()


func _physics_process(delta: float) -> void:
	_track_target(delta)
	super._physics_process(delta)
	_aim_bow()


## Скорость цели по смещению между кадрами: у чужих героев на хосте velocity не заполнена
func _track_target(delta: float) -> void:
	if not is_instance_valid(target_player) or delta <= 0.0:
		_target_prev_pos = Vector2.INF
		return
	var pos := target_player.global_position
	if _target_prev_pos.is_finite():
		var step := pos - _target_prev_pos
		if step.length() > MAX_TARGET_SPEED * delta * 2.0:
			_target_velocity = Vector2.ZERO # телепорт или смена цели
		else:
			_target_velocity = _target_velocity.lerp(step / delta, 0.2)
	_target_prev_pos = pos


## Направление выстрела с упреждением: точка перехвата бегущей цели стрелой.
## Цель к моменту выстрела (через _state_timer) в p, скорость v; ищем t: |p + v·t| = s·t
func _aim_direction() -> Vector2:
	var from := _body.global_position
	var target := target_player.global_position
	var v := _target_velocity.limit_length(MAX_TARGET_SPEED) * LEAD_FACTOR
	var p := target + v * maxf(_state_timer, 0.0) - from
	var a := v.dot(v) - arrow_speed * arrow_speed
	var b := 2.0 * p.dot(v)
	var d := b * b - 4.0 * a * p.dot(p)
	var aim := target
	if d >= 0.0 and absf(a) > 0.001:
		var t := (-b - sqrt(d)) / (2.0 * a) # a < 0: этот корень положительный
		if t > 0.0:
			aim = from + p + v * t
	# Цель не пробежит сквозь стену: упреждение обрезаем у препятствия на её пути
	var lead := aim - target
	if lead.length() > 1.0:
		var space_state := _body.get_world_2d().direct_space_state
		var hit := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(target, aim, 1))
		if not hit.is_empty():
			aim = hit.position - lead.normalized() * minf(24.0, target.distance_to(hit.position))
	var dir := (aim - from).normalized()
	return dir if dir != Vector2.ZERO else (target - from).normalized()

func _roll_shot_delay() -> void:
	_next_shot_delay = randf_range(shot_interval_min, shot_interval_max)


## Видимость для выстрела: центр и края стрелы. Луч из одного центра проходил впритирку
## к углу колонны, а сама стрела в угол попадала
func _has_line_of_sight() -> bool:
	if not is_instance_valid(target_player):
		return false
	var space_state := _body.get_world_2d().direct_space_state
	var from := _body.global_position
	var to := target_player.global_position
	var side := (to - from).normalized().orthogonal() * ARROW_HALF_WIDTH
	for offset in [Vector2.ZERO, side, -side]:
		var query := PhysicsRayQueryParameters2D.create(from + offset, to + offset, 1)
		if not space_state.intersect_ray(query).is_empty():
			return false
	return true


func _process_chase(delta: float) -> void:
	if not is_instance_valid(target_player):
		_change_state(State.IDLE)
		return
	var dist: float = _body.global_position.distance_to(target_player.global_position)
	if dist <= shoot_range and _has_line_of_sight():
		_change_state(State.ENCIRCLE)
		return
	# Без прямой видимости идём по пути к цели даже вблизи: за углом укрытия линия
	# откроется. Переход в ENCIRCLE по дистанции (как у слайма) тут же возвращал в CHASE,
	# а обход цели по дуге упирался в само укрытие — лучник топтался, не стреляя.
	var move_dir: Vector2 = _unstick(_avoid_obstacles(_get_chase_direction(delta)), delta)
	_body.velocity = _body.velocity.move_toward(move_dir * base_speed, 450.0 * delta)
	_body.move_and_slide()


## ENCIRCLE у лучника — удержание дистанции и стрейф
func _process_encircle(delta: float) -> void:
	if not is_instance_valid(target_player):
		_change_state(State.IDLE)
		return

	var to_target: Vector2 = target_player.global_position - _body.global_position
	var dist: float = to_target.length()
	var has_los: bool = _has_line_of_sight()
	if not has_los and _los_lost_time == 0.0:
		# Стрейф увёл за колонну — возвращаемся туда, где линия была открыта
		_circumnavigate_side *= -1
	_los_lost_time = 0.0 if has_los else _los_lost_time + delta

	if dist > shoot_range + 60.0 or _los_lost_time > LOS_GRACE:
		_change_state(State.CHASE)
		return

	_encircle_timer += delta
	if _encircle_timer >= _next_shot_delay and has_los:
		_change_state(State.WINDUP)
		return

	var away: Vector2 = -to_target.normalized()
	var tangent: Vector2 = Vector2(-to_target.y, to_target.x).normalized() * _circumnavigate_side
	var desired: Vector2
	if dist < min_distance:
		desired = (away * 1.0 + tangent * 0.35).normalized() * base_speed * 1.15
	elif dist > preferred_distance + 40.0:
		desired = (-away * 0.8 + tangent * 0.4).normalized() * base_speed
	else:
		# Стрейф с мягким подтягиванием к комфортной дистанции
		var radial: float = clampf((dist - preferred_distance) / preferred_distance, -0.5, 0.5)
		desired = (tangent + to_target.normalized() * radial * 1.6).normalized() * base_speed * 0.6

	var steer_dir: Vector2 = _steer_clear_of_nearby_walls(desired.normalized(), _body.get_world_2d().direct_space_state, _body.global_position)
	# Упёрлись в стену при стрейфе — меняем сторону
	if _body.get_slide_collision_count() > 0 and dist >= min_distance:
		_circumnavigate_side *= -1
	_body.velocity = _body.velocity.move_toward(steer_dir * desired.length(), 500.0 * delta)
	_body.move_and_slide()


func _process_windup(delta: float) -> void:
	_state_timer -= delta
	_body.velocity = _body.velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	_body.move_and_slide()

	# Пока не зафиксировали прицел — ведём цель
	if not _aim_locked and is_instance_valid(target_player):
		_lunge_dir = _aim_direction()
		if _state_timer <= windup_time * (1.0 - aim_lock_ratio):
			_aim_locked = true
	_update_aim_line()

	if _state_timer <= 0.0:
		_change_state(State.LUNGE)


func _process_lunge(delta: float) -> void:
	_state_timer -= delta
	_body.velocity = _body.velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	_body.move_and_slide()
	if _state_timer <= 0.0:
		_change_state(State.RECOVER)


func _change_state(new_state: State) -> void:
	match new_state:
		State.WINDUP:
			current_state = new_state
			_state_timer = windup_time
			_aim_locked = false
			if is_instance_valid(target_player):
				_lunge_dir = (target_player.global_position - _body.global_position).normalized()
			if _aim_line:
				_aim_line.visible = true
			_update_aim_line()
			_play_squash_tween(Vector2(0.92, 1.08), windup_time)

		State.LUNGE:
			current_state = new_state
			_state_timer = lunge_duration
			if _aim_line:
				_aim_line.visible = false
			_shoot()
			_play_squash_tween(Vector2(1.1, 0.9), 0.08)

		State.RECOVER:
			current_state = new_state
			_state_timer = recover_time
			_roll_shot_delay()
			_play_squash_tween(Vector2.ONE, 0.15)

		_:
			if _aim_line:
				_aim_line.visible = false
			_los_lost_time = 0.0
			super._change_state(new_state)


func _shoot() -> void:
	var arrow := ARROW_SCENE.instantiate() as EnemyArrow
	arrow.direction = _lunge_dir
	arrow.speed = arrow_speed
	arrow.damage = _body.contact_damage if "contact_damage" in _body else 12
	arrow.attacker = _body
	# В сети у клиента — точка выстрела у хоста, чтобы стрела летела по тому же пути
	var from: Vector2 = event_origin if event_origin.is_finite() else _body.global_position
	arrow.global_position = from + _lunge_dir * 16.0

	var world_root: Node = get_tree().current_scene
	if not world_root:
		world_root = _body.get_parent()
	world_root.add_child(arrow)

	# Отдача лука
	if _bow:
		var tween: Tween = create_tween()
		tween.tween_property(_bow, "position:x", _bow_rest_x - 4.0, 0.05)
		tween.tween_property(_bow, "position:x", _bow_rest_x, 0.12)


## Лук смотрит на цель (во время замаха — по линии прицела)
func _aim_bow() -> void:
	if not _bow_pivot:
		return
	var dir: Vector2 = Vector2.ZERO
	if current_state == State.WINDUP or current_state == State.LUNGE:
		dir = _lunge_dir
	elif is_instance_valid(target_player):
		dir = target_player.global_position - _body.global_position
	if dir != Vector2.ZERO:
		_bow_pivot.rotation = lerp_angle(_bow_pivot.rotation, dir.angle(), 0.3)


## Линия прицела — телеграф выстрела, ярче к моменту спуска тетивы
func _update_aim_line() -> void:
	if not _aim_line:
		return
	var length: float = shoot_range
	var space_state := _body.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_body.global_position, _body.global_position + _lunge_dir * shoot_range, 1)
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		length = _body.global_position.distance_to(hit.position)
	_aim_line.points = PackedVector2Array([_lunge_dir * 14.0, _lunge_dir * length])
	var progress: float = 1.0 - clampf(_state_timer / maxf(windup_time, 0.01), 0.0, 1.0)
	_aim_line.default_color = Color(1.0, 0.25, 0.2, 0.15 + 0.5 * progress)
	_aim_line.width = 1.0 + progress * 1.5
