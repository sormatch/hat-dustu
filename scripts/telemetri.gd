# Çökme/hata raporu ve basit analitik: oyundaki betik hataları ve önemli olaylar (oturum, maç, kasa...)
# küçük paketler halinde sunucuya gider (POST /telemetri). Kişisel veri içermez; aynı hata tekrar yollanmaz.
# iOS'ta çökme (ör. bellek sınırı aşılınca sistemin uygulamayı kapatması) uygulama içinden yakalanamaz: bunun için
# "oturum açık" bayrağı tutulur (user://oturum.cfg). Uygulama ön plandayken bayrak açık, arka plana geçince ya da
# düzgün kapanınca kapalıdır. Açılışta bayrak açık kalmışsa önceki oturum ön plandayken kapanmıştır (çökme):
# "onceki_cokme" olayı son bellek ölçümü ve son olayla birlikte gönderilir. Her olayda bellek (MB) de gider.
extends Node

var SURUM: String = str(ProjectSettings.get_setting("application/config/version", "?"))  # tek kaynak: project.godot
const MAX_HATA := 25  # bir oturumda en fazla bu kadar farklı hata
const OTURUM := "user://oturum.cfg"
const OLCUM_ARALIK := 15.0  # son bellek ölçümünün diske yazılma aralığı (sn)

var server_url := ""  # ws(s):// adresi; http(s)'e çevrilir
var _queue: Array = []
var _seen := {}
var _errors := 0
var _http: HTTPRequest
var _busy := false
var _t := 0.0
var _olcum_t := 0.0
var _son_olay := ""
var _bas_ms := 0
var _tepe := [0.0, 0.0]  # bu oturumda görülen en yüksek [bellek, video belleği] MB
var _logger: Logger
static var son_ekran := ""  # çökme raporu için: en son açılan ekran (magaza, kasa, envanter, mac...)
static var _ben: Node


class Yakalayici extends Logger:
	var sink: Node

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		# başka bir iş parçacığından gelebilir: ana döngüye aktar
		sink.call_deferred("_add_error", "%s:%d %s %s %s" % [file.get_file(), line, function, code, rationale], error_type)

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bas_ms = Time.get_ticks_msec()
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void: _busy = false)
	_logger = Yakalayici.new()
	_logger.sink = self
	OS.add_logger(_logger)
	_ben = self
	_onceki_oturum()
	var mem := OS.get_memory_info()
	event("oturum", {"platform": OS.get_name(), "model": OS.get_model_name(), "dil": OS.get_locale_language(),
		"ram": int(float(mem.get("physical", -1)) / 1048576.0)})
	var cf := ConfigFile.new()
	cf.load(OTURUM)
	cf.set_value("o", "uyari", 0)
	cf.save(OTURUM)
	_bayrak(true)


func _exit_tree() -> void:
	# düzgün çıkış (menüye dönüşte sahne yeniden kurulur, oyun kapanır): çökme sayılmaz
	_bayrak(false)
	if _logger:
		OS.remove_logger(_logger)


# Önceki oturum ön plandayken kapandıysa (bayrak açık kaldıysa) bildir.
func _onceki_oturum() -> void:
	var cf := ConfigFile.new()
	if cf.load(OTURUM) != OK:
		return
	if bool(cf.get_value("o", "acik", false)):
		event("onceki_cokme", {"surum": str(cf.get_value("o", "surum", "")), "sure_sn": int(cf.get_value("o", "sure_sn", 0)),
			"son_olay": str(cf.get_value("o", "son_olay", "")), "son_ekran": str(cf.get_value("o", "son_ekran", "")), "bellek": float(cf.get_value("o", "bellek", 0.0)),
			"vram": float(cf.get_value("o", "vram", 0.0)), "tepe_bellek": float(cf.get_value("o", "tepe_bellek", 0.0)),
			"tepe_vram": float(cf.get_value("o", "tepe_vram", 0.0)), "uyari": int(cf.get_value("o", "uyari", 0))})


