# scripts/enemies/slime_ai.gd
extends Node

# ═════════════════════════════════════════════
# МОЗГ СЛАЙМА v2
# Адаптация к классу цели, уклонение от AoE,
# зигзаг-подход к дальникам
# ═════════════════════════════════════════════

# ─────────────────────────────────────────────
# ССЫЛКИ
# ─────────────────────────────────────────────

var swarm: SwarmManager = null
@onready var body: CharacterBody2D = get_parent()

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
# НАСТРОЙКИ РОЛЕЙ
# ─────────────────────────────────────────────

@export var flank_distance: float = 100.0
@export var orbit_radius: float = 150.0
@export var orbit_speed: float = 1.5
@export var retreat_distance: float = 120.0
@export var retreat_duration: float = 1.2
@export var attack_range: float = 35.0
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

## Кэш: PlayerInfo цели (обновляется при смене цели)
var _target_info: PlayerInfo = null
var _cached_target: CharacterBody2D = null

# ─────────────────────────────────────────────
# ИНИЦИАЛИЗАЦИЯ
# ─────────────────────────────────────────────

func _ready() -> void:
	swarm = _find_swarm_manager()
	if swarm:
		swarm.register_slime(body)
	_randomize_personality()


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
	if not swarm:
		return
	if not is_instance_valid(assigned_target):
		# Нет цели — стоим (менеджер скоро назначит)
		body.velocity = Vector2.ZERO
		return

	# Обновляем кэш PlayerInfo
	_update_target_info()

	# Таймеры
	_attack_timer -= delta
	if _is_retreating:
		_retreat_timer -= delta
		if _retreat_timer <= 0.0:
			_is_retreating = false

	# ── 1. Целевая позиция по роли + адаптация к классу ──
	var target_pos := _get_role_target_position()

	# ── 2. Boids-силы ──
	# Separation — ОТ ВСЕХ слаймов (чтобы разные отряды не слипались)
	var all_neighbors: Array[CharacterBody2D] = swarm.get_all_neighbors(body, neighbor_radius)
	var separation := _calc_separation(all_neighbors) * weight_separation

	# Cohesion + Alignment — только среди СВОЕГО отряда
	var squad_neighbors: Array[CharacterBody2D] = swarm.get_squad_neighbors(
		body, assigned_player_id, neighbor_radius
	)
	var cohesion := _calc_cohesion(squad_neighbors) * weight_cohesion
	var alignment := _calc_alignment(squad_neighbors) * weight_alignment

	# ── 3. Направление к целевой позиции ──
	var to_target := Vector2.ZERO
	if body.global_position.distance_to(target_pos) > 5.0:
		to_target = (target_pos - body.global_position).normalized() * weight_target

	# ── 4. Уклонение от опасных зон ──
	var danger_avoid := _calc_danger_avoidance() * weight_avoid_danger

	# ── 5. Зигзаг (против дальников) ──
	var zigzag := _calc_zigzag()

	# ── 6. Суммируем ──
	var desired := (
		to_target
		+ separation
		+ cohesion
		+ alignment
		+ danger_avoid
		+ zigzag
	).normalized()

	if desired.length() < 0.01:
		desired = Vector2.ZERO

	# ── 7. Скорость ──
	var speed := _get_current_speed()

	# ── 8. Двигаемся ──
	body.velocity = desired * speed
	body.move_and_slide()

	if desired.length() > 0.1:
		last_direction = desired

	# ── 9. Атака ──
	_try_attack()

# ─────────────────────────────────────────────
# АДАПТИВНАЯ ЦЕЛЕВАЯ ПОЗИЦИЯ
# ─────────────────────────────────────────────

func _get_role_target_position() -> Vector2:
	var player_pos: Vector2 = assigned_target.global_position
	var my_pos: Vector2 = body.global_position
	var dist_mult := _get_distance_multiplier()

	# Отступление
	if _is_retreating:
		var away := (my_pos - player_pos).normalized()
		return my_pos + away * retreat_distance * dist_mult

	match current_role:
		# ── RUSHER ──
		swarm.Role.RUSHER:
			# Против мечника: целимся чуть МИМО (не прямо в лоб)
			# Чтобы не попасть под AoE удар
			if _target_is_melee():
				var to_player := (player_pos - my_pos)
				if to_player.length() < 1.0:
					return player_pos
				var offset_angle := to_player.angle() + 0.3 * flank_side
				var offset_pos := player_pos + Vector2.from_angle(offset_angle) * 20.0
				return offset_pos
			else:
				# Против дальника: рашим прямо
				return player_pos

		# ── FLANKER ──
		swarm.Role.FLANKER:
			var to_player := (player_pos - my_pos)
			if to_player.length() < 1.0:
				return player_pos

			var base_angle: float = to_player.angle()
			var flank_angle: float = base_angle + (PI / 2.0) * flank_side

			# Адаптивная дистанция фланга
			var adaptive_flank := flank_distance * dist_mult
			var flank_pos := player_pos + Vector2.from_angle(flank_angle) * adaptive_flank

			# Если близко к точке фланга — атакуем
			if my_pos.distance_to(flank_pos) < 30.0:
				return player_pos

			return flank_pos

		# ── ORBITER ──
		swarm.Role.ORBITER:
			var time := Time.get_ticks_msec() / 1000.0

			# Против мечника кружим ДАЛЬШЕ
			var adaptive_orbit := orbit_radius * dist_mult

			# Против дальника кружим быстрее (чтобы сложнее попасть)
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
			var away := (my_pos - player_pos).normalized()
			return my_pos + away * retreat_distance

	return player_pos

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
# BOIDS
# ─────────────────────────────────────────────

func _calc_separation(neighbors: Array[CharacterBody2D]) -> Vector2:
	var force := Vector2.ZERO
	var my_pos := body.global_position

	for other in neighbors:
		var diff := my_pos - other.global_position
		var dist := diff.length()
		if dist < separation_radius and dist > 0.01:
			force += diff.normalized() * (separation_radius / dist)

	return force.normalized() if force.length() > 0.01 else Vector2.ZERO


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

func _try_attack() -> void:
	if _attack_timer > 0.0 or _is_retreating:
		return
	if not _is_in_attack_range():
		return

	# Просим токен для КОНКРЕТНОГО игрока
	if not swarm.request_attack_token(body, assigned_player_id):
		return

	_perform_attack()


func _perform_attack() -> void:
	# Урон через HealthComponent
	if assigned_target.has_node("HealthComponent"):
		assigned_target.get_node("HealthComponent").take_damage(10, body)

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

func _get_current_speed() -> float:
	var speed := personal_speed

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

	# Waiter двигается медленно
	if current_role == swarm.Role.WAITER:
		speed *= 0.6

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
