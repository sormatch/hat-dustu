# Telefonla sesli konuşma: mikrofonu yakalar, 24 kHz tek kanala indirir, Opus ile sıkıştırıp 40 ms'lik parçalar
# halinde yollar; gelen parçaları açıp hoparlörden çalar.
# Telefonda mikrofon (iPhone'da gelen konuşma da) telefonun sesli görüşme yolundan geçer (HatSes, addons/hatses):
# işletim sisteminin yankı engelleyicisi hoparlörden mikrofona kaçan sesi siler (WhatsApp / FaceTime gibi).
# Eski sürümler (OYUN_SURUMU < 5) 16 kHz mu-law konuşur: onlardan gelen açılıp 24 kHz'e çevrilir; odada eski sürüm
# varsa (eski_var) her parça ayrıca mu-law olarak da yollanır (sunucu kime hangisinin gideceğini seçer).
# Örnek başına işler (kodlama, açma, karıştırma) tablo ve yerel değişkenle yapılır: telefon ısınmasın.
extends Node

signal packet_ready(data: PackedByteArray)
signal mik_sorun(tur: String)  # "izin": mikrofon izni yok, "sessiz": mikrofondan hiç veri gelmiyor

const RATE := 24000
const CHUNK := 960  # 40 ms
const ESKI_RATE := 16000  # eski sürümlerin mu-law sesi
const ESKI_CHUNK := 640
const OPUS_BIT := 32000  # konuşma için dolgun ve net (mu-law 128 kbps'ten iyi, 4 kat az veri)
const OPUS_BAS := [0xC7, 0x02]  # Opus paketi: C7, sürüm 2, gönderenin parça sayacı (2 bayt), Opus verisi
# (mu-law paketi tam 640 bayttır, ayırt edilir). Sayaç her 40 ms'lik mikrofon parçasında bir artar (konuşmasa da):
# alan taraf her parçanın ne zaman konuşulduğunu bilir: ağ gecikmesini tam ölçer, susma ile takılmayı ayırır.
const T_MIN := 3  # zaman damgalı konuşanda en az 3 parça (120 ms) tampon
const GIZLE_MAX := 4  # zaman damgalı konuşanda geç kalan parça en çok 4 parça (160 ms) kayıp gizlemeyle köprülenir
const SUSMA_DOLDUR := 2  # 2 parçaya kadar susma sessizlikle doldurulur (konuşma bölünmez, yeniden tamponlanmaz)
const GATE_OPEN := 0.0035  # en düşük açılma eşiği (sessiz mikrofonlu telefonlarda da ses gitsin)
const GATE_CLOSE := 0.002  # en düşük kapanma eşiği; eşikler ortam gürültüsüyle birlikte yükselir (_gurultu)
const HANGOVER := 25  # parça (1 sn): konuşma bitmeden kapı kapanmasın (kısık hecede kapanınca ses sekiyordu; Opus'la sessizlik ucuz)
const PRIME := 4  # gelen seste en az 4 parça (160 ms) birikmeden çalmaya başlama
const PRIME_MAX := 12  # bağlantı dalgalıysa konuşan başına birikme 480 ms'ye kadar çıkar
const BOSLUK_KAPAT := 2  # paket gecikince en çok 2 parça (80 ms) son ses kısılarak tekrarlanır (tık sesi yerine)
const HEDEF_SES := 0.07  # kendiliğinden kazanç: giden konuşmanın hedef seviyesi (tepeler kırpılmasın)
const KAZANC_MAX := 3.0  # fazlası susarken ortam gürültüsünü de büyütüp hışırtı yapıyordu
const TAVAN := 0.88
const DIZ := 0.6  # yumuşak sınırlayıcı: bu seviyenin üstü sıkıştırılır, ses asla 1'e çarpıp çatlamaz
const YANKI_ORAN := 0.5  # hoparlörden mikrofona kaçan ses: karşı taraf konuşurken kapı bu oranda yükselir
const YANKI_KUYRUK := 0.6  # hoparlöre giden ses ~0,3 sn sonra duyulur: yankı kapısı o kadar geç söner (sn)
const SESSIZ_SURE := 1.5  # mikrofondan bu kadar süre hiç veri gelmezse yeniden başlatılır
# Öğrenilen ortam gürültüsünün tavanı (ses kapısı eşiği bunun 3 katı). Telefonda işletim sistemi hoparlör sesini
# mikrofondan siler; bilgisayarda (yankı engelleme yok) oyun müziği mikrofona girip eşiği konuşmanın geçemeyeceği
# kadar yükseltiyordu: masaüstünde tavan düşük (eşik en çok ~0,018).
var GURULTU_TAVAN := 0.03 if OS.has_feature("mobile") else 0.006

