# BÜYÜK KAÇIŞ (maçın son oyunu). Kurallar sunucuda: server/src/modes/kacis.js. Burada görüntü, ses ve etkileşim.
# Hücre: 10 gizli yer (yatak altı, yastık, raf, poster, havalandırma, gevşek tuğla, lavabo altı, koltuk, dolap, bilgisayar),
#   kaçış defteri (tarifler + ipucu), klozet (4 vida, kenara çekilir, altında toprak).
# Yer altı: 1 m'lik ızgarada kazılan kareler tek ağ olarak kurulur (toprak / kaya / beton temel / tuğla / ızgara duvarlar,
#   ahşap destekler); çakmak ışığı, fenerle güçlü ışık; kazarken yorulma; yön göstergesi (batı: temel ve tel örgü).
# Sayım: zil + gardiyan koridorda feneriyle hücrelere bakar; 15 sn içinde kendi hücrende ve klozet kapalı olmalı.
# Kaçış: tel örgünün ötesinde yukarı kazınca dışarı (gece, orman, arkada hapishane duvarı ve projektör); sonra izleyici.
extends "res://scripts/modlar/mod_ui.gd"

const Dunya := preload("res://scripts/dunya.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")
const Titresim := preload("res://scripts/titresim.gd")

# --- sunucuyla (kacis.js) aynı ---
const HUCRE_ARA := 6.6
const KLOZET := Vector2(1.5, -2.54)
const SINIR := {"x0": -24, "x1": 1, "z0": -27, "z1": 26}
const TEMEL_X := -9
const CIT_X := -19
const YUKARI := 3
const SURE := {"kasik": 6.5, "kurek": 2.6, "tugla": 9.0, "yukari_kasik": 7.0, "yukari_kurek": 3.0, "vida": 1.1, "ara": 0.9}
const TARIFLER := {"kurek": ["kasik", "tahta", "bant"], "fener": ["pil", "ampul", "tel"], "maymuncuk": ["tel", "catal"]}
const AD := {"caki": "Çakı", "kasik": "Kaşık", "tahta": "Tahta", "bant": "Bant", "pil": "Pil", "ampul": "Ampul", "tel": "Tel",
	"catal": "Çatal", "kurek": "Kürek", "fener": "Fener", "maymuncuk": "Maymuncuk"}
# gizli yerler: hücreye göre konum ve düğme yazısı
const YERLER := {
	"yatak": [Vector3(-1.05, 0.25, -1.95), "Yatağın altına bak"],
	"yastik": [Vector3(-1.5, 0.66, -2.6), "Yastığı yokla"],
	"kitaplik": [Vector3(-1.35, 1.0, 2.62), "Rafı karıştır"],
	"poster": [Vector3(-1.45, 1.75, -2.93), "Posterin arkasına bak"],
	"havalandirma": [Vector3(-0.75, 2.62, -2.93), "Havalandırma ızgarası"],
	"tugla": [Vector3(-0.25, 0.3, -2.95), "Gevşek tuğla"],
	"lavabo": [Vector3(1.5, 0.6, -2.62), "Lavabonun altına bak"],
	"koltuk": [Vector3(0.0, 0.5, -1.5), "Koltuğun minderini kaldır"],
	"dolap": [Vector3(-1.55, 1.0, -0.22), "Dolabı karıştır"],
	"bilgisayar": [Vector3(-1.5, 0.55, 1.05), "Bilgisayar kasasına bak"],
}
const DEFTER := Vector3(-1.35, 0.57, -1.25)  # yatağın üstünde
const TY := -2.35  # tünel tabanı
const TH := 1.35  # tünel yüksekliği

var _kazilan := {}  # "x,z" -> true
var _acik_izgara := {}
var _harita := {}  # {izgara: [z], tugla: [z], kaya: ["x,z"]}
var _kaya := {}
var _env: Array = []
var _ipucu := {}
var _vida := 0
var _klozet_acik := false
var _aranan := {}  # "hücre:yer" -> true
var _yer_alti := false
var _yorgunluk := 1.0  # 1 dinç, 0 bitkin
var _is := {}  # sürmekte olan eylem: {tur, t, sure, veri}
var _ceza_bitis := 0
var _sayim_bitis := 0
var _kactim := 0
var _kacanlar := {}
var _yukari_n := 0

var _tunel: Node3D
var _tunel_govde: StaticBody3D
var _malz := {}
var _cakmak: OmniLight3D
var _fener: SpotLight3D
var _env_eski := {}
var _ortam: AudioStreamPlayer
var _nefes: AudioStreamPlayer
var _ses_t := 0.0
var _gardiyan: Node3D
var _gardiyan_fener: SpotLight3D
var _defterler: Array = []
var _gizliler: Array = []
var _dis: Node3D  # kaçış sahnesi (dışarısı)
var _kam: Camera3D
var _izlenen := 0
var _izle_bakis := Vector2.ZERO
var _izle_bar: HBoxContainer
var _izle_ad: Label

# arayüz
var _esya_bar: HBoxContainer
var _ilerleme: ProgressBar
var _ilerleme_yazi: Label
var _yorgun_bar: ProgressBar
var _pusula: Label
var _sayim_yazi: Label
var _karanlik: ColorRect


func _ready() -> void:
	_esya_bar = HBoxContainer.new()
	_esya_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_esya_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_esya_bar.offset_top = 96
	_esya_bar.offset_right = -24
	_esya_bar.add_theme_constant_override("separation", 6)
	_esya_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root().add_child(_esya_bar)
	_ilerleme = ProgressBar.new()
	_ilerleme.set_anchors_preset(Control.PRESET_CENTER)
	_ilerleme.custom_minimum_size = Vector2(420, 22)
	_ilerleme.offset_left = -210
	_ilerleme.offset_right = 210
	_ilerleme.offset_top = 70
	_ilerleme.offset_bottom = 92
	_ilerleme.show_percentage = false
	_ilerleme.max_value = 1.0
	_ilerleme.visible = false
	var dolu := UI.flat(Color(1.0, 0.75, 0.3), Color(1, 0.85, 0.5), 8)
	var bos := UI.flat(Color(0.05, 0.04, 0.03, 0.8), Color(0.4, 0.3, 0.2), 8)
	_ilerleme.add_theme_stylebox_override("fill", dolu)
	_ilerleme.add_theme_stylebox_override("background", bos)
	root().add_child(_ilerleme)
	_ilerleme_yazi = UI.title("", UI.FS_ORTA, GOLD, true)
	_ilerleme_yazi.set_anchors_preset(Control.PRESET_CENTER)
	_ilerleme_yazi.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ilerleme_yazi.offset_top = 30
	_ilerleme_yazi.offset_bottom = 66
	_ilerleme_yazi.visible = false
	root().add_child(_ilerleme_yazi)
	_yorgun_bar = ProgressBar.new()
	_yorgun_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_yorgun_bar.custom_minimum_size = Vector2(260, 12)
	_yorgun_bar.offset_left = -130
	_yorgun_bar.offset_right = 130
	_yorgun_bar.offset_top = -40
	_yorgun_bar.offset_bottom = -28
	_yorgun_bar.show_percentage = false
	_yorgun_bar.max_value = 1.0
	_yorgun_bar.add_theme_stylebox_override("fill", UI.flat(Color(0.45, 0.85, 0.5), Color(0.6, 1, 0.6), 6))
	_yorgun_bar.add_theme_stylebox_override("background", UI.flat(Color(0.05, 0.05, 0.05, 0.7), Color(0.3, 0.3, 0.3), 6))
	_yorgun_bar.visible = false
	root().add_child(_yorgun_bar)
	_pusula = UI.title("", UI.FS_KUCUK + 4, Color(0.95, 0.9, 0.75), true)
	_pusula.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pusula.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pusula.offset_top = 132
	_pusula.offset_bottom = 164
	_pusula.visible = false
	root().add_child(_pusula)
	_sayim_yazi = UI.title("", UI.FS_DEV, RED, true)
	_sayim_yazi.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sayim_yazi.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sayim_yazi.offset_top = 170
	_sayim_yazi.offset_bottom = 260
	_sayim_yazi.visible = false
	root().add_child(_sayim_yazi)
	_karanlik = ColorRect.new()
	_karanlik.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_karanlik.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float k = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.25, 0.8, d) * k);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_karanlik.material = mat
	root().add_child(_karanlik)
	root().move_child(_karanlik, 0)


# ---------- yardımcılar ----------

static func hucre_z(k: int) -> float:
	return (k - 3.5) * HUCRE_ARA


static func klozet_kare(cell: int) -> Vector2i:
	return Vector2i(floori(KLOZET.x), floori(hucre_z(cell) + KLOZET.y))


static func anahtar(x: int, z: int) -> String:
	return "%d,%d" % [x, z]


func kare(x: int, z: int) -> String:
	if x == TEMEL_X:
		if z in _harita.get("izgara", []):
			return "" if _acik_izgara.has(anahtar(x, z)) else "izgara"
		if z in _harita.get("tugla", []):
			return "tugla"
		return "temel"
	if _kaya.has(anahtar(x, z)):
		return "kaya"
	return ""


