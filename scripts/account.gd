# Hesap bağlantısı: @kullanıcıadı, arkadaşlar, istekler ve lobi davetleri (oyun açıkken hep bağlı).
extends Node

signal me_changed
signal list_changed
signal invited(handle: String, name: String, code: String)
signal request_received(handle: String)
signal message(text: String)

var server_url := ""
var token := ""
var handle := ""
var friends: Array = []   # [{handle, name, online, room}]
var incoming: Array = []
var outgoing: Array = []
var connected := false
var ws := WebSocketPeer.new()
var _retry := 0.0
var _ping := 0.0


func start(url: String, tok: String) -> void:
	server_url = url
	token = tok
	_connect()


func _connect() -> void:
	ws = WebSocketPeer.new()
	ws.connect_to_url("%s/hesap?token=%s" % [server_url, token])


func send(d: Dictionary) -> void:
	if connected:
		ws.send_text(JSON.stringify(d))


func register(new_handle: String, display_name: String) -> void:
	send({"t": "kayit", "handle": new_handle.strip_edges().trim_prefix("@").to_lower(), "ad": display_name})


func set_room(code: String) -> void:
	send({"t": "durum", "oda": code})


func online_count() -> int:
	var n := 0
	for f in friends:
		if f.online:
			n += 1
	return n


func _process(delta: float) -> void:
	if token == "":
		return
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			connected = true
			_ping += delta
			if _ping > 20.0:
				_ping = 0.0
				ws.send_text("ping")
			while ws.get_available_packet_count() > 0:
				var s := ws.get_packet().get_string_from_utf8()
				if s != "pong":
					_on(JSON.parse_string(s))
		WebSocketPeer.STATE_CLOSED:
			connected = false
			_retry += delta
			if _retry > 5.0:
				_retry = 0.0
				_connect()


func _on(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	match str(d.get("t", "")):
		"ben":
			handle = str(d.handle)
			me_changed.emit()
		"liste":
			friends = d.friends
			incoming = d.incoming
			outgoing = d.outgoing
			list_changed.emit()
		"istek_geldi":
			request_received.emit(str(d.handle))
		"davet_geldi":
			invited.emit(str(d.handle), str(d.name), str(d.oda))
		"hata", "bilgi":
			message.emit(str(d.m))
