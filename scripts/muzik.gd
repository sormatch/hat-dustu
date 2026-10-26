# Fon müziği ve gardiyan anonsları. Müzikler iki çalar arasında yumuşakça geçer (crossfade);
# telefonda konuşurken ya da anons sırasında müzik kısılır. Ses düzeyi ayarlardan (muzik_ses).
extends Node

const TRACKS := {
	"menu": "res://assets/muzik/menu.ogg", "gerilim": "res://assets/muzik/gerilim.ogg", "nabiz": "res://assets/muzik/nabiz.ogg",
	"ortam": "res://assets/muzik/ortam.ogg", "korku": "res://assets/muzik/korku.ogg", "hava": "res://assets/muzik/hava.ogg",
	"zafer": "res://assets/muzik/zafer.ogg",
}
# her mini oyunun müziği
const GAME_TRACK := {
	"tahta": "ortam", "devre": "nabiz", "kimkim": "korku", "yalanci": "hava", "rulet": "gerilim", "c4": "nabiz", "ortalama": "ortam",
	"ikilem": "hava", "kumar": "gerilim",
}
const BASE_DB := -9.0  # müzik konuşmanın ve efektlerin altında kalsın

var volume := 0.7  # ayarlardaki müzik sesi (0-1)
var _players: Array[AudioStreamPlayer] = []
var _cur := 0
var _track := ""
var _duck := 1.0  # anons/telefon sırasında kısma
var _duck_target := 1.0
var _announcer: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		p.bus = &"Muzik"
		add_child(p)
		_players.append(p)
	_announcer = AudioStreamPlayer.new()
	_announcer.volume_db = 2.0
	_announcer.bus = &"Efekt"
	add_child(_announcer)
	_announcer.finished.connect(func() -> void: _duck_target = 1.0)


# Müziği değiştir ("" durdurur). Aynı parça çalıyorsa dokunmaz.
func play(track: String, fade := 1.5) -> void:
	if track == _track:
		return
	_track = track
	var old := _players[_cur]
	_cur = 1 - _cur
	var nu := _players[_cur]
	if old.playing:
		var to := old.create_tween()
		to.tween_property(old, "volume_db", -80.0, fade)
		to.tween_callback(old.stop)
	if track == "" or not TRACKS.has(track):
		return
	var st: AudioStream = load(TRACKS[track])
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = track != "zafer"
	nu.stream = st
	nu.volume_db = -80.0
	nu.play()
	nu.create_tween().tween_property(nu, "volume_db", _target_db(), fade)


func play_game(task: String) -> void:
	play(GAME_TRACK.get(task, "ortam"))


func _target_db() -> float:
	return BASE_DB + linear_to_db(maxf(volume * _duck, 0.0005))


# Gardiyan anonsu (assets/ses/anons/<ad>.ogg; İngilizcede anons_en/); çalarken müzik kısılır.
func announce(line: String) -> void:
	var path := "res://assets/ses/anons/%s.ogg" % line
	if not preload("res://scripts/dil.gd").tr_mi():
		var en := "res://assets/ses/anons_en/%s.ogg" % line
		if ResourceLoader.exists(en):
			path = en
	if not ResourceLoader.exists(path):
		return
	_announcer.stream = load(path)
	_announcer.play()
	_duck_target = 0.35


# Telefonda konuşurken müzik kısılsın.
func set_call(on: bool) -> void:
	_duck_target = 0.25 if on else 1.0


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	_duck = move_toward(_duck, _duck_target, delta * 1.5)
	var p := _players[_cur]
	if p.playing and not _is_fading(p):
		p.volume_db = _target_db()
	_karistir(delta)
	_ortam_isle(delta)


func _is_fading(p: AudioStreamPlayer) -> bool:
	return p.volume_db < _target_db() - 6.0 and p.get_playback_position() < 2.0


# =====================================================================
# KARIŞTIRMA: efekt sesi ayarı + sesli sohbette müzik ve ortamın kısılması (ducking)
# =====================================================================

const DUCK_MUZIK_DB := -6.0  # biri konuşurken müzik bu kadar kısılır
const DUCK_ORTAM_DB := -8.0  # ortam sesi biraz daha
var _konusma := 0.0  # konuşma zarfı (0-1): hızlı iner, yavaş kalkar
var _bus := {}


func _bus_i(ad: StringName) -> int:
	if not _bus.has(ad):
		_bus[ad] = AudioServer.get_bus_index(ad)
	return _bus[ad]