func _hucrem() -> int:
	return int(w.my_cell)


func _oyuncu_hucresi(id: int) -> int:
	return int(w._player_entry(id).get("cell", -1))


func _kazili(x: int, z: int) -> bool:
	return _kazilan.has(anahtar(x, z))


func _ben_kare() -> Vector2i:
	var p: Vector3 = w.player.global_position
	return Vector2i(floori(p.x), floori(p.z))


func _sesc(ad: String, db := 0.0) -> void:
	play("kacis/" + ad, db)


func _ses3d(ad: String, pos: Vector3, db: float, unit := 4.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = load("res://assets/ses/%s.ogg" % ad)
	p.volume_db = db
	p.unit_size = unit
	p.max_distance = 40.0
	p.bus = &"Efekt"
	w.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _gardiyan_sesi(ad: String) -> void:
	var p := "res://assets/ses/%s/%s.ogg" % ["gardiyan" if Dil.tr_mi() else "gardiyan_en", ad]
	if not ResourceLoader.exists(p):
		p = "res://assets/ses/gardiyan/%s.ogg" % ad
	if not ResourceLoader.exists(p):
		return
	var a := AudioStreamPlayer.new()
	a.stream = load(p)
	a.bus = &"Efekt"
	add_child(a)
	a.finished.connect(a.queue_free)
	a.play()


func _toast(t: String) -> void:
	if w.hud and w.hud.has_method("show_toast"):
		w.hud.show_toast(t)


# ---------- sunucudan ----------

func on_state(d: Dictionary, entered: bool) -> void:
	state = d
	if d.has("harita"):
		_harita = d.harita
		_kaya.clear()
		for k in _harita.get("kaya", []):
			_kaya[str(k)] = true
	for k in d.get("kazilan", []):
		_kazilan[str(k)] = true
	for k in d.get("acik_izgara", []):
		_acik_izgara[str(k)] = true
	for id in d.get("kacan", []):
		_kacanlar[int(id)] = true
	# kimin klozeti açık (geri dönen / geç gelen de görsün)
	var kl = d.get("klozet", {})
	if kl is Dictionary:
		for k in kl:
			var c := _oyuncu_hucresi(int(k))
			if c >= 0 and c < w.cells.size():
				w.cells[c].klozet_ac(bool(kl[k]), false)
	if not entered:
		return
	_tunel_hazirla()
	_tunel_kur()
	match phase():
		"anons":
			_gece(true)
			_gardiyan_sesi("kacis_basla")
			g.get_tree().create_timer(1.0).timeout.connect(show_card)
			_esyalari_goster()
			_defterleri_koy()
			_gizli_kur()
		"kacis":
			close_card()
			_defterleri_koy()
			_gizli_kur()
			_gece(true)
			if int(d.get("sayim", -1)) > 0:
				_sayim_uyari(int(d.sayim))


func on_secret(d: Dictionary) -> void:
	secret = d
	_durum_al(d)


func _durum_al(d: Dictionary) -> void:
	if d.has("env"):
		_env = d.env.duplicate()
		_esyalari_goster()
	if d.has("ipucu") and d.ipucu is Dictionary:
		_ipucu = d.ipucu
	if d.has("vida"):
		_vida = int(d.vida)
		if _hucrem() >= 0:
			w.cells[_hucrem()].klozet_vida(_vida)
	if d.has("klozet"):
		_klozet_acik = bool(d.klozet)
	if int(d.get("ceza", 0)) > 0:
		_ceza_bitis = Time.get_ticks_msec() + int(d.ceza)
	_fener_guncelle()


func on_event(d: Dictionary) -> void:
	match str(d.get("tur", "")):
		"coklu":
			for e in d.get("liste", []):
				on_event(e)
		"durum":
			_durum_al(d)
			if d.has("yapildi"):
				flash(tr("%s YAPTIN!") % up(tr(AD.get(str(d.yapildi), ""))), "", GREEN, 1.6)
				_sesc("vida_dus", -2.0)
			if d.has("aldi"):
				flash(tr("%s ALDIN") % up(tr(AD.get(str(d.aldi), ""))), pname(int(d.get("kimden", 0))), GOLD, 1.4)
		"red":
			_toast(Dil.sunucu(d, "m"))
			play("hata", -6.0)
		"bos":
			_aranan["%d:%s" % [int(d.hucre), str(d.yer)]] = true
			_toast(tr("Burada bir şey yok."))
		"buldu":
			_aranan["%d:%s" % [int(d.hucre), str(d.yer)]] = true
			_durum_al(d)
			flash(tr("%s BULDUN!") % up(tr(AD.get(str(d.esya), ""))), "", GOLD, 1.6)
			play("odul", -4.0)
		"vida":
			var c := _oyuncu_hucresi(int(d.id))
			if c >= 0 and c < w.cells.size():
				w.cells[c].klozet_vida(int(d.n))
				_ses3d("kacis/vida_dus", w.cells[c].klozet_world(), -4.0, 2.0)
		"klozet":
			var c := int(d.get("hucre", -1))
			if c >= 0 and c < w.cells.size():
				w.cells[c].klozet_ac(bool(d.acik))
				_ses3d("kacis/klozet_cek", w.cells[c].klozet_world(), 0.0, 4.0)
			var kk: Array = d.get("kare", [])
			if bool(d.acik) and kk.size() == 2:
				_kazilan[anahtar(int(kk[0]), int(kk[1]))] = true
				_tunel_kur()
		"kazildi":
			var kk: Array = d.kare
			_kazilan[anahtar(int(kk[0]), int(kk[1]))] = true
			if str(d.get("ne", "")) == "izgara":
				_acik_izgara[anahtar(int(kk[0]), int(kk[1]))] = true
			_tunel_kur()
			var pos := Vector3(float(kk[0]) + 0.5, TY + 0.6, float(kk[1]) + 0.5)
			if int(d.id) == me():
				_sesc("toprak_dokul", -2.0)
				if str(d.get("ne", "")) == "tugla":
					_sesc("tugla", 0.0)
				elif str(d.get("ne", "")) == "izgara":
					play("projektor/parmaklik_1", 0.0)
			elif w.player.global_position.distance_to(pos) < 25.0:
				_ses3d("kacis/kurek_%d" % randi_range(1, 4), pos, -4.0, 3.0)
		"sert":
			var ne := str(d.get("ne", ""))
			_sesc("kaya_%d" % randi_range(1, 2), 0.0)
			w._shake(0.25, 0.03)
			match ne:
				"kaya":
					flash("KAYA!", "Kazılmıyor, etrafından dolaş.", UI.AMBER, 1.8)
				"temel":
					flash("BETON TEMEL!", "Buradan geçilmez. Eski ızgarayı ya da gevşek tuğlayı bul.", UI.AMBER, 2.4)
				"izgara":
					flash("ESKİ DEMİR IZGARA", "Maymuncukla açılır.", UI.AMBER, 2.2)
				"tugla":
					flash("GEVŞEK TUĞLALAR", "Kürekle kazılır (yavaş).", UI.AMBER, 2.2)
		"yukari":
			_yukari_n = int(d.n)
			_sesc("tas_toprak", 0.0)
			w._shake(0.3, 0.04)
			flash(tr("YUKARI KAZ: %d/%d") % [_yukari_n, YUKARI], "Toprak dökülüyor, az kaldı!", GOLD, 1.4)
		"toprak":
			var kk: Array = d.kare
			_ses3d("kacis/tas_toprak", Vector3(float(kk[0]) + 0.5, TY + 1.0, float(kk[1]) + 0.5), -4.0, 3.0)
		"kacti":
			_kacanlar[int(d.id)] = true
			if int(d.id) == me():
				_kactim = int(d.sira)
				_kacis_sahnesi(d.get("kare", []))
			else:
				flash(tr("%s KAÇTI!") % up(pname(int(d.id))), tr("%d. kaçan") % int(d.sira), RED, 2.0)
				_gardiyan_sesi("kacak_var")
				_sesc("sayim_zili", -10.0)
				if w.remotes.has(int(d.id)):
					(w.remotes[int(d.id)].root as Node3D).visible = false
		"sayim_uyari":
			_sayim_uyari(int(d.get("ms", 15000)))
		"sayim":
			_sayim(d.get("yakalanan", []))


func show_card() -> void:
	if phase() != "anons":
		return
	role_card("BÜYÜK KAÇIŞ!", GOLD, "Hücrende gizli yerleri ara, kaçış defterindeki tariflerle alet yap. Çakıyla klozetin 4 vidasını sök, kaşıkla kaz. Hapishanenin beton temelini geç, tel örgünün ötesinde yukarı kaz. Sayımda hücrende ol! Ne kadar erken kaçarsan o kadar çok puan.")


func banner() -> Array:
	return [str(state.get("title", "")), tr("Kaçan: %d") % _kacanlar.size()]


func help_rows() -> Array:
	return [["kilit", "Klozeti sök, altını kaz"], ["envanter", "Gizli yerleri ara, alet yap"], ["kapi", "Sayımda hücrende ol"]]


func doors_open() -> bool:
	return false


# Yer altındayken (ya da kaçınca) yalnız bu oyunun düğmeleri (koltuk, kapı, telefon yok)
func sadece_kendi() -> bool:
	return _yer_alti or _kactim > 0


func on_result(d: Dictionary) -> void:
	_eylem_bitir()
	var kacan: Array = d.get("kacan_ad", [])
	var head := tr("KİMSE KAÇAMADI")
	if _kactim > 0:
		head = tr("%d. KAÇAN SENSİN!") % _kactim
	elif not kacan.is_empty():
		head = tr("%d KİŞİ KAÇTI") % kacan.size()
	var satir := []
	for i in mini(kacan.size(), 4):
		satir.append("%d. %s" % [i + 1, str(kacan[i])])
	result_modal(head, GREEN if _kactim > 0 else RED, satir, d, [], 1 if _kactim > 0 else -1)
	g.get_tree().create_timer(2.0).timeout.connect(_eve_don)


func cleanup() -> void:
	_eve_don()
	for n in [_esya_bar, _ilerleme, _ilerleme_yazi, _yorgun_bar, _pusula, _sayim_yazi, _karanlik]:
		if is_instance_valid(n):
			(n as Node).queue_free()


# ---------- hedefler (main.gd eylem düğmesi) ----------

func targets(cell: int) -> Array:
	var out := []
	if phase() != "kacis" or _kactim > 0 or not _is.is_empty():
		return out
	var p: CharacterBody3D = w.player
	var cam: Camera3D = p.camera
	var on := cam.global_position - cam.global_transform.basis.z * 0.6
	if _yer_alti:
		var k := _ben_kare()
		# kuyunun altındaysan yukarı çık (açık klozeti olan herhangi bir hücre)
		var ust := _kuyu_hucresi(k)
		if ust >= 0:
			out.append(["cik", on + Vector3(0, 0.15, 0), 3.0, tr("Yukarı çık")])
		if k.x <= CIT_X and _kazili(k.x, k.y):
			out.append(["yukari", on, 3.0, tr("Yukarı kaz (%d/%d)") % [_yukari_n, YUKARI]])
		var yon := _yon()
		var hedef := k + yon
		if not _kazili(hedef.x, hedef.y) and hedef.x >= SINIR.x0 and hedef.x <= SINIR.x1 and hedef.y >= SINIR.z0 and hedef.y <= SINIR.z1:
			var yuz := Vector3(k.x + 0.5 + yon.x * 0.45, TY + 0.75, k.y + 0.5 + yon.y * 0.45)
			out.append(["kaz", yuz, 2.2, _kaz_yazisi(hedef)])
		return out
	if cell < 0 or cell >= w.cells.size():
		return out
	var c: Node3D = w.cells[cell]
	# gizli yerler (bulunduğun hücrede)
	for y in YERLER:
		if _aranan.has("%d:%s" % [cell, y]):
			continue
		out.append(["ara:" + y, c.to_global(YERLER[y][0]), 1.9, tr(YERLER[y][1])])
	if cell == _hucrem():
		out.append(["defter", c.to_global(DEFTER), 2.0, tr("Kaçış defteri")])
		if _vida < 4:
			var yazi := tr("Vidayı sök (%d/4)") % _vida if "caki" in _env else tr("Vidalar sıkı (çakı lazım)")
			out.append(["vida", c.klozet_world(), 1.8, yazi])
		elif not c.klozet_acik:
			out.append(["klozet_ac", c.klozet_world(), 1.8, tr("Klozeti kenara çek")])
		else:
			out.append(["klozet_kapa", c.klozet.global_position + Vector3(0, 0.3, 0), 1.8, tr("Klozeti yerine koy")])
	if c.klozet_acik:
		out.append(["in:%d" % cell, c.klozet_delik.global_position + Vector3(0, 0.1, 0), 1.8, tr("Aşağı in")])
	return out


func _kaz_yazisi(h: Vector2i) -> String:
	var aletim := "Kürekle kaz" if "kurek" in _env else ("Kaşıkla kaz" if "kasik" in _env else "Kaz (alet yok)")
	match kare(h.x, h.y):
		"kaya":
			return tr("Kaya")
		"temel":
			return tr("Beton temel")
		"izgara":
			return tr("Izgarayı aç (maymuncuk)") if "maymuncuk" in _env else tr("Demir ızgara")
		"tugla":
			return tr("Tuğlaları kaz (kürek)")
	return tr(aletim)


# Kameranın baktığı ana yön (ızgarada): (±1, 0) ya da (0, ±1)
func _yon() -> Vector2i:
	var f: Vector3 = -w.player.camera.global_transform.basis.z
	if absf(f.x) > absf(f.z):
		return Vector2i(1 if f.x > 0 else -1, 0)
	return Vector2i(0, 1 if f.z > 0 else -1)


# Bu kare açık bir klozetin kuyusu mu? Dönen: hücre (yoksa -1)
func _kuyu_hucresi(k: Vector2i) -> int:
	for i in w.cells.size():
		if klozet_kare(i) == k and w.cells[i].klozet_acik:
			return i
	return -1


func do_action(name: String) -> void:
	if Time.get_ticks_msec() < _ceza_bitis:
		_toast(tr("Sayımda yakalandın, biraz bekle."))
		return
	if name.begins_with("ara:"):
		_eylem("ara", SURE.ara + 0.6, {"yer": name.substr(4)}, tr("Arıyorsun..."))
		play("dolap" if randf() < 0.5 else "kumas_%d" % randi_range(1, 3), -6.0)
		return
	if name.begins_with("in:"):
		_asagi_in(int(name.substr(3)))
		return
	match name:
		"defter":
			_defter_ac()
		"vida":
			if not "caki" in _env:
				_toast(tr("Vidaları sökmek için çakı lazım. Hücreni ara!"))
				return
			_eylem("vida", SURE.vida + 0.3, {}, tr("Vida sökülüyor..."))
			_sesc("vida", -2.0)
		"klozet_ac":
			net_karar({"klozet": true})
		"klozet_kapa":
			net_karar({"klozet": false})
		"cik":
			_yukari_cik(_kuyu_hucresi(_ben_kare()))
		"kaz":
			var hedef := _ben_kare() + _yon()
			var ne := kare(hedef.x, hedef.y)
			if not ("kasik" in _env or "kurek" in _env):
				_toast(tr("Kazmak için kaşık ya da kürek lazım."))
				return
			if ne in ["kaya", "temel"] or (ne == "izgara" and not "maymuncuk" in _env) or (ne == "tugla" and not "kurek" in _env):
				net_karar({"kaz": [hedef.x, hedef.y]})  # sunucu "sert" der: ses ve açıklama
				return
			var sure: float = SURE.tugla if ne == "tugla" else (SURE.kurek if "kurek" in _env else SURE.kasik)
			_eylem("kaz", sure * (1.0 + (1.0 - _yorgunluk) * 1.2), {"kare": [hedef.x, hedef.y]}, tr("Kazıyorsun..."))
		"yukari":
			var sure: float = SURE.yukari_kurek if "kurek" in _env else SURE.yukari_kasik
			var k := _ben_kare()
			_eylem("yukari", sure * (1.0 + (1.0 - _yorgunluk) * 1.2), {"kare": [k.x, k.y]}, tr("Yukarı kazıyorsun..."))


func net_karar(v: Dictionary) -> void:
	if g.net:
		g.decided.emit(v)


# Süren eylem: oyuncu kıpırdamaz, ilerleme çubuğu dolar, bitince sunucuya gider
func _eylem(tur: String, sure: float, veri: Dictionary, yazi: String) -> void:
	_is = {"tur": tur, "t": 0.0, "sure": sure, "veri": veri}
	w.player.busy = true
	_ilerleme.value = 0.0
	_ilerleme.visible = true
	_ilerleme_yazi.text = yazi
	_ilerleme_yazi.visible = true
	_ses_t = 0.0


func _eylem_bitir() -> void:
	_is = {}
	if w and w.player:
		w.player.busy = false
	if is_instance_valid(_ilerleme):
		_ilerleme.visible = false
		_ilerleme_yazi.visible = false


func _eylem_kare(delta: float) -> void:
	if _is.is_empty():
		return
	_is.t = float(_is.t) + delta
	_ilerleme.value = clampf(float(_is.t) / float(_is.sure), 0.0, 1.0)
	var tur: String = _is.tur
	if tur == "kaz" or tur == "yukari":
		# kazı sesi ve kamera sarsıntısı; yorgunluk düşer
		_ses_t -= delta
		if _ses_t <= 0.0:
			var kurek := "kurek" in _env
			_ses_t = randf_range(0.55, 0.75) if kurek else randf_range(0.4, 0.55)
			_sesc(("kurek_%d" % randi_range(1, 4)) if kurek else ("kasik_%d" % randi_range(1, 3)), -2.0)
			w._shake(0.12, 0.012)
		_yorgunluk = maxf(0.0, _yorgunluk - delta * (0.035 if "kurek" in _env else 0.05))
	if float(_is.t) >= float(_is.sure):
		var veri: Dictionary = _is.veri
		_eylem_bitir()
		match tur:
			"ara":
				net_karar({"ara": veri.yer})
			"vida":
				net_karar({"vida": true})
			"kaz":
				net_karar({"kaz": veri.kare})
			"yukari":
				net_karar({"yukari": veri.kare})


# ---------- her kare ----------

func process(delta: float) -> void:
	_eylem_kare(delta)
	if _yer_alti and _is.is_empty():
		_yorgunluk = minf(1.0, _yorgunluk + delta * 0.09)
	# yorgunluk göstergesi, ekran kararması, nefes
	if is_instance_valid(_yorgun_bar):
		_yorgun_bar.visible = _yer_alti
		_yorgun_bar.value = _yorgunluk
	var mat: ShaderMaterial = _karanlik.material if is_instance_valid(_karanlik) else null
	if mat:
		mat.set_shader_parameter("k", (0.75 - _yorgunluk) * 1.1 if _yer_alti and _yorgunluk < 0.75 else (0.35 if _yer_alti else 0.0))
	if _yer_alti and _yorgunluk < 0.35 and (not is_instance_valid(_nefes) or not _nefes.playing):
		if not is_instance_valid(_nefes):
			_nefes = AudioStreamPlayer.new()
			_nefes.bus = &"Efekt"
			add_child(_nefes)
		_nefes.stream = load("res://assets/ses/kacis/nefes.ogg")
		_nefes.volume_db = -6.0
		_nefes.play()
	# yer altında yön göstergesi: batı (temel ve tel örgü) nerede, ne kadar uzak
	if is_instance_valid(_pusula):
		_pusula.visible = _yer_alti
		if _yer_alti:
			_pusula.text = _pusula_yazisi()
	# sayım geri sayımı
	if _sayim_bitis > 0 and is_instance_valid(_sayim_yazi):
		var kalan := ceili(float(_sayim_bitis - Time.get_ticks_msec()) / 1000.0)
		if kalan > 0:
			var ek := ""
			if _yer_alti:
				var kk := klozet_kare(_hucrem())
				var d := Vector2(_ben_kare()).distance_to(Vector2(kk))
				ek = "\n" + tr("Kuyuna %d m") % int(d)
			_sayim_yazi.text = tr("SAYIM! %d") % kalan + ek
			_sayim_yazi.visible = true
		else:
			_sayim_yazi.visible = false
			_sayim_bitis = 0
	# düşen olursa (çarpışma kurulmadan) kuyuya geri
	if _yer_alti and w.player.global_position.y < TY - 2.0:
		var kk := klozet_kare(_hucrem())
		w.player.global_position = Vector3(kk.x + 0.5, TY + 0.05, kk.y + 0.5)
		w.player.velocity = Vector3.ZERO
	_gardiyan_kare(delta)
	if _kactim > 0:
		_kontroller(false)
		_izle_kare()


func _pusula_yazisi() -> String:
	var p: CharacterBody3D = w.player
	var f: Vector3 = -p.camera.global_transform.basis.z
	var sag: Vector3 = p.camera.global_transform.basis.x
	var bati := Vector3(-1, 0, 0)
	var ok := "↑"
	var fd := f.dot(bati)
	var rd := sag.dot(bati)
	if absf(rd) > absf(fd):
		ok = "→" if rd > 0 else "←"
	elif fd < 0:
		ok = "↓"
	var x := p.global_position.x
	var parca := []
	if x > TEMEL_X:
		parca.append(tr("Temel %d m") % int(x - TEMEL_X))
	if x > CIT_X:
		parca.append(tr("Tel örgü %d m") % int(x - CIT_X))
	else:
		parca.append(tr("Tel örgüyü geçtin: YUKARI KAZ!"))
	return tr("BATI %s") % ok + "   " + "  ·  ".join(parca)


# ---------- hücreler: eşyalar, defter, gece ----------

func _esyalari_goster() -> void:
	if not is_instance_valid(_esya_bar):
		return
	for c in _esya_bar.get_children():
		c.queue_free()
	for e in _env:
		var pc := PanelContainer.new()
		var renk := Color(0.85, 0.6, 0.25) if e in TARIFLER else Color(0.55, 0.5, 0.42)
		pc.add_theme_stylebox_override("panel", UI.flat(Color(0.06, 0.05, 0.04, 0.85), renk, 10))
		var l := UI.title(up(tr(AD.get(str(e), str(e)))), UI.FS_KUCUK + 2, renk.lightened(0.3), true)
		pc.add_child(l)
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_esya_bar.add_child(pc)


# Her kullanılan hücrede yatağın üstünde kaçış defteri (küçük not defteri)
func _defterleri_koy() -> void:
	if not _defterler.is_empty():
		return
	for id in state.get("players", []):
		var c := _oyuncu_hucresi(int(id))
		if c < 0 or c >= w.cells.size():
			continue
		var d := Node3D.new()
		w.cells[c].add_child(d)
		d.position = DEFTER
		d.rotation.y = 0.3
		var kap := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.17, 0.02, 0.23)
		kap.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.45, 0.12, 0.08)
		m.roughness = 0.8
		kap.material_override = m
		d.add_child(kap)
		var sayfa := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.155, 0.012, 0.215)
		sayfa.mesh = sm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.86, 0.82, 0.7)
		sayfa.material_override = pm
		sayfa.position = Vector3(0.006, 0.012, 0)
		d.add_child(sayfa)
		_defterler.append(d)


