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
signal moderation(kind: String, text: String)  # yönetici işlemi: "yasak" (hesap askıda) ya da "uyari"; text oyuncunun dilinde
signal name_reset(new_name: String)  # yönetici görünen adı sıfırladı ("OyuncuNNNN")
signal islem_sonuc(ok: bool, d: Dictionary)  # mağaza işlemi (islem()): set, seviye yolu, hediye, istek listesi; hata ise d.m
signal gift_received(d: Dictionary)  # arkadaştan hediye geldi: {handle, ad, kat, id}

const Dil := preload("res://scripts/dil.gd")

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
var room_game := false  # o odada maç başladı mı (arkadaşlar "MAÇTA" görür)

# Arka planda giden mesajlar: bağlı değilken sessizce düşer. Diğerlerinde oyuncuya "bağlı değilsin" denir.
const _SESSIZ := ["liste", "engeller", "durum", "profil_kaydet", "ekonomi", "liderlik"]


var eco := {}  # son ekonomi özeti
var engeller: Array = []  # engellediğin kullanıcı adları
var engeller_misafir: Array = []  # maçta engellediğin, kullanıcı adı olmayan oyuncular: [{k, ad}] (kaldırmak için k)
var yasak_metni := ""  # hesap askıdaysa sunucunun mesajı ("Hesabın ... tarihine kadar askıya alındı.")
var lider := {}  # son liderlik cevabı
var _pending_buy := false
var _islem := ""  # cevabı beklenen mağaza işleminin türü (ör. "set_alindi")
var eco_t := 0  # son ekonomi özetinin geldiği an (ms): vitrin geri sayımları buna göre işler


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


# Görünen ad kullanılabilir mi (sunucunun küfür süzgeci, server/src/suzgec.js)? cb.call(uygun: bool)
# Bağlı değilsek ya da 4 sn'de cevap gelmezse uygun sayılır: oda sunucusu adı yine süzer ("Oyuncu N" yapar).
var _ad_bekleyen := {}  # ad -> [Callable]


func ad_dene(ad: String, cb: Callable) -> void:
	var n := ad.strip_edges()
	if n == "" or not connected:
		cb.call(true)
		return
	if _ad_bekleyen.has(n):
		(_ad_bekleyen[n] as Array).append(cb)
		return
	_ad_bekleyen[n] = [cb]
	send({"t": "ad_kontrol", "ad": n})
	get_tree().create_timer(4.0).timeout.connect(func() -> void: _ad_sonuc(n, true))


func _ad_sonuc(n: String, uygun: bool) -> void:
	var cbs: Array = _ad_bekleyen.get(n, [])
	_ad_bekleyen.erase(n)
	for c in cbs:
		if (c as Callable).is_valid():
			(c as Callable).call(uygun)


# Görünen adı değiştir (arkadaşların yeni adı görür).
func change_name(display_name: String) -> void:
	if handle != "" and display_name.strip_edges() != "":
		send({"t": "ad", "ad": display_name.strip_edges()})


# Çıkış: cihaz yeni boş bir anahtar alır (hesap sunucuda durur, tekrar giriş yapılabilir).
func sign_out() -> void:
	_switch(Crypto.new().generate_random_bytes(16).hex_encode())


# Mağazadan satın alma (sunucu elması düşer, eşyayı verir); sonuç purchase_result ile gelir.
# fiyat: telefonda görülen fiyat; sunucuda fiyat bundan yüksekse (vitrin yenilendi) almaz.
func buy(category: String, id: String, deal := false, fiyat := -1) -> void:
	_pending_buy = true
	var d := {"t": "satin_al", "kat": category, "id": id, "firsat": deal}
	if fiyat >= 0:
		d["fiyat"] = fiyat
	send(d)


# Mağaza işlemi (market.js): cevap türü gelince islem_sonuc(true, d), hata gelirse islem_sonuc(false, {m}).
func islem(d: Dictionary, cevap: String) -> void:
	_islem = cevap
	send(d)


# Vitrin geri sayımı: sunucunun söylediği kalan saniyeden, özet geldiğinden beri geçen süre düşülür.
func kalan_sn(alan: String) -> int:
	var v: Dictionary = eco.get("vitrin", {})
	if not v.has(alan):
		return -1
	return maxi(0, int(v[alan]) - (Time.get_ticks_msec() - eco_t) / 1000)


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


# Bulunduğun oda (boş = odada değil) ve maçın başlayıp başlamadığı; arkadaşların listesinde görünür.
func set_room(code: String, in_game := false) -> void:
	room = code
	room_game = in_game and code != ""
	send({"t": "durum", "oda": code, "oyun": room_game})


func online_count() -> int:
	var n := 0
	for f in friends:
		if f.online:
			n += 1
	return n


# Sahne yenilenince (ör. maçtan ana menüye dönüş) eski bağlantı hemen kapansın;
# yoksa sunucu bir süre eski oda durumunu (MAÇTA) göstermeye devam edebilir.
func _exit_tree() -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.close(1000, "cikis")
		ws.poll()


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
					send({"t": "durum", "oda": room, "oyun": room_game})  # koptuktan sonra arkadaşlar yine odada görsün
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
			if _retry > (60.0 if yasak_metni != "" else 5.0):
				_retry = 0.0
				_connect()


func _on(d) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		return
	match str(d.get("t", "")):
		"ben":
			yasak_metni = ""  # bağlantı kabul edildi: askı yok (ya da bitti)
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
			eco_t = Time.get_ticks_msec()
			economy_changed.emit()
		"set_alindi", "yol_alindi", "hediye_gitti", "istek_tamam":
			if _islem == str(d.t):
				_islem = ""
				islem_sonuc.emit(true, d)
		"hediye_geldi":
			gift_received.emit(d)
		"kasa_sonuc":
			chest_result.emit(d)
		"liderlik":
			lider = d
			leaderboard.emit(d)
		"engeller":
			engeller = (d.get("liste", []) as Array).duplicate()
			engeller_misafir = (d.get("misafir", []) as Array).duplicate()
			blocks_changed.emit()
		"yasak":
			var ilk := yasak_metni == ""
			yasak_metni = Dil.sunucu(d)
			if ilk:
				moderation.emit("yasak", yasak_metni)
		"uyari":
			moderation.emit("uyari", Dil.sunucu(d))
		"ad_sifirlandi":
			name_reset.emit(str(d.get("ad", "")))
		"hesap_silindi":
			account_deleted.emit()
		"ad_kontrol":
			_ad_sonuc(str(d.get("ad", "")).strip_edges(), bool(d.get("ok", true)))
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
				purchase_result.emit(false, Dil.sunucu(d))
				return
			if _islem != "" and str(d.t) == "hata":
				_islem = ""
				islem_sonuc.emit(false, {"m": Dil.sunucu(d)})
				return
			son_hata = str(d.t) == "hata"
			message.emit(Dil.sunucu(d))
