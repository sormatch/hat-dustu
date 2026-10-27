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
signal lines_changed  # telefonda olanlar değişti (busy_ids)
signal voice(data: PackedByteArray)
signal emote(id: int, name: String)
signal game_state(d: Dictionary)
signal game_secret(d: Dictionary)
signal game_result(d: Dictionary)
signal game_over(d: Dictionary)
signal info(text: String)
signal notice(kind: String, id: int, text: String)  # oyuncu bildirimi (bag: koptu, geri, ayrildi, katildi, cikti, sahip)
signal written(kind: String)
signal devre_event(d: Dictionary)
signal devre_status(d: Dictionary)
signal mode_event(d: Dictionary)
signal reconnecting(left: float)  # oyun sırasında bağlantı koptu, yeniden deneniyor (kalan süre)
signal rejoined  # koptuktan sonra aynı oyuncu olarak maça geri dönüldü
signal lobby_back  # maç sonu ekranından aynı odanın bekleme salonuna dönüldü (TEKRAR OYNA ya da süre doldu)
signal public_countdown(seconds: int)  # Hızlı Oyun odası: oyun kaç saniye sonra başlıyor  # yeni oyunların anlık olayları (rulet atışı, bomba devri...)

const Dil := preload("res://scripts/dil.gd")
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
var busy_ids: Array = []  # şu an telefonda olan (konuşan, arayan ya da çalan) oyuncular; Kim Kim?'de takma numara
var _ping_t := 0.0
var ping_ms := -1  # son ölçülen gidiş-dönüş süresi (ms); -1 bilinmiyor
var _ping_bekle := -1.0  # cevabı beklenen "ping"in üstünden geçen süre (sn); -1 bekleyen yok
const PING_ARALIK := 4.0  # sunucu "ping"e kendiliğinden "pong" der (Durable Object uyanmaz)
var _was_open := false
var _connecting := false
var _got_error := false
var in_game := false  # oyun başladıysa kopunca otomatik yeniden bağlanılır
var account_token := ""  # hesap anahtarı: maç ödülleri hesaba işlensin
const OYUN_SURUMU := 3  # yeni mini oyun eklenince bir artır (sunucu: modes/<oyun>.js surum)
var rejoin_token := ""  # sunucunun verdiği geri dönüş anahtarı (aynı oyuncu olarak geri girmek için)
var _player_name := ""
var _retry_left := 0.0  # yeniden bağlanma için kalan süre (sn)
var _retry_t := 0.0
const REJOIN_SECONDS := 45.0
# Kurulan odanın ayarı (sunucunun {t:"oda_ayar"} mesajı): {gor: "herkes"|"arkadas", max, ad, botla}. Hızlı Oyun'da boş.
var oda_ayar := {}
var _oda_demo := false  # test pozu: oda_demo= verildi (ayar silinmez)
signal room_settings_changed


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("server="):
			server_url = a.substr(7)
		elif a.begins_with("oda_demo="):
			# test pozu (lobi): oda_demo=herkes:6:1:Gece%20Kulübü -> görünürlük:kişi:botla:ad
			_oda_demo = true
			var p := a.substr(9).split(":")
			oda_ayar = {"gor": p[0], "max": int(p[1]) if p.size() > 1 else 8, "botla": p.size() > 2 and p[2] == "1", "ad": p[3].uri_decode() if p.size() > 3 else ""}


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
	# hesap anahtarı başlıkta (engellediğin oyuncularla aynı odaya düşmemek için; adres çubuğunda değil)
	var basliklar: PackedStringArray = ["X-Hesap: " + account_token] if account_token != "" else []
	if _quick_http.request(base + "/hizli", basliklar) != OK:
		failed.emit("Sunucuya bağlanılamadı. İnternetini kontrol et.")
		return
	var res: Array = await _quick_http.request_completed
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8()) if int(res[1]) == 200 else null
	if int(res[1]) == 429:
		failed.emit("Çok hızlı denedin, biraz bekle.")
		return
	if int(res[1]) == 403:
		failed.emit("Oynamak için hesap aç ya da giriş yap.")  # misafir oynayamaz
		return
	if typeof(d) != TYPE_DICTIONARY or str(d.get("kod", "")).length() != 4:
		failed.emit("Oyun bulunamadı, tekrar dene.")
		return
	join(str(d.kod), player_name, false, "", true)


