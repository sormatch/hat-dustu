# BÜYÜK KAÇIŞ (maçın son oyunu). Kurallar sunucuda: server/src/modes/kacis.js. Burada görüntü, ses ve etkileşim.
# Hücre: 13 gizli yer (yatak altı, yastık, raf, poster, havalandırma, gevşek tuğla, lavabo altı, koltuk, dolap, bilgisayar,
#   ayna arkası, çöp kutusu, gevşek karo) + açıkta tuvalet kağıdı ve çarşaf; her hücrede tam takım malzeme.
#   Kaçış defteri (tarifler + ipucu), klozet (4 vida, kenara çekilir, altında toprak). Kukla: 2 tuvalet kağıdı + çarşaf.
# Yer altı: 1 m'lik ızgarada kazılan kareler tek ağ olarak kurulur (toprak / kaya / beton temel / tuğla / ızgara duvarlar,
#   ahşap destekler); çakmak ışığı, fenerle güçlü ışık; kazarken yorulma; yön göstergesi (batı: temel ve tel örgü).
# Sayım: zil çalar, 30 sn sonra gardiyan koridorun ucundan girer, kapıları tek tek dolaşıp camdan feneriyle bakar;
#   kapına geldiğinde hücrende (ya da yatakta kukla) ve klozet kapalı olmalı.
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
const TARIFLER := {"kurek": ["kasik", "tahta", "bant"], "fener": ["pil", "ampul", "tel"], "maymuncuk": ["tel", "catal"],
	"kukla": ["kagit", "kagit", "carsaf"]}
const AD := {"caki": "Çakı", "kasik": "Kaşık", "tahta": "Tahta", "bant": "Bant", "pil": "Pil", "ampul": "Ampul", "tel": "Tel",
	"catal": "Çatal", "kurek": "Kürek", "fener": "Fener", "maymuncuk": "Maymuncuk", "kagit": "Tuvalet kağıdı", "carsaf": "Çarşaf",
	"kukla": "Kukla"}
# gizli yerler: hücreye göre konum ve düğme yazısı
const YERLER := {
	"yatak": [Vector3(-1.05, 0.25, -1.95), "Yatak altı"],
	"yastik": [Vector3(-1.5, 0.66, -2.6), "Yastığı yokla"],
	"kitaplik": [Vector3(-1.35, 1.0, 2.62), "Rafı karıştır"],
	"poster": [Vector3(-1.45, 1.75, -2.93), "Poster arkası"],
	"havalandirma": [Vector3(-0.75, 2.62, -2.93), "Havalandırma"],
	"tugla": [Vector3(-0.25, 0.3, -2.95), "Gevşek tuğla"],
	"lavabo": [Vector3(1.5, 0.6, -2.62), "Lavabo altı"],
	"koltuk": [Vector3(0.0, 0.5, -1.5), "Minderi kaldır"],
	"dolap": [Vector3(-1.55, 1.0, -0.22), "Dolabı karıştır"],
	"bilgisayar": [Vector3(-1.5, 0.55, 1.05), "Kasaya bak"],
	"ayna": [Vector3(-1.9, 1.78, 1.05), "Aynanın arkası"],
	"cop": [Vector3(0.85, 0.32, -2.62), "Çöpü karıştır"],
	"zemin": [Vector3(1.0, 0.04, 2.05), "Gevşek karo"],
	# açıkta duranlar (hep aynı eşya)
	"tuvalet": [Vector3(1.91, 0.62, -2.2), "Tuvalet kağıdını al"],
	"carsaf": [Vector3(-1.04, 0.5, -2.45), "Çarşafı çek"],
}
const KAPI_CAMI := Vector3(2.75, 0, 0.5)  # gardiyanın durduğu yer: kapı camının önü (koridor, hücreye göre)
const DEFTER := Vector3(-1.3, 0.612, -1.2)  # yatağın üstünde (battaniyenin üstü 0.60)
const KUKLA_YER := Vector3(-1.5, 0.7, -1.7)  # yatağın ortası (kukla düğmesi)
const ELDE := Vector3(0.15, -0.145, -0.33)  # kameraya göre elde tutulan eşyanın yeri (sağ alt)
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
var _tur := {}  # sürmekte olan sayım turu: {t0 (ilk kapı, ms), sira, ara, bakis, islenen}
var _defterler: Array = []
var _gizliler: Array = []
var _acik_parca := {}  # "hücre:yer" -> açıkta duran eşyanın görüntüsü (tuvalet kağıdı, katlı çarşaf): alınınca gizlenir
var _dis: Node3D  # kaçış sahnesi (dışarısı)
var _kam: Camera3D
var _izlenen := 0
var _izle_bakis := Vector2.ZERO
var _izle_bar: HBoxContainer
var _kuklalar := {}  # hücre -> kukla düğümü (yatakta battaniye altında)
var _kuklam := false
var _fenerliler := {}  # id -> true (kafasında fener olanlar)
var _kafa_lambalari := {}  # id -> kafa lambası düğümü (uzak oyuncunun kafasında)
var _lamba_t := 0.0
var _bildirim: PanelContainer
var _bildirim_bas: Label
var _bildirim_alt: Label
var _bildirim_tw: Tween
var _eldeki: Node3D  # elde tutulan eşya / alet (kameraya bağlı)
var _gosterim := false  # otomatik nasıl kaçılır gösterimi (sunucusuz, olayları kendisi üretir)
var _altyazi: Label
var _izle_ad: Label

# arayüz
var _esya_bar: HFlowContainer
var _ilerleme: ProgressBar
var _ilerleme_yazi: Label
var _yorgun_bar: ProgressBar
var _pusula: Label
var _sayim_yazi: Label
var _karanlik: ColorRect


