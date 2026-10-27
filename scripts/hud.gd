# Oyun içi ekran: joystick, eylem düğmesi, EĞİL / HAREKET, nişan noktası, süre, bildirimler,
# bekleme salonu (oda kodu, oyuncu kartları, HAZIRIM / BAŞLAT), telefon rehberi ve arama şeridi.
# Tasarım takımı: scripts/ui.gd (docs/TASARIM.md). Oyuncu avatarı / şikayet: scripts/oyuncu_ui.gd
extends CanvasLayer

signal action_pressed
signal contact_chosen(id: int)
signal settings_pressed
signal emote_chosen(id: String)
signal crouch_pressed
signal ptt_changed(down: bool)
signal lobby_ready(on: bool)
signal lobby_start
signal lobby_invite
signal lobby_leave
signal lobby_bot(add: bool)  # kurucu: bot ekle / çıkar
signal hangup_pressed  # arama şeridindeki kapat düğmesi

const UI := preload("res://scripts/ui.gd")
const OU := preload("res://scripts/oyuncu_ui.gd")
const OdalarUI := preload("res://scripts/odalar.gd")  # lobideki oda bilgisi şeridi + ODA AYARI penceresi
const Catalog := preload("res://scripts/catalog.gd")
const Dil := preload("res://scripts/dil.gd")
const JOY_R := 85.0
const JOY_HOME := Vector2(50, -280)
const MAX_OYUNCU := 8
# Sağ başparmak kümesi (1280x720 tabanında, sağ alt köşeye göre). Ana EYLEM köşeye en yakın ve en büyük;
# diğerleri onun çevresinde bir yay üstünde: EĞİL solunda, HAREKET sol üstünde, BAS KONUŞ tam üstünde.
const EYLEM_PX := 168.0
const EYLEM_OFS := Vector2(-200, -216)  # sol üst köşe (merkez: sağdan ~136, alttan ~132)
const EGIL_PX := 104.0
const EGIL_OFS := Vector2(-350, -150)
const HAREKET_PX := 104.0
const HAREKET_OFS := Vector2(-296, -334)
const KONUS_PX := 124.0
const KONUS_OFS := Vector2(-178, -380)
const AYAR_PX := 76.0
const MIK_PX := 92.0  # mikrofon aç/kapa düğmesi (salonda ve maçta hep görünür, ayarların altında)
const MIK_OFS := Vector2(8, 88)
const PILL_AV := 66.0  # arama şeridindeki avatar

var floating_joy := true  # joystick parmağın değdiği yerde açılır
var sprint := false  # joystick yukarıdaki KOŞ halkasında
var gems_label: Label
var emote_btn: Button
var crouch_btn: Button
var ptt_btn: Button
var fps_label: Label
# kurucunun seçtiği oyun ("" = hepsi sırayla)
const GAME_CHOICES := [["", "TÜM OYUNLAR"], ["tahta", "KARA TAHTA"], ["devre", "KISA DEVRE"], ["kimkim", "KİM KİM?"], ["yalanci", "YALANCI"], ["rulet", "RUS RULETİ"], ["c4", "C4"], ["ortalama", "ORTALAMA SAYI"]]
var game_pick := 0
var _ready_on := false
var _game_pills: Array[Control] = []
var emote_panel: PanelContainer
var emote_grid: GridContainer
var _emote_kay: ScrollContainer
var mik: Mik  # mikrofon göstergesi (sol üst)
var _mik_dokunus := -1000  # son dokunuşun zamanı (ms): tek dokunuşun çift olayı mikrofonu iki kez çevirmesin
var mik_kapali := false  # oyuncu kendi mikrofonunu kapattı (göstergeye dokununca)
var _ptt_dalga: Dalga  # BAS KONUŞ basılıyken yeşil dalga
var _ptt_zorla := false  # main.gd set_ptt(true): telefonda bas-konuş
var _mik_test := ""  # test: mik=konusuyor|kapali|bekle|susturuldu|acik (göstergeyi zorla)
var _sinyal: Sinyal  # zayıf bağlantı göstergesi (mikrofonun altında)
var _ping_test := -1  # test: ping=1 (zayıf) | ping=2 (kötü)
var _ptt_test := false  # test: ptt=1 (BAS KONUŞ hep görünür)
var _isaret: Isaret  # oyunda gidilecek yeri gösteren işaret
var _ulasilan := {}  # bu turda varılmış tek seferlik hedefler ("görev:tur:ad")
var _aradi := ""  # bu turda en az bir kez telefonda konuşuldu ("görev:tur")
var _hedef_test: Array = []  # test: hedef=telefon|tahta|kutu|dolap (zorla)
# tek seferlik kısa ipuçları (ilk kez gereken anda; görülenler user://ipuclari.cfg'de)
const IPUCU_DOSYA := "user://ipuclari.cfg"
var _ipucu_kat: CanvasLayer
var _ipucu_acik: Control
var _ipucu_hep := false  # test: ipucu=hep (görülmüş olsa da göster, kaydetme)
var _ipucu_yok := false  # otomatik test (shot= / auto=): ipucu gösterme, kaydetme
var _ipucu_cfg: ConfigFile
var _tap_blockers: Array[Control] = []

var player: Node  # main.gd bağlar
var move := Vector2.ZERO

var joy: Joy
var joy_index := -1
var look_index := -1

var action_btn: Button
var prompt_label: Label
var timer_label: Label
var timer_pill: PanelContainer
var _last_sec := -1
var _tick: AudioStreamPlayer
var ring_label: Label  # main.gd yazar ("Telefon çalıyor: Ali" + visible); arama şeridi bunu izler
var call_panel: PanelContainer  # altyazı balonu (çevrimdışı konuşmada karşı tarafın sözleri)
var call_title: Label
var call_text: Label
var hint: Label
var avatars: HBoxContainer
var round_pill: PanelContainer
var contacts: Control
var contact_list: GridContainer

var _root: Control
var _ust: Control  # modal ve menüler (açıkken joystick / bakış çalışmaz)
var _toast_host: Control
var _toast: Control
var _t := 0.0

# eylem düğmesi
var _action_text := ""
var _action_label: Label
var _action_icon: TextureRect
var _action_halo: Panel
var _action_shake: Tween

# telefon şeridi (sağ üst, oyun panellerinin de üstünde)
var _tel: CanvasLayer
var _tel_kok: Control
var _pill: PanelContainer
var _pill_style: StyleBoxFlat
var _pill_avatar_kutu: Control
var _pill_dalga: Dalga
var _pill_ad: Label
var _pill_durum: Label
var _pill_kapat: Button
var _pill_sikayet: Button
var _call_state := ""  # "" / caliyor / ariyor / baglaniyor / hatta
var _call_who := ""
var _call_t := 0.0
var _call_time_text := ""

# bekleme salonu
var lobby_panel: Control  # bekleme salonu katmanı (oda kartı + oyuncu kartları + alt düğmeler)
var _lobby_card: PanelContainer
var _lobby_code: Label
var _lobby_code_text := ""
var _lobby_ready_lbl: Label
var _lobby_count_row: Control
var _lobby_count_num: Label
var _lobby_count_bar: UI.Cubuk
var _lobby_host_box: VBoxContainer
var _lobby_game_btn: Button
var _lobby_bot_num: Label
var _lobby_bot_minus: Button
var _lobby_bot_plus: Button
var _lobby_strip: HBoxContainer
var _lobby_bar: HBoxContainer
var _lobby_ready_btn: Button
var _lobby_start_btn: Button
var _lobby_invite_btn: Button
var _lobby_ids: Array = []
var _lobby_oda: Button  # oda bilgisi şeridi (odalar.gd lobi_bilgi)
var _lobby_host := false
var _public_left := -1.0
var _public_total := 30.0
var _lobby_count_lbl: Label  # "sn içinde başlıyor" / "Herkes hazır olunca başlar"
var _lobby_count_cr: Control
var _lobby_son: Array = []  # son update_lobby bağımsız değişkenleri (mikrofon değişince kartlar yenilensin)


# ---------------------------------------------------------------- joystick

class Joy extends Control:
	var knob := Vector2.ZERO
	var sprint := false
	var active := false

	func _draw() -> void:
		var c := size / 2.0
		# taban: koyu disk + krem halka + amber yön okları
		draw_circle(c, 92.0, Color(0, 0, 0, 0.16))
		draw_circle(c, 86.0, Color(0.03, 0.04, 0.04, 0.42))
		draw_arc(c, 86.0, 0.0, TAU, 72, Color(0.95, 0.92, 0.85, 0.45), 4.0, true)
		draw_arc(c, 62.0, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 2.0, true)
		for a in [0.0, PI / 2.0, PI, PI * 1.5]:
			var d := Vector2.from_angle(a)
			var p := c + d * 72.0
			var side := d.orthogonal() * 8.0
			draw_colored_polygon(PackedVector2Array([p + d * 9.0, p + side, p - side]), Color(1, 0.69, 0.13, 0.8 if active else 0.5))
		if active:
			# yukarıdaki halkaya itince hızlı koşma
			var sc := c + Vector2(0, -225)
			draw_circle(sc, 42.0, Color(1, 0.69, 0.13, 0.9 if sprint else 0.2))
			draw_arc(sc, 42.0, 0.0, TAU, 48, Color(1, 0.82, 0.4, 0.95), 3.0, true)
			var f: Font = UI.TITLE_FONT
			if not sprint:
				draw_string_outline(f, sc + Vector2(-42, 8), tr("KOŞ"), HORIZONTAL_ALIGNMENT_CENTER, 84, 22, 5, Color(0, 0, 0, 0.7))
			draw_string(f, sc + Vector2(-42, 8), tr("KOŞ"), HORIZONTAL_ALIGNMENT_CENTER, 84, 22, Color("#1a1206") if sprint else Color.WHITE)
			for i in 2:
				var y := sc.y - 52.0 - i * 12.0
				draw_polyline(PackedVector2Array([Vector2(sc.x - 10, y + 6), Vector2(sc.x, y - 2), Vector2(sc.x + 10, y + 6)]), Color(1, 0.82, 0.4, 0.8 - i * 0.3), 3.0, true)
		# topuz: gölge + açık çelik + amber göbek
		var k := c + knob
		draw_circle(k + Vector2(0, 4), 38.0, Color(0, 0, 0, 0.35))
		draw_circle(k, 38.0, Color("#ffb020") if sprint else Color(0.74, 0.75, 0.72, 0.95))
		draw_circle(k + Vector2(0, -4), 31.0, Color("#ffd36b") if sprint else Color(0.9, 0.9, 0.87, 0.95))
		draw_arc(k, 38.0, 0.0, TAU, 48, Color(0, 0, 0, 0.45), 2.0, true)
		draw_circle(k, 9.0, Color("#b86f00") if sprint else Color(1, 0.69, 0.13, 0.9 if active else 0.6))


# Arama şeridindeki avatarın arkasında yayılan halkalar (arıyor / çalıyor).
class Dalga extends Control:
	var renk := Color.WHITE
	var acik := false
	var taban := 26.0  # ilk halkanın yarıçapı
	var _t := 0.0

	func _process(delta: float) -> void:
		if acik:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		if not acik:
			return
		var c := size / 2.0
		for i in 3:
			var f := fmod(_t * 0.9 + i / 3.0, 1.0)
			draw_arc(c, taban + f * 28.0, 0.0, TAU, 48, Color(renk, (1.0 - f) * 0.8), 3.0, true)


# Bağlantı çubukları (sinyal): seviye 0-4 dolu çubuk; cizik: kırmızı çapraz çizgi (bağlantı koptu).
# Bildirimlerde ve sol üstteki zayıf bağlantı göstergesinde kullanılır.
class Sinyal extends Control:
	var seviye := 4
	var renk := Color("#4cc23a")
	var cizik := false
	var zemin := false  # koyu yuvarlak zemin (tek başına dururken okunsun)

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) / 2.0
		if zemin:
			draw_circle(size / 2.0, s * 0.5, Color(0.03, 0.04, 0.04, 0.82))
			draw_arc(size / 2.0, s * 0.5 - 1.5, 0.0, TAU, 32, Color(renk, 0.9), 3.0, true)
			s *= 0.62
			o = (size - Vector2(s, s)) / 2.0
		var w := s / 5.5
		for i in 4:
			var h := s * (0.3 + 0.7 * (i + 1) / 4.0)
			var r := Rect2(o + Vector2(i * w * 1.45, s - h), Vector2(w, h))
			draw_rect(r.grow(1.5), Color(0, 0, 0, 0.7))
			draw_rect(r, renk if i < seviye else Color(0.45, 0.47, 0.45, 0.6))
		if cizik:
			draw_line(o + Vector2(s * 0.05, s * 0.05), o + Vector2(s * 0.95, s * 0.95), Color(0, 0, 0, 0.8), 6.0, true)
			draw_line(o + Vector2(s * 0.05, s * 0.05), o + Vector2(s * 0.95, s * 0.95), Color("#ff5a4e"), 3.5, true)


