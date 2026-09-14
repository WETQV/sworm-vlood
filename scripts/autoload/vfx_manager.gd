extends Node
## VFXManager — автозагружаемый менеджер эффектов и частиц (Game Juice).

var _default_fade_gradient: Gradient = null
var _spark_fade_gradient: Gradient = null
var _dust_fade_gradient: Gradient = null


func _ready() -> void:
	_init_gradients()


func _init_gradients() -> void:
	# Стандартный градиент: сохраняет яркость, затем плавно уходит в 0 по альфе
	_default_fade_gradient = Gradient.new()
	_default_fade_gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	_default_fade_gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.85),
		Color(1, 1, 1, 0.0)
	])

	# Градиент для искр: мягкое угасание в прозрачность
	_spark_fade_gradient = Gradient.new()
	_spark_fade_gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	_spark_fade_gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.8),
		Color(1, 1, 1, 0.0)
	])

	# Градиент для пыли и дыма: мягкий подъем и растворение
	_dust_fade_gradient = Gradient.new()
	_dust_fade_gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	_dust_fade_gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0.7),
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.6),
		Color(1, 1, 1, 0.0)
	])


func spawn_hit_particles(global_pos: Vector2, color: Color = Color("44cc44")) -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 10
	p.lifetime = 0.35
	p.spread = 180.0
	p.gravity = Vector2(0, 150)
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 150.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color

	_spawn_effect(p)


func spawn_death_burst(global_pos: Vector2, color: Color = Color("44cc44")) -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 18
	p.lifetime = 0.5
	p.spread = 180.0
	p.gravity = Vector2(0, 180)
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 220.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.0
	p.color = color

	_spawn_effect(p)


func spawn_spark(global_pos: Vector2, color: Color = Color(1.0, 0.8, 0.3)) -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 8
	p.lifetime = 0.25
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 180.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = color
	p.color_ramp = _spark_fade_gradient

	_spawn_effect(p)


func spawn_holy_nova(global_pos: Vector2, radius: float = 46.0) -> void:
	# 1. Аккуратный выброс золотых искр (мягкий свет, не ослепляет)
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.94
	p.amount = 10
	p.lifetime = 0.22
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 45.0
	p.initial_velocity_max = 95.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 2.8
	p.color = Color(1.0, 0.88, 0.45, 0.75)
	p.color_ramp = _spark_fade_gradient
	_spawn_effect(p)

	# 2. Тонкое золотистое кольцо ударной волны
	var ring := Line2D.new()
	ring.top_level = true
	ring.global_position = global_pos
	ring.width = 1.8
	ring.default_color = Color(1.0, 0.86, 0.4, 0.65)
	ring.z_index = 10
	var pts := PackedVector2Array()
	var segs := 20
	var base_r: float = radius * 0.4
	for i in range(segs + 1):
		var ang := float(i) / float(segs) * TAU
		pts.append(Vector2(cos(ang), sin(ang)) * base_r)
	ring.points = pts

	var scene: Node = _get_target_scene()
	if not scene:
		ring.queue_free()
		return
	scene.add_child(ring)

	var target_scale: float = radius / base_r
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(target_scale, target_scale), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(ring, "modulate:a", 0.0, 0.18).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


## Огненный взрыв при попадании файрбола (раскалённые угли + кольцо жара)
func spawn_fire_explosion(global_pos: Vector2) -> void:
	# 1. Частицы пламени и дыма
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 18
	p.lifetime = 0.38
	p.spread = 180.0
	p.gravity = Vector2(0, -30) # Поднимающийся жар
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 210.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(1.0, 0.42, 0.08, 1.0)
	_spawn_effect(p)

	# 2. Огненное кольцо тепловой волны
	var ring := Line2D.new()
	ring.top_level = true
	ring.global_position = global_pos
	ring.width = 3.5
	ring.default_color = Color(1.0, 0.65, 0.15, 0.95)
	ring.z_index = 10
	var pts := PackedVector2Array()
	var segs := 20
	for i in range(segs + 1):
		var ang := float(i) / float(segs) * TAU
		pts.append(Vector2(cos(ang), sin(ang)) * 14.0)
	ring.points = pts

	var scene: Node = _get_target_scene()
	if not scene:
		ring.queue_free()
		return
	scene.add_child(ring)

	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(3.5, 3.5), 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(ring, "modulate:a", 0.0, 0.22).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


## Кинетические пронзающие искры при попадании стрелы
func spawn_pierce_spark(global_pos: Vector2, dir: Vector2 = Vector2.ZERO) -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 12
	p.lifetime = 0.24
	if dir != Vector2.ZERO:
		p.direction = -dir # Осколки отлетают назад от точки удара
		p.spread = 70.0
	else:
		p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 220.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = Color(0.35, 1.0, 0.55, 1.0)
	p.color_ramp = _spark_fade_gradient
	_spawn_effect(p)


## Дуговой след взмаха клинка (Melee Slash Arc)
func spawn_slash_arc(global_pos: Vector2, angle: float, radius: float = 38.0, color: Color = Color(0.9, 0.95, 1.0, 0.9)) -> void:
	var arc := Line2D.new()
	arc.top_level = true
	arc.global_position = global_pos
	arc.width = 4.0
	arc.default_color = color
	arc.z_index = 8
	var pts := PackedVector2Array()
	var segs := 14
	var start_a := angle - 0.75
	var end_a := angle + 0.75
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var a: float = lerpf(start_a, end_a, t)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	arc.points = pts

	var scene: Node = _get_target_scene()
	if not scene:
		arc.queue_free()
		return
	scene.add_child(arc)

	var tween := arc.create_tween()
	tween.set_parallel(true)
	tween.tween_property(arc, "scale", Vector2(1.25, 1.25), 0.16).set_ease(Tween.EASE_OUT)
	tween.tween_property(arc, "modulate:a", 0.0, 0.16).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(arc.queue_free)


