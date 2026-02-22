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
	_transitioning = true
	
	timer.stop()
	status_label.text = "ПЕРЕХОД..."
	
	# Вызываем эффект затемнения в Game сцене
	var game = get_tree().current_scene
	if game and game.has_method("fade_out"):
		var tween = game.fade_out(0.6)
		if tween:
			await tween.finished
	
	GameManager.next_floor()


func _get_total_players_count() -> int:
	return get_tree().get_nodes_in_group("player").size()