# Mikrofon göstergesi (sol üst). durum: acik (dinliyor), konusuyor (ses gidiyor: yeşil dalga),
# bekle (bas-konuş açık, düğmeye basılmıyor: soluk), kapali (oyuncu kapattı: kırmızı çizik),
# susturuldu (oyun susturdu, ör. rulette ölü: gri çizik).
class Mik extends Control:
	var durum := "acik"
	var seviye := 0.0  # 0..1 (yumuşatılmış)
	var _t := 0.0
	var _ikon: Texture2D

	func _ready() -> void:
		_ikon = UI.icon_texture("mikrofon", 96)

	func _process(delta: float) -> void:
		_t += delta
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.36
		var renk := UI.YESIL  # açık: yeşil halka
		var zemin := Color(0.03, 0.12, 0.04, 0.86)
		var cizik := false
		match durum:
			"bekle":
				renk = Color(0.7, 0.72, 0.68)
				zemin = Color(0.03, 0.04, 0.04, 0.8)
			"konusuyor":
				renk = UI.YESIL.lightened(0.2)
				zemin = Color(0.04, 0.17, 0.05, 0.9)
			"kapali":
				renk = Color("#ff5a4e")
				zemin = Color(0.28, 0.04, 0.03, 0.92)
				cizik = true
			"susturuldu":
				renk = Color(0.62, 0.64, 0.62)
				zemin = Color(0.03, 0.04, 0.04, 0.8)
				cizik = true
		# konuşurken iki yanda ses dalgaları (seviyeye göre büyür, hafifçe atar)
		if durum == "konusuyor":
			var k := clampf(0.35 + seviye * 1.6, 0.0, 1.0)
			for i in 3:
				var a := clampf(k * 1.4 - i * 0.35, 0.0, 1.0) * (0.75 + 0.25 * sin(_t * 12.0 - i))
				var rr := r + 6.0 + i * 6.0
				draw_arc(c, rr, -0.55, 0.55, 12, Color(renk, a), 3.0, true)
				draw_arc(c, rr, PI - 0.55, PI + 0.55, 12, Color(renk, a), 3.0, true)
		draw_circle(c + Vector2(0, 2), r + 1.0, Color(0, 0, 0, 0.35))
		draw_circle(c, r, zemin)
		draw_arc(c, r, 0.0, TAU, 40, Color(renk, 0.95), 4.0, true)
		if size.x < 56.0:
			_glif(c, r * 2.0, Color(0.95, 0.93, 0.88) if not cizik else Color(0.95, 0.93, 0.88, 0.85))  # küçükte sade mikrofon
		elif _ikon:
			var s := r * 1.3
			var soluk := cizik or durum == "bekle"
			draw_texture_rect(_ikon, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, 0.6) if soluk else Color.WHITE)
		if cizik:
			var d := Vector2(r, r) * 0.62
			var k := maxf(1.0, size.x / 76.0)
			draw_line(c - d, c + d, Color(0, 0, 0, 0.8), 7.0 * k if size.x >= 56.0 else 5.0, true)
			draw_line(c - d, c + d, renk, 4.0 * k if size.x >= 56.0 else 3.0, true)

	# Sade mikrofon çizimi (s: kutu boyu): kapsül, U tutucu, sap, taban
	func _glif(c: Vector2, s: float, renk: Color) -> void:
		var w := s * 0.16
		var ust := c + Vector2(0, -s * 0.2)
		var alt := c + Vector2(0, -s * 0.02)
		draw_circle(ust, w, renk)
		draw_circle(alt, w, renk)
		draw_rect(Rect2(ust.x - w, ust.y, w * 2.0, alt.y - ust.y), renk)
		var t := maxf(1.5, s * 0.06)
		draw_arc(alt, w + s * 0.1, 0.0, PI, 16, renk, t, true)
		draw_line(alt + Vector2(0, w + s * 0.1), c + Vector2(0, s * 0.34), renk, t)
		draw_line(c + Vector2(-s * 0.14, s * 0.34), c + Vector2(s * 0.14, s * 0.34), renk, t)


# Hedef işareti: oyunda gitmen gereken yer (çalan telefon, tahta, sigorta kutusu, dolap, bombayı vereceğin kişi).
# Hedef ekrandaysa üstünde inip kalkan küçük bir iğne; ekran dışındaysa kenarda o yönü gösteren ok.
# Kısa yazı (1-2 kelime) + ikon. Tüm ekranı kaplayan tek bir Control; dokunmaları geçirir.
class Isaret extends Control:
	var hedef_var := false
	var kenar := false  # hedef ekran dışında: kenarda ok
	var nokta := Vector2.ZERO  # iğnenin ucu ya da kenardaki dairenin merkezi
	var yon := Vector2.DOWN  # kenar okunun yönü
	var metin := ""
	var renk := Color("#ffb020")
	var ikon: Texture2D
	var _a := 0.0
	var _t := 0.0
	var _p := Vector2.ZERO  # ekrandaki (yumuşatılmış) konum

	func ilerle(delta: float) -> void:
		_t += delta
		_a = move_toward(_a, 1.0 if hedef_var else 0.0, delta * 5.0)
		if hedef_var:
			_p = nokta if _a < 0.05 or _p == Vector2.ZERO else _p.lerp(nokta, 1.0 - exp(-delta * 18.0))
		visible = _a > 0.0
		if visible:
			queue_redraw()

	func _draw() -> void:
		var r := 27.0
		var bob := sin(_t * 4.0) * 5.0
		var c := _p
		var yazi_y := 0.0
		if kenar:
			# kenarda: daire + dışa bakan ok (nabız gibi ileri geri)
			var d := yon.normalized()
			var it := 6.0 + (0.5 + 0.5 * sin(_t * 6.0)) * 6.0
			var uc := c + d * (r + 10.0 + it)
			var yan := d.orthogonal() * 13.0
			var k := c + d * (r + it - 4.0)
			draw_colored_polygon(PackedVector2Array([uc + d * 3.0, k + yan * 1.15, k - yan * 1.15]), Color(0, 0, 0, 0.55 * _a))
			draw_colored_polygon(PackedVector2Array([uc, k + yan, k - yan]), Color(renk, _a))
			yazi_y = c.y + r + 24.0 if d.y <= 0.35 else c.y - r - 12.0
		else:
			# ekranda: hedefin üstünde iğne (daire + aşağı bakan sivri uç)
			c = _p + Vector2(0, -r - 26.0 + bob)
			var uc2 := c + Vector2(0, r + 18.0)
			draw_colored_polygon(PackedVector2Array([uc2 + Vector2(0, 3), c + Vector2(-15, r * 0.55), c + Vector2(15, r * 0.55)]), Color(0, 0, 0, 0.5 * _a))
			draw_colored_polygon(PackedVector2Array([uc2, c + Vector2(-12, r * 0.6), c + Vector2(12, r * 0.6)]), Color(renk, _a))
			yazi_y = c.y - r - 12.0
		draw_circle(c + Vector2(0, 3), r + 2.0, Color(0, 0, 0, 0.45 * _a))
		draw_circle(c, r, Color(0.04, 0.05, 0.05, 0.92 * _a))
		draw_arc(c, r, 0.0, TAU, 40, Color(renk, _a), 3.5, true)
		var nab := 0.5 + 0.5 * sin(_t * 5.0)
		draw_arc(c, r + 4.0 + nab * 8.0, 0.0, TAU, 40, Color(renk, (1.0 - nab) * 0.5 * _a), 2.5, true)
		if ikon:
			var s := r * 1.25
			draw_texture_rect(ikon, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, _a))
		if metin != "":
			var f: Font = UI.TITLE_FONT
			var fs := 19
			var t := tr(metin)
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var x := clampf(c.x - w / 2.0, 8.0, size.x - w - 8.0)
			var kutu := Rect2(Vector2(x - 10, yazi_y - 20), Vector2(w + 20, 28))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.03, 0.04, 0.04, 0.85 * _a)
			sb.border_color = Color(renk, 0.8 * _a)
			sb.border_width_bottom = 2
			sb.set_corner_radius_all(8)
			draw_style_box(sb, kutu)
			draw_string_outline(f, Vector2(x, yazi_y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8 * _a))
			draw_string(f, Vector2(x, yazi_y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.METIN, _a))


# ---------------------------------------------------------------- yardımcılar

# Bir arayüz parçasını ekranın bir köşesine/kenarına göre yerleştirir.
func _place(c: Control, preset: int, ofs: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = ofs.x
	c.offset_top = ofs.y
	c.offset_right = ofs.x + sz.x
	c.offset_bottom = ofs.y + sz.y


# Ekranın sol/sağ kenarına yaslı dokunmatik öğeler: telefonun yuvarlak köşesi, çentiği ya da kamera deliği
# altında kalmasın diye en az HUD_KENAR (ya da güvenli alan payı) kadar içeri alınır.
const HUD_KENAR := 20.0
const _SOL := [Control.PRESET_TOP_LEFT, Control.PRESET_BOTTOM_LEFT, Control.PRESET_CENTER_LEFT, Control.PRESET_LEFT_WIDE]
const _SAG := [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT, Control.PRESET_RIGHT_WIDE]

func _place_kenar(c: Control, preset: int, ofs: Vector2, sz: Vector2) -> void:
	var g := UI.guvenli_pay()
	if preset in _SOL:
		ofs.x += maxf(g.x, HUD_KENAR)
	elif preset in _SAG:
		ofs.x -= maxf(g.z, HUD_KENAR)
	_place(c, preset, ofs, sz)


# Önce oyunun diline çevir, sonra büyük harf (Türkçede i -> İ, ı -> I)
static func _buyuk(s: String) -> String:
	return Dil.buyuk(Dil.t(s))


func _daire(c: Color, kenar: Color, px: float, glow := 0.0, kenar_px := 0) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.border_color = kenar
	st.set_border_width_all(kenar_px if kenar_px > 0 else maxi(2, int(px * 0.03)))
	st.set_corner_radius_all(int(px))
	st.anti_aliasing = true
	if glow > 0.0:
		st.shadow_color = Color(c, glow)
		st.shadow_size = int(maxf(6.0, px * 0.12))
	return st


func _ana_bool(ad: String) -> bool:
	var p := get_parent()
	if p == null:
		return false
	var v = p.get(ad)
	return v is bool and v


# Koyu ad plakası (yuvarlak düğmelerin altında).
func _plaka(text: String, size := 18) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UI.flat(Color(0.04, 0.045, 0.045, 0.94), Color(1, 1, 1, 0.18), UI.R_KUCUK + 2)
	st.set_border_width_all(1)
	st.shadow_size = 3
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 1
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.title(text, size, UI.METIN, true)
	p.add_child(l)
	p.set_meta("label", l)
	return p


# Yuvarlak oyun düğmesi: perçinli çelik halka (btn_round) + isteğe bağlı renkli disk + ikon + altta ad plakası.
func _yuvarlak(px: float, icon_name: String, yazi: String, disk := Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px, px)
	var bos := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, bos)
	var halo := Panel.new()
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(halo, Control.PRESET_FULL_RECT, Vector2(-px * 0.07, -px * 0.07), Vector2.ZERO)
	halo.offset_right = px * 0.07
	halo.offset_bottom = px * 0.07
	halo.visible = false
	b.add_child(halo)
	b.set_meta("halo", halo)
	var t := UI.texture("btn_round", int(px * 2))
	if t:
		var cer := TextureRect.new()
		cer.texture = t
		cer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cer.set_anchors_preset(Control.PRESET_FULL_RECT)
		cer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cer)
	else:
		var yedek := Panel.new()
		yedek.add_theme_stylebox_override("panel", _daire(Color(0.06, 0.07, 0.07, 0.8), Color(1, 1, 1, 0.5), px / 2.0))
		yedek.set_anchors_preset(Control.PRESET_FULL_RECT)
		yedek.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(yedek)
	var d := Panel.new()
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ins := px * 0.17
	_place(d, Control.PRESET_FULL_RECT, Vector2(ins, ins), Vector2.ZERO)
	d.offset_right = -ins
	d.offset_bottom = -ins
	b.add_child(d)
	b.set_meta("disk", d)
	# disk üstünde ışık
	var parla := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(1, 1, 1, 0.16)
	ps.set_corner_radius_all(int(px))
	parla.add_theme_stylebox_override("panel", ps)
	parla.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(parla, Control.PRESET_FULL_RECT, Vector2(px * 0.28, px * 0.21), Vector2.ZERO)
	parla.offset_right = -px * 0.28
	parla.offset_bottom = -px * 0.53
	b.add_child(parla)
	b.set_meta("parla", parla)
	_disk_renk(b, disk)
	var ic := TextureRect.new()
	ic.texture = UI.icon_texture(icon_name, int(px * 0.5))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ip := px * (0.28 if yazi == "" else 0.25)
	var dy := px * 0.05 if yazi != "" else 0.0
	_place(ic, Control.PRESET_CENTER, Vector2(-ip, -ip - dy), Vector2(ip * 2.0, ip * 2.0))
	b.add_child(ic)
	b.set_meta("ikon", ic)
	if yazi != "":
		var pl := _plaka(yazi, 18 if px < 130 else UI.FS_METIN + 2)  # 720p'de en az 18 px
		_place(pl, Control.PRESET_CENTER_BOTTOM, Vector2(0, -px * 0.17), Vector2.ZERO)
		pl.grow_horizontal = Control.GROW_DIRECTION_BOTH
		b.add_child(pl)
		b.set_meta("plaka", pl)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.9, 0.06)
		# oyun içi yuvarlak düğmeler: hafif dokunma sesi (BAS KONUŞ gibi basılı tutulanlarda "sessiz")
		if not b.get_meta("sessiz", false):
			UI.tik(-13.0))
	b.button_up.connect(func() -> void:
		b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(b, "scale", Vector2.ONE, 0.16))
	return b


func _disk_renk(b: Button, c: Color, glow := 0.0) -> void:
	var d: Panel = b.get_meta("disk")
	d.visible = c.a > 0.0
	(b.get_meta("parla") as Control).visible = d.visible
	if d.visible:
		d.add_theme_stylebox_override("panel", _daire(c, c.lightened(0.45), b.custom_minimum_size.x / 2.0, glow, 3))


