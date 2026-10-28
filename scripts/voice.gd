# Telefonla sesli konuşma: mikrofonu yakalar, 16 kHz'e indirir, mu-law ile sıkıştırıp
# 40 ms'lik parçalar halinde yollar; gelen parçaları açıp hoparlörden çalar.
extends Node

signal packet_ready(data: PackedByteArray)

const RATE := 16000
const CHUNK := 640  # 40 ms
const GATE_OPEN := 0.009  # konuşma bu seviyede başlar
const GATE_CLOSE := 0.004  # bu seviyenin altına inip yarım saniye sessiz kalınca kapı kapanır
const HANGOVER := 12  # parça (480 ms): cümle aralarında ve kısık hecelerde ses kesilmesin
const PRIME := 4  # gelen seste en az 4 parça (160 ms) birikmeden çalmaya başlama

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
var _queues := {}  # konuşan kimliği -> ses parçaları
var gains := {}  # konuşan kimliği -> ses seviyesi
var _space := {}  # konuşan kimliği -> mekânsal ses durumu (kazanç, pan, boğukluk, süzgeç durumları)
var _talk := {}  # konuşan kimliği -> son ses enerjisi
var _primed := false
var _kapasite := 0  # hoparlör halka tamponunun gerçek boyu (kare; motor 2'nin kuvvetine yuvarlar)
const MAX_TAMPON := RATE / 4  # 250 ms: hoparlörde bundan fazla ses birikmesin (gecikme büyümesin)
var _open_left := 0  # ses kapısı açık kalma sayacı (parça)
var _prev_chunk := PackedFloat32Array()  # konuşma başlamadan önceki parça (hece başı kesilmesin)
var muted := false  # Rus Ruleti: ölüler konuşamaz (mikrofon hiçbir şey göndermez)
var kapali := false  # oyuncu mikrofonunu kapattı (hud.gd mik_kapat): ne yakındakilere ne telefona ses gider
var robot := false  # Kim Kim?: gelen herkesin sesi robot sesine döner (kim olduğu anlaşılmasın)
var phone_line := false  # telefon görüşmesi: gelen ses dar bantlı "hat" sesi gibi (300-3400 Hz)
var _tel_hp_x := 0.0
var _tel_hp_y := 0.0
var _tel_lp1 := 0.0
var _tel_lp2 := 0.0
var _rb_phase := 0.0
var _rb_delay := PackedFloat32Array()
var _rb_i := 0
var _hat: AudioStreamPlayer  # görüşme sırasında hat hışırtısı (assets/ses/telefon/hat.ogg, -30 LUFS)
const HAT_DB := -15.0  # çok kısık: konuşmanın ~25 dB altında


func _ready() -> void:
	# "Mikrofon" bus'ı yalnızca yoksa kurulur: sahne yeniden yüklenince (menüye dönüş, Tekrar Oyna) var olan bus
	# ve üstündeki yakalama efekti yeniden kullanılır (bus sayısı artmasın, hud.gd mik_kapat doğru bus'ı bulsun).
	var bus := AudioServer.get_bus_index("Mikrofon")
	if bus < 0:
		bus = AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, "Mikrofon")
	AudioServer.set_bus_mute(bus, true)  # kendi sesini duyma
	_capture = null
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(bus, i)
			AudioServer.set_bus_effect_enabled(bus, i, true)  # yeni sahnede mikrofon açık başlar
			break
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(bus, _capture)
	_capture.clear_buffer()
	# telefon görüşmesinde hattın çok kısık hışırtısı (karşı taraf konuşmasa da hat "canlı" duyulsun)
	_hat = AudioStreamPlayer.new()
	var hs: AudioStreamOggVorbis = load("res://assets/ses/telefon/hat.ogg")
	hs.loop = true
	_hat.stream = hs
	_hat.volume_db = HAT_DB
	_hat.bus = &"Ses"
	add_child(_hat)
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
	_out_player.bus = &"Ses"  # sesli sohbet kendi bus'ında: efekt sesi kısılınca konuşma kısılmasın
	add_child(_out_player)
	for a in OS.get_cmdline_user_args():
		if a == "tone=1":
			test_tone = true


