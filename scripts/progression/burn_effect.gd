extends Node
## «Горение» мага: периодический урон по врагу. Живёт только на хосте (урон считает хост,
## клиентам приходит обычная вспышка попадания Hurtbox._net_hit_fx).
## Повторный поджог обновляет длительность и берёт больший урон, но не складывается.

var _tick_damage: int = 0
var _interval: float = 0.5
## Оставшиеся тики (счётчик, а не время: сравнение float теряло последний тик)
var _ticks_left: int = 0
var _timer: float = 0.0
var _attacker: Node2D = null


func ignite(tick_damage: int, duration: float, interval: float, attacker: Node2D) -> void:
	_interval = maxf(interval, 0.1)
	if _ticks_left <= 0:
		_timer = _interval
		_tick_damage = 0
	_tick_damage = maxi(_tick_damage, tick_damage)
	_ticks_left = maxi(_ticks_left, int(round(duration / _interval)))
	_attacker = attacker


func _physics_process(delta: float) -> void:
	if _ticks_left <= 0:
		return
	var body := get_parent() as Node2D
	var health := body.get_node_or_null("HealthComponent") as HealthComponent if body else null
	if health == null or not health.is_alive():
		queue_free()
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer += _interval
		_ticks_left -= 1
		var hurtbox := body.get_node_or_null("Hurtbox") as Hurtbox
		var source: Node2D = _attacker if is_instance_valid(_attacker) else null
		if hurtbox:
			# Без отбрасывания, мимо i-frames и не включая их
			hurtbox.receive_damage(_tick_damage, 0.0, body.global_position, source, true, false)