func _ready() -> void:
	_esya_bar = HFlowContainer.new()
	_esya_bar.custom_minimum_size = Vector2(380, 0)
	_esya_bar.alignment = FlowContainer.ALIGNMENT_END
	_esya_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_esya_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_esya_bar.offset_top = 96
	_esya_bar.offset_right = -24
	_esya_bar.add_theme_constant_override("h_separation", 5)
	_esya_bar.add_theme_constant_override("v_separation", 5)
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
	_sayim_yazi = UI.title("", UI.FS_ORTA + 2, RED, true)
	_sayim_yazi.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sayim_yazi.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sayim_yazi.offset_top = 164
	_sayim_yazi.offset_bottom = 222
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
	p.stream = g.ses_akis(ad)
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
	if d.has("fener"):
		_fener_listesi(d.fener)
	if d.has("kukla"):
		for id in d.kukla:
			_kukla_goster(_oyuncu_hucresi(int(id)), true)
			if int(id) == me():
				_kuklam = true
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
			var gd = d.get("gardiyan", null)
			if gd is Dictionary:
				_sayim_uyari(int(gd.get("bas", 0)), gd.get("sira", [7, 6, 5, 4, 3, 2, 1, 0]), int(gd.get("ara", 4000)), int(gd.get("bakis", 900)))
			elif int(d.get("sayim", -1)) > 0:
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
				var yap := str(d.yapildi)
				_bildir(tr("%s YAPTIN!") % up(tr(AD.get(yap, ""))), tr("Kafanda. Tüneli aydınlatır.") if yap == "fener" else (tr("Yatağına yatır, gardiyanı kandırsın.") if yap == "kukla" else ""), GREEN, 2.0)
				_sesc("vida_dus", -2.0)
			if d.has("aldi"):
				_bildir(tr("%s ALDIN") % up(tr(AD.get(str(d.aldi), ""))), pname(int(d.get("kimden", 0))), GOLD, 1.4)
		"red":
			_toast(Dil.sunucu(d, "m"))
			play("hata", -6.0)
		"bos":
			_aranan["%d:%s" % [int(d.hucre), str(d.yer)]] = true
			_bildir(tr("Burada bir şey yok."), "", Color(0.75, 0.72, 0.65), 1.2)
		"buldu":
			_aranan["%d:%s" % [int(d.hucre), str(d.yer)]] = true
			_acik_yer_al(int(d.hucre), str(d.yer))
			_bildir(tr("%s BULDUN!") % up(tr(AD.get(str(d.esya), ""))), "", GOLD, 1.6)
			play("odul", -6.0)
			# eşya saklandığı yerden ele gelir, sonra cebe (envanter) girer
			_al_animasyonu(w.cells[int(d.hucre)].to_global(YERLER[str(d.yer)][0]) if YERLER.has(str(d.yer)) and int(d.hucre) >= 0 else Vector3.ZERO, str(d.esya), d)
		"vida":
			var c := _oyuncu_hucresi(int(d.id))
			if c >= 0 and c < w.cells.size():
				if int(d.id) != me():
					w.cells[c].klozet_vida_sok(int(d.n) - 1, 0.6)
				_ses3d("kacis/vida_dus", w.cells[c].klozet_world(), -4.0, 2.0)
		"klozet":
			var c := int(d.get("hucre", -1))
			if c >= 0 and c < w.cells.size():
				w.cells[c].klozet_ac(bool(d.acik))
				_ses3d("kacis/klozet_cek", w.cells[c].klozet_world(), 0.0, 4.0)
			var kk: Array = d.get("kare", [])
			if bool(d.acik) and kk.size() == 2:
				_kazilan[anahtar(int(kk[0]), int(kk[1]))] = true
			_tunel_yenile()  # kuyu açıldı / kapandı: tavan ve kuyu yeniden
		"kazildi":
			var kk: Array = d.kare
			_kazilan[anahtar(int(kk[0]), int(kk[1]))] = true
			if str(d.get("ne", "")) == "izgara":
				_acik_izgara[anahtar(int(kk[0]), int(kk[1]))] = true
			_tunel_yenile()
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
					_bildir("KAYA", "Yandan dolaş.", UI.AMBER, 1.8)
				"temel":
					_bildir("BETON TEMEL", "Izgarayı ya da gevşek tuğlayı bul.", UI.AMBER, 2.4)
				"izgara":
					_bildir("ESKİ DEMİR IZGARA", "Maymuncukla açılır.", UI.AMBER, 2.2)
				"tugla":
					_bildir("GEVŞEK TUĞLALAR", "Kürekle kazılır.", UI.AMBER, 2.2)
		"yukari":
			_yukari_n = int(d.n)
			_sesc("tas_toprak", 0.0)
			w._shake(0.3, 0.04)
			_bildir(tr("YUKARI KAZ: %d/%d") % [_yukari_n, YUKARI], "Az kaldı.", GOLD, 1.4)
		"toprak":
			var kk: Array = d.kare
			_ses3d("kacis/tas_toprak", Vector3(float(kk[0]) + 0.5, TY + 1.0, float(kk[1]) + 0.5), -4.0, 3.0)
		"kacti":
			_kacanlar[int(d.id)] = true
			if int(d.id) == me():
				_kactim = int(d.sira)
				_kacis_sahnesi(d.get("kare", []))
			else:
				_bildir(tr("%s KAÇTI!") % up(pname(int(d.id))), tr("%d. kaçan") % int(d.sira), RED, 2.0)
				_gardiyan_sesi("kacak_var")
				_sesc("sayim_zili", -10.0)
				if w.remotes.has(int(d.id)):
					(w.remotes[int(d.id)].root as Node3D).visible = false
		"sayim_uyari":
			_sayim_uyari(int(d.get("ms", 30000)), d.get("sira", [7, 6, 5, 4, 3, 2, 1, 0]), int(d.get("ara", 4000)), int(d.get("bakis", 900)))
		"kontrol":
			_kontrol(d)
		"kukla":
			_kukla_goster(int(d.get("hucre", -1)), bool(d.get("on", false)))
			if int(d.get("id", 0)) == me():
				_kuklam = bool(d.get("on", false))
				if _kuklam:
					_bildir(tr("KUKLA YATAKTA"), tr("Gardiyanı kandırır. Klozeti kapalı tut."), GREEN, 2.6)
		"kandirdi":
			_bildir(tr("GARDİYAN KANDI"), tr("Kazmaya devam."), GREEN, 2.6)
		"fener":
			_fener_listesi(d.get("ids", []))
		"sayim":
			_sayim(d.get("yakalanan", []))


func show_card() -> void:
	if phase() != "anons":
		return
	role_card("BÜYÜK KAÇIŞ", GOLD, "Alet yap, klozetin altını kaz, kaç. Sayımda hücrende ol.")


var _bant_t := 0.0


# Görev bandı: başlık ne yapacağın (sayımda geri sayım), bilgi yer altında yön, yukarıda kaçan sayısı
func banner() -> Array:
	var bas := tr("KAÇ")
	var bilgi := tr("Kaçan: %d") % _kacanlar.size()
	if _yer_alti and w and w.player:
		bilgi = _pusula_yazisi()
	if _sayim_bitis > 0:
		# zilden gardiyan gelene kadar SAYIM, sonra kapına gelene kadar GARDİYAN geri sayımı
		var gardiyan_yolda: bool = not _tur.is_empty() and Time.get_ticks_msec() >= int(_tur.t0)
		bas = (tr("GARDİYAN %d") if gardiyan_yolda else tr("SAYIM %d")) % maxi(0, ceili(float(_sayim_bitis - Time.get_ticks_msec()) / 1000.0))
		if _yer_alti:
			bilgi = tr("Kuyuna %d m") % int(Vector2(_ben_kare()).distance_to(Vector2(klozet_kare(_hucrem()))))
	return [bas, bilgi]


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
	for n in [_esya_bar, _ilerleme, _ilerleme_yazi, _yorgun_bar, _pusula, _sayim_yazi, _karanlik, _bildirim]:
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
		# kendi kuyunun altında: klozeti üstüne çek (sayıma karşı) ya da it, aç
		if k == klozet_kare(_hucrem()) and _vida >= 4:
			var yukari_bak := on + Vector3(0, 0.6, 0)
			if w.cells[_hucrem()].klozet_acik:
				out.append(["klozet_kapa", yukari_bak, 3.0, tr("Klozeti kapat")])
			else:
				out.append(["klozet_ac", yukari_bak, 3.0, tr("Klozeti aç")])
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
		if _kuklam:
			out.append(["kukla_kaldir", c.to_global(KUKLA_YER), 2.0, tr("Kuklayı kaldır")])
		elif "kukla" in _env:
			out.append(["kukla", c.to_global(KUKLA_YER), 2.0, tr("Kukla yatır")])
		if _vida < 4:
			# sıradaki vidaya bak: her vida ayrı sökülür
			var vida_yer: Vector3 = c.klozet_vida_yeri(_vida) + Vector3(0, 0.03, 0)
			var yazi := tr("Vida %d/4") % (_vida + 1) if "caki" in _env else tr("Çakı lazım")
			out.append(["vida", vida_yer, 2.3, yazi])
		elif not c.klozet_acik:
			out.append(["klozet_ac", c.klozet_world(), 1.8, tr("Klozeti çek")])
		else:
			out.append(["klozet_kapa", c.klozet.global_position + Vector3(0, 0.3, 0), 1.8, tr("Klozeti kapat")])
	if c.klozet_acik:
		out.append(["in:%d" % cell, c.klozet_delik.global_position + Vector3(0, 0.1, 0), 1.8, tr("Aşağı in")])
	return out


func _kaz_yazisi(h: Vector2i) -> String:
	var aletim := "Kürekle kaz" if "kurek" in _env else ("Kaşıkla kaz" if "kasik" in _env else "Alet yok")
	match kare(h.x, h.y):
		"kaya":
			return tr("Kaya")
		"temel":
			return tr("Beton temel")
		"izgara":
			return tr("Izgarayı aç") if "maymuncuk" in _env else tr("Demir ızgara")
		"tugla":
			return tr("Tuğlayı kaz")
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
		_toast(tr("Yakalandın, bekle."))
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
				_toast(tr("Çakı lazım. Hücreni ara."))
				return
			_eylem("vida", SURE.vida + 0.3, {}, tr("Vida sökülüyor..."))
			w.cells[_hucrem()].klozet_vida_sok(_vida, SURE.vida + 0.3)
			_sesc("vida", -2.0)
		"kukla":
			if not "kukla" in _env:
				_toast(tr("Önce kukla yap: 2 tuvalet kağıdı + çarşaf."))
				return
			_eylem("kukla", 2.8, {}, tr("Kukla yatırılıyor..."))
			play("kumas_%d" % randi_range(1, 3), -4.0)
		"kukla_kaldir":
			net_karar({"kukla": false})
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
				_toast(tr("Kaşık ya da kürek lazım."))
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
	if g.net and not _gosterim:
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
	if tur in ["kaz", "yukari"]:
		_ele_al("kurek" if "kurek" in _env else "kasik")
	elif tur == "vida":
		_ele_al("caki")


