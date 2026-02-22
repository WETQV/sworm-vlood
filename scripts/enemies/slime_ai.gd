# scripts/enemies/slime_ai.gd
extends Node
class_name SlimeAI

# ═════════════════════════════════════════════
# МОЗГ СЛАЙМА v2
# Адаптация к классу цели, уклонение от AoE,
# зигзаг-подход к дальникам
# ═════════════════════════════════════════════

# ─────────────────────────────────────────────
# ССЫЛКИ
# ─────────────────────────────────────────────

var swarm: SwarmManager = null
var body: CharacterBody2D = null
var nav_agent: NavigationAgent2D = null

## Назначенная цель (конкретный игрок, не один на всех)
var assigned_target: CharacterBody2D = null

## ID игрока в массиве SwarmManager.players
var assigned_player_id: int = 0

# ─────────────────────────────────────────────
# НАСТРОЙКИ ДВИЖЕНИЯ
# ─────────────────────────────────────────────

@export var base_speed: float = 100.0
@export var dash_speed: float = 200.0
@export var separation_radius: float = 40.0
@export var neighbor_radius: float = 120.0

# ─────────────────────────────────────────────
# ОБХОД ПРЕПЯТСТВИЙ (RAYCAST)
# ─────────────────────────────────────────────
@export var obstacle_avoidance_range: float = 30.0
@export var obstacle_avoidance_force: float = 50.0

# ─────────────────────────────────────────────
# НАСТРОЙКИ РОЛЕЙ
# ─────────────────────────────────────────────

@export var flank_distance: float = 100.0
@export var orbit_radius: float = 150.0
@export var orbit_speed: float = 1.5
@export var retreat_distance: float = 120.0
@export var retreat_duration: float = 1.2
@export var attack_range: float = 40.0
@export var attack_cooldown: float = 1.5

# ─────────────────────────────────────────────
# НАСТРОЙКИ АДАПТАЦИИ К КЛАССАМ
# ─────────────────────────────────────────────

## Множитель дистанции для ближних классов
## (держимся дальше от мечника/паладина)
@export var melee_distance_multiplier: float = 1.3

## Множитель дистанции для дальних классов
## (лезем ближе к магу/лучнику)
@export var ranged_distance_multiplier: float = 0.8

## Амплитуда зигзага при подходе к дальнику
@export var zigzag_amplitude: float = 40.0

## Частота зигзага
@export var zigzag_frequency: float = 3.0

## Радиус уклонения от опасных зон
@export var danger_avoid_radius: float = 30.0

## Сила уклонения от опасных зон
@export var danger_avoid_weight: float = 3.0

# ─────────────────────────────────────────────
# ВЕСА BOIDS-СИЛ
# ─────────────────────────────────────────────

@export var weight_separation: float = 1.5
@export var weight_cohesion: float = 0.3
@export var weight_alignment: float = 0.2
@export var weight_target: float = 1.0
@export var weight_avoid_danger: float = 2.5

# ─────────────────────────────────────────────
# СОСТОЯНИЕ
# ─────────────────────────────────────────────

var current_role: int = -1
var role_index: int = 0
var flank_side: float = 1.0
var orbit_offset: float = 0.0
var personal_speed: float = 100.0

var _attack_timer: float = 0.0
var _retreat_timer: float = 0.0
var _is_retreating: bool = false
var last_direction: Vector2 = Vector2.RIGHT
var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO

## Параметры для прыжка (Leap)
var _is_lunging: bool = false
var _lunge_timer: float = 0.0
@export var lunge_duration: float = 0.3
@export var lunge_speed_mult: float = 2.5

## Кэш: PlayerInfo цели (обновляется при смене цели)
var _target_info: PlayerInfo = null
var _cached_target: CharacterBody2D = null

# ─────────────────────────────────────────────
# ПРЕДСКАЗАНИЕ ДВИЖЕНИЯ ИГРОКА
# ─────────────────────────────────────────────
var _player_position_history: Array[Vector2] = []
var _predicted_player_position: Vector2 = Vector2.ZERO

