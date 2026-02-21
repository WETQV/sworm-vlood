extends Node
class_name SwarmManager

# ═════════════════════════════════════════════
# РОЕВОЙ МЕНЕДЖЕР v2
# Поддержка 1-4 игроков, адаптация к классам,
# отряды (squads), threat-система
# ═════════════════════════════════════════════

# ─────────────────────────────────────────────
# ПЕРЕЧИСЛЕНИЯ
# ─────────────────────────────────────────────

enum Strategy { SOLO, PACK, SWARM, HORDE }

enum Role {
	RUSHER,
	FLANKER,
	ORBITER,
	WAITER,
	RETREATER
}

# ─────────────────────────────────────────────
# НАСТРОЙКИ
# ─────────────────────────────────────────────

## Как часто пересчитывать отряды и роли
@export var reassign_interval: float = 0.6

## Базовое число атакующих на одного игрока
@export var base_attackers_per_player: int = 2

## Максимум атакующих на одного игрока
@export var max_attackers_per_player: int = 4

## Ближняя дистанция
@export var close_range: float = 80.0

## Средняя дистанция
@export var medium_range: float = 200.0

## Минимальный размер отряда (чтобы ни один игрок не остался без внимания)
@export var min_squad_size: int = 1

# ─── Веса для расчёта угрозы ───

## Вес дистанции (ближе = опаснее для слаймов → больше внимания)
@export var threat_weight_distance: float = 1.0

## Вес урона (кто больше убивает → больше угроза)
@export var threat_weight_damage: float = 1.5

## Вес низкого HP (раненый → легче добить → выше приоритет)
@export var threat_weight_low_hp: float = 2.0

## Вес класса (маг/лучник опаснее для роя → атакуем первым)
@export var threat_weight_class: float = 1.2

# ─────────────────────────────────────────────
# СОСТОЯНИЕ
# ─────────────────────────────────────────────

## Все живые слаймы
var slimes: Array[CharacterBody2D] = []

## Все игроки в игре
var players: Array[CharacterBody2D] = []

## Отряд: player_id → массив слаймов
## player_id = индекс в массиве players
var squads: Dictionary = {}  # { int: Array[CharacterBody2D] }

## Стратегия каждого отряда
var squad_strategies: Dictionary = {}  # { int: Strategy }

## Токены атаки PER PLAYER
var _attack_tokens: Dictionary = {}  # { int: Array[CharacterBody2D] }

## Угрозы PER PLAYER
var _threat_scores: Dictionary = {}  # { int: float }

## Таймер
var _reassign_timer: float = 0.0

# ─────────────────────────────────────────────
# ЖИЗНЕННЫЙ ЦИКЛ
# ─────────────────────────────────────────────

func _ready() -> void:
	add_to_group("swarm_manager")
	_find_players()


func _physics_process(delta: float) -> void:
	_reassign_timer -= delta
	if _reassign_timer <= 0.0:
		_reassign_timer = reassign_interval
		_find_players()
		_calculate_threats()
		_assign_squads()
		_assign_roles_for_all_squads()
		_cleanup_all_tokens()

# ─────────────────────────────────────────────
# РЕГИСТРАЦИЯ
# ─────────────────────────────────────────────

func register_slime(slime: CharacterBody2D) -> void:
	if slime not in slimes:
		slimes.append(slime)


func unregister_slime(slime: CharacterBody2D) -> void:
	slimes.erase(slime)
	# Убираем из всех отрядов и токенов
	for pid in squads:
		squads[pid].erase(slime)
	for pid in _attack_tokens:
		_attack_tokens[pid].erase(slime)

	# Сообщаем игрокам о убийстве (для threat-системы)
	# Тут нужно знать, кто убил — передаётся из HealthComponent
	# Пока пропускаем, register_kill вызывается из другого места


func _find_players() -> void:
	players.clear()
	var found := get_tree().get_nodes_in_group("player")
	for p in found:
		if p is CharacterBody2D and is_instance_valid(p):
			players.append(p as CharacterBody2D)

	# Инициализируем структуры для новых игроков
	for i in range(players.size()):
		if i not in squads:
			squads[i] = []
		if i not in _attack_tokens:
			_attack_tokens[i] = []
		if i not in _threat_scores:
			_threat_scores[i] = 0.0

# ─────────────────────────────────────────────
# THREAT-СИСТЕМА
# ─────────────────────────────────────────────
# Оцениваем каждого игрока: насколько он "важная цель".
# Чем выше threat → тем больше слаймов на него выделяем.
# ─────────────────────────────────────────────

