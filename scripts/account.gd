# Hesap bağlantısı: @kullanıcıadı, arkadaşlar, istekler ve lobi davetleri (oyun açıkken hep bağlı).
extends Node

signal me_changed
signal list_changed
signal invited(handle: String, name: String, code: String)
signal request_received(handle: String)
signal message(text: String)
signal token_changed(token: String)
signal economy_changed  # elmas, eşyalar, seviye, görevler (sunucudan)
signal reward(d: Dictionary)  # ödül: {elmas, neden} ya da maç ödülü {xp, elmas, seviye_atladi}
signal chest_result(d: Dictionary)  # kasa sonucu (sunucu belirler)
signal purchase_result(ok: bool, msg: String)
signal gem_purchased(d: Dictionary)  # elmas paketi alındı: {t:"elmas_alindi", paket, elmas (eklenen), toplam}; hata "message" ile gelir
signal leaderboard(d: Dictionary)  # haftalık liderlik: {liste:[{sira,ad,handle,puan,seviye}], benim_sira, benim_puan, hafta}
signal blocks_changed  # engellenen oyuncular listesi (engeller) güncellendi
signal account_deleted  # sunucu hesabı sildi (hesap_silindi)

var server_url := ""
var token := ""
var handle := ""
var has_account := false  # şifreli hesap (başka cihazdan giriş yapılabilir)
var remote_profile = null  # sunucudaki kayıt (görünüş, elmas, eşyalar) ya da null
var friends: Array = []   # [{handle, name, online, room}]
var incoming: Array = []
var outgoing: Array = []
var connected := false
var ws := WebSocketPeer.new()
var _retry := 0.0
var _ping := 0.0
var _conn_t := 0.0  # bağlanma / kapanma süresi (takılırsa yeniden denenir)
var _sessiz_t := 0.0  # sunucudan en son ne zaman bir şey geldi (internet sessizce koparsa anlamak için)
var son_hata := false  # son "message" bir hata mıydı (true) yoksa bilgi mi (false)
var room := ""  # bulunduğun oda kodu; bağlantı koparsa yeniden bağlanınca sunucuya tekrar bildirilir

# Arka planda giden mesajlar: bağlı değilken sessizce düşer. Diğerlerinde oyuncuya "bağlı değilsin" denir.
const _SESSIZ := ["liste", "engeller", "durum", "profil_kaydet", "ekonomi", "liderlik"]


var eco := {}  # son ekonomi özeti
var engeller: Array = []  # engellediğin kullanıcı adları
var lider := {}  # son liderlik cevabı
var _pending_buy := false


func start(url: String, tok: String) -> void:
	server_url = url
	token = tok
	_connect()


func _connect() -> void:
	if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		ws.close()
	connected = false
	_conn_t = 0.0
	ws = WebSocketPeer.new()
	ws.connect_to_url("%s/hesap?token=%s" % [server_url, token])


func send(d: Dictionary) -> void:
	if connected and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))
	elif not _SESSIZ.has(str(d.get("t", ""))):
		_on({"t": "hata", "m": "Sunucuya bağlı değilsin. İnternetini kontrol et."})


# Kullanıcı adını sunucunun beklediği biçime getirir: boşluksuz, @ işaretsiz, küçük harf.
static func clean_handle(s: String) -> String:
	return s.strip_edges().trim_prefix("@").strip_edges().to_lower()


# Kullanıcı adı kuralı (sunucudakiyle aynı). Uygunsa "", değilse kısa Türkçe hata.
static func handle_error(h: String) -> String:
	if h == "":
		return "Kullanıcı adını yaz."
	for ch in "çğıöşüâîû̇":
		if h.contains(ch):
			return "Kullanıcı adında Türkçe harf olamaz (ç, ğ, ı, ö, ş, ü)."
	if h.contains(" "):
		return "Kullanıcı adında boşluk olamaz."
	if h.length() < 3:
		return "Kullanıcı adı en az 3 karakter olmalı."
	if h.length() > 16:
		return "Kullanıcı adı en fazla 16 karakter olabilir."
	if not RegEx.create_from_string("^[a-z0-9_.]+$").search(h):
		return "Kullanıcı adında sadece harf, rakam, _ ve . olabilir."
	if not RegEx.create_from_string("[a-z0-9]").search(h):
		return "Kullanıcı adında en az bir harf ya da rakam olmalı."
	return ""