func _bayrak(acik: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(OTURUM)
	var m := bellek()
	_tepe = [maxf(_tepe[0], m[0]), maxf(_tepe[1], m[1])]
	cf.set_value("o", "acik", acik)
	cf.set_value("o", "surum", SURUM)
	cf.set_value("o", "sure_sn", (Time.get_ticks_msec() - _bas_ms) / 1000)
	cf.set_value("o", "son_olay", _son_olay)
	cf.set_value("o", "son_ekran", son_ekran)
	cf.set_value("o", "bellek", m[0])
	cf.set_value("o", "vram", m[1])
	cf.set_value("o", "tepe_bellek", _tepe[0])
	cf.set_value("o", "tepe_vram", _tepe[1])
	cf.save(OTURUM)


# [statik bellek MB, video belleği MB] (bir ondalık)
static func bellek() -> Array:
	return [snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1)]


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			# arka plana geçti: sistem burada kapatırsa çökme sayılmaz
			_bayrak(false)
			preload("res://scripts/thumbs.gd").bosalt()
		NOTIFICATION_APPLICATION_RESUMED:
			_bayrak(true)
		NOTIFICATION_WM_CLOSE_REQUEST:
			_bayrak(false)
		NOTIFICATION_OS_MEMORY_WARNING:
			# sistem bellek az diyor: önbellekler boşalır (gerekince yeniden üretilir)
			var once := bellek()
			bellek_bosalt()
			event("bellek_uyarisi", {"once": once})
			var cf := ConfigFile.new()
			if cf.load(OTURUM) == OK:
				cf.set_value("o", "uyari", int(cf.get_value("o", "uyari", 0)) + 1)
				cf.save(OTURUM)


# Yeniden üretilebilen statik önbellekleri bırakır (kullanılanlar sahnedeki düğümlerde kalır, gerisi silinir).
static func bellek_bosalt() -> void:
	preload("res://scripts/thumbs.gd").bosalt()
	var ui: GDScript = load("res://scripts/ui.gd")
	(ui.get("_tex") as Dictionary).clear()
	var mb: GDScript = load("res://scripts/model_body.gd")
	for k in ["_mask_cache", "_merge_cache", "_ink"]:
		(mb.get(k) as Dictionary).clear()


func _add_error(msg: String, kind: int) -> void:
	var key := msg.left(160)
	if _seen.has(key) or _errors >= MAX_HATA:
		return
	_seen[key] = true
	_errors += 1
	_queue.append({"k": "hata", "m": msg.left(400), "tur": kind, "s": SURUM, "p": OS.get_name()})


# Analitik olay: ör. event("mac_basla", {"oyunlar": 7}). Her olaya o anki bellek eklenir: "mb": [bellek, vram].
func event(name: String, data := {}) -> void:
	_son_olay = name.left(32)
	if _queue.size() > 200:
		return
	var d: Dictionary = data.duplicate()
	d["mb"] = bellek()
	_queue.append({"k": name.left(32), "d": d, "s": SURUM, "p": OS.get_name()})


func _process(delta: float) -> void:
	_t += delta
	_olcum_t += delta
	if _olcum_t >= OLCUM_ARALIK:
		# son bellek ölçümü diske: çökerse bir sonraki açılışta bu değerler bildirilir
		_olcum_t = 0.0
		_bayrak(true)
	if _t < 10.0 or _busy or _queue.is_empty() or server_url == "":
		return
	_t = 0.0
	var base := server_url.replace("wss://", "https://").replace("ws://", "http://")
	var batch := _queue.slice(0, 40)
	_queue = _queue.slice(40)
	_busy = true
	var err := _http.request(base + "/telemetri", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"olaylar": batch}))
	if err != OK:
		_busy = false


# Ekran değişimi (çökme raporunda "son_ekran"): Telemetri.ekran("kasa"). Bayrak dosyası hemen güncellenir.
static func ekran(ad: String) -> void:
	son_ekran = ad
	if is_instance_valid(_ben) and _ben.is_inside_tree():
		_ben._bayrak(true)
