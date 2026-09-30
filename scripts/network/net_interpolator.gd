extends RefCounted
class_name NetInterpolator
## NetInterpolator — буфер сетевых снимков позиции удалённой сущности.
##
## Отправитель нумерует снимки (seq = номер физического тика отправителя).
## Получатель показывает сущность с небольшой задержкой (interp_delay) и
## интерполирует между двумя соседними снимками — так рывки из-за джиттера и
## потерь пакетов не видны. Старые и переупорядоченные снимки отбрасываются.
## Эпоха (epoch) растёт при телепорте: снимки старой эпохи больше не применяются,
## поэтому персонаж не «откатывается» на позицию до телепорта.

## Интервал между снимками отправителя, мс (1000 / частота снимков)
var send_interval_ms: float = 1000.0 / 30.0
## Задержка показа подстраивается: ~1.2 интервала снимков + измеренный джиттер, в этих пределах
var min_delay_ms: float = 25.0
var max_delay_ms: float = 200.0
## Текущая задержка показа «в прошлом», мс (для отладки/замеров)
var interp_delay_ms: float = 60.0
## Как долго можно продолжать движение по скорости, если снимки перестали приходить
var max_extrapolation_ms: float = 100.0
## Длительность одного тика отправителя (seq → время)
var tick_ms: float = 1000.0 / 60.0

var epoch: int = 0
var last_seq: int = -1

# Снимок: {"t": время отправителя в мс, "pos": Vector2, "vel": Vector2, "extra": Array}
var _buffer: Array[Dictionary] = []
# Оценка сдвига часов «местное время − время отправителя» (минимум сглаживает джиттер)
var _clock_offset: float = INF
var _offset_samples: Array[float] = []

## Статистика для отладки/замеров
var dropped_old: int = 0
var dropped_stale_epoch: int = 0


## Добавить снимок. Возвращает false, если снимок устарел и отброшен.
func push(seq: int, snap_epoch: int, pos: Vector2, vel: Vector2, extra: Array = []) -> bool:
	if snap_epoch < epoch:
		dropped_stale_epoch += 1
		return false
	if snap_epoch > epoch:
		# Новая эпоха (телепорт у отправителя) — старая история больше не нужна
		reset(pos, snap_epoch)
	elif seq <= last_seq:
		dropped_old += 1
		return false
	last_seq = seq

	var sender_t: float = seq * tick_ms
	var now: float = Time.get_ticks_msec()
	_offset_samples.append(now - sender_t)
	if _offset_samples.size() > 60:
		_offset_samples.pop_front()
	# Минимальная задержка из последних ~2 секунд — самый «быстрый» пакет, без джиттера
	_clock_offset = _offset_samples.min()
	# Джиттер = 90-й перцентиль опоздания относительно самого быстрого пакета
	var late: Array[float] = []
	for o in _offset_samples:
		late.append(o - _clock_offset)
	late.sort()
	var jitter: float = late[int(late.size() * 0.9)] if late.size() > 4 else send_interval_ms
	interp_delay_ms = clampf(send_interval_ms + jitter, min_delay_ms, max_delay_ms)

	# Якорь после reset() (t = -INF) нужен только до первого настоящего снимка:
	# интерполяция между -INF и конечным временем дала бы NaN
	if _buffer.size() == 1 and is_inf(_buffer[0]["t"]):
		_buffer.clear()
	_buffer.append({"t": sender_t, "pos": pos, "vel": vel, "extra": extra})
	if _buffer.size() > 32:
		_buffer.pop_front()
	return true


## Сбросить историю (телепорт, новая жизнь, новый этаж)
func reset(pos: Vector2, new_epoch: int = -1) -> void:
	if new_epoch >= 0:
		epoch = new_epoch
	last_seq = -1
	_buffer.clear()
	_offset_samples.clear()
	_clock_offset = INF
	_buffer.append({"t": -INF, "pos": pos, "vel": Vector2.ZERO, "extra": []})


func has_data() -> bool:
	return not _buffer.is_empty()


## Интерполированное состояние на текущий момент: {"pos", "vel", "extra"}
func sample() -> Dictionary:
	if _buffer.is_empty():
		return {}
	if _buffer.size() == 1 or _clock_offset == INF:
		return _buffer[-1]

	var render_t: float = Time.get_ticks_msec() - _clock_offset - interp_delay_ms

	# Выбрасываем снимки, которые уже целиком в прошлом (оставляем один «до» render_t)
	while _buffer.size() > 2 and _buffer[1]["t"] <= render_t:
		_buffer.pop_front()

	var a: Dictionary = _buffer[0]
	if render_t <= a["t"]:
		return a
	if _buffer.size() >= 2:
		var b: Dictionary = _buffer[1]
		if render_t <= b["t"]:
			var k: float = (render_t - a["t"]) / maxf(0.001, b["t"] - a["t"])
			return {
				"pos": (a["pos"] as Vector2).lerp(b["pos"], k),
				"vel": (a["vel"] as Vector2).lerp(b["vel"], k),
				"extra": b["extra"] if k > 0.5 else a["extra"],
			}
	# Снимков новее нет — короткая экстраполяция по скорости, потом стоим
	var last: Dictionary = _buffer[-1]
	var ahead: float = minf(render_t - last["t"], max_extrapolation_ms)
	return {"pos": (last["pos"] as Vector2) + (last["vel"] as Vector2) * (ahead / 1000.0),
		"vel": last["vel"], "extra": last["extra"]}
