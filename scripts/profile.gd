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
var settings := {"hassasiyet": 1.0, "oyun_ses": 0.8, "konusma_ses": 1.0, "kalite": 1, "yuzen_joy": true}
var last_daily := ""
var token := ""  # cihazın gizli hesap anahtarı (arkadaş sistemi)
var _play_t := 0.0


func _ready() -> void:
	load_profile()


func load_profile() -> void:
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


func owns(category: String, id: String) -> bool:
	return Catalog.price(category, id) == 0 or owned.has(category + ":" + id)


func buy(category: String, id: String) -> bool:
	if owns(category, id):
		return true
	var p := Catalog.price(category, id)
	if gems < p:
		return false
	gems -= p
	owned.append(category + ":" + id)
	save()
	return true


func add_gems(n: int) -> void:
	gems += n
	save()


func daily_available() -> bool:
	return last_daily != Time.get_date_string_from_system()


func claim_daily() -> bool:
	if not daily_available():
		return false
	last_daily = Time.get_date_string_from_system()
	gems += DAILY_GEMS
	save()
	return true


# Oynanan her tam dakika için 2 elmas.
func tick_play(delta: float) -> void:
	_play_t += delta
	if _play_t >= 60.0:
		_play_t -= 60.0
		add_gems(2)
