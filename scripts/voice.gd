# Telefonla sesli konuşma: mikrofonu yakalar, 16 kHz'e indirir, mu-law ile sıkıştırıp
# 40 ms'lik parçalar halinde yollar; gelen parçaları açıp hoparlörden çalar.
# Örnek başına işler (kodlama, açma, karıştırma) tablo ve yerel değişkenle yapılır: telefon ısınmasın.
extends Node

signal packet_ready(data: PackedByteArray)
signal mik_sorun(tur: String)  # "izin": mikrofon izni yok, "sessiz": mikrofondan hiç veri gelmiyor

const RATE := 16000
const CHUNK := 640  # 40 ms
const GATE_OPEN := 0.0035  # en düşük açılma eşiği (sessiz mikrofonlu telefonlarda da ses gitsin)
const GATE_CLOSE := 0.002  # en düşük kapanma eşiği; eşikler ortam gürültüsüyle birlikte yükselir (_gurultu)
const HANGOVER := 12  # parça (480 ms): cümle aralarında ve kısık hecelerde ses kesilmesin
const PRIME := 4  # gelen seste en az 4 parça (160 ms) birikmeden çalmaya başlama
const PRIME_MAX := 8  # bağlantı dalgalıysa konuşan başına birikme 320 ms'ye kadar çıkar
const BOSLUK_KAPAT := 2  # paket gecikince en çok 2 parça (80 ms) son ses kısılarak tekrarlanır (tık sesi yerine)
const HEDEF_SES := 0.07  # kendiliğinden kazanç: giden konuşmanın hedef seviyesi (tepeler kırpılmasın)
const KAZANC_MAX := 3.0  # fazlası susarken ortam gürültüsünü de büyütüp hışırtı yapıyordu
const DIZ := 0.6  # yumuşak sınırlayıcı: bu seviyenin üstü sıkıştırılır, ses asla 1'e çarpıp çatlamaz
const YANKI_ORAN := 0.2  # hoparlörden mikrofona kaçan ses: karşı taraf konuşurken kapı bu oranda yükselir
const SESSIZ_SURE := 1.5  # mikrofondan bu kadar süre hiç veri gelmezse yeniden başlatılır

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
var _queues := {}  # konuşan kimliği -> ses parçaları
var _son_ornek := 0.0  # önceki karenin son mikrofon örneği (kareler arasında dalga kırılmasın)
var _gurultu := 0.002  # öğrenilen ortam gürültüsü
var tepe := 0.0  # görüşme ölçümü: mikrofonun en yüksek seviyesi (main.gd _arama_olc)
var _kazanc := 1.6  # mikrofon kazancı (kısık telefonlarda yükselir)
var _cikis_rms := 0.0  # hoparlöre giden sesin son seviyesi
var _sifir_t := 0.0  # mikrofondan veri gelmeyen süre
var _yeniden_sayi := 0
var _izin_bekliyor := false
var _sorun_bildirildi := false
var _yanki_acik := false
var _yanki_son_ms := 0
var _yanki_bus := -1
var _out_yanki: AudioStreamPlayer  # uzaktaki sesin yankısı: ayrı bus'ta gerçek (motorun) yankı efekti
var _yanki: AudioStreamGeneratorPlayback
var _mix_l := PackedFloat32Array()
var _mix_r := PackedFloat32Array()
var _mix_w := PackedFloat32Array()
var _buf := PackedVector2Array()
var _buf_w := PackedVector2Array()
var _sifir_buf := PackedVector2Array()
static var _KOD := PackedByteArray()  # |x| (14 bit) -> mu-law
static var _AC := PackedFloat32Array()  # mu-law -> örnek
var gains := {}  # konuşan kimliği -> ses seviyesi
var _space := {}  # konuşan kimliği -> mekânsal ses durumu (kazanç, pan, boğukluk, süzgeç durumları)
var _talk := {}  # konuşan kimliği -> son ses enerjisi
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
const HAT_DB := -34.0  # neredeyse duyulmaz: konuşmayı kirletmesin (eskisi -15 cızırtı gibi duyuluyordu)


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
	var suzgecli := false
	for i in AudioServer.get_bus_effect_count(bus):
		var fx := AudioServer.get_bus_effect(bus, i)
		if fx is AudioEffectLowPassFilter:
			suzgecli = true
		if fx is AudioEffectCapture:
			_capture = fx
			AudioServer.set_bus_effect_enabled(bus, i, true)  # yeni sahnede mikrofon açık başlar
	if not suzgecli:
		# 16 kHz'e inmeden önce 7 kHz üstü kesilir: yoksa tiz sesler aşağı katlanır, ses metalik/robot gibi çıkar.
		# Uğultu da gitsin. İkisi de motorun içinde çalışır, GDScript yükü yok; yakalamadan ÖNCE gelmeli.
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 7000.0
		lp.db = AudioEffectFilter.FILTER_24DB
		AudioServer.add_bus_effect(bus, lp, 0)
		var hp := AudioEffectHighPassFilter.new()
		hp.cutoff_hz = 90.0
		AudioServer.add_bus_effect(bus, hp, 1)
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(bus, _capture)
	_capture.clear_buffer()
	_tablolar()
	if OS.has_feature("android") and not get_tree().on_request_permissions_result.is_connected(_izin_sonucu):
		get_tree().on_request_permissions_result.connect(_izin_sonucu)
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
	_out_player.volume_db = 1.0
	_out_player.bus = &"Ses"  # sesli sohbet kendi bus'ında: efekt sesi kısılınca konuşma kısılmasın
	add_child(_out_player)
	_yanki_bus_kur()
	var gen_y := AudioStreamGenerator.new()
	gen_y.mix_rate = RATE
	gen_y.buffer_length = 0.6
	_out_yanki = AudioStreamPlayer.new()
	_out_yanki.stream = gen_y
	_out_yanki.bus = &"SesYanki"
	add_child(_out_yanki)
	_mix_l.resize(CHUNK)
	_mix_r.resize(CHUNK)
	_mix_w.resize(CHUNK)
	_buf.resize(CHUNK)
	_buf_w.resize(CHUNK)
	_sifir_buf.resize(CHUNK)
	for a in OS.get_cmdline_user_args():
		if a == "tone=1":
			test_tone = true