func _calculate_threats() -> void:
	if players.is_empty() or slimes.is_empty():
		return

	var swarm_center := _get_swarm_center()

	for i in range(players.size()):
		var player := players[i]
		var info := _get_player_info(player)

		var threat := 0.0

		# ── Фактор дистанции ──
		# Чем ближе игрок к центру роя, тем он "опаснее"
		var dist := player.global_position.distance_to(swarm_center)
		var dist_factor := clampf(1.0 - (dist / 600.0), 0.1, 1.0)
		threat += dist_factor * threat_weight_distance

		if info:
			# ── Фактор урона ──
			# Кто убивает больше слаймов — тот приоритетнее
			var kill_factor := clampf(info.recent_kills / 5.0, 0.0, 1.0)
			threat += kill_factor * threat_weight_damage

			# ── Фактор низкого HP ──
			# Раненого легче добить → повышаем приоритет
			var hp_ratio := info.get_hp_ratio()
			var low_hp_factor := clampf(1.0 - hp_ratio, 0.0, 1.0)
			threat += low_hp_factor * threat_weight_low_hp

			# ── Фактор класса ──
			# Стеклянные пушки — приоритетные цели
			var class_factor := _get_class_priority(info.player_class)
			threat += class_factor * threat_weight_class

		_threat_scores[i] = threat


## Приоритет класса (выше = атакуем первым)
func _get_class_priority(pclass: int) -> float:
	match pclass:
		PlayerInfo.PlayerClass.MAGE:
			return 1.0    # стеклянная пушка → убить первым
		PlayerInfo.PlayerClass.RANGER:
			return 0.8    # тоже больно бьёт
		PlayerInfo.PlayerClass.WARRIOR:
			return 0.5    # танкует, но не так приоритетен
		PlayerInfo.PlayerClass.PALADIN:
			return 0.3    # танк-поддержка → в последнюю очередь
	return 0.5

# ─────────────────────────────────────────────
# РАСПРЕДЕЛЕНИЕ ПО ОТРЯДАМ
# ─────────────────────────────────────────────
# Каждый слайм назначается на одного игрока.
# Количество слаймов в отряде пропорционально угрозе игрока.
# ─────────────────────────────────────────────

func _assign_squads() -> void:
	if players.is_empty() or slimes.is_empty():
		return

	# ── Шаг 1: определяем квоты ──
	var total_threat := 0.0
	for pid in range(players.size()):
		total_threat += _threat_scores.get(pid, 1.0)

	if total_threat < 0.01:
		total_threat = 1.0

	var quotas: Dictionary = {}  # pid → желаемый размер отряда
	var total_slimes := slimes.size()

	for pid in range(players.size()):
		var ratio: float = _threat_scores.get(pid, 1.0) / total_threat
		var quota: int = max(min_squad_size, roundi(ratio * total_slimes))
		quotas[pid] = quota

	# Нормализуем, чтобы сумма квот = total_slimes
	var quota_sum := 0
	for pid in quotas:
		quota_sum += quotas[pid]

	# Если квот больше чем слаймов — урежем пропорционально
	if quota_sum > total_slimes:
		for pid in quotas:
			quotas[pid] = max(1, roundi(float(quotas[pid]) / quota_sum * total_slimes))

	# ── Шаг 2: очищаем старые отряды ──
	for pid in squads:
		squads[pid] = []

	# ── Шаг 3: назначаем слаймов ──
	# Для каждого слайма считаем "оценку назначения" к каждому игроку.
	# Это комбинация: близость к игроку × угроза игрока.
	# Затем жадно назначаем, пока квоты не заполнены.

	var unassigned := slimes.duplicate()
	var assigned_count: Dictionary = {}
	for pid in range(players.size()):
		assigned_count[pid] = 0

	# Сортируем игроков по убыванию угрозы (сначала набираем отряд
	# для самого приоритетного)
	var sorted_pids: Array[int] = []
	for pid in range(players.size()):
		sorted_pids.append(pid)
	sorted_pids.sort_custom(func(a, b):
		return _threat_scores.get(a, 0) > _threat_scores.get(b, 0)
	)

	for pid in sorted_pids:
		var player := players[pid]
		var player_pos := player.global_position
		var quota: int = quotas.get(pid, 1)

		# Сортируем неназначенных слаймов по близости к этому игроку
		unassigned.sort_custom(func(a: CharacterBody2D, b: CharacterBody2D) -> bool:
			return a.global_position.distance_squared_to(player_pos) \
				 < b.global_position.distance_squared_to(player_pos)
		)

		var to_assign := mini(quota, unassigned.size())
		for j in range(to_assign):
			var slime: CharacterBody2D = unassigned[j]
			if pid not in squads:
				squads[pid] = []
			squads[pid].append(slime)

			# Сообщаем слайму его новую цель
			var ai := _get_ai(slime)
			if ai:
				ai.assigned_target = player
				ai.assigned_player_id = pid

		# Убираем назначенных
		for j in range(to_assign - 1, -1, -1):
			unassigned.remove_at(j)

	# Оставшиеся (если есть) — на самого приоритетного
	if not unassigned.is_empty() and not sorted_pids.is_empty():
		var fallback_pid: int = sorted_pids[0]
		for slime: CharacterBody2D in unassigned:
			if fallback_pid not in squads:
				squads[fallback_pid] = []
			squads[fallback_pid].append(slime)
			var ai := _get_ai(slime)
			if ai:
				ai.assigned_target = players[fallback_pid]
				ai.assigned_player_id = fallback_pid

	# ── Шаг 4: обновляем стратегию каждого отряда ──
	for pid in squads:
		var squad_size: int = squads[pid].size()
		squad_strategies[pid] = _size_to_strategy(squad_size)

