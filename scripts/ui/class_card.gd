extends PanelContainer

## ClassCard — скрипт для анимации карточки персонажа (hover, scale)

const HOVER_SCALE: float = 1.05
const NORMAL_SCALE: float = 1.0
const HOVER_DURATION: float = 0.2

var _is_hovered: bool = false
var _tween: Tween
var _is_selected: bool = false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_update_hover_state()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_update_hover_state()


func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_hover_state()


func _update_hover_state() -> void:
	# Если карточка выбрана — hover не применяем
	if _is_selected:
		_animate_to(NORMAL_SCALE)
		return
	
	# Если мышь над карточкой — hover
	if _is_hovered:
		_animate_to(HOVER_SCALE)
	else:
		_animate_to(NORMAL_SCALE)


func _animate_to(target_scale: float) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "scale", Vector2(target_scale, target_scale), HOVER_DURATION)