# Bir öğeyi (dx, dy) uzaktan yerine kaydırarak getirir.
func _kay(c: Control, dx: float, dy: float, sure := 0.38) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.22)
	for pr in [["offset_left", dx], ["offset_right", dx], ["offset_top", dy], ["offset_bottom", dy]]:
		var ad: String = pr[0]
		var d: float = pr[1]
		if d == 0.0:
			continue
		var goal: float = c.get(ad)
		tw.tween_property(c, ad, goal, sure).from(goal + d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _pop(c: Control) -> void:
	c.pivot_offset = c.custom_minimum_size / 2.0
	c.scale = Vector2.ONE * 0.6
	c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(c, "scale", Vector2.ONE, 0.28)


# ---------------------------------------------------------------- kurulum

func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var root := _root

	# eski tur göstergesi (oyunda gösterilmiyor; main.gd gizler)
	round_pill = _plaka("TUR")
	round_pill.visible = false
	root.add_child(round_pill)
	_place(round_pill, Control.PRESET_TOP_LEFT, Vector2(104, 26), Vector2.ZERO)

	# Sol üst: ayarlar
	var gear := _yuvarlak(AYAR_PX, "ayarlar", "")
	gear.pressed.connect(func() -> void: settings_pressed.emit())
	root.add_child(gear)
	_place_kenar(gear, Control.PRESET_TOP_LEFT, Vector2(16, 6), Vector2(AYAR_PX, AYAR_PX))
	_tap_blockers.append(gear)

	# Sol üst, ayarların altında: mikrofon göstergesi (konuşurken dalga, kapalıyken çizik). Dokununca kapat / aç.
	mik = Mik.new()
	mik.custom_minimum_size = Vector2(MIK_PX, MIK_PX)
	mik.mouse_filter = Control.MOUSE_FILTER_STOP
	mik.visible = false
	mik.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			mik.accept_event()
			# telefonda tek dokunuş hem dokunma hem (taklit) fare tıklaması olarak gelir: ikisi birden açıp
			# hemen geri kapatıyordu. Aynı dokunuşun ikinci olayı yok sayılır.
			var simdi := Time.get_ticks_msec()
			if simdi - _mik_dokunus < 350:
				return
			_mik_dokunus = simdi
			UI.tik(-12.0)
			mik_kapat(not mik_kapali))
	root.add_child(mik)
	_place_kenar(mik, Control.PRESET_TOP_LEFT, MIK_OFS, Vector2(MIK_PX, MIK_PX))
	_tap_blockers.append(mik)
	# mikrofonun altında: bağlantın zayıflayınca küçük sarı / kırmızı sinyal göstergesi (iyiyken gizli)
	_sinyal = Sinyal.new()
	_sinyal.zemin = true
	_sinyal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sinyal.visible = false
	root.add_child(_sinyal)
	_place_kenar(_sinyal, Control.PRESET_TOP_LEFT, MIK_OFS + Vector2((MIK_PX - 50.0) / 2.0, MIK_PX + 8.0), Vector2(50, 50))

	fps_label = UI.title("", 18, UI.YESIL)
	fps_label.visible = false
	root.add_child(fps_label)
	_place_kenar(fps_label, Control.PRESET_TOP_LEFT, Vector2(100, 96), Vector2(120, 24))

	# elmas sayacı (oyunda gizli: elmas mağazada/menüde görünür)
	var gem_row := UI.counter("elmas", "0", 34)
	gems_label = gem_row.get_meta("label")
	gem_row.visible = false
	root.add_child(gem_row)
	_place_kenar(gem_row, Control.PRESET_TOP_RIGHT, Vector2(-28, 84), Vector2.ZERO)
	gem_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# oyuncu yuvarlakları (oyunda gizli)
	avatars = HBoxContainer.new()
	avatars.add_theme_constant_override("separation", 8)
	avatars.visible = false
	root.add_child(avatars)
	_place_kenar(avatars, Control.PRESET_TOP_RIGHT, Vector2(-28, 20), Vector2.ZERO)
	avatars.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Üst orta: süre
	timer_pill = PanelContainer.new()
	timer_pill.add_theme_stylebox_override("panel", _timer_style(false))
	timer_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label = UI.title("1:30", 32, UI.METIN, true)
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_pill.add_child(timer_label)
	root.add_child(timer_pill)
	_place(timer_pill, Control.PRESET_CENTER_TOP, Vector2(-68, 12), Vector2(136, 58))
	timer_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_pills.append(timer_pill)

	# Ekran ortası: nişan noktası (koyu kenarlı, her zeminde görünür)
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", _daire(Color(1, 1, 1, 0.8), Color(0, 0, 0, 0.5), 5, 0.0, 2))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)
	_place(dot, Control.PRESET_CENTER, Vector2(-5, -5), Vector2(10, 10))

	prompt_label = UI.title("", UI.FS_METIN, UI.METIN, true)
	root.add_child(prompt_label)
	_place(prompt_label, Control.PRESET_CENTER, Vector2(-200, 26), Vector2(400, 40))

	# Sol alt: joystick
	joy = Joy.new()
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(joy)
	_place_kenar(joy, Control.PRESET_BOTTOM_LEFT, JOY_HOME, Vector2(240, 240))

	# Sağ alt: eylem düğmesi (büyük, ikonlu; altında ne yapacağı yazar)
	action_btn = _yuvarlak(EYLEM_PX, "el", "EYLEM", UI.AMBER)
	_action_label = (action_btn.get_meta("plaka") as Control).get_meta("label")
	_action_icon = action_btn.get_meta("ikon")
	_action_halo = action_btn.get_meta("halo")
	_action_halo.visible = true
	action_btn.pressed.connect(func() -> void: action_pressed.emit())
	action_btn.visible = false
	root.add_child(action_btn)
	_place_kenar(action_btn, Control.PRESET_BOTTOM_RIGHT, EYLEM_OFS, Vector2(EYLEM_PX, EYLEM_PX))

	# EĞİL (eylemin solunda) ve HAREKET (eylemin sol üstünde): başparmak yayı
	crouch_btn = _yuvarlak(EGIL_PX, "egil", "EĞİL")
	crouch_btn.pressed.connect(func() -> void: crouch_pressed.emit())
	root.add_child(crouch_btn)
	_place_kenar(crouch_btn, Control.PRESET_BOTTOM_RIGHT, EGIL_OFS, Vector2(EGIL_PX, EGIL_PX))
	_tap_blockers.append(crouch_btn)
	emote_btn = _yuvarlak(HAREKET_PX, "emote", "HAREKET")
	emote_btn.pressed.connect(func() -> void:
		_emote_ac(not emote_panel.visible)
		contacts.visible = false)
	root.add_child(emote_btn)
	_place_kenar(emote_btn, Control.PRESET_BOTTOM_RIGHT, HAREKET_OFS, Vector2(HAREKET_PX, HAREKET_PX))
	_tap_blockers.append(emote_btn)

	# bas-konuş (ayarlarda açıksa): basılı tutunca ses gider. Eylemin tam üstünde; basılıyken yeşil ses dalgası.
	ptt_btn = _yuvarlak(KONUS_PX, "mikrofon", "BAS KONUŞ", UI.ZEYTIN)
	ptt_btn.set_meta("sessiz", true)  # basılı tutulur; tık sesi rahatsız etmesin / mikrofona girmesin
	_ptt_dalga = Dalga.new()
	_ptt_dalga.renk = UI.YESIL
	_ptt_dalga.taban = KONUS_PX * 0.44
	_ptt_dalga.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_ptt_dalga, Control.PRESET_CENTER, Vector2(-KONUS_PX * 0.5, -KONUS_PX * 0.5), Vector2(KONUS_PX, KONUS_PX))
	ptt_btn.add_child(_ptt_dalga)
	ptt_btn.move_child(_ptt_dalga, 0)
	ptt_btn.button_down.connect(func() -> void:
		ptt_changed.emit(true)
		_ptt_dalga.acik = true
		_disk_renk(ptt_btn, UI.YESIL, 0.7))
	ptt_btn.button_up.connect(func() -> void:
		ptt_changed.emit(false)
		_ptt_dalga.acik = false
		_ptt_dalga.queue_redraw()
		_disk_renk(ptt_btn, UI.ZEYTIN))
	ptt_btn.visible = false
	root.add_child(ptt_btn)
	_place_kenar(ptt_btn, Control.PRESET_BOTTOM_RIGHT, KONUS_OFS, Vector2(KONUS_PX, KONUS_PX))
	_tap_blockers.append(ptt_btn)

	# hareket menüsü (HAREKET düğmesinin solunda açılır)
	emote_panel = PanelContainer.new()
	var eps := UI.flat(Color(UI.YUZEY, 0.95), Color(UI.AMBER, 0.55), UI.R_ORTA)
	eps.set_border_width_all(2)
	eps.content_margin_left = UI.B_S
	eps.content_margin_right = UI.B_S
	eps.content_margin_top = UI.B_S
	eps.content_margin_bottom = UI.B_S
	eps.shadow_size = 16
	emote_panel.add_theme_stylebox_override("panel", eps)
	# çok hareket varsa liste kayar (panel ekranı kaplamasın)
	_emote_kay = ScrollContainer.new()
	_emote_kay.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(_emote_kay)
	emote_panel.add_child(_emote_kay)
	emote_grid = GridContainer.new()
	emote_grid.columns = 2
	emote_grid.add_theme_constant_override("h_separation", UI.B_XS)
	emote_grid.add_theme_constant_override("v_separation", UI.B_XS)
	_emote_kay.add_child(emote_grid)
	emote_panel.visible = false
	root.add_child(emote_panel)
	# EĞİL düğmesinin solunda, alt kenara yaslı; yukarı doğru büyür (sağ başparmağın yanında)
	_place_kenar(emote_panel, Control.PRESET_BOTTOM_RIGHT, Vector2(EGIL_OFS.x - 12, -14), Vector2.ZERO)
	emote_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	emote_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tap_blockers.append(emote_panel)

	# Alt orta: çevrimdışı konuşmanın altyazısı
	_build_subtitle()

	# hedef işareti (çalan telefon, tahta, kutu...): düğmelerin ve bildirimlerin altında
	_isaret = Isaret.new()
	_isaret.set_anchors_preset(Control.PRESET_FULL_RECT)
	_isaret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_isaret.visible = false
	root.add_child(_isaret)
	root.move_child(_isaret, 0)

	_toast_host = Control.new()
	_toast_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_host)

	# telefon rehberi ve arama şeridi
	_build_contacts()
	_build_phone_strip()

	_ust = Control.new()
	_ust.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_ust)

	# Android geri tuşu / Esc (oyunda / lobide): önce açık menü ya da tahta kapanır, yoksa ayarlar açılır
	UI.geri_tusu(root, func() -> void:
		if emote_panel.visible:
			_emote_ac(false)
			return
		if contacts.visible:
			contacts.visible = false
			return
		var gu = get_parent().get("game_ui") if get_parent() else null
		if gu and is_instance_valid(gu) and gu.has_method("geri_kapat") and gu.geri_kapat():
			return
		settings_pressed.emit())

	# tek seferlik ipuçları en üstte (oyun pencerelerinin de üstünde), dokunmaları geçirir
	_ipucu_kat = CanvasLayer.new()
	_ipucu_kat.layer = 31
	add_child(_ipucu_kat)
	# test parametreleri: mik=<durum> ptt=1 hedef=<ad>[:yazı] ipucu=hep
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mik="):
			_mik_test = a.substr(4)
		elif a.begins_with("ping="):
			_ping_test = int(a.substr(5))
		elif a == "ptt=1":
			_ptt_test = true
		elif a.begins_with("hedef="):
			_hedef_test = [a.substr(6), Dil.buyuk(a.substr(6)), "el", UI.AMBER, true]
		elif a == "ipucu=hep":
			_ipucu_hep = true
		elif a.begins_with("shot=") or a.begins_with("auto="):
			_ipucu_yok = true  # otomatik testler oyuncunun "görüldü" kaydını değiştirmesin (ipucu=hep ile görünür)


func _timer_style(urgent: bool) -> StyleBoxFlat:
	var st: StyleBoxFlat
	if urgent:
		st = UI.flat(Color(0.34, 0.04, 0.03, 0.94), UI.KIRMIZI, UI.R_ORTA, Color(UI.KIRMIZI, 0.6))
	else:
		st = UI.flat(Color(0.035, 0.045, 0.045, 0.86), Color(1, 1, 1, 0.18), UI.R_ORTA)
	st.set_border_width_all(2)
	st.border_width_bottom = 4
	st.content_margin_left = UI.B_M
	st.content_margin_right = UI.B_M
	st.content_margin_top = 2
	st.content_margin_bottom = 4
	return st


# ---------------------------------------------------------------- genel

func set_fps_visible(on: bool) -> void:
	fps_label.visible = on


# main.gd telefonda bas-konuş açıkken çağırır. Görünürlük her karede _dugmeler() içinde hesaplanır:
# bas-konuş ayarı açıksa ses açık olan her an (yakındakilerle konuşma dahil) BAS KONUŞ görünür.
func set_ptt(on: bool) -> void:
	_ptt_zorla = on
	if on:
		_emote_ac(false)


# Ana sahnedeki ses düğümü (scripts/voice.gd; yoksa null)
func _ses() -> Node:
	var p := get_parent()
	var v = p.get("voice") if p else null
	return v if v is Node else null


func _goster(c: Control, on: bool) -> void:
	if c.visible == on:
		return
	c.visible = on
	if on:
		_pop(c)


# Her kare: kullanılmayan düğmeler gizlenir, mikrofon göstergesi sesin durumunu gösterir.
#  - BAS KONUŞ: ayarlarda bas-konuş açık ve ses açıkken (oyunun susturduğu ya da sen kapattıysan gizli)
#  - HAREKET: telefondayken ve otururken gizli (o anda yapılamaz)   - EĞİL: otururken gizli
func _dugmeler() -> void:
	var p := get_parent()
	var v := _ses()
	var aktif := v != null and bool(v.get("active"))
	var oturdu := player != null and bool(player.get("seated"))
	var ps = p.get("phone_state") if p else null
	var telefonda := ps != null and int(ps) >= 2  # 2 arıyor, 3 konuşuyor (main.gd Phone)
	var bas_konus := v != null and bool(v.get("ptt_enabled"))
	var susturuldu := v != null and bool(v.get("muted"))
	_goster(ptt_btn, (_ptt_test or _ptt_zorla or (bas_konus and aktif)) and not susturuldu and not mik_kapali)
	if ptt_btn.visible and not ptt_btn.has_meta("ipucu"):
		if ipucu("ptt", "Basılı tut ve konuş", "mikrofon", ptt_btn, "ust"):
			ptt_btn.set_meta("ipucu", true)
	_goster(emote_btn, not telefonda and not oturdu)
	# salonda EĞİL gerekmez (alttaki DAVET · HAZIRIM · BAŞLAT şeridiyle çakışmasın)
	_goster(crouch_btn, not oturdu and not (lobby_panel != null and lobby_panel.visible))
	if emote_panel.visible and not emote_btn.visible:
		_emote_ac(false)
	# bağlantı kalitesi: yalnız zayıfken görünür (sarı 2 çubuk, kötüyse kırmızı 1 çubuk)
	var ag = p.get("net") if p else null
	var kal := _ping_test
	if kal < 0:
		kal = int(ag.call("baglanti_kalitesi")) if ag is Node and (ag as Node).has_method("baglanti_kalitesi") else 0
	_sinyal.visible = kal > 0 and visible
	if _sinyal.visible:
		var r := UI.AMBER if kal == 1 else UI.KIRMIZI
		if _sinyal.renk != r:
			_sinyal.renk = r
			_sinyal.seviye = 2 if kal == 1 else 1
			_sinyal.queue_redraw()
	# mikrofon göstergesi
	if _mik_test != "":
		mik.visible = true
		mik.durum = _mik_test
		mik.seviye = 0.55
		return
	mik.visible = aktif and visible
	if not mik.visible:
		return
	if not mik.has_meta("ipucu") and bool(p.get("game_on")):
		if ipucu("mik", "Mikrofonu kapatmak için dokun", "mikrofon", mik, "sag", false):
			mik.set_meta("ipucu", true)
	var seviye := 0.0
	if mik_kapali:
		mik.durum = "kapali"
	elif susturuldu:
		mik.durum = "susturuldu"
	elif bas_konus and not bool(v.get("ptt_down")):
		mik.durum = "bekle"
	elif int(v.get("_open_left")) > 0:
		mik.durum = "konusuyor"
		seviye = float(v.get("level"))
	else:
		mik.durum = "acik"
	mik.seviye = lerpf(mik.seviye, seviye, 0.3)