# ─────────────────────────────────────────────
# УЯЗВИМЫЕ МОМЕНТЫ (EXPLOIT OPENINGS)
# ─────────────────────────────────────────────
## Игрок только что атаковал — есть окно для атаки
var _player_attack_window: float = 0.0
## Слайм находится за спиной игрока
var _is_behind_player: bool = false
## Бонус к урону за backstab
var backstab_multiplier: float = 1.5

# ─────────────────────────────────────────────
# ИНИЦИАЛИЗАЦИЯ
# ─────────────────────────────────────────────

var _is_ready: bool = false

func _ready() -> void:
	# Получаем ссылку на родительское тело
	body = get_parent() as CharacterBody2D
	
	# Навигацию получаем через call_deferred, чтобы убедиться, что все ноды добавлены
	call_deferred("_init_navigation")
	
	swarm = _find_swarm_manager()
	if swarm:
		swarm.register_slime(body)
	_randomize_personality()
	_is_ready = true


func _init_navigation() -> void:
	if body:
		nav_agent = body.get_node_or_null("NavigationAgent2D")


func _exit_tree() -> void:
	if swarm:
		swarm.unregister_slime(body)


func _randomize_personality() -> void:
	personal_speed = base_speed * randf_range(0.85, 1.15)
	orbit_offset = randf() * TAU
	flank_side = [-1.0, 1.0].pick_random()
	attack_cooldown *= randf_range(0.8, 1.2)

# ─────────────────────────────────────────────
# ОСНОВНОЙ ЦИКЛ
# ─────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# Проверяем, что слайм полностью инициализирован
	if not _is_ready or not body:
		body.velocity = Vector2.ZERO
		return

	# Проверяем, что слайм готов к работе
	if not swarm:
		body.velocity = Vector2.ZERO
		return

	if not is_instance_valid(assigned_target):
		# Нет цели — стоим (менеджер скоро назначит)
		body.velocity = Vector2.ZERO
		return
	
	# Отладка: проверка позиции
	if Engine.get_frames_drawn() % 120 == 0:
		print("[SlimeAI] My pos: ", body.global_position, " Target: ", assigned_target.global_position, " Role: ", current_role)

	# Проверяем, что тело имеет доступ к physics space
	if not body.is_inside_tree() or not body.get_world_2d():
		body.velocity = Vector2.ZERO
		return

	# Обновляем кэш PlayerInfo
	_update_target_info()
	
	# Предсказываем движение игрока
	_update_player_prediction()
	
	# Проверяем уязвимые моменты
	_update_exploit_openings(delta)
	
	# Проверка на застревание
	_check_if_stuck(delta)

	# Таймеры
	_attack_timer -= delta
	if _is_retreating:
		_retreat_timer -= delta
		if _retreat_timer <= 0.0:
			_is_retreating = false

	# ── 1. Целевая позиция по роли ──
	var target_pos := _get_role_target_position()

	# ── 2. Навигация через NavigationAgent2D ──
	var nav_direction := Vector2.ZERO
	if nav_agent:
		nav_agent.target_position = target_pos
		
		# Если мы еще не у цели
		if not nav_agent.is_navigation_finished():
			var next_path_pos := nav_agent.get_next_path_position()
			nav_direction = (next_path_pos - body.global_position).normalized()
	else:
		# Фолбэк, если навигация не инициализирована
		if body.global_position.distance_to(target_pos) > 10.0:
			nav_direction = (target_pos - body.global_position).normalized()

	# ── 3. Boids-силы ──
	var all_neighbors: Array[CharacterBody2D] = swarm.get_all_neighbors(body, neighbor_radius)
	var separation := _calc_separation(all_neighbors) * weight_separation
	
	# УСИЛЕННОЕ ОТТАЛКИВАНИЕ ОТ ИГРОКА (чтобы не залипать в хитбоксе)
	var dist_to_player_actual := body.global_position.distance_to(assigned_target.global_position)
	if dist_to_player_actual < 25.0 and not _is_lunging:
		var push_away := (body.global_position - assigned_target.global_position).normalized()
		# Сила выталкивания растёт при приближении к центру игрока
		var push_strength := (25.0 - dist_to_player_actual) * 2.5
		separation += push_away * push_strength

	# ── 4. Избегание препятствий (дополнительное к навигации) ──
	var obstacle_avoid := _calc_obstacle_avoidance() * obstacle_avoidance_force

	# ── 5. Уклонение от опасных зон ──
	var danger_avoid := _calc_danger_avoidance() * weight_avoid_danger

	# ── 6. Зигзаг (против дальников) ──
	var zigzag := _calc_zigzag()

	# ── 7. Суммируем ──
	var desired := (nav_direction + separation + obstacle_avoid + danger_avoid + zigzag).normalized()

	if desired.length() < 0.01:
		desired = Vector2.ZERO

	# ── 8. Скорость и движение ──
	var speed := _get_current_speed()
	
	# Проверка дистанции остановки, чтобы не "колбасило" в упор
	# Но для RUSHER или при атаке — не останавливаемся
	var stop_dist := 18.0
	if current_role == swarm.Role.RUSHER or _is_retreating:
		stop_dist = 5.0
		
	if dist_to_player_actual < stop_dist and not _is_retreating:
		# Если мы очень близко — только Boids (separation) чтобы разойтись
		body.velocity = separation * speed * 0.5
	else:
		body.velocity = desired * speed

	if body.is_inside_tree() and body.get_world_2d():
		body.move_and_slide()

	if desired.length() > 0.1:
		last_direction = desired

	# ── 9. Атака ──
	_try_attack()

	# ── 10. Таймер прыжка ──
	if _is_lunging:
		_lunge_timer -= delta
		if _lunge_timer <= 0.0:
			_is_lunging = false