func _gece(on: bool) -> void:
	var env: Environment = w.env
	if on:
		if _env_eski.is_empty():
			_env_eski = {"amb_e": env.ambient_light_energy, "fog_d": env.fog_density}
		_ortam_ayarla()
	elif not _env_eski.is_empty():
		env.ambient_light_energy = _env_eski.amb_e
		env.fog_density = _env_eski.fog_d
		_env_eski = {}


# Yer altında ortam ışığı neredeyse yok (çakmak ve fener yeter), yukarıda gece loşluğu
func _ortam_ayarla() -> void:
	if _env_eski.is_empty():
		return
	var env: Environment = w.env
	env.ambient_light_energy = 0.035 if _yer_alti else float(_env_eski.amb_e) * 0.75
	env.fog_density = 0.09 if _yer_alti else float(_env_eski.fog_d)


# Havalandırma ızgarası (arka duvarın üstü) ve gevşek tuğla (arka duvarın dibi, biraz dışarı çıkık, etrafı çatlak)
func _gizli_kur() -> void:
	if not _gizliler.is_empty():
		return
	var demir := StandardMaterial3D.new()
	demir.albedo_color = Color(0.32, 0.33, 0.33)
	demir.metallic = 0.6
	demir.roughness = 0.55
	var karanlik := StandardMaterial3D.new()
	karanlik.albedo_color = Color(0.02, 0.02, 0.02)
	var tugla: Material = w._pbr("broken_brick_wall", 0.35, 1.0, Color(0.8, 0.62, 0.55))
	for id in state.get("players", []):
		var c := _oyuncu_hucresi(int(id))
		if c < 0 or c >= w.cells.size():
			continue
		var kok := Node3D.new()
		w.cells[c].add_child(kok)
		_gizliler.append(kok)
		# havalandırma: koyu oyuk + çerçeve + yatay lameller + 4 vida
		var hv := Vector3(-0.75, 2.62, -2.99)
		_kutu_mi(kok, hv, Vector3(0.46, 0.3, 0.02), karanlik)
		for i in 4:
			var yy := -0.1 + i * 0.066
			var lm := _kutu_mi(kok, hv + Vector3(0, yy, 0.02), Vector3(0.42, 0.018, 0.03), demir)
			lm.rotation.x = -0.5
		for kx in [-1, 1]:
			_kutu_mi(kok, hv + Vector3(kx * 0.225, 0, 0.015), Vector3(0.025, 0.32, 0.03), demir)
		for ky in [-1, 1]:
			_kutu_mi(kok, hv + Vector3(0, ky * 0.15, 0.015), Vector3(0.47, 0.025, 0.03), demir)
		# gevşek tuğla: duvardan 2 cm çıkık, etrafında koyu derz boşluğu
		var tg := Vector3(-0.25, 0.3, -2.985)
		_kutu_mi(kok, tg, Vector3(0.27, 0.12, 0.02), karanlik)
		var t := _kutu_mi(kok, tg + Vector3(0.01, 0, 0.025), Vector3(0.24, 0.095, 0.06), tugla)
		t.rotation.z = 0.04