func _eylem_bitir() -> void:
	_is = {}
	_elden_birak()
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
	if is_instance_valid(_eldeki):
		var ritim := float(_is.t) * (7.0 if tur == "vida" else 5.5)
		var yukarisi := tur == "yukari"
		var vurus := pow(maxf(0.0, sin(ritim)), 2.0)
		if tur == "vida":
			_eldeki.rotation.z = sin(ritim) * 0.9  # çakı çevriliyor
		else:
			_eldeki.position = ELDE + (Vector3(0, 0.07, -0.02) * vurus if yukarisi else Vector3(0, -0.04, -0.09) * vurus)
	if float(_is.t) >= float(_is.sure):
		var veri: Dictionary = _is.veri
		_eylem_bitir()
		if _gosterim:
			return  # gösterimde olayları gösterim kendisi üretir
		match tur:
			"ara":
				net_karar({"ara": veri.yer})
			"vida":
				net_karar({"vida": true})
			"kukla":
				net_karar({"kukla": true})
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
	# yön göstergesi ve sayım geri sayımı görev bandında (ayrı yazı yok, üst üste binmesin)
	if _sayim_bitis > 0 and _sayim_bitis <= Time.get_ticks_msec():
		_sayim_bitis = 0
	_bant_t -= delta
	if _bant_t <= 0.0:
		_bant_t = 0.25
		g._update_banner()
	# düşen olursa (çarpışma kurulmadan) kuyuya geri
	if _yer_alti and w.player.global_position.y < TY - 2.0:
		var kk := klozet_kare(_hucrem())
		w.player.global_position = Vector3(kk.x + 0.5, TY + 0.05, kk.y + 0.5)
		w.player.velocity = Vector3.ZERO
	_lamba_t -= delta
	if _lamba_t <= 0.0:
		_lamba_t = 0.4
		_kafa_lambalarini_guncelle()
		for id in _kacanlar:  # geri bağlanınca gövde yeniden kurulur: kaçan görünmesin
			if id != me() and w.remotes.has(id) and (w.remotes[id].root as Node3D).visible:
				(w.remotes[id].root as Node3D).visible = false
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
		parca.append(tr("Örgü %d m") % int(x - CIT_X))
	else:
		parca.append(tr("YUKARI KAZ"))
	return tr("BATI %s") % ok + "  ·  " + "  ·  ".join(parca)


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
		var l := UI.title(up(tr(AD.get(str(e), str(e)))), UI.FS_KUCUK, renk.lightened(0.3), true)
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
		_yeni_yerler_kur(kok, c, demir, karanlik)


# Sürüm 4 yerleri: tuvalet kağıdı askısı (rulosuyla), çöp kutusu, gevşek karo, yatakta katlı çarşaf
func _yeni_yerler_kur(kok: Node3D, c: int, demir: Material, karanlik: Material) -> void:
	var beyaz := _malzeme(Color(0.93, 0.92, 0.88), 0.0, 0.95)
	# askı: sağ duvarda (x 1.95 iç yüz) kısa kol, üstünde rulo
	var tv: Vector3 = YERLER.tuvalet[0]
	_kutu_mi(kok, tv + Vector3(0.035, 0, 0), Vector3(0.02, 0.05, 0.16), demir)
	_kutu_mi(kok, tv + Vector3(-0.02, 0, 0), Vector3(0.1, 0.012, 0.012), demir)
	if not _aranan.has("%d:tuvalet" % c):
		var rulo := _parca(kok, _silindir(0.055, 0.1), beyaz, tv + Vector3(-0.045, 0, 0), Vector3(0, 0, PI / 2.0))
		_acik_parca["%d:tuvalet" % c] = rulo
	# çöp kutusu: klozetin solunda teneke
	var cp: Vector3 = YERLER.cop[0]
	var kutu := _parca(kok, _silindir(0.13, 0.34), demir, Vector3(cp.x, 0.17, cp.z))
	kutu.name = "Cop"
	_parca(kok, _silindir(0.115, 0.01), karanlik, Vector3(cp.x, 0.336, cp.z))
	# gevşek karo: zeminde hafif kalkık, kenarı koyu
	var zm: Vector3 = YERLER.zemin[0]
	_kutu_mi(kok, Vector3(zm.x, 0.004, zm.z), Vector3(0.42, 0.006, 0.42), karanlik)
	var karo := _kutu_mi(kok, Vector3(zm.x, 0.014, zm.z), Vector3(0.38, 0.02, 0.38), _malzeme(Color(0.42, 0.41, 0.38), 0.0, 0.9))
	karo.rotation.x = 0.03
	# yatağın kenarında katlı çarşaf
	if not _aranan.has("%d:carsaf" % c):
		var cs := _kutu_mi(kok, YERLER.carsaf[0] + Vector3(-0.12, 0.13, 0), Vector3(0.3, 0.05, 0.36), _malzeme(Color(0.86, 0.85, 0.8), 0.0, 1.0))
		_acik_parca["%d:carsaf" % c] = cs


func _acik_yer_al(c: int, yer: String) -> void:
	var k := "%d:%s" % [c, yer]
	if _acik_parca.has(k) and is_instance_valid(_acik_parca[k]):
		(_acik_parca[k] as Node3D).visible = false
	_acik_parca.erase(k)


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
	var m := chalk_modal(tr("KAÇIŞ DEFTERİ"), "", 1060.0)
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
	var not1 := chalk(tr("KÜREK hızlı kazar · FENER aydınlatır · MAYMUNCUK ızgarayı açar"), 22, Color(0.85, 0.85, 0.75))
	not1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kutu.add_child(not1)
	var ip := chalk(tr("İPUCU: %s") % _ipucu_yazisi(), 26, Color(1.0, 0.86, 0.5))
	ip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kutu.add_child(ip)
	var yol := chalk(tr("Batıya kaz: önce temel, sonra tel örgü. Geçince YUKARI."), 22, Color(0.8, 0.85, 0.8))
	yol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kutu.add_child(yol)
	# yanındaki oyuncuya eşya ver
	var yakin := _yakindaki()
	if yakin != 0 and not _env.is_empty():
		var vr := HFlowContainer.new()  # çok eşya varsa alt satıra geçer, tahtadan taşmaz
		vr.add_theme_constant_override("h_separation", 10)
		vr.add_theme_constant_override("v_separation", 8)
		vr.add_child(chalk(tr("Ver: %s") % pname(yakin), 24))
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
		return tr("Izgara: %d. hücre hizası") % no
	return tr("Gevşek tuğla: %d. hücre hizası") % no


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
		_comel(p, true)
		_yer_alti_ol(true))
	_sesc("toprak_dokul", -4.0)


func _yukari_cik(cell: int) -> void:
	if cell < 0:
		return
	var p: CharacterBody3D = w.player
	var c: Node3D = w.cells[cell]
	_karart(0.25, func() -> void:
		_comel(p, false)
		p.global_position = c.klozet_delik.global_position + Vector3(-0.7, 0.05, 0.6)
		p.velocity = Vector3.ZERO
		_yer_alti_ol(false, cell))


# Meşgulken de çömelt / kaldır; yer altında ayağa kalkılamaz (tünel 1.35 m)
func _comel(p: CharacterBody3D, on: bool) -> void:
	p.alcak_tavan = false
	if p.crouched != on:
		var b: bool = p.busy
		p.busy = false
		p.toggle_crouch()
		p.busy = b
	p.alcak_tavan = on


func _yer_alti_ol(on: bool, cell := -1) -> void:
	_yer_alti = on
	if not on and w.player.alcak_tavan:
		w.player.alcak_tavan = false
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


# Aynı karede gelen birden çok olay (coklu, peş peşe kazılar) tüneli bir kez kursun
var _tunel_kirli := false


func _tunel_yenile() -> void:
	if _tunel_kirli:
		return
	_tunel_kirli = true
	(func() -> void:
		_tunel_kirli = false
		_tunel_kur()).call_deferred()


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
	var acik_kuyular := {}
	for i in w.cells.size():
		if w.cells[i].klozet_acik:
			var kq := klozet_kare(i)
			acik_kuyular[anahtar(kq.x, kq.y)] = true
	for anah in _kazilan:
		var pr: PackedStringArray = str(anah).split(",")
		var x := int(pr[0])
		var z := int(pr[1])
		dolu[anah] = true
		var y0 := TY
		var y1 := TY + TH
		# taban ve tavan (açık klozetin kuyusunda tavan yok: yukarıdan hücrenin ışığı süzülür)
		_yuzey(st.zemin, Vector3(x, y0, z), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3.UP, 0.0, carpisma)
		if not acik_kuyular.has(anah):
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