func start() -> void:
	if active:
		return
	active = true
	_pending.clear()
	_queues.clear()
	_primed = false
	_open_left = 0
	_prev_chunk = PackedFloat32Array()
	_capture.clear_buffer()
	if not test_tone:
		_mic_player.play()
	_out_player.play()
	_out = _out_player.get_stream_playback()
	_kapasite = _out.get_frames_available() if _out else 0  # boşken boş yer = gerçek kapasite


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
	_hat_isle()
	for id in _talk:
		_talk[id] = float(_talk[id]) * exp(-delta * 5.0)
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
	if muted or kapali or (ptt_enabled and not ptt_down):
		_open_left = 0
		_prev_chunk = chunk
		return
	# yumuşak ses kapısı: yüksek eşikle açılır, düşük eşik + bekleme süresiyle kapanır
	var was_open := _open_left > 0
	if rms >= GATE_OPEN or (was_open and rms >= GATE_CLOSE):
		_open_left = HANGOVER
	elif _open_left > 0:
		_open_left -= 1
	if _open_left <= 0:
		_prev_chunk = chunk
		return
	# karşı taraf konuşurken hoparlörden mikrofona kaçan yankıyı hafifçe kıs (sesi tamamen kesme)
	var gain := 0.6 if _remote_level_t > 0.0 else 1.0
	if not was_open and _prev_chunk.size() == chunk.size():
		_emit_chunk(_prev_chunk, gain)  # konuşma başlamadan önceki an da gitsin
	_emit_chunk(chunk, gain)
	_prev_chunk = chunk


func _emit_chunk(chunk: PackedFloat32Array, gain: float) -> void:
	var data := PackedByteArray()
	data.resize(chunk.size())
	for i in chunk.size():
		data[i] = _enc(chunk[i] * gain * 1.6)
	sent_packets += 1
	packet_ready.emit(data)


# Gelen ses: ilk bayt konuşanın kimliği, gerisi mu-law ses. Her konuşanın ayrı kuyruğu var;
# çalınırken mesafeye göre (gains) karıştırılır.
func receive(data: PackedByteArray) -> void:
	if not active or data.size() < 2:
		return
	received_packets += 1
	var id := int(data[0])
	var pcm := PackedFloat32Array()
	pcm.resize(data.size() - 1)
	for i in pcm.size():
		pcm[i] = _dec(data[i + 1])
	if not _queues.has(id):
		_queues[id] = []
	_queues[id].append(pcm)
	if _queues[id].size() > 15:
		_queues[id] = _queues[id].slice(_queues[id].size() - PRIME)  # çok geride kaldıysa yetiş
	_remote_level_t = 0.25


# Bir konuşanın ses seviyesi (0 = duyulmaz, 1 = tam). Eski arayüz: ortada, süzgeçsiz.
# Ayrılan konuşanın kuyruk, kazanç ve süzgeç durumları silinir.
func forget(id: int) -> void:
	_queues.erase(id)
	gains.erase(id)
	_space.erase(id)
	_talk.erase(id)


func set_gain(id: int, g: float) -> void:
	set_spatial(id, g, 0.0, 0.0)


# Mekânsal ses: kazanç (0-1), pan (-1 sol .. 1 sağ), boğukluk (0 açık .. 1 duvar arkası gibi),
# phone: bu kişi telefondan konuşuyor (ortada, tam ses, hat süzgeçli).
func set_spatial(id: int, gain: float, pan: float, muffle: float, phone := false) -> void:
	var s: Dictionary = _space.get(id, {})
	if s.is_empty():
		s = {"g": gain, "p": pan, "g0": gain, "p0": pan, "lp": 0.0, "tel": [0.0, 0.0, 0.0, 0.0]}
		_space[id] = s
	s.g = gain
	s.p = clampf(pan, -1.0, 1.0)
	s.m = clampf(muffle, 0.0, 1.0)
	s.phone = phone
	gains[id] = gain


