extends CharacterBody2D
## Slime.gd — простой враг, идёт к игроку и бьёт контактом

@onready var health_component: HealthComponent = $HealthComponent
@onready var attack_area: Area2D = $AttackArea
@onready var body_sprite: ColorRect = $Visuals/Body
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hp_bar: ProgressBar = $HPBar

# --- Настройки ---
@export var speed: float = 70.0
@export var contact_damage: int = 10
@export var attack_cooldown: float = 1.0
@export var stop_distance: float = 20.0
@export var detection_range: float = 2000.0

	# --- Внутреннее состояние ---
var _knockback_velocity: Vector2 = Vector2.ZERO

# --- Цвета ---
var _color_normal: Color = Color("44cc44")
var _color_damaged: Color = Color("ccaa44")      # Желтоватый (50-70% HP)
var _color_wounded: Color = Color("cc8844")       # Оранжевый (30-50% HP)
var _color_critical: Color = Color("cc4444")      # Красный (< 30% HP)

var _wobble_tween: Tween = null

func _ready() -> void:
	add_to_group("enemy")

	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	hurtbox.damage_received.connect(_on_damage_received)

	# HP бар
	hp_bar.max_value = health_component.max_health
	hp_bar.value = health_component.current_health

	body_sprite.color = _color_normal
	
	# Обновляем цвет сразу при старте
	_update_color_by_health()


func _physics_process(_delta: float) -> void:
	if not health_component.is_alive():
		return

	# Движение теперь управляется нодой SlimeAI (если она есть)
	# Отбрасывание всё еще обрабатываем тут
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 600.0 * _delta)

	if not has_node("SlimeAI"):
		velocity = _knockback_velocity
		move_and_slide()


## Получил урон — отбрасывание
func _on_damage_received(_amount: int, knockback: Vector2) -> void:
	_knockback_velocity = knockback


## HP изменилось — обновляем цвет и визуальные эффекты
func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	
	# Обновляем цвет по HP
	_update_color_by_health()


## Обновить цвет слайма в зависимости от процента HP
func _update_color_by_health() -> void:
	if not health_component:
		return
	
	var hp_percent = health_component.get_health_percent()
	
	# Останавливаем предыдущую дрожь
	if _wobble_tween:
		_wobble_tween.kill()
	
	if hp_percent < 0.2:
		# КРИТИЧЕСКОЕ HP (< 20%) — ярко-красный + дрожь
		body_sprite.color = _color_critical
		_start_wobble_animation()
	elif hp_percent < 0.4:
		# РАНЕНЫЙ (20-40%) — оранжевый
		body_sprite.color = _color_wounded
	elif hp_percent < 0.7:
		# ПОВРЕЖДЁН (40-70%) — желтоватый
		body_sprite.color = _color_damaged
	else:
		# ЗДОРОВ (70-100%) — зелёный
		body_sprite.color = _color_normal


## Анимация дрожи для критического HP
func _start_wobble_animation() -> void:
	# Слайм дрожит от боли (быстрое смещение вверх-вниз)
	_wobble_tween = create_tween().set_loops()
	_wobble_tween.tween_property(body_sprite, "position:y", -2.0, 0.08)
	_wobble_tween.tween_property(body_sprite, "position:y", 0.0, 0.08)


## Смерть
func _on_died(killed_by: Node2D) -> void:
	# Сообщаем убийце для threat-системы
	if is_instance_valid(killed_by) and killed_by.has_node("PlayerInfo"):
		killed_by.get_node("PlayerInfo").register_kill()
	
	set_physics_process(false)

	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)

	print("%s убит!" % name)