func _sayim_uyari(ms: int, sira: Array = [7, 6, 5, 4, 3, 2, 1, 0], ara := 4000, bakis := 900) -> void:
	var simdi := Time.get_ticks_msec()
	_tur = {"t0": simdi + ms, "sira": sira.map(func(x) -> int: return int(x)), "ara": maxi(ara, 500), "bakis": bakis, "islenen": {}}
	var sirada: int = (_tur.sira as Array).find(_hucrem())
	_sayim_bitis = int(_tur.t0) + maxi(sirada, 0) * int(_tur.ara) + bakis
	_gardiyan_kur()
	if ms < 0:
		return  # geç gelen / yeniden bağlanan: gardiyan zaten koridorda, zil yok
	_sesc("sayim_zili", 0.0)
	_gardiyan_sesi("sayim_geliyor")
	if _yer_alti and _kuklam:
		_bildir("SAYIM GELİYOR", "Kuyuya dön, klozeti kapat." if _klozet_acik else "Kukla yatakta, klozet kapalı.", RED, 3.0)
	elif _yer_alti:
		_bildir("SAYIM GELİYOR", "Gardiyan kapı kapı bakacak. Hücrene dön.", RED, 3.0)
	elif _klozet_acik:
		_bildir("SAYIM GELİYOR", "Klozeti kapat.", RED, 2.6)
	else:
		_bildir("SAYIM GELİYOR", "Gardiyan kapı kapı bakacak.", RED, 2.4)
	Titresim.vur("guclu")


# Gardiyan bir kapının camından baktı (sunucu): hücrede mi, kukla mı, yakalandı mı
func _kontrol(d: Dictionary) -> void:
	var id := int(d.get("id", 0))
	if not _tur.is_empty():
		(_tur.islenen as Dictionary)[id] = true
	var sonuc := str(d.get("sonuc", ""))
	if sonuc == "yakalandi":
		_gardiyan_sesi("sayim_yakaladim")
		if is_instance_valid(_gardiyan_fener):
			_gardiyan_fener.light_color = Color(1.0, 0.45, 0.4)
		_yakalandi_isle(id, str(d.get("neden", "")))
		if id != me():
			_toast(tr("%s yakalandı.") % pname(id))
	elif id == me():
		_sayim_bitis = 0
		if sonuc == "tamam":
			_bildir(tr("GARDİYAN BAKTI"), tr("Sorun yok."), GREEN, 1.6)


# Turun sonu (sunucunun özeti): kapıda işlenmemiş yakalananlar varsa onlar da uygulanır, gardiyan çıkar
func _sayim(yakalanan: Array) -> void:
	_sayim_bitis = 0
	var islenen: Dictionary = _tur.get("islenen", {})
	for id in yakalanan:
		if not islenen.has(int(id)):
			_yakalandi_isle(int(id), "")
	if yakalanan.is_empty() and randf() < 0.5:
		_gardiyan_sesi("sayim_tamam")
	_tunel_kur()
	var tur := _tur
	g.get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if _tur == tur:
			_tur = {}
			_gardiyan_kaldir())


func _yakalandi_isle(id: int, neden: String) -> void:
	var c := _oyuncu_hucresi(id)
	if c >= 0 and c < w.cells.size():
		w.cells[c].klozet_ac(false, false)
		w.cells[c].klozet_vida(0)
		_kukla_goster(c, false)
	if id != me():
		return
	_sayim_bitis = 0
	_eylem_bitir()
	screen_flash(Color(0.9, 0.05, 0.02), 0.8, 0.03, 0.5)
	_bildir("YAKALANDIN", tr("Klozet açıktı. Aletler gitti.") if neden == "klozet" else tr("Hücrende yoktun. Aletler gitti."), RED, 3.0)
	var p: CharacterBody3D = w.player
	if _yer_alti:
		_yer_alti_ol(false, _hucrem())
	_comel(p, false)
	p.global_position = w.cells[_hucrem()].spawn_world()
	p.velocity = Vector3.ZERO
	_vida = 0
	_klozet_acik = false
	_kuklam = false
	_tunel_kur()


# Sayımda gardiyan koridorun ucundan girer, kapıları sırayla dolaşır, her kapının camından feneriyle içeri bakar
func _gardiyan_kur() -> void:
	if is_instance_valid(_gardiyan):
		return
	_gardiyan = BodyScript.new()
	_gardiyan.look = Catalog.sanitize({"govde": "erkek", "kiyafet": "gardiyan", "sapka": "kep", "sakal": "biyik", "sac": "kisa", "ten": 2})
	w.add_child(_gardiyan)
	_gardiyan.visible = false
	_gardiyan_fener = SpotLight3D.new()
	_gardiyan_fener.light_color = Color(0.95, 0.97, 1.0)
	_gardiyan_fener.light_energy = 7.0
	_gardiyan_fener.spot_angle = 18.0
	_gardiyan_fener.spot_range = 7.0
	_gardiyan_fener.visible = false
	w.add_child(_gardiyan_fener)
	# yüzüne vuran zayıf ışık: camın arkasında gardiyanın yüzü seçilsin
	var yuz := OmniLight3D.new()
	yuz.name = "Yuz"
	yuz.light_color = Color(1.0, 0.92, 0.8)
	yuz.light_energy = 0.9
	yuz.omni_range = 1.1
	yuz.position = Vector3(0, 1.62, -0.35)
	_gardiyan.add_child(yuz)
	_gardiyan_kare(0.0)


func _gardiyan_kaldir() -> void:
	if is_instance_valid(_gardiyan):
		_gardiyan.queue_free()
	if is_instance_valid(_gardiyan_fener):
		_gardiyan_fener.queue_free()
	_gardiyan = null


# Kapı camının önü (koridor): gardiyanın durduğu yer
func _kapi_onu(c: int) -> Vector3:
	if c >= 0 and c < w.cells.size():
		return w.cells[c].to_global(KAPI_CAMI)
	return Vector3(KAPI_CAMI.x, 0, (c - 3.5) * HUCRE_ARA + KAPI_CAMI.z)