func start() -> void:
	if active:
		return
	active = true
	_pending.clear()
	_queues.clear()
	_space.clear()
	_open_left = 0
	_prev_chunk = PackedFloat32Array()
	_sifir_t = 0.0
	_capture.clear_buffer()
	if not test_tone:
		_mik_baslat()
	_out_player.play()
	_out = _out_player.get_stream_playback()
	_kapasite = _out.get_frames_available() if _out else 0  # boşken boş yer = gerçek kapasite
	_out_yanki.play()
	_yanki = _out_yanki.get_stream_playback()


func stop() -> void:
	active = false
	_mic_player.stop()
	_out_player.stop()
	_out_yanki.stop()
	_out = null
	_yanki = null


# Android'de izin yokken mikrofon sessizce çalışmaz; izin önce istenir, gelince başlatılır (_izin_sonucu).
func _mik_baslat() -> void:
	if OS.has_feature("android") and not OS.request_permission("RECORD_AUDIO"):
		_izin_bekliyor = true
		return
	_izin_bekliyor = false
	_mic_player.play()


func _izin_sonucu(izin: String, verildi: bool) -> void:
	if not izin.ends_with("RECORD_AUDIO"):
		return
	_izin_bekliyor = false
	if not verildi:
		_sorun("izin")
	elif active or testing:
		_mic_player.stop()
		_mic_player.play()


func _sorun(tur: String) -> void:
	if not _sorun_bildirildi:
		_sorun_bildirildi = true
		mik_sorun.emit(tur)