var active := false
var testing := false  # ayarlardaki mikrofon testi: sadece seviye ölçülür, hiçbir şey gönderilmez
var level := 0.0  # son mikrofon seviyesi (0-1)
var ptt_enabled := false  # bas-konuş: sadece düğmeye basılıyken ses gider
var ptt_down := false
var test_tone := false  # testte mikrofon yerine bip sesi yollar
var test_kaynak := PackedFloat32Array()  # test (kaynak=erkek|kadin|ince|genc): mikrofon yerine bu konuşma döngüde
var _test_konum := 0
var test_alinan := {}  # test: konuşan kimliği -> gelen paket sayısı (test_olay_ac iken)
var test_kesinti := {}  # test: konuşan kimliği -> gerçek sekme sayısı (tampon boşaldı, 250 ms içinde aynı kişiden ses geldi)
var _bos_ms := {}  # konuşan kimliği -> tamponun boşaldığı an
var test_gelis := {}  # test: konuşan kimliği -> paket geliş anları (ms)
var test_gidis := []  # test: paket yollama anları (ms)
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
var test_giden := false  # test: yollanan (ya da kapıda kalan) her parça test_kayit'a eklenir (tools/ses_senaryo.gd)
var test_kayit := PackedFloat32Array()
var test_olaylar := []  # test: dinleyen tarafta tampon olayları [ms, olay, kimlik, kuyruk, hoparlör]
var test_olay_ac := false
var _son_giden := PackedByteArray()
var tepe := 0.0  # görüşme ölçümü: mikrofonun en yüksek seviyesi (main.gd _arama_olc)
var _kazanc := 1.6  # mikrofon kazancı (kısık telefonlarda yükselir)
var _konusma_kazanc := 1.6  # en son gerçek konuşmada öğrenilen kazanç (zil sonrası buna dönülür)
var _gurultu_kayit := 0.002  # zil başlamadan önceki ortam gürültüsü
# Telefon çalıyor (arayanda çalma sesi, arananda zil): hoparlörden mikrofona kaçan yüksek ton kazancı ve gürültü
# eşiğini bozmasın diye öğrenme durur. (Eskiden zil kazancı en alta çekiyordu: bağlanınca konuşma 1-2 sn çok kısık
# gidiyor, kazanç yavaşça açılırken ses kapısı açılıp kapanıyordu — "ilk saniyeler gitmiyor, sonra sekiyor".)
var zil := false:
	set(v):
		if v and not zil:
			_gurultu_kayit = _gurultu
		zil = v
var _cikis_rms := 0.0  # hoparlöre giden sesin son seviyesi
var _yanki_tepe := 0.0  # yankı kapısı için çıkış seviyesi (yavaş söner: YANKI_KUYRUK)
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
const MAX_TAMPON := RATE * 16 / 100  # 160 ms: hoparlörde bundan fazla ses birikmesin (gecikme); geç kalan parçayı beklerken pay
var _open_left := 0  # ses kapısı açık kalma sayacı (parça)
var _prev_chunk := PackedFloat32Array()  # konuşma başlamadan önceki parça (hece başı kesilmesin)
var muted := false  # Rus Ruleti: ölüler konuşamaz (mikrofon hiçbir şey göndermez)
var eski_var := false  # odada eski sürüm (mu-law) oyuncu var: her parça ayrıca mu-law da yollanır (main.gd)
var _kod: RefCounted = null  # HatOpusKodlayici (yoksa yalnız mu-law)
var _cozucu := {}  # konuşan kimliği -> HatOpusCozucu
var _yerel: RefCounted = null  # HatSes: telefonun sesli görüşme yolu (yankı engelleme)
var _yerel_cikis := false  # gelen konuşma da yerel yoldan çalıyor (iOS)
var yerel_izin := true  # sunucu ayarı (account.uzak_ayar.yerel_ses): sorun çıkarsa güncellemesiz kapatılır (main.gd)
var _yanki_oran := YANKI_ORAN  # yerel yankı engelleme açıkken yankı kapısı gevşer (iki kişi aynı anda konuşabilsin)
static var YANKI_TEST := -1.0
var _son_giden_pcm := PackedFloat32Array()
var _tik := 0  # gönderilen mikrofon parçası sayacı (40 ms)
var _q2 := {}  # zaman damgalı konuşanlar: kimlik -> [[tik, pcm], ...] (sıralı)
var test_aclik_kare := []  # test: açlık anındaki kare süreleri (ms)
var test_cikis_aclik := 0  # test: hoparlör tamponu konuşma sürerken boşaldı (oyun karesi takıldı)
var _aclik := false
var _cikis_pay := 160.0  # ms: hoparlörde önceden biriken ses; oyun karesi takılıp tampon boşalırsa büyür, sonra yavaşça küçülür
var _pay_ms := 0
var _onceki_dolu := 0  # önceki karede hoparlör tamponundaki ses (açlık: sesten sıfıra düşüş)
var kapali := false  # oyuncu mikrofonunu kapattı (hud.gd mik_kapat): ne yakındakilere ne telefona ses gider
var robot := false  # Kim Kim?: gelen herkesin sesi robot sesine döner (kim olduğu anlaşılmasın)
var phone_line := false  # telefon görüşmesi: gelen ses dar bantlı "hat" sesi gibi (300-3400 Hz)
var _tel_hp_x := 0.0
var _tel_hp_y := 0.0
var _tel_lp1 := 0.0
var _tel_lp2 := 0.0
var _rb_phase := 0.0
var _rb_lp: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _rb_lfo := 0.0
var _rb_tasiyici := 0.0
var _rb_tut := 0.0
var _rb_say := 0
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
			(fx as AudioEffectLowPassFilter).cutoff_hz = 10500.0  # 24 kHz örneklemeye göre
		if fx is AudioEffectCapture:
			_capture = fx
			AudioServer.set_bus_effect_enabled(bus, i, true)  # yeni sahnede mikrofon açık başlar
	if not suzgecli:
		# 24 kHz'e inmeden önce 10,5 kHz üstü kesilir: yoksa tiz sesler aşağı katlanır, ses metalik/robot gibi çıkar.
		# Uğultu da gitsin. İkisi de motorun içinde çalışır, GDScript yükü yok; yakalamadan ÖNCE gelmeli.
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 10500.0
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
	if ClassDB.class_exists("HatOpusKodlayici") and not OS.get_cmdline_user_args().has("eski_istemci=1"):
		_kod = ClassDB.instantiate("HatOpusKodlayici")
		if not _kod.call("kur", RATE, OPUS_BIT):
			_kod = null
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
	_out_player.volume_db = 0.0
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
		elif a.begins_with("kaynak="):
			test_kaynak = _wav_oku("res://build/ses/kaynak/%s_ham.wav" % a.substr(7))
		elif a.begins_with("yanki_oran="):
			YANKI_TEST = float(a.substr(11))  # test: telefonun yankı engelleyicisi açıkmış gibi (ör. 0.12)
		elif a == "mik_kapali=1":
			kapali = true  # test: dinleyen taraf (aynı bilgisayardaki ikinci oyuncu) hiç ses yollamaz


