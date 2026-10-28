# Gerçek uygulama içi satın alma (tüketilebilir elmas paketleri).
#   iOS:     GodotApplePlugins StoreKit 2 (addons/GodotApplePluginsStoreKit, GDExtension; yalnız iPhone derlemesinde
#            .github/workflows/iphone.yml indirir). Sınıf: StoreKitManager / StoreProduct / StoreTransaction.
#   Android: GodotGooglePlayBilling (addons/GodotGooglePlayBilling, yalnız "Android Play" ön ayarında, Gradle ile).
#   Masaüstü / eklenti yok: platform = "" -> mağazada paketler "YAKINDA" kalır, oyun bozulmaz.
# Akış: ürünleri sorgula (yerel fiyat metni) -> satin_al(kimlik) -> mağaza ödemeyi alır -> imzalı makbuz
# (iOS: StoreKit 2 JWS, Android: originalJson + signature) sunucuya {t:"elmas_paketi", platform, paket, islem, makbuz}
# -> sunucu doğrularsa elmas verir ("elmas_alindi") ya da işlem zaten işlenmişse "odeme_tamam" -> ANCAK O ZAMAN işlem
# bitirilir (iOS finish, Android consume). Reddedilen ("odeme_red") işlem bitirilmez; uygulama yeniden açılınca mağaza
# yarım kalan işlemleri yeniden verir (iOS Transaction.unfinished, Android queryPurchases) ve yeniden sunucuya gider.
# Tek örnek: Odeme.al(get_tree()) -> /root/Odeme (sahne yenilense de yaşar; main.gd her açılışta baglan(account) der).
# Test (masaüstü ekran görüntüsü): komut satırında odeme_demo=hazir -> sahte fiyatlarla "satılabilir" görünür,
# satın alma mağaza aşamasında bekler (bekleme göstergesi). Hiçbir istek gönderilmez.
extends Node

# durum: satın alma akışındaki gelişme (mağaza ekranı dinler)
#   "sunucu"   mağaza ödemeyi aldı, sunucu doğruluyor
#   "iptal"    oyuncu vazgeçti          "bekliyor" ödeme onay bekliyor (ör. aile onayı / bekleyen ödeme)
#   "hata"     mağaza hatası (mesaj)     "red"      sunucu makbuzu doğrulayamadı (mesaj)
#   "zaten"    bu işlem daha önce işlenmiş (elmaslar önceden eklenmiş)
signal durum(kod: String, mesaj: String)
signal fiyatlar_geldi  # mağazanın yerel fiyat metinleri geldi (vitrin yeniden çizilir)

const Dil := preload("res://scripts/dil.gd")
const URUNLER := ["baslangic", "elmas_100", "elmas_550", "elmas_1200", "elmas_2500", "elmas_6500"]
const YENIDEN_GONDER := 20.0  # sunucu cevap vermezse makbuz bu kadar saniyede bir yeniden gider
const GP_TEKRAR_BAGLAN := 15.0  # Google Play bağlantısı koparsa yeniden deneme
# StoreKitManager.StoreKitStatus
const SK_OK := 0
const SK_KULLANICI_IPTAL := 4
const SK_BEKLIYOR := 5
const SK_DOGRULANMADI := 3
# Google Play BillingResponseCode / Purchase.PurchaseState (eklentinin BillingClient.gd'si ile aynı)
const GP_OK := 0
const GP_IPTAL := 1
const GP_ZATEN_SAHIP := 7
const GP_SATIN_ALINDI := 1
const GP_BEKLIYOR := 2

var platform := ""  # "ios" | "android" | "demo" | "" (satın alma yok)
var hazir := false  # mağaza bağlı ve ürünler geldi
var fiyatlar := {}  # kimlik -> mağazanın yerel fiyat metni ("₺179,99")
var magaza_acik := false  # elmas mağazası ekranı açık mı (kapalıyken arka planda gelen elmas için bildirim)
var account: Node = null
var aktif := ""  # şu an satın alınan ürün ("" yok)

var _sk: RefCounted = null  # iOS StoreKitManager
var _sk_urun := {}  # kimlik -> StoreProduct
var _gp: Object = null  # Android GodotGooglePlayBilling tekili
var _gp_bekle := 0.0
# Sunucuya gidecek / cevabı beklenen işlemler: anahtar ("ios:<id>" / "android:<token>") ->
# {paket, mesaj (sunucuya giden), nesne (iOS StoreTransaction) / token (Android), son (son gönderim, sn), red}
var _islemler := {}
var _saat := 0.0