# Konuşanın son anlardaki ses enerjisi (0-1): "konuşuyor" göstergesi için.
func talk_level(id: int) -> float:
	return float(_talk.get(id, 0.0))


# Duyulan en yüksek konuşma enerjisi (0-1; uzaklık kazancıyla): biri konuşurken müzik ve ortam kısılır (muzik.gd).
func talk_max() -> float:
	var m := 0.0
	for id in _talk:
		m = maxf(m, float(_talk[id]) * minf(1.0, float(gains.get(id, 1.0))))
	return m


func _feed_output() -> void:
	if _out == null:
		return
	# ağdaki gecikme dalgalanmasına karşı birkaç parça birikmeden çalmaya başlama
	if not _primed:
		var most := 0
		for q in _queues.values():
			most = maxi(most, q.size())
		if most < PRIME:
			return
		_primed = true
	while _out.get_frames_available() >= CHUNK and _kapasite - _out.get_frames_available() < MAX_TAMPON:
		var mix_l := PackedFloat32Array()
		var mix_r := PackedFloat32Array()
		mix_l.resize(CHUNK)
		mix_r.resize(CHUNK)
		var any := false
		for id in _queues:
			var q: Array = _queues[id]
			if q.is_empty():
				continue
			var pcm: PackedFloat32Array = q.pop_front()
			any = true
			_mix_speaker(int(id), pcm, mix_l, mix_r)
		if not any:
			break
		var buf := PackedVector2Array()
		buf.resize(CHUNK)
		for i in CHUNK:
			var l := mix_l[i]
			var r := mix_r[i]
			if robot:
				# Kim Kim?: herkes tek kanal robot sesi (kim olduğu anlaşılmasın)
				var m := _robotize((l + r) * 0.5)
				if phone_line:
					m = _telephone(m)
				l = m
				r = m
			buf[i] = Vector2(clampf(l, -1.0, 1.0), clampf(r, -1.0, 1.0))
		_out.push_buffer(buf)
	# sıra boşaldı ve hoparlöre gidecek ses de bitmek üzere: kesik kesik çalmak yerine yeniden biriktir
	var empty := true
	for q in _queues.values():
		if not q.is_empty():
			empty = false
	var buffered := _kapasite - _out.get_frames_available()
	if empty and buffered < CHUNK:
		_primed = false


# Tek konuşanın parçası: kazanç/pan parça boyunca yumuşakça geçer, uzaklık boğukluğu, telefondaysa hat süzgeci.
func _mix_speaker(id: int, pcm: PackedFloat32Array, mix_l: PackedFloat32Array, mix_r: PackedFloat32Array) -> void:
	var s: Dictionary = _space.get(id, {})
	var known := not s.is_empty()
	# bilinmeyen konuşan (ör. Kim Kim?'deki takma kimlik): telefondaysak hattan gelir, değilse ortada tam ses
	var phone: bool = bool(s.get("phone", false)) if known else phone_line
	var g1: float = 1.0 if phone else float(s.get("g", 1.0))
	var p1: float = 0.0 if phone else float(s.get("p", 0.0))
	var g0: float = float(s.get("g0", g1))
	var p0: float = float(s.get("p0", p1))
	var muffle: float = 0.0 if phone else float(s.get("m", 0.0))
	if not known:
		s = {"lp": 0.0, "tel": [0.0, 0.0, 0.0, 0.0]}
		_space[id] = s
	s.g0 = g1
	s.p0 = p1
	var energy := 0.0
	for v in pcm:
		energy += v * v
	_talk[id] = maxf(float(_talk.get(id, 0.0)) * 0.5, clampf(sqrt(energy / maxf(1.0, pcm.size())) * 8.0, 0.0, 1.0))
	if g0 <= 0.005 and g1 <= 0.005:
		return
	# boğukluk: tek kutuplu alçak geçiren, 7 kHz (açık) .. 600 Hz (duvar arkası)
	var cut := lerpf(7000.0, 600.0, muffle)
	var a := 1.0 - exp(-TAU * cut / RATE)
	var lp: float = s.lp
	var tel: Array = s.tel
	var n := mini(CHUNK, pcm.size())
	# eşit güçte pan: açılar parçanın başı ve sonu için bir kez, arası doğrusal geçiş
	var ang0 := (p0 + 1.0) * PI * 0.25
	var ang1 := (p1 + 1.0) * PI * 0.25
	var l0 := g0 * cos(ang0) * 1.41
	var r0 := g0 * sin(ang0) * 1.41
	var l1 := g1 * cos(ang1) * 1.41
	var r1 := g1 * sin(ang1) * 1.41
	var tel_on := phone and not robot
	for i in n:
		var k := float(i) / n
		var x := pcm[i]
		if tel_on:
			x = _telephone_st(x, tel)
		lp += (x - lp) * a
		mix_l[i] += lp * lerpf(l0, l1, k)
		mix_r[i] += lp * lerpf(r0, r1, k)
	s.lp = lp
	s.tel = tel