# Gardiyanın yeri zamana göre hesaplanır (herkeste aynı): t0'da ilk kapıda, her kapıda "dur" kadar bakar, sonra yürür
func _gardiyan_kare(_delta: float) -> void:
	if not is_instance_valid(_gardiyan) or _tur.is_empty():
		return
	var sira: Array = _tur.sira
	var ara := float(_tur.ara)
	var dur := minf(1800.0, ara * 0.45)
	var t := float(Time.get_ticks_msec() - int(_tur.t0))
	var giris := _kapi_onu(int(sira[0])) + Vector3(0, 0, 6.0)
	var pos: Vector3
	var bakiyor := -1
	var yuru := true
	var once: Vector3 = _gardiyan.global_position
	if t < -6000.0:
		_gardiyan.visible = false
		_gardiyan_fener.visible = false
		return
	if t < 0.0:
		pos = giris.lerp(_kapi_onu(int(sira[0])), clampf((t + 6000.0) / 6000.0, 0.0, 1.0))
	else:
		var i := int(t / ara)
		var yerel := t - i * ara
		if i >= sira.size() - 1 and (i >= sira.size() or yerel >= dur):
			# son kapıdan sonra koridorun öbür ucuna yürür, gözden çıkar
			var son := _kapi_onu(int(sira[sira.size() - 1]))
			var gec := t - (sira.size() - 1) * ara - dur
			pos = son + Vector3(0, 0, -gec / 1000.0 * 2.4)
			if gec > 5000.0:
				_gardiyan.visible = false
				_gardiyan_fener.visible = false
				return
		elif yerel < dur:
			pos = _kapi_onu(int(sira[i]))
			bakiyor = int(sira[i])
			yuru = false
		else:
			pos = _kapi_onu(int(sira[i])).lerp(_kapi_onu(int(sira[i + 1])), (yerel - dur) / (ara - dur))
	_gardiyan.visible = true
	_gardiyan.global_position = pos
	# gövdenin önü -z: kapıda cama döner, yürürken gittiği yöne
	var yon: Vector3 = (w.cells[bakiyor].to_global(Vector3(KAPI_CAMI.x - 1.0, 0, KAPI_CAMI.z)) - pos) if bakiyor >= 0 and bakiyor < w.cells.size() else (pos - once)
	yon.y = 0.0
	if yon.length() > 0.001:
		_gardiyan.rotation.y = atan2(-yon.x, -yon.z)
	_gardiyan.set("walk", 1.0 if yuru else 0.0)
	_gardiyan_fener.visible = true
	_gardiyan_fener.global_position = _gardiyan.to_global(Vector3(0.12, 1.5, -0.3))
	if bakiyor >= 0 and bakiyor < w.cells.size():
		# camdan içeri: yatağa ve klozete doğru tarar
		var tarama := sin(t / 300.0) * 0.8
		_gardiyan_fener.look_at(w.cells[bakiyor].to_global(Vector3(-0.9, 0.55, -1.6 + tarama)), Vector3.UP)
	else:
		_gardiyan_fener.look_at(_gardiyan.to_global(Vector3(0, 0.2, -3.0)), Vector3.UP)
		_gardiyan_fener.light_color = Color(0.95, 0.97, 1.0)


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
	p.body.visible = false  # kaçış kamerası kuyunun içinden çıkarken kendi gövdemi görmesin (ormana koşan ayrı gövde)
	_kontroller(false)
	_comel(p, false)
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
		_bildir(tr("KAÇTIN!"), tr("%d. kaçan sensin") % _kactim, GREEN, 3.0)
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
	ay.light_energy = 1.5
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
	if not is_instance_valid(_kam) or _izlenen == 0:
		return
	if _kacanlar.has(_izlenen) or not w.remotes.has(_izlenen):
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
	for c in _kuklalar:
		if is_instance_valid(_kuklalar[c]):
			(_kuklalar[c] as Node).queue_free()
	_kuklalar.clear()
	_kuklam = false
	for id in _kafa_lambalari:
		if is_instance_valid(_kafa_lambalari[id]):
			(_kafa_lambalari[id] as Node).queue_free()
	_kafa_lambalari.clear()
	_fenerliler.clear()
	for d in _defterler + _gizliler:
		if is_instance_valid(d):
			(d as Node).queue_free()
	_defterler.clear()
	_gizliler.clear()
	_acik_parca.clear()
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
		p.body.visible = true
		_comel(p, false)
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
	if ek == "gosterim":
		await _gosterim_oyna(args)
		return
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
	state["klozet"] = {"1": ek in ["klozet", "tunel", "kaz", "kacis", "kazi_el"]}
	on_state(state, true)
	_durum_al({"env": ["caki", "kasik", "tel", "catal"] if ek != "tunel" else ["caki", "kurek", "fener", "maymuncuk"], "vida": 4 if ek in ["klozet", "tunel", "kaz"] else 1,
		"klozet": ek in ["klozet", "tunel", "kaz"], "ipucu": {"tur": "izgara", "z": floori(hucre_z(2))}})
	if ek in ["klozet", "tunel", "kaz", "kazi_el"]:
		w.cells[w.my_cell].klozet_ac(true, false)
	var p: CharacterBody3D = w.player
	match ek:
		"hucre":
			p.global_position = w.cells[w.my_cell].to_global(Vector3(0.3, 0, 0.9))
			p.rotation.y = deg_to_rad(12)
		"yerler":
			# klozet tarafı: tuvalet kağıdı askısı, çöp kutusu; arkada yatakta katlı çarşaf
			p.global_position = w.cells[w.my_cell].to_global(Vector3(-0.2, 0, 0.6))
			p.rotation.y = deg_to_rad(-20)
			p.head.rotation.x = deg_to_rad(-22)
		"zemin":
			p.global_position = w.cells[w.my_cell].to_global(Vector3(0.2, 0, 0.6))
			p.rotation.y = deg_to_rad(-150)
			p.head.rotation.x = deg_to_rad(-45)
		"gardiyan":
			# gardiyan kapımın camından bakıyor (içeriden kapıya bakış)
			var sira := [7, 6, 5, 4, 3, 2, 1, 0]
			_sayim_uyari(-(sira.find(w.my_cell) * 4000) + int(float(args.get("wait", "2.5")) * 1000.0) - 700, sira, 4000, 900)
			_kukla_goster(w.my_cell, true)
			p.global_position = w.cells[w.my_cell].to_global(Vector3(4.6, 0, 3.2) if args.has("koridor") else Vector3(-0.4, 0, 0.5))
			var kd: Vector3 = w.cells[w.my_cell].to_global(Vector3(2.1, 0, 0.5)) - p.global_position
			p.rotation.y = atan2(-kd.x, -kd.z)
			p.head.rotation.x = deg_to_rad(8)
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
			_sayim_uyari(30000)
		"vida":
			w.cells[w.my_cell].klozet_ac(false, false)
			_durum_al({"env": ["caki", "kasik"], "vida": 1, "klozet": false})
			p.global_position = w.cells[w.my_cell].to_global(Vector3(0.95, 0, -1.75))
			p.rotation.y = deg_to_rad(-38)
			p.head.rotation.x = deg_to_rad(-48)
			await g.get_tree().create_timer(0.3).timeout
			do_action("vida")
		"esya":
			p.global_position = w.cells[w.my_cell].to_global(Vector3(-0.6, 0, -1.6))
			p.rotation.y = deg_to_rad(10)
			p.head.rotation.x = deg_to_rad(-25)
			await g.get_tree().create_timer(0.3).timeout
			on_event({"tur": "buldu", "hucre": w.my_cell, "yer": "tugla", "esya": str(args.get("esya", "kasik")), "env": ["caki", str(args.get("esya", "kasik"))]})
		"kukla":
			_kukla_goster(w.my_cell, true)
			p.global_position = w.cells[w.my_cell].to_global(Vector3(0.3, 0, 0.4))
			p.rotation.y = deg_to_rad(40)
			p.head.rotation.x = deg_to_rad(-20)
			_bildir("KUKLA YATAKTA", "Gardiyanı kandırır. Klozeti kapalı tut.", GREEN, 5.0)
		"kazi_el":
			_asagi_in(w.my_cell)
			await g.get_tree().create_timer(0.8).timeout
			p.global_position = Vector3(-4.5, TY + 0.05, kz.y + 3.5)
			p.rotation.y = PI
			_eylem("kaz", 5.0, {"kare": [-5, kz.y + 4]}, tr("Kaşıkla kaz") + "...")


# ---------- gösterim: nasıl kaçılır (sunucusuz; sayımlar atlanır, süreler kısaltılır) ----------
# main.gd: pose=oyunici oyun=kacis ekran=gosterim [cik=1]

func _adim(yazi: String) -> void:
	if not is_instance_valid(_altyazi):
		_altyazi = UI.title("", UI.FS_ORTA + 2, Color.WHITE, true)
		_altyazi.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_altyazi.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_altyazi.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_altyazi.offset_left = -450
		_altyazi.offset_right = 450
		_altyazi.offset_top = -150
		_altyazi.offset_bottom = -70
		_altyazi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var sb := UI.flat(Color(0, 0, 0, 0.72), GOLD, 12)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		_altyazi.add_theme_stylebox_override("normal", sb)
		root().add_child(_altyazi)
	_altyazi.text = yazi


func _bekle(t: float) -> void:
	await g.get_tree().create_timer(t).timeout


# Oyuncuyu bir noktaya bakacak şekilde döndür (gövde sağa sola, baş yukarı aşağı)
func _bak(hedef: Vector3, t := 0.45) -> void:
	var p: CharacterBody3D = w.player
	var goz: Vector3 = p.camera.global_position
	var d: Vector3 = hedef - goz
	var yaw := atan2(-d.x, -d.z)
	var egim := atan2(d.y, Vector2(d.x, d.z).length())
	var y0 := p.rotation.y
	yaw = y0 + wrapf(yaw - y0, -PI, PI)
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "rotation:y", yaw, t).set_trans(Tween.TRANS_SINE)
	tw.tween_property(p.head, "rotation:x", clampf(egim, -1.2, 1.0), t).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _yuru(hedef: Vector3, t: float) -> void:
	var p: CharacterBody3D = w.player
	var tw := p.create_tween()
	tw.tween_property(p, "global_position", hedef, t).set_trans(Tween.TRANS_SINE)
	await tw.finished


# Süren eylemi (çubuk dolar) oynat; bitince sunucuya bir şey gitmez
func _eylem_oyna(tur: String, sure: float, yazi: String) -> void:
	_eylem(tur, sure, {}, yazi)
	while not _is.is_empty():
		await g.get_tree().process_frame
	w.player.busy = true


func _ara_oyna(yer: String, esya: String) -> void:
	var c: Node3D = w.cells[w.my_cell]
	await _bak(c.to_global(YERLER[yer][0]))
	play("dolap" if randf() < 0.5 else "kumas_%d" % randi_range(1, 3), -6.0)
	await _eylem_oyna("ara", 0.7, tr(YERLER[yer][1]) + "...")
	var env := _env.duplicate()
	env.append(esya)
	on_event({"tur": "buldu", "hucre": w.my_cell, "yer": yer, "esya": esya, "env": env})
	await _bekle(1.75)


