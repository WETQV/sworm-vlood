extends RefCounted
## «Страж этажа» — элитный вариант обычного врага во второй волне выходной арены 1–6.
## Видимый модификатор: золотая аура и подпись, крупнее, больше здоровья, почти не
## отбрасывается. Поведение и телеграфы прежние — игрок узнаёт роль, но не может
## «отжать» стража отбрасыванием. Цена угрозы — EncounterPlanner.ELITE_SURCHARGE.
## Применяется ДО добавления в дерево (до _ready) у всех участников: на хосте при спавне,
## у клиентов — в spawn_function сетевого спавнера по флагу elite.

const HP_FACTOR := 2.2
const DAMAGE_FACTOR := 1.25
const KNOCKBACK_RESISTANCE_FACTOR := 4.0
const VISUAL_SCALE := 1.3
const TINT := Color(1.0, 0.86, 0.45)


static func apply(enemy: Node2D) -> void:
	enemy.set_meta("elite", true)
	var health := enemy.get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.max_health = int(round(health.max_health * HP_FACTOR))
		health.current_health = health.max_health
	if "contact_damage" in enemy:
		enemy.contact_damage = int(round(enemy.contact_damage * DAMAGE_FACTOR))
	if "knockback_resistance" in enemy:
		enemy.knockback_resistance *= KNOCKBACK_RESISTANCE_FACTOR
	var visuals := enemy.get_node_or_null("Visuals") as Node2D
	if visuals:
		visuals.scale *= VISUAL_SCALE
		visuals.modulate = visuals.modulate * TINT
	var label := Label.new()
	label.name = "EliteLabel"
	label.text = "Страж"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	label.add_theme_constant_override("outline_size", 3)
	label.size = Vector2(60, 14)
	label.position = Vector2(-30, -44)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy.add_child(label)