func _kutu_mi(kok: Node3D, p: Vector3, b: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = b
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	kok.add_child(mi)
	return mi


# ---------- defter (tarifler, ipucu, eşya verme) ----------

func _defter_ac() -> void:
	var m := chalk_modal(tr("KAÇIŞ DEFTERİ"), tr("Tarifler, ipucu ve eşyaların"), 1060.0)
	var kutu: VBoxContainer = m[1]
	for t in TARIFLER:
		var satir := HBoxContainer.new()
		satir.add_theme_constant_override("separation", 14)
		var parcalar: Array = TARIFLER[t]
		var yazi := "%s = %s" % [up(tr(AD[t])), " + ".join(parcalar.map(func(x) -> String: return up(tr(AD[x]))))]
		var l := chalk(yazi, 30)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		satir.add_child(l)
		var yapilir := true
		var env2 := _env.duplicate()
		for p in parcalar:
			if not p in env2:
				yapilir = false
				break
			env2.erase(p)
		var b := chalk_button(tr("YAP"), "onay", yapilir, 150.0, 60.0)
		b.disabled = not yapilir
		var tt: String = t
		b.pressed.connect(func() -> void:
			net_karar({"yap": tt})
			close_panel())
		satir.add_child(b)
		kutu.add_child(satir)
	var not1 := chalk(tr("KÜREK hızlı kazar · FENER tünelde görmeni sağlar · MAYMUNCUK temeldeki eski ızgarayı açar"), 22, Color(0.85, 0.85, 0.75))
	not1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kutu.add_child(not1)
	kutu.add_child(chalk(tr("İPUCU: %s") % _ipucu_yazisi(), 26, Color(1.0, 0.86, 0.5)))
	var yol := chalk(tr("Batıda (hücrelerin arka duvarı tarafı) beton temel, onun da ötesinde tel örgü var. Örgüyü geçince YUKARI kaz."), 22, Color(0.8, 0.85, 0.8))
	yol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kutu.add_child(yol)
	# yanındaki oyuncuya eşya ver
	var yakin := _yakindaki()
	if yakin != 0 and not _env.is_empty():
		var vr := HBoxContainer.new()
		vr.add_theme_constant_override("separation", 10)
		vr.add_child(chalk(tr("%s kişisine ver:") % pname(yakin), 24))
		for e in _env:
			var ee: String = e
			var vb := chalk_button(up(tr(AD.get(ee, ee))), "", false, 130.0, 52.0)
			vb.pressed.connect(func() -> void:
				net_karar({"ver": {"kime": yakin, "esya": ee}})
				close_panel())
			vr.add_child(vb)
		kutu.add_child(vr)
	chalk_sfx()


func _ipucu_yazisi() -> String:
	if _ipucu.is_empty():
		return tr("yok")
	var z := float(_ipucu.get("z", 0))
	var k := clampi(roundi(z / HUCRE_ARA + 3.5), 0, w.cells.size() - 1)
	var no: int = w.cells[k].number
	if str(_ipucu.get("tur", "")) == "izgara":
		return tr("Temeldeki eski demir ızgara %d numaralı hücrenin hizasında.") % no
	return tr("Temelde gevşek tuğlalar %d numaralı hücrenin hizasında.") % no


func _yakindaki() -> int:
	var p: Vector3 = w.player.global_position
	var en := 0
	var en_d := 2.6
	for id in w.remotes:
		if w.is_bot(int(id)) or _kacanlar.has(int(id)):
			continue
		var rp: Vector3 = (w.remotes[id].root as Node3D).global_position
		var d := rp.distance_to(p)
		if d < en_d:
			en_d = d
			en = int(id)
	return en


# ---------- yer altı: inme, çıkma ----------

func _asagi_in(cell: int) -> void:
	var kk := klozet_kare(cell)
	_kazilan[anahtar(kk.x, kk.y)] = true
	_tunel_kur()
	var p: CharacterBody3D = w.player
	_karart(0.25, func() -> void:
		p.global_position = Vector3(kk.x + 0.5, TY + 0.05, kk.y + 0.5)
		p.velocity = Vector3.ZERO
		if not p.crouched:
			p.toggle_crouch()
		_yer_alti_ol(true))
	_sesc("toprak_dokul", -4.0)


func _yukari_cik(cell: int) -> void:
	if cell < 0:
		return
	var p: CharacterBody3D = w.player
	var c: Node3D = w.cells[cell]
	_karart(0.25, func() -> void:
		if p.crouched:
			p.toggle_crouch()
		p.global_position = c.klozet_delik.global_position + Vector3(-0.7, 0.05, 0.6)
		p.velocity = Vector3.ZERO
		_yer_alti_ol(false, cell))


func _yer_alti_ol(on: bool, cell := -1) -> void:
	_yer_alti = on
	net_karar({"nerede": -1 if on else cell})
	_ortam_ayarla()
	_fener_guncelle()
	if on:
		if not is_instance_valid(_ortam):
			_ortam = AudioStreamPlayer.new()
			_ortam.stream = load("res://assets/ses/kacis/tunel_ortam.ogg")
			_ortam.bus = &"Efekt"
			_ortam.volume_db = -2.0
			add_child(_ortam)
			_ortam.finished.connect(_ortam.play)
		_ortam.play()
	elif is_instance_valid(_ortam):
		_ortam.stop()


func _fener_guncelle() -> void:
	var cam: Camera3D = w.player.camera if w and w.player else null
	if not cam:
		return
	if not is_instance_valid(_cakmak):
		_cakmak = OmniLight3D.new()
		_cakmak.light_color = Color(1.0, 0.74, 0.46)
		_cakmak.light_energy = 0.75
		_cakmak.omni_range = 3.4
		_cakmak.position = Vector3(0.18, -0.15, -0.25)
		cam.add_child(_cakmak)
		var tw := _cakmak.create_tween().set_loops()
		tw.tween_property(_cakmak, "light_energy", 0.62, 0.13)
		tw.tween_property(_cakmak, "light_energy", 0.8, 0.17)
	if not is_instance_valid(_fener):
		_fener = SpotLight3D.new()
		_fener.light_color = Color(0.95, 0.95, 1.0)
		_fener.light_energy = 4.0
		_fener.spot_range = 14.0
		_fener.spot_angle = 30.0
		_fener.position = Vector3(0.12, -0.1, 0)
		cam.add_child(_fener)
	_cakmak.visible = _yer_alti
	_fener.visible = _yer_alti and "fener" in _env


# ---------- tünel ağı (kazılan karelerden tek ağ) ----------

func _tunel_hazirla() -> void:
	if is_instance_valid(_tunel):
		return
	_tunel = Node3D.new()
	_tunel.name = "Tuneller"
	w.add_child(_tunel)
	_malz = {
		"zemin": w._pbr("dirt_floor", 0.55, 1.0, Color(0.62, 0.55, 0.48)),
		"toprak": w._pbr("excavated_soil_wall", 0.5, 1.0, Color(0.62, 0.6, 0.58)),
		"tavan": w._pbr("excavated_soil_wall", 0.6, 1.0, Color(0.42, 0.4, 0.38)),
		"kaya": w._pbr("rock_wall_08", 0.6, 1.0, Color(0.7, 0.7, 0.72)),
		"temel": w._pbr("rough_concrete", 0.6, 1.0, Color(0.55, 0.55, 0.57)),
		"tugla": w._pbr("broken_brick_wall", 0.6, 1.0, Color(0.85, 0.75, 0.7)),
		"tahta": w._pbr("weathered_planks", 1.6, 1.0, Color(0.6, 0.5, 0.42)),
	}
	var demir := StandardMaterial3D.new()
	demir.albedo_color = Color(0.22, 0.17, 0.13)
	demir.metallic = 0.7
	demir.roughness = 0.6
	_malz["demir"] = demir


static func _gurultu(v: Vector3) -> float:
	return sin(v.x * 3.7 + v.z * 1.3) * 0.5 + sin(v.y * 4.9 + v.x * 2.1) * 0.3 + sin(v.z * 5.3 - v.y * 2.7) * 0.2


func _tunel_kur() -> void:
	if not is_instance_valid(_tunel):
		return
	for c in _tunel.get_children():
		c.queue_free()
	var st := {}
	for k in _malz:
		if k != "demir":
			var s := SurfaceTool.new()
			s.begin(Mesh.PRIMITIVE_TRIANGLES)
			st[k] = s
	var carpisma := PackedVector3Array()
	var dolu := {}
	for anah in _kazilan:
		var pr: PackedStringArray = str(anah).split(",")
		var x := int(pr[0])
		var z := int(pr[1])
		dolu[anah] = true
		var y0 := TY
		var y1 := TY + TH
		# taban ve tavan
		_yuzey(st.zemin, Vector3(x, y0, z), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3.UP, 0.0, carpisma)
		_yuzey(st.tavan, Vector3(x, y1, z + 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3.DOWN, 0.06, carpisma)
		# dört yanda kazılmamış komşu: duvar (malzemesi komşunun türü)
		for yon in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + yon.x
			var nz: int = z + yon.y
			if _kazilan.has(anahtar(nx, nz)):
				continue
			var ne := kare(nx, nz)
			var malz: String = "toprak" if ne == "" else ("temel" if ne == "izgara" else ne)
			var oyuk := 0.0 if ne in ["temel", "izgara", "tugla"] else (0.11 if ne == "kaya" else 0.08)
			var n := Vector3(-yon.x, 0, -yon.y)  # tünelin içine doğru
			var a: Vector3
			var u: Vector3
			if yon.x == 1:
				a = Vector3(x + 1, y0, z + 1)
				u = Vector3(0, 0, -1)
			elif yon.x == -1:
				a = Vector3(x, y0, z)
				u = Vector3(0, 0, 1)
			elif yon.y == 1:
				a = Vector3(x, y0, z + 1)
				u = Vector3(1, 0, 0)
			else:
				a = Vector3(x + 1, y0, z)
				u = Vector3(-1, 0, 0)
			_yuzey(st[malz], a, u, Vector3(0, TH, 0), n, oyuk, carpisma)
			if ne == "izgara":
				_izgara(a, u, n)
		# ahşap destek: tavanda kiriş ve iki yanda dikme (her üç karede bir, tünel yönüne dik)
		if (x * 7 + z * 13) % 3 == 0:
			var yatay := not (_kazilan.has(anahtar(x + 1, z)) or _kazilan.has(anahtar(x - 1, z)))
			_destek(st.tahta, Vector3(x + 0.5, y0, z + 0.5), yatay)
	for k in st:
		var s: SurfaceTool = st[k]
		s.generate_normals()
		var mesh := s.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _malz[k]
		_tunel.add_child(mi)
	# açık klozetlerin kuyuları (tünel tavanından hücre tabanına)
	for i in w.cells.size():
		if w.cells[i].klozet_acik:
			var kk := klozet_kare(i)
			_kuyu(Vector3(kk.x + 0.5, TY + TH, kk.y + 0.5))
	# çarpışma
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(carpisma)
	cs.shape = sh
	_tunel_govde = StaticBody3D.new()
	_tunel_govde.add_child(cs)
	_tunel.add_child(_tunel_govde)


# 3 x 3 parçalı yüzey (a köşesinden u ve v boyunca), içe doğru gürültüyle oyulmuş (kazılmış toprak görünümü)
func _yuzey(st: SurfaceTool, a: Vector3, u: Vector3, v: Vector3, n: Vector3, oyuk: float, carpisma: PackedVector3Array) -> void:
	var b := 3
	var nok := []
	for i in b + 1:
		var satir := []
		for j in b + 1:
			var p := a + u * (float(i) / b) + v * (float(j) / b)
			var kenar := i == 0 or i == b or j == 0 or j == b
			var oy := oyuk * (0.4 if kenar else 1.0) * (0.6 + 0.4 * _gurultu(p))
			satir.append(p + n * oy)
		nok.append(satir)
	for i in b:
		for j in b:
			var p00: Vector3 = nok[i][j]
			var p10: Vector3 = nok[i + 1][j]
			var p01: Vector3 = nok[i][j + 1]
			var p11: Vector3 = nok[i + 1][j + 1]
			# üçgenler içe (n) bakacak sırayla
			var ters := (p10 - p00).cross(p01 - p00).dot(n) > 0.0
			var tri := [p00, p01, p11, p00, p11, p10] if ters else [p00, p10, p11, p00, p11, p01]
			for q in tri:
				st.add_vertex(q)
	carpisma.append_array([a, a + u, a + u + v, a, a + u + v, a + v])


func _destek(st: SurfaceTool, c: Vector3, yatay: bool) -> void:
	var yan := Vector3(1, 0, 0) if yatay else Vector3(0, 0, 1)
	for s in [-0.42, 0.42]:
		_kutu_yuz(st, c + yan * s + Vector3(0, TH * 0.5, 0), Vector3(0.09, TH - 0.04, 0.09))
	_kutu_yuz(st, c + Vector3(0, TH - 0.09, 0), (Vector3(0.95, 0.1, 0.1) if yatay else Vector3(0.1, 0.1, 0.95)))


func _kutu_yuz(st: SurfaceTool, c: Vector3, b: Vector3) -> void:
	var h := b / 2.0
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var yuzler := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [3, 7, 6, 2], [0, 4, 7, 3], [1, 2, 6, 5]]
	for f in yuzler:
		var q: Array = f
		for t in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
			for i in t:
				st.add_vertex(c + v[i])


# Temeldeki eski demir ızgara: beton duvarın önünde paslı dikey ve yatay çubuklar
func _izgara(a: Vector3, u: Vector3, n: Vector3) -> void:
	var kok := Node3D.new()
	_tunel.add_child(kok)
	for i in 6:
		var p := a + u * (0.12 + i * 0.152) + n * 0.03
		Dunya.boru(kok, p + Vector3(0, 0.05, 0), p + Vector3(0, TH - 0.05, 0), 0.018, _malz.demir, 6)
	for j in 3:
		var y := 0.25 + j * 0.42
		Dunya.boru(kok, a + n * 0.04 + Vector3(0, y, 0), a + u + n * 0.04 + Vector3(0, y, 0), 0.015, _malz.demir, 6)


# Klozetin altından yukarı açılan dar kuyu (ışık hücreden süzülür)
func _kuyu(alt: Vector3) -> void:
	var kok := Node3D.new()
	_tunel.add_child(kok)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.42
	cm.height = absf(alt.y) + 0.02
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m: StandardMaterial3D = (_malz.toprak as StandardMaterial3D).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_FRONT  # içinden görünsün
	mi.material_override = m
	mi.position = Vector3(alt.x, alt.y + cm.height / 2.0, alt.z)
	kok.add_child(mi)
	var isik := OmniLight3D.new()
	isik.light_color = Color(1.0, 0.85, 0.6)
	isik.light_energy = 0.7
	isik.omni_range = 2.6
	isik.position = alt + Vector3(0, 0.4, 0)
	kok.add_child(isik)


# ---------- sayım ----------

func _sayim_uyari(ms: int) -> void:
	_sayim_bitis = Time.get_ticks_msec() + ms
	_sesc("sayim_zili", 0.0)
	_gardiyan_sesi("sayim_geliyor")
	if _yer_alti or _klozet_acik:
		flash("SAYIM GELİYOR!", "Hücrene dön ve klozeti yerine koy!", RED, 2.6)
	Titresim.vur("guclu")
	_gardiyan_kur()


func _sayim(yakalanan: Array) -> void:
	_sayim_bitis = 0
	if is_instance_valid(_sayim_yazi):
		_sayim_yazi.visible = false
	var ben := false
	for id in yakalanan:
		var c := _oyuncu_hucresi(int(id))
		if c >= 0 and c < w.cells.size():
			w.cells[c].klozet_ac(false, false)
			w.cells[c].klozet_vida(0)
		if int(id) == me():
			ben = true
	if ben:
		_eylem_bitir()
		_gardiyan_sesi("sayim_yakaladim")
		screen_flash(Color(0.9, 0.05, 0.02), 0.8, 0.03, 0.5)
		flash("SAYIMDA YOKSUN!", "Aletlerin toplandı, klozetin yeniden vidalandı.", RED, 3.0)
		var p: CharacterBody3D = w.player
		if _yer_alti:
			_yer_alti_ol(false, _hucrem())
		if p.crouched:
			p.toggle_crouch()
		p.global_position = w.cells[_hucrem()].spawn_world()
		p.velocity = Vector3.ZERO
		_vida = 0
		_klozet_acik = false
	elif not yakalanan.is_empty():
		_toast(tr("Sayımda %d kişi yakalandı.") % yakalanan.size())
		_gardiyan_sesi("sayim_yakaladim")
	elif randf() < 0.5:
		_gardiyan_sesi("sayim_tamam")
	_tunel_kur()
	g.get_tree().create_timer(3.0).timeout.connect(_gardiyan_kaldir)


# Sayımda gardiyan koridorda yürür, feneriyle hücrelere bakar
func _gardiyan_kur() -> void:
	_gardiyan_kaldir()
	_gardiyan = BodyScript.new()
	_gardiyan.look = Catalog.sanitize({"govde": "erkek", "kiyafet": "gardiyan", "sapka": "kep", "sakal": "biyik", "sac": "kisa", "ten": 2})
	w.add_child(_gardiyan)
	_gardiyan.global_position = Vector3(3.9, 0, 26.0)
	_gardiyan.rotation.y = 0.0
	_gardiyan_fener = SpotLight3D.new()
	_gardiyan_fener.light_color = Color(0.95, 0.97, 1.0)
	_gardiyan_fener.light_energy = 6.0
	_gardiyan_fener.spot_angle = 20.0
	_gardiyan_fener.spot_range = 9.0
	w.add_child(_gardiyan_fener)


func _gardiyan_kaldir() -> void:
	if is_instance_valid(_gardiyan):
		_gardiyan.queue_free()
	if is_instance_valid(_gardiyan_fener):
		_gardiyan_fener.queue_free()
	_gardiyan = null


func _gardiyan_kare(delta: float) -> void:
	if not is_instance_valid(_gardiyan):
		return
	var p := _gardiyan.global_position
	if p.z > -26.0:
		p.z -= 3.2 * delta
		_gardiyan.global_position = p
		_gardiyan.set("walk", 1.0)
	else:
		_gardiyan.set("walk", 0.0)
	if is_instance_valid(_gardiyan_fener):
		_gardiyan_fener.global_position = p + Vector3(-0.3, 1.3, -0.3)
		# en yakın hücrenin içine bakar
		var hedef := Vector3(-0.5, 0.3, round((p.z) / HUCRE_ARA - 0.0) * HUCRE_ARA - 1.0)
		_gardiyan_fener.look_at(hedef, Vector3.UP)


# ---------- kaçış: dışarısı ----------

func _kacis_sahnesi(kare_) -> void:
	_eylem_bitir()
	var kx := float(kare_[0]) + 0.5 if kare_ is Array and kare_.size() == 2 else float(CIT_X)
	var kz := float(kare_[1]) + 0.5 if kare_ is Array and kare_.size() == 2 else 0.0
	_yer_alti = false
	_ortam_ayarla()
	if is_instance_valid(_ortam):
		_ortam.stop()
	if is_instance_valid(_cakmak):
		_cakmak.visible = false
	if is_instance_valid(_fener):
		_fener.visible = false
	_dis_kur(Vector3(kx, 0, kz))
	var p: CharacterBody3D = w.player
	p.busy = true
	_kontroller(false)
	if p.crouched:
		p.toggle_crouch()
	_kam = Camera3D.new()
	_kam.fov = 62.0
	w.add_child(_kam)
	_kam.global_position = Vector3(kx, TY + 1.0, kz)
	_kam.look_at(Vector3(kx - 0.2, 2.0, kz + 0.1), Vector3.UP)
	_kam.make_current()
	_sesc("tas_toprak", 2.0)
	# delikten çık: kamera yükselir, sonra ormana döner
	var tw := _kam.create_tween()
	tw.tween_property(_kam, "global_position", Vector3(kx, 1.55, kz), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		_kam.look_at(Vector3(kx - 6.0, 1.2, kz), Vector3.UP)
		_ses3d("projektor/siren", Vector3(TEMEL_X, 6.0, kz), -8.0, 30.0)
		_gardiyan_sesi("kacak_var")
		flash(tr("KAÇTIN!"), tr("%d. kaçan sensin") % _kactim, GREEN, 3.0)
		play("seviye", -2.0))
	tw.tween_interval(0.4)
	# kamera ormana (batıya) çekilir, arkasında hapishane: koşan kendini ve duvardaki projektörü görürsün
	tw.tween_property(_kam, "global_position", Vector3(kx - 9.0, 2.4, kz + 3.5), 3.2).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(func(v: float) -> void: _kam.look_at(Vector3(kx - v * 5.0, 1.2 + v * 0.8, kz), Vector3.UP), 0.0, 1.0, 3.2)
	# kendi gövdem ormana koşar
	var b: Node3D = BodyScript.new()
	b.look = Catalog.sanitize(w._player_entry(me()).get("g", {}))
	w.add_child(b)
	b.global_position = Vector3(kx, 0, kz)
	b.rotation.y = PI / 2.0  # batıya (-x)
	b.set("walk", 1.0)
	var btw := b.create_tween()
	btw.tween_interval(1.8)
	btw.tween_property(b, "global_position", Vector3(kx - 13.0, 0, kz + 1.0), 6.0)
	btw.tween_callback(b.queue_free)
	g.get_tree().create_timer(6.5).timeout.connect(func() -> void:
		if _kactim > 0:
			_izle_baslat())


# Dışarısı: orman zemini, tel örgü (arkada), hapishanenin yüksek duvarı ve kulesi, ağaçlar, ay
func _dis_kur(c: Vector3) -> void:
	if is_instance_valid(_dis):
		_dis.queue_free()
	_dis = Node3D.new()
	w.add_child(_dis)
	var zemin := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	zemin.mesh = pm
	zemin.material_override = w._pbr("forest_ground_04", 0.25, 1.0, Color(0.75, 0.78, 0.72))
	zemin.position = Vector3(c.x - 10, 0.0, c.z)
	_dis.add_child(zemin)
	# delik
	var del := MeshInstance3D.new()
	var dc := CylinderMesh.new()
	dc.top_radius = 0.45
	dc.bottom_radius = 0.45
	dc.height = 0.02
	del.mesh = dc
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.03, 0.02, 0.015)
	del.material_override = dm
	del.position = c + Vector3(0, 0.012, 0)
	_dis.add_child(del)
	# tel örgü (arkada, doğuda) ve dikenli tel
	for i in 12:
		var z := c.z - 12.0 + i * 2.2
		w.model("modular_chainlink_fence", Vector3(float(CIT_X) + 2.6, 0, z), PI / 2.0, 1.0, NAN, _dis)
	# hapishanenin dış duvarı ve kulesi
	var duvar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 9.0, 70.0)
	duvar.mesh = bm
	duvar.material_override = w._pbr("concrete_wall_008", 0.25, 1.0, Color(0.45, 0.45, 0.48))
	duvar.position = Vector3(float(TEMEL_X) + 0.5, 4.5, c.z)
	_dis.add_child(duvar)
	# duvarın üstünde sodyum lambalar: duvar gece seçilsin
	var lamba_m := StandardMaterial3D.new()
	lamba_m.albedo_color = Color(1.0, 0.7, 0.35)
	lamba_m.emission_enabled = true
	lamba_m.emission = Color(1.0, 0.65, 0.3)
	lamba_m.emission_energy_multiplier = 4.0
	for i in 7:
		var lz := c.z - 24.0 + i * 8.0
		var lp := Vector3(float(TEMEL_X) - 0.3, 8.2, lz)
		_kutu_mi(_dis, lp, Vector3(0.35, 0.14, 0.5), lamba_m)
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.68, 0.38)
		ol.light_energy = 1.6
		ol.omni_range = 9.0
		ol.position = lp + Vector3(-0.6, -0.4, 0)
		_dis.add_child(ol)
	var kule_isik := SpotLight3D.new()
	kule_isik.light_color = Color(1.0, 0.95, 0.85)
	kule_isik.light_energy = 10.0
	kule_isik.spot_range = 40.0
	kule_isik.spot_angle = 9.0
	_dis.add_child(kule_isik)
	kule_isik.global_position = Vector3(float(TEMEL_X), 10.0, c.z + 6.0)
	var huz: MeshInstance3D = Dunya.huzme(_dis, Vector3.ZERO, 10.0, 0.2, 1.6, Color(1.0, 0.95, 0.85), 0.2)
	var tw := kule_isik.create_tween().set_loops()
	tw.tween_method(func(v: float) -> void:
		var hedef := Vector3(c.x - 6.0 + sin(v) * 8.0, 0, c.z + cos(v * 0.7) * 10.0)
		if is_instance_valid(kule_isik):
			kule_isik.look_at(hedef, Vector3.UP)
			var top := kule_isik.global_position
			var y := (top - hedef).normalized()
			var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
			huz.global_transform = Transform3D(Basis(x, y * (top.distance_to(hedef) / 10.0), x.cross(y)), (top + hedef) / 2.0), 0.0, TAU, 9.0)
	# ağaçlar: koyu gövde ve iğne yapraklı tepeler
	var govde_m := StandardMaterial3D.new()
	govde_m.albedo_color = Color(0.12, 0.09, 0.07)
	var yaprak_m := StandardMaterial3D.new()
	yaprak_m.albedo_color = Color(0.05, 0.09, 0.06)
	yaprak_m.roughness = 0.95
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 40:
		var p := Vector3(c.x - rng.randf_range(5.0, 28.0), 0, c.z + rng.randf_range(-24.0, 24.0))
		if absf(p.z - c.z - 1.5) < 5.5 and p.x > c.x - 20.0:
			continue  # kaçış yolu ve kamera açık kalsın
		var h := rng.randf_range(5.0, 9.0)
		var gv := MeshInstance3D.new()
		var gc := CylinderMesh.new()
		gc.top_radius = 0.12
		gc.bottom_radius = 0.2
		gc.height = h * 0.45
		gv.mesh = gc
		gv.material_override = govde_m
		gv.position = p + Vector3(0, h * 0.225, 0)
		_dis.add_child(gv)
		for k in 3:
			var kon := MeshInstance3D.new()
			var cc := CylinderMesh.new()
			cc.top_radius = 0.0
			cc.bottom_radius = h * (0.28 - k * 0.06)
			cc.height = h * 0.42
			kon.mesh = cc
			kon.material_override = yaprak_m
			kon.position = p + Vector3(0, h * (0.42 + k * 0.17), 0)
			_dis.add_child(kon)
	var ay := DirectionalLight3D.new()
	ay.light_color = Color(0.55, 0.65, 0.95)
	ay.light_energy = 0.9
	ay.shadow_enabled = true
	ay.rotation = Vector3(deg_to_rad(-40), deg_to_rad(60), 0)
	_dis.add_child(ay)