func _yap_oyna(t: String) -> void:
	var c: Node3D = w.cells[w.my_cell]
	await _bak(c.to_global(DEFTER), 0.35)
	_defter_ac()
	await _bekle(1.8)
	close_panel()
	var env := _env.duplicate()
	for x in TARIFLER[t]:
		env.erase(x)
	env.append(t)
	on_event({"tur": "durum", "env": env, "yapildi": t})
	await _bekle(1.1)


func _kaz_oyna(k: Vector2i, ne := "") -> void:
	var p: CharacterBody3D = w.player
	var su := _ben_kare()
	var yon := k - su
	await _bak(Vector3(su.x + 0.5 + yon.x * 1.5, TY + 1.0, su.y + 0.5 + yon.y * 1.5), 0.3)
	if ne == "kaya":
		on_event({"tur": "sert", "ne": "kaya"})
		await _bekle(1.8)
		return
	var yazi := tr("Izgarayı aç") if ne == "izgara" else tr("Kürekle kaz")
	await _eylem_oyna("kaz", 1.5 if ne == "izgara" else 0.75, yazi + "...")
	on_event({"tur": "kazildi", "id": me(), "kare": [k.x, k.y], "ne": ne})
	await _yuru(Vector3(k.x + 0.5, TY + 0.05, k.y + 0.5), 0.45)
	p.velocity = Vector3.ZERO


func _gosterim_oyna(args: Dictionary) -> void:
	_gosterim = true
	w.set("solo_ring_wait", 1.0e9)  # gösterimde sahte telefon çalmasın
	var kz := klozet_kare(w.my_cell)
	var hat := kz.y + 1  # kayayı dolaştıktan sonra tünelin gittiği sıra
	state["phase"] = "kacis"
	state["harita"] = {"izgara": [hat, hat + 33], "tugla": [hat + 13], "kaya": [anahtar(-4, kz.y), anahtar(-6, hat + 1), anahtar(-12, hat - 1), anahtar(-14, hat + 1)]}
	state["kazilan"] = []
	on_state(state, true)
	_durum_al({"env": [], "vida": 0, "klozet": false, "ipucu": {"tur": "izgara", "z": hat}})
	var p: CharacterBody3D = w.player
	var c: Node3D = w.cells[w.my_cell]
	p.busy = true
	# gösterimde yürüme kolu ve hareket düğmeleri gizli; eylem düğmesi (neye basılacağı) görünür
	w.hud.set("izleyici", true)
	if w.hud.get("joy") is CanvasItem:
		(w.hud.get("joy") as CanvasItem).visible = false
	p.global_position = c.to_global(Vector3(0.0, 0, 0.6))
	p.rotation.y = 0.0
	await _bekle(1.0)
	_adim(tr("NASIL KAÇILIR?"))
	await _bekle(2.2)
	# 1) ara
	_adim(tr("1) Gizli yerleri ara"))
	await _ara_oyna("yatak", "caki")
	await _ara_oyna("tugla", "kasik")
	await _ara_oyna("havalandirma", "tahta")
	await _ara_oyna("poster", "bant")
	# 2) aletler
	_adim(tr("2) Defterden KÜREK yap"))
	await _yap_oyna("kurek")
	_adim(tr("Aramaya devam"))
	await _ara_oyna("dolap", "pil")
	await _ara_oyna("bilgisayar", "ampul")
	await _ara_oyna("kitaplik", "tel")
	_adim(tr("Pil + Ampul + Tel = FENER"))
	await _yap_oyna("fener")
	await _ara_oyna("koltuk", "tel")
	await _ara_oyna("yastik", "catal")
	_adim(tr("Tel + Çatal = MAYMUNCUK"))
	await _yap_oyna("maymuncuk")
	# 3) kukla: tuvalet kağıtları + çarşaf
	_adim(tr("3) Tuvalet kağıdı ve çarşaftan kukla"))
	await _ara_oyna("tuvalet", "kagit")
	await _ara_oyna("cop", "kagit")
	await _ara_oyna("carsaf", "carsaf")
	_adim(tr("Kağıt + Kağıt + Çarşaf = KUKLA"))
	await _yap_oyna("kukla")
	await _bak(c.to_global(KUKLA_YER), 0.4)
	play("kumas_%d" % randi_range(1, 3), -4.0)
	await _eylem_oyna("kukla", 1.4, tr("Kukla yatırılıyor..."))
	var env_k := _env.duplicate()
	env_k.erase("kukla")
	_durum_al({"env": env_k})
	on_event({"tur": "kukla", "id": me(), "hucre": w.my_cell, "on": true})
	await _bekle(2.4)
	# 4) klozet: vidalar tek tek
	_adim(tr("4) Klozetin vidalarını sök"))
	await _bak(c.klozet_world(), 0.4)
	await _yuru(c.to_global(Vector3(0.95, 0, -1.7)), 1.0)
	for i in 4:
		await _bak(c.klozet_vida_yeri(i) + Vector3(0, 0.02, 0), 0.35)
		_sesc("vida", -2.0)
		c.klozet_vida_sok(i, 0.7)
		await _eylem_oyna("vida", 0.7, tr("Vida sökülüyor..."))
		_durum_al({"vida": i + 1})
		on_event({"tur": "vida", "id": me(), "n": i + 1})
		await _bekle(0.35)
	_adim(tr("Klozeti çek, aşağı in"))
	_klozet_acik = true
	on_event({"tur": "klozet", "id": me(), "hucre": w.my_cell, "acik": true, "kare": [kz.x, kz.y]})
	await _bekle(1.2)
	await _bak(c.klozet_delik.global_position, 0.4)
	await _bekle(0.6)
	_asagi_in(w.my_cell)
	await _bekle(1.0)
	p.busy = true
	_adim(tr("Klozeti alttan kapat"))
	await _bak(p.camera.global_position + Vector3(0.05, 2.0, 0.0), 0.4)
	_klozet_acik = false
	on_event({"tur": "klozet", "id": me(), "hucre": w.my_cell, "acik": false, "kare": [kz.x, kz.y]})
	await _bekle(1.8)
	# 5) kaz: batıya, kayayı dolaş, temeldeki ızgarayı aç, tel örgünün ötesine
	_adim(tr("5) Batıya kaz"))
	var yol: Array = []
	for x in range(kz.x - 1, -4, -1):
		yol.append([Vector2i(x, kz.y), ""])
	yol.append([Vector2i(-4, kz.y), "kaya"])
	yol.append([Vector2i(-3, hat), ""])
	for x in range(-4, TEMEL_X, -1):
		yol.append([Vector2i(x, hat), ""])
	yol.append([Vector2i(TEMEL_X, hat), "izgara"])
	for x in range(TEMEL_X - 1, CIT_X - 2, -1):
		yol.append([Vector2i(x, hat), ""])
	for adim in yol:
		var k: Vector2i = adim[0]
		var ne: String = adim[1]
		if ne == "kaya":
			_adim(tr("Kaya: yandan dolaş"))
		elif k == Vector2i(-4, hat):
			_adim(tr("SAYIM! Kukla seni kurtarır"))
			on_event({"tur": "sayim_uyari", "ms": 9000})
		elif k == Vector2i(-7, hat):
			on_event({"tur": "sayim", "yakalanan": []})
			on_event({"tur": "kandirdi"})
		elif k.x == TEMEL_X + 1:
			_adim(tr("6) Izgarayı maymuncukla aç"))
		elif k.x == TEMEL_X - 1:
			_adim(tr("7) Örgünün ötesine kaz"))
		await _kaz_oyna(k, ne)
	# 5) yukarı kaz, kaç
	_adim(tr("8) YUKARI kaz"))
	var son := _ben_kare()
	await _bak(Vector3(son.x + 0.5, TY + 3.0, son.y + 0.4), 0.4)
	for i in 2:
		await _eylem_oyna("yukari", 1.0, tr("Yukarı kazıyorsun..."))
		on_event({"tur": "yukari", "n": i + 1})
		await _bekle(1.0)
	await _eylem_oyna("yukari", 1.0, tr("Yukarı kazıyorsun..."))
	_adim(tr("KAÇTIN!"))
	on_event({"tur": "kacti", "id": me(), "sira": 1, "kare": [son.x, son.y]})
	await _bekle(5.5)
	_adim(tr("Sayımda: hücrende ol ya da kukla yatır ve klozeti kapat (gardiyan kuklayı bazen fark eder)"))
	await _bekle(3.5)
	if str(args.get("cik", "")) == "1":
		g.get_tree().quit()