# ─────────────────────────────────────────────
# АДАПТИВНАЯ ЦЕЛЕВАЯ ПОЗИЦИЯ
# ─────────────────────────────────────────────

func _get_role_target_position() -> Vector2:
	# ИСПОЛЬЗУЕМ ПРЕДСКАЗАННУЮ ПОЗИЦИЮ для RUSHER и FLANKER
	var player_pos: Vector2 = assigned_target.global_position
	var my_pos: Vector2 = body.global_position
	var dist_mult := _get_distance_multiplier()
	
	# Для RUSHER и FLANKER используем предсказанную позицию (перерезаем путь)
	var target_player_pos := player_pos
	if current_role == swarm.Role.RUSHER or current_role == swarm.Role.FLANKER:
		if _predicted_player_position != Vector2.ZERO:
			target_player_pos = _predicted_player_position

	# Отступление (после атаки или при низком HP)
	if _is_retreating or current_role == swarm.Role.RETREATER:
		# ТАКТИКА "ЖИВОЙ ЩИТ": ищем союзника, чтобы спрятаться
		var shield_pos := _find_meat_shield_position(player_pos)
		if shield_pos != Vector2.ZERO:
			return shield_pos
		
		# Если щита нет — используем умный отход от игрока
		var away := (my_pos - player_pos).normalized()
		var retreat_target := my_pos + away * retreat_distance * dist_mult
		
		# Если сзади стена (RayCast или NavMesh) — уходим вбок
		if _is_wall_at(retreat_target):
			# Вектор вбок (перпендикуляр)
			var side := Vector2(-away.y, away.x) * flank_side
			retreat_target = my_pos + side * retreat_distance
		
		return retreat_target

	match current_role:
		# ── RUSHER ──
		swarm.Role.RUSHER:
			# Против мечника: целимся чуть МИМО (не прямо в лоб)
			# Чтобы не попасть под AoE удар
			if _target_is_melee():
				var to_player := (target_player_pos - my_pos)
				if to_player.length() < 1.0:
					return target_player_pos
				var offset_angle := to_player.angle() + 0.3 * flank_side
				var offset_pos := target_player_pos + Vector2.from_angle(offset_angle) * 20.0
				return offset_pos
			else:
				# Против дальника: рашим прямо к предсказанной позиции
				return target_player_pos

		# ── FLANKER ──
		swarm.Role.FLANKER:
			var to_player := (target_player_pos - my_pos)
			if to_player.length() < 1.0:
				return target_player_pos

			var base_angle: float = to_player.angle()
			var flank_angle: float = base_angle + (PI / 2.0) * flank_side

			# Адаптивная дистанция фланга
			var adaptive_flank := flank_distance * dist_mult
			var flank_pos := target_player_pos + Vector2.from_angle(flank_angle) * adaptive_flank

			# Если близко к точке фланга — атакуем
			if my_pos.distance_to(flank_pos) < 30.0:
				return target_player_pos

			return flank_pos

		# ── ORBITER ──
		swarm.Role.ORBITER:
			# НОВОЕ: Нырок для атаки, если игрок уязвим или просто шанс "пробы"
			var should_dive := _check_for_opening() or (randf() < 0.015) 
			
			if should_dive:
				return target_player_pos # Летим прямо к игроку
			
			var time := Time.get_ticks_msec() / 1000.0
			var adaptive_orbit := orbit_radius * dist_mult
			var adaptive_speed := orbit_speed
			if _target_is_ranged():
				adaptive_speed *= 1.4

			var angle := time * adaptive_speed + orbit_offset
			return player_pos + Vector2.from_angle(angle) * adaptive_orbit

		# ── WAITER ──
		swarm.Role.WAITER:
			var to_player := (player_pos - my_pos).normalized()
			var wait_dist := orbit_radius * 1.5 * dist_mult
			return player_pos - to_player * wait_dist

		# ── RETREATER ──
		swarm.Role.RETREATER:
			# Уже обработано в блоке _is_retreating выше
			var shield_pos := _find_meat_shield_position(player_pos)
			if shield_pos != Vector2.ZERO:
				return shield_pos
			var away := (my_pos - player_pos).normalized()
			return my_pos + away * retreat_distance

	return player_pos