static func al(agac: SceneTree) -> Node:
	var n := agac.root.get_node_or_null("Odeme")
	if n == null:
		n = load("res://scripts/odeme.gd").new()
		n.name = "Odeme"
		agac.root.add_child.call_deferred(n)
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("odeme_demo="):
			_demo_kur()
			return
	if OS.get_name() == "iOS" and ClassDB.class_exists("StoreKitManager"):
		_ios_kur()
	elif OS.get_name() == "Android" and Engine.has_singleton("GodotGooglePlayBilling"):
		_android_kur()


# main.gd her açılışta (sahne yenilenince yeni hesap bağlantısı) çağırır
func baglan(acc: Node) -> void:
	account = acc
	if acc == null:
		return
	if not acc.gem_purchased.is_connected(_sunucu_elmas):
		acc.gem_purchased.connect(_sunucu_elmas)
	if acc.has_signal("odeme_cevap") and not acc.odeme_cevap.is_connected(_sunucu_cevap):
		acc.odeme_cevap.connect(_sunucu_cevap)
	# yeni bağlantı: reddedilmiş olanlar dahil bekleyenler yeniden denensin
	for k in _islemler:
		_islemler[k].son = -1000.0
		_islemler[k].red = false


# Bu platformda gerçek satın alma yapılabilir mi (eklenti hazır, ürünler geldi, sunucu bu mağazayı doğruluyor)
func satilabilir() -> bool:
	if platform == "demo":
		return true
	if platform == "" or not hazir or account == null:
		return false
	var eco: Variant = account.get("eco")
	if typeof(eco) != TYPE_DICTIONARY:
		return false
	var od: Variant = (eco as Dictionary).get("odeme", {})
	return typeof(od) == TYPE_DICTIONARY and bool((od as Dictionary).get(platform, false))


func fiyat_metni(kimlik: String) -> String:
	return str(fiyatlar.get(kimlik, ""))


func magaza_adi() -> String:
	return "Google Play" if platform == "android" or OS.get_name() == "Android" else "App Store"


# Satın almayı başlatır. false: başlatılamadı (durum "hata" sinyali de gelir)
func satin_al(kimlik: String) -> bool:
	if aktif != "":
		durum.emit("hata", Dil.t("Önceki alım işleniyor."))
		return false
	if not satilabilir():
		durum.emit("hata", Dil.t("Mağaza şu an kapalı."))
		return false
	aktif = kimlik
	match platform:
		"demo":
			return true  # ekran görüntüsü: mağaza aşamasında bekler
		"ios":
			var p: RefCounted = _sk_urun.get(kimlik)
			if p == null:
				return _hata_bitir(Dil.t("Bu paket mağazada bulunamadı."))
			_sk.call("purchase", p)
			return true
		"android":
			var r: Variant = _gp.call("purchase", kimlik, "", "", false)
			var kod := int((r as Dictionary).get("response_code", -1)) if typeof(r) == TYPE_DICTIONARY else -1
			if kod != GP_OK:
				if kod == GP_ZATEN_SAHIP:
					_gp.call("queryPurchases", "inapp", false)  # bitirilmemiş eski satın alma: önce o teslim edilir
				return _hata_bitir(Dil.t("Ödeme ekranı açılamadı. Tekrar dene."))
			return true
	aktif = ""
	return false


var _bagliydi := false


# Mağaza ekranı bekleme süresini aştı: bu satın alma "aktif" sayılmasın (işlem gelirse yine teslim edilir)
func aktif_birak() -> void:
	aktif = ""


func _hata_bitir(m: String) -> bool:
	aktif = ""
	durum.emit("hata", m)
	return false


func _process(delta: float) -> void:
	_saat += delta
	if _gp != null and not hazir and _gp_bekle > 0.0:
		_gp_bekle -= delta
		if _gp_bekle <= 0.0:
			_gp.call("startConnection")
	var bagli := account != null and is_instance_valid(account) and bool(account.get("connected"))
	if bagli and not _bagliydi:
		for k in _islemler:  # bağlantı yeniden kuruldu: geçici nedenle reddedilenler yeniden denensin
			_islemler[k].red = false
			_islemler[k].son = -1000.0
	_bagliydi = bagli
	if _islemler.is_empty() or not bagli:
		return
	for k in _islemler:
		var it: Dictionary = _islemler[k]
		if not bool(it.red) and _saat - float(it.son) >= YENIDEN_GONDER:
			it.son = _saat
			account.send(it.mesaj)


# ---------------------------------------------------------------------
# Sunucu cevapları (account.gd: "elmas_alindi" -> gem_purchased, "odeme_tamam"/"odeme_red" -> odeme_cevap)
# ---------------------------------------------------------------------

