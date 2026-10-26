# Oyuncunun kaydı: ad, görünüş, elmaslar, satın alınanlar ve ayarlar (telefonda saklanır).
extends Node

signal changed

const Catalog := preload("res://scripts/catalog.gd")
const PATH := "user://profil.cfg"

var path := PATH  # testte ikinci oyuncu için: -- profil=2
const START_GEMS := 9999  # test sürümü: herkese bol elmas
const DAILY_GEMS := 50

var player_name := ""
var look: Dictionary = Catalog.DEFAULT_LOOK.duplicate()
var gems := START_GEMS
var owned: Array = []  # "kategori:kimlik"
var settings := {"hassasiyet": 1.0, "oyun_ses": 0.8, "konusma_ses": 1.0, "kalite": 1, "yuzen_joy": true,
	"fov": 72.0, "bob": true, "titresim": true, "fps": false, "zil": 0, "bas_konus": false, "giris_soruldu": false,
	"dil": "", "kurallar": false, "kurallar_tarih": ""}  # dil: "" = cihaz diline göre (scripts/dil.gd), "tr" / "en" = oyuncunun seçtiği
var last_daily := ""
var daily_ready := false  # günlük ödül alınabilir mi (sunucu söyler)
var token := ""  # cihazın gizli hesap anahtarı (arkadaş sistemi)
var _play_t := 0.0


func _ready() -> void:
	load_profile()


# Yeni kurulumda grafik kalitesi cihaza göre: belleği 3,5 GB altı telefonlarda "Pil dostu" (gölge, parlama kapalı,
# 3D çözünürlük düşük). Ayarlardan değiştirilebilir; kayıtlı seçim her zaman öncelikli.
static func varsayilan_kalite() -> int:
	if OS.has_feature("mobile"):
		var ram := float(OS.get_memory_info().get("physical", -1))
		if ram > 0.0 and ram < 3.5 * 1073741824.0:
			return 0
	return 1


func load_profile() -> void:
	settings.kalite = varsayilan_kalite()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("profil="):
			path = "user://profil%s.cfg" % a.substr(7)
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		token = Crypto.new().generate_random_bytes(16).hex_encode()
		# eski sürümden kalan adı al
		var old := ConfigFile.new()
		if old.load("user://ayar.cfg") == OK:
			player_name = str(old.get_value("oyuncu", "ad", ""))
		look = Catalog.random_look()
		save()
		return
	player_name = str(cfg.get_value("oyuncu", "ad", ""))
	look = Catalog.sanitize(cfg.get_value("oyuncu", "gorunum", {}))
	gems = maxi(int(cfg.get_value("oyuncu", "elmas", START_GEMS)), START_GEMS)
	owned = cfg.get_value("oyuncu", "sahip", [])
	last_daily = str(cfg.get_value("oyuncu", "gunluk", ""))
	token = str(cfg.get_value("oyuncu", "anahtar", ""))
	if token == "":
		token = Crypto.new().generate_random_bytes(16).hex_encode()
		save()
	var s: Dictionary = cfg.get_value("oyuncu", "ayarlar", {})
	for k in s:
		if settings.has(k):
			settings[k] = s[k]


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("oyuncu", "ad", player_name)
	cfg.set_value("oyuncu", "gorunum", look)
	cfg.set_value("oyuncu", "elmas", gems)
	cfg.set_value("oyuncu", "sahip", owned)
	cfg.set_value("oyuncu", "gunluk", last_daily)
	cfg.set_value("oyuncu", "ayarlar", settings)
	cfg.set_value("oyuncu", "anahtar", token)
	cfg.save(path)
	changed.emit()


# Hesapta saklanan kısım (ayarlar telefonda kalır).
func to_cloud() -> Dictionary:
	return {"ad": player_name, "gorunum": look, "elmas": gems, "sahip": owned, "gunluk": last_daily}


func from_cloud(d: Dictionary) -> void:
	player_name = str(d.get("ad", player_name))
	look = Catalog.sanitize(d.get("gorunum", look))
	gems = maxi(int(d.get("elmas", gems)), START_GEMS)
	owned = d.get("sahip", owned)
	last_daily = str(d.get("gunluk", last_daily))
	save()


# Sunucudan gelen ekonomi: elmas ve eşyalar telefonda sadece gösterim için tutulur.
func apply_economy(d: Dictionary) -> void:
	if d.has("elmas"):
		gems = int(d.elmas)
	if d.has("sahip"):
		owned = (d.sahip as Array).duplicate()
	daily_ready = bool(d.get("gunluk_hazir", false))
	save()
	changed.emit()


func owns(category: String, id: String) -> bool:
	return Catalog.price(category, id) == 0 or owned.has(category + ":" + id)


func buy(category: String, id: String, price_override := -1) -> bool:
	if owns(category, id):
		return true
	var p := Catalog.price(category, id) if price_override < 0 else price_override
	if gems < p:
		return false
	gems -= p
	owned.append(category + ":" + id)
	save()
	return true


# Sandıktan çıkan: bedava verilir.
func grant(category: String, id: String) -> void:
	if not owns(category, id):
		owned.append(category + ":" + id)
	save()


func add_gems(n: int) -> void:
	gems += n
	save()


func daily_available() -> bool:
	return daily_ready


# Günlük ödül sunucudan istenir (main.gd account'a iletir); sonuç ekonomi güncellemesiyle gelir.
signal daily_requested


func claim_daily() -> bool:
	if not daily_available():
		return false
	daily_ready = false
	daily_requested.emit()
	return true


# Oynanan her tam dakika için 2 elmas.
func tick_play(delta: float) -> void:
	_play_t += delta
	if _play_t >= 60.0:
		_play_t -= 60.0
		pass  # elmas artık maç sonunda sunucudan gelir
