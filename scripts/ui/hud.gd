extends CanvasLayer
class_name GameHUD
## GameHUD — внутриигровой интерфейс в стиле Dark Fantasy.
## Отображает здоровье с эффектом затухающего следа урона, класс и этаж.

@onready var hp_bar_front: ProgressBar = %HPBarFront
@onready var hp_bar_back: ProgressBar = %HPBarBack
@onready var hp_label: Label = %HPLabel
@onready var dash_bar: ProgressBar = %DashBar
@onready var class_label: Label = %ClassLabel
@onready var floor_label: Label = %FloorLabel

var _player: CharacterBody2D = null
var _damage_tween: Tween = null


func _ready() -> void:
	layer = 10
	if GameManager:
		set_floor(GameManager.current_floor)


func setup_player(player: CharacterBody2D) -> void:
	_player = player
	if not is_instance_valid(_player):
		return

	var health: HealthComponent = _player.health_component
	if health:
		hp_bar_front.max_value = health.max_health
		hp_bar_front.value = health.current_health
		hp_bar_back.max_value = health.max_health
		hp_bar_back.value = health.current_health
		_update_hp_text(health.current_health, health.max_health)

		health.health_changed.connect(_on_health_changed)

	if _player.has_signal("dash_cooldown_updated"):
		_player.dash_cooldown_updated.connect(_on_dash_cooldown_updated)

	if GameManager.CLASS_DATA.has(GameManager.selected_class):
		var class_name_str: String = GameManager.CLASS_DATA[GameManager.selected_class]["name"]
		if class_label:
			class_label.text = class_name_str.to_upper()


func set_floor(floor_num: int) -> void:
	if floor_label:
		floor_label.text = "ЭТАЖ %d" % floor_num


func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar_front.max_value = maximum
	hp_bar_back.max_value = maximum

	_update_hp_text(current, maximum)

	# Передняя полоска падает мгновенно
	hp_bar_front.value = current

	# Задняя полоска (след урона) плавно догоняет через задержку
	if _damage_tween and _damage_tween.is_valid():
		_damage_tween.kill()

	_damage_tween = create_tween()
	_damage_tween.tween_interval(0.35)
	_damage_tween.tween_property(hp_bar_back, "value", float(current), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_hp_text(current: int, maximum: int) -> void:
	if hp_label:
		hp_label.text = "%d / %d" % [current, maximum]


func _on_dash_cooldown_updated(current: float, max_time: float) -> void:
	if dash_bar:
		dash_bar.max_value = max_time
		dash_bar.value = current