# ─────────────────────────────────────────────
# ПРЕДСКАЗАНИЕ ДВИЖЕНИЯ ИГРОКА
# ─────────────────────────────────────────────
# Запоминаем последние позиции игрока и предсказываем,
# где он будет через 0.5 секунды

func _update_player_prediction() -> void:
	if not is_instance_valid(assigned_target):
		_player_position_history.clear()
		_predicted_player_position = Vector2.ZERO
		return
	
	# Запоминаем последние 10 позиций (при 60 FPS = ~0.17 сек)
	_player_position_history.append(assigned_target.global_position)
	if _player_position_history.size() > 10:
		_player_position_history.pop_front()

	# Предсказываем: куда игрок движется?
	if _player_position_history.size() >= 2:
		var first := _player_position_history[0]
		var last := _player_position_history[-1]
		var velocity := (last - first) / float(_player_position_history.size())

		# Предсказываем на 0.5 сек вперёд (ограничиваем скорость)
		var max_predict := 100.0  # Максимум 100px вперёд
		_predicted_player_position = last + velocity.normalized() * minf(velocity.length() * 5.0, max_predict)
	else:
		_predicted_player_position = assigned_target.global_position
	
	# Отладка: выводим позицию раз в 60 кадров
	if Engine.get_frames_drawn() % 60 == 0:
		print("[SlimeAI] Target: ", assigned_target.global_position, " Predicted: ", _predicted_player_position)


# ─────────────────────────────────────────────
# УЯЗВИМЫЕ МОМЕНТЫ (EXPLOIT OPENINGS)
# ─────────────────────────────────────────────
# Слаймы видят, когда игрок атакует (окно для контратаки)
# и когда находятся за спиной игрока (backstab)

