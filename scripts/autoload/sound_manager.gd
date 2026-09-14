extends Node

## SoundManager — глобальный аудио-менеджер для звуковых эффектов (Autoload)
## Поддерживает пул проигрывателей (до 16 одновременных звуков) и органичную микро-вариацию высоты звука (pitch).

const POOL_SIZE := 16

# Загрузка всех звуковых эффектов
var sfx_sword_swing: AudioStream = preload("res://resources/audio/sfx/sword_swing.wav")
var sfx_bow_shoot: AudioStream = preload("res://resources/audio/sfx/bow_shoot.wav")
var sfx_arrow_hit: AudioStream = preload("res://resources/audio/sfx/arrow_hit.wav")
var sfx_fireball_cast: AudioStream = preload("res://resources/audio/sfx/fireball_cast.wav")
var sfx_fireball_explosion: AudioStream = preload("res://resources/audio/sfx/fireball_explosion.wav")
var sfx_shield_bash: AudioStream = preload("res://resources/audio/sfx/shield_bash.wav")
var sfx_holy_shockwave: AudioStream = preload("res://resources/audio/sfx/holy_shockwave.wav")
var sfx_dash: AudioStream = preload("res://resources/audio/sfx/dash.wav")
var sfx_player_hurt: AudioStream = preload("res://resources/audio/sfx/player_hurt.wav")
var sfx_enemy_hit: AudioStream = preload("res://resources/audio/sfx/enemy_hit.wav")
var sfx_enemy_death: AudioStream = preload("res://resources/audio/sfx/enemy_death.wav")
var sfx_slime_lunge: AudioStream = preload("res://resources/audio/sfx/slime_lunge.wav")
var sfx_door_slam: AudioStream = preload("res://resources/audio/sfx/door_slam.wav")
var sfx_door_open: AudioStream = preload("res://resources/audio/sfx/door_open.wav")
var sfx_room_cleared: AudioStream = preload("res://resources/audio/sfx/room_cleared.wav")
var sfx_ui_click: AudioStream = preload("res://resources/audio/sfx/ui_click.wav")

var _players: Array[AudioStreamPlayer] = []
var _next_player_idx: int = 0
var _bus_name: String = "Master"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Проверяем наличие шины SFX
	for i in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i).to_lower() == "sfx":
			_bus_name = AudioServer.get_bus_name(i)
			break

	# Инициализируем пул проигрывателей
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = _bus_name
		add_child(p)
		_players.append(p)


func play_sound(stream: AudioStream, volume_db: float = 0.0, pitch_variation: float = 0.07) -> void:
	if stream == null or _players.is_empty():
		return

	var p: AudioStreamPlayer = _players[_next_player_idx]
	_next_player_idx = (_next_player_idx + 1) % _players.size()

	p.stream = stream
	p.volume_db = volume_db
	if pitch_variation > 0.0:
		p.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	else:
		p.pitch_scale = 1.0

	p.play()


# ── Специфические методы для оружия и способностей ──

func play_sword_swing() -> void:
	play_sound(sfx_sword_swing, -2.0, 0.08)

func play_bow_shoot() -> void:
	play_sound(sfx_bow_shoot, -4.0, 0.08)

func play_arrow_hit() -> void:
	play_sound(sfx_arrow_hit, -3.0, 0.09)

func play_fireball_cast() -> void:
	play_sound(sfx_fireball_cast, -2.0, 0.06)

func play_fireball_explosion() -> void:
	play_sound(sfx_fireball_explosion, 0.0, 0.05)

func play_shield_bash() -> void:
	play_sound(sfx_shield_bash, -1.0, 0.07)

func play_holy_shockwave() -> void:
	play_sound(sfx_holy_shockwave, -5.0, 0.05)

func play_dash() -> void:
	play_sound(sfx_dash, -4.0, 0.08)

func play_player_hurt() -> void:
	play_sound(sfx_player_hurt, 0.0, 0.06)

func play_enemy_hit() -> void:
	play_sound(sfx_enemy_hit, -4.0, 0.10)

func play_enemy_death() -> void:
	play_sound(sfx_enemy_death, -2.0, 0.08)

func play_slime_lunge() -> void:
	play_sound(sfx_slime_lunge, -5.0, 0.09)

func play_door_slam() -> void:
	play_sound(sfx_door_slam, -2.0, 0.04)

func play_door_open() -> void:
	play_sound(sfx_door_open, -2.0, 0.05)

func play_room_cleared() -> void:
	play_sound(sfx_room_cleared, -1.0, 0.0)

func play_ui_click() -> void:
	play_sound(sfx_ui_click, -6.0, 0.03)
