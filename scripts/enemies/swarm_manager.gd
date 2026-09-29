extends Node
class_name SwarmManager
## SwarmManager — координатор роя врагов.
## Распределяет цели между игроками и выдает токены атаки,
## предотвращая одновременный навал десятков мобов.

@export var max_attackers_per_player: int = 3
@export var reassign_interval: float = 0.5

var players: Array[CharacterBody2D] = []
var enemies: Array[CharacterBody2D] = []

# player -> Array[CharacterBody2D] (враги с активным токеном)
var _attack_tokens: Dictionary = {}
var _timer: float = 0.0


func _ready() -> void:
	add_to_group("swarm_manager")
	_find_players()


func _physics_process(delta: float) -> void:
	_timer += delta
	if _timer >= reassign_interval:
		_timer = 0.0
		_cleanup_and_refresh()


func _find_players() -> void:
	players.clear()
	for node in get_tree().get_nodes_in_group("player"):
		if node is CharacterBody2D and is_instance_valid(node):
			players.append(node as CharacterBody2D)


func _cleanup_and_refresh() -> void:
	# Список игроков обновляем всегда: в сети персонажи появляются не в один кадр
	_find_players()

	# Очистка невалидных врагов
	enemies = enemies.filter(func(e: CharacterBody2D) -> bool: return is_instance_valid(e))

	# Очистка токенов
	for p in _attack_tokens.keys():
		if not is_instance_valid(p):
			_attack_tokens.erase(p)
			continue
		var active: Array = _attack_tokens[p]
		_attack_tokens[p] = active.filter(func(e: CharacterBody2D) -> bool: return is_instance_valid(e))


## Регистрация врага
func register_enemy(enemy: CharacterBody2D) -> void:
	if is_instance_valid(enemy) and not enemies.has(enemy):
		enemies.append(enemy)


## Удаление врага
func unregister_enemy(enemy: CharacterBody2D) -> void:
	enemies.erase(enemy)
	for p in _attack_tokens.keys():
		_attack_tokens[p].erase(enemy)


## Запрос токена атаки (разрешения на рывок)
func request_attack_token(enemy: CharacterBody2D, target: CharacterBody2D) -> bool:
	if not is_instance_valid(enemy) or not is_instance_valid(target):
		return false

	if not _attack_tokens.has(target):
		_attack_tokens[target] = []

	var tokens: Array = _attack_tokens[target]
	if tokens.has(enemy):
		return true

	if tokens.size() < max_attackers_per_player:
		tokens.append(enemy)
		return true

	return false


## Освобождение токена после атаки/промаха
func release_attack_token(enemy: CharacterBody2D, target: CharacterBody2D) -> void:
	if is_instance_valid(target) and _attack_tokens.has(target):
		_attack_tokens[target].erase(enemy)


## Поиск наилучшей цели для врага (ближайший живой игрок)
func get_best_target_for(enemy: CharacterBody2D) -> CharacterBody2D:
	if not is_instance_valid(enemy) or players.is_empty():
		return null

	var best_target: CharacterBody2D = null
	var min_dist_sq: float = INF

	for p in players:
		if not is_instance_valid(p):
			continue
		var hc := p.get_node_or_null("HealthComponent") as HealthComponent
		if hc and not hc.is_alive():
			continue
		var dist_sq: float = enemy.global_position.distance_squared_to(p.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			best_target = p

	return best_target