func _update_exploit_openings(delta: float) -> void:
	if not is_instance_valid(assigned_target):
		_player_attack_window = 0.0
		_is_behind_player = false
		return
	
	# Таймер окна атаки игрока
	if _player_attack_window > 0.0:
		_player_attack_window -= delta
	
	# Проверяем, атакует ли игрок сейчас (через PlayerInfo)
	if _target_info and _target_info.is_ability_active:
		# Игрок кастует способность — окно для атаки!
		_player_attack_window = 0.5  # 0.5 сек на атаку
	
	# Проверяем, находимся ли за спиной игрока
	var player_dir := assigned_target.velocity.normalized()
	if player_dir.length() < 0.1:
		# Игрок стоит — определяем по направлению к ближайшему слайму
		player_dir = (assigned_target.global_position - body.global_position).normalized()
	
	var to_player := (assigned_target.global_position - body.global_position).normalized()
	var dot := player_dir.dot(to_player)
	
	# Если dot < -0.5 — мы за спиной игрока (он смотрит в другую сторону)
	_is_behind_player = dot < -0.5


## Проверка на уязвимый момент для атаки
func _check_for_opening() -> bool:
	# Игрок атакует — окно для контратаки
	if _player_attack_window > 0.0:
		return true
	
	# Мы за спиной игрока — backstab!
	if _is_behind_player:
		return true
	
	return false


# ─────────────────────────────────────────────
# ПРОВЕРКА НА ЗАСТРЕВАНИЕ
# ─────────────────────────────────────────────
# Если слайм застрял на 1 сек — сбрасываем отступление

func _check_if_stuck(delta: float) -> void:
	if _last_position == Vector2.ZERO:
		_last_position = body.global_position
		return
	
	var moved := body.global_position.distance_to(_last_position)
	_last_position = body.global_position
	
	if moved < 5.0:  # Почти не двигается
		_stuck_timer += delta
		if _stuck_timer > 1.0:
			# Застрял на 1 сек — сбрасываем отступление
			if _is_retreating:
				_is_retreating = false
				_retreat_timer = 0.0
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0


# ─────────────────────────────────────────────
# ЗИГЗАГ (ПРОТИВ ДАЛЬНИКОВ)
# ─────────────────────────────────────────────
# Когда слайм бежит к лучнику/магу, он двигается волной,
# чтобы в него было сложнее попасть снарядами.

func _calc_zigzag() -> Vector2:
	if not _target_is_ranged():
		return Vector2.ZERO

	# Зигзаг только для рашеров и фланкеров
	if current_role != swarm.Role.RUSHER and current_role != swarm.Role.FLANKER:
		return Vector2.ZERO

	# Только если достаточно далеко (вблизи зигзаг не нужен)
	var dist := body.global_position.distance_to(assigned_target.global_position)
	if dist < 60.0:
		return Vector2.ZERO

	# Перпендикуляр к направлению на цель
	var to_target := (assigned_target.global_position - body.global_position).normalized()
	var perpendicular := Vector2(-to_target.y, to_target.x)

	# Синусоидальное смещение (у каждого слайма свой orbit_offset,
	# поэтому зигзаги не синхронны)
	var time := Time.get_ticks_msec() / 1000.0
	var zigzag_value := sin(time * zigzag_frequency + orbit_offset) * zigzag_amplitude

	# Ослабляем зигзаг с приближением
	var dist_factor := clampf(dist / 200.0, 0.0, 1.0)

	return perpendicular * zigzag_value * dist_factor * 0.01

# ─────────────────────────────────────────────
# УКЛОНЕНИЕ ОТ ОПАСНЫХ ЗОН
# ─────────────────────────────────────────────
# Слаймы видят, когда игрок активирует способность,
# и убегают из зоны поражения.