# Mikrofon sustuysa yeniden başlatır (arama, uygulama değişimi, kulaklık takılması mikrofonu öldürebilir).
func _mik_yeniden() -> void:
	_sifir_t = 0.0
	if test_tone or _izin_bekliyor or _mic_player == null:
		return
	if OS.has_feature("android") and not OS.request_permission("RECORD_AUDIO"):
		_izin_bekliyor = true
		return
	_mic_player.stop()
	_mic_player.play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and active:
		_mik_yeniden()


static func _enc(x: float) -> int:
	var s := clampf(x, -1.0, 1.0)
	var m := log(1.0 + 255.0 * absf(s)) / log(256.0)
	return (0x80 if s < 0.0 else 0) | int(round(m * 127.0))


static func _dec(b: int) -> float:
	var v := (pow(256.0, float(b & 0x7f) / 127.0) - 1.0) / 255.0
	return -v if (b & 0x80) != 0 else v


# Kodlama ve açma tabloları (telefonda örnek başına log/pow hesabı yapılmasın; biçim aynı, eski sürümlerle uyumlu).
static func _tablolar() -> void:
	if not _AC.is_empty():
		return
	_KOD.resize(16384)
	for i in 16384:
		_KOD[i] = _enc(float(i) / 16383.0)
	_AC.resize(256)
	for i in 256:
		_AC[i] = _dec(i)


# Yankılı uzak ses için ayrı bus (taş koridor). Sahne yenilense de bir kez kurulur.
func _yanki_bus_kur() -> void:
	_yanki_bus = AudioServer.get_bus_index("SesYanki")
	if _yanki_bus < 0:
		_yanki_bus = AudioServer.bus_count
		AudioServer.add_bus(_yanki_bus)
		AudioServer.set_bus_name(_yanki_bus, "SesYanki")
		AudioServer.set_bus_send(_yanki_bus, &"Ses")
		var r := AudioEffectReverb.new()
		r.dry = 0.0
		r.wet = 1.0
		r.room_size = 0.78
		r.damping = 0.32
		r.spread = 0.7
		r.hipass = 0.18
		r.predelay_msec = 70.0
		r.predelay_feedback = 0.3
		AudioServer.add_bus_effect(_yanki_bus, r)
	_yanki_acik = false
	AudioServer.set_bus_effect_enabled(_yanki_bus, 0, false)  # yankı gerekmedikçe kapalı (işlemci harcamasın)


func start_test() -> void:
	testing = true
	_capture.clear_buffer()
	_mik_baslat()


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
	_cikis_rms *= exp(-delta * 4.0)
	if _yanki_acik and Time.get_ticks_msec() - _yanki_son_ms > 4000:
		_yanki_acik = false
		AudioServer.set_bus_effect_enabled(_yanki_bus, 0, false)
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
		_sessiz_mi(delta)
		return
	_pending.append_array(ornek_indir(_capture.get_buffer(frames), AudioServer.get_mix_rate() / RATE))


# Mikrofon akışını 16 kHz'e indirir. Konum kareler arasında korunur; -1..0 aralığı önceki karenin son örneği
# ile bu karenin ilk örneğinin arasıdır. (Eskiden o aralıkta doğru dışına taşıyordu: her karede küçük kırılma,
# yani kare hızında vızıltı ve robot sesi.)
func ornek_indir(buf: PackedVector2Array, step: float) -> PackedFloat32Array:
	var n := buf.size()
	var cikis := PackedFloat32Array()
	if n == 0:
		return cikis
	cikis.resize(int(float(n + 2) / step) + 2)
	var k := 0
	var pos := _resample_pos
	var onceki := _son_ornek
	while pos < n - 1:
		var i := floori(pos)
		var f := pos - i
		var b: Vector2 = buf[i + 1]
		if i < 0:
			cikis[k] = onceki + ((b.x + b.y) * 0.5 - onceki) * f
		else:
			var a: Vector2 = buf[i]
			var va := (a.x + a.y) * 0.5
			cikis[k] = va + ((b.x + b.y) * 0.5 - va) * f
		k += 1
		pos += step
	var son: Vector2 = buf[n - 1]
	_son_ornek = (son.x + son.y) * 0.5
	_resample_pos = pos - n
	cikis.resize(k)
	return cikis


