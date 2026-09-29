extends Area2D
class_name Portal

@export var next_floor_level: int = 1
@export var wait_time: float = 10.0

@onready var timer: Timer = $Timer
@onready var status_label: Label = %StatusLabel

var _players_inside: Array[Node2D] = []
var _transitioning: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	timer.timeout.connect(_on_timer_timeout)
	status_label.text = ""

	# Эффектное появление портала при спавне
	scale = Vector2(0.05, 0.05)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	if _transitioning:
		return
		
	if not _players_inside.is_empty() and not timer.is_stopped():
		var remaining = ceil(timer.time_left)
		status_label.text = "Переход через: %d сек\n(Игроков: %d/%d)" % [
			remaining, 
			_players_inside.size(), 
			_get_total_players_count()
		]


func _on_body_entered(body: Node2D) -> void:
	if not NetworkManager.is_authority():
		return # кто в портале и когда переходить — решает хост
	if body.is_in_group("player") and not _players_inside.has(body):
		_players_inside.append(body)
		
		# Если это первый игрок — запускаем таймер
		if timer.is_stopped() and not _transitioning:
			timer.start(wait_time)
			
		# Проверяем, все ли зашли
		_check_all_players_present()


func _on_body_exited(body: Node2D) -> void:
	if _players_inside.has(body):
		_players_inside.erase(body)
		
		# Если все вышли, а таймер шёл — сбрасываем (опционально)
		# Но лучше оставить таймер, раз уж кто-то "задел" портал.
		if _players_inside.is_empty() and not _transitioning:
			status_label.text = ""


func _check_all_players_present() -> void:
	if _transitioning: return
	
	var total = _get_total_players_count()
	if _players_inside.size() >= total and total > 0:
		_trigger_transition()


func _on_timer_timeout() -> void:
	_trigger_transition()


func _trigger_transition() -> void:
	if _transitioning: return
	if NetworkManager.is_online():
		_net_play_transition.rpc()
	else:
		_play_transition()


@rpc("authority", "call_local", "reliable")
func _net_play_transition() -> void:
	_play_transition()


## Анимация перехода — у всех игроков; сам переход на этаж запускает хост
func _play_transition() -> void:
	if _transitioning: return
	_transitioning = true

	timer.stop()
	status_label.text = "ПЕРЕХОД..."

	# Эффект вихря частиц портала
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_spark"):
		vfx.spawn_spark(global_position, Color(0.85, 0.45, 1.0, 1.0))

	# Затягивание игроков в центр портала
	for p in _players_inside:
		if is_instance_valid(p):
			p.set_physics_process(false)
			var p_tween := create_tween()
			p_tween.set_parallel(true)
			p_tween.tween_property(p, "global_position", global_position, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			p_tween.tween_property(p, "scale", Vector2(0.1, 0.1), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Затемнение экрана с указанием следующего этажа
	var game = get_tree().current_scene
	if game and game.has_method("fade_out"):
		var gm = get_node_or_null("/root/GameManager")
		var fl: int = (gm.current_floor + 1) if gm else 2
		var tween: Tween = game.fade_out(0.8, fl)
		if tween:
			await tween.finished
	else:
		await get_tree().create_timer(0.8).timeout

	# Пауза для комфортного чтения надписи этажа
	await get_tree().create_timer(1.8).timeout

	if not NetworkManager.is_authority():
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("next_floor"):
		gm.next_floor()


func _get_total_players_count() -> int:
	return get_tree().get_nodes_in_group("player").size()
