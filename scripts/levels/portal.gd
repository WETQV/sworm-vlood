extends Area2D
class_name Portal

@export var next_floor_level: int = 1

func _ready() -> void:
	# Подключаем сигнал входа игрока в портал
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# Если это мультиплеер, тут будет вызов UI-окна подтверждения и RPC.
		# Для MVP просто переходим на следующий этаж сразу.
		if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
			call_deferred("_trigger_next_floor")

func _trigger_next_floor() -> void:
	GameManager.next_floor()
