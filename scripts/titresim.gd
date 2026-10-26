# Kısa telefon titreşimleri (dokunsal geri bildirim). Çağıran betikte (projede class_name kullanılmıyor):
#   const Titresim := preload("res://scripts/titresim.gd")
#   Titresim.vur("hafif")  düğmeye basma, küçük vuruş (çok kısa, zayıf)
#   Titresim.vur("orta")   silah atışı uzakta, kasa sarsılması, elektrik
#   Titresim.vur("guclu")  vurulma, elinde patlama, kasa açılışı
#   Titresim.zil()         telefon çalıyor (iki uzun titreşim)
# Ayarlarda "Titreşim" kapalıysa (profile.settings.titresim == false) hiçbiri titretmez.
# Ayar, çalışan sahnenin (main.gd) profile.settings'inden okunur. Masaüstünde titreşim etkisizdir.
extends RefCounted

# tip: [süre ms, güç 0-1 (Android 8+ / iOS; eski cihaz yalnız süreyi kullanır)]
const TIPLER := {"hafif": [12, 0.25], "orta": [35, 0.55], "guclu": [90, 1.0]}
const ZIL_MS := 420
const ZIL_ARA := 0.75  # iki zil titreşimi arası (sn)

# Ayar sözlüğü (main.gd'nin profile.settings'i; aynı sözlük, ayar değişince kendiliğinden güncel).
# Atanmamışsa çalışan sahnenin "profile" düğümünden okunur.
static var ayarlar: Dictionary = {}
static var _son_ms := -1000
static var _son_guc := 0.0


static func acik() -> bool:
	var s := ayarlar
	if s.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		var sc: Node = tree.current_scene if tree else null
		if sc and "profile" in sc:
			var pr = sc.get("profile")
			if pr is Object and is_instance_valid(pr) and "settings" in pr:
				s = pr.settings
	return bool(s.get("titresim", true))


static func vur(tip := "hafif") -> void:
	var t: Array = TIPLER.get(tip, TIPLER.hafif)
	var simdi := Time.get_ticks_msec()
	# az önce daha güçlü bir titreşim başladıysa hafifi onu kesmesin
	if simdi - _son_ms < 60 and float(t[1]) < _son_guc:
		return
	if not acik():
		return
	_son_ms = simdi
	_son_guc = float(t[1])
	Input.vibrate_handheld(int(t[0]), float(t[1]))


# Telefon çalarken: iki uzun titreşim (gerçek telefon gibi).
static func zil() -> void:
	if not acik():
		return
	_son_ms = Time.get_ticks_msec()
	_son_guc = 1.0
	Input.vibrate_handheld(ZIL_MS, 0.8)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.create_timer(ZIL_ARA).timeout.connect(func() -> void:
			if acik():
				Input.vibrate_handheld(ZIL_MS, 0.8))