# ─────────────────────────────────────────────
# НАЗНАЧЕНИЕ РОЛЕЙ (ПО ОТРЯДАМ)
# ─────────────────────────────────────────────

func _assign_roles_for_all_squads() -> void:
	for pid in squads:
		if pid >= players.size():
			continue
		var player := players[pid]
		var squad: Array = squads[pid]
		var strategy: Strategy = squad_strategies.get(pid, Strategy.SOLO)
		var info := _get_player_info(player)

		_assign_roles_for_squad(squad, player, strategy, info)


func _assign_roles_for_squad(
	squad: Array,
	player: CharacterBody2D,
	strategy: Strategy,
	info: PlayerInfo
) -> void:
	if squad.is_empty():
		return

	var player_pos := player.global_position
	var is_melee := info.is_melee() if info else true

	# Сортируем по дистанции до СВОЕГО игрока
	squad.sort_custom(func(a: CharacterBody2D, b: CharacterBody2D) -> bool:
		return a.global_position.distance_squared_to(player_pos) \
			 < b.global_position.distance_squared_to(player_pos)
	)

	# ── Выбираем распределение ролей в зависимости от
	#    стратегии + класса цели ──

	var role_plan: Array = _get_role_plan(strategy, is_melee, squad.size())

	for i in range(squad.size()):
		var ai := _get_ai(squad[i])
		if not ai:
			continue
		var role: Role = role_plan[mini(i, role_plan.size() - 1)]
		ai.set_role(role, i)


## Генерирует массив ролей для отряда.
## Учитывает стратегию (сколько слаймов) и класс цели.
func _get_role_plan(strategy: Strategy, target_is_melee: bool, count: int) -> Array:
	var plan: Array = []

	match strategy:
		Strategy.SOLO:
			if target_is_melee:
				# Против мечника/паладина: оба фланкируют
				# Не лезем в лоб — обходим
				for _i in range(count):
					plan.append(Role.FLANKER)
			else:
				# Против дальника: рашим — нужно закрыть дистанцию
				for _i in range(count):
					plan.append(Role.RUSHER)

		Strategy.PACK:
			if target_is_melee:
				# vs мечник: 1 раш + остальные фланк/орбит
				plan.append(Role.RUSHER)
				for i in range(1, count):
					plan.append(Role.FLANKER if i % 2 == 0 else Role.ORBITER)
			else:
				# vs дальник: больше рашеров, нужно прорваться
				var rushers := ceili(count * 0.6)
				for _i in range(rushers):
					plan.append(Role.RUSHER)
				for _i in range(rushers, count):
					plan.append(Role.FLANKER)

		Strategy.SWARM:
			if target_is_melee:
				# vs мечник: мало рашеров, много фланкеров и орбитеров
				# Изматываем, не подставляемся под AoE
				var rushers := ceili(count * 0.2)
				var flankers := ceili(count * 0.4)
				for _i in range(rushers):
					plan.append(Role.RUSHER)
				for _i in range(flankers):
					plan.append(Role.FLANKER)
				for _i in range(rushers + flankers, count):
					plan.append(Role.ORBITER)
			else:
				# vs дальник: много рашеров, окружение
				var rushers := ceili(count * 0.4)
				var flankers := ceili(count * 0.35)
				for _i in range(rushers):
					plan.append(Role.RUSHER)
				for _i in range(flankers):
					plan.append(Role.FLANKER)
				for _i in range(rushers + flankers, count):
					plan.append(Role.ORBITER)

		Strategy.HORDE:
			if target_is_melee:
				# vs мечник: орбитеры + фланкеры + ожидающие, мало рашеров
				var rushers := ceili(count * 0.15)
				var flankers := ceili(count * 0.30)
				var orbiters := ceili(count * 0.30)
				for _i in range(rushers):
					plan.append(Role.RUSHER)
				for _i in range(flankers):
					plan.append(Role.FLANKER)
				for _i in range(orbiters):
					plan.append(Role.ORBITER)
				for _i in range(rushers + flankers + orbiters, count):
					plan.append(Role.WAITER)
			else:
				# vs дальник: давим массой
				var rushers := ceili(count * 0.35)
				var flankers := ceili(count * 0.30)
				var orbiters := ceili(count * 0.20)
				for _i in range(rushers):
					plan.append(Role.RUSHER)
				for _i in range(flankers):
					plan.append(Role.FLANKER)
				for _i in range(orbiters):
					plan.append(Role.ORBITER)
				for _i in range(rushers + flankers + orbiters, count):
					plan.append(Role.WAITER)

	# Добиваем до нужной длины, если вдруг не хватило
	while plan.size() < count:
		plan.append(Role.WAITER)

	return plan