func register(new_handle: String, display_name: String) -> void:
	send({"t": "kayit", "handle": new_handle.strip_edges().trim_prefix("@").to_lower(), "ad": display_name})


func sign_up(new_handle: String, password: String, display_name: String) -> void:
	send({"t": "uye_ol", "handle": clean_handle(new_handle), "sifre": password, "ad": display_name})


func sign_in(user: String, password: String) -> void:
	send({"t": "giris", "handle": clean_handle(user), "sifre": password})


# Görünen adı değiştir (arkadaşların yeni adı görür).
func change_name(display_name: String) -> void:
	if handle != "" and display_name.strip_edges() != "":
		send({"t": "ad", "ad": display_name.strip_edges()})


# Çıkış: cihaz yeni boş bir anahtar alır (hesap sunucuda durur, tekrar giriş yapılabilir).
func sign_out() -> void:
	_switch(Crypto.new().generate_random_bytes(16).hex_encode())


# Mağazadan satın alma (sunucu elması düşer, eşyayı verir); sonuç purchase_result ile gelir.
func buy(category: String, id: String, deal := false) -> void:
	_pending_buy = true
	send({"t": "satin_al", "kat": category, "id": id, "firsat": deal})


func push_profile(p: Dictionary) -> void:
	if has_account:
		send({"t": "profil_kaydet", "p": p})


func _switch(tok: String) -> void:
	token = tok
	handle = ""
	has_account = false
	remote_profile = null
	friends = []
	incoming = []
	outgoing = []
	token_changed.emit(tok)
	me_changed.emit()
	_connect()


func set_room(code: String) -> void:
	room = code
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
			if not connected:
				connected = true
				_retry = 0.0
				_sessiz_t = 0.0
				_conn_t = 0.0
				if room != "":
					send({"t": "durum", "oda": room})  # koptuktan sonra arkadaşlar yine odada görsün
			_ping += delta
			_sessiz_t += delta
			if _ping > 20.0:
				_ping = 0.0
				ws.send_text("ping")
			while ws.get_available_packet_count() > 0:
				_sessiz_t = 0.0
				var s := ws.get_packet().get_string_from_utf8()
				if s != "pong":
					_on(JSON.parse_string(s))
			if _sessiz_t > 50.0:
				_connect()  # 20 sn'lik ping'lere cevap gelmiyor: bağlantı ölü, yenisini aç
		WebSocketPeer.STATE_CONNECTING:
			_conn_t += delta
			if _conn_t > 12.0:
				_connect()  # bağlanma takıldı: baştan dene
		WebSocketPeer.STATE_CLOSING:
			connected = false
			_conn_t += delta
			if _conn_t > 3.0:
				_connect()  # kapanma takıldı: beklemeden yeni bağlantı
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
			has_account = bool(d.get("hesap", false))
			remote_profile = d.get("profil")
			me_changed.emit()
		"giris_ok":
			_switch(str(d.token))
		"liste":
			friends = d.friends
			incoming = d.incoming
			outgoing = d.outgoing
			list_changed.emit()
		"istek_geldi":
			request_received.emit(str(d.handle))
		"davet_geldi":
			invited.emit(str(d.handle), str(d.name), str(d.oda))
		"ekonomi":
			eco = d
			economy_changed.emit()
		"kasa_sonuc":
			chest_result.emit(d)
		"liderlik":
			lider = d
			leaderboard.emit(d)
		"engeller":
			engeller = (d.get("liste", []) as Array).duplicate()
			blocks_changed.emit()
		"hesap_silindi":
			account_deleted.emit()
		"elmas_alindi":
			gem_purchased.emit(d)
		"satin_alindi":
			_pending_buy = false
			purchase_result.emit(true, "")
		"odul", "mac_odul":
			reward.emit(d)
		"hata", "bilgi":
			if _pending_buy and str(d.t) == "hata":
				_pending_buy = false
				purchase_result.emit(false, str(d.m))
				return
			son_hata = str(d.t) == "hata"
			message.emit(str(d.m))