# Mikrofondan uzun süre veri (ya da hiç sıfır dışı örnek) gelmediyse yeniden başlatır; düzelmezse bildirir.
func _sessiz_mi(sure: float) -> void:
	if kapali or test_tone or _izin_bekliyor:
		_sifir_t = 0.0
		return
	_sifir_t += sure
	if _sifir_t < SESSIZ_SURE or _yeniden_sayi >= 6:
		return
	_yeniden_sayi += 1
	_mik_yeniden()
	if _yeniden_sayi == 3:
		_sorun("sessiz")


func _send_chunk(chunk: PackedFloat32Array) -> void:
	var rms := 0.0
	for v in chunk:
		rms += v * v
	rms = sqrt(rms / chunk.size())
	level = clampf(rms * 6.0, 0.0, 1.0)
	tepe = maxf(tepe, rms)
	if rms > 0.0:
		_sifir_t = 0.0
		_yeniden_sayi = 0
	else:
		_sessiz_mi(float(chunk.size()) / RATE)
	if muted or kapali or (ptt_enabled and not ptt_down):
		_open_left = 0
		_prev_chunk = chunk
		return
	var was_open := _open_left > 0
	# ortam gürültüsü yalnız kapı kapalıyken öğrenilir; eşikler onunla yükselir (fan, sokak sesi kapıyı açık tutmasın)
	if not was_open:
		_gurultu = lerpf(_gurultu, minf(rms, 0.03), 0.25 if rms < _gurultu else 0.02)
	var esik := maxf(GATE_OPEN, _gurultu * 3.0)
	var esik_kapa := maxf(GATE_CLOSE, _gurultu * 1.6)
	# karşı taraf konuşurken hoparlörden mikrofona kaçan ses geri gitmesin (kendi sesini robot gibi duyar);
	# bas-konuş basılıyken kişi bilerek konuşuyor, kapı yükselmez
	if _cikis_rms > 0.002 and not ptt_enabled:
		var yanki := _cikis_rms * YANKI_ORAN
		esik = maxf(esik, yanki)
		esik_kapa = maxf(esik_kapa, yanki)
	# yumuşak ses kapısı: yüksek eşikle açılır, düşük eşik + bekleme süresiyle kapanır
	if rms >= esik or (was_open and rms >= esik_kapa):
		_open_left = HANGOVER
	elif _open_left > 0:
		_open_left -= 1
	if _open_left <= 0:
		_prev_chunk = chunk
		return
	# kendiliğinden kazanç: kısık mikrofon yükselir, gürültü yükselmesin diye yalnız konuşma parçalarında değişir
	var k0 := _kazanc
	if rms >= esik:
		var iste := clampf(HEDEF_SES / maxf(rms, 0.001), 1.0, KAZANC_MAX)
		_kazanc = lerpf(_kazanc, iste, 0.5 if iste < _kazanc else 0.06)
	if not was_open and _prev_chunk.size() == chunk.size():
		_emit_chunk(_prev_chunk, k0, k0)  # konuşma başlamadan önceki an da gitsin
	_emit_chunk(chunk, k0, _kazanc)
	_prev_chunk = chunk


func _emit_chunk(chunk: PackedFloat32Array, k0: float, k1: float) -> void:
	var n := chunk.size()
	var data := PackedByteArray()
	data.resize(n)
	var tablo := _KOD
	var g := k0
	var dg := (k1 - k0) / n
	for i in n:
		var x := chunk[i] * g
		g += dg
		if x > DIZ or x < -DIZ:
			x = _sinirla(x)
		if x < 0.0:
			data[i] = 0x80 | tablo[mini(int(-x * 16383.0), 16383)]
		else:
			data[i] = tablo[mini(int(x * 16383.0), 16383)]
	sent_packets += 1
	packet_ready.emit(data)


