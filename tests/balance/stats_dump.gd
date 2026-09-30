extends Node
## Снимок итоговых параметров после spawn (P0 баланса): классы, оружие, враги.
## Запуск: godot --path . res://tests/balance/stats_dump.tscn -- out=C:/tmp/stats.md
## Параметры читаются с живых экземпляров в игровой сцене, после всех _ready и переопределений.

const ENEMIES := {
	"Слайм": "res://scenes/enemies/slime.tscn",
	"Скелет": "res://scenes/enemies/skeleton.tscn",
	"Лучник": "res://scenes/enemies/archer.tscn",
	"Летучая мышь": "res://scenes/enemies/bat.tscn",
	"Слайм-босс": "res://scenes/enemies/slime_boss.tscn",
}


func _ready() -> void:
	if name != "StatsDump":
		var h := Node.new()
		h.set_script(get_script())
		h.name = "StatsDump"
		get_tree().root.add_child.call_deferred(h)
		return
	await get_tree().process_frame
	var out_path: String = "user://stats_dump.md"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out_path = a.substr(4)

	GameManager.selected_class = GameManager.PlayerClass.WARRIOR
	GameManager.start_new_game()
	for i in 60:
		await get_tree().process_frame
	var game := get_tree().current_scene
	while game.get("_player") == null:
		await get_tree().process_frame

	var lines: PackedStringArray = []
	lines.append("# Итоговые параметры после spawn")
	lines.append("")
	lines.append("Godot %s, этаж %d, difficulty_multiplier %.2f." % [Engine.get_version_info().string, GameManager.current_floor, GameManager.difficulty_multiplier])
	lines.append("")
	lines.append("## Классы")
	lines.append("")
	lines.append("| Класс | HP | Скорость | Урон оружия | Кулдаун, с | Отбрасывание | Снижение урона | Урон в UI (CLASS_DATA) |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
	for cls in [0, 1, 2, 3]:
		var p: Player = game._spawn_player_node(100 + cls, cls, Vector2(-5000 - cls * 200, -5000))
		for i in 3:
			await get_tree().process_frame
		var w: BaseWeapon = p.current_weapon
		var data: Dictionary = GameManager.CLASS_DATA[cls]
		lines.append("| %s | %d/%d | %.0f | %d | %.2f | %.0f | %.0f%% | %d |" % [data["name"],
			p.health_component.current_health, p.health_component.max_health, p.speed,
			w.damage, w.attack_cooldown, w.knockback_force, p.hurtbox.damage_reduction * 100.0,
			data["stats"]["damage"]])
		p.queue_free()

	lines.append("")
	lines.append("## Враги")
	lines.append("")
	lines.append("| Тип | HP текущее/макс | contact_damage | Урон хитбокса | Скорость ИИ | Дистанция атаки (у лучника — выстрела) | Замах, с | Удар, с | Восстановление, с | Сопр. отбрасыванию |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	var room: Room = game._dungeon.get_start_room()
	for enemy_name in ENEMIES:
		var e: Node2D = load(ENEMIES[enemy_name]).instantiate()
		e.position = Vector2(-9000, -9000)
		room.spawn_root.add_child(e)
		for i in 3:
			await get_tree().process_frame
		var hc: HealthComponent = e.get_node("HealthComponent")
		var hb := e.get_node_or_null("AttackArea") as HitboxComponent
		var ai: SlimeAI = null
		for c in e.get_children():
			if c is SlimeAI:
				ai = c
		lines.append("| %s | %d/%d | %d | %s | %.0f | %.0f | %.2f | %.2f | %.2f | %.1f |" % [enemy_name,
			hc.current_health, hc.max_health, e.contact_damage,
			str(hb.damage) if hb else "стрела", ai.base_speed, ai.shoot_range if ai is ArcherAI else ai.attack_range,
			ai.windup_time, ai.lunge_duration, ai.recover_time, e.knockback_resistance])
		e.queue_free()

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("\n".join(lines))
	get_tree().quit()
