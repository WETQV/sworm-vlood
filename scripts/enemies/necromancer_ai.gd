extends ArcherAI
class_name NecromancerAI
## NecromancerAI — некромант: держит дистанцию как лучник и чередует два действия.
## - Призыв (раз в summon_cooldown, пока живых прислужников меньше max_minions):
##   долгий замах с фиолетовым кругом-телеграфом, затем рядом поднимаются 2 скелета
##   (risen_skeleton: мало HP и урона). Со смертью некроманта прислужники рассыпаются.
## - Сгусток тьмы: медленный снаряд с линией прицела (как стрела лучника, но медленнее).
## Роль — приоритетная цель за спинами ближников: контригра — прорваться/зайти с фланга
## и убить его, пока не поднялась вторая волна. Паспорт — docs/encounter_catalog.md.
##
## Сеть: решает хост. Клиенты узнают, что идёт призыв, по нулевому направлению в событии
## замаха (_net_ai_event), и рисуют только телеграф — скелеты приходят через спавнер.

const RISEN_SCENE := preload("res://scenes/enemies/risen_skeleton.tscn")
const BOLT_COLOR := Color(0.75, 0.45, 1.0)

@export var summon_cooldown: float = 6.0
@export var first_summon_delay: float = 2.0
@export var summon_count: int = 2
@export var max_minions: int = 3

var _summon_timer: float = 0.0
var _summoning: bool = false
var _minions: Array[Node2D] = []
var _circle: Polygon2D


func _ready() -> void:
	super._ready()
	_summon_timer = first_summon_delay
	var hc := _body.get_node_or_null("HealthComponent") as HealthComponent
	if hc:
		hc.died.connect(_on_necromancer_died)


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_online() or multiplayer.is_server():
		_summon_timer -= delta
		_minions = _minions.filter(func(m: Node2D) -> bool:
			return is_instance_valid(m) and m.health_component.is_alive())
	super._physics_process(delta)


func _wants_summon() -> bool:
	return _summon_timer <= 0.0 and _minions.size() < max_minions


func _change_state(new_state: State) -> void:
	if new_state == State.WINDUP:
		var is_host := not NetworkManager.is_online() or multiplayer.is_server()
		# Хост решает; у клиента признак призыва — нулевое направление из события хоста
		_summoning = _wants_summon() if is_host else _lunge_dir == Vector2.ZERO
		if _summoning:
			current_state = new_state
			_state_timer = windup_time
			_lunge_dir = Vector2.ZERO
			if _aim_line:
				_aim_line.visible = false
			_show_circle(true)
			_play_squash_tween(Vector2(0.85, 1.2), windup_time)
			return
	if new_state == State.RECOVER or new_state == State.CHASE or new_state == State.IDLE:
		_show_circle(false)
	super._change_state(new_state)


func _process_windup(delta: float) -> void:
	if not _summoning:
		super._process_windup(delta)
		return
	_state_timer -= delta
	_body.velocity = _body.velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	_body.move_and_slide()
	if _circle:
		_circle.scale = Vector2.ONE * (1.4 - 0.6 * clampf(_state_timer / windup_time, 0.0, 1.0))
	if _state_timer <= 0.0:
		_change_state(State.LUNGE)


func _shoot() -> void:
	if _summoning:
		_summoning = false
		_show_circle(false)
		_summon()
		return
	var bolt := ARROW_SCENE.instantiate() as EnemyArrow
	bolt.direction = _lunge_dir
	bolt.speed = arrow_speed
	bolt.damage = _body.contact_damage if "contact_damage" in _body else 10
	bolt.attacker = _body
	bolt.modulate = BOLT_COLOR
	var from: Vector2 = event_origin if event_origin.is_finite() else _body.global_position
	bolt.global_position = from + _lunge_dir * 16.0
	var world_root: Node = get_tree().current_scene if get_tree().current_scene else _body.get_parent()
	world_root.add_child(bolt)


## Хост: поднять прислужников рядом (не в стене), учитывая предел живых
func _summon() -> void:
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx and vfx.has_method("spawn_holy_nova"):
		vfx.spawn_holy_nova(_body.global_position, 60.0)
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	_summon_timer = summon_cooldown
	var space_state := _body.get_world_2d().direct_space_state
	var game := get_tree().current_scene
	var spawned := 0
	for i in 6:
		if spawned >= summon_count or _minions.size() >= max_minions:
			break
		var dir := Vector2.RIGHT.rotated(TAU * (i + 0.5) / 6.0 + randf() * 0.3)
		var want := _body.global_position + dir * 56.0
		var hit := space_state.intersect_ray(PhysicsRayQueryParameters2D.create(_body.global_position, want + dir * 16.0, 1))
		if not hit.is_empty():
			continue # за стеной — пробуем другое направление
		var minion: Node2D
		if NetworkManager.is_online() and game and game.has_method("spawn_network_enemy"):
			minion = game.spawn_network_enemy(RISEN_SCENE, want)
		else:
			minion = RISEN_SCENE.instantiate()
			_body.get_parent().add_child(minion)
			minion.global_position = want # после добавления: у родителя-комнаты своё смещение
		_minions.append(minion)
		spawned += 1


func _on_necromancer_died(_killer: Node2D) -> void:
	_show_circle(false)
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	for minion in _minions:
		if is_instance_valid(minion) and minion.health_component.is_alive():
			minion.health_component.take_damage(minion.health_component.current_health)
	_minions.clear()


func _show_circle(on: bool) -> void:
	if on:
		if _circle == null:
			_circle = Polygon2D.new()
			var points := PackedVector2Array()
			for i in 24:
				points.append(Vector2.RIGHT.rotated(TAU * i / 24.0) * Vector2(52, 30))
			_circle.polygon = points
			_circle.color = Color(0.6, 0.25, 0.95, 0.28)
			_circle.z_index = -1
			_body.add_child(_circle)
		_circle.visible = true
		_circle.scale = Vector2(0.8, 0.8)
	elif _circle:
		_circle.visible = false