func _sunucu_elmas(d: Dictionary) -> void:
	var k := str(d.get("istemci", ""))
	if k == "" or not _islemler.has(k):
		return
	var paket := str(_islemler[k].paket)
	_bitir(k)
	if paket == aktif or aktif == "":
		aktif = ""
	if not magaza_acik:
		# mağaza kapalıyken (ör. açılışta yarım kalan satın alma) teslim edildi
		preload("res://scripts/ui.gd").toast(Dil.t("+%s elmas") % preload("res://scripts/ekran.gd").sayi(int(d.get("elmas", 0))), null, 3.0, "basari")


func _sunucu_cevap(d: Dictionary) -> void:
	var k := str(d.get("istemci", ""))
	if k == "" or not _islemler.has(k):
		return
	var paket := str(_islemler[k].paket)
	var benim := paket == aktif
	if str(d.get("t", "")) == "odeme_tamam":
		_bitir(k)
		if benim:
			aktif = ""
			durum.emit("zaten", Dil.t("Bu alım zaten eklendi."))
	else:
		_islemler[k].red = true  # bu oturumda yeniden gönderilmez; bitirilmez (sonraki açılışta yeniden denenir)
		if benim:
			aktif = ""
			durum.emit("red", Dil.sunucu(d))


# Sunucu işlemi kabul etti (ya da zaten işlenmişti): mağazada da bitir
func _bitir(k: String) -> void:
	var it: Dictionary = _islemler[k]
	_islemler.erase(k)
	if it.has("nesne") and it.nesne != null:
		(it.nesne as Object).call("finish")
	elif it.has("token") and _gp != null:
		_gp.call("consumePurchase", str(it.token))


func _kuyruga(k: String, paket: String, mesaj: Dictionary, ek: Dictionary) -> void:
	if _islemler.has(k):
		if paket == aktif:
			durum.emit("sunucu", "")  # aynı işlem yeniden geldi: mağaza ekranı sunucuyu beklesin
		return
	var it := {"paket": paket, "mesaj": mesaj, "son": -1000.0, "red": false}
	it.merge(ek)
	_islemler[k] = it
	if paket == aktif:
		durum.emit("sunucu", "")


# ---------------------------------------------------------------------
# iOS: StoreKit 2 (GodotApplePlugins)
# ---------------------------------------------------------------------

func _ios_kur() -> void:
	_sk = ClassDB.instantiate("StoreKitManager")
	if _sk == null:
		return
	platform = "ios"
	_sk.connect("products_request_completed", _ios_urunler)
	_sk.connect("purchase_completed", _ios_satin_alindi)
	_sk.connect("transaction_updated", _ios_islem)
	_sk.connect("unverified_transaction_updated", func(_t: Variant, hata: int) -> void:
		push_warning("StoreKit: doğrulanamayan işlem (%d)" % hata))
	_sk.call("start")  # işlem dinleyicisi + bitirilmemiş işlemler (transaction_updated ile gelir)
	_sk.call("request_products", PackedStringArray(URUNLER))


func _ios_urunler(urunler: Array, kod: int) -> void:
	if kod != SK_OK:
		push_warning("StoreKit: ürünler alınamadı (%d)" % kod)
		get_tree().create_timer(30.0).timeout.connect(func() -> void: _sk.call("request_products", PackedStringArray(URUNLER)))
		return
	for p in urunler:
		if p == null:
			continue
		var id := str(p.get("product_id"))
		_sk_urun[id] = p
		fiyatlar[id] = str(p.get("display_price"))
	hazir = not _sk_urun.is_empty()
	fiyatlar_geldi.emit()


func _ios_satin_alindi(t: Variant, kod: int, mesaj: String) -> void:
	match kod:
		SK_OK:
			if t != null:
				_ios_islem(t)
			else:
				aktif = ""
				durum.emit("hata", Dil.t("Satın alma tamamlanamadı. Ödeme alınmadı."))
		SK_KULLANICI_IPTAL:
			aktif = ""
			durum.emit("iptal", Dil.t("Satın alma iptal edildi."))
		SK_BEKLIYOR:
			aktif = ""
			durum.emit("bekliyor", Dil.t("Ödeme onay bekliyor."))
		SK_DOGRULANMADI:
			aktif = ""
			durum.emit("hata", Dil.t("Apple bu satın almayı doğrulayamadı."))
		_:
			aktif = ""
			push_warning("StoreKit satın alma: %d %s" % [kod, mesaj])
			durum.emit("hata", Dil.t("Satın alma tamamlanamadı. Ödeme alınmadı."))


# Doğrulanmış (cihazda) işlem: satın alma sonucu, sonradan onaylanan ya da bitirilmemiş eski işlem
func _ios_islem(t: Variant) -> void:
	if t == null:
		return
	var paket := str(t.get("product_id"))
	var jws := str(t.get("jws_representation"))
	if float(t.get("revocation_date")) > 0.0 or jws == "" or not URUNLER.has(paket):
		if paket == aktif:
			aktif = ""
			durum.emit("hata", Dil.t("Satın alma tamamlanamadı. Ödeme alınmadı."))
		return
	var k := "ios:%d" % int(t.get("transaction_id"))
	_kuyruga(k, paket, {"t": "elmas_paketi", "platform": "ios", "paket": paket, "islem": k, "makbuz": jws}, {"nesne": t})