# ─────────────────────────────────────────────
# ТОКЕНЫ АТАКИ (PER PLAYER)
# ─────────────────────────────────────────────

func request_attack_token(slime: CharacterBody2D, player_id: int) -> bool:
	if player_id not in _attack_tokens:
		_attack_tokens[player_id] = []

	var tokens: Array = _attack_tokens[player_id]
	if slime in tokens:
		return true

	var max_tokens := _get_max_attackers_for_player(player_id)
	if tokens.size() < max_tokens:
		tokens.append(slime)
		return true
	return false


func release_attack_token(slime: CharacterBody2D, player_id: int) -> void:
	if player_id in _attack_tokens:
		_attack_tokens[player_id].erase(slime)


func _get_max_attackers_for_player(player_id: int) -> int:
	if player_id >= players.size():
		return base_attackers_per_player

	var info := _get_player_info(players[player_id])
	if not info:
		return base_attackers_per_player

	# Танков можно атаковать бо́льшим числом — они выдержат
	# Стеклянных пушек — меньшим (и так помрут, а остальные
	# слаймы пусть давят других игроков)
	match info.player_class:
		PlayerInfo.PlayerClass.PALADIN:
			return max_attackers_per_player      # 4
		PlayerInfo.PlayerClass.WARRIOR:
			return base_attackers_per_player + 1  # 3
		PlayerInfo.PlayerClass.RANGER:
			return base_attackers_per_player       # 2
		PlayerInfo.PlayerClass.MAGE:
			return base_attackers_per_player       # 2

	return base_attackers_per_player


func _cleanup_all_tokens() -> void:
	for pid in _attack_tokens:
		_attack_tokens[pid] = _attack_tokens[pid].filter(
			func(s: CharacterBody2D): return is_instance_valid(s) and s in slimes
		)

# ─────────────────────────────────────────────
# УТИЛИТЫ
# ─────────────────────────────────────────────

func _size_to_strategy(count: int) -> Strategy:
	if count <= 2:
		return Strategy.SOLO
	elif count <= 5:
		return Strategy.PACK
	elif count <= 10:
		return Strategy.SWARM
	else:
		return Strategy.HORDE


func _get_ai(slime: CharacterBody2D) -> Node:
	if slime.has_node("SlimeAI"):
		return slime.get_node("SlimeAI")
	return null


func _get_player_info(player: CharacterBody2D) -> PlayerInfo:
	if player.has_node("PlayerInfo"):
		return player.get_node("PlayerInfo") as PlayerInfo
	return null


func _get_swarm_center() -> Vector2:
	if slimes.is_empty():
		return Vector2.ZERO
	var center := Vector2.ZERO
	for s in slimes:
		center += s.global_position
	return center / slimes.size()


## Получить соседей из ТОГО ЖЕ ОТРЯДА (для cohesion/alignment)
func get_squad_neighbors(slime: CharacterBody2D, player_id: int, radius: float) -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	var squad: Array = squads.get(player_id, [])
	var pos := slime.global_position

	for other in squad:
		if other == slime:
			continue
		if pos.distance_squared_to(other.global_position) < radius * radius:
			result.append(other)
	return result


## Получить ВСЕХ соседей (для separation — чтобы слаймы из разных
## отрядов тоже не слипались друг с другом)
func get_all_neighbors(slime: CharacterBody2D, radius: float) -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	var pos := slime.global_position

	for other in slimes:
		if other == slime:
			continue
		if pos.distance_squared_to(other.global_position) < radius * radius:
			result.append(other)
	return result
