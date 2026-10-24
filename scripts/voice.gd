# Telefonla sesli konuşma: mikrofonu yakalar, 16 kHz'e indirir, mu-law ile sıkıştırıp
# 40 ms'lik parçalar halinde yollar; gelen parçaları açıp hoparlörden çalar.
extends Node

signal packet_ready(data: PackedByteArray)

const RATE := 16000
const CHUNK := 640  # 40 ms
const GATE := 0.012  # bu sesten kısa (sessiz) parçalar yollanmaz

var active := false
var testing := false  # ayarlardaki mikrofon testi: sadece seviye ölçülür, hiçbir şey gönderilmez
var level := 0.0  # son mikrofon seviyesi (0-1)
var ptt_enabled := false  # bas-konuş: sadece düğmeye basılıyken ses gider
var ptt_down := false
var test_tone := false  # testte mikrofon yerine bip sesi yollar
var received_packets := 0
var sent_packets := 0

var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _out_player: AudioStreamPlayer
var _out: AudioStreamGeneratorPlayback
var _pending: PackedFloat32Array = PackedFloat32Array()
var _resample_pos := 0.0
var _tone_phase := 0.0
var _remote_level_t := 0.0
var _queue: Array[PackedFloat32Array] = []
var _primed := false


func _ready() -> void:
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Mikrofon")
	AudioServer.set_bus_mute(bus, true)  # kendi sesini duyma
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(bus, _capture)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Mikrofon"
	add_child(_mic_player)

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.6
	_out_player = AudioStreamPlayer.new()
	_out_player.stream = gen
	_out_player.volume_db = 4.0
	add_child(_out_player)
	for a in OS.get_cmdline_user_args():
		if a == "tone=1":
			test_tone = true


func start() -> void:
	if active:
		return
	active = true
	_pending.clear()
	_queue.clear()
	_primed = false
	_capture.clear_buffer()
	if not test_tone:
		_mic_player.play()
	_out_player.play()
	_out = _out_player.get_stream_playback()


func stop() -> void:
	active = false
	_mic_player.stop()
	_out_player.stop()
	_out = null


static func _enc(x: float) -> int:
	var s := clampf(x, -1.0, 1.0)
	var m := log(1.0 + 255.0 * absf(s)) / log(256.0)
	return (0x80 if s < 0.0 else 0) | int(round(m * 127.0))


static func _dec(b: int) -> float:
	var v := (pow(256.0, float(b & 0x7f) / 127.0) - 1.0) / 255.0
	return -v if (b & 0x80) != 0 else v


func start_test() -> void:
	testing = true
	_capture.clear_buffer()
	_mic_player.play()


func stop_test() -> void:
	testing = false
	level = 0.0
	if not active:
		_mic_player.stop()


func _process(delta: float) -> void:
	if testing and not active:
		var fr := _capture.get_frames_available()
		if fr > 0:
			var peak := 0.0
			for f in _capture.get_buffer(fr):
				peak = maxf(peak, absf(f.x))
			level = lerpf(level, clampf(peak * 2.5, 0.0, 1.0), 0.5)
		else:
			level = lerpf(level, 0.0, 0.1)
		return
	if not active:
		return
	_remote_level_t = maxf(0.0, _remote_level_t - delta)
	_read_input(delta)
	while _pending.size() >= CHUNK:
		var chunk := _pending.slice(0, CHUNK)
		_pending = _pending.slice(CHUNK)
		_send_chunk(chunk)
	_feed_output()


# Mikrofonu (ya da test bipini) 16 kHz tek kanala çevirip biriktirir.
func _read_input(delta: float) -> void:
	if test_tone:
		var n := int(RATE * delta)
		for i in n:
			_tone_phase += TAU * 440.0 / RATE
			var on := fmod(_tone_phase / TAU / 440.0, 1.0) < 0.5
			_pending.append(sin(_tone_phase) * 0.3 if on else 0.0)
		return
	var frames := _capture.get_frames_available()
	if frames <= 0:
		return
	var buf := _capture.get_buffer(frames)
	var step := AudioServer.get_mix_rate() / RATE
	while _resample_pos < buf.size() - 1:
		var i := int(_resample_pos)
		var f := _resample_pos - i
		var a := (buf[i].x + buf[i].y) * 0.5
		var b := (buf[i + 1].x + buf[i + 1].y) * 0.5
		_pending.append(lerpf(a, b, f))
		_resample_pos += step
	_resample_pos -= buf.size()


func _send_chunk(chunk: PackedFloat32Array) -> void:
	var rms := 0.0
	for v in chunk:
		rms += v * v
	rms = sqrt(rms / chunk.size())
	level = clampf(rms * 6.0, 0.0, 1.0)
	if rms < GATE or (ptt_enabled and not ptt_down):
		return
	# karşı taraf konuşurken hoparlörden mikrofona kaçan yankıyı bastır
	var gain := 0.25 if _remote_level_t > 0.0 else 1.0
	var data := PackedByteArray()
	data.resize(chunk.size())
	for i in chunk.size():
		data[i] = _enc(chunk[i] * gain * 1.6)
	sent_packets += 1
	packet_ready.emit(data)


func receive(data: PackedByteArray) -> void:
	if not active:
		return
	received_packets += 1
	var pcm := PackedFloat32Array()
	pcm.resize(data.size())
	for i in data.size():
		pcm[i] = _dec(data[i])
	_queue.append(pcm)
	_remote_level_t = 0.25


func _feed_output() -> void:
	if _out == null:
		return
	# ağdaki gecikme dalgalanmasına karşı 3 parça (120 ms) birikmeden çalmaya başlama
	if not _primed:
		if _queue.size() < 3:
			return
		_primed = true
	while not _queue.is_empty() and _out.get_frames_available() >= _queue[0].size():
		var pcm: PackedFloat32Array = _queue.pop_front()
		for v in pcm:
			_out.push_frame(Vector2(v, v))
	if _queue.is_empty() and _out.get_frames_available() > RATE * 0.5:
		_primed = false
	if _queue.size() > 12:
		_queue = _queue.slice(_queue.size() - 4)  # çok geride kaldıysa yetiş


func set_volume(v: float) -> void:
	_out_player.volume_db = linear_to_db(maxf(v, 0.001)) + 4.0