# Ayarlardaki "Oyun sesi" (0-1): Efekt bus'ı; ortam da Efekt'e bağlı olduğu için onunla kısılır.
func set_efekt(v: float) -> void:
	var i := _bus_i(&"Efekt")
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func _karistir(delta: float) -> void:
	var w := get_parent()
	# ayarlar açıkken kaydırıcı oynatılınca da anında uygulansın (yalnızca değer değişince)
	var prof = w.get("profile") if w else null
	if prof:
		var v := float(prof.settings.get("oyun_ses", 1.0))
		if not is_equal_approx(v, _efekt_son):
			_efekt_son = v
			set_efekt(v)
	var talk := 0.0
	var voice = w.get("voice") if w else null
	if voice and voice.get("active") and voice.has_method("talk_max"):
		talk = voice.talk_max()
	var hedef := 1.0 if talk > 0.12 else 0.0
	_konusma = move_toward(_konusma, hedef, delta * (6.0 if hedef > _konusma else 1.2))
	var mi := _bus_i(&"Muzik")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, DUCK_MUZIK_DB * _konusma)
	var oi := _bus_i(&"Ortam")
	if oi >= 0:
		AudioServer.set_bus_volume_db(oi, DUCK_ORTAM_DB * _konusma)


var _efekt_son := -1.0


# =====================================================================
# ORTAM SESİ: hücre/koridor/yemekhane. Kısık bir döngü (havalandırma, floresan vızıltısı,
# uzak uğultu, damla) + rastgele aralıklarla koridorun ucundan gelen 3B tek seferlik sesler
# (uzak kapı çarpması, parmaklık, öksürük, anahtar, boru, bağırış). Menüde ve maç sonunda susar.
# =====================================================================

const ORTAM_DONGU := "res://assets/ses/ortam_dongu.ogg"
const ORTAM_DB := -6.0  # döngü dosyası -30 LUFS; müziğin (≈ -32) altında kalsın
const ORTAM_OLAY := ["uzak_kapi_1", "uzak_kapi_2", "uzak_kapi_3", "uzak_parmaklik", "uzak_oksuruk_1",
	"uzak_oksuruk_2", "uzak_oksuruk_3", "uzak_anahtar", "uzak_boru", "uzak_bagiris"]
# koridor (main.gd CORRIDOR_X0..X1, CORRIDOR_HALF): olaylar iki uçtan birinden gelir
const KORIDOR_X := 3.9
const KORIDOR_UC := 26.0
var _ortam_izin := true  # maç sonunda false (main.gd game_over)
var _ortam: AudioStreamPlayer
var _olay: AudioStreamPlayer3D
var _olay_t := 6.0
var _son_olay := ""


# Maç bitti / yeni maç başladı.
func ortam_izin(on: bool) -> void:
	_ortam_izin = on


func _ortam_isle(delta: float) -> void:
	var w := get_parent()
	var acik: bool = _ortam_izin and w != null and bool(w.get("playing"))
	if acik and _ortam == null:
		_ortam = AudioStreamPlayer.new()
		var st: AudioStreamOggVorbis = load(ORTAM_DONGU)
		st.loop = true
		_ortam.stream = st
		_ortam.bus = &"Ortam"
		_ortam.volume_db = -60.0
		add_child(_ortam)
		_ortam.play()
		_olay = AudioStreamPlayer3D.new()
		_olay.bus = &"Ortam"
		_olay.unit_size = 10.0
		_olay.max_distance = 70.0
		_olay.volume_db = -3.0
		w.add_child(_olay)  # 3B dünyada (bu düğüm Node; konum için Node3D ebeveyn gerekir)
	if _ortam == null:
		return
	# yumuşak açılıp kapanma
	_ortam.volume_db = move_toward(_ortam.volume_db, ORTAM_DB if acik else -60.0, delta * 20.0)
	if not acik:
		if _ortam.volume_db <= -59.0 and _ortam.playing:
			_ortam.stop()
			_olay.stop()
		return
	if not _ortam.playing:
		_ortam.play()
	_olay_t -= delta
	if _olay_t > 0.0:
		return
	_olay_t = randf_range(8.0, 20.0)
	_ortam_olay(w)


func _ortam_olay(w: Node) -> void:
	var pl = w.get("player")
	if not (pl is Node3D) or not is_instance_valid(_olay):
		return
	var me: Vector3 = (pl as Node3D).global_position
	var ad: String = ORTAM_OLAY[randi() % ORTAM_OLAY.size()]
	if ad == _son_olay:
		ad = ORTAM_OLAY[(ORTAM_OLAY.find(ad) + 1 + randi() % (ORTAM_OLAY.size() - 1)) % ORTAM_OLAY.size()]
	_son_olay = ad
	var pos: Vector3
	if bool(w.get("in_lobby")):
		# yemekhane: uzakta, rastgele bir yönde
		var a := randf() * TAU
		pos = me + Vector3(cos(a), 0.0, sin(a)) * randf_range(14.0, 22.0)
	else:
		# koridorun oyuncuya uzak olan ucu (ara sıra yakın uç)
		var uc := -KORIDOR_UC if me.z > 0.0 else KORIDOR_UC
		if randf() < 0.3:
			uc = -uc
		pos = Vector3(KORIDOR_X + randf_range(-1.2, 1.2), 0.0, uc)
	pos.y = randf_range(1.2, 2.4)
	_olay.global_position = pos
	_olay.stream = load("res://assets/ses/%s.ogg" % ad)
	_olay.pitch_scale = randf_range(0.93, 1.05)
	_olay.play()