func _calc_danger_avoidance() -> Vector2:
	var force := Vector2.ZERO
	var my_pos := body.global_position

	# Проверяем ВСЕ опасные зоны всех игроков
	# (не только своей цели — чужой маг тоже может кастануть метеорит рядом)
	for player in swarm.players:
		var info := _get_info_for(player)
		if not info or not info.is_ability_active:
			continue

		var zone_center := info.ability_zone_center
		var zone_radius := info.ability_zone_radius + danger_avoid_radius

		var dist := my_pos.distance_to(zone_center)

		if dist < zone_radius and dist > 0.01:
			# Убегаем от центра зоны
			var away := (my_pos - zone_center).normalized()

			# Чем ближе к центру — тем сильнее паника
			var urgency := clampf(1.0 - (dist / zone_radius), 0.0, 1.0)

			# Щит паладина — особый случай: слаймы вообще не лезут в зону
			if info.ability_type == "shield":
				urgency *= 2.0

			force += away * urgency

	return force.normalized() if force.length() > 0.01 else Vector2.ZERO

# ─────────────────────────────────────────────
# BOIDS — УМНОЕ ИЗБЕГАНИЕ СОЮЗНИКОВ
# ─────────────────────────────────────────────
# ТЕПЕРЬ: слаймы сильнее избегают атакующих союзников,
# чтобы не мешать им атаковать

func _calc_separation(neighbors: Array[CharacterBody2D]) -> Vector2:
	var force := Vector2.ZERO
	var my_pos := body.global_position

	for other in neighbors:
		var diff := my_pos - other.global_position
		var dist := diff.length()
		
		if dist < separation_radius and dist > 0.01:
			var avoidance_strength := separation_radius / dist
			
			# УСИЛЕННОЕ ИЗБЕГАНИЕ: если союзник атакует — не мешаем ему
			var other_ai := _get_ai(other)
			if other_ai and other_ai.current_role == swarm.Role.RUSHER:
				# Атакующего слайма избегаем в 2 раза сильнее
				avoidance_strength *= 2.0
			
			# Также избегаем тех, кто ближе к игроку (они в "очереди" впереди)
			var dist_to_player := body.global_position.distance_to(assigned_target.global_position)
			var other_dist_to_player := other.global_position.distance_to(assigned_target.global_position)
			
			if other_dist_to_player < dist_to_player:
				# Этот слайм ближе к игроку — значит он в очереди впереди
				avoidance_strength *= 1.5
			
			force += diff.normalized() * avoidance_strength

	return force.normalized() if force.length() > 0.01 else Vector2.ZERO


# ─────────────────────────────────────────────
# ИЗБЕГАНИЕ ПРЕПЯТСТВИЙ
# ─────────────────────────────────────────────
# Простая проверка: если впереди стена — смещаемся вбок

func _calc_obstacle_avoidance() -> Vector2:
	var avoidance := Vector2.ZERO
	
	# Получаем RayCast из тела
	var raycast: RayCast2D = body.get_node_or_null("ObstacleRaycast")
	if not raycast:
		return Vector2.ZERO
	
	# Поворачиваем raycast в направлении движения
	if body.velocity.length() > 1.0:
		raycast.target_position = body.velocity.normalized() * obstacle_avoidance_range
		raycast.force_raycast_update()
		
		if raycast.is_colliding():
			# Препятствие найдено — смещаемся вбок
			var normal := raycast.get_collision_normal()
			avoidance = Vector2(-normal.y, normal.x)  # Перпендикулярно нормали
	
	return avoidance


func _calc_cohesion(neighbors: Array[CharacterBody2D]) -> Vector2:
	if neighbors.is_empty():
		return Vector2.ZERO

	var center := Vector2.ZERO
	for other in neighbors:
		center += other.global_position
	center /= neighbors.size()

	var to_center := center - body.global_position
	return to_center.normalized() if to_center.length() > 1.0 else Vector2.ZERO