# ---------- kaçınca: izleyici (hayattakilerin gözünden) ----------

func _izle_baslat() -> void:
	if not is_instance_valid(_kam):
		_kam = Camera3D.new()
		w.add_child(_kam)
	_kam.fov = 70.0
	_kam.near = 0.06
	_kam.make_current()
	if is_instance_valid(_dis) and not _izlenebilir().is_empty():
		_dis.visible = false
	if not is_instance_valid(_izle_bar):
		_izle_bar = HBoxContainer.new()
		_izle_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_izle_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_izle_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_izle_bar.offset_top = -120
		_izle_bar.offset_bottom = -24
		_izle_bar.alignment = BoxContainer.ALIGNMENT_CENTER
		_izle_bar.add_theme_constant_override("separation", 18)
		var sol := UI.icon_button("geri", "ikincil", 80)
		sol.pressed.connect(func() -> void: _izle_degistir(-1))
		_izle_bar.add_child(sol)
		var kutu := VBoxContainer.new()
		kutu.alignment = BoxContainer.ALIGNMENT_CENTER
		var ust := UI.title(tr("KAÇTIN · İZLİYORSUN"), 22, Color(0.75, 1.0, 0.8))
		ust.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kutu.add_child(ust)
		_izle_ad = UI.title("", UI.FS_ORTA + 4, GOLD)
		_izle_ad.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_izle_ad.custom_minimum_size = Vector2(380, 0)
		kutu.add_child(_izle_ad)
		_izle_bar.add_child(kutu)
		var sag := UI.icon_button("oyna", "ikincil", 80)
		sag.pressed.connect(func() -> void: _izle_degistir(1))
		_izle_bar.add_child(sag)
		root().add_child(_izle_bar)
	_izle_bar.visible = true
	_izlenen = 0
	_izle_degistir(1)