# Oyuncu kendi mikrofonunu kapatır / açar (sol üstteki göstergeye dokununca). Mikrofon yakalaması durur:
# ne telefonda ne yakındakilere ses gider. Oyunun susturmasından (voice.muted) bağımsızdır.
func mik_kapat(on: bool) -> void:
	mik_kapali = on
	var v := _ses()
	if v:
		v.set("kapali", on)  # voice.gd: kapalıyken hiçbir ses parçası gönderilmez (yakın ses + telefon)
	var p := get_parent()
	var n = p.get("net") if p else null
	if n is Node:
		(n as Node).call("send", {"t": "mik", "kapali": on})  # başkaları baş üstünde çizik mikrofonu görsün
	var bus := AudioServer.get_bus_index("Mikrofon")
	if bus >= 0:
		for i in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect(bus, i) is AudioEffectCapture:
				AudioServer.set_bus_effect_enabled(bus, i, not on)
	_toast_ver("Mikrofon kapalı" if on else "Mikrofon açık", "hata" if on else "basari", "", "mik")
	if lobby_panel and lobby_panel.visible and not _lobby_son.is_empty():
		update_lobby.callv(_lobby_son)  # kendi kartındaki çizik mikrofon hemen görünsün


# ---------------------------------------------------------------- hedef işareti

# Gidilecek yer: [dünya konumu, yazı, ikon, renk] ya da []. Önce çalan telefon, sonra oyunun istediği yer
# (game_ui.hedef). Oyuncu hedefe varınca (eylem düğmesi onu gösterir) işaret kalkar; tek seferlik hedefler
# o turda bir daha çıkmaz.
func _hedef_bul() -> Array:
	var m := get_parent()
	if m == null or player == null or not bool(m.get("playing")) or bool(m.get("in_lobby")):
		return []
	var cells = m.get("cells")
	var mc := int(m.get("my_cell"))
	if not (cells is Array) or mc < 0 or mc >= (cells as Array).size():
		return []
	var cell: Node3D = cells[mc]
	var eylem_su_an := str(m.get("current_target"))
	var tel := int(m.get("phone_state"))
	# 1) telefon çalıyor: telefonun yeri (cevaplayana kadar)
	if ring_label.visible and tel == 1:
		if eylem_su_an == "phone":
			return []
		return [cell.phone_world(), "CEVAPLA", "telefon", UI.YESIL]
	var gu = m.get("game_ui")
	if not bool(m.get("game_on")) and _hedef_test.is_empty():
		return []
	var h: Array = _hedef_test
	var anahtar_on := "test"
	if h.is_empty():
		if not (gu is Node) or not (gu as Node).has_method("hedef"):
			return []
		var sec = gu.get("secret")
		anahtar_on = str(gu.get("_board_task")) + ":" + str((sec as Dictionary).get("round", 0) if sec is Dictionary else 0)
		if tel == 3:
			_aradi = anahtar_on
		h = gu.hedef(_aradi == anahtar_on)
	if h.is_empty():
		return []
	var ad := str(h[0])
	var pos := Vector3.ZERO
	var eylem := ""
	match ad:
		"telefon":
			if tel >= 2:
				return []  # zaten telefonda
			pos = cell.phone_world()
			eylem = "phone"
		"tahta":
			pos = cell.board_world()
			eylem = "board"
		"kutu":
			pos = cell.fuse_world()
			eylem = "kutu"
		"dolap":
			pos = cell.locker_world()
			eylem = "m:dolap"
		_:
			if not ad.begins_with("oyuncu:"):
				return []
			var id := int(ad.substr(7))
			var rem = m.get("remotes")
			if not (rem is Dictionary) or not (rem as Dictionary).has(id):
				return []
			pos = (rem[id].root as Node3D).global_position + Vector3(0, 2.05, 0)
			eylem = "m:ver:%d" % id
	var surekli := h.size() > 4 and bool(h[4])
	var anahtar := anahtar_on + ":" + ad
	if not surekli and _ulasilan.has(anahtar):
		return []
	var p := player as Node3D
	var yakin := Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length() < 1.5
	if eylem_su_an == eylem or yakin:
		if not surekli:
			_ulasilan[anahtar] = true
		return []
	return [pos, str(h[1]), str(h[2]), h[3] if h.size() > 3 else UI.AMBER]


func _hedef_guncelle(delta: float) -> void:
	var h: Array = []
	if visible and not contacts.visible and _ust.get_child_count() == 0:
		h = _hedef_bul()
	_isaret.hedef_var = false
	var cam: Camera3D = player.get("camera") if player else null
	if not h.is_empty() and cam and cam.is_inside_tree():
		var pos: Vector3 = h[0]
		var vs := _isaret.size
		var g := UI.guvenli_pay()
		# işaretin dolaşabileceği alan: üstteki bant ve sayaç, alttaki düğmeler hariç
		var alan := Rect2(Vector2(70 + maxf(g.x, HUD_KENAR), 150), Vector2.ZERO)
		alan.end = Vector2(vs.x - 70 - maxf(g.z, HUD_KENAR), vs.y - 230)
		var yerel := cam.global_transform.affine_inverse() * pos
		var arkada := yerel.z > -0.05
		var sp := cam.unproject_position(pos)
		if not arkada and alan.grow(-30).has_point(sp):
			_isaret.kenar = false
			_isaret.nokta = sp
		else:
			var d := Vector2(yerel.x, -yerel.y)
			if arkada:
				d = Vector2(1.0 if yerel.x >= 0.0 else -1.0, clampf(-yerel.y * 0.2, -0.3, 0.3))
			if d.length() < 0.001:
				d = Vector2.DOWN
			d = d.normalized()
			var c := alan.get_center()
			var t := INF
			if absf(d.x) > 0.001:
				t = minf(t, ((alan.end.x if d.x > 0.0 else alan.position.x) - c.x) / d.x)
			if absf(d.y) > 0.001:
				t = minf(t, ((alan.end.y if d.y > 0.0 else alan.position.y) - c.y) / d.y)
			_isaret.kenar = true
			_isaret.nokta = c + d * t
			_isaret.yon = d
		_isaret.hedef_var = true
		if _isaret.metin != str(h[1]) or _isaret.ikon == null or _isaret.get_meta("ikon_ad", "") != str(h[2]):
			_isaret.metin = str(h[1])
			var ik := str(h[2])
			_isaret.ikon = UI.texture("uretim/oyun_" + ik.substr(6), 128) if ik.begins_with("rozet:") else UI.icon_texture(ik, 64)
			_isaret.set_meta("ikon_ad", str(h[2]))
		_isaret.renk = h[3]
	_isaret.ilerle(delta)


# Yeni maç / lobiye dönüş: tur hafızası temizlenir.
func hedef_sifirla() -> void:
	_ulasilan.clear()
	_aradi = ""


# ---------------------------------------------------------------- tek seferlik ipuçları

func _ipucu_gorulmus(anahtar: String) -> bool:
	if _ipucu_hep:
		return false
	if _ipucu_yok:
		return true
	if _ipucu_cfg == null:
		_ipucu_cfg = ConfigFile.new()
		_ipucu_cfg.load(IPUCU_DOSYA)
	return bool(_ipucu_cfg.get_value("gorulen", anahtar, false))


func _ipucu_kaydet(anahtar: String) -> void:
	if _ipucu_hep:
		return
	_ipucu_cfg.set_value("gorulen", anahtar, true)
	_ipucu_cfg.save(IPUCU_DOSYA)