## ayar: ODA KUR penceresinin seçimleri {gor, max, oda_ad, botla} (yalnız create); liste: ODALAR listesinden katılma
## (sunucu yalnız lobideki "Herkes" odasına alır; Kim Kim? için "arkadaşının odası" sayılmaz).
func join(code: String, player_name: String, create: bool, rejoin := "", public := false, ayar := {}, liste := false) -> void:
	if rejoin == "":
		leave()
	else:
		ws.close()
	_player_name = player_name
	room_code = code.to_upper()
	_got_error = false
	_ping_bekle = -1.0
	ping_ms = -1
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	# kodla ya da davetle katılan: arkadaşının odasına gelmiştir (Kim Kim? sadece böyle odalarda)
	var url := "%s/oda/%s?ad=%s&kur=%d&davet=%d" % [server_url, room_code, player_name.uri_encode(), 1 if create else 0, 0 if create else 1]
	# sv: bu sürümün desteklediği oyunlar (2: Projektör Avı). Sunucu yeni oyunu yalnız herkes destekliyorsa seçer.
	url += "&sv=%d" % OYUN_SURUMU
	if rejoin != "":
		url += "&tekrar=" + rejoin.uri_encode()
	if public:
		url = url.replace("&davet=1", "&davet=0") + "&acik=1"
	if liste:
		url = url.replace("&davet=1", "&davet=0") + "&liste=1"
	if create and not ayar.is_empty():
		url += "&gor=%s&max=%d&botla=%d" % ["herkes" if str(ayar.get("gor", "")) == "herkes" else "arkadas", int(ayar.get("max", 8)), 1 if bool(ayar.get("botla", false)) else 0]
		if str(ayar.get("oda_ad", "")) != "":
			url += "&oda_ad=" + str(ayar.oda_ad).uri_encode()
	if account_token != "":
		url += "&hesap=" + account_token.uri_encode()
	url += "&dil=" + Dil.kod()  # odanın dili kurucunun dili olur (Kara Tahta kelimeleri vb.)
	var err := ws.connect_to_url(url)
	_connecting = err == OK
	if err != OK:
		failed.emit(tr("Sunucuya bağlanılamadı (%d).") % err)


func leave() -> void:
	if connected:
		ws.send_text(JSON.stringify({"t": "cik"}))  # bilerek çıkış: sunucu geri dönme yeri tutmasın
	in_game = false
	rejoin_token = ""
	_retry_left = 0.0
	if not _oda_demo:
		oda_ayar = {}  # yeni oda: ayarı sunucu yollar (Hızlı Oyun odasında yok)
	if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		ws.close()
	connected = false
	_was_open = false
	_connecting = false
	players.clear()
	busy_ids.clear()
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
		if _ping_bekle >= 0.0:
			_ping_bekle += delta
		if _ping_t > PING_ARALIK:
			_ping_t = 0.0
			if _ping_bekle < 0.0:
				_ping_bekle = 0.0
			ws.send_text("ping")
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				_on_text(pkt.get_string_from_utf8())
			else:
				voice.emit(pkt)
	elif st == WebSocketPeer.STATE_CLOSING:
		# sunucu hata yollayıp hemen kapattı (Oda dolu, maç başladı...): mesaj kapanırken okunur, kaybolmaz
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				_on_text(pkt.get_string_from_utf8())
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
		# sunucunun hata mesajı kapanmadan önce gelmiş olabilir (kapanırken okunduysa _got_error zaten true)
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				_on_text(pkt.get_string_from_utf8())
		var was_connected := connected
		connected = false
		_was_open = false
		_connecting = false
		var kod := ws.get_close_code()
		if kod == 4001 or kod == 4008:
			# 4001: bu hesapla başka cihazdan girildi, 4008: çok hızlı mesaj. Sunucu geri almaz; denemek boşuna.
			rejoin_token = ""
			_retry_left = 0.0
			in_game = false
			if not _got_error:
				failed.emit("Bu hesapla başka bir cihazdan odaya girildi." if kod == 4001 else "Çok hızlı mesaj gönderildi, bağlantı kesildi.")
			return
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


# Bağlantı kalitesi: 0 iyi, 1 zayıf (gecikme > 300 ms ya da cevap 3 sn gecikti), 2 kötü (> 800 ms / 6 sn cevapsız)
func baglanti_kalitesi() -> int:
	if not connected:
		return 0
	var ms := maxf(float(ping_ms), _ping_bekle * 1000.0)
	if ms > 800.0 or _ping_bekle > 6.0:
		return 2
	if ms > 300.0 or _ping_bekle > 3.0:
		return 1
	return 0


func _on_text(s: String) -> void:
	if s == "pong":
		if _ping_bekle >= 0.0:
			ping_ms = int(_ping_bekle * 1000.0)
			_ping_bekle = -1.0
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
			if d.has("bag"):
				notice.emit(str(d.bag), int(d.get("id", 0)), Dil.sunucu(d))
			else:
				info.emit(Dil.sunucu(d))
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
		"lobi":
			# maç bitti, oda bekleme salonuna döndü: aynı kimlik, hücre ve oda; sahiplik değişmiş olabilir
			my_id = int(d.get("id", my_id))
			my_cell = int(d.get("cell", my_cell))
			is_host = bool(d.get("host", is_host))
			players = d.get("players", players)
			in_game = false
			lobby_back.emit()
			players_changed.emit()
		"oda_ayar":
			# kurulan odanın ayarı (girişte ve oda sahibi değiştirince): lobideki oda bilgisi şeridi
			oda_ayar = {"gor": str(d.get("gor", "arkadas")), "max": int(d.get("max", 8)), "ad": str(d.get("ad", "")), "botla": bool(d.get("botla", false))}
			room_settings_changed.emit()
		"hata":
			_got_error = true
			failed.emit(Dil.sunucu(d))
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
		"mik":
			# bir oyuncu mikrofonunu kapattı / açtı (baş üstünde ve lobi kartında çizik mikrofon)
			for p in players:
				if int(p.id) == int(d.get("id", 0)):
					p["mk"] = bool(d.get("kapali", false))
			players_changed.emit()
		"mesgul":
			busy.emit()
		"hatlar":
			busy_ids.clear()
			for x in d.get("ids", []):
				busy_ids.append(int(x))
			lines_changed.emit()
