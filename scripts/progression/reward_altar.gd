extends Area2D
class_name RewardAltar
## Сундук (CHEST) или святилище (SHRINE) в комнате. Создаётся комнатой у всех участников
## с одинаковым именем; касание героя проверяет только хост.
## Сундук: открывается один раз и выкладывает личный предмет каждому живому герою.
## Святилище: каждому коснувшемуся герою — его собственный выбор из трёх вариантов.

enum Kind { CHEST, SHRINE }

var kind: Kind = Kind.CHEST
## Ключ источника наград: этаж + комната — не повторяется между этажами и комнатами
var source_key: String = ""

var _body: Polygon2D
var _lid: Polygon2D
var _glow: Polygon2D
var _label: Label
var _opened: bool = false
var _touching: Dictionary = {}
var _time: float = 0.0


func setup(altar_kind: Kind, key: String) -> void:
	kind = altar_kind
	source_key = key


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	z_index = 3
	var shape := CircleShape2D.new()
	shape.radius = 40.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	_glow = Polygon2D.new()
	_glow.polygon = _circle(46.0)
	_glow.color = Color(1.0, 0.8, 0.35, 0.12) if kind == Kind.CHEST else Color(0.55, 0.75, 1.0, 0.16)
	add_child(_glow)
	if kind == Kind.CHEST:
		_body = _rect(Vector2(-24, -10), Vector2(48, 26), Color(0.45, 0.28, 0.14))
		_lid = _rect(Vector2(-26, -22), Vector2(52, 14), Color(0.62, 0.42, 0.18))
		_rect(Vector2(-4, -12), Vector2(8, 10), Color(0.95, 0.8, 0.35))
	else:
		_body = _rect(Vector2(-20, -8), Vector2(40, 24), Color(0.4, 0.42, 0.5))
		_rect(Vector2(-8, -40), Vector2(16, 34), Color(0.55, 0.58, 0.68))
		_lid = _rect(Vector2(-5, -54), Vector2(10, 10), Color(0.6, 0.85, 1.0))

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	_label.add_theme_constant_override("outline_size", 4)
	_label.size = Vector2(200, 16)
	_label.position = Vector2(-100, 26)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = "Сундук — подойдите, чтобы открыть" if kind == Kind.CHEST else "Святилище — подойдите, чтобы выбрать дар"
	add_child(_label)
	Progression.offers_closed.connect(_on_offers_closed)


func _circle(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 20:
		points.append(Vector2.RIGHT.rotated(TAU * i / 20.0) * Vector2(radius, radius * 0.55))
	return points


func _rect(pos: Vector2, size: Vector2, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y)])
	poly.color = color
	add_child(poly)
	return poly


func _physics_process(delta: float) -> void:
	_time += delta
	_glow.scale = Vector2.ONE * (1.0 + sin(_time * 2.2) * 0.06)
	if kind == Kind.SHRINE and _lid:
		_lid.position.y = sin(_time * 2.0) * 3.0
	if not NetworkManager.is_authority():
		return
	var now: Dictionary = {}
	for body in get_overlapping_bodies():
		var player := body as Player
		if player == null or not player.health_component.is_alive():
			continue
		now[player.peer_id] = true
		if _touching.has(player.peer_id):
			continue # реагируем только на новое касание, а не каждый кадр
		if kind == Kind.CHEST:
			if not _opened and Progression.open_chest(source_key, global_position):
				if NetworkManager.is_online():
					_net_open.rpc()
				else:
					_net_open()
		else:
			Progression.request_offers(source_key, player.peer_id)
	_touching = now


@rpc("authority", "reliable")
func _net_open() -> void:
	if _opened:
		return
	_opened = true
	_label.text = "Сундук открыт"
	var tween := create_tween()
	tween.tween_property(_lid, "rotation", -0.5, 0.25).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(_lid, "position", Vector2(-6, -10), 0.25)
	_glow.color = Color(1.0, 0.85, 0.4, 0.3)
	var snd = get_node_or_null("/root/SoundManager")
	if snd and snd.has_method("play_room_cleared"):
		snd.play_room_cleared()


func _on_offers_closed(offer_key: String) -> void:
	if kind == Kind.SHRINE and offer_key.begins_with(source_key + "#"):
		_label.text = "Святилище: дар получен"
		modulate = Color(0.75, 0.75, 0.8)