# Gelen ses: ilk bayt konuşanın kimliği, gerisi mu-law ses. Her konuşanın ayrı kuyruğu var;
# çalınırken mesafeye göre (gains) karıştırılır.
func receive(data: PackedByteArray) -> void:
	if not active or data.size() < 2:
		return
	received_packets += 1
	var id := int(data[0])
	var n := data.size() - 1
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	var tablo := _AC
	for i in n:
		pcm[i] = tablo[data[i + 1]]
	if not _queues.has(id):
		_queues[id] = []
	var q: Array = _queues[id]
	q.append(pcm)
	var s := _konusan(id)
	# boşluktan hemen sonra paket geldiyse konuşma bitmemiş, bağlantı dalgalanmış: bu kişi için tamponu büyüt;
	# uzun süre sorun yoksa yavaşça geri iner
	if int(s.alt_ms) > 0:
		var ara := Time.get_ticks_msec() - int(s.alt_ms)
		if ara < 500:
			s.hedef = mini(int(s.hedef) + 1, PRIME_MAX)
		elif ara > 10000:
			s.hedef = maxi(int(s.hedef) - 1, PRIME)
		s.alt_ms = 0
	if q.size() > 15:
		_queues[id] = q.slice(q.size() - int(s.hedef))  # çok geride kaldıysa yetiş


func _konusan(id: int) -> Dictionary:
	var s: Dictionary = _space.get(id, {})
	if s.is_empty():
		s = {"g": 0.0, "p": 0.0, "g0": 0.0, "p0": 0.0, "m": 0.0, "w": 0.0, "w0": 0.0, "lp": 0.0, "tel": [0.0, 0.0, 0.0, 0.0],
			"phone": phone_line, "bilinen": false, "hazir": false, "hedef": PRIME, "bosluk": 0, "son": PackedFloat32Array(), "alt_ms": 0}
		_space[id] = s
	return s


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
# phone: bu kişi telefondan konuşuyor (ortada, tam ses, hat süzgeçli); yanki: yankı bus'ına giden pay (0 = yok).
func set_spatial(id: int, gain: float, pan: float, muffle: float, phone := false, yanki := 0.0) -> void:
	var s := _konusan(id)
	if not bool(s.bilinen):
		s.g0 = gain
		s.p0 = pan
		s.w0 = yanki
		s.bilinen = true
	s.g = gain
	s.p = clampf(pan, -1.0, 1.0)
	s.m = clampf(muffle, 0.0, 1.0)
	s.phone = phone
	s.w = yanki
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
	while true:
		var bos := _out.get_frames_available()
		var dolu := _kapasite - bos
		if bos < CHUNK or dolu >= MAX_TAMPON:
			break
		# konuşan başına tampon: yeni konuşan birikmeden çalmaz, ötekileri bekletmez
		var veri := false
		for id in _queues:
			var q: Array = _queues[id]
			var s := _konusan(int(id))
			if not bool(s.hazir) and q.size() >= int(s.hedef):
				s.hazir = true
				s.bosluk = 0
				s.g0 = 0.0  # girişte tık olmasın
				s.w0 = 0.0
			if bool(s.hazir) and not q.is_empty():
				veri = true
		if not veri and dolu >= CHUNK:
			break  # hoparlörde hâlâ ses var: paketi bekle
		var any := false
		_mix_l.fill(0.0)
		_mix_r.fill(0.0)
		_mix_w.fill(0.0)
		for id in _queues:
			var s := _konusan(int(id))
			if not bool(s.hazir):
				continue
			var q: Array = _queues[id]
			if q.is_empty():
				# paket gecikti: boşluk yerine son parça kısılarak söner; uzun sürerse konuşma bitmiştir
				if int(s.bosluk) < BOSLUK_KAPAT and not (s.son as PackedFloat32Array).is_empty():
					s.bosluk = int(s.bosluk) + 1
					_mix_speaker(int(id), s.son, true)
					any = true
				else:
					s.hazir = false
					s.son = PackedFloat32Array()
					s.alt_ms = Time.get_ticks_msec()
				continue
			var pcm: PackedFloat32Array = q.pop_front()
			s.bosluk = 0
			s.son = pcm
			_mix_speaker(int(id), pcm, false)
			any = true
		if not any:
			break
		_sesi_yolla()


