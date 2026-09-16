extends PanelContainer

## ClassCard — Скрипт карточки героя с органическими ликвид-формами
## Обеспечивает:
## 1. 100% кликабельность по всей площади (игнор мыши дочерними нодами).
## 2. Управление волновыми SDF-шейдерами (ликвид-карточка, витринный шар-пузырь, жидкие колбы статов).
## 3. Идеальное центрирование и парение оружия внутри сферы без выступов.
## 4. Плавные анимации hover и select.

signal card_clicked(card: PanelContainer)

const HOVER_SCALE: float = 1.035
const NORMAL_SCALE: float = 1.0
const ANIM_DURATION: float = 0.22

var is_hovered: bool = false
var is_selected: bool = false
var hover_amount: float = 0.0
var select_amount: float = 0.0

var _scale_tween: Tween
var _shader_tween: Tween

@onready var shader_bg: ColorRect = get_node_or_null("ShaderBackground")
@onready var orb_bg: ColorRect = find_child("OrbBackground", true, false)
@onready var weapon_pivot: Marker2D = find_child("WeaponPivot", true, false)

var _weapon_instance: Node2D = null
var _base_weapon_rot: float = 0.0
var _base_weapon_scale: float = 1.4
var _weapon_offset: Vector2 = Vector2.ZERO
var _anim_time: float = 0.0
var _accent_color: Color = Color(0.85, 0.72, 0.42)

# Шейдер жидких полос
var _liquid_bar_shader: Shader = preload("res://resources/shaders/liquid_bar.gdshader")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_set_mouse_filter_recursive(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	var empty_style = StyleBoxEmpty.new()
	add_theme_stylebox_override("panel", empty_style)
	
	_setup_liquid_bars()
	_update_shader_materials()


func _set_mouse_filter_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Control and child != shader_bg:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_mouse_filter_recursive(child)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(self)


func _process(delta: float) -> void:
	_anim_time += delta
	if weapon_pivot and _weapon_instance:
		# Органическое левитирование оружия внутри сферы
		var float_amp = 3.0 if (is_hovered or is_selected) else 1.8
		var float_y = sin(_anim_time * 2.2) * float_amp
		var sway = sin(_anim_time * 1.5) * 0.035
		_weapon_instance.position = _weapon_offset + Vector2(0.0, float_y)
		_weapon_instance.rotation = _base_weapon_rot + sway


func setup_weapon(weapon_scene: PackedScene, base_rot_deg: float, base_scale: float, offset: Vector2, accent: Color) -> void:
	_accent_color = accent
	_base_weapon_rot = deg_to_rad(base_rot_deg)
	_base_weapon_scale = base_scale
	_weapon_offset = offset
	
	if shader_bg and shader_bg.material is ShaderMaterial:
		var mat = shader_bg.material as ShaderMaterial
		mat.set_shader_parameter("accent_color", _accent_color)
	
	if orb_bg and orb_bg.material is ShaderMaterial:
		var mat = orb_bg.material as ShaderMaterial
		mat.set_shader_parameter("glow_color", _accent_color)
	
	if not weapon_pivot:
		weapon_pivot = find_child("WeaponPivot", true, false)
	
	if weapon_pivot and weapon_scene:
		if _weapon_instance:
			_weapon_instance.queue_free()
		_weapon_instance = weapon_scene.instantiate() as Node2D
		if _weapon_instance:
			_weapon_instance.scale = Vector2(_base_weapon_scale, _base_weapon_scale)
			_weapon_instance.rotation = _base_weapon_rot
			_weapon_instance.position = _weapon_offset
			weapon_pivot.add_child(_weapon_instance)


func update_stat_bar(bar_name: String, current_val: float, max_val: float) -> void:
	var bar = find_child(bar_name, true, false) as ProgressBar
	if not bar:
		return
	bar.max_value = max_val
	bar.value = current_val
	if bar.material is ShaderMaterial:
		var progress_ratio = clamp(current_val / max_val if max_val > 0 else 0.0, 0.0, 1.0)
		(bar.material as ShaderMaterial).set_shader_parameter("progress", progress_ratio)


func _setup_liquid_bars() -> void:
	_setup_single_bar("HPBar", Color(0.88, 0.20, 0.26), Color(1.0, 0.40, 0.40))
	_setup_single_bar("DamageBar", Color(0.96, 0.58, 0.16), Color(1.0, 0.75, 0.30))
	_setup_single_bar("SpeedBar", Color(0.20, 0.88, 0.68), Color(0.40, 1.0, 0.85))


func _setup_single_bar(bar_name: String, liq_color: Color, liq_glow: Color) -> void:
	var bar = find_child(bar_name, true, false) as ProgressBar
	if not bar:
		return
	var mat = ShaderMaterial.new()
	mat.shader = _liquid_bar_shader
	mat.set_shader_parameter("vial_bg", Color(0.08, 0.06, 0.10, 0.9))
	mat.set_shader_parameter("liquid_color", liq_color)
	mat.set_shader_parameter("liquid_glow", liq_glow)
	mat.set_shader_parameter("glass_rim", Color(0.45, 0.38, 0.25, 0.8))
	mat.set_shader_parameter("bar_size", Vector2(148.0, 16.0))
	mat.set_shader_parameter("corner_radius", 4.0)
	var ratio = bar.value / bar.max_value if bar.max_value > 0 else 0.5
	mat.set_shader_parameter("progress", ratio)
	bar.material = mat


func _on_mouse_entered() -> void:
	is_hovered = true
	_animate_state()


func _on_mouse_exited() -> void:
	is_hovered = false
	_animate_state()


func set_selected(selected: bool) -> void:
	is_selected = selected
	_animate_state()


func _animate_state() -> void:
	var target_scale = HOVER_SCALE if (is_hovered and not is_selected) else (1.02 if is_selected else NORMAL_SCALE)
	var target_hover = 1.0 if is_hovered else 0.0
	var target_select = 1.0 if is_selected else 0.0
	
	if _scale_tween and _scale_tween.is_running():
		_scale_tween.kill()
	_scale_tween = create_tween().set_parallel(true)
	_scale_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_scale_tween.tween_property(self, "scale", Vector2(target_scale, target_scale), ANIM_DURATION)
	
	if _shader_tween and _shader_tween.is_running():
		_shader_tween.kill()
	_shader_tween = create_tween().set_parallel(true)
	_shader_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_shader_tween.tween_method(_set_hover_amount, hover_amount, target_hover, ANIM_DURATION)
	_shader_tween.tween_method(_set_select_amount, select_amount, target_select, ANIM_DURATION)


func _set_hover_amount(val: float) -> void:
	hover_amount = val
	_update_shader_materials()


func _set_select_amount(val: float) -> void:
	select_amount = val
	_update_shader_materials()


func _update_shader_materials() -> void:
	var c_size = size if size.x > 10 else Vector2(210, 320)
	if shader_bg and shader_bg.material is ShaderMaterial:
		var mat = shader_bg.material as ShaderMaterial
		mat.set_shader_parameter("hover_amount", hover_amount)
		mat.set_shader_parameter("select_amount", select_amount)
		mat.set_shader_parameter("card_size", c_size)
	
	if orb_bg and orb_bg.material is ShaderMaterial:
		var mat = orb_bg.material as ShaderMaterial
		mat.set_shader_parameter("hover_amount", hover_amount)
		mat.set_shader_parameter("select_amount", select_amount)