# ---------------------------------------------------------------------
# Android: Google Play Billing (GodotGooglePlayBilling 3.x)
# ---------------------------------------------------------------------

func _android_kur() -> void:
	_gp = Engine.get_singleton("GodotGooglePlayBilling")
	platform = "android"
	_gp.call("initPlugin")
	_gp.connect("connected", func() -> void:
		_gp.call("queryProductDetails", PackedStringArray(URUNLER), "inapp")
		_gp.call("queryPurchases", "inapp", false))
	_gp.connect("disconnected", func() -> void:
		hazir = false
		_gp_bekle = GP_TEKRAR_BAGLAN)
	_gp.connect("connect_error", func(kod: int, m: String) -> void:
		push_warning("Google Play bağlantısı: %d %s" % [kod, m])
		hazir = false
		_gp_bekle = GP_TEKRAR_BAGLAN * 2.0)
	_gp.connect("query_product_details_response", _gp_urunler)
	_gp.connect("query_purchases_response", func(r: Dictionary) -> void:
		if int(r.get("response_code", -1)) == GP_OK:
			for p in r.get("purchases", []):
				_gp_satin_alma(p as Dictionary, false))
	_gp.connect("on_purchase_updated", _gp_guncel)
	_gp.connect("consume_purchase_response", func(r: Dictionary) -> void:
		if int(r.get("response_code", -1)) != GP_OK:
			push_warning("Google Play consume: %s" % str(r)))
	_gp.call("startConnection")


func _gp_urunler(r: Dictionary) -> void:
	if int(r.get("response_code", -1)) != GP_OK:
		push_warning("Google Play ürünleri: %s" % str(r.get("debug_message", "")))
		_gp_bekle = GP_TEKRAR_BAGLAN * 2.0
		return
	for d in r.get("product_details", []):
		var urun := d as Dictionary
		var teklif: Variant = urun.get("one_time_purchase_offer_details_list")
		if teklif is Array and not (teklif as Array).is_empty():
			fiyatlar[str(urun.get("product_id", ""))] = str((teklif[0] as Dictionary).get("formatted_price", ""))
	hazir = not fiyatlar.is_empty()
	fiyatlar_geldi.emit()


func _gp_guncel(r: Dictionary) -> void:
	var kod := int(r.get("response_code", -1))
	if kod == GP_OK:
		for p in r.get("purchases", []):
			_gp_satin_alma(p as Dictionary, true)
		return
	aktif = ""
	if kod == GP_IPTAL:
		durum.emit("iptal", Dil.t("Satın alma iptal edildi."))
	elif kod == GP_ZATEN_SAHIP:
		_gp.call("queryPurchases", "inapp", false)
		durum.emit("hata", Dil.t("Önceki alım işleniyor."))
	else:
		push_warning("Google Play satın alma: %d %s" % [kod, str(r.get("debug_message", ""))])
		durum.emit("hata", Dil.t("Satın alma tamamlanamadı. Ödeme alınmadı."))


func _gp_satin_alma(p: Dictionary, yeni: bool) -> void:
	var urunler: Variant = p.get("product_ids", [])
	var paket := str(urunler[0]) if (urunler is Array or urunler is PackedStringArray) and urunler.size() > 0 else ""
	if not URUNLER.has(paket):
		return
	var st := int(p.get("purchase_state", 0))
	if st == GP_BEKLIYOR:
		if yeni and paket == aktif:
			aktif = ""
			durum.emit("bekliyor", Dil.t("Ödeme onay bekliyor."))
		return
	if st != GP_SATIN_ALINDI:
		return
	var tok := str(p.get("purchase_token", ""))
	var k := "android:" + tok
	_kuyruga(k, paket, {"t": "elmas_paketi", "platform": "android", "paket": paket, "islem": k,
		"makbuz": {"json": str(p.get("original_json", "")), "imza": str(p.get("signature", ""))}}, {"token": tok})


# ---------------------------------------------------------------------
# Test: sahte "hazır" mağaza (yalnız komut satırı odeme_demo=...)
# ---------------------------------------------------------------------

func _demo_kur() -> void:
	platform = "demo"
	hazir = true
	var tl := {"baslangic": 59.99, "elmas_100": 39.99, "elmas_550": 179.99, "elmas_1200": 349.99, "elmas_2500": 699.99, "elmas_6500": 1749.99}
	for k in tl:
		fiyatlar[k] = load("res://scripts/elmas_magaza.gd").tl(float(tl[k]))