# ---------- sade bildirim (büyük flaş yerine: üstte küçük kutu, kendiliğinden söner) ----------

func _bildir(baslik: String, alt := "", renk := GOLD, sure := 1.8) -> void:
	if not is_instance_valid(_bildirim):
		_bildirim = PanelContainer.new()
		_bildirim.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_bildirim.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_bildirim.offset_top = 156
		_bildirim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kutu := VBoxContainer.new()
		kutu.add_theme_constant_override("separation", 0)
		kutu.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bildirim_bas = UI.title("", UI.FS_ORTA, renk, true)
		_bildirim_alt = UI.title("", UI.FS_METIN, Color(0.92, 0.9, 0.84), true)
		kutu.add_child(_bildirim_bas)
		kutu.add_child(_bildirim_alt)
		_bildirim.add_child(kutu)
		root().add_child(_bildirim)
	var sb := UI.flat(Color(0.04, 0.035, 0.03, 0.8), Color(renk, 0.8), 10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 5
	sb.content_margin_bottom = 6
	_bildirim.add_theme_stylebox_override("panel", sb)
	_bildirim_bas.text = tr(baslik)
	_bildirim_bas.add_theme_color_override("font_color", renk)
	_bildirim_alt.text = tr(alt)
	_bildirim_alt.visible = alt != ""
	_bildirim.reset_size()
	_bildirim.offset_left = -_bildirim.get_combined_minimum_size().x / 2.0
	_bildirim.offset_right = -_bildirim.offset_left
	_bildirim.visible = true
	_bildirim.modulate.a = 1.0
	if _bildirim_tw and _bildirim_tw.is_valid():
		_bildirim_tw.kill()
	_bildirim_tw = _bildirim.create_tween()
	_bildirim_tw.tween_interval(sure)
	_bildirim_tw.tween_property(_bildirim, "modulate:a", 0.0, 0.35)
	_bildirim_tw.tween_callback(func() -> void: _bildirim.visible = false)


# ---------- eşyalar: 3B küçük modeller (uzun ekseni -z, tutma yeri başlangıçta) ----------

func _malzeme(renk: Color, metal := 0.0, puruz := 0.7, isik := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = renk
	m.metallic = metal
	m.roughness = puruz
	if isik > 0.0:
		m.emission_enabled = true
		m.emission = Color(renk.r, renk.g, renk.b)
		m.emission_energy_multiplier = isik
	return m


func _parca(kok: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, olcek := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = olcek
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kok.add_child(mi)
	return mi


func _kutu(b: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = b
	return bm


func _silindir(r: float, h: float, r2 := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0.0 else r2
	c.height = h
	c.radial_segments = 14
	return c


func _halka(ic: float, dis: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = ic
	t.outer_radius = dis
	t.rings = 18
	t.ring_segments = 8
	return t


func _esya_mesh(ad: String) -> Node3D:
	var kok := Node3D.new()
	var celik := _malzeme(Color(0.78, 0.79, 0.8), 0.9, 0.28)
	var ahsap := _malzeme(Color(0.5, 0.34, 0.2), 0.0, 0.85)
	var bakir := _malzeme(Color(0.8, 0.45, 0.22), 0.85, 0.35)
	var siyah := _malzeme(Color(0.05, 0.05, 0.055), 0.2, 0.5)
	var boy := Vector3(PI / 2.0, 0, 0)  # silindiri -z boyunca yatır
	match ad:
		"caki":
			_parca(kok, _kutu(Vector3(0.024, 0.016, 0.09)), _malzeme(Color(0.78, 0.06, 0.05), 0.1, 0.35), Vector3(0, 0, -0.02))
			_parca(kok, _kutu(Vector3(0.013, 0.0035, 0.075)), celik, Vector3(0, 0.003, -0.1))
		"kasik":
			_parca(kok, _kutu(Vector3(0.012, 0.004, 0.13)), celik, Vector3(0, 0, -0.03))
			var kase := SphereMesh.new()
			kase.radius = 0.022
			kase.height = 0.044
			_parca(kok, kase, celik, Vector3(0, 0.002, -0.115), Vector3.ZERO, Vector3(1.0, 0.28, 1.45))
		"catal":
			_parca(kok, _kutu(Vector3(0.012, 0.004, 0.12)), celik, Vector3(0, 0, -0.03))
			_parca(kok, _kutu(Vector3(0.026, 0.004, 0.02)), celik, Vector3(0, 0, -0.095))
			for i in 4:
				_parca(kok, _kutu(Vector3(0.0035, 0.0035, 0.045)), celik, Vector3(-0.0105 + i * 0.007, 0, -0.125))
		"tahta":
			_parca(kok, _kutu(Vector3(0.07, 0.02, 0.32)), ahsap, Vector3(0, 0, -0.1))
		"bant":
			_parca(kok, _halka(0.022, 0.042), _malzeme(Color(0.66, 0.67, 0.7), 0.3, 0.55), Vector3(0, 0, -0.04), Vector3(PI / 2.0, 0, 0), Vector3(1, 0.55, 1))
		"pil":
			_parca(kok, _silindir(0.013, 0.05), siyah, Vector3(0, 0, -0.03), boy)
			_parca(kok, _silindir(0.0132, 0.012), bakir, Vector3(0, 0, -0.051), boy)
			_parca(kok, _silindir(0.005, 0.006), celik, Vector3(0, 0, -0.06), boy)
		"ampul":
			var cam := SphereMesh.new()
			cam.radius = 0.026
			cam.height = 0.06
			var cm := _malzeme(Color(1.0, 0.97, 0.85), 0.0, 0.05, 0.6)
			cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cm.albedo_color.a = 0.55
			_parca(kok, cam, cm, Vector3(0, 0, -0.06))
			_parca(kok, _silindir(0.011, 0.022), celik, Vector3(0, 0, -0.026), boy)
		"tel":
			for i in 3:
				_parca(kok, _halka(0.024, 0.0275), bakir, Vector3(0, 0, -0.04 - i * 0.004), Vector3(PI / 2.0, 0, 0))
		"kurek":
			_parca(kok, _silindir(0.012, 0.22), ahsap, Vector3(0, 0, -0.05), boy)
			_parca(kok, _halka(0.012, 0.017), _malzeme(Color(0.6, 0.6, 0.62), 0.2, 0.6), Vector3(0, 0, -0.15), Vector3(PI / 2.0, 0, 0))
			_parca(kok, _kutu(Vector3(0.09, 0.008, 0.11)), celik, Vector3(0, 0, -0.21), Vector3(0.12, 0, 0))
		"fener":
			_parca(kok, _silindir(0.017, 0.1), siyah, Vector3(0, 0, -0.04), boy)
			_parca(kok, _silindir(0.022, 0.03, 0.017), siyah, Vector3(0, 0, -0.1), boy)
			_parca(kok, _silindir(0.02, 0.004), _malzeme(Color(1, 1, 0.92), 0.0, 0.1, 2.0), Vector3(0, 0, -0.116), boy)
		"maymuncuk":
			_parca(kok, _kutu(Vector3(0.0045, 0.0045, 0.1)), celik, Vector3(0, 0, -0.04))
			_parca(kok, _kutu(Vector3(0.0045, 0.0045, 0.028)), celik, Vector3(0.008, 0, -0.098), Vector3(0, 0.5, 0))
			_parca(kok, _kutu(Vector3(0.016, 0.006, 0.03)), bakir, Vector3(0, 0, 0.005))
		"kagit":
			var kb := _malzeme(Color(0.95, 0.94, 0.9), 0.0, 0.95)
			_parca(kok, _silindir(0.05, 0.095), kb, Vector3(0, 0, -0.06))
			_parca(kok, _silindir(0.019, 0.097), _malzeme(Color(0.55, 0.42, 0.28), 0.0, 0.9), Vector3(0, 0, -0.06))
		"carsaf":
			_parca(kok, _kutu(Vector3(0.2, 0.05, 0.16)), _malzeme(Color(0.86, 0.85, 0.8), 0.0, 1.0), Vector3(0, 0, -0.08))
		"kukla":
			var kb2 := _malzeme(Color(0.95, 0.94, 0.9), 0.0, 0.95)
			for i in 3:
				_parca(kok, _silindir(0.04, 0.08), kb2, Vector3(-0.04 + i * 0.04, 0, -0.08), boy)
			_parca(kok, _kutu(Vector3(0.18, 0.03, 0.14)), _malzeme(Color(0.86, 0.85, 0.8), 0.0, 1.0), Vector3(0, -0.04, -0.08))
	return kok


# Bulunan eşya saklandığı yerden ele uçar, elde biraz tutulur (döndürülür), sonra cebe girer
func _al_animasyonu(yer: Vector3, esya: String, d: Dictionary) -> void:
	_durum_al(d)  # envanter hemen güncellenir; animasyon yalnız görsel (yarıda kesilse de eşya cepte)
	var cam: Camera3D = w.player.camera
	if yer == Vector3.ZERO or not is_instance_valid(cam):
		return
	_elden_birak()
	var n := _esya_mesh(esya)
	w.add_child(n)
	n.global_position = yer
	n.look_at(cam.global_position, Vector3.UP)
	_eldeki = n
	_el_pozu(true)
	var bas := n.global_position
	var tw := n.create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(cam):
			return
		var hedef := cam.to_global(ELDE + Vector3(-0.06, 0.04, 0.0))
		n.global_position = bas.lerp(hedef, t) + Vector3(0, sin(t * PI) * 0.12, 0)
		n.global_basis = n.global_basis.slerp(cam.global_basis * Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, 0.35), t), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(n) and is_instance_valid(cam):
			_onde_ciz(n)
			n.reparent(cam, true))
	tw.tween_property(n, "rotation:y", n.rotation.y + 0.9, 0.85).set_trans(Tween.TRANS_SINE)
	tw.tween_property(n, "position", Vector3(0.3, 0.17, -0.5), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(n, "scale", Vector3.ONE * 0.2, 0.28)
	tw.tween_callback(func() -> void:
		if _eldeki == n:
			_elden_birak()
		elif is_instance_valid(n):
			n.queue_free()
		_esya_parlat())


# Envanterdeki son eşya kısa parlar (cebe girdi)
func _esya_parlat() -> void:
	if not is_instance_valid(_esya_bar) or _esya_bar.get_child_count() == 0:
		return
	var son := _esya_bar.get_child(_esya_bar.get_child_count() - 1) as Control
	son.pivot_offset = son.size / 2.0
	var tw := son.create_tween()
	tw.tween_property(son, "scale", Vector2.ONE * 1.25, 0.12)
	tw.tween_property(son, "scale", Vector2.ONE, 0.2)


# Aleti eline al (kazarken kaşık / kürek, vidada çakı): kameraya bağlı, sağ altta
func _ele_al(ad: String) -> void:
	_elden_birak()
	var cam: Camera3D = w.player.camera
	if not is_instance_valid(cam):
		return
	var n := _esya_mesh(ad)
	_onde_ciz(n)
	cam.add_child(n)
	n.position = ELDE
	n.rotation = Vector3(-0.95 if ad == "caki" else -0.3, 0.12, 0.0)
	_eldeki = n
	_el_pozu(true)


# Elde tutulan eşya duvara girse de görünsün (birinci şahıs oyunlarındaki gibi hep önde çizilir)
func _onde_ciz(n: Node3D) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m:
			m = m.duplicate()
			m.no_depth_test = true
			m.render_priority = 10
			(mi as MeshInstance3D).material_override = m


func _elden_birak() -> void:
	if is_instance_valid(_eldeki):
		_eldeki.queue_free()
	_eldeki = null
	_el_pozu(false)


# Sağ el, eldeki eşyayı tutuyormuş gibi öne gelir (birinci şahısta görünür)
func _el_pozu(on: bool) -> void:
	var p = w.player if w else null
	if not p or not p.has_method("set_hand_pose"):
		return
	if on:
		p.set_hand_pose(1, {"p": ELDE + Vector3(0.0, -0.025, 0.07), "f": Vector3(-0.1, -0.2, -1.0), "u": Vector3(0.0, 1.0, 0.0), "e": Vector3(0.35, -1.0, 0.1), "c": [0.9, 0.7, 1.0, 1.0, 1.0], "r": 12.0})
	else:
		p.set_hand_pose(1, "")


# ---------- kukla: yatakta battaniyenin altında yatan biri gibi ----------

func _kukla_goster(cell: int, on: bool) -> void:
	if cell < 0 or cell >= w.cells.size():
		return
	if not on:
		if _kuklalar.has(cell) and is_instance_valid(_kuklalar[cell]):
			(_kuklalar[cell] as Node).queue_free()
		_kuklalar.erase(cell)
		return
	if _kuklalar.has(cell) and is_instance_valid(_kuklalar[cell]):
		return
	var kok := Node3D.new()
	w.cells[cell].add_child(kok)
	_kuklalar[cell] = kok
	# tuvalet kağıdı rulolarından gövde, üstünde çarşaf; başı yastıkta iki rulo (karanlıkta camdan uyuyan biri gibi)
	var ortu := _malzeme(Color(0.8, 0.79, 0.74), 0.0, 1.0)
	var kagit := _malzeme(Color(0.95, 0.94, 0.9), 0.0, 0.95)
	var govde := CapsuleMesh.new()
	govde.radius = 0.19
	govde.height = 1.3
	_parca(kok, govde, ortu, Vector3(-1.5, 0.66, -1.62), Vector3(PI / 2.0, 0, 0), Vector3(1.15, 1.0, 0.62))
	var bacak := CapsuleMesh.new()
	bacak.radius = 0.1
	bacak.height = 0.5
	_parca(kok, bacak, ortu, Vector3(-1.38, 0.64, -1.05), Vector3(PI / 2.0, 0.06, 0), Vector3(1.0, 1.0, 0.7))
	for i in 2:
		_parca(kok, _silindir(0.065, 0.1), kagit, Vector3(-1.5 + (i - 0.5) * 0.07, 0.7, -2.36), Vector3(0, 0, PI / 2.0))
	# çarşafın altından görünen bir rulo ucu (ayak ucu)
	_parca(kok, _silindir(0.05, 0.09), kagit, Vector3(-1.33, 0.62, -0.84), Vector3(PI / 2.0, 0, 0))


# ---------- kafa feneri: fener yapanın kafasında lamba (başkaları da görür, tünelde yanar) ----------

func _fener_listesi(ids) -> void:
	_fenerliler.clear()
	if ids is Array:
		for id in ids:
			_fenerliler[int(id)] = true
	_kafa_lambalarini_guncelle()


func _kafa_lambalarini_guncelle() -> void:
	for id in _kafa_lambalari.keys():
		if not _fenerliler.has(id) or not w.remotes.has(id) or not is_instance_valid(_kafa_lambalari[id]):
			if is_instance_valid(_kafa_lambalari[id]):
				(_kafa_lambalari[id] as Node).queue_free()
			_kafa_lambalari.erase(id)
	for id in _fenerliler:
		if id == me() or not w.remotes.has(id):
			continue
		var r: Dictionary = w.remotes[id]
		if not _kafa_lambalari.has(id):
			var bas = (r.body as Node).get("_head")
			if not (bas is Node3D) or not is_instance_valid(bas):
				continue
			_kafa_lambalari[id] = _kafa_lambasi(bas)
		var lamba: Node3D = _kafa_lambalari[id]
		var isik := lamba.get_node_or_null("Isik") as SpotLight3D
		if isik:
			isik.visible = (r.root as Node3D).global_position.y < -0.5


func _kafa_lambasi(bas: Node3D) -> Node3D:
	var kok := Node3D.new()
	kok.name = "KafaLambasi"
	bas.add_child(kok)
	# kafa çerçevesi: yüz -z, yarıçap ~0.115
	_parca(kok, _halka(0.112, 0.124), _malzeme(Color(0.08, 0.08, 0.09), 0.0, 0.7), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.0, 0.35, 1.08))
	_parca(kok, _kutu(Vector3(0.05, 0.034, 0.026)), _malzeme(Color(0.1, 0.1, 0.11), 0.3, 0.5), Vector3(0, 0.035, -0.132))
	_parca(kok, _silindir(0.013, 0.006), _malzeme(Color(1, 1, 0.92), 0.0, 0.1, 3.0), Vector3(0, 0.035, -0.147), Vector3(PI / 2.0, 0, 0))
	var isik := SpotLight3D.new()
	isik.name = "Isik"
	isik.light_color = Color(0.95, 0.95, 1.0)
	isik.light_energy = 3.0
	isik.spot_range = 9.0
	isik.spot_angle = 26.0
	isik.position = Vector3(0, 0.035, -0.16)
	isik.visible = false
	kok.add_child(isik)
	return kok