# İlk kez gereken anda tek seferlik, ikonlu, kısa (3-5 kelime) ipucu balonu: hedef düğmenin yanında çıkar,
# üstünde dokunan bir el belirir. ~4,5 sn sonra ya da düğmeye basılınca kaybolur. yan: sol | ust | sag
# Başka bir ipucu açıksa bekler (gösterilmez, sonra yine denenir). Dönen: gösterildi mi.
func ipucu(anahtar: String, metin: String, ikon: String, hedef: Control, yan := "sol", el := true) -> bool:
	if not visible or not is_instance_valid(hedef) or not hedef.is_visible_in_tree():
		return false
	if is_instance_valid(_ipucu_acik) or _ipucu_gorulmus(anahtar):
		return false
	# rol kartı, tahta ya da başka bir oyun penceresi açıkken ipucu beklesin (aynı anda tek şey)
	var gu = get_parent().get("game_ui") if get_parent() else null
	if gu is Node and (gu as Node).has_method("pencere_acik") and gu.pencere_acik() and hedef.get_meta("pencere_ustu", false) != true:
		return false
	if contacts.visible or _ust.get_child_count() > 0:
		return false
	_ipucu_kaydet(anahtar)
	var kok := Control.new()
	kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ipucu_kat.add_child(kok)
	_ipucu_acik = kok
	# düğme o an "pop" ile küçülmüş olabilir: ölçek ortadan olduğu için merkez + gerçek boyut kullanılır
	var r := Rect2(hedef.get_global_rect().get_center() - hedef.size / 2.0, hedef.size)
	# balon: koyu hap, amber kenar, ikon + kısa yazı
	var b := PanelContainer.new()
	var st := UI.flat(Color(0.04, 0.05, 0.05, 0.95), UI.AMBER, UI.R_BUYUK, Color(UI.AMBER, 0.25))
	st.set_border_width_all(2)
	st.content_margin_left = UI.B_S
	st.content_margin_right = UI.B_M
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	b.add_theme_stylebox_override("panel", st)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_XS)
	b.add_child(row)
	var ic := UI.icon(ikon, 40)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := UI.title(metin, UI.FS_METIN, UI.METIN)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	kok.add_child(b)
	var bs := b.get_combined_minimum_size()
	var ok := Polygon2D.new()  # balondan düğmeye bakan küçük üçgen
	ok.color = UI.AMBER
	var pos: Vector2
	match yan:
		"ust":
			pos = Vector2(r.get_center().x - bs.x / 2.0, r.position.y - bs.y - 18.0)
			ok.polygon = PackedVector2Array([Vector2(-11, 0), Vector2(11, 0), Vector2(0, 12)])
			ok.position = Vector2(r.get_center().x, r.position.y - 18.0)
		"sag":
			pos = Vector2(r.end.x + 18.0, r.get_center().y - bs.y / 2.0)
			ok.polygon = PackedVector2Array([Vector2(0, -11), Vector2(0, 11), Vector2(-12, 0)])
			ok.position = Vector2(r.end.x + 18.0, r.get_center().y)
		_:
			# solda, düğmenin üst kısmı hizasında (alttaki EĞİL düğmesinin üstüne binmesin)
			var y := minf(r.get_center().y, r.position.y + bs.y / 2.0 + 4.0)
			pos = Vector2(r.position.x - bs.x - 18.0, y - bs.y / 2.0)
			ok.polygon = PackedVector2Array([Vector2(0, -11), Vector2(0, 11), Vector2(12, 0)])
			ok.position = Vector2(r.position.x - 18.0, y)
	var vs := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 12.0, vs.x - bs.x - 12.0)
	pos.y = clampf(pos.y, 12.0, vs.y - bs.y - 12.0)
	b.position = pos
	b.size = bs
	kok.add_child(ok)
	# dokunan el: düğmenin ortasında aşağı yukarı "basar"
	if el:
		var eli := UI.icon("el", 64)
		eli.position = r.get_center() + Vector2(-8, -4)
		eli.size = Vector2(64, 64)
		eli.pivot_offset = Vector2(20, 8)
		eli.rotation = -0.35
		kok.add_child(eli)
		var et := eli.create_tween().set_loops(5)
		et.tween_property(eli, "scale", Vector2.ONE * 0.82, 0.18).set_trans(Tween.TRANS_SINE)
		et.tween_property(eli, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_SINE)
		et.tween_interval(0.25)
	# giriş: balon kayarak ve büyüyerek gelir
	kok.modulate.a = 0.0
	b.pivot_offset = bs / 2.0
	b.scale = Vector2.ONE * 0.8
	var tw := kok.create_tween().set_parallel(true)
	tw.tween_property(kok, "modulate:a", 1.0, 0.18)
	tw.tween_property(b, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var kapat := func() -> void:
		if not is_instance_valid(kok) or kok.has_meta("kapaniyor"):
			return
		kok.set_meta("kapaniyor", true)
		var kt := kok.create_tween()
		kt.tween_property(kok, "modulate:a", 0.0, 0.2)
		kt.tween_callback(kok.queue_free)
	get_tree().create_timer(4.5).timeout.connect(kapat)
	if hedef is BaseButton:
		(hedef as BaseButton).button_down.connect(kapat, CONNECT_ONE_SHOT)
	return true


func _emote_ac(on: bool) -> void:
	if on == emote_panel.visible:
		return
	emote_panel.visible = on
	if on:
		emote_panel.pivot_offset = emote_panel.size  # sağ alt köşeden (düğmelerin yanından) açılır
		emote_panel.scale = Vector2.ONE * 0.85
		emote_panel.modulate.a = 0.0
		var tw := emote_panel.create_tween().set_parallel(true)
		tw.tween_property(emote_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(emote_panel, "modulate:a", 1.0, 0.14)


func _process(delta: float) -> void:
	_t += delta
	if _tel:
		_tel.visible = visible
	if _public_left > 0.0:
		# salon gizliyken de (maç sonu ekranında) sayılır: dönünce doğru süre görünsün
		_public_left = maxf(0.0, _public_left - delta)
	if _public_left >= 0.0 and lobby_panel and lobby_panel.visible:
		_lobby_count_num.text = str(ceili(_public_left))
		_lobby_count_bar.value = _public_left / maxf(1.0, _public_total)
	if fps_label and fps_label.visible:
		fps_label.text = tr("%d FPS") % Engine.get_frames_per_second()
	if action_btn.visible:
		_action_halo.modulate.a = 0.35 + 0.35 * sin(_t * 4.0)
	_dugmeler()
	_hedef_guncelle(delta)
	if (joy_index != -1 or look_index != -1) and _oyun_penceresi():
		_dokunma_birak()
	_update_ring()
	if _call_state == "hatta" and _call_time_text == "":
		_call_t += delta
		_pill_durum.text = tr("● HATTA  %s") % ("%d:%02d" % [int(_call_t) / 60, int(_call_t) % 60])
	elif _call_state == "ariyor" or _call_state == "baglaniyor":
		var n := int(_t * 2.5) % 4
		_pill_durum.text = tr("ARANIYOR" if _call_state == "ariyor" else "BAĞLANIYOR") + ".".repeat(n)
	elif _call_state == "caliyor":
		_pill_style.shadow_size = int(10 + 10 * (0.5 + 0.5 * sin(_t * 9.0)))


func refresh_gems(n: int) -> void:
	gems_label.text = str(n)


# Hareket menüsü: sadece sahip olunan hareketler.
func set_emotes(owned_ids: Array) -> void:
	for ch in emote_grid.get_children():
		emote_grid.remove_child(ch)
		ch.queue_free()
	for it in Catalog.ITEMS.hareket:
		if not owned_ids.has(it[0]):
			continue
		var b := UI.button(_buyuk(str(it[1])), "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN, "", 176)
		# yazı zaten çevrilip büyütüldü: ikinci kez çevrilmesin ("Hayır" -> "NO" -> kablo şemasındaki "NO" = "SOCKET" oluyordu)
		(b.get_meta("label") as Label).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var id: String = it[0]
		b.pressed.connect(func() -> void:
			_emote_ac(false)
			emote_chosen.emit(id))
		emote_grid.add_child(b)
	# 8'den fazlaysa 3 sütun; liste en fazla 6 satır görünür, gerisi kaydırılır
	var n := emote_grid.get_child_count()
	emote_grid.columns = 2 if n <= 8 else 3
	var satir := ceili(n / float(emote_grid.columns))
	_emote_kay.custom_minimum_size = Vector2(emote_grid.columns * 176 + (emote_grid.columns - 1) * UI.B_XS,
		minf(satir, 6) * (UI.BTN_H_KUCUK + UI.B_XS) - UI.B_XS)


# Kısa bildirim (tasarım takımı UI.toast). Tür metinden anlaşılır: olumsuzlar kırmızı, ödüller yeşil.
# (metin Türkçe ya da çevrilmiş İngilizce gelebilir: iki dilin anahtar kelimeleri de bakılır)
func show_toast(text: String) -> void:
	var kind := "bilgi"
	var k := text.to_lower()
	for w in ["açmadı", "meşgul", "kilitli", "yapamazsın", "izleyici", "kimse yok", "hata", "koptu", "önce ",
			"didn't answer", "busy", "locked", "can't", "spectator", "no one", "error", "disconnected", "lost connection", "first"]:
		if k.contains(w):
			kind = "hata"
	if k.begins_with("+") or k.contains("kazandın") or k.contains("geri döndün") or k.contains("geri bağlandı") or k.contains("you won") or k.contains("you're back") or k.contains("reconnected"):
		kind = "basari"
	_toast_ver(text, kind)


# Maç başlarken ortada büyük 3-2-1 (salondan hücreye geçerken; sunucu ilk oyunu ~4 sn sonra başlatır).
func geri_sayim(n := 3) -> void:
	if not _tick:
		_tick = AudioStreamPlayer.new()
		_tick.stream = load("res://assets/ses/tik_ui.ogg")
		add_child(_tick)
	for i in range(n, 0, -1):
		var l := UI.title(str(i), 150, UI.AMBER, true)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast_host.add_child(l)
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		l.custom_minimum_size = Vector2(300, 220)
		l.position = get_viewport().get_visible_rect().size / 2.0 - l.custom_minimum_size / 2.0
		l.size = l.custom_minimum_size
		l.pivot_offset = l.size / 2.0
		l.scale = Vector2.ONE * 1.7
		l.modulate.a = 0.0
		var tw := l.create_tween()
		tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(l, "modulate:a", 1.0, 0.15)
		tw.tween_interval(0.4)
		tw.tween_property(l, "modulate:a", 0.0, 0.25)
		tw.tween_callback(l.queue_free)
		_tick.volume_db = 0.0
		_tick.pitch_scale = 1.0 if i > 1 else 1.3
		_tick.play()
		await get_tree().create_timer(1.0).timeout


# Oyuncu bildirimi (sunucunun "bag" alanı): bağlantı koptu / geri bağlandı / ayrıldı / odaya katıldı / çıktı /
# oda sahibi değişti. Kısa, ikonlu, renkli; sıraya girer.
func bildirim(tur: String, text: String) -> void:
	match tur:
		"koptu":
			_toast_ver(text, "hata", "sinyal_yok")
		"geri":
			_toast_ver(text, "basari", "sinyal")
		"ayrildi", "cikti":
			_toast_ver(text, "bilgi", "kapi")
		"katildi":
			_toast_ver(text, "basari", "arkadas")
		"sahip":
			_toast_ver(text, "bilgi", "tac")
		"istek", "davet":
			_toast_ver(text, "bilgi", "arkadas" if tur == "istek" else "davet")
		_:
			show_toast(text)


# Bildirimler sıraya girer: aynı anda en çok BILDIRIM_MAX tanesi alt alta görünür (üst üste binmez), gerisi
# sırayla gelir. Aynı yazı yinelenmez; anahtarı aynı olan (ör. "mik") eskisinin yerini alır.
const BILDIRIM_MAX := 2
const BILDIRIM_SURE := 2.8
var _bildirim_sira: Array = []  # [metin, tür, ikon, anahtar]
var _bildirim_acik: Array = []  # görünen bildirim kutuları (PanelContainer)


func _toast_ver(text: String, kind: String, ikon := "", anahtar := "") -> void:
	var metin := tr(text)
	for c in _bildirim_acik.duplicate():
		if is_instance_valid(c) and anahtar != "" and str(c.get_meta("anahtar", "")) == anahtar:
			_bildirim_kapat(c, true)
		elif is_instance_valid(c) and str(c.get_meta("metin", "")) == metin and not c.get_meta("kapaniyor", false):
			return
	_bildirim_sira = _bildirim_sira.filter(func(b: Array) -> bool: return b[0] != metin and (anahtar == "" or b[3] != anahtar))
	_bildirim_sira.append([metin, kind, ikon, anahtar])
	while _bildirim_sira.size() > 4:
		_bildirim_sira.pop_front()  # çok birikirse en eskisi düşer
	_bildirim_isle()


func _bildirim_isle() -> void:
	_bildirim_acik = _bildirim_acik.filter(func(c) -> bool: return is_instance_valid(c) and not c.get_meta("kapaniyor", false))
	while _bildirim_acik.size() < BILDIRIM_MAX and not _bildirim_sira.is_empty():
		var b: Array = _bildirim_sira.pop_front()
		_bildirim_acik.append(_bildirim_kur(b[0], b[1], b[2], b[3]))
	_bildirim_diz()


# Görünenleri alt alta dizer (yenisi altta); kalkan olunca yukarı kayarlar.
func _bildirim_diz() -> void:
	# maçta üst ortada; salonda alttaki düğmelerin üstünde (oda kartı ve oyuncu kartlarıyla çakışmasın)
	var y := 84.0
	if lobby_panel and lobby_panel.visible:
		y = get_viewport().get_visible_rect().size.y - 90.0 - 16.0 - BILDIRIM_MAX * 62.0
	for i in _bildirim_acik.size():
		var p: PanelContainer = _bildirim_acik[i]
		var hedef := y + i * 62.0
		if p.has_meta("y"):
			if absf(float(p.get_meta("y")) - hedef) > 0.5:
				p.create_tween().tween_property(p, "offset_top", hedef, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			p.offset_top = hedef - 24.0
			var tw := p.create_tween().set_parallel(true)
			tw.tween_property(p, "modulate:a", 1.0, 0.18)
			tw.tween_property(p, "offset_top", hedef, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		p.set_meta("y", hedef)


func _bildirim_kur(metin: String, kind: String, ikon: String, anahtar: String) -> PanelContainer:
	var renk: Color = {"bilgi": UI.AMBER, "basari": UI.YESIL, "hata": UI.KIRMIZI}.get(kind, UI.AMBER)
	var p := PanelContainer.new()
	var st := UI.flat(Color(0.05, 0.06, 0.06, 0.95), Color(renk, 0.9), UI.R_BUYUK, Color(renk, 0.22))
	st.set_border_width_all(2)
	st.border_width_left = 8
	st.content_margin_left = UI.B_M if ikon != "" else UI.B_L
	st.content_margin_right = UI.B_L
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.modulate.a = 0.0
	p.set_meta("metin", metin)
	p.set_meta("anahtar", anahtar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	if ikon == "sinyal" or ikon == "sinyal_yok":
		var sg := Sinyal.new()
		sg.custom_minimum_size = Vector2(32, 32)
		sg.seviye = 4 if ikon == "sinyal" else 0
		sg.renk = UI.YESIL if ikon == "sinyal" else UI.KIRMIZI
		sg.cizik = ikon == "sinyal_yok"
		h.add_child(sg)
	elif ikon != "":
		var ic := UI.icon(ikon, 32)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var l := UI.label(metin, UI.FS_METIN, UI.METIN, true)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # zaten çevrildi
	l.add_theme_font_override("font", UI.TITLE_FONT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	_toast_host.add_child(p)
	_toast = p
	get_tree().create_timer(BILDIRIM_SURE).timeout.connect(func() -> void: _bildirim_kapat(p, false))
	return p


func _bildirim_kapat(p: Control, hemen: bool) -> void:
	if not is_instance_valid(p) or p.get_meta("kapaniyor", false):
		return
	p.set_meta("kapaniyor", true)
	_bildirim_acik.erase(p)
	if hemen:
		p.queue_free()
	else:
		var tw := p.create_tween()
		tw.tween_property(p, "modulate:a", 0.0, 0.25)
		tw.tween_callback(p.queue_free)
	_bildirim_isle()


# Oyuncu yuvarlakları (oyunda gizli; liste yine de tutulur).
func set_players(list: Array, my_id: int) -> void:
	for ch in avatars.get_children():
		ch.queue_free()
	for pl in list:
		var me := int(pl.id) == my_id
		var p := OU.avatar(str(pl.name), 52, UI.AMBER if me else Color(0, 0, 0, 0))
		p.tooltip_text = str(pl.name)
		p.set_meta("id", int(pl.id))
		avatars.add_child(p)


# Oyunda hattı düşenlerin yuvarlağı solar.
func set_alive(alive: Array) -> void:
	for p in avatars.get_children():
		var out := not (int(p.get_meta("id", 0)) in alive)
		p.modulate = Color(0.35, 0.35, 0.38, 0.6) if out else Color.WHITE


# ---------------------------------------------------------------- eylem düğmesi

# eylem metni -> ikon (kit/ikon_*)
func _action_icon_name(text: String, phone: bool) -> String:
	var k := text.to_lower()
	if phone:
		return "telefon"
	if k.contains("tahtayı oku") or k.contains("sigorta"):
		return "sigorta"
	if k.contains("tahta") or k.contains("eşleştir") or k.begins_with("oyla") or k.contains("sayı yaz"):
		return "tahta"
	if k.contains("dolab"):
		return "envanter"
	if k.contains("bilgisayar"):
		return "bilgisayar"
	if k.contains("otur") or k.contains("kalk"):
		return "sandalye"
	if k.contains("kapı"):
		return "kapi"
	return "el"


# Eylem düğmesi: "" gizler. phone: telefon eylemi (Ara / Cevapla yeşil, Kapat kırmızı). Her karede çağrılabilir.
func set_action(text: String, phone := false) -> void:
	if text == "":
		if action_btn.visible:
			action_btn.visible = false
			_action_text = ""
			if _action_shake:
				_action_shake.kill()
			action_btn.rotation = 0.0
		return
	var key := text + ("#tel" if phone else "")
	if key == _action_text and action_btn.visible:
		return
	var yeni := not action_btn.visible
	_action_text = key
	action_btn.visible = true
	_action_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # _buyuk zaten çevirdi
	_action_label.text = _buyuk(text)
	UI.sigdir(_action_label, EYLEM_PX + 56)  # uzun yazı ("VER: KIVIRCIK AHMET") ekrandan taşmasın
	_action_icon.texture = UI.icon_texture(_action_icon_name(text, phone), 80)
	var renk := UI.AMBER
	if phone:
		renk = UI.KIRMIZI if text.to_lower().begins_with("kapat") else UI.YESIL
	_disk_renk(action_btn, renk)
	_action_halo.add_theme_stylebox_override("panel", _daire(Color(renk, 0.0), Color(renk, 0.95), 90.0, 0.0, 5))
	if _action_shake:
		_action_shake.kill()
	action_btn.pivot_offset = Vector2(EYLEM_PX, EYLEM_PX) / 2.0
	action_btn.rotation = 0.0
	if yeni:
		_pop(action_btn)
	var kk := text.to_lower()
	if phone and kk.begins_with("cevap"):
		# çalan telefon: düğme titrer
		_action_shake = action_btn.create_tween().set_loops()
		for a in [0.1, -0.1, 0.08, -0.08, 0.05, 0.0]:
			_action_shake.tween_property(action_btn, "rotation", a, 0.05)
		_action_shake.tween_interval(0.5)
	# ilk kez: düğmenin yanında kısa ipucu + dokunan el (bir kez gösterilir)
	if phone and kk.begins_with("ara"):
		ipucu("ara", "Birini aramak için dokun", "telefon", action_btn)
	elif phone and kk.begins_with("cevap"):
		ipucu("cevapla", "Cevaplamak için dokun", "telefon", action_btn)
	elif not phone:
		ipucu("eylem", "Kullanmak için dokun", "el", action_btn)


func set_timer(seconds: float) -> void:
	var s := int(ceil(seconds))
	timer_label.text = "%d:%02d" % [s / 60, s % 60]


# Oyun sayacı: son 15 saniyede kırmızı, her saniye nabız gibi atar ve tik sesi gelir.
func set_game_timer(seconds: float) -> void:
	set_timer(seconds)
	var s := int(ceil(seconds))
	var urgent := s <= 15 and s > 0
	if bool(timer_pill.get_meta("acil", false)) != urgent:
		timer_pill.set_meta("acil", urgent)
		timer_pill.add_theme_stylebox_override("panel", _timer_style(urgent))
		timer_label.add_theme_color_override("font_color", Color("#ffe0d8") if urgent else UI.METIN)
	if not urgent or s == _last_sec:
		if not urgent:
			timer_pill.scale = Vector2.ONE
			_last_sec = -1
		return
	_last_sec = s
	timer_pill.pivot_offset = timer_pill.size / 2.0
	var tw := timer_pill.create_tween()
	tw.tween_property(timer_pill, "scale", Vector2.ONE * (1.32 if s <= 5 else 1.16), 0.08)
	tw.tween_property(timer_pill, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not _tick:
		_tick = AudioStreamPlayer.new()
		_tick.stream = load("res://assets/ses/tik_ui.ogg")
		add_child(_tick)
	_tick.volume_db = 0.0 if s <= 5 else -8.0
	_tick.pitch_scale = 1.25 if s <= 5 else 1.0
	_tick.play()


# ---------------------------------------------------------------- telefon: rehber

func _build_contacts() -> void:
	contacts = Control.new()
	contacts.set_anchors_preset(Control.PRESET_FULL_RECT)
	contacts.mouse_filter = Control.MOUSE_FILTER_STOP
	contacts.visible = false
	var perde := ColorRect.new()
	perde.color = UI.PERDE
	perde.set_anchors_preset(Control.PRESET_FULL_RECT)
	perde.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_contacts_kapat())
	contacts.add_child(perde)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contacts.add_child(cc)
	var box := UI.panel(Vector2(900, 0), UI.B_L)
	box.name = "Kutu"
	cc.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_M)
	box.add_child(v)
	var ust := HBoxContainer.new()
	ust.add_theme_constant_override("separation", UI.B_S)
	v.add_child(ust)
	var h := UI.header("KİMİ ARAYACAKSIN?", UI.FS_ORTA + 2)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ust.add_child(h)
	var kapat := UI.icon_button("kapat", "ikincil", UI.DOKUNMA)
	kapat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kapat.pressed.connect(_contacts_kapat)
	ust.add_child(kapat)
	var govde := HBoxContainer.new()
	govde.add_theme_constant_override("separation", UI.B_L)
	v.add_child(govde)
	# sol: eski tip çevirmeli telefon, arkasında sıcak lamba ışığı
	var sol := Control.new()
	sol.custom_minimum_size = Vector2(220, 320)
	govde.add_child(sol)
	var isik := Panel.new()
	var ist := _daire(Color(UI.AMBER, 0.06), Color(UI.AMBER, 0.0), 100, 0.0)
	ist.shadow_color = Color(UI.AMBER, 0.14)
	ist.shadow_size = 60
	isik.add_theme_stylebox_override("panel", ist)
	isik.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(isik, Control.PRESET_TOP_LEFT, Vector2(20, 60), Vector2(180, 180))
	sol.add_child(isik)
	var tel := UI.icon("ahize", 210)
	tel.name = "Ahize"
	_place(tel, Control.PRESET_TOP_LEFT, Vector2(5, 40), Vector2(210, 210))
	sol.add_child(tel)
	# sağ: kişi kartları
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(610, 336)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(sc)
	govde.add_child(sc)
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_theme_constant_override("margin_right", 6)
	mc.add_theme_constant_override("margin_top", 6)
	mc.add_theme_constant_override("margin_bottom", 6)
	sc.add_child(mc)
	contact_list = GridContainer.new()
	contact_list.columns = 2
	contact_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contact_list.add_theme_constant_override("h_separation", UI.B_S)
	contact_list.add_theme_constant_override("v_separation", UI.B_S)
	mc.add_child(contact_list)
	box.resized.connect(func() -> void: box.pivot_offset = box.size / 2.0)
	_root.add_child(contacts)


func _contacts_kapat() -> void:
	if not contacts.visible or contacts.has_meta("kapaniyor"):
		return
	contacts.set_meta("kapaniyor", true)
	var box: Control = contacts.find_child("Kutu", true, false)
	var tw := contacts.create_tween().set_parallel(true)
	tw.tween_property(contacts, "modulate:a", 0.0, 0.16)
	tw.tween_property(box, "scale", Vector2.ONE * 0.9, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		contacts.visible = false
		contacts.remove_meta("kapaniyor"))


# "Deniz  (hücre 12)" -> ["Deniz", "HÜCRE 12"]
static func _kisi_ad(s: String) -> Array:
	var re := RegEx.create_from_string("^(.*?)\\s*\\(hücre (\\d+)\\)\\s*$")
	var m := re.search(s)
	if m:
		return [m.get_string(1), Dil.t("HÜCRE %s") % m.get_string(2)]
	return [s, ""]


func _contact_card(c: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(290, 100)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := UI.flat(Color(UI.YUZEY_2, 0.97), UI.CIZGI, UI.R_ORTA)
	st.set_border_width_all(2)
	st.border_width_bottom = 4
	st.shadow_size = 5
	var bas := st.duplicate() as StyleBoxFlat
	bas.border_color = UI.YESIL
	bas.bg_color = UI.YUZEY_2.lightened(0.07)
	for k in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(k, st)
	b.add_theme_stylebox_override("pressed", bas)
	# telefonda olan kişi: kart kırmızı (zemin, kalın çerçeve, kırmızı ışıma), aranamaz
	var mst := st.duplicate() as StyleBoxFlat
	mst.bg_color = Color("#3a1210")
	mst.border_color = UI.KIRMIZI
	mst.set_border_width_all(3)
	mst.border_width_bottom = 5
	mst.shadow_color = Color(UI.KIRMIZI, 0.35)
	mst.shadow_size = 10
	b.set_meta("st", st)
	b.set_meta("st_bas", bas)
	b.set_meta("st_mesgul", mst)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UI.B_M
	row.offset_right = -UI.B_M
	row.add_theme_constant_override("separation", UI.B_M)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var ad: Array = _kisi_ad(str(c.name))
	var av := OU.avatar(str(ad[0]), 64)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(av)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UI.title(str(ad[0]), UI.FS_ORTA + 2, UI.METIN)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(nm)
	var alt := HBoxContainer.new()
	alt.add_theme_constant_override("separation", UI.B_S)
	alt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(ad[1]) != "":
		alt.add_child(UI.label(str(ad[1]), UI.FS_KUCUK, UI.METIN_SOLUK))
	tv.add_child(alt)
	# telefonda olan kişi: adın altında büyük kırmızı "MEŞGUL" (mark_busy açar/kapatır)
	var ms := UI.title("MEŞGUL", UI.FS_ORTA + 2, Color("#ff5a4e"))
	ms.name = "Mesgul"
	ms.visible = false
	tv.add_child(ms)
	row.add_child(tv)
	# yeşil ahize düğmesi (meşgulken gri ve sönük)
	var ara := Panel.new()
	ara.name = "Ara"
	ara.custom_minimum_size = Vector2(66, 66)
	ara.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ara.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ara.add_theme_stylebox_override("panel", _daire(UI.YESIL.darkened(0.08), UI.YESIL.lightened(0.5), 33, 0.45, 3))
	var ic := UI.icon("telefon", 42)
	_place(ic, Control.PRESET_CENTER, Vector2(-21, -21), Vector2(42, 42))
	ara.add_child(ic)
	row.add_child(ara)
	_kart_mesgul(b, bool(c.get("mesgul", false)))
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.96, 0.05)
		UI.tik())
	b.button_up.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
	return b


func show_contacts(list: Array) -> void:
	_emote_ac(false)
	for ch in contact_list.get_children():
		ch.queue_free()
	contact_list.columns = 1 if list.size() <= 1 else 2
	var i := 0
	for c in list:
		var b := _contact_card(c)
		var id: int = c.id
		b.set_meta("id", id)
		b.pressed.connect(func() -> void:
			_contacts_kapat()
			contact_chosen.emit(id))
		contact_list.add_child(b)
		# kartlar sırayla belirir
		b.modulate.a = 0.0
		var tw := b.create_tween()
		tw.tween_interval(0.08 + i * 0.05)
		tw.tween_property(b, "modulate:a", 1.0, 0.18)
		i += 1
	contacts.visible = true
	contacts.remove_meta("kapaniyor")
	contacts.modulate.a = 0.0
	var box: Control = contacts.find_child("Kutu", true, false)
	box.scale = Vector2.ONE * 0.86
	var tw := contacts.create_tween().set_parallel(true)
	tw.tween_property(contacts, "modulate:a", 1.0, 0.16)
	tw.tween_property(box, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# ahize hafifçe sallanır
	var tel: Control = contacts.find_child("Ahize", true, false)
	if tel:
		tel.pivot_offset = Vector2(105, 170)
		var sw := tel.create_tween()
		for a in [0.07, -0.06, 0.04, -0.02, 0.0]:
			sw.tween_property(tel, "rotation", a, 0.07)


# ---------------------------------------------------------------- telefon: arama şeridi ve altyazı

func _build_phone_strip() -> void:
	# main.gd ring_label'ı yazar; görünmez bir kaynak olarak tutulur, şerit ondan okur
	var kaynak := Control.new()
	kaynak.visible = false
	add_child(kaynak)
	ring_label = Label.new()
	ring_label.visible = false
	kaynak.add_child(ring_label)

	_tel = CanvasLayer.new()
	_tel.layer = 30  # oyun panellerinin (tahta, sigorta kutusu) de üstünde
	add_child(_tel)
	_tel_kok = Control.new()
	_tel_kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tel_kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tel.add_child(_tel_kok)

	_pill = PanelContainer.new()
	_pill_style = UI.flat(Color(0.035, 0.045, 0.045, 0.96), UI.AMBER, 36, Color(UI.AMBER, 0.3))
	_pill_style.set_border_width_all(3)
	_pill_style.content_margin_left = 6
	_pill_style.content_margin_right = 6
	_pill_style.content_margin_top = 4
	_pill_style.content_margin_bottom = 4
	_pill.add_theme_stylebox_override("panel", _pill_style)
	_pill.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_S)
	_pill.add_child(row)
	_pill_avatar_kutu = Control.new()
	_pill_avatar_kutu.custom_minimum_size = Vector2(PILL_AV, PILL_AV)
	_pill_avatar_kutu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_pill_avatar_kutu)
	_pill_dalga = Dalga.new()
	_pill_dalga.taban = PILL_AV * 0.47
	_pill_dalga.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_pill_dalga, Control.PRESET_TOP_LEFT, Vector2(PILL_AV / 2.0 - 60.0, PILL_AV / 2.0 - 60.0), Vector2(120, 120))
	_pill_avatar_kutu.add_child(_pill_dalga)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", -2)
	row.add_child(tv)
	_pill_ad = UI.title("", 26, UI.METIN)
	_pill_ad.clip_text = true
	_pill_ad.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pill_ad.custom_minimum_size.x = 160
	tv.add_child(_pill_ad)
	_pill_durum = UI.title("", 20, UI.AMBER)
	tv.add_child(_pill_durum)
	_pill_sikayet = UI.icon_button("sikayet", "ikincil", UI.DOKUNMA)
	_pill_sikayet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pill_sikayet.pressed.connect(func() -> void:
		var n = get_parent().get("net") if get_parent() else null
		var oda := ""
		if n is Node:
			oda = str((n as Node).get("room_code"))
		var peer = get_parent().get("phone_peer") if get_parent() else 0
		open_report(_call_who, "", oda, _tel_kok, int(peer) if peer != null else 0))
	row.add_child(_pill_sikayet)
	# kırmızı KAPAT (ahize): her an hattı kapatır
	_pill_kapat = UI.icon_button("telefon", "tehlike", 72)
	_pill_kapat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pill_kapat.pressed.connect(_kapat_basildi)
	row.add_child(_pill_kapat)
	_tel_kok.add_child(_pill)
	_place_kenar(_pill, Control.PRESET_TOP_RIGHT, Vector2(-14, 6), Vector2.ZERO)
	_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _kapat_basildi() -> void:
	if hangup_pressed.get_connections().is_empty() and get_parent() and get_parent().has_method("_hang_up"):
		get_parent().call("_hang_up")
	else:
		hangup_pressed.emit()


func _build_subtitle() -> void:
	call_panel = PanelContainer.new()
	var st := UI.flat(Color(0.035, 0.045, 0.045, 0.92), Color(UI.AMBER, 0.9), UI.R_ORTA)
	st.set_border_width_all(1)
	st.border_width_left = 6
	st.content_margin_left = UI.B_M
	st.content_margin_right = UI.B_L
	st.content_margin_top = UI.B_S
	st.content_margin_bottom = UI.B_S
	call_panel.add_theme_stylebox_override("panel", st)
	call_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_M)
	call_panel.add_child(row)
	var av := Control.new()
	av.custom_minimum_size = Vector2(52, 52)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.name = "Av"
	row.add_child(av)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	call_title = UI.title("", UI.FS_KUCUK, UI.AMBER)
	call_text = UI.label("", 22, UI.METIN)
	call_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	call_text.custom_minimum_size = Vector2(540, 0)
	cv.add_child(call_title)
	cv.add_child(call_text)
	row.add_child(cv)
	call_panel.visible = false
	_root.add_child(call_panel)
	_place(call_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-330, -150), Vector2(660, 0))
	call_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _pill_kur(state: String, who: String) -> void:
	var degisti := state != _call_state or who != _call_who
	if who != _call_who:
		for ch in _pill_avatar_kutu.get_children():
			if ch != _pill_dalga:
				ch.queue_free()
		_pill_avatar_kutu.add_child(OU.avatar(who, PILL_AV))
	if state == "hatta" and _call_state != "hatta":
		_call_t = 0.0
	_call_state = state
	_call_who = who
	_pill_ad.text = who
	var renk := UI.YESIL if state == "hatta" else (UI.KIRMIZI if state == "mesgul" else UI.AMBER)
	_pill_style.border_color = renk
	_pill_style.shadow_color = Color(renk, 0.32)
	_pill_style.shadow_size = 18 if state == "mesgul" else 12
	_pill_dalga.renk = renk
	_pill_dalga.acik = state != "hatta" and state != "mesgul"
	_pill_dalga.queue_redraw()
	_pill_durum.add_theme_color_override("font_color", renk)
	# meşgulken durum yazısı büyük ve kırmızı ("MEŞGUL"), diğer durumlarda küçük
	_pill_durum.add_theme_font_size_override("font_size", 36 if state == "mesgul" else 20)
	_pill_style.content_margin_right = 22 if state == "mesgul" else 4  # kapat düğmesi yok: yazı kenara yapışmasın
	_pill_kapat.visible = state != "caliyor" and state != "mesgul"
	_pill_sikayet.visible = state == "hatta" and _ana_bool("online")
	if state == "caliyor":
		_pill_durum.text = "SENİ ARIYOR"
	elif state == "mesgul":
		_pill_durum.text = "MEŞGUL"
	if not _pill.visible or _pill.has_meta("gizleniyor"):
		_pill.remove_meta("gizleniyor")
		_pill.visible = true
		_pill.modulate.a = 0.0
		var tw := _pill.create_tween().set_parallel(true)
		tw.tween_property(_pill, "modulate:a", 1.0, 0.18)
		tw.tween_property(_pill, "offset_top", 6.0, 0.32).from(-50.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_pill, "offset_bottom", 6.0, 0.32).from(-50.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif degisti:
		_pill.pivot_offset = _pill.size / 2.0
		var tw2 := _pill.create_tween()
		tw2.tween_property(_pill, "scale", Vector2.ONE * 1.06, 0.08)
		tw2.tween_property(_pill, "scale", Vector2.ONE, 0.18)


# Aranan kişi meşgul: şerit kırmızıya döner, büyük "MEŞGUL" yazısı görünür ve şerit sallanır.
# main.gd ~2 sn sonra hattı kapatır (hide_call), şerit de kapanır.
func show_busy(who: String) -> void:
	call_panel.visible = false
	_pill_kur("mesgul", who)
	_pill.pivot_offset = _pill.size / 2.0
	var tw := _pill.create_tween()
	for a in [-0.035, 0.03, -0.022, 0.014, -0.006, 0.0]:
		tw.tween_property(_pill, "rotation", a, 0.05)


# Rehberde telefonda olan kişilerin kartı kırmızı + büyük "MEŞGUL", arama düğmesi gri ve pasif
# (sunucunun "hatlar" bilgisi; rehber açıkken her değişiklikte anında güncellenir).
func mark_busy(ids: Array) -> void:
	if not contact_list:
		return
	for b in contact_list.get_children():
		if b is Button and not b.is_queued_for_deletion():
			_kart_mesgul(b, ids.has(int(b.get_meta("id", -1))))


func _kart_mesgul(b: Button, on: bool) -> void:
	if b.has_meta("mesgul") and bool(b.get_meta("mesgul")) == on:
		return
	b.set_meta("mesgul", on)
	var st: StyleBox = b.get_meta("st_mesgul") if on else b.get_meta("st")
	for k in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	b.add_theme_stylebox_override("pressed", st if on else b.get_meta("st_bas"))
	b.disabled = on  # meşgul kişi aranamaz
	var etiket: Control = b.find_child("Mesgul", true, false)
	if etiket:
		etiket.visible = on
	var ara: Panel = b.find_child("Ara", true, false)
	if ara:
		var ds := _daire(Color(0.32, 0.33, 0.34), Color(0.5, 0.5, 0.5), 33, 0.0, 3) if on \
			else _daire(UI.YESIL.darkened(0.08), UI.YESIL.lightened(0.5), 33, 0.45, 3)
		ara.add_theme_stylebox_override("panel", ds)
		ara.modulate = Color(0.75, 0.75, 0.75, 0.7) if on else Color.WHITE


func _pill_gizle() -> void:
	_call_state = ""
	_call_who = ""
	_call_time_text = ""
	_pill_dalga.acik = false
	for ch in _pill_avatar_kutu.get_children():
		if ch != _pill_dalga:
			ch.queue_free()
	if _pill.visible:
		_pill.set_meta("gizleniyor", true)
		var tw := _pill.create_tween()
		tw.tween_property(_pill, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func() -> void:
			if _pill.has_meta("gizleniyor"):
				_pill.remove_meta("gizleniyor")
				_pill.visible = false
				# geniş "MEŞGUL" yazısından sonra şerit eski genişliğine dönsün (sağa yaslı, sola doğru büyür)
				_pill.offset_left = _pill.offset_right)


# Gelen arama: main.gd ring_label'ı yazar ("Telefon çalıyor: Ali") ve görünür yapar; şerit bunu izler.
func _update_ring() -> void:
	var caliyor := ring_label.visible
	if caliyor and (_call_state == "" or _call_state == "caliyor"):
		var t := ring_label.text
		var who := t.get_slice(": ", 1) if t.contains(": ") else t
		if _call_state != "caliyor" or who != _call_who:
			_pill_kur("caliyor", who)
	elif not caliyor and _call_state == "caliyor":
		_pill_gizle()


# Arama ekranı. text: "Çalıyor…" (sen arıyorsun), "Bağlanıyor…", "Konuşuyorsunuz 0:23"
# ya da çevrimdışı konuşmada karşı tarafın söylediği cümle (altta altyazı olarak çıkar).
func show_call(who: String, text: String) -> void:
	var k := text.to_lower()
	if k.begins_with("çalıyor"):
		_pill_kur("ariyor", who)
		call_panel.visible = false
	elif k.begins_with("bağlanıyor"):
		_pill_kur("baglaniyor", who)
		call_panel.visible = false
	else:
		if _call_state != "hatta" or who != _call_who:
			_pill_kur("hatta", who)
		var m: RegExMatch = null
		if k.begins_with("konuşuyor"):
			m = RegEx.create_from_string("(\\d+:\\d\\d)").search(text)
		if m:
			_call_time_text = m.get_string(1)
			_pill_durum.text = tr("● HATTA  %s") % _call_time_text
			call_panel.visible = false
		else:
			_call_time_text = ""
			_subtitle(who, text)


func _subtitle(who: String, text: String) -> void:
	var s := text.strip_edges()
	if s == "" or s == "…":
		call_panel.visible = false
		return
	if call_text.text == text and call_panel.visible:
		return
	call_title.text = Dil.buyuk(who)
	call_text.text = text
	var av: Control = call_panel.find_child("Av", true, false)
	if str(av.get_meta("ad", "")) != who:
		for ch in av.get_children():
			ch.queue_free()
		av.add_child(OU.avatar(who, 52))
		av.set_meta("ad", who)
	call_panel.visible = true
	call_panel.modulate.a = 0.0
	call_panel.create_tween().tween_property(call_panel, "modulate:a", 1.0, 0.2)


func hide_call() -> void:
	call_panel.visible = false
	_pill_gizle()


# main.gd _set_call_bar buraya bağlanır: "" = şerit kapanır; "● Ali aranıyor…" / "● Hatta: Ali   0:23".
func set_call_bar(text: String) -> void:
	if text == "":
		hide_call()
		return
	var t := text.trim_prefix("●").strip_edges()
	if t.begins_with("Hatta:"):
		var rest := t.trim_prefix("Hatta:").strip_edges()
		var m := RegEx.create_from_string("^(.*?)\\s+(\\d+:\\d\\d)$").search(rest)
		if m:
			if _call_state != "hatta" or m.get_string(1) != _call_who:
				_pill_kur("hatta", m.get_string(1))
			_call_time_text = m.get_string(2)
			_pill_durum.text = tr("● HATTA  %s") % _call_time_text
		elif _call_state != "hatta":
			_pill_kur("hatta", rest)
	elif t.ends_with("aranıyor…") and _call_state == "":
		_pill_kur("ariyor", t.trim_suffix("aranıyor…").strip_edges())


# ---------------------------------------------------------------- şikayet

func _account() -> Node:
	var p := get_parent()
	if p == null:
		return null
	var a = p.get("account")
	return a if a is Node else null


# Oyuncuyu şikayet et penceresi (neden seçtirir). oyuncu_id > 0: maçtaki oyuncu, oda sunucusuna
# {"t":"sikayet","id":..} gider ve sunucu oda içi numarayı hesaba çevirir; değilse hesap sunucusuna.
func open_report(ad: String, handle := "", oda := "", host: Node = null, oyuncu_id := 0) -> void:
	OU.sikayet(host if host else _ust, _account(), ad, handle, oda, _oda_gonder(oyuncu_id))


# Oda bağlantısı üzerinden oyuncu numarasıyla gönderen işlev (numara yoksa boş Callable)
func _oda_gonder(oyuncu_id: int) -> Callable:
	if oyuncu_id <= 0:
		return Callable()
	var p := get_parent()
	var n = p.get("net") if p else null
	if not (n is Node):
		return Callable()
	var ag: Node = n
	return func(d: Dictionary) -> void:
		d["id"] = oyuncu_id
		ag.call("send", d)


# ---------------------------------------------------------------- bekleme salonu

func _build_lobby() -> void:
	lobby_panel = Control.new()
	lobby_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby_panel.visible = false
	_root.add_child(lobby_panel)
	_root.move_child(lobby_panel, _toast_host.get_index())

	# --- sol üst: oda kartı (kod, kopyala, çık, hazır sayısı, kurucu ayarları)
	_lobby_card = UI.panel(Vector2(380, 0), 34)
	lobby_panel.add_child(_lobby_card)
	_place_kenar(_lobby_card, Control.PRESET_TOP_LEFT, Vector2(MIK_OFS.x + MIK_PX + 12, 6), Vector2.ZERO)  # ayarlar + mikrofonun sağında
	_tap_blockers.append(_lobby_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	_lobby_card.add_child(v)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", UI.B_S)
	v.add_child(r1)
	var kv := VBoxContainer.new()
	kv.add_theme_constant_override("separation", -2)
	kv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(kv)
	kv.add_child(UI.label("ODA KODU", UI.FS_KUCUK, UI.METIN_SOLUK))
	_lobby_code = UI.title("----", 40, UI.AMBER)
	kv.add_child(_lobby_code)
	var kop := UI.icon_button("kopyala", "ikincil", UI.DOKUNMA)
	kop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kop.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_lobby_code_text)
		_toast_ver(tr("Oda kodu kopyalandı: %s") % _lobby_code_text, "basari"))
	r1.add_child(kop)
	var cik := UI.button("ÇIK", "tehlike", UI.BTN_H_KUCUK, UI.FS_ORTA, "", 92)
	cik.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cik.pressed.connect(func() -> void: lobby_leave.emit())
	r1.add_child(cik)
	# oda bilgisi (ODA KUR ayarı: ad, Herkes/Arkadaşlarım, kişi/sınır; sahip dokununca ODA AYARI) — scripts/odalar.gd
	_lobby_oda = OdalarUI.lobi_bilgi(self)
	v.add_child(_lobby_oda)
	# hazır sayısı
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", UI.B_XS)
	v.add_child(r2)
	var oi := UI.icon("onay", 30)
	oi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(oi)
	_lobby_ready_lbl = UI.title("", UI.FS_METIN, UI.METIN)
	_lobby_ready_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(_lobby_ready_lbl)
	# Hızlı Oyun geri sayımı
	var cd := VBoxContainer.new()
	cd.add_theme_constant_override("separation", 4)
	cd.visible = false
	v.add_child(cd)
	_lobby_count_row = cd
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", UI.B_XS)
	cd.add_child(cr)
	_lobby_count_num = UI.title("25", UI.FS_BUYUK, UI.AMBER)
	cr.add_child(_lobby_count_num)
	var cl := UI.label("sn içinde başlıyor", UI.FS_METIN, UI.METIN)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cr.add_child(cl)
	_lobby_count_cr = cr
	# geri sayım yalnız herkes HAZIR iken: değilse bu yazı görünür
	_lobby_count_lbl = UI.label("Herkes hazır olunca başlar", UI.FS_METIN, UI.AMBER)
	_lobby_count_lbl.visible = false
	UI.sigdir(_lobby_count_lbl, 330)
	cd.add_child(_lobby_count_lbl)
	_lobby_count_bar = UI.progress(1.0, 320, 24)
	cd.add_child(_lobby_count_bar)
	# kurucu: oyun seçici + bot
	_lobby_host_box = VBoxContainer.new()
	_lobby_host_box.add_theme_constant_override("separation", UI.B_S)
	v.add_child(_lobby_host_box)
	_lobby_game_btn = UI.button(str(GAME_CHOICES[game_pick][1]), "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN, "oyna")
	_lobby_game_btn.pressed.connect(_oyun_sec)
	_lobby_host_box.add_child(_lobby_game_btn)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", UI.B_S)
	# elle BOT ekle / çıkar kullanıcı isteğiyle kaldırıldı (27 Ekim 2026, mağaza incelemesi öncesi): satır gizli.
	# Botlar yalnız kendiliğinden gelir: Hızlı Oyun boş yerleri doldurur, ODA KUR'da "Botla doldur" seçilebilir.
	br.visible = false
	_lobby_host_box.add_child(br)
	var bi := UI.icon("bot", 46)
	bi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(bi)
	var bl := UI.title("BOT", UI.FS_ORTA, UI.METIN)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(bl)
	_lobby_bot_minus = UI.button("-", "ikincil", UI.BTN_H_KUCUK, UI.FS_BUYUK, "", 64)
	_lobby_bot_minus.pressed.connect(func() -> void: lobby_bot.emit(false))
	br.add_child(_lobby_bot_minus)
	_lobby_bot_num = UI.title("0", UI.FS_BUYUK, UI.METIN, true)
	_lobby_bot_num.custom_minimum_size.x = 40
	_lobby_bot_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(_lobby_bot_num)
	_lobby_bot_plus = UI.button("+", "ikincil", UI.BTN_H_KUCUK, UI.FS_BUYUK, "", 64)
	_lobby_bot_plus.pressed.connect(func() -> void: lobby_bot.emit(true))
	br.add_child(_lobby_bot_plus)

	# --- sağ üst: oyuncu kartları
	_lobby_strip = HBoxContainer.new()
	_lobby_strip.add_theme_constant_override("separation", 6)
	_lobby_strip.alignment = BoxContainer.ALIGNMENT_END
	lobby_panel.add_child(_lobby_strip)
	_place_kenar(_lobby_strip, Control.PRESET_TOP_RIGHT, Vector2(-14, 10), Vector2.ZERO)
	_lobby_strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tap_blockers.append(_lobby_strip)

	# --- alt orta: DAVET · HAZIRIM · BAŞLAT
	_lobby_bar = HBoxContainer.new()
	_lobby_bar.add_theme_constant_override("separation", UI.B_S)
	_lobby_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	lobby_panel.add_child(_lobby_bar)
	_place(_lobby_bar, Control.PRESET_CENTER_BOTTOM, Vector2(-14, -90), Vector2.ZERO)
	_lobby_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tap_blockers.append(_lobby_bar)
	_lobby_invite_btn = UI.button("DAVET", "ikincil", UI.BTN_H, UI.FS_ORTA, "davet", 166)
	_lobby_invite_btn.pressed.connect(func() -> void: lobby_invite.emit())
	_lobby_bar.add_child(_lobby_invite_btn)
	_lobby_ready_btn = UI.button("HAZIRIM", "ana", UI.BTN_H, UI.FS_ORTA, "onay", 200)
	_lobby_ready_btn.pressed.connect(func() -> void:
		_ready_on = not _ready_on
		_hazir_gorunum()
		lobby_ready.emit(_ready_on))
	_lobby_bar.add_child(_lobby_ready_btn)
	_lobby_start_btn = UI.button("BAŞLAT", "ana", UI.BTN_H, UI.FS_ORTA, "oyna", 206)
	_lobby_start_btn.pressed.connect(func() -> void: lobby_start.emit())
	# HAZIR demeyen varken BAŞLAT gri ve pasif; dokununca neden başlamadığı söylenir
	_lobby_start_btn.gui_input.connect(func(e: InputEvent) -> void:
		var bas: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)
		if bas and _lobby_start_btn.disabled:
			_toast_ver(tr("Herkes hazır değil: {0}").format([", ".join(_hazir_olmayanlar())]), "hata"))
	_lobby_bar.add_child(_lobby_start_btn)


func _hazir_gorunum() -> void:
	if not _lobby_ready_btn:
		return
	UI.set_button_text(_lobby_ready_btn, "HAZIRSIN" if _ready_on else "HAZIRIM")
	# ekranda tek amber ana eylem: kurucuda BAŞLAT, misafirde HAZIRIM
	UI.set_button_kind(_lobby_ready_btn, "yesil" if _ready_on else ("ikincil" if _lobby_host else "ana"))


func _oyun_sec() -> void:
	var m := UI.modal("OYUN SEÇ", 720)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", UI.B_S)
	g.add_theme_constant_override("v_separation", UI.B_S)
	m.body.add_child(g)
	for i in GAME_CHOICES.size():
		var b := UI.button(str(GAME_CHOICES[i][1]), "ana" if i == game_pick else "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN, "", 318)
		var k := i
		b.pressed.connect(func() -> void:
			game_pick = k
			UI.set_button_text(_lobby_game_btn, str(GAME_CHOICES[k][1]))
			m.close())
		g.add_child(b)
	_ust.add_child(m)


func show_lobby(on: bool) -> void:
	if not lobby_panel:
		_build_lobby()
	var acildi := on and not lobby_panel.visible
	lobby_panel.visible = on
	for p in _game_pills:
		p.visible = not on
	if on:
		if hint:
			hint.visible = false
	if acildi:
		# giriş: oda kartı soldan, oyuncular üstten, düğmeler alttan kayar
		_kay(_lobby_card, -440.0, 0.0)
		_kay(_lobby_strip, 0.0, -170.0)
		_kay(_lobby_bar, 0.0, 140.0)


# Hızlı Oyun odasında geri sayım: "25 sn içinde başlıyor". -1: herkes HAZIR değil, geri sayım durdu
# ("Herkes hazır olunca başlar"; HAZIR demeyen bir süre sonra kendiliğinden hazır sayılır, sunucu OTO_HAZIR).
func set_public_countdown(seconds: int) -> void:
	if float(seconds) > _public_left + 1.5:
		_public_total = maxf(1.0, float(seconds))
	_public_left = float(seconds)
	if not lobby_panel:
		_build_lobby()
	var bekle := seconds < 0
	_lobby_count_row.visible = true
	_lobby_count_cr.visible = not bekle
	_lobby_count_bar.visible = not bekle
	_lobby_count_lbl.visible = bekle
	_lobby_count_num.text = str(maxi(seconds, 0))


func _player_card(p: Dictionary, me: bool, yeni: bool) -> Button:
	var hazir := bool(p.get("r", false))
	var bot := bool(p.get("bot", false))
	var ad := str(p.get("name", "?"))
	var handle := str(p.get("handle", ""))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(88, 146)
	var st := UI.flat(Color(UI.YUZEY, 0.92), Color(UI.YESIL, 0.9) if hazir else UI.CIZGI, UI.R_ORTA)
	st.set_border_width_all(2)
	st.border_width_bottom = 5
	st.shadow_size = 6
	st.content_margin_left = 4
	st.content_margin_right = 4
	if me:
		st.border_color = UI.AMBER
		st.bg_color = Color(UI.YUZEY_2, 0.96)
	for k in ["normal", "hover", "focus", "pressed", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 12
	v.offset_bottom = -6
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ak := Control.new()
	ak.custom_minimum_size = Vector2(62, 62)
	ak.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ak)
	var ms := bool(p.get("ms", false))  # hâlâ maç sonu ekranında (lobiye dönmedi)
	var av := OU.avatar(ad, 62, UI.YESIL if hazir else Color(0, 0, 0, 0))
	if not hazir:
		av.modulate = Color(0.78, 0.78, 0.78) if not ms else Color(0.5, 0.5, 0.5)
	ak.add_child(av)
	if ms:
		var mp := PanelContainer.new()
		var mst := UI.flat(Color(UI.AMBER_KOYU.darkened(0.35), 0.96), UI.AMBER, 8)
		mst.set_border_width_all(2)
		mst.content_margin_left = 4
		mst.content_margin_right = 4
		mst.content_margin_top = 0
		mst.content_margin_bottom = 0
		mp.add_theme_stylebox_override("panel", mst)
		mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ml := UI.title("MAÇ SONU", 13, Color.WHITE, true)
		UI.sigdir(ml, 74)
		mp.add_child(ml)
		_place(mp, Control.PRESET_CENTER_BOTTOM, Vector2(-41, -18), Vector2(82, 22))
		ak.add_child(mp)
	if bool(p.get("host", false)):
		var cr := UI.icon("tac", 32)
		_place(cr, Control.PRESET_TOP_LEFT, Vector2(-14, -18), Vector2(32, 32))
		cr.pivot_offset = Vector2(16, 16)
		cr.rotation = -0.35
		ak.add_child(cr)
	if bot:
		var bi := UI.icon("bot", 30)
		_place(bi, Control.PRESET_TOP_LEFT, Vector2(42, -14), Vector2(30, 30))
		ak.add_child(bi)
	if hazir:
		var ok := UI.icon("onay", 32)
		_place(ok, Control.PRESET_TOP_LEFT, Vector2(40, 36), Vector2(32, 32))
		ak.add_child(ok)
	if bool(p.get("mk", false)) or (me and mik_kapali):
		# mikrofonu kapalı: avatarın sol altında küçük kırmızı çizik mikrofon
		var mk := Mik.new()
		mk.durum = "kapali"
		mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(mk, Control.PRESET_TOP_LEFT, Vector2(-12, 34), Vector2(36, 36))
		ak.add_child(mk)
	var nm := UI.title(ad, UI.FS_KUCUK, UI.METIN if hazir or me else UI.METIN_SOLUK, true)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = 80
	v.add_child(nm)
	v.add_child(hazir_rozet(hazir and not ms))
	if not me and not bot:
		# kart menüsü: dokun ya da uzun bas -> ŞİKAYET ET (/ ENGELLE)
		var menu := func() -> void:
			var pid := int(p.get("id", 0))
			var items := [["ŞİKAYET ET", "sikayet", "tehlike", func() -> void: open_report(ad, handle, _lobby_code_text, null, pid)]]
			# maçtaki oyuncu oda içi numarasıyla engellenir (misafir de olsa; sunucu hesaba çevirir)
			items.append(["ENGELLE", "engelle", "ikincil", func() -> void: OU.engelle(_ust, _account(), ad, handle, Callable(), _oda_gonder(pid))])
			OU.menu(_ust, b, items, 262)
		OU.uzun_bas(b, menu)
		b.pressed.connect(func() -> void:
			if not bool(b.get_meta("uzun", false)):
				menu.call())
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.95, 0.05)
		UI.tik())
	b.button_up.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
	if yeni:
		b.modulate.a = 0.0
		b.scale = Vector2.ONE * 0.7
		b.pivot_offset = Vector2(44, 73)
		var tw := b.create_tween().set_parallel(true)
		tw.tween_property(b, "modulate:a", 1.0, 0.2)
		tw.tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return b


