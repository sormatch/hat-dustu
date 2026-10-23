# Oda sunucusuyla bağlantı: oda kurma/katılma, oyuncu listesi, konum, kapı, arama ve ses.
extends Node

signal welcomed
signal players_changed
signal started
signal failed(message: String)
signal remote_state(id: int, data: Dictionary)
signal player_left(id: int)
signal door(cell: int, open: bool)
signal ringing(from_id: int)
signal ring_cell(cell: int, on: bool)
signal call_connected(with_id: int)
signal call_ended
signal busy
signal voice(data: PackedByteArray)
signal emote(id: int, name: String)

const DEFAULT_SERVER := "wss://hat-dustu.hatdustu.workers.dev"
const CODE_CHARS := "ABCDEFGHJKLMNPRSTUVYZ23456789"

var server_url := DEFAULT_SERVER
var ws := WebSocketPeer.new()
var connected := false
var my_id := 0
var my_cell := 0
var is_host := false
var room_code := ""
var players: Array = []  # [{id, name, cell, host}]
var _ping_t := 0.0
var _was_open := false
var _connecting := false
var _got_error := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("server="):
			server_url = a.substr(7)


static func new_code() -> String:
	var s := ""
	for i in 4:
		s += CODE_CHARS[randi() % CODE_CHARS.length()]
	return s


func join(code: String, player_name: String, create: bool) -> void:
	leave()
	room_code = code.to_upper()
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	var url := "%s/oda/%s?ad=%s&kur=%d" % [server_url, room_code, player_name.uri_encode(), 1 if create else 0]
	var err := ws.connect_to_url(url)
	_connecting = err == OK
	if err != OK:
		failed.emit("Sunucuya bağlanılamadı (%d)." % err)


func leave() -> void:
	if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		ws.close()
	connected = false
	_was_open = false
	_connecting = false
	players.clear()
	my_id = 0


func player_name(id: int) -> String:
	for p in players:
		if int(p.id) == id:
			return p.name
	return "?"


func send(d: Dictionary) -> void:
	if connected:
		ws.send_text(JSON.stringify(d))


func send_voice(data: PackedByteArray) -> void:
	if connected:
		ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)


func _process(delta: float) -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		_was_open = true
		_ping_t += delta
		if _ping_t > 20.0:
			_ping_t = 0.0
			ws.send_text("ping")
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				_on_text(pkt.get_string_from_utf8())
			else:
				voice.emit(pkt)
	elif st == WebSocketPeer.STATE_CLOSED and (_was_open or connected or _connecting):
		# sunucunun hata mesajı kapanmadan önce gelmiş olabilir
		_got_error = false
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				_on_text(pkt.get_string_from_utf8())
		var was_connected := connected
		connected = false
		_was_open = false
		_connecting = false
		if was_connected:
			failed.emit("Sunucuyla bağlantı koptu.")
		elif not _got_error:
			if ws.get_close_code() == 4000:
				failed.emit("Oda bulunamadı ya da dolu. Kodu kontrol et.")
			else:
				failed.emit("Sunucuya bağlanılamadı. İnternetini kontrol et.")


func _on_text(s: String) -> void:
	if s == "pong":
		return
	var d = JSON.parse_string(s)
	if typeof(d) != TYPE_DICTIONARY:
		return
	match str(d.get("t", "")):
		"hosgeldin":
			connected = true
			_connecting = false
			my_id = int(d.id)
			my_cell = int(d.cell)
			is_host = bool(d.host)
			players = d.players
			welcomed.emit()
			if bool(d.get("started", false)):
				started.emit()
		"hata":
			_got_error = true
			failed.emit(str(d.m))
		"oyuncular":
			players = d.players
			for p in players:
				if int(p.id) == my_id:
					is_host = bool(p.host)
			players_changed.emit()
		"basladi":
			started.emit()
		"konum":
			remote_state.emit(int(d.id), d)
		"ayrildi":
			player_left.emit(int(d.id))
		"kapi":
			door.emit(int(d.cell), bool(d.open))
		"caliyor":
			ringing.emit(int(d.from))
		"zil":
			ring_cell.emit(int(d.cell), bool(d.on))
		"baglandi":
			call_connected.emit(int(d.with))
		"kapandi":
			call_ended.emit()
		"emote":
			emote.emit(int(d.id), str(d.e))
		"mesgul":
			busy.emit()