# Kaçınca yürüme kolu, eğil / hareket / eylem düğmeleri ve nişan noktası gizli
func _kontroller(on: bool) -> void:
	var h = w.hud if w else null
	if not h:
		return
	h.set("izleyici", not on)
	for ad in ["joy", "action_btn", "dot"]:
		var n = h.get(ad)
		if n is CanvasItem and (n as CanvasItem).visible != on:
			(n as CanvasItem).visible = on


func _izlenebilir() -> Array:
	var out := []
	for id in state.get("players", []):
		var pid := int(id)
		if pid != me() and not _kacanlar.has(pid) and w.remotes.has(pid) and not w.is_bot(pid):
			out.append(pid)
	return out


func _izle_degistir(yon: int) -> void:
	_izle_bakis = Vector2.ZERO
	if _izlenen != 0 and w.remotes.has(_izlenen):
		(w.remotes[_izlenen].body as Node3D).visible = true
	var liste := _izlenebilir()
	if liste.is_empty():
		_izlenen = 0
		if is_instance_valid(_izle_ad):
			_izle_ad.text = tr("İzlenecek kimse yok")
		return
	var i := liste.find(_izlenen)
	i = 0 if i < 0 else posmod(i + yon, liste.size())
	_izlenen = int(liste[i])
	(w.remotes[_izlenen].body as Node3D).visible = false
	if is_instance_valid(_izle_ad):
		_izle_ad.text = pname(_izlenen)