func _calc_alignment(neighbors: Array[CharacterBody2D]) -> Vector2:
	if neighbors.is_empty():
		return Vector2.ZERO

	var avg_vel := Vector2.ZERO
	var count := 0
	for other in neighbors:
		if other.velocity.length() > 1.0:
			avg_vel += other.velocity.normalized()
			count += 1

	if count == 0:
		return Vector2.ZERO

	avg_vel /= count
	return avg_vel.normalized()

# ─────────────────────────────────────────────
# АТАКА
# ─────────────────────────────────────────────
# ТЕПЕРЬ: раненые слаймы (WAITER/RETREATER) атакуют реже
# + ВОЛНОВАЯ АТАКА: только активная волна атакует

func _try_attack() -> void:
	# ═════════════════════════════════════════════
	# ПРОВЕРКА ВОЛНЫ: только активная волна атакует
	# ═════════════════════════════════════════════
	if swarm and not swarm.is_slime_active_wave(body, assigned_player_id):
		# Не наша волна — ждём (но двигаемся к позиции)
		return
	
	# ═════════════════════════════════════════════
	# BACK LINE: раненые слаймы атакуют с шансом
	# ═════════════════════════════════════════════
	if current_role == swarm.Role.WAITER:
		# Раненые ждут момента — атакуют только 30% времени
		if randf() > 0.3:
			return  # Ждём, не атакуем

	if current_role == swarm.Role.RETREATER:
		# Отступающие атакуют только если игрок очень близко
		if not _is_in_attack_range():
			return
		if randf() > 0.5:
			return  # 50% шанс атаки
	
	# Обычная проверка для здоровых слаймов
	if _attack_timer > 0.0 or _is_retreating:
		return
	if not _is_in_attack_range():
		return

	# Просим токен для КОНКРЕТНОГО игрока
	if not swarm.request_attack_token(body, assigned_player_id):
		return

	_perform_attack()


func _perform_attack() -> void:
	# ═════════════════════════════════════════════
	# РЫВОК (LUNGE)
	# ═════════════════════════════════════════════
	_is_lunging = true
	_lunge_timer = lunge_duration
	
	# Небольшая пауза для эффекта замаха
	await get_tree().create_timer(0.05).timeout
	if not is_instance_valid(assigned_target): return

	# ═════════════════════════════════════════════
	# DAMAGE CALCULATION
	# ═════════════════════════════════════════════
	var damage := 10
	if body and "contact_damage" in body:
		damage = body.contact_damage
	
	if _check_for_opening():
		# Уязвимый момент — наносим больше урона!
		damage = int(damage * backstab_multiplier)
	
	# Урон через HealthComponent
	if assigned_target.has_node("HealthComponent"):
		assigned_target.get_node("HealthComponent").take_damage(damage, body)

	_attack_timer = attack_cooldown
	swarm.release_attack_token(body, assigned_player_id)
	_start_retreat()


func _start_retreat() -> void:
	_is_retreating = true
	_retreat_timer = retreat_duration

	# Против ближника — отступаем дольше и дальше
	if _target_is_melee():
		_retreat_timer *= 1.3

	flank_side *= -1.0

# ─────────────────────────────────────────────
# СКОРОСТЬ
# ─────────────────────────────────────────────
# ТЕПЕРЬ: раненые слаймы двигаются медленнее

func _get_current_speed() -> float:
	var speed := personal_speed
	
	# ═════════════════════════════════════════════
	# ПРЫЖОК (Leap Attack)
	# ═════════════════════════════════════════════
	if _is_lunging:
		return personal_speed * lunge_speed_mult

	# ═════════════════════════════════════════════
	# BACK LINE: раненые двигаются МЕДЛЕННЕЕ
	# ═════════════════════════════════════════════
	if current_role == swarm.Role.WAITER or current_role == swarm.Role.RETREATER:
		# Раненые не лезут вперёд — двигаются на 50% медленнее
		speed *= 0.5

	# Рашер ускоряется вблизи цели
	if current_role == swarm.Role.RUSHER:
		var dist := body.global_position.distance_to(assigned_target.global_position)
		if dist < swarm.close_range * 1.5:
			speed = dash_speed

	# Против дальника: базовая скорость чуть выше (нужно добежать)
	if _target_is_ranged():
		speed *= 1.1

	# Отступление чуть медленнее
	if _is_retreating:
		speed *= 0.8

	return speed

