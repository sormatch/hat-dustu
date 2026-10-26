# Çökme/hata raporu ve basit analitik: oyundaki betik hataları ve önemli olaylar (oturum, maç, kasa...)
# küçük paketler halinde sunucuya gider (POST /telemetri). Kişisel veri içermez; aynı hata tekrar yollanmaz.
extends Node

var SURUM: String = str(ProjectSettings.get_setting("application/config/version", "?"))  # tek kaynak: project.godot
const MAX_HATA := 25  # bir oturumda en fazla bu kadar farklı hata

var server_url := ""  # ws(s):// adresi; http(s)'e çevrilir
var _queue: Array = []
var _seen := {}
var _errors := 0
var _http: HTTPRequest
var _busy := false
var _t := 0.0
var _logger: Logger


class Yakalayici extends Logger:
	var sink: Node

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		# başka bir iş parçacığından gelebilir: ana döngüye aktar
		sink.call_deferred("_add_error", "%s:%d %s %s %s" % [file.get_file(), line, function, code, rationale], error_type)

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void: _busy = false)
	_logger = Yakalayici.new()
	_logger.sink = self
	OS.add_logger(_logger)
	event("oturum", {"platform": OS.get_name(), "model": OS.get_model_name(), "dil": OS.get_locale_language()})


func _exit_tree() -> void:
	if _logger:
		OS.remove_logger(_logger)


func _add_error(msg: String, kind: int) -> void:
	var key := msg.left(160)
	if _seen.has(key) or _errors >= MAX_HATA:
		return
	_seen[key] = true
	_errors += 1
	_queue.append({"k": "hata", "m": msg.left(400), "tur": kind, "s": SURUM, "p": OS.get_name()})


# Analitik olay: ör. event("mac_basla", {"oyunlar": 7})
func event(name: String, data := {}) -> void:
	if _queue.size() > 200:
		return
	_queue.append({"k": name.left(32), "d": data, "s": SURUM, "p": OS.get_name()})


func _process(delta: float) -> void:
	_t += delta
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