func start() -> void:
	if active:
		return
	active = true
	_pending.clear()
	_queues.clear()
	_q2.clear()
	_space.clear()
	_open_left = 0
	_prev_chunk = PackedFloat32Array()
	_sifir_t = 0.0
	_capture.clear_buffer()
	if not test_tone:
		_mik_baslat()
	_out_player.play()  # yerel çıkış varsa da açık kalır (boş): yerel yol koparsa hemen buraya dönülür
	_out = _out_player.get_stream_playback()
	_kapasite = _out.get_frames_available() if _out else 0  # boşken boş yer = gerçek kapasite
	_out_yanki.play()
	_yanki = _out_yanki.get_stream_playback()


# Telefon bağlandı: zilden kalan ayarlar bırakılır, konuşma kazancına dönülür, kapı hemen açık başlar (ilk hece kesilmesin).
func hat_acildi() -> void:
	zil = false
	_kazanc = _konusma_kazanc
	_gurultu = minf(_gurultu, _gurultu_kayit)
	_yanki_tepe = 0.0
	_open_left = HANGOVER


func stop() -> void:
	active = false
	_yerel_durdur()
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
	if active and _yerel_baslat():
		_mic_player.stop()
		return
	_mic_player.play()


# Telefonun sesli görüşme yolu (yalnız telefonda; eklenti yoksa ya da açılamazsa Godot'nun mikrofonu kullanılır)
func _yerel_baslat() -> bool:
	if test_tone or not yerel_izin or not OS.has_feature("mobile") or not ClassDB.class_exists("HatSes"):
		return false
	if _yerel == null:
		_yerel = ClassDB.instantiate("HatSes")
	if not _yerel.call("calisiyor") and not _yerel.call("baslat", RATE):
		print("[ses] yerel yol acilamadi: ", _yerel.call("durum"))
		_yerel = null
		_yerel_cikis = false
		_yanki_oran = YANKI_ORAN
		return false
	_yerel_cikis = bool(_yerel.call("cikis_var"))
	# platform yankı engelleyicisi açık: kendi yankı kapımız yalnız artığa karşı (iOS'ta gelen ses de onun üstünden)
	if bool(_yerel.call("yanki_engelleme")):
		_yanki_oran = 0.12 if _yerel_cikis else 0.3
	print("[ses] ", _yerel.call("durum"))
	return true


func _yerel_durdur() -> void:
	if _yerel:
		_yerel.call("durdur")
	_yerel = null
	_yerel_cikis = false
	_yanki_oran = YANKI_ORAN


func yerel_durum() -> String:
	return str(_yerel.call("durum")) if _yerel else "godot"


func _izin_sonucu(izin: String, verildi: bool) -> void:
	if not izin.ends_with("RECORD_AUDIO"):
		return
	_izin_bekliyor = false
	if not verildi:
		_sorun("izin")
	elif active:
		_mic_player.stop()
		_mik_baslat()
	elif testing:
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
	# telefonun sesli görüşme yolu iki kez üst üste sessiz kaldıysa bu oturumda Godot'nun mikrofonuna geçilir
	# (aynı yolu yeniden yeniden denemesin; telemetride "ses_yolu" godot görünür)
	if _yerel and _yeniden_sayi >= 2:
		print("[ses] yerel yol sessiz kaldı, Godot mikrofonuna geçiliyor")
		yerel_izin = false
	_yerel_durdur()
	_mik_baslat()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and active:
		_mik_yeniden()