# ─────────────────────────────────────────────
# АДАПТИВНЫЕ МНОЖИТЕЛИ
# ─────────────────────────────────────────────

## Множитель дистанции по классу цели
func _get_distance_multiplier() -> float:
	if _target_is_melee():
		return melee_distance_multiplier    # 1.3 — держимся дальше
	elif _target_is_ranged():
		return ranged_distance_multiplier   # 0.8 — лезем ближе
	return 1.0

# ─────────────────────────────────────────────
# УТИЛИТЫ
# ─────────────────────────────────────────────

func _target_is_melee() -> bool:
	return _target_info != null and _target_info.is_melee()

func _target_is_ranged() -> bool:
	return _target_info != null and _target_info.is_ranged()

func _is_in_attack_range() -> bool:
	if not is_instance_valid(assigned_target):
		return false
	return body.global_position.distance_to(
		assigned_target.global_position
	) < attack_range

func _update_target_info() -> void:
	if assigned_target != _cached_target:
		_cached_target = assigned_target
		_target_info = _get_info_for(assigned_target)

func _get_info_for(player: CharacterBody2D) -> PlayerInfo:
	if is_instance_valid(player) and player.has_node("PlayerInfo"):
		return player.get_node("PlayerInfo") as PlayerInfo
	return null


## Получить AI компонент от другого слайма
func _get_ai(slime: CharacterBody2D) -> SlimeAI:
	if is_instance_valid(slime) and slime.has_node("SlimeAI"):
		return slime.get_node("SlimeAI") as SlimeAI
	return null


## Поиск позиции за спиной здорового союзника
func _find_meat_shield_position(player_pos: Vector2) -> Vector2:
	if not swarm: return Vector2.ZERO
	
	var best_shield: CharacterBody2D = null
	var min_dist := 9999.0
	
	# Ищем ближайшего здорового союзника (Рашер или Фланкер)
	for other in swarm.slimes:
		if other == body: continue
		
		var other_ai := _get_ai(other)
		if other_ai and (other_ai.current_role == swarm.Role.RUSHER or other_ai.current_role == swarm.Role.FLANKER):
			var d = body.global_position.distance_squared_to(other.global_position)
			if d < min_dist:
				min_dist = d
				best_shield = other
	
	if best_shield:
		# Позиция: за союзником относительно игрока
		var dir_from_player = (best_shield.global_position - player_pos).normalized()
		return best_shield.global_position + dir_from_player * 40.0 # Вставам на 40px сзади
	
	return Vector2.ZERO


## Проверка: есть ли в этой точке стена/препятствие?
func _is_wall_at(pos: Vector2) -> bool:
	if nav_agent and nav_agent.get_navigation_map():
		var closest = NavigationServer2D.map_get_closest_point(nav_agent.get_navigation_map(), pos)
		return pos.distance_to(closest) > 10.0 # Если ближайшая точка нави меша далеко — там стена
	return false


func set_role(role: int, index: int = 0) -> void:
	current_role = role
	role_index = index
	flank_side = 1.0 if index % 2 == 0 else -1.0

	# Уникальное смещение орбиты
	var squad_size := 1
	if swarm and assigned_player_id in swarm.squads:
		squad_size = maxi(swarm.squads[assigned_player_id].size(), 1)
	orbit_offset = (index * TAU) / squad_size

func _find_swarm_manager() -> SwarmManager:
	var managers := get_tree().get_nodes_in_group("swarm_manager")
	if managers.size() > 0:
		return managers[0] as SwarmManager
	var root := get_tree().current_scene
	if root.has_node("SwarmManager"):
		return root.get_node("SwarmManager") as SwarmManager
	return null
