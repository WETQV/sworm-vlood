extends Node

## SettingsManager — глобальный менеджер настроек (Autoload)

const SAVE_PATH := "user://settings.cfg"

# ── Аудио ────────────────────────────────────────────────────────────────────
var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0

# ── Видео ─────────────────────────────────────────────────────────────────────
var fullscreen: bool = false
var vsync: bool = true

# ── Управление ────────────────────────────────────────────────────────────────
var mouse_sensitivity: float = 1.0

# ── Сеть (заготовка) ─────────────────────────────────────────────────────────
var player_name: String = "Player"
var port: int = 7000

func _ready() -> void:
	load_settings()
	apply_settings()

func apply_settings() -> void:
	# Видео
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
	var vsync_mode := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)
	
	# Аудио
	if AudioServer.bus_count > 0:
		AudioServer.set_bus_volume_db(0, linear_to_db(master_volume))
	if AudioServer.bus_count > 1:
		AudioServer.set_bus_volume_db(1, linear_to_db(music_volume))
	if AudioServer.bus_count > 2:
		AudioServer.set_bus_volume_db(2, linear_to_db(sfx_volume))

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "vsync", vsync)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("network", "player_name", player_name)
	config.set_value("network", "port", port)
	config.save(SAVE_PATH)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	
	master_volume = config.get_value("audio", "master", master_volume)
	music_volume = config.get_value("audio", "music", music_volume)
	sfx_volume = config.get_value("audio", "sfx", sfx_volume)
	fullscreen = config.get_value("video", "fullscreen", fullscreen)
	vsync = config.get_value("video", "vsync", vsync)
	mouse_sensitivity = config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	player_name = config.get_value("network", "player_name", player_name)
	port = config.get_value("network", "port", port)