# Robot sesi: halka modülasyonu (metalik vınlama) + kısa yankı tarağı + hafif dijital kırpma.
func _robotize(x: float) -> float:
	if _rb_delay.is_empty():
		_rb_delay.resize(88)  # 5.5 ms
	_rb_phase = fmod(_rb_phase + TAU * 64.0 / RATE, TAU)
	var y := x * (0.3 + 0.7 * sin(_rb_phase))
	var o := y + _rb_delay[_rb_i] * 0.5
	_rb_delay[_rb_i] = o
	_rb_i = (_rb_i + 1) % _rb_delay.size()
	return snappedf(o * 0.9, 1.0 / 64.0)


func set_volume(v: float) -> void:
	_out_player.volume_db = linear_to_db(maxf(v, 0.001)) + 4.0


# Telefon hattı: 300 Hz altı ve 3400 Hz üstü kesilir (bant geçiren), hafif doyma ve çok hafif hat hışırtısı.
func _telephone(x: float) -> float:
	var a_hp := 1.0 / (1.0 + TAU * 300.0 / RATE)
	var hp := a_hp * (_tel_hp_y + x - _tel_hp_x)
	_tel_hp_x = x
	_tel_hp_y = hp
	var a_lp := 1.0 - exp(-TAU * 3400.0 / RATE)
	_tel_lp1 += (hp - _tel_lp1) * a_lp
	_tel_lp2 += (_tel_lp1 - _tel_lp2) * a_lp
	var y := _tel_lp2 * 1.5
	y = y / (1.0 + absf(y) * 0.35)  # karbon mikrofon gibi yumuşak doyma
	return y + (randf() - 0.5) * 0.004


# Konuşana özel hat süzgeci (durum dizide: hp_x, hp_y, lp1, lp2), _telephone ile aynı eğri.
func _telephone_st(x: float, st: Array) -> float:
	var a_hp := 1.0 / (1.0 + TAU * 300.0 / RATE)
	var hp: float = a_hp * (float(st[1]) + x - float(st[0]))
	st[0] = x
	st[1] = hp
	var a_lp := 1.0 - exp(-TAU * 3400.0 / RATE)
	st[2] = float(st[2]) + (hp - float(st[2])) * a_lp
	st[3] = float(st[3]) + (float(st[2]) - float(st[3])) * a_lp
	var y: float = float(st[3]) * 1.5
	return y / (1.0 + absf(y) * 0.35) + (randf() - 0.5) * 0.004


# Hat hışırtısı yalnızca telefon görüşmesi sürerken; konuşma sesi ayarıyla birlikte kısılır.
func _hat_isle() -> void:
	if _hat == null:
		return
	var on := active and phone_line
	if on and not _hat.playing:
		_hat.volume_db = HAT_DB + _out_player.volume_db - 4.0
		_hat.play()
	elif not on and _hat.playing:
		_hat.stop()
