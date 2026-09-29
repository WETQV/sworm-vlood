extends SlimeAI
class_name SkeletonAI
## SkeletonAI — ИИ скелета-мечника.
## Погоня, кружение и обход стен наследуются от SlimeAI,
## но вместо прыжка скелет замахивается и рубит мечом по дуге:
## WINDUP (замах) -> LUNGE (шаг + удар мечом) -> RECOVER.

@export var swing_arc_deg: float = 150.0      ## Ширина дуги удара
@export var hitbox_offset: float = 22.0       ## Вынос зоны удара вперёд от центра

var _sword_pivot: Node2D
var _attack_area: Area2D


func _ready() -> void:
	super._ready()
	_sword_pivot = _body.get_node_or_null("Visuals/SwordPivot") as Node2D
	_attack_area = _body.get_node_or_null("AttackArea") as Area2D


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_aim_sword()


## Вне атаки меч смотрит на цель
func _aim_sword() -> void:
	if not _sword_pivot or not is_instance_valid(target_player):
		return
	if current_state in [State.WINDUP, State.LUNGE, State.RECOVER]:
		return
	var to_target: Vector2 = target_player.global_position - _body.global_position
	if to_target != Vector2.ZERO:
		_sword_pivot.rotation = lerp_angle(_sword_pivot.rotation, to_target.angle(), 0.25)


func _change_state(new_state: State) -> void:
	match new_state:
		State.WINDUP:
			current_state = new_state
			_state_timer = windup_time
			if is_instance_valid(target_player):
				_lunge_dir = (target_player.global_position - _body.global_position).normalized()
			# Замах: меч уходит назад-в-сторону — это телеграф для игрока
			var base_angle: float = _lunge_dir.angle()
			_tween_sword(base_angle - deg_to_rad(swing_arc_deg * 0.5), windup_time, Tween.EASE_OUT)
			_play_squash_tween(Vector2(0.9, 1.1), windup_time)

		State.LUNGE:
			current_state = new_state
			_state_timer = lunge_duration
			if _attack_area:
				_attack_area.position = _lunge_dir * hitbox_offset
			if _hitbox:
				_hitbox.set_active(true)
			# Удар: меч проходит всю дугу
			var base_angle: float = _lunge_dir.angle()
			_tween_sword(base_angle + deg_to_rad(swing_arc_deg * 0.5), lunge_duration, Tween.EASE_IN)
			var snd = get_node_or_null("/root/SoundManager")
			if snd and snd.has_method("play_sword_swing"):
				snd.play_sword_swing()
			var vfx = get_node_or_null("/root/VFXManager")
			if vfx and vfx.has_method("spawn_slash_arc"):
				vfx.spawn_slash_arc(_body.global_position + _lunge_dir * hitbox_offset, base_angle, 30.0, Color(0.85, 0.8, 0.7, 0.85))

		State.RECOVER:
			current_state = new_state
			_state_timer = recover_time
			if _hitbox:
				_hitbox.set_active(false)
			if _swarm and is_instance_valid(target_player):
				_swarm.release_attack_token(_body, target_player)
			_play_squash_tween(Vector2.ONE, 0.15)

		_:
			super._change_state(new_state)


func _tween_sword(target_rotation: float, duration: float, ease_type: Tween.EaseType) -> void:
	if not _sword_pivot:
		return
	# Крутим по кратчайшему пути, чтобы меч не делал лишний оборот
	var current: float = _sword_pivot.rotation
	target_rotation = current + wrapf(target_rotation - current, -PI, PI)
	var tween: Tween = create_tween()
	tween.tween_property(_sword_pivot, "rotation", target_rotation, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(ease_type)