func _izle_kare() -> void:
	if not is_instance_valid(_kam) or _izlenen == 0 or not w.remotes.has(_izlenen):
		return
	if _kacanlar.has(_izlenen):
		_izle_degistir(1)
		return
	var r: Dictionary = w.remotes[_izlenen]
	var root_n: Node3D = r.root
	var goz := root_n.global_position + Vector3(0, 1.0 if bool(r.body.get("crouched")) else 1.6, 0)
	var yaw := root_n.global_rotation.y - _izle_bakis.x
	var egim := clampf(-0.06 + _izle_bakis.y, -1.2, 1.1)
	var ileri := Vector3(-sin(yaw) * cos(egim), sin(egim), -cos(yaw) * cos(egim))
	_kam.global_position = goz
	_kam.look_at(goz + ileri, Vector3.UP)


func _input(event: InputEvent) -> void:
	if _kactim == 0 or _izlenen == 0:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).double_tap:
		_izle_degistir(1)
		return
	var fark := Vector2.ZERO
	if event is InputEventScreenDrag:
		fark = (event as InputEventScreenDrag).relative
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT):
		fark = (event as InputEventMouseMotion).relative
	if fark != Vector2.ZERO:
		_izle_bakis.x += fark.x * 0.005
		_izle_bakis.y = clampf(_izle_bakis.y - fark.y * 0.005, -1.1, 1.1)


