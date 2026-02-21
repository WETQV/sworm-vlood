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

func _ready() -> void:
	add_to_group("enemy")

	health_component.died.connect(_on_died)
	health_component.health_changed.connect(_on_health_changed)
	hurtbox.damage_received.connect(_on_damage_received)

	# HP бар
	hp_bar.max_value = health_component.max_health
	hp_bar.value = health_component.current_health

	body_sprite.color = _color_normal


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


## HP изменилось
func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current


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