# Karışımı hoparlöre (ve yankı bus'ına) yollar. İki üreteç aynı anda beslenir: yankı doğrudan sesin önüne geçmesin.
func _sesi_yolla() -> void:
	var ml := _mix_l
	var mr := _mix_r
	var buf := _buf
	var enerji := 0.0
	if robot:
		for i in CHUNK:
			# Kim Kim?: herkes tek kanal robot sesi (kim olduğu anlaşılmasın)
			var m := _robotize((ml[i] + mr[i]) * 0.5)
			if phone_line:
				m = _telephone(m)
			if m > DIZ or m < -DIZ:
				m = _sinirla(m)
			buf[i] = Vector2(m, m)
			enerji += m * m
	else:
		for i in CHUNK:
			var l := ml[i]
			var r := mr[i]
			if l > DIZ or l < -DIZ:
				l = _sinirla(l)
			if r > DIZ or r < -DIZ:
				r = _sinirla(r)
			buf[i] = Vector2(l, r)
			enerji += l * l + r * r
	_cikis_rms = sqrt(enerji / (CHUNK * (1.0 if robot else 2.0)))
	_out.push_buffer(buf)
	if _yanki == null:
		return
	var yanki_var := false
	if not robot:
		var mw := _mix_w
		var bw := _buf_w
		for i in CHUNK:
			var w := mw[i]
			bw[i] = Vector2(w, w)
			if w != 0.0:
				yanki_var = true
		if yanki_var:
			_yanki.push_buffer(bw)
	if not yanki_var:
		_yanki.push_buffer(_sifir_buf)
	else:
		_yanki_son_ms = Time.get_ticks_msec()
		if not _yanki_acik:
			_yanki_acik = true
			AudioServer.set_bus_effect_enabled(_yanki_bus, 0, true)