# ---------- bitiş ----------

func _karart(t: float, sonra: Callable) -> void:
	var f := ColorRect.new()
	f.color = Color(0, 0, 0, 0)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root().add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "color", Color(0, 0, 0, 1), t)
	tw.tween_callback(sonra)
	tw.tween_property(f, "color", Color(0, 0, 0, 0), t)
	tw.tween_callback(f.queue_free)


func _eve_don() -> void:
	if not w:
		return
	_eylem_bitir()
	_gardiyan_kaldir()
	if _izlenen != 0 and w.remotes.has(_izlenen):
		(w.remotes[_izlenen].body as Node3D).visible = true
	_izlenen = 0
	_kactim = 0
	_kontroller(true)
	if is_instance_valid(_izle_bar):
		_izle_bar.queue_free()
	if is_instance_valid(_kam):
		_kam.queue_free()
	if is_instance_valid(_dis):
		_dis.queue_free()
	if is_instance_valid(_tunel):
		_tunel.queue_free()
	for d in _defterler + _gizliler:
		if is_instance_valid(d):
			(d as Node).queue_free()
	_defterler.clear()
	_gizliler.clear()
	if is_instance_valid(_ortam):
		_ortam.queue_free()
	if is_instance_valid(_cakmak):
		_cakmak.queue_free()
	if is_instance_valid(_fener):
		_fener.queue_free()
	_yer_alti = false
	_gece(false)
	var p: CharacterBody3D = w.player
	if p:
		p.busy = false
		if p.crouched:
			p.toggle_crouch()
		p.camera.make_current()
		p.global_position = w.cells[w.my_cell].spawn_world()
		p.velocity = Vector3.ZERO
	for c in w.cells:
		c.klozet_ac(false, false)
		c.klozet_vida(0)
	for id in w.remotes:
		(w.remotes[id].root as Node3D).visible = true
		(w.remotes[id].body as Node3D).visible = true
	if is_instance_valid(_karanlik):
		(_karanlik.material as ShaderMaterial).set_shader_parameter("k", 0.0)


# ---------- test (sunucusuz) ----------
# main.gd: pose=oyunici oyun=kacis ekran=hucre|defter|klozet|tunel|kaz|kacis|sayim
func test_ekran(ek: String, args: Dictionary) -> void:
	for p in g.net.players:
		if int(p.id) != me():
			p["bot"] = true
	w.game_on = true
	var tohum := 4242
	state["phase"] = "kacis"
	state["harita"] = {"izgara": [floori(hucre_z(2)), floori(hucre_z(6))], "tugla": [floori(hucre_z(4))], "kaya": ["-4,-14", "-5,-14", "-6,-12", "-3,-9", "-12,-11", "-13,-11"]}
	var kz := klozet_kare(w.my_cell)
	var kazi := [anahtar(kz.x, kz.y)]
	# klozetten batıya bir tünel, kayayı dolaşıp temele, oradan yan dal
	for x in range(kz.x - 1, TEMEL_X, -1):
		kazi.append(anahtar(x, kz.y))
	for z in range(kz.y + 1, kz.y + 4):
		kazi.append(anahtar(-5, z))
	state["kazilan"] = kazi
	state["klozet"] = {"1": ek in ["klozet", "tunel", "kaz", "kacis"]}
	on_state(state, true)
	_durum_al({"env": ["caki", "kasik", "tel", "catal"] if ek != "tunel" else ["caki", "kurek", "fener", "maymuncuk"], "vida": 4 if ek in ["klozet", "tunel", "kaz"] else 1,
		"klozet": ek in ["klozet", "tunel", "kaz"], "ipucu": {"tur": "izgara", "z": floori(hucre_z(2))}})
	if ek in ["klozet", "tunel", "kaz"]:
		w.cells[w.my_cell].klozet_ac(true, false)
	var p: CharacterBody3D = w.player
	match ek:
		"hucre":
			p.global_position = w.cells[w.my_cell].to_global(Vector3(0.3, 0, 0.9))
			p.rotation.y = deg_to_rad(12)
		"defter":
			_defter_ac()
		"klozet":
			p.global_position = w.cells[w.my_cell].to_global(Vector3(0.6, 0, -1.4))
			p.rotation.y = deg_to_rad(-35)
			p.head.rotation.x = deg_to_rad(-30)
		"tunel", "kaz":
			_asagi_in(w.my_cell)
			await g.get_tree().create_timer(0.8).timeout
			if ek == "kaz":
				p.global_position = Vector3(-4.5, TY + 0.05, kz.y + 3.5)
				p.rotation.y = PI  # +z
				do_action("kaz")
			else:
				p.global_position = Vector3(TEMEL_X + 2.5, TY + 0.05, kz.y + 0.5)
				p.rotation.y = PI / 2.0  # batıya
		"kacis":
			_kactim = 1
			_kacis_sahnesi([CIT_X - 1, 0])
		"sayim":
			_sayim_uyari(15000)