# BAŞLAT'ı bekleten insanlar (HAZIR demeyen ya da hâlâ maç sonu ekranında olan; kurucu ve botlar hariç)
func _hazir_olmayanlar() -> PackedStringArray:
	var adlar := PackedStringArray()
	if _lobby_son.size() < 3:
		return adlar
	for p in _lobby_son[1]:
		if bool(p.get("bot", false)) or int(p.get("id", 0)) == int(_lobby_son[2]):
			continue
		if not bool(p.get("r", false)) or bool(p.get("ms", false)):
			adlar.append(str(p.get("name", "?")))
	return adlar


# Oyuncu kartının altındaki durum: yeşil HAZIR / kırmızı HAZIR DEĞİL
static func hazir_rozet(on: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	var st := UI.flat(Color(UI.YESIL.darkened(0.25), 0.95) if on else Color(UI.KIRMIZI.darkened(0.45), 0.92), UI.YESIL if on else Color(UI.KIRMIZI, 0.8), 8)
	st.set_border_width_all(2)
	st.content_margin_left = 2
	st.content_margin_right = 2
	st.content_margin_top = 0
	st.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", st)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UI.title("HAZIR" if on else "HAZIR DEĞİL", 15, Color.WHITE, true)
	UI.sigdir(l, 78)
	pc.add_child(l)
	return pc


func update_lobby(code: String, players: Array, my_id: int, is_host: bool) -> void:
	if not lobby_panel:
		_build_lobby()
	_lobby_son = [code, players, my_id, is_host]
	_lobby_host = is_host
	_lobby_code_text = code
	_lobby_code.text = code
	var ready_n := 0
	var bots := 0
	for p in players:
		if bool(p.get("r", false)):
			ready_n += 1
		if bool(p.get("bot", false)):
			bots += 1
		if int(p.get("id", 0)) == my_id:
			_ready_on = bool(p.get("r", false))
	_lobby_ready_lbl.text = tr("%d/%d HAZIR") % [ready_n, players.size()]
	_lobby_host_box.visible = is_host
	_lobby_bot_num.text = str(bots)
	_lobby_bot_minus.disabled = bots == 0
	_lobby_bot_plus.disabled = players.size() >= mini(MAX_OYUNCU, OdalarUI.sinir(self))
	OdalarUI.lobi_bilgi_guncelle(_lobby_oda, players, is_host)
	_lobby_start_btn.visible = is_host
	# BAŞLAT: odadaki bütün insanlar HAZIR olmalı (botlar hep hazır; kurucunun BAŞLAT'ı kendi hazırı sayılır)
	_lobby_start_btn.disabled = not _hazir_olmayanlar().is_empty()
	_hazir_gorunum()
	# oyuncu kartları (sen en solda); yeni gelen kart büyüyerek belirir
	for ch in _lobby_strip.get_children():
		_lobby_strip.remove_child(ch)
		ch.queue_free()
	var sirali := players.duplicate()
	sirali.sort_custom(func(a, b) -> bool:
		var am := int(a.get("id", 0)) == my_id
		var bm := int(b.get("id", 0)) == my_id
		if am != bm:
			return am
		return int(a.get("cell", 0)) < int(b.get("cell", 0)))
	var ids := []
	for p in sirali:
		var id := int(p.get("id", 0))
		ids.append(id)
		_lobby_strip.add_child(_player_card(p, id == my_id, not _lobby_ids.is_empty() and not (id in _lobby_ids)))
	_lobby_ids = ids


# ---------------------------------------------------------------- dokunma (joystick / bakış)

# Ortadaki küçük ölü bölge titremeyi keser; kenara yakın itince tam hız (koşma).
func _update_joy(pos: Vector2) -> void:
	var c := joy.get_global_rect().get_center()
	var raw := pos - c
	joy.active = true
	sprint = raw.y < -JOY_R * 1.95 and absf(raw.x) < 80.0
	joy.sprint = sprint
	var v := raw.limit_length(JOY_R)
	joy.knob = v
	if sprint:
		move = Vector2(0, -1)
		joy.queue_redraw()
		return
	var m := v.length() / JOY_R
	m = 0.0 if m < 0.12 else minf(1.0, (m - 0.12) / 0.8)
	move = v.normalized() * m if v.length() > 0.0 else Vector2.ZERO
	joy.queue_redraw()


# Oyun penceresi (tahta, sigorta kutusu, rol kartı, tur sonu, yardım) açık mı? Açıkken joystick ve bakış
# çalışmaz: kutuda kablo sürüklerken karakter yürümesin, kamera dönmesin.
func _oyun_penceresi() -> bool:
	var gu = get_parent().get("game_ui") if get_parent() else null
	return gu is Node and (gu as Node).has_method("pencere_acik") and gu.pencere_acik()


func _over_button(pos: Vector2) -> bool:
	# açık pencere, menü ya da rehber varken joystick / bakış çalışmaz
	if contacts.visible or _ust.get_child_count() > 0 or _tel_kok.get_child_count() > 1 or _oyun_penceresi():
		return true
	if _pill.visible and _pill.get_global_rect().grow(10).has_point(pos):
		return true
	for c in _tap_blockers:
		if c.is_visible_in_tree() and c.get_global_rect().grow(10).has_point(pos):
			return true
	# oyunun alttaki ana düğmesi (EŞLEŞTİR, SAYI YAZ, OYLA) ve üstteki görev bandı
	var gu = get_parent().get("game_ui") if get_parent() else null
	if gu is CanvasLayer and (gu as CanvasLayer).visible:
		for ad in ["_write_btn", "_banner"]:
			var c = gu.get(ad)
			if c is Control and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().grow(10).has_point(pos):
				return true
	return action_btn.visible and action_btn.get_global_rect().grow(10).has_point(pos)


# Joystick: ekranın sol yarısında parmağın değdiği yerde açılır (ayarlardan sabit yapılabilir).
func _joy_zone(pos: Vector2) -> bool:
	var vs := get_viewport().get_visible_rect().size
	if floating_joy:
		return pos.x < vs.x * 0.42 and pos.y > vs.y * 0.3 and not _over_button(pos)
	return joy.get_global_rect().grow(60).has_point(pos) and not _over_button(pos)


# Bir pencere açılınca basılı joystick / bakış bırakılır (tahta kendiliğinden açılınca karakter durur).
func _dokunma_birak() -> void:
	if joy_index != -1:
		joy_index = -1
		joy.knob = Vector2.ZERO
		joy.active = false
		joy.sprint = false
		sprint = false
		move = Vector2.ZERO
		_place_kenar(joy, Control.PRESET_BOTTOM_LEFT, JOY_HOME, Vector2(240, 240))
		joy.queue_redraw()
	look_index = -1


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var vw := get_viewport().get_visible_rect().size.x
		if event.pressed:
			if joy_index == -1 and _joy_zone(event.position):
				joy_index = event.index
				if floating_joy:
					joy.global_position = event.position - joy.size / 2.0
				_update_joy(event.position)
			elif look_index == -1 and not _over_button(event.position) and event.position.x > vw * 0.3:
				look_index = event.index
		else:
			if event.index == joy_index:
				joy_index = -1
				joy.knob = Vector2.ZERO
				joy.active = false
				joy.sprint = false
				sprint = false
				move = Vector2.ZERO
				_place_kenar(joy, Control.PRESET_BOTTOM_LEFT, JOY_HOME, Vector2(240, 240))
				joy.queue_redraw()
			if event.index == look_index:
				look_index = -1
	elif event is InputEventScreenDrag:
		if event.index == joy_index:
			_update_joy(event.position)
		elif event.index == look_index and player:
			player.look(event.relative)