# Test: 16 bit tek kanal WAV'ı örneklere çevirir (yoksa boş)
static func _wav_oku(yol: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var b := FileAccess.get_file_as_bytes(yol)
	var i := 12
	while i + 8 <= b.size():
		var ad := b.slice(i, i + 4).get_string_from_ascii()
		var n := b.decode_u32(i + 4)
		if ad == "data":
			var j := i + 8
			while j + 1 < mini(i + 8 + n, b.size()):
				out.append(float(b.decode_s16(j)) / 32768.0)
				j += 2
			break
		i += 8 + n + (n & 1)
	return out


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
	_yanki_tepe = maxf(_cikis_rms, _yanki_tepe * exp(-delta / YANKI_KUYRUK))
	if _yanki_acik and Time.get_ticks_msec() - _yanki_son_ms > 4000:
		_yanki_acik = false
		AudioServer.set_bus_effect_enabled(_yanki_bus, 0, false)
	_read_input(delta)
	while _pending.size() >= CHUNK:
		var chunk := _pending.slice(0, CHUNK)
		_pending = _pending.slice(CHUNK)
		_send_chunk(chunk)
	_feed_output()


# Mikrofonu (ya da test bipini) 24 kHz tek kanala çevirip biriktirir.
func _read_input(delta: float) -> void:
	if not test_kaynak.is_empty():
		var nk := int(RATE * delta)
		for i in nk:
			_pending.append(test_kaynak[_test_konum])
			_test_konum = (_test_konum + 1) % test_kaynak.size()
		return
	if test_tone:
		var n := int(RATE * delta)
		for i in n:
			_tone_phase += TAU * 440.0 / RATE
			var on := fmod(_tone_phase / TAU / 440.0, 1.0) < 0.5
			_pending.append(sin(_tone_phase) * 0.3 if on else 0.0)
		return
	if _yerel:
		var p: PackedFloat32Array = _yerel.call("oku")
		if p.is_empty():
			_sessiz_mi(delta)
		else:
			_pending.append_array(p)
		return
	var frames := _capture.get_frames_available()
	if frames <= 0:
		_sessiz_mi(delta)
		return
	_pending.append_array(ornek_indir(_capture.get_buffer(frames), AudioServer.get_mix_rate() / RATE))


# Mikrofon akışını 24 kHz'e indirir. Konum kareler arasında korunur; -1..0 aralığı önceki karenin son örneği
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
	# ilk 6 deneme hızlı (1,5 sn arayla); sonra vazgeçmeden 5 sn'de bir: Windows mikrofonu bir süre kapatıp
	# (Win+Alt+K, gizlilik, sürücü) yeniden açınca oyun kendiliğinden toparlansın (eskiden 6 denemede pes ediyordu)
	if _sifir_t < (SESSIZ_SURE if _yeniden_sayi < 6 else 5.0):
		return
	_yeniden_sayi = mini(_yeniden_sayi + 1, 1000)
	_mik_yeniden()
	if _yeniden_sayi == 3:
		_sorun("sessiz")


func _send_chunk(chunk: PackedFloat32Array) -> void:
	_tik = (_tik + 1) & 0xFFFF
	var rms := 0.0
	for v in chunk:
		rms += v * v
	rms = sqrt(rms / chunk.size())
	level = clampf(rms * 6.0, 0.0, 1.0)
	tepe = maxf(tepe, rms)
	if rms > 0.0:
		_sifir_t = 0.0
		_yeniden_sayi = 0
	elif OS.has_feature("mobile"):
		_sessiz_mi(float(chunk.size()) / RATE)
	# Bilgisayarda tam sıfır ses normaldir: dizüstü mikrofonlarındaki yapay zekâ gürültü engelleme (Acer PurifiedVoice,
	# Realtek, ASUS AI...) konuşma yokken sıfır verir. Eskiden bu "mikrofon öldü" sanılıp mikrofon 1,5 sn'de bir
	# kapatılıp açılıyordu: konuşmanın başı kesiliyor, ses sekiyordu. Masaüstünde yalnız hiç veri gelmezse yeniden başlatılır.
	if muted or kapali or (ptt_enabled and not ptt_down):
		_open_left = 0
		_prev_chunk = chunk
		_test_ekle(null)
		return
	var was_open := _open_left > 0
	# ortam gürültüsü yalnız kapı kapalıyken öğrenilir; eşikler onunla yükselir (fan, sokak sesi kapıyı açık tutmasın)
	if not was_open and not zil:
		_gurultu = lerpf(_gurultu, minf(rms, GURULTU_TAVAN), 0.25 if rms < _gurultu else 0.02)
	var esik := maxf(GATE_OPEN, _gurultu * 3.0)
	var esik_kapa := maxf(GATE_CLOSE, _gurultu * 1.6)
	# karşı taraf konuşurken hoparlörden mikrofona kaçan ses geri gitmesin (kendi sesini robot gibi duyar);
	# bas-konuş basılıyken kişi bilerek konuşuyor, kapı yükselmez
	if _yanki_tepe > 0.002 and not ptt_enabled:
		var yanki := _yanki_tepe * (YANKI_TEST if YANKI_TEST >= 0.0 else _yanki_oran)
		esik = maxf(esik, yanki)
		esik_kapa = maxf(esik_kapa, yanki)
	# yumuşak ses kapısı: yüksek eşikle açılır, düşük eşik + bekleme süresiyle kapanır
	if rms >= esik or (was_open and rms >= esik_kapa):
		_open_left = HANGOVER
	elif _open_left > 0:
		_open_left -= 1
	if _open_left <= 0:
		_prev_chunk = chunk
		_test_ekle(null)
		return
	# kendiliğinden kazanç: kısık mikrofon yükselir, gürültü yükselmesin diye yalnız konuşma parçalarında değişir
	var k0 := _kazanc
	if rms >= esik and not zil:
		var iste := clampf(HEDEF_SES / maxf(rms, 0.001), 1.0, KAZANC_MAX)
		_kazanc = lerpf(_kazanc, iste, 0.5 if iste < _kazanc else 0.06)
		_konusma_kazanc = _kazanc
	if not was_open and _prev_chunk.size() == chunk.size():
		_emit_chunk(_prev_chunk, k0, k0, (_tik - 1) & 0xFFFF)  # konuşma başlamadan önceki an da gitsin
	_emit_chunk(chunk, k0, _kazanc, _tik)
	_prev_chunk = chunk
	_test_ekle(_son_giden)


func _emit_chunk(chunk: PackedFloat32Array, k0: float, k1: float, tik: int) -> void:
	var n := chunk.size()
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	var g := k0
	var dg := (k1 - k0) / n
	for i in n:
		var x := chunk[i] * g
		g += dg
		if x > DIZ or x < -DIZ:
			x = _sinirla(x)
		pcm[i] = x
	sent_packets += 1
	_son_giden_pcm = pcm
	if test_olay_ac:
		test_gidis.append(Time.get_ticks_msec())
	if _kod:
		var paket: PackedByteArray = _kod.call("kodla", pcm)
		if not paket.is_empty():
			var data := PackedByteArray([OPUS_BAS[0], OPUS_BAS[1], tik & 0xFF, (tik >> 8) & 0xFF])
			data.append_array(paket)
			_son_giden = data
			packet_ready.emit(data)
			if not eski_var:
				return
	# eski sürümler (ya da Opus yoksa herkes): 16 kHz mu-law
	var eski := _mulaw(_asagi_ornekle(pcm))
	_son_giden = eski
	packet_ready.emit(eski)


# 24 kHz -> 16 kHz (eski sürümler): hafif yumuşatma (8 kHz üstü katlanmasın) + doğrusal ara değer
static func _asagi_ornekle(p: PackedFloat32Array) -> PackedFloat32Array:
	var n := p.size()
	var m := int(n * ESKI_RATE / RATE)
	var o := PackedFloat32Array()
	o.resize(m)
	for j in m:
		var pos := j * 1.5
		var i := int(pos)
		var f := pos - i
		var a0 := p[maxi(i - 1, 0)]
		var a1 := p[i]
		var a2 := p[mini(i + 1, n - 1)]
		var a3 := p[mini(i + 2, n - 1)]
		var y1 := (a0 + 2.0 * a1 + a2) * 0.25
		var y2 := (a1 + 2.0 * a2 + a3) * 0.25
		o[j] = y1 + (y2 - y1) * f
	return o


# 16 kHz -> 24 kHz (eski sürümden gelen ses): doğrusal ara değer
static func _yukari_ornekle(p: PackedFloat32Array) -> PackedFloat32Array:
	var n := p.size()
	var m := int(n * RATE / ESKI_RATE)
	var o := PackedFloat32Array()
	o.resize(m)
	for j in m:
		var pos := j / 1.5
		var i := int(pos)
		var f := pos - i
		var a := p[i]
		var b := p[mini(i + 1, n - 1)]
		o[j] = a + (b - a) * f
	return o


static func _mulaw(p: PackedFloat32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(p.size())
	var tablo := _KOD
	for i in p.size():
		var x := clampf(p[i], -1.0, 1.0)
		if x < 0.0:
			data[i] = 0x80 | tablo[mini(int(-x * 16383.0), 16383)]
		else:
			data[i] = tablo[mini(int(x * 16383.0), 16383)]
	return data


# Test: bu 40 ms'de giden ses (kapıda kaldıysa sessizlik) kayda eklenir
func _test_ekle(veri: Variant) -> void:
	if not test_giden:
		return
	if veri == null:
		var z := PackedFloat32Array()
		z.resize(CHUNK)
		test_kayit.append_array(z)
		return
	test_kayit.append_array(_son_giden_pcm)


# Zaman damgalı parça (Opus sürüm 2): sayaç açılır (16 bit sarması), gecikme oynaması ölçülür, sıraya konur.
func _al_damgali(id: int, tik16: int, pcm: PackedFloat32Array) -> void:
	var s := _konusan(id)
	var t: int
	if int(s.tik_son) < 0:
		t = tik16 + 0x10000  # ilk parça: geriye sarmada eksiye düşmesin
	else:
		var fark := posmod(tik16 - (int(s.tik_son) & 0xFFFF) + 0x8000, 0x10000) - 0x8000
		t = int(s.tik_son) + fark
	s.tik_son = maxi(int(s.tik_son), t)
	var simdi := Time.get_ticks_msec()
	# gecikme oynaması: (geliş - konuşulma) farkı; son 5 sn'deki en büyük ile en küçük farkı tampon hedefini verir
	var d := simdi - t * 40
	var g: Array = s.dly
	g.append(d)
	if g.size() > 125:
		g.pop_front()
	# en kötü değil %90'lık dilim: tek bir ani takılma tamponu 5 sn boyunca şişirmesin (nadir takılmayı hoparlör
	# payı ve kayıp gizleme karşılar)
	var oyn := 0
	if g.size() > 4:
		var sirali := g.duplicate()
		sirali.sort()
		oyn = int(sirali[int(sirali.size() * 0.95)]) - int(sirali[0])
	# gerçek takılma yaşandıysa ek pay (her 4 sn takılmasız geçişte bir parça geri); ilk ölçümlerde temkinli başla
	if int(s.ek) > 0 and simdi - int(s.ek_ms) > 4000:
		s.ek = int(s.ek) - 1
		s.ek_ms = simdi
	# ilk ~1 sn ölçüm yokken temkinli (240 ms): oynama öğrenilene kadar boşalmasın
	var en_az := T_MIN if g.size() >= 25 else 6
	s.hedef = clampi(ceili((float(oyn) + 20.0) / 40.0) + int(s.ek), en_az, PRIME_MAX)
	# test: gizlenen (geç kalan) parçanın devamı geldi: gerçek takılma
	if test_olay_ac and int(s.gizle_tik) >= 0:
		if absi(t - int(s.gizle_tik)) <= 3:
			test_kesinti[id] = int(test_kesinti.get(id, 0)) + 1
		s.gizle_tik = -1
	if not _q2.has(id):
		_q2[id] = []
	var q: Array = _q2[id]
	# çalınmış ya da gizlenmiş anın parçası geç geldi: atılır (gecikme birikmesin)
	if bool(s.hazir) and t < int(s.beklenen):
		return
	q.append([t, pcm])
	# çok birikti (ör. uygulama arka plandan döndü): hedefin üstü atılır, en yeniye yetişilir
	if q.size() > int(s.hedef) + 6:
		while q.size() > int(s.hedef):
			q.pop_front()
		if bool(s.hazir):
			s.beklenen = int(q[0][0])


# Gelen ses: ilk bayt konuşanın kimliği, gerisi mu-law ses. Her konuşanın ayrı kuyruğu var;
# çalınırken mesafeye göre (gains) karıştırılır.
func receive(data: PackedByteArray) -> void:
	if not active or data.size() < 2:
		return
	received_packets += 1
	var id := int(data[0])
	if test_olay_ac:
		test_alinan[id] = int(test_alinan.get(id, 0)) + 1
		if not test_gelis.has(id):
			test_gelis[id] = []
		(test_gelis[id] as Array).append(Time.get_ticks_msec())
		var bm := int(_bos_ms.get(id, 0))
		if bm > 0 and Time.get_ticks_msec() - bm < 250:
			test_kesinti[id] = int(test_kesinti.get(id, 0)) + 1
		_bos_ms[id] = 0
	var n := data.size() - 1
	var pcm := PackedFloat32Array()
	if n >= 3 and data[1] == OPUS_BAS[0] and (data[2] == 0x01 or data[2] == 0x02) and n != ESKI_CHUNK:
		var bas := 3
		var tik := -1
		if data[2] == 0x02 and n >= 5:
			tik = int(data[3]) | (int(data[4]) << 8)
			bas = 5
		var c: RefCounted = _cozucu.get(id)
		if c == null:
			if not ClassDB.class_exists("HatOpusCozucu"):
				return
			c = ClassDB.instantiate("HatOpusCozucu")
			c.call("kur", RATE)
			_cozucu[id] = c
		pcm = c.call("coz", data.slice(bas))
		if pcm.is_empty():
			return
		_konusan(id).opus = true
		if tik >= 0:
			_al_damgali(id, tik, pcm)
			return
	else:
		var eski := PackedFloat32Array()
		eski.resize(n)
		var tablo := _AC
		for i in n:
			eski[i] = tablo[data[i + 1]]
		pcm = _yukari_ornekle(eski)
	if not _queues.has(id):
		_queues[id] = []
	var q: Array = _queues[id]
	q.append(pcm)
	var s := _konusan(id)
	_titresim(s)
	# boşluktan hemen sonra paket geldiyse konuşma bitmemiş, bağlantı dalgalanmış: bu kişi için tamponu büyüt
	if int(s.alt_ms) > 0:
		if Time.get_ticks_msec() - int(s.alt_ms) < 500:
			s.hedef = mini(int(s.hedef) + 1, PRIME_MAX)
		s.alt_ms = 0
	if q.size() > 15:
		_queues[id] = q.slice(q.size() - int(s.hedef))  # çok geride kaldıysa yetiş


# Bağlantı takılması ölçülür: takılmanın ardından biriken paketler art arda (aynı karede) gelir. Art arda gelen paket
# sayısı takılmanın süresini verir (n paket = (n-1) x 40 ms). Konuşmadaki duraklamadan sonra böyle bir yığılma olmaz,
# bu yüzden duraklama takılma sanılmaz. En kötü takılma (yavaşça unutularak) tampon hedefini belirler.
func _titresim(s: Dictionary) -> void:
	var simdi := Time.get_ticks_msec()
	var ara := simdi - int(s.son_ms)
	s.son_ms = simdi
	if ara > 300:
		s.say = 0  # yeni konuşma parçası: ilk paket (ve hemen ardından gelen ön parça) yığılma sayılmaz
	elif ara < 15:
		s.say = int(s.say) + 1
	else:
		s.say = 1
	var takilma := float(maxi(int(s.say) - 1, 0)) * 40.0
	s.gec = maxf(takilma, float(s.gec) * 0.998)  # en kötü takılma, ~14 sn'de yarıya iner
	s.hedef = clampi(ceili((float(s.gec) + 50.0) / 40.0), PRIME, PRIME_MAX)


func _konusan(id: int) -> Dictionary:
	var s: Dictionary = _space.get(id, {})
	if s.is_empty():
		s = {"g": 0.0, "p": 0.0, "g0": 0.0, "p0": 0.0, "m": 0.0, "w": 0.0, "w0": 0.0, "lp": 0.0, "tel": [0.0, 0.0, 0.0, 0.0],
			"phone": phone_line, "bilinen": false, "hazir": false, "hedef": PRIME, "bosluk": 0, "son": PackedFloat32Array(), "alt_ms": 0,
			"ilk_ms": 0, "say": 0, "gec": 0.0, "son_ms": 0, "taban": 0.0, "opus": false,
			"tik_son": -1, "dly": [], "beklenen": 0, "gizle_tik": -1, "ek": 0, "ek_ms": 0}
		_space[id] = s
	return s


# Bir konuşanın ses seviyesi (0 = duyulmaz, 1 = tam). Eski arayüz: ortada, süzgeçsiz.
# Ayrılan konuşanın kuyruk, kazanç ve süzgeç durumları silinir.
func forget(id: int) -> void:
	_queues.erase(id)
	_q2.erase(id)
	_cozucu.erase(id)
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


# Hoparlöre giden konuşmanın tamponu: yerel yol (iOS, yankı engelleyicinin bildiği) ya da Godot üreteci
func _cikis_bos() -> int:
	if _yerel_cikis and _yerel:
		return int(_yerel.call("bos_yer"))
	return _out.get_frames_available()


func _cikis_dolu() -> int:
	if _yerel_cikis and _yerel:
		return int(_yerel.call("bekleyen"))
	return _kapasite - _out.get_frames_available()


func _feed_output() -> void:
	if _out == null:
		return
	# test: konuşma sürerken hoparlör tamponu bittiyse oyun karesi takılmıştır (sesin kendisi değil)
	var calan := false
	for id in _q2:
		calan = calan or bool(_konusan(int(id)).hazir)
	var simdi_dolu := _cikis_dolu()
	if calan and simdi_dolu <= 0 and _onceki_dolu > 0:
		if not _aclik:
			if test_olay_ac:
				test_cikis_aclik += 1
				test_aclik_kare.append(int(get_process_delta_time() * 1000.0))
			_cikis_pay = minf(_cikis_pay + 40.0, 320.0)  # kare takıldı: payı büyüt
			_pay_ms = Time.get_ticks_msec()
		_aclik = true
	elif simdi_dolu > 0:
		_aclik = false
	_onceki_dolu = simdi_dolu
	if _cikis_pay > 160.0 and Time.get_ticks_msec() - _pay_ms > 10000:
		_cikis_pay -= 20.0
		_pay_ms = Time.get_ticks_msec()
	var azami := int(RATE * _cikis_pay / 1000.0)
	while true:
		var bos := _cikis_bos()
		var dolu := _cikis_dolu()
		if bos < CHUNK or dolu >= azami:
			break
		# konuşan başına tampon: yeni konuşan birikmeden çalmaz, ötekileri bekletmez
		var veri := false
		for id in _queues:
			var q: Array = _queues[id]
			var s := _konusan(int(id))
			if not bool(s.hazir) and q.size() >= int(s.hedef):
				if test_olay_ac:
					test_olaylar.append([Time.get_ticks_msec(), "basla", int(id), q.size(), dolu, int(s.hedef)])
				s.hazir = true
				s.bosluk = 0
				s.g0 = 0.0  # girişte tık olmasın
				s.w0 = 0.0
			if bool(s.hazir) and not q.is_empty():
				veri = true
		var bekle := false
		for id in _q2:
			var q: Array = _q2[id]
			var s := _konusan(int(id))
			if not bool(s.hazir) and not q.is_empty() and int(q.back()[0]) - int(q[0][0]) + 1 >= int(s.hedef):
				if test_olay_ac:
					test_olaylar.append([Time.get_ticks_msec(), "basla", int(id), q.size(), dolu, int(s.hedef)])
				s.hazir = true
				s.bosluk = 0
				s.beklenen = int(q[0][0])
				s.g0 = 0.0  # girişte tık olmasın
				s.w0 = 0.0
			if bool(s.hazir):
				veri = true
				# sıradaki parçası geç kalan (konuşmayı sürdürüyor ama parça henüz yok) konuşan: hoparlörde ses
				# varken beklenir; parça yetişirse gizlemeye gerek kalmaz
				var b := int(s.beklenen)
				var gecikti := (q.is_empty() or int(q[0][0]) > b) and int(s.tik_son) >= b - 1 and int(s.bosluk) < GIZLE_MAX
				# (bekleme payı 80 ms: oyun karesi ~16-33 ms, ses kartı sesi bloklar halinde tüketir; 40 ms sınırında
				# bir sonraki karede tampon çoktan bitmiş oluyordu)
				if gecikti and dolu >= RATE * 8 / 100:
					bekle = true
		if bekle:
			break
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
			# takılmadan sonra: tampon yeniden biraz dolmadan sürdürme (yoksa her dalgada küçük delikler olur)
			if int(s.bosluk) > 0 and q.size() < maxi(2, int(s.hedef) / 2):
				if dolu >= CHUNK:
					continue
				q = []
			if q.is_empty():
				# paket gecikti: boşluk yerine son parça kısılarak söner; uzun sürerse konuşma bitmiştir
				if test_olay_ac:
					test_olaylar.append([Time.get_ticks_msec(), "bos", int(id), 0, dolu, int(s.hedef)])
					if int(_bos_ms.get(int(id), 0)) == 0:
						_bos_ms[int(id)] = Time.get_ticks_msec()
				if int(s.bosluk) == 0:
					s.gec = maxf(float(s.gec), float(s.hedef) * 40.0)  # konuşurken tampon boşaldı: bir sonraki için büyüt
					s.hedef = clampi(ceili((float(s.gec) + 50.0) / 40.0), PRIME, PRIME_MAX)
				if int(s.bosluk) < BOSLUK_KAPAT and not (s.son as PackedFloat32Array).is_empty():
					s.bosluk = int(s.bosluk) + 1
					# Opus: çözücünün kayıp gizlemesi (konuşmanın doğal devamı, kısılarak); mu-law: son parça tekrar
					var gizle: PackedFloat32Array = s.son
					var c: RefCounted = _cozucu.get(int(id))
					if bool(s.opus) and c:
						var plc: PackedFloat32Array = c.call("kayip", CHUNK)
						if plc.size() == CHUNK:
							gizle = plc
					_mix_speaker(int(id), gizle, true)
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
		for id in _q2:
			if _cal_damgali(int(id)):
				any = true
		if not any:
			break
		_sesi_yolla()


# Zaman damgalı konuşanın sıradaki 40 ms'i: sırası gelen parça; kısa susma sessizlik; gecikmiş parça kayıp gizleme
# (en çok 2 parça, sonra konuşma "bitti" sayılır, devamı gelince yeniden tamponlanır). false: bu turda ses yok.
func _cal_damgali(id: int) -> bool:
	var s := _konusan(id)
	if not bool(s.hazir):
		return false
	var q: Array = _q2[id]
	var b := int(s.beklenen)
	while not q.is_empty() and int(q[0][0]) < b:
		q.pop_front()  # gizlenen anın geç gelen parçası
	if not q.is_empty() and int(q[0][0]) == b:
		var pcm: PackedFloat32Array = q.pop_front()[1]
		s.bosluk = 0
		s.son = pcm
		s.beklenen = b + 1
		_mix_speaker(id, pcm, false)
		return true
	if not q.is_empty() and int(q[0][0]) - b <= SUSMA_DOLDUR:
		# gönderen çok kısa sustu (ses kapısı): araya sessizlik, konuşma bölünmez
		s.beklenen = b + 1
		s.son = PackedFloat32Array()
		return true
	if not q.is_empty():
		# uzun susmadan sonra yeni konuşma: yeniden tamponla
		s.hazir = false
		return false
	# parça henüz gelmedi: gönderen konuşuyor muydu? son gelen parça bu anın hemen öncesiyse evet (geç kaldı)
	if int(s.tik_son) >= b - 1 and int(s.bosluk) < GIZLE_MAX:
		if int(s.bosluk) == 0:
			s.gizle_tik = b
			# geç kalan parça yüzünden gizleme: bu konuşanın tamponuna bir parça pay ekle
			s.ek = mini(int(s.ek) + 1, 6)
			s.ek_ms = Time.get_ticks_msec()
			if test_olay_ac:
				test_olaylar.append([Time.get_ticks_msec(), "bos", id, 0, _cikis_dolu(), int(s.hedef)])
		s.bosluk = int(s.bosluk) + 1
		var gizle := PackedFloat32Array()
		var c: RefCounted = _cozucu.get(id)
		if c:
			gizle = c.call("kayip", CHUNK)
		if gizle.size() != CHUNK:
			gizle = s.son
		s.beklenen = b + 1
		if gizle.size() == CHUNK:
			_mix_speaker(id, gizle, true)
		return true
	s.hazir = false
	s.son = PackedFloat32Array()
	return false


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
	if _yerel_cikis and _yerel:
		_yerel.call("yaz", buf)
	else:
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
	# geçiş parça boyunca; ama sessizlikten açılırken (g0 = 0) yalnız ilk 5 ms
	var gecis := n
	if g0 <= 0.0 and g1 > 0.0 and not son:
		gecis = mini(n, RATE / 200)  # 5 ms
	var dl := (g1 * cos(ang1) * 1.41 - l) / gecis
	var dr := (g1 * sin(ang1) * 1.41 - r) / gecis
	var w := w0
	var dw := (w1 - w0) / gecis
	var ml := _mix_l
	var mr := _mix_r
	var mw := _mix_w
	if phone and not robot:
		var tel: Array = s.tel
		for i in n:
			lp += (_telephone_st(pcm[i], tel) - lp) * a
			ml[i] += lp * l
			mr[i] += lp * r
			if i < gecis:
				l += dl
				r += dr
	elif w0 <= 0.0 and w1 <= 0.0:
		for i in n:
			lp += (pcm[i] - lp) * a
			ml[i] += lp * l
			mr[i] += lp * r
			if i < gecis:
				l += dl
				r += dr
	else:
		for i in n:
			lp += (pcm[i] - lp) * a
			ml[i] += lp * l
			mr[i] += lp * r
			mw[i] += lp * w
			if i < gecis:
				l += dl
				r += dr
				w += dw
	s.lp = lp


# Yumuşak sınırlayıcı: DIZ üstü tanh ile sıkıştırılır (en çok 1.0). Sert kırpma cızırtı/çatlama yapıyordu.
static func _sinirla(x: float) -> float:
	var a := absf(x)
	var y := DIZ + (TAVAN - DIZ) * tanh((a - DIZ) / (TAVAN - DIZ))
	return y if x > 0.0 else -y


# Robot sesi (Kim Kim?): ne kimin konuştuğu ne de ne dediği anlaşılsın (kullanıcı isteği, 8 Kasım 2026).
# Konuşmanın ritmi ve vurgusu duyulur ("biri konuşuyor"), kelimeler anlaşılmaz:
#  - ~2,8 kHz alçak geçiren, sonra kayan ~3 kHz taşıyıcıyla çarpma: tayf ters döner (telsiz karıştırıcısı gibi;
#    kalın sesler ince, ince sesler kalın olur, ünlüler / ünsüzler tanınmaz). Taşıyıcı yavaşça kaydığı için
#    beyin alışıp çözemez.
#  - yansıyı ikinci alçak geçirenle süz, 4 kHz örnek tutma: metalik robot dokusu
#  - 90 Hz genlik vınlaması + yumuşak doyum: klasik robot
func _robotize(x: float) -> float:
	var a := 1.0 - exp(-TAU * 2800.0 / RATE)  # tek kutuplu alçak geçiren (~2,8 kHz)
	_rb_lp[0] += a * (x - _rb_lp[0])
	_rb_lp[1] += a * (_rb_lp[0] - _rb_lp[1])
	_rb_lfo = fmod(_rb_lfo + TAU * 0.6 / RATE, TAU)
	var fc := 3000.0 + 450.0 * sin(_rb_lfo)
	_rb_tasiyici = fmod(_rb_tasiyici + TAU * fc / RATE, TAU)
	var y: float = _rb_lp[1] * cos(_rb_tasiyici) * 2.8
	_rb_lp[2] += a * (y - _rb_lp[2])
	_rb_lp[3] += a * (_rb_lp[2] - _rb_lp[3])
	_rb_say += 1
	if _rb_say >= RATE / 4000:  # 4 kHz örnek tutma
		_rb_say = 0
		_rb_tut = _rb_lp[3]
	_rb_phase = fmod(_rb_phase + TAU * 90.0 / RATE, TAU)
	var o := _rb_tut * (0.35 + 0.65 * absf(sin(_rb_phase)))
	return tanh(o * 2.0) * 0.75


func set_volume(v: float) -> void:
	_out_player.volume_db = linear_to_db(maxf(v, 0.001))


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
		_hat.volume_db = HAT_DB + _out_player.volume_db
		_hat.play()
	elif not on and _hat.playing:
		_hat.stop()
