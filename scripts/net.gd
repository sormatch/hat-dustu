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
signal game_state(d: Dictionary)
signal game_secret(d: Dictionary)
signal game_result(d: Dictionary)
signal game_over(d: Dictionary)
signal info(text: String)
signal written(kind: String)
signal devre_event(d: Dictionary)
signal devre_status(d: Dictionary)
signal mode_event(d: Dictionary)
signal reconnecting(left: float)  # oyun sırasında bağlantı koptu, yeniden deneniyor (kalan süre)
signal rejoined  # koptuktan sonra aynı oyuncu olarak maça geri dönüldü
signal public_countdown(seconds: int)  # Hızlı Oyun odası: oyun kaç saniye sonra başlıyor  # yeni oyunların anlık olayları (rulet atışı, bomba devri...)

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
var in_game := false  # oyun başladıysa kopunca otomatik yeniden bağlanılır
var account_token := ""  # hesap anahtarı: maç ödülleri hesaba işlensin
var rejoin_token := ""  # sunucunun verdiği geri dönüş anahtarı (aynı oyuncu olarak geri girmek için)
var _player_name := ""
var _retry_left := 0.0  # yeniden bağlanma için kalan süre (sn)
var _retry_t := 0.0
const REJOIN_SECONDS := 45.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("server="):
			server_url = a.substr(7)


static func new_code() -> String:
	var s := ""
	for i in 4:
		s += CODE_CHARS[randi() % CODE_CHARS.length()]
	return s


var _quick_http: HTTPRequest


# Hızlı Oyun: sunucudan dolmamış açık bir oda kodu al ve gir (yoksa sunucu yenisini açar).
func quick_match(player_name: String) -> void:
	if not _quick_http:
		_quick_http = HTTPRequest.new()
		_quick_http.timeout = 10.0
		add_child(_quick_http)
	var base := server_url.replace("wss://", "https://").replace("ws://", "http://")
	if _quick_http.request(base + "/hizli") != OK:
		failed.emit("Sunucuya bağlanılamadı. İnternetini kontrol et.")
		return
	var res: Array = await _quick_http.request_completed
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8()) if int(res[1]) == 200 else null
	if typeof(d) != TYPE_DICTIONARY or str(d.get("kod", "")).length() != 4:
		failed.emit("Oyun bulunamadı, tekrar dene.")
		return
	join(str(d.kod), player_name, false, "", true)


func join(code: String, player_name: String, create: bool, rejoin := "", public := false) -> void:
	if rejoin == "":
		leave()
	else:
		ws.close()
	_player_name = player_name
	room_code = code.to_upper()
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	# kodla ya da davetle katılan: arkadaşının odasına gelmiştir (Kim Kim? sadece böyle odalarda)
	var url := "%s/oda/%s?ad=%s&kur=%d&davet=%d" % [server_url, room_code, player_name.uri_encode(), 1 if create else 0, 0 if create else 1]
	if rejoin != "":
		url += "&tekrar=" + rejoin.uri_encode()
	if public:
		url = url.replace("&davet=1", "&davet=0") + "&acik=1"
	if account_token != "":
		url += "&hesap=" + account_token.uri_encode()
	var err := ws.connect_to_url(url)
	_connecting = err == OK
	if err != OK:
		failed.emit("Sunucuya bağlanılamadı (%d)." % err)


func leave() -> void:
	if connected:
		ws.send_text(JSON.stringify({"t": "cik"}))  # bilerek çıkış: sunucu geri dönme yeri tutmasın
	in_game = false
	rejoin_token = ""
	_retry_left = 0.0
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
	if _retry_left > 0.0 and not connected:
		_retry_left -= delta
		_retry_t -= delta
		if _retry_left <= 0.0:
			_retry_left = 0.0
			in_game = false
			failed.emit("Bağlantı geri gelmedi. Oyundan düştün.")
		elif _retry_t <= 0.0 and not _connecting:
			_retry_t = 2.0
			reconnecting.emit(_retry_left)
			join(room_code, _player_name, false, rejoin_token)
	if st == WebSocketPeer.STATE_OPEN:
		pass
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
		if was_connected and in_game and rejoin_token != "":
			# oyun sürerken koptu: aynı oyuncu olarak geri girmeyi dene
			if _retry_left <= 0.0:
				_retry_left = REJOIN_SECONDS
			_retry_t = 1.0
			reconnecting.emit(_retry_left)
			return
		if _retry_left > 0.0:
			return  # yeniden deneme sürüyor; bu deneme olmadı, bir sonrakini bekle
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
		"oyun", "sonuc", "bitti":
			# JSON sayıları ondalıklı gelir; oyuncu kimliği listelerini tam sayıya çevir
			for k in ["players"]:
				if d.has(k):
					d[k] = d[k].map(func(x) -> int: return int(x))
			for k in ["winner", "writer"]:
				if d.has(k):
					d[k] = int(d[k])
			match str(d.t):
				"oyun":
					game_state.emit(d)
				"sonuc":
					game_result.emit(d)
				"bitti":
					in_game = false
					game_over.emit(d)
		"gizli":
			game_secret.emit(d)
		"bilgi":
			info.emit(str(d.get("m", "")))
		"karar_alindi":
			written.emit(str(d.get("ne", "")))
		"devre":
			devre_event.emit(d)
		"olay":
			mode_event.emit(d)
		"acik_oda":
			public_countdown.emit(int(d.get("baslama", 0)))
		"devre_durum":
			devre_status.emit(d)
		"hosgeldin":
			connected = true
			_connecting = false
			my_id = int(d.id)
			my_cell = int(d.cell)
			is_host = bool(d.host)
			players = d.players
			rejoin_token = str(d.get("tekrar", rejoin_token))
			if bool(d.get("geri", false)):
				_retry_left = 0.0
				rejoined.emit()
				return
			welcomed.emit()
			if bool(d.get("started", false)):
				in_game = true
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
			in_game = true
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