# Tek konuşanın parçası: kazanç/pan parça boyunca yumuşakça geçer, uzaklık boğukluğu, telefondaysa hat süzgeci.
# son: paket gecikti, bu parça önceki sesin sönen tekrarı.
func _mix_speaker(id: int, pcm: PackedFloat32Array, son: bool) -> void:
	var s := _konusan(id)
	# bilinmeyen konuşan (ör. Kim Kim?'deki takma kimlik): telefondaysak hattan gelir, değilse ortada tam ses
	var phone: bool = bool(s.phone) if bool(s.bilinen) else phone_line
	var g1: float = 1.0 if phone or not bool(s.bilinen) else float(s.g)
	var p1: float = 0.0 if phone else float(s.p)
	var w1: float = 0.0 if phone else float(s.w)
	var g0: float = float(s.g0)
	var p0: float = float(s.p0)
	var w0: float = float(s.w0)
	var muffle: float = 0.0 if phone else float(s.m)
	if son:
		g1 = 0.0
		w1 = 0.0
	s.g0 = g1
	s.p0 = p1
	s.w0 = w1
	var n := mini(CHUNK, pcm.size())
	if not son:
		var energy := 0.0
		var j := 0
		while j < n:
			var e := pcm[j]
			energy += e * e
			j += 4
		_talk[id] = maxf(float(_talk.get(id, 0.0)) * 0.5, clampf(sqrt(energy / maxf(1.0, n / 4.0)) * 8.0, 0.0, 1.0))
	if g0 <= 0.005 and g1 <= 0.005 and w0 <= 0.005 and w1 <= 0.005:
		return
	# boğukluk: tek kutuplu alçak geçiren, 7 kHz (açık) .. 600 Hz (duvar arkası)
	var a := 1.0 - exp(-TAU * lerpf(7000.0, 600.0, muffle) / RATE)
	var lp: float = s.lp
	# eşit güçte pan: açılar parçanın başı ve sonu için bir kez, arası doğrusal geçiş
	var ang0 := (p0 + 1.0) * PI * 0.25
	var ang1 := (p1 + 1.0) * PI * 0.25
	var l := g0 * cos(ang0) * 1.41
	var r := g0 * sin(ang0) * 1.41
	var dl := (g1 * cos(ang1) * 1.41 - l) / n
	var dr := (g1 * sin(ang1) * 1.41 - r) / n
	var w := w0
	var dw := (w1 - w0) / n
	var ml := _mix_l
	var mr := _mix_r
	var mw := _mix_w
	if phone and not robot:
		var tel: Array = s.tel
		for i in n:
			lp += (_telephone_st(pcm[i], tel) - lp) * a
			ml[i] += lp * l
			mr[i] += lp * r
			l += dl
			r += dr
	elif w0 <= 0.0 and w1 <= 0.0:
		for i in n:
			lp += (pcm[i] - lp) * a
			ml[i] += lp * l
			mr[i] += lp * r
			l += dl
			r += dr
	else:
		for i in n:
			lp += (pcm[i] - lp) * a
			ml[i] += lp * l
			mr[i] += lp * r
			mw[i] += lp * w
			l += dl
			r += dr
			w += dw
	s.lp = lp


# Yumuşak sınırlayıcı: DIZ üstü tanh ile sıkıştırılır (en çok 1.0). Sert kırpma cızırtı/çatlama yapıyordu.
static func _sinirla(x: float) -> float:
	var a := absf(x)
	var y := DIZ + (1.0 - DIZ) * tanh((a - DIZ) / (1.0 - DIZ))
	return y if x > 0.0 else -y


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
	_out_player.volume_db = linear_to_db(maxf(v, 0.001)) + 1.0


# Telefon hattı: 250 Hz altı ve 4200 Hz üstü kesilir (bant geçiren). Hışırtı ve doyma yok: ses net kalsın.
func _telephone(x: float) -> float:
	var a_hp := 1.0 / (1.0 + TAU * 250.0 / RATE)
	var hp := a_hp * (_tel_hp_y + x - _tel_hp_x)
	_tel_hp_x = x
	_tel_hp_y = hp
	var a_lp := 1.0 - exp(-TAU * 4200.0 / RATE)
	_tel_lp1 += (hp - _tel_lp1) * a_lp
	_tel_lp2 += (_tel_lp1 - _tel_lp2) * a_lp
	return _tel_lp2 * 1.15


# Konuşana özel hat süzgeci (durum dizide: hp_x, hp_y, lp1, lp2), _telephone ile aynı eğri.
func _telephone_st(x: float, st: Array) -> float:
	var a_hp := 1.0 / (1.0 + TAU * 250.0 / RATE)
	var hp: float = a_hp * (float(st[1]) + x - float(st[0]))
	st[0] = x
	st[1] = hp
	var a_lp := 1.0 - exp(-TAU * 4200.0 / RATE)
	st[2] = float(st[2]) + (hp - float(st[2])) * a_lp
	st[3] = float(st[3]) + (float(st[2]) - float(st[3])) * a_lp
	return float(st[3]) * 1.15


# Hat hışırtısı yalnızca telefon görüşmesi sürerken; konuşma sesi ayarıyla birlikte kısılır.
func _hat_isle() -> void:
	if _hat == null:
		return
	var on := active and phone_line
	if on and not _hat.playing:
		_hat.volume_db = HAT_DB + _out_player.volume_db - 1.0
		_hat.play()
	elif not on and _hat.playing:
		_hat.stop()
