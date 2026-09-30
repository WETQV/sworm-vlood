extends Area2D
## Личный предмет из сундука. Подбор определяет хост по пересечению с телом владельца
## (Progression.try_collect); у остальных участников предмет только отображается.

const Catalog := preload("res://scripts/progression/progression_catalog.gd")

var key: String = ""
var item_id: String = ""
var owner_id: int = 0

var _gem: Polygon2D
var _label: Label
var _time: float = 0.0
var _collected: bool = false


func setup(pickup_key: String, item: String, owner_peer: int) -> void:
	key = pickup_key
	item_id = item
	owner_id = owner_peer


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # тела игроков
	monitoring = true
	z_index = 4
	var shape := CircleShape2D.new()
	shape.radius = 22.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	var item: Dictionary = Catalog.ITEMS.get(item_id, {})
	_gem = Polygon2D.new()
	_gem.polygon = PackedVector2Array([Vector2(0, -14), Vector2(11, 0), Vector2(0, 14), Vector2(-11, 0)])
	_gem.color = Color(0.98, 0.78, 0.3) if item.has("skill") else Color(0.45, 0.9, 0.6)
	add_child(_gem)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	_label.add_theme_constant_override("outline_size", 4)
	_label.size = Vector2(180, 30)
	_label.position = Vector2(-90, -48)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	set_owner_id(owner_id)


func set_owner_id(owner_peer: int) -> void:
	owner_id = owner_peer
	if _label == null:
		return
	var item_name: String = Catalog.ITEMS.get(item_id, {}).get("name", Catalog.BLESSING["name"])
	var mine := owner_id == 0 or not NetworkManager.is_online() or owner_id == multiplayer.get_unique_id()
	var who := ""
	if NetworkManager.is_online() and owner_id != 0:
		who = "\n" + ("для вас" if mine else "для " + str(NetworkManager.players.get(owner_id, {}).get("name", "союзника")))
	_label.text = item_name + who
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7) if mine else Color(0.7, 0.72, 0.8))
	modulate.a = 1.0 if mine else 0.55


func _physics_process(delta: float) -> void:
	_time += delta
	if _gem:
		_gem.position.y = sin(_time * 3.0) * 3.0
		_gem.rotation = sin(_time * 1.7) * 0.15
	if _collected or not NetworkManager.is_authority():
		return
	for body in get_overlapping_bodies():
		if body is Player and Progression.try_collect(key, body):
			return


## Подобран (у всех участников по команде хоста)
func collect() -> void:
	if _collected:
		return
	_collected = true
	set_deferred("monitoring", false)
	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_room_cleared"):
		snd.play_room_cleared()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.6, 1.6), 0.25)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)