## Элегантные скоростные линии рывка (Speed Streaks) без клонирования тела персонажа
func spawn_dash_lines(global_pos: Vector2, dash_dir: Vector2, color: Color = Color(1.0, 1.0, 1.0, 0.85)) -> void:
	var perp: Vector2 = Vector2(-dash_dir.y, dash_dir.x).normalized() * 12.0
	var scene: Node = _get_target_scene()
	if not scene:
		return

	for side in [-1.0, 1.0]:
		var line := Line2D.new()
		line.top_level = true
		var start_pt: Vector2 = global_pos + perp * side
		var end_pt: Vector2 = start_pt - dash_dir * 32.0
		line.points = PackedVector2Array([start_pt, end_pt])
		line.width = 2.0
		line.default_color = color
		line.z_index = 3
		scene.add_child(line)

		var tween := line.create_tween()
		tween.tween_property(line, "modulate:a", 0.0, 0.10).set_ease(Tween.EASE_OUT)
		tween.tween_callback(line.queue_free)

	# Короткий веер пыли позади
	spawn_dash_puff(global_pos, dash_dir, color)


## Энергетический след / клубы пыли в начале рывка
func spawn_dash_puff(global_pos: Vector2, dash_dir: Vector2, color: Color = Color(0.75, 0.85, 1.0, 0.6)) -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 7
	p.lifetime = 0.18
	p.direction = -dash_dir
	p.spread = 45.0
	p.gravity = Vector2(0, 0)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 140.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.2
	p.color = color
	p.color_ramp = _dust_fade_gradient
	_spawn_effect(p)


## Компактный полупрозрачный след рывка (Dash Afterimage Streak)
func spawn_dash_ghost_streak(global_pos: Vector2, color: Color) -> void:
	var ghost := ColorRect.new()
	ghost.top_level = true
	ghost.size = Vector2(22, 22)
	ghost.position = global_pos - Vector2(11, 11)
	ghost.color = color.lightened(0.2)
	ghost.color.a = 0.28
	ghost.z_index = -1  # Строго ПОД персонажем, чтобы никогда не закрывать тело

	var scene: Node = _get_target_scene()
	if not scene:
		ghost.queue_free()
		return
	scene.add_child(ghost)

	var tween := ghost.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "scale", Vector2(0.4, 0.4), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "modulate:a", 0.0, 0.12).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ghost.queue_free)


## Легкие следы пыли при беге (Footstep Dust)
func spawn_footstep_dust(global_pos: Vector2, move_dir: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.90
	p.amount = 3
	p.lifetime = 0.20
	p.direction = -move_dir
	p.spread = 35.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 50.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.4
	p.color = Color(0.45, 0.45, 0.52, 0.35)
	p.color_ramp = _dust_fade_gradient
	_spawn_effect(p)


## Эффект материализации врага (выход из слизи / всплеск)
func spawn_enemy_spawn_burst(global_pos: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 14
	p.lifetime = 0.35
	p.spread = 180.0
	p.gravity = Vector2(0, -40) # Капли поднимаются вверх
	p.initial_velocity_min = 35.0
	p.initial_velocity_max = 80.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = Color(color.r, color.g, color.b, 0.8)
	_spawn_effect(p)

	# Кольцо жижи на полу
	var ring := Line2D.new()
	ring.top_level = true
	ring.global_position = global_pos
	ring.width = 2.0
	ring.default_color = Color(color.r, color.g, color.b, 0.6)
	ring.z_index = -1
	var pts := PackedVector2Array()
	var segs := 16
	for i in range(segs + 1):
		var ang := float(i) / float(segs) * TAU
		pts.append(Vector2(cos(ang), sin(ang)) * 8.0)
	ring.points = pts

	var scene: Node = _get_target_scene()
	if not scene:
		ring.queue_free()
		return
	scene.add_child.call_deferred(ring)

	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(2.8, 1.4), 0.30).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, 0.30).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


## Клубы каменной пыли при падении / разрушении решетки ворот
func spawn_door_slam_dust(global_pos: Vector2, rot: float) -> void:
	var p := CPUParticles2D.new()
	p.global_position = global_pos
	p.rotation = rot
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 16
	p.lifetime = 0.38
	p.direction = Vector2.UP
	p.spread = 90.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(80, 8)
	p.gravity = Vector2(0, 20)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.scale_amount_min = 1.8
	p.scale_amount_max = 3.5
	p.color = Color(0.55, 0.55, 0.62, 0.5)
	p.color_ramp = _dust_fade_gradient
	_spawn_effect(p)


func _get_target_scene() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if not tree:
		return null
	var scene: Node = tree.current_scene
	if not scene:
		scene = tree.root
	return scene


func _spawn_effect(particles: CPUParticles2D) -> void:
	if particles.color_ramp == null:
		if _default_fade_gradient == null:
			_init_gradients()
		particles.color_ramp = _default_fade_gradient

	var scene: Node = _get_target_scene()
	if not scene:
		particles.queue_free()
		return

	scene.add_child.call_deferred(particles)

	if is_inside_tree():
		var tree := get_tree()
		if tree:
			tree.create_timer(particles.lifetime + 0.1).timeout.connect(
				func() -> void:
					if is_instance_valid(particles):
						particles.queue_free()
			)
