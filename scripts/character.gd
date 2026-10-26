# Karakter & Mağaza ekranı: solda dönen 3D önizleme (ad kutusu altında), sağda kategori sekmeleri,
# nadirlik çerçeveli eşya kartları ve alt eylem çubuğu (seçilen eşya, SATIN AL, KAYDET).
# Kilitli parçalar önizlenebilir; satın alma onay penceresiyle sunucuda yapılır. Kasa sekmesinde iki kasa
# ve CS:GO tarzı açılış gösterisi (spin). Kaydederken yalnızca sahip olunan parçalar kalır.
# Vitrin: haftanın seti (büyük kart) + günün 6 fırsatı, geri sayımlarla. Setler: indirimli tematik paketler
# (sahip olunan parça fiyattan düşer). Kasa: şans güvencesi sayacı, olasılıklar, seviye yolundan ücretsiz kasa.
# Alt çubukta istek listesi (kalp) ve arkadaşa hediye. Fiyat ve sonuçlar sunucuda (server/src/market.js).
extends CanvasLayer

signal closed(saved: bool)

const Catalog := preload("res://scripts/catalog.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const ThumbsScript := preload("res://scripts/thumbs.gd")
const Fx := preload("res://scripts/store_fx.gd")
const CAT_ICONS := {"vitrin": "deal", "setler": "gift", "sandik": "chest", "govde": "profile", "ten": "skin", "sac": "hair", "sac_renk": "hair", "sakal": "beard", "kiyafet": "outfit", "aksesuar": "accessory", "sapka": "hat", "dovme": "tattoo", "hareket": "emote"}
const TAB_NAMES := {"vitrin": "VİTRİN", "setler": "SETLER", "sandik": "KASA", "govde": "KARAKTER", "ten": "TEN", "sac": "SAÇ", "sac_renk": "SAÇ RENGİ", "sakal": "SAKAL",
	"sapka": "ŞAPKA", "dovme": "DÖVME", "kiyafet": "KIYAFET", "aksesuar": "AKSESUAR", "hareket": "HAREKET"}
const COLOR_CATS := ["ten", "sac_renk", "goz"]
const CATS := ["vitrin", "setler", "sandik", "govde", "ten", "sac", "sac_renk", "sakal", "sapka", "dovme", "kiyafet", "aksesuar", "hareket"]
# Kasalar: [ad, fiyat, altın mı, nadirlik ağırlıkları SIRADAN/NADİR/EPİK/EFSANE, sunucudaki tür]
# (sunucudaki ekonomi.js CHESTS ile aynı; olasılıklar sunucudan da gelir: eco.olasilik)
const CHESTS := [["Tahta kasa", 100, false, [55, 35, 9, 1], "tahta"], ["Altın kasa", 400, true, [0, 35, 45, 20], "altin"]]
# Başlangıç Paketi'nden gelen hediye kasa (elmasla alınmaz; hakkı varsa görünür)
const HEDIYE_KASA := ["Hediye kasa", 0, true, [0, 70, 25, 5], "nadir"]
const NADIR_KEYS := ["siradan", "nadir", "epik", "efsane"]
# Kasa görselleri [kapalı, açık] (assets/ui/uretim/)
const CHEST_ART := [["uretim/kasa_kapali", "uretim/kasa_acik"], ["uretim/kasa_altin_kapali", "uretim/kasa_altin_acik"]]
# Kasa şeridi: kart sayısı, kazananın sırası, kart boyu, aralık ve dönme süresi (sn)
const REEL_N := 56
const REEL_WIN := 48
const REEL_CARD := Vector2(172, 212)
const REEL_GAP := 8.0
const REEL_TIME := 6.2
const RARITY := Catalog.RARITY
const STAGE_RATIO := 0.6  # sol önizleme / sağ içerik genişlik oranı

var profile: Node
var account: Node  # sunucu bağlantısı: satın alma ve kasa sonucu buradan
var _look: Dictionary
var _cat := "vitrin"
var _gems_shown := -1.0
var _gem_label: Label
var _countdown: Label
var _deal_price := -1  # vitrinden seçilen ürünün indirimli fiyatı
var _preview_item := ""  # hareket kategorisinde önizlenen
var _body: Node3D
var _turntable: Node3D
var _cam: Camera3D
var _close_up := true
var _name_edit: LineEdit
var _kok: Control
var _tab_scroll: ScrollContainer
var _cat_row: HBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _grid: GridContainer
var _grid_min_w := 168.0
var _sel_box: VBoxContainer
var _sel_name: Label
var _sel_sub: Label
var _buy_btn: Button
var _daily_btn: Button
var _zoom_btn: Button
var _pending := ["", ""]  # satın alınacak / önizlenen [kategori, kimlik]
var _thumbs: Node
var _opening := false  # kasa açılırken ikinci dokunuş yok sayılır
var _refund := -1  # son kasa kopya çıktıysa sunucunun geri verdiği elmas
var _chest_btns: Array = []
var _anim := true
var _countdown_w: Label  # haftanın seti geri sayımı
var _wish_btn: Button  # istek listesi (kalp)
var _wish_heart: Control
var _gift_btn: Button
var _emote_loop := 0.0  # hareket önizlemesi bitince yeniden oynatma sayacı
var _last_garanti := false  # son kasa güvenceden mi geldi
var _yenile_istendi := false  # vitrin süresi dolunca sunucudan yeni vitrin istendi mi
var _sahne_sv: SubViewport  # sol 3D vitrin


# ---------------------------------------------------------------------
# Ortak parçalar (envanter.gd, menu.gd ve diğerleri de kullanır)
# ---------------------------------------------------------------------

class Gem extends Control:
	func _draw() -> void:
		var s := size
		var pts := PackedVector2Array([Vector2(s.x * 0.5, 0), Vector2(s.x, s.y * 0.38), Vector2(s.x * 0.5, s.y), Vector2(0, s.y * 0.38)])
		draw_colored_polygon(pts, Color("#3fd6f0"))
		draw_colored_polygon(PackedVector2Array([pts[0], pts[1], Vector2(s.x * 0.5, s.y * 0.38), pts[3]]), Color("#a8f2ff"))


# Kasa şeridi kartı: nadirlik çerçevesi (assets/ui/uretim/kart_*.png), arkasında seçiliyken renkli ışık,
# içinde eşyanın küçük resmi (gelene kadar kategori simgesi) ve adı.
class LootCard extends Control:
	var accent := Color.WHITE
	var glow := 0.0  # kazanan / giyili kartın parlaması (0-1)
	var thumb: TextureRect
	var holder: Control  # resim gelene kadar görünen simge
	var name_label: Label
	var tier_label: Label
	var skin_bg: Panel  # dövmelerde ten renginde yuvarlak zemin
	var frame: StyleBox  # üretilmiş kart çerçevesi varsa

	func _ready() -> void:
		resized.connect(_layout)
		_layout()

	func _process(_d: float) -> void:
		if holder and thumb and thumb.texture != null:
			holder.visible = false
			set_process(false)

	# Çerçeve resmi varken içerik kenar süslerinin içinde kalır.
	func inset() -> float:
		return clampf(size.x * 0.1, 10.0, 22.0) if frame else 0.0

	func _layout() -> void:
		var k := inset()
		var pic_h := size.y * (0.66 if frame else 0.66)
		var top := k + (20.0 if tier_label else 4.0)
		if tier_label:
			tier_label.position = Vector2(k + 9, k + 4)
			tier_label.size = Vector2(size.x - 2 * k - 18, 18)
		if thumb:
			thumb.position = Vector2(k + 4, top)
			thumb.size = Vector2(size.x - 2 * k - 8, pic_h - top + 4)
		if skin_bg:
			var d := minf(size.x - 2 * k - 36, pic_h - top - 6)
			skin_bg.size = Vector2(d, d)
			skin_bg.position = Vector2(size.x / 2.0 - d / 2.0, top + (pic_h - top) / 2.0 - d / 2.0)
			thumb.size = skin_bg.size * 0.9
			thumb.position = skin_bg.position + skin_bg.size * 0.05
		if holder:
			holder.position = Vector2(size.x / 2.0, top + (pic_h - top) / 2.0) - holder.size / 2.0
		if name_label:
			name_label.position = Vector2(k + 4, pic_h + 2)
			name_label.size = Vector2(size.x - 2 * k - 8, size.y - pic_h - k - 6.0)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if glow > 0.0:
			var sh := StyleBoxFlat.new()
			sh.bg_color = Color(accent, 0.5 * glow)
			sh.set_corner_radius_all(14)
			sh.shadow_color = Color(accent, 0.75 * glow)
			sh.shadow_size = int(26 * glow)
			draw_style_box(sh, r.grow(-4))
		if frame:
			draw_style_box(frame, r)
			var k := inset()
			var a0 := 0.18 + 0.25 * glow
			var t0 := size.y * 0.3
			var b0 := size.y - k - 2
			draw_polygon(PackedVector2Array([Vector2(k, t0), Vector2(size.x - k, t0), Vector2(size.x - k, b0), Vector2(k, b0)]),
				PackedColorArray([Color(accent, 0.0), Color(accent, 0.0), Color(accent, a0), Color(accent, a0)]))
			return
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.085, 0.09, 0.1, 0.97)
		bg.set_corner_radius_all(10)
		bg.border_color = accent.lerp(Color.WHITE, 0.35) if glow > 0.0 else accent.darkened(0.45)
		bg.set_border_width_all(3 if glow > 0.0 else 2)
		draw_style_box(bg, r)


# Kasa şeridinin ortasındaki ibre (üstte ve altta üçgen uçlu, her tıkta parlar).
class ReelPointer extends Control:
	var band_top := 14.0
	var band_h := 236.0
	var flash := 0.0
	var color := Color("#ffd23a")

	func _process(delta: float) -> void:
		if flash > 0.0:
			flash = maxf(0.0, flash - delta * 7.0)
			queue_redraw()

	func _draw() -> void:
		var x := size.x / 2.0
		var col := color.lerp(Color("#fff6d0"), flash)
		var y0 := band_top - 6.0
		var y1 := band_top + band_h + 6.0
		for k in 5:
			var w := 3.0 + (k + 1) * (4.0 + 3.0 * flash)
			draw_rect(Rect2(x - w / 2.0, y0, w, y1 - y0), Color(col, 0.07 + 0.08 * flash))
		draw_rect(Rect2(x - 1.5, y0, 3.0, y1 - y0), col)
		var t := 16.0
		draw_colored_polygon(PackedVector2Array([Vector2(x - t, y0 - t), Vector2(x + t, y0 - t), Vector2(x, y0 + 4)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(x - t, y1 + t), Vector2(x + t, y1 + t), Vector2(x, y1 - 4)]), col)


# Genişleyerek sönen şok dalgası halkası (kazanan kart ortaya çıkınca).
class Ring extends Control:
	var color := Color.WHITE
	var max_r := 420.0
	var width := 16.0
	var dur := 0.7
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta / dur
		if _t >= 1.0:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := 1.0 - pow(1.0 - _t, 3.0)
		draw_arc(Vector2.ZERO, max_r * k, 0.0, TAU, 96, Color(color, (1.0 - _t) * 0.9), maxf(1.5, width * (1.0 - _t)), true)


# İstek listesi kalbi: doluysa kırmızı, boşsa kontur.
class Heart extends Control:
	var on := false
	var color := Color("#ff4d6d")

	func _draw() -> void:
		var k := minf(size.x, size.y) / 36.0
		var pts := PackedVector2Array()
		for i in 40:
			var t := TAU * i / 40.0
			var x := 16.0 * pow(sin(t), 3)
			var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
			pts.append(size / 2.0 + Vector2(x, y - 2.5) * k)
		if on:
			draw_colored_polygon(pts, color)
		pts.append(pts[0])
		draw_polyline(pts, color if on else Color("#f3ead8"), maxf(2.0, k * 2.6), true)


# Kasa sekmesindeki olasılık çubuğu: nadirlik renkleriyle oransal parçalar.
class OddsBar extends Control:
	var weights: Array = []
	var colors: Array = []

	func _draw() -> void:
		var total := 0.0
		for w in weights:
			total += float(w)
		if total <= 0.0:
			return
		var x := 0.0
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.55)
		bg.set_corner_radius_all(int(size.y / 2.0))
		draw_style_box(bg, Rect2(Vector2(-2, -2), size + Vector2(4, 4)))
		for i in weights.size():
			var w := size.x * float(weights[i]) / total
			if w <= 0.0:
				continue
			draw_rect(Rect2(x, 0, maxf(1.0, w - 2.0), size.y), colors[i])
			x += w


static var _fade_mat: ShaderMaterial


# Küçük resmin alt kenarı yumuşakça kaybolur (omuzdan kesilmiş sert çizgi görünmesin).
static func _fade_material() -> ShaderMaterial:
	if _fade_mat == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;
void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	COLOR.a *= smoothstep(1.0, 0.72, UV.y);
}
"
		_fade_mat = ShaderMaterial.new()
		_fade_mat.shader = sh
	return _fade_mat


static func _tier_of(it: Array) -> Array:
	return ["", "ELMAS", "#3fd6f0"] if str(it[0]) == "elmas" else Catalog.rarity(int(it[3]))


# Kasa şeridi kartı. it: [kategori, kimlik, ad, fiyat]; kategori "elmas" ise elmas ödülü kartıdır.
static func loot_card(it: Array, thumbs: Node, look: Dictionary, show_tier := false, name_size := 15) -> LootCard:
	var cat: String = it[0]
	var id: String = it[1]
	var tier: Array = _tier_of(it)
	var c := LootCard.new()
	var rk := UI.rarity_key(str(tier[1]))
	c.accent = UI.rarity_color(rk) if rk != "" else Color(tier[2])
	var fr := "uretim/kart_" + (rk if rk != "" else "nadir")
	if UI.has(fr):
		c.frame = UI.kit_sbox(fr, 220, UI.KESIM.kart_nadirlik, Vector4.ZERO)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if show_tier:
		c.tier_label = UI.title(str(tier[1]), 13, c.accent.lightened(0.35))
		c.add_child(c.tier_label)
	c.holder = UI.icon(str(CAT_ICONS.get(cat, "chest")), 58)
	c.holder.modulate = Color(1, 1, 1, 0.5)
	c.holder.size = Vector2(58, 58)
	c.add_child(c.holder)
	if cat == "dovme" and id != "yok":
		c.skin_bg = Panel.new()
		var sk := Color(Catalog.SKIN[int(look.get("ten", 1))])
		c.skin_bg.add_theme_stylebox_override("panel", UI.flat(sk, sk.darkened(0.3), 80))
		c.skin_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(c.skin_bg)
	c.thumb = TextureRect.new()
	c.thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	c.thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not (cat == "dovme" and id != "yok") and cat != "elmas":
		c.thumb.material = _fade_material()
	c.add_child(c.thumb)
	c.name_label = UI.title(str(it[2]), name_size, UI.METIN, true)
	c.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	c.name_label.max_lines_visible = 2
	c.add_child(c.name_label)
	if cat == "elmas":
		c.thumb.texture = UI.texture("gem_pile", 256)
	elif cat == "dovme" and id != "yok":
		c.thumb.texture = BodyScript.ink_texture(id)
	elif thumbs:
		thumbs.request(look, cat, id, c.thumb)
	return c


# Mağaza / envanter eşya kartı: nadirlik çerçevesi (UI.card_frame), resim, ad ve alt satır (fiyat ya da durum).
# Seçiliyken arkasında amber ışık yanar: set_card_selected(b, true). Alt satıra öğe: b.get_meta("foot").
static func item_card(cat: String, id: String, title: String, rarity: String, thumbs: Node, look: Dictionary, h := 224.0) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var empty := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, empty)
	# seçim ışığı: çerçevenin arkasında amber hale + ince kenar
	var sel := Panel.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(UI.AMBER, 0.22)
	ss.border_color = Color(UI.AMBER, 0.95)
	ss.set_border_width_all(3)
	ss.set_corner_radius_all(UI.R_ORTA)
	ss.shadow_color = Color(UI.AMBER, 0.5)
	ss.shadow_size = 16
	sel.add_theme_stylebox_override("panel", ss)
	sel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sel.offset_left = -3
	sel.offset_top = -3
	sel.offset_right = 3
	sel.offset_bottom = 3
	sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel.visible = false
	b.add_child(sel)
	var fr := UI.card_frame(rarity, Vector2(0, h))
	fr.custom_minimum_size = Vector2.ZERO
	fr.set_anchors_preset(Control.PRESET_FULL_RECT)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(fr)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.add_child(v)
	# resim alanı: alttan nadirlik renginde hafif ışıma
	var pic := Control.new()
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.clip_contents = true
	v.add_child(pic)
	var rc := UI.rarity_color(rarity) if rarity != "" else UI.METIN_SOLUK
	var gl := E.glow(rc, 0.32)
	gl.set_anchors_preset(Control.PRESET_FULL_RECT)
	gl.offset_top = 30
	gl.offset_bottom = 40
	pic.add_child(gl)
	var holder := UI.icon(str(CAT_ICONS.get(cat, "chest")), 56)
	holder.modulate = Color(1, 1, 1, 0.4)
	holder.set_anchors_preset(Control.PRESET_CENTER)
	holder.offset_left = -28
	holder.offset_top = -28
	holder.offset_right = 28
	holder.offset_bottom = 28
	pic.add_child(holder)
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.draw.connect(func() -> void: holder.visible = t.texture == null)
	if cat == "dovme" and id != "yok":
		# dövme: ten renginde yuvarlak zemin üstünde mürekkep resmi
		var sk := Color(Catalog.SKIN[int(look.get("ten", 1))])
		var disc := Panel.new()
		disc.add_theme_stylebox_override("panel", UI.flat(sk, sk.darkened(0.3), 200))
		disc.set_anchors_preset(Control.PRESET_CENTER)
		disc.offset_left = -52
		disc.offset_top = -52
		disc.offset_right = 52
		disc.offset_bottom = 52
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.add_child(disc)
		t.set_anchors_preset(Control.PRESET_CENTER)
		t.offset_left = -46
		t.offset_top = -46
		t.offset_right = 46
		t.offset_bottom = 46
		t.texture = BodyScript.ink_texture(id)
		holder.visible = false
	else:
		t.material = _fade_material()
		if thumbs and id != "":
			thumbs.request(look, cat, id, t)
	pic.add_child(t)
	var nm := UI.title(title, 17, UI.METIN, true)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	# uzun ad (Kovboy şapkası, Korsan şapkası, İngilizce adlar) kesilmesin: kart genişliğine göre küçülür
	nm.resized.connect(func() -> void: UI.sigdir(nm, nm.size.x - 4.0))
	v.add_child(nm)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 4)
	foot.custom_minimum_size.y = 28
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	b.set_meta("sel", sel)
	b.set_meta("foot", foot)
	b.set_meta("thumb", t)
	b.set_meta("pic", pic)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.95, 0.06))
	b.button_up.connect(func() -> void:
		b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(b, "scale", Vector2.ONE, 0.16))
	return b


static func set_card_selected(b: Button, on: bool) -> void:
	(b.get_meta("sel") as Control).visible = on


# Kartın sağ üst köşesine küçük kilit simgesi.
static func card_lock(b: Button) -> void:
	var ic := UI.icon("kilit", 30)
	ic.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ic.offset_left = -50
	ic.offset_right = -20
	ic.offset_top = 18
	ic.offset_bottom = 48
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)


# Fiyat satırı: elmas ikonu + sayı (yetmiyorsa kırmızımsı).
static func price_row(box: HBoxContainer, price: int, enough := true, size := 20) -> void:
	var g := UI.icon("elmas", size + 4)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(g)
	var l := UI.title(E.sayi(price), size, UI.ELMAS if enough else UI.KIRMIZI.lightened(0.25))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)


# Üst çubuktaki elmas sayacı + yeşil "+" (ikisi de elmas mağazasını açar). Sayı: get_meta("label").
static func gem_widget(on_open: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -10)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var gem_btn := Button.new()
	gem_btn.focus_mode = Control.FOCUS_NONE
	gem_btn.custom_minimum_size = Vector2(170, UI.DOKUNMA)
	var bos := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus"]:
		gem_btn.add_theme_stylebox_override(k, bos)
	var gem := UI.counter("elmas", "0", 44)
	gem.set_anchors_preset(Control.PRESET_FULL_RECT)
	gem.offset_top = 6
	gem.offset_bottom = -6
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(gem.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 22
	var l: Label = gem.get_meta("label")
	l.add_theme_color_override("font_color", UI.ELMAS)
	l.add_theme_font_size_override("font_size", 26)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gem_btn.add_child(gem)
	gem_btn.pressed.connect(on_open)
	UI._basma_hissi(gem_btn, null)
	row.add_child(gem_btn)
	var plus := UI.button("+", "yesil", UI.DOKUNMA, 40, "", UI.DOKUNMA)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(plus.get_meta("row") as Control).offset_left = 0
	(plus.get_meta("row") as Control).offset_right = 0
	plus.pressed.connect(on_open)
	row.add_child(plus)
	row.set_meta("label", l)
	return row


# Elmas mağazasını açar (main.gd open_gem_store; başka bir ekran yazar).
static func open_gem_store(from: Node) -> void:
	var m = from.get_tree().current_scene
	if m and m.has_method("open_gem_store"):
		m.open_gem_store()


static func gem_icon(px: float) -> Control:
	var g := Gem.new()
	g.custom_minimum_size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


static func styled_button(text: String, primary: bool, font := 22, h := 56.0) -> Button:
	return UI.button(text, "orange" if primary else "normal", int(h), font)


# Türkçe büyük harf (Godot'nun to_upper'ı i -> I yapar).
static func tr_upper(s: String) -> String:
	return preload("res://scripts/dil.gd").buyuk(TranslationServer.translate(s))


# ---------------------------------------------------------------------
# Ekran kurulumu
# ---------------------------------------------------------------------

func _ready() -> void:
	layer = 20
	preload("res://scripts/telemetri.gd").ekran("magaza")
	_thumbs = ThumbsScript.new()
	add_child(_thumbs)
	_look = profile.look.duplicate()
	var s := E.screen("MAĞAZA", "magaza", "bg_store", 0.6)
	_kok = s.kok
	add_child(_kok)
	(s.geri as Button).pressed.connect(_back)
	var sag: HBoxContainer = s.bar_sag
	# günlük ödül (alınabiliyorsa yeşil, nabız atar)
	_daily_btn = UI.button("+%d" % profile.DAILY_GEMS, "yesil", UI.DOKUNMA, UI.FS_ORTA, "gift", 150)
	_daily_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_daily_btn.pressed.connect(_claim_daily)
	sag.add_child(_daily_btn)
	E.pulse(_daily_btn, 1.05, 0.6)
	var gw := gem_widget(func() -> void: open_gem_store(self))
	_gem_label = gw.get_meta("label")
	sag.add_child(gw)

	var govde: Control = s.govde
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left", UI.B_M)
	mc.add_theme_constant_override("margin_right", UI.B_M)
	mc.add_theme_constant_override("margin_top", UI.B_XS)
	mc.add_theme_constant_override("margin_bottom", UI.B_M)
	govde.add_child(mc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_M)
	mc.add_child(row)
	row.add_child(_build_stage_panel())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", UI.B_S)
	row.add_child(right)
	# kategori sekmeleri (tek satır, parmakla yana kaydırılır)
	_tab_scroll = ScrollContainer.new()
	_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_tab_scroll.scroll_deadzone = 14
	_tab_scroll.custom_minimum_size.y = UI.DOKUNMA + 4
	right.add_child(_tab_scroll)
	_cat_row = HBoxContainer.new()
	_cat_row.add_theme_constant_override("separation", 4)
	_tab_scroll.add_child(_cat_row)
	# içerik: kaydırılan kart ızgarası (vitrinde üstte başlık)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(_scroll)
	right.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + m, 6)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", UI.B_S)
	pad.add_child(_list)
	_scroll.resized.connect(_layout_grid)
	right.add_child(_build_action_bar())

	if account and account.has_signal("economy_changed"):
		account.economy_changed.connect(_on_economy)
	_refresh()
	E.intro(_kok, govde)


# Sol: çelik çerçeveli 3D vitrin; altta ad kutusu, sol üstte yakın/uzak düğmesi.
func _build_stage_panel() -> Control:
	var panel := UI.panel(Vector2.ZERO, 10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = STAGE_RATIO
	var st := Control.new()
	st.clip_contents = true
	panel.add_child(st)
	var gl := E.glow(UI.AMBER, 0.22)
	gl.set_anchors_preset(Control.PRESET_FULL_RECT)
	gl.offset_top = 40
	gl.offset_bottom = 60
	st.add_child(gl)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	st.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X if int(profile.settings.get("kalite", 1)) >= 1 else Viewport.MSAA_2X
	_sahne_sv = sv
	sv.transparent_bg = true
	svc.add_child(sv)
	_build_stage(sv)
	svc.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenDrag:
			_turntable.rotation.y += (e as InputEventScreenDrag).relative.x * 0.012
		elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT):
			_turntable.rotation.y += (e as InputEventMouseMotion).relative.x * 0.012)
	# yakın / tüm boy
	_zoom_btn = UI.button("BOY", "ikincil", UI.DOKUNMA, UI.FS_KUCUK + 2, "", 132)  # İngilizce "HEIGHT" sığsın
	_zoom_btn.position = Vector2(UI.B_S, UI.B_S)
	_zoom_btn.pressed.connect(func() -> void:
		_close_up = not _close_up
		_place_camera())
	st.add_child(_zoom_btn)
	# ad kutusu
	_name_edit = LineEdit.new()
	_name_edit.text = profile.player_name
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "Adın"
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.style_edit(_name_edit, UI.FS_ORTA)
	_name_edit.add_theme_font_override("font", UI.TITLE_FONT)
	_name_edit.custom_minimum_size.y = UI.DOKUNMA
	_name_edit.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_name_edit.offset_left = UI.B_S
	_name_edit.offset_right = -UI.B_S
	_name_edit.offset_top = -UI.DOKUNMA - UI.B_S
	_name_edit.offset_bottom = -UI.B_S
	st.add_child(_name_edit)
	return panel


func _sigdir_sel() -> void:
	if is_instance_valid(_sel_name) and _sel_name.size.x > 10.0:
		UI.sigdir(_sel_name, _sel_name.size.x - 4.0)


# Alt eylem çubuğu: seçilen eşyanın adı ve nadirliği, SATIN AL (yeşil), KAYDET (ana).
func _build_action_bar() -> Control:
	var bar := E.row_box(Color(0, 0, 0, 0), Vector4(UI.B_M, UI.B_XS, UI.B_XS, UI.B_XS))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	bar.add_child(h)
	_sel_box = VBoxContainer.new()
	_sel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sel_box.add_theme_constant_override("separation", -2)
	h.add_child(_sel_box)
	_sel_name = UI.title("", UI.FS_ORTA, UI.METIN)
	_sel_name.clip_text = true
	_sel_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# uzun ad (Gardiyan üniforması, İngilizce adlar) kesilmesin: alana göre küçülür (_sigdir_sel)
	_sel_name.resized.connect(_sigdir_sel)
	_sel_box.add_child(_sel_name)
	_sel_sub = UI.label("", UI.FS_KUCUK, UI.METIN_SOLUK)
	_sel_box.add_child(_sel_sub)
	# istek listesi: eşya vitrine girince menüde rozet çıkar
	_wish_btn = UI.button("", "ikincil", UI.DOKUNMA, UI.FS_ORTA, "", UI.DOKUNMA)
	_wish_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wish_heart = Heart.new()
	_wish_heart.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wish_heart.offset_left = 14
	_wish_heart.offset_right = -14
	_wish_heart.offset_top = 12
	_wish_heart.offset_bottom = -14
	_wish_heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wish_btn.add_child(_wish_heart)
	_wish_btn.pressed.connect(_toggle_wish)
	h.add_child(_wish_btn)
	# arkadaşa hediye
	_gift_btn = UI.icon_button("gift", "ikincil", UI.DOKUNMA)
	_gift_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gift_btn.pressed.connect(_gift_open)
	h.add_child(_gift_btn)
	_buy_btn =UI.button("0", "yesil", UI.DOKUNMA, UI.FS_ORTA, "elmas", 210)
	_buy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_buy_btn.pressed.connect(_on_buy_pressed)
	h.add_child(_buy_btn)
	var save := UI.button("KAYDET", "ana", UI.DOKUNMA, UI.FS_ORTA, "", 180)
	save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save.pressed.connect(_save)
	h.add_child(save)
	return bar


func _play(n: String, vol := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p


func _process(delta: float) -> void:
	# elmas sayacı yeni değere doğru sayarak gider
	var target := float(profile.gems)
	if _gems_shown < 0.0:
		_gems_shown = target
		_gem_label.text = E.sayi(int(target))
	if absf(_gems_shown - target) > 0.5:
		_gems_shown = move_toward(_gems_shown, target, maxf(absf(target - _gems_shown) * delta * 4.0, 60.0 * delta))
		_gem_label.text = E.sayi(int(round(_gems_shown)))
	if is_instance_valid(_countdown):
		# vitrin süresi sunucudan (Türkiye saatiyle gece yarısı); sunucu yoksa telefon saati
		var left: int = account.kalan_sn("gun_kalan") if account else -1
		if left < 0:
			var now := Time.get_time_dict_from_system()
			left = 86400 - (int(now.hour) * 3600 + int(now.minute) * 60 + int(now.second))
		_countdown.text = sure_yaz(left)
		if left == 0 and not _yenile_istendi and account:
			_yenile_istendi = true
			account.send({"t": "ekonomi"})  # yeni günün vitrini
	if is_instance_valid(_countdown_w) and account:
		_countdown_w.text = sure_yaz(account.kalan_sn("hafta_kalan"))
	# hareket önizlemesi canlı: bitince kısa bir aradan sonra yeniden oynar
	if _preview_item != "" and _body and str(_body.get("emote")) == "" and not _opening:
		_emote_loop += delta
		if _emote_loop > 0.9:
			_emote_loop = 0.0
			_body.play_emote(_preview_item)
	else:
		_emote_loop = 0.0
	_daily_btn.visible = profile.daily_available()


# Kalan süre: bir günden azsa 05:12:09, fazlaysa "3G 04S" (gün, saat).
static func sure_yaz(left: int) -> String:
	if left < 0:
		return ""
	if left >= 86400:
		return TranslationServer.translate("%dG %02dS") % [left / 86400, (left / 3600) % 24]
	return "%02d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]


func _on_economy() -> void:
	# sunucudan yeni elmas / eşya: kasa gösterisi sürerken bekler, sonra yenilenir
	if not _opening:
		_refresh_selection()


func _claim_daily() -> void:
	if profile.claim_daily():
		_play("kasa/elmas", -3.0)
		UI.toast(tr("+%d elmas") % profile.DAILY_GEMS, null, 1.8, "basari")


func _build_tabs() -> void:
	for ch in _cat_row.get_children():
		ch.queue_free()
	var on_btn: Button = null
	for c in CATS:
		var b := UI.tab(str(TAB_NAMES.get(c, c)), c == _cat, CAT_ICONS.get(c, ""))
		b.pressed.connect(_select_cat.bind(c))
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		_cat_row.add_child(b)
		if c == _cat:
			on_btn = b
	if on_btn:
		_scroll_tab_into_view.call_deferred(on_btn)


# Seçili sekme görünür kalsın (gerekirse şerit ortalanır).
func _scroll_tab_into_view(b: Button) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var w := _tab_scroll.size.x
	var x0 := float(_tab_scroll.scroll_horizontal)
	if b.position.x < x0 or b.position.x + b.size.x > x0 + w:
		_tab_scroll.scroll_horizontal = int(maxf(0.0, b.position.x - (w - b.size.x) / 2.0))


func _select_cat(c: String) -> void:
	if c == _cat:
		return
	_onizleme_geri_al()
	_cat = c
	_pending = ["", ""]
	_deal_price = -1
	_refresh()
	_scroll.scroll_vertical = 0
	# içerik hafifçe kayarak gelir
	_list.modulate.a = 0.0
	var tw := _list.create_tween()
	tw.tween_property(_list, "modulate:a", 1.0, 0.18)


func _build_stage(sv: SubViewport) -> void:
	var root := Node3D.new()
	sv.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(200), 0)
	key.light_energy = 1.3
	key.light_color = Color("#ffe2c0")
	root.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.2, 2.0, 1.5)
	rim.light_color = Color("#ffb34a")
	rim.light_energy = 1.4
	rim.omni_range = 5.0
	root.add_child(rim)
	# kaide: koyu metal disk ve amber halka
	var disk := CylinderMesh.new()
	disk.top_radius = 0.5
	disk.bottom_radius = 0.54
	disk.height = 0.06
	var fl := MeshInstance3D.new()
	fl.mesh = disk
	fl.position.y = -0.03
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#22262a")
	fm.metallic = 0.5
	fm.roughness = 0.45
	fl.material_override = fm
	root.add_child(fl)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.495
	ring.outer_radius = 0.515
	var rg := MeshInstance3D.new()
	rg.mesh = ring
	rg.position.y = 0.005
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(UI.AMBER, 0.85)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rg.material_override = rm
	root.add_child(rg)
	_turntable = Node3D.new()
	_turntable.rotation.y = 0.35
	root.add_child(_turntable)
	_body = BodyScript.new()
	_body.look = _look.duplicate()
	_turntable.add_child(_body)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_place_camera()


# Dövme elde ise kamerayı ele, yüz/boyunda ise yüze çevirir (karakter de o yana döner).
func _focus_tattoo(id: String) -> void:
	var place := str(BodyScript.TATTOO_PLACE.get(id, ["yuz"])[0])
	if place == "el":
		_turntable.rotation.y = 0.9
		_cam.position = Vector3(-0.35, 1.25, -1.6)
		_cam.look_at_from_position(_cam.position, Vector3(-0.15, 0.95, 0))
	elif place == "kafa":
		_turntable.rotation.y = 1.15
		_place_camera()
	else:
		_turntable.rotation.y = 0.2
		_place_camera()


func _place_camera() -> void:
	if _close_up:
		_cam.position = Vector3(0, 1.56, -1.75)
		_cam.look_at_from_position(_cam.position, Vector3(0, 1.48, 0))
	else:
		_cam.position = Vector3(0, 1.08, -3.5)
		_cam.look_at_from_position(_cam.position, Vector3(0, 0.9, 0))
	if _zoom_btn:
		UI.set_button_text(_zoom_btn, "BOY" if _close_up else "YÜZ")


# ---------------------------------------------------------------------
# İçerik
# ---------------------------------------------------------------------

# anim: kartlar sırayla belirsin mi (seçim değişince hayır)
func _refresh(anim := true) -> void:
	_anim = anim
	_build_tabs()
	for ch in _list.get_children():
		ch.queue_free()
	_grid = null
	_chest_btns.clear()
	_countdown = null
	_countdown_w = null
	if _cat == "vitrin":
		_fill_vitrin()
	elif _cat == "setler":
		_fill_setler()
	elif _cat == "sandik":
		_fill_chests()
	elif _cat in COLOR_CATS:
		_fill_colors()
	else:
		_fill_items()
	_layout_grid()
	_update_action()


func _new_grid(min_w: float) -> GridContainer:
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", UI.B_S)
	_grid.add_theme_constant_override("v_separation", UI.B_S)
	_grid_min_w = min_w
	_list.add_child(_grid)
	return _grid


# Sütun sayısı genişliğe göre (geniş telefonda daha çok kart sığar).
func _layout_grid() -> void:
	if _grid == null or not is_instance_valid(_grid):
		return
	var w := _scroll.size.x - 12.0
	if w <= 0.0:
		return
	var cols := clampi(int((w + UI.B_S) / (_grid_min_w + UI.B_S)), 2, 8)
	_grid.columns = mini(cols, maxi(2, _grid.get_child_count()))


func _fill_colors() -> void:
	var colors: Array = {"ten": Catalog.SKIN, "sac_renk": Catalog.HAIR_COLORS, "goz": Catalog.EYE_COLORS}[_cat]
	var hair := _cat == "sac_renk"
	_new_grid(150.0 if hair else 110.0)
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 170 if hair else 96)
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sel := int(_look[_cat]) == i
		var st := StyleBoxFlat.new()
		# saç rengi: düz renk yerine o renkteki saçın gerçek çekimi (ışıkta saç, düz renkten farklı görünür);
		# altta katalog rengi şeridi. Resimler pakette (assets/kucuk/<set>/sac_<stil>_<renk>.webp)
		st.bg_color = Color("#1b1e25") if hair else Color(colors[i])
		st.set_corner_radius_all(UI.R_ORTA)
		st.border_color = UI.AMBER if sel else Color(0, 0, 0, 0.5)
		st.set_border_width_all(5 if sel else 2)
		st.shadow_color = Color(UI.AMBER, 0.55) if sel else Color(0, 0, 0, 0.4)
		st.shadow_size = 14 if sel else 4
		for k in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(k, st)
		if hair:
			var t := TextureRect.new()
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			t.set_anchors_preset(Control.PRESET_FULL_RECT)
			t.offset_left = 6
			t.offset_top = 6
			t.offset_right = -6
			t.offset_bottom = -22
			b.add_child(t)
			_thumbs.request(_look, "sac_renk", str(i), t)
			var chip := Panel.new()
			var cs := StyleBoxFlat.new()
			cs.bg_color = Color(colors[i])
			cs.set_corner_radius_all(6)
			chip.add_theme_stylebox_override("panel", cs)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			chip.offset_left = 12
			chip.offset_right = -12
			chip.offset_top = -18
			chip.offset_bottom = -8
			b.add_child(chip)
		b.pressed.connect(func() -> void:
			UI.tik()
			_look[_cat] = i
			_apply())
		_grid.add_child(b)
	_close_up = true
	_place_camera()


func _fill_items() -> void:
	_new_grid(168.0)
	for it in Catalog.ITEMS[_cat]:
		var id: String = it[0]
		var selected: bool = (_preview_item == id) if _cat == "hareket" else (str(_look[_cat]) == id)
		_grid.add_child(_shop_card(_cat, id, str(it[1]), int(it[2]), selected, _pick.bind(id)))
	if _anim:
		E.stagger(_grid, 0.02)
	_close_up = _cat in ["sac", "kas", "sakal", "aksesuar", "sapka", "dovme"]
	_place_camera()
	if _cat == "dovme":
		_focus_tattoo(str(_look.dovme))


# Mağaza kartı: kilitliyse köşede kilit + fiyat, sahipse "SENDE", üstündeyse "GİYİLİ".
func _shop_card(cat: String, id: String, title: String, price: int, selected: bool, on_press: Callable, h := 224.0) -> Button:
	var tier: Array = Catalog.rarity(Catalog.price(cat, id) if id != "" else price)
	# saç ve sakal kartları önizlemedeki saç rengiyle (renk sekmesinde seçilen renk kartlara da yansısın)
	var b := item_card(cat, id, title, UI.rarity_key(str(tier[1])), _thumbs, _look if cat in ThumbsScript.RENKLI else profile.look, h)
	var foot: HBoxContainer = b.get_meta("foot")
	var owned: bool = profile.owns(cat, id)
	var on: bool = cat != "hareket" and str(_look.get(cat, "")) == id
	if not owned:
		card_lock(b)
		if _wished(cat, id):
			card_heart(b)
		# bugün vitrindeyse indirimli fiyat (üstü çizili eskisiyle)
		var now := _price_now(cat, id) if price > 0 else price
		if now < price:
			foot.add_child(_old_price(price))
		price_row(foot, now, profile.gems >= now)
	elif on:
		foot.add_child(E.pill("GİYİLİ", UI.AMBER, UI.FS_KUCUK))
	elif price > 0:
		foot.add_child(E.pill("SENDE", UI.YESIL, UI.FS_KUCUK))
	set_card_selected(b, selected)
	b.pressed.connect(on_press)
	return b


# Günün fırsatları sunucudan: [kategori, kimlik, ad, eski fiyat, indirim %, yeni fiyat]
func _server_deals() -> Array:
	var out := []
	var src: Array = account.eco.get("firsatlar", []) if account else []
	for f in src:
		out.append([str(f[0]), str(f[1]), Catalog.item_name(str(f[0]), str(f[1])), int(f[2]), int(f[3]), int(f[4])])
	if out.is_empty():
		return Catalog.daily_deals(Time.get_date_string_from_system())
	return out


# Bir eşyanın şu anki fiyatı: bugün vitrindeyse indirimli (sunucu da böyle hesaplar).
func _price_now(cat: String, id: String) -> int:
	for d in _server_deals():
		if d[0] == cat and d[1] == id:
			return int(d[5])
	return Catalog.price(cat, id)


func _sets() -> Array:
	return account.eco.get("setler", []) if account else []


func _set_by_key(k: String) -> Dictionary:
	for s in _sets():
		if str(s.k) == k:
			return s
	return {}


func _haftanin_seti() -> Dictionary:
	if not account:
		return {}
	return _set_by_key(str((account.eco.get("vitrin", {}) as Dictionary).get("haftanin_seti", "")))


static func _rarity_index(price: int) -> int:
	for i in RARITY.size():
		if price <= int(RARITY[i][0]):
			return i
	return 0


# Setin nadirliği: en nadir parçası
static func set_rarity(s: Dictionary) -> String:
	var best := 0
	for p in s.get("parcalar", []):
		best = maxi(best, _rarity_index(int(p[2])))
	return NADIR_KEYS[best]


# İstek listesi (sunucuda): "kategori:kimlik" listesi
func _wishlist() -> Array:
	return account.eco.get("istek", []) if account else []


func _wished(cat: String, id: String) -> bool:
	return _wishlist().has(cat + ":" + id)


# Kartın sağ üstüne (kilidin soluna) küçük dolu kalp: istek listesinde.
static func card_heart(b: Control) -> void:
	var h := Heart.new()
	h.on = true
	h.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	h.offset_left = -84
	h.offset_right = -54
	h.offset_top = 18
	h.offset_bottom = 48
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)


# Üstü çizili eski fiyat
static func _old_price(n: int, size := UI.FS_KUCUK) -> Label:
	var old := UI.title(E.sayi(n), size, UI.METIN_SOLUK)
	old.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var strike := ColorRect.new()
	strike.color = UI.KIRMIZI
	strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	old.add_child(strike)
	old.resized.connect(func() -> void:
		strike.position = Vector2(-2, old.size.y / 2.0)
		strike.size = Vector2(old.size.x + 4, 3))
	return old


# Sol üst köşede eğik indirim şeridi (-%30)
static func _ribbon(parent: Control, off: int, size := UI.FS_METIN) -> void:
	var rib := PanelContainer.new()
	var rs := UI.flat(UI.KIRMIZI, Color("#ffb3a8"), UI.R_KUCUK)
	rs.content_margin_left = 10
	rs.content_margin_right = 10
	rs.content_margin_top = 2
	rs.content_margin_bottom = 2
	rs.shadow_size = 4
	rib.add_theme_stylebox_override("panel", rs)
	rib.add_child(UI.title(TranslationServer.translate("-%%%d") % off, size, Color.WHITE, true))
	rib.position = Vector2(14, 16)
	rib.rotation = -0.1
	rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rib)


# Vitrin: solda haftanın seti (büyük kart, haftalık geri sayım), sağda günün 6 fırsatı (gece yarısına geri sayım).
# Herkes aynı vitrini görür (sunucu tarihten üretir).
func _fill_vitrin() -> void:
	if account and int(account.eco.get("istek_yeni", 0)) > 0:
		account.send({"t": "vitrin_bakti"})  # istek listesi rozeti bugün için söner
	var h := maxf(380.0, _scroll.size.y - 14.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_M)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(row)
	var hs := _haftanin_seti()
	if not hs.is_empty():
		var big := _set_card(hs, true, h)
		big.size_flags_stretch_ratio = 0.8
		row.add_child(big)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.25
	right.add_theme_constant_override("separation", UI.B_S)
	row.add_child(right)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.B_S)
	head.custom_minimum_size.y = 40
	var ic := UI.icon("deal", 36)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var t := UI.title("GÜNÜN FIRSATLARI", UI.FS_ORTA, UI.METIN)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(t)
	var cd := E.pill("00:00:00", UI.AMBER, UI.FS_ORTA - 4)
	cd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_countdown = cd.get_meta("label")
	head.add_child(cd)
	right.add_child(head)
	var g := GridContainer.new()
	g.columns = 3
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", UI.B_S)
	g.add_theme_constant_override("v_separation", UI.B_S)
	right.add_child(g)
	var ch := floorf((h - 40.0 - UI.B_S * 2) / 2.0)
	for d in _server_deals():
		g.add_child(_deal_card(d, ch))
	if _anim:
		E.stagger(g, 0.04)
		E.stagger(row, 0.06)
	_close_up = _pending[0] != "set"
	_place_camera()


# Günün fırsatı kartı: indirim şeridi, üstü çizili eski fiyat, yeni fiyat; istek listesindeyse kalp.
func _deal_card(d: Array, h: float) -> Button:
	var cat: String = d[0]
	var id: String = d[1]
	var owned: bool = profile.owns(cat, id)
	var card := item_card(cat, id, str(d[2]), UI.rarity_key(str(Catalog.rarity(Catalog.price(cat, id))[1])), _thumbs, profile.look, h)
	var foot: HBoxContainer = card.get_meta("foot")
	if owned:
		foot.add_child(E.pill("SENDE", UI.YESIL, UI.FS_KUCUK))
	else:
		card_lock(card)
		if _wished(cat, id):
			card_heart(card)
		foot.add_child(_old_price(int(d[3])))
		var sp := Control.new()
		sp.custom_minimum_size.x = 2
		foot.add_child(sp)
		price_row(foot, int(d[5]), profile.gems >= int(d[5]), 20)
	_ribbon(card, int(d[4]))
	set_card_selected(card, _pending == [cat, id])
	card.pressed.connect(_pick_deal.bind(d))
	return card


func _pick_deal(d: Array) -> void:
	var cat: String = d[0]
	var id: String = d[1]
	_play("kumas", -4.0)
	var geri := _onizleme_geri_al(false)
	if cat == "hareket":
		_preview_item = id
		if geri:
			_body.set_look(_look)
		_body.play_emote(id)
	else:
		_preview_item = ""
		_look[cat] = id
		_body.set_look(_look)
	_pending = [cat, id]
	_deal_price = int(d[5])
	_refresh_selection()


# Setler sekmesi: bütün setler iki sütun (haftanın seti başta, hepsi sende olanlar sonda).
func _fill_setler() -> void:
	var sets := _sets().duplicate()
	if sets.is_empty():
		var l := UI.label("Setler sunucuya bağlanınca görünür", UI.FS_METIN, UI.METIN_SOLUK, true)
		l.custom_minimum_size.y = 200
		_list.add_child(l)
		return
	sets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := (0 if bool(a.one_cikan) else 1) * 10 + (1 if bool(a.hepsi_sende) else 0)
		var kb := (0 if bool(b.one_cikan) else 1) * 10 + (1 if bool(b.hepsi_sende) else 0)
		if ka != kb:
			return ka < kb
		return int(a.fiyat) < int(b.fiyat))
	_new_grid(320.0)
	for s in sets:
		_grid.add_child(_set_card(s, false, 246.0))
	if _anim:
		E.stagger(_grid, 0.03)
	_close_up = false
	_place_camera()


# Set kartı: nadirlik çerçevesi, ad, parçaların küçük resimleri (sahip olunan işaretli), indirim şeridi,
# üstü çizili toplam ve set fiyatı. big: vitrindeki "haftanın seti" (2x2 parça + haftalık geri sayım).
func _set_card(s: Dictionary, big: bool, h: float) -> Button:
	var k := str(s.k)
	var rk := set_rarity(s)
	var rc := UI.rarity_color(rk)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var sel := Panel.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(UI.AMBER, 0.22)
	ss.border_color = Color(UI.AMBER, 0.95)
	ss.set_border_width_all(3)
	ss.set_corner_radius_all(UI.R_ORTA)
	ss.shadow_color = Color(UI.AMBER, 0.5)
	ss.shadow_size = 16
	sel.add_theme_stylebox_override("panel", ss)
	sel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sel.offset_left = -3
	sel.offset_top = -3
	sel.offset_right = 3
	sel.offset_bottom = 3
	sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel.visible = _pending == ["set", k]
	b.add_child(sel)
	b.set_meta("sel", sel)
	var fr := UI.card_frame(rk, Vector2(0, h))
	fr.custom_minimum_size = Vector2.ZERO
	fr.set_anchors_preset(Control.PRESET_FULL_RECT)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(fr)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.add_child(v)
	if big:
		# üstte: HAFTANIN SETİ + haftalık geri sayım
		var top := HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_END
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(top)
		var cd := E.pill("", UI.AMBER, UI.FS_KUCUK)
		_countdown_w = cd.get_meta("label")
		top.add_child(cd)
		var hb := UI.title("HAFTANIN SETİ", UI.FS_KUCUK + 2, UI.AMBER, true)
		v.add_child(hb)
	else:
		var sp0 := Control.new()
		sp0.custom_minimum_size.y = 8
		sp0.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sp0)
	var nm := UI.title(tr(str(s.ad)), UI.FS_ORTA + (0 if big else -2), rc.lightened(0.25), true)
	if big:
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.max_lines_visible = 2
	else:
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nm)
	var parts := GridContainer.new()
	parts.columns = 2 if big else 4
	parts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts.add_theme_constant_override("h_separation", 6)
	parts.add_theme_constant_override("v_separation", 6)
	parts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(parts)
	for p in s.get("parcalar", []):
		parts.add_child(_part_thumb(str(p[0]), str(p[1]), bool(p[3]), int(p[2])))
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 6)
	foot.custom_minimum_size.y = 34
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	if bool(s.hepsi_sende):
		foot.add_child(E.pill("SENDE", UI.YESIL, UI.FS_KUCUK))
	else:
		foot.add_child(_old_price(int(s.toplam), UI.FS_KUCUK + 2))
		price_row(foot, int(s.fiyat), profile.gems >= int(s.fiyat), 24 if big else 22)
	var pad := Control.new()
	pad.custom_minimum_size.y = 4
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pad)
	if not bool(s.hepsi_sende):
		_ribbon(b, int(s.indirim), UI.FS_METIN + (2 if big else 0))
	b.pressed.connect(_pick_set.bind(s))
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.97, 0.06))
	b.button_up.connect(func() -> void:
		b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(b, "scale", Vector2.ONE, 0.16))
	return b


# Setteki parçanın küçük resmi: nadirlik kenarlı koyu kutu; sahip olunan parçada yeşil onay, harekette küçük ikon.
func _part_thumb(cat: String, id: String, owned: bool, price: int) -> Control:
	var p := Panel.new()
	var rc := UI.rarity_color(NADIR_KEYS[_rarity_index(price)])
	p.add_theme_stylebox_override("panel", UI.flat(Color(0, 0, 0, 0.38), Color(rc, 0.7), UI.R_KUCUK))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(56, 56)
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gl := E.glow(rc, 0.25)
	gl.set_anchors_preset(Control.PRESET_FULL_RECT)
	gl.offset_top = 16
	p.add_child(gl)
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.offset_left = 3
	t.offset_top = 3
	t.offset_right = -3
	t.offset_bottom = -3
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cat == "dovme":
		var sk := Color(Catalog.SKIN[int(profile.look.get("ten", 1))])
		p.add_theme_stylebox_override("panel", UI.flat(sk.darkened(0.2), Color(rc, 0.7), UI.R_KUCUK))
		t.texture = BodyScript.ink_texture(id)
	else:
		t.material = _fade_material()
		_thumbs.request(profile.look, cat, id, t)
	p.add_child(t)
	if cat == "hareket":
		var em := UI.icon(str(CAT_ICONS.hareket), 24)
		em.position = Vector2(4, 4)
		p.add_child(em)
	if owned:
		var ok := UI.icon("onay", 26)
		ok.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		ok.offset_left = -30
		ok.offset_right = -4
		ok.offset_top = 4
		ok.offset_bottom = 30
		p.add_child(ok)
	return p


# Set seçilince bütün parçaları karakterde denenir, hareketi canlı oynar; tüm boy kamera.
func _pick_set(s: Dictionary) -> void:
	_play("kumas", -4.0)
	_onizleme_geri_al(false)
	var emote := ""
	for p in s.get("parcalar", []):
		if str(p[0]) == "hareket":
			emote = str(p[1])
		else:
			_look[str(p[0])] = str(p[1])
	_body.set_look(_look)
	_preview_item = emote
	if emote != "":
		_body.play_emote(emote)
	_pending = ["set", str(s.k)]
	_deal_price = -1
	_refresh_selection()


# Kasa sekmesi: üstte OLASILIKLAR düğmesi; kasalar yan yana (görsel, olasılık çubuğu, şans güvencesi sayacı,
# AÇ düğmesi). Seviye yolundan gelen ücretsiz kasa hakkı varsa düğme ÜCRETSİZ olur. Hediye kasa hakkı varsa
# üçüncü kasa görünür.
func _fill_chests() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UI.B_S)
	_list.add_child(head)
	var ic := UI.icon("kasa", 36)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var t := UI.title("KASALAR", UI.FS_ORTA, UI.METIN)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	# Başlangıç Paketi'nden gelen hediye kasa: başlıkta ayrı düğme (kasalar iki sütunda kalsın)
	var gift_n := _gift_chests()
	if gift_n > 0:
		var gb := UI.button("HEDİYE KASA", "yesil", UI.DOKUNMA, UI.FS_KUCUK + 2, "gift", 250)
		var gx := UI.title(tr("×%d") % gift_n, UI.FS_METIN, Color.WHITE)
		gx.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		(gb.get_meta("row") as HBoxContainer).add_child(gx)
		gb.set_meta("ch", HEDIYE_KASA)
		gb.pressed.connect(_open_chest.bind(HEDIYE_KASA))
		E.pulse(gb, 1.04, 0.6)
		head.add_child(gb)
		_chest_btns.append(gb)
	var odds_btn := UI.button("OLASILIKLAR", "ikincil", UI.DOKUNMA, UI.FS_KUCUK + 2, "", 220)
	odds_btn.pressed.connect(_odds_modal)
	head.add_child(odds_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_M)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(row)
	var h := maxf(380.0, _scroll.size.y - 14.0 - UI.DOKUNMA - UI.B_S)
	for c in CHESTS:
		row.add_child(_chest_card(c, h))
	if _anim:
		E.stagger(row, 0.08)
	_close_up = false
	_place_camera()


# Gösterilen kasalar: tahta, altın (+ hakkı varsa hediye kasa)
func _chest_list() -> Array:
	var out := CHESTS.duplicate()
	if _gift_chests() > 0:
		out.append(HEDIYE_KASA)
	return out


static func chest_kind(ch: Array) -> String:
	return str(ch[4]) if ch.size() > 4 else ("altin" if ch[2] else "tahta")


func _gift_chests() -> int:
	return int(account.eco.get("hediye_kasa", 0)) if account else 0


# Seviye yolundan gelen ücretsiz kasa hakkı
func _free_chests(kind: String) -> int:
	if kind == "nadir":
		return _gift_chests()
	return int((account.eco.get("kasa_hak", {}) as Dictionary).get(kind, 0)) if account else 0


# Şans güvencesi: {n, min, sayac, kalan} (sunucudan)
func _pity(kind: String) -> Dictionary:
	return (account.eco.get("pity", {}) as Dictionary).get(kind, {}) if account else {}


func _chest_card(ch: Array, h: float) -> Control:
	var gold: bool = ch[2]
	var kind := chest_kind(ch)
	var col: Color = UI.NADIRLIK.efsane if gold else UI.METIN
	if kind == "nadir":
		col = UI.NADIRLIK.epik.lightened(0.2)
	var card := UI.card_frame("epik" if kind == "nadir" else ("efsane" if gold else "siradan"), Vector2(0, h))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_XS)
	card.add_child(v)
	var nm := UI.title(tr_upper(str(ch[0])), UI.FS_BUYUK - 6, col, true)
	nm.clip_text = true
	v.add_child(nm)
	# kasa görseli: arkada ışık, hafifçe süzülür
	var art := Control.new()
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	var gl := E.glow(UI.AMBER if gold else Color("#c9d27a"), 0.45 if gold else 0.25)
	gl.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.add_child(gl)
	if gold:
		var rays := Fx.Rays.new()
		rays.color = Color("#d9a0ff") if kind == "nadir" else Color("#ffcf6a")
		rays.set_anchors_preset(Control.PRESET_FULL_RECT)
		rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rays.modulate.a = 0.55
		art.add_child(rays)
	var tex := UI.texture(CHEST_ART[1 if gold else 0][0], 360)
	var pic: Control
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic = tr
	else:
		var drawn := Fx.Chest.new()
		drawn.gold = gold
		pic = drawn
	if kind == "nadir":
		pic.modulate = Color(0.95, 0.8, 1.15)
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.offset_left = 18
	pic.offset_right = -18
	pic.offset_top = 6
	pic.offset_bottom = -6
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(pic)
	pic.resized.connect(func() -> void: pic.pivot_offset = pic.size * Vector2(0.5, 0.9))
	var tw := pic.create_tween().set_loops()
	tw.tween_method(func(k: float) -> void:
		pic.offset_top = 6.0 - 8.0 * k
		pic.offset_bottom = -6.0 - 8.0 * k
		pic.rotation = 0.03 * (k - 0.5), 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(k: float) -> void:
		pic.offset_top = 6.0 - 8.0 * k
		pic.offset_bottom = -6.0 - 8.0 * k
		pic.rotation = 0.03 * (k - 0.5), 1.0, 0.0, 1.1).set_trans(Tween.TRANS_SINE)
	# olasılıklar: renkli çubuk + yüzdeler (sunucudan; yoksa sabit)
	var w := _chest_weights(ch)
	var bar := OddsBar.new()
	bar.weights = w
	bar.colors = [UI.NADIRLIK.siradan, UI.NADIRLIK.nadir, UI.NADIRLIK.epik, UI.NADIRLIK.efsane]
	bar.custom_minimum_size = Vector2(0, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	var odds := HBoxContainer.new()
	odds.alignment = BoxContainer.ALIGNMENT_CENTER
	odds.add_theme_constant_override("separation", UI.B_S)
	odds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 4:
		if float(w[i]) <= 0.0:
			continue
		var o := HBoxContainer.new()
		o.add_theme_constant_override("separation", 4)
		var dot := Panel.new()
		var ds := StyleBoxFlat.new()
		ds.bg_color = UI.NADIRLIK[NADIR_KEYS[i]]
		ds.set_corner_radius_all(6)
		dot.add_theme_stylebox_override("panel", ds)
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		o.add_child(dot)
		o.add_child(UI.title(yuzde(float(w[i])), UI.FS_KUCUK + 2, Color(UI.NADIRLIK[NADIR_KEYS[i]]).lightened(0.25)))
		odds.add_child(o)
	v.add_child(odds)
	# şans güvencesi: "N kasa içinde EPİK" + dolan çubuk
	var p := _pity(kind)
	if not p.is_empty():
		var nd := int(p.get("n", 10))
		var kalan := int(p.get("kalan", nd))
		var hedef: String = str(RARITY[int(p.get("min", 2))][1])
		var txt := tr("Sıradaki kasada %s garanti!") % tr(hedef) if kalan <= 1 else tr("%d kasa içinde %s garanti") % [kalan, tr(hedef)]
		var pb := UI.progress(float(nd - kalan) / float(maxi(1, nd - 1)), 0, 30, txt)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var yazi: Label = pb._yazi
		pb.resized.connect(func() -> void: UI.sigdir(yazi, pb.size.x - 20.0))
		v.add_child(pb)
	# AÇ düğmesi: ücretsiz hak varsa "ÜCRETSİZ ×n", yoksa "AÇ" + elmas + fiyat
	var free := _free_chests(kind)
	var b := UI.button("ÜCRETSİZ" if free > 0 and kind != "nadir" else "AÇ", "yesil", UI.BTN_H, UI.FS_BUYUK - 4, "", 0)
	var br: HBoxContainer = b.get_meta("row")
	if free > 0:
		var xl := UI.title(tr("×%d") % free, UI.FS_ORTA + 2, Color.WHITE)
		xl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		br.add_child(xl)
		E.pulse(b, 1.03, 0.7)
	else:
		var gi := UI.icon("elmas", 34)
		gi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		br.add_child(gi)
		var pl := UI.title(E.sayi(int(ch[1])), UI.FS_ORTA + 2, Color.WHITE)
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		br.add_child(pl)
	b.set_meta("ch", ch)
	b.pressed.connect(_open_chest.bind(ch))
	v.add_child(b)
	var foot_pad := Control.new()
	foot_pad.custom_minimum_size.y = 10
	v.add_child(foot_pad)
	_chest_btns.append(b)
	return card


# Kasanın nadirlik yüzdeleri: sunucunun bildirdiği (mağaza kuralı: şeffaf), yoksa sabit tablo.
func _chest_weights(ch: Array) -> Array:
	var ol: Dictionary = account.eco.get("olasilik", {}) if account else {}
	var d: Dictionary = ol.get(chest_kind(ch), {})
	var y: Array = d.get("yuzde", [])
	return y if y.size() == 4 else ch[3]


# "%55" / "%0,5" biçimli yüzde
static func yuzde(p: float) -> String:
	var s := str(int(round(p))) if is_equal_approx(p, round(p)) else String.num(p, 1)
	if preload("res://scripts/dil.gd").tr_mi():
		s = s.replace(".", ",")
	return TranslationServer.translate("%%%s") % s


# Olasılıklar penceresi: her kasada nadirlik yüzdesi, o nadirlikteki eşya sayısı ve şans güvencesi kuralı.
func _odds_modal() -> void:
	_play("kumas", -6.0)
	var ol: Dictionary = account.eco.get("olasilik", {}) if account else {}
	var m := UI.modal("OLASILIKLAR", 760)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UI.B_S)
	m.body.add_child(list)
	for ch in _chest_list():
		var kind := chest_kind(ch)
		var d: Dictionary = ol.get(kind, {})
		var w := _chest_weights(ch)
		var havuz: Array = d.get("havuz", [])
		var box := E.row_box(Color(0, 0, 0, 0), Vector4(UI.B_M, UI.B_XS, UI.B_M, UI.B_XS))
		list.add_child(box)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		box.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", UI.B_S)
		v.add_child(top)
		var tl := UI.title(tr_upper(str(ch[0])), UI.FS_METIN, UI.NADIRLIK.efsane if ch[2] else UI.METIN)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(tl)
		var g: Dictionary = d.get("guvence", {}) if d.get("guvence") is Dictionary else {}
		if not g.is_empty():
			top.add_child(E.pill(tr("Her %d kasada en az %s") % [int(g.n), tr(str(RARITY[int(g.min)][1]))], UI.AMBER, UI.FS_KUCUK))
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", UI.B_S)
		v.add_child(cols)
		for i in 4:
			var c := HBoxContainer.new()
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.add_theme_constant_override("separation", 6)
			cols.add_child(c)
			var dot := Panel.new()
			var ds := StyleBoxFlat.new()
			ds.bg_color = UI.NADIRLIK[NADIR_KEYS[i]] if float(w[i]) > 0.0 else Color(UI.CIZGI, 0.6)
			ds.set_corner_radius_all(7)
			dot.add_theme_stylebox_override("panel", ds)
			dot.custom_minimum_size = Vector2(14, 14)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			c.add_child(dot)
			var cv := VBoxContainer.new()
			cv.add_theme_constant_override("separation", -2)
			c.add_child(cv)
			var renk: Color = Color(UI.NADIRLIK[NADIR_KEYS[i]]).lightened(0.25) if float(w[i]) > 0.0 else UI.METIN_SOLUK
			cv.add_child(UI.title(yuzde(float(w[i])), UI.FS_ORTA, renk))
			var alt := tr(str(RARITY[i][1]))
			if havuz.size() == 4:
				alt += "  " + tr("%d eşya") % int(havuz[i])
			cv.add_child(UI.label(alt, UI.FS_KUCUK, UI.METIN_SOLUK))
	var note := UI.label("Sende olmayan eşyalar önce çıkar. Hepsi sendeyse elmas iadesi.", UI.FS_KUCUK, UI.METIN_SOLUK, true)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.body.add_child(note)
	add_child(m)


# ---------------------------------------------------------------------
# Seçim, satın alma, kaydetme
# ---------------------------------------------------------------------

# Alt çubuk: önizlenen eşya ya da set; kilitliyse SATIN AL (elması yetmiyorsa ELMAS AL), istek listesi kalbi
# (sahip olunmayan eşyada) ve hediye düğmesi (satılan her eşyada).
func _update_action() -> void:
	var cat: String = _pending[0]
	var id: String = _pending[1]
	_buy_btn.visible = false
	_wish_btn.visible = false
	_gift_btn.visible = false
	_sel_box.modulate.a = 1.0 if cat != "" else 0.0
	if cat == "":
		return
	if cat == "set":
		var s := _set_by_key(id)
		if s.is_empty():
			_sel_box.modulate.a = 0.0
			return
		_sel_name.text = tr(str(s.ad))
		_sigdir_sel()
		_sel_name.add_theme_color_override("font_color", UI.rarity_color(set_rarity(s)).lightened(0.2))
		_sel_sub.text = tr("SET  ·  %d parça") % (s.get("parcalar", []) as Array).size()
		if bool(s.hepsi_sende):
			return
		_buy_btn.visible = true
		_buy_btn.disabled = false
		UI.set_button_text(_buy_btn, E.sayi(int(s.fiyat)) if profile.gems >= int(s.fiyat) else "ELMAS AL")
		return
	var full := Catalog.price(cat, id)
	var price := _price_now(cat, id)
	var tier: Array = Catalog.rarity(full)
	var rk := UI.rarity_key(str(tier[1]))
	_sel_name.text = Catalog.item_name(cat, id)
	_sigdir_sel()
	_sel_name.add_theme_color_override("font_color", UI.rarity_color(rk).lightened(0.2))
	var sub := tr(str(Catalog.CATEGORY_NAMES.get(cat, cat)))
	if full > 0:
		sub = tr(str(tier[1])) + "  ·  " + sub
		_gift_btn.visible = true
	_sel_sub.text = sub
	if profile.owns(cat, id):
		return
	_wish_btn.visible = true
	(_wish_heart as Heart).on = _wished(cat, id)
	_wish_heart.queue_redraw()
	_buy_btn.visible = true
	_buy_btn.disabled = false
	if profile.gems >= price:
		UI.set_button_text(_buy_btn, E.sayi(price))
	else:
		UI.set_button_text(_buy_btn, "ELMAS AL")


func _on_buy_pressed() -> void:
	var cat: String = _pending[0]
	var id: String = _pending[1]
	var price := int(_set_by_key(id).get("fiyat", 0)) if cat == "set" else _price_now(cat, id)
	if profile.gems < price:
		_play("hata", -6.0)
		open_gem_store(self)
		return
	if cat == "set":
		_buy_set(_set_by_key(id))
	else:
		_buy()


# Sunucuya mağaza işlemi yollar ve cevabı bekler: [başarılı mı, cevap] (hata ise cevap.m).
static func islem_bekle(host: Node, account: Node, d: Dictionary, cevap: String) -> Array:
	if not account or not account.connected:
		return [false, {"m": "Sunucuya bağlanılamadı"}]
	var st := {"r": []}
	var on_res := func(good: bool, dd: Dictionary) -> void: st.r = [good, dd]
	account.islem_sonuc.connect(on_res)
	account.islem(d, cevap)
	var t0 := Time.get_ticks_msec()
	while (st.r as Array).is_empty() and Time.get_ticks_msec() - t0 < 10000 and is_instance_valid(host):
		await host.get_tree().process_frame
	account.islem_sonuc.disconnect(on_res)
	if (st.r as Array).is_empty():
		return [false, {"m": "Sunucu yanıt vermedi"}]
	return st.r


# İstek listesi: kalbe dokununca eklenir / çıkarılır (sunucuda saklanır, vitrine girince menüde rozet).
func _toggle_wish() -> void:
	var cat: String = _pending[0]
	var id: String = _pending[1]
	if cat == "" or cat == "set" or not account:
		return
	var on := not _wished(cat, id)
	if not account.connected:
		UI.toast("Sunucuya bağlanılamadı", null, 2.0, "hata")
		return
	# iyimser: kalp hemen dolar, sunucunun özeti gelince kesinleşir
	var l: Array = _wishlist().duplicate()
	if on:
		l.append(cat + ":" + id)
	else:
		l.erase(cat + ":" + id)
	account.eco["istek"] = l
	account.send({"t": "istek_listesi", "kat": cat, "id": id, "ekle": on})
	_play("kumas", -6.0, 1.3 if on else 0.9)
	var hh := _wish_heart as Heart
	hh.on = on
	hh.queue_redraw()
	hh.pivot_offset = hh.size / 2.0
	var tw := hh.create_tween()
	tw.tween_property(hh, "scale", Vector2.ONE * 1.35, 0.08)
	tw.tween_property(hh, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	UI.toast("İstek listesine eklendi. Vitrine girince haber vereceğiz." if on else "İstek listesinden çıkarıldı", null, 2.0, "bilgi")
	_refresh_selection()


# Set satın alma onayı: parçalar (sende olanlar işaretli, fiyattan düşülmüş), üstü çizili toplam ve set fiyatı.
func _buy_set(s: Dictionary) -> void:
	if s.is_empty() or bool(s.hepsi_sende):
		return
	var rc := UI.rarity_color(set_rarity(s))
	var m := UI.modal("SET SATIN AL", 720)
	var nm := UI.title(tr(str(s.ad)), UI.FS_BUYUK, rc.lightened(0.25), true)
	m.body.add_child(nm)
	var parts := HBoxContainer.new()
	parts.alignment = BoxContainer.ALIGNMENT_CENTER
	parts.add_theme_constant_override("separation", UI.B_S)
	m.body.add_child(parts)
	var owned_any := false
	for p in s.get("parcalar", []):
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		parts.add_child(v)
		var th := _part_thumb(str(p[0]), str(p[1]), bool(p[3]), int(p[2]))
		th.custom_minimum_size = Vector2(130, 130)
		th.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v.add_child(th)
		var pn := UI.label(Catalog.item_name(str(p[0]), str(p[1])), UI.FS_KUCUK, UI.METIN, true)
		pn.custom_minimum_size.x = 130
		pn.clip_text = true
		pn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(pn)
		if bool(p[3]):
			owned_any = true
			th.modulate = Color(1, 1, 1, 0.55)
	var pr := HBoxContainer.new()
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	pr.add_theme_constant_override("separation", 8)
	m.body.add_child(pr)
	pr.add_child(_old_price(int(s.toplam), UI.FS_METIN))
	price_row(pr, int(s.fiyat), true, UI.FS_BUYUK)
	pr.add_child(E.pill(tr("-%%%d") % int(s.indirim), UI.KIRMIZI, UI.FS_KUCUK))
	if owned_any:
		m.body.add_child(UI.label("Sende olan parçalar fiyattan düşüldü", UI.FS_KUCUK, UI.YESIL, true))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", UI.B_S)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	m.body.add_child(btns)
	var no := UI.button("VAZGEÇ", "ikincil", UI.DOKUNMA, UI.FS_ORTA, "", 180)
	no.pressed.connect(m.close)
	btns.add_child(no)
	var ok := UI.button("SATIN AL", "yesil", UI.DOKUNMA, UI.FS_ORTA, "elmas", 240)
	ok.pressed.connect(func() -> void: _do_buy_set(m, ok, s))
	btns.add_child(ok)
	add_child(m)


func _do_buy_set(m: Control, ok: Button, s: Dictionary) -> void:
	ok.disabled = true
	UI.set_button_text(ok, "...")
	var res: Array = await islem_bekle(self, account, {"t": "set_al", "k": str(s.k), "fiyat": int(s.fiyat)}, "set_alindi")
	if is_instance_valid(m):
		(m as UI.Modal).close()
	if bool(res[0]):
		_play("kasa/satin_al")
		_play("odul", -6.0)
		# ödül penceresinde setin ilk giyilebilir parçası
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var look := _look.duplicate()
		var shown := false
		for p in s.get("parcalar", []):
			if str(p[0]) != "hareket" and str(p[0]) != "dovme" and not shown:
				shown = true
				_thumbs.request(look, str(p[0]), str(p[1]), pic)
		var rk := set_rarity(s)
		Fx.reward_popup(self, "SET ALINDI!", tr(str(s.ad)), str(RARITY[NADIR_KEYS.find(rk)][1]), UI.rarity_color(rk), pic)
		for p in s.get("parcalar", []):
			if str(p[0]) != "hareket":
				_look[str(p[0])] = str(p[1])
		_body.set_look(_look)
	else:
		_play("hata", -4.0)
		UI.toast(str((res[1] as Dictionary).get("m", "Satın alınamadı")), null, 2.4, "hata")
	_refresh_selection()


# Hediye: arkadaş listesi; GÖNDER'e iki kez dokunulur (ilk dokunuş ONAYLA'ya çevirir). Elmas senden düşer,
# eşya arkadaşına gider. Günlük sınır ve seviye şartı sunucuda.
func _gift_open() -> void:
	var cat: String = _pending[0]
	var id: String = _pending[1]
	if cat == "" or cat == "set" or Catalog.price(cat, id) <= 0:
		return
	if not account or account.handle == "":
		_play("hata", -6.0)
		UI.toast("Hediye göndermek için hesap aç", null, 2.4, "bilgi")
		return
	var hd: Dictionary = account.eco.get("hediye", {})
	var price := _price_now(cat, id)
	var tier: Array = Catalog.rarity(Catalog.price(cat, id))
	var rk := UI.rarity_key(str(tier[1]))
	var m := UI.modal("HEDİYE GÖNDER", 720)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", UI.B_M)
	m.body.add_child(top)
	var card := item_card(cat, id, Catalog.item_name(cat, id), rk, _thumbs, profile.look, 170)
	card.custom_minimum_size.x = 132
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(card)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 6)
	top.add_child(info)
	var nm := UI.title(Catalog.item_name(cat, id), UI.FS_BUYUK - 4, UI.rarity_color(rk).lightened(0.2))
	info.add_child(nm)
	var pr := HBoxContainer.new()
	price_row(pr, price, profile.gems >= price, UI.FS_ORTA)
	info.add_child(pr)
	var kalan := int(hd.get("kalan", 3))
	info.add_child(UI.label(tr("Bugün kalan hediye: %d/%d") % [kalan, int(hd.get("sinir", 3))], UI.FS_KUCUK, UI.METIN_SOLUK))
	var min_sv := int(hd.get("min_seviye", 5))
	var sv := int(account.eco.get("seviye", 1))
	if sv < min_sv:
		info.add_child(UI.label(tr("Hediye için en az %d. seviye olmalısın.") % min_sv, UI.FS_KUCUK, UI.KIRMIZI.lightened(0.3)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 236)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(sc)
	m.body.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", UI.B_XS)
	sc.add_child(list)
	var friends: Array = account.friends
	if friends.is_empty():
		var bos := UI.label("Hediye göndermek için önce arkadaş ekle.", UI.FS_METIN, UI.METIN_SOLUK, true)
		bos.custom_minimum_size.y = 120
		bos.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(bos)
	for f in friends:
		var row := E.row_box(Color(0, 0, 0, 0), Vector4(UI.B_S, 4, 4, 4))
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", UI.B_S)
		row.add_child(h)
		var av := E.avatar(str(f.get("name", f.handle)), str(f.handle), 48)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(av)
		var fv := VBoxContainer.new()
		fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fv.alignment = BoxContainer.ALIGNMENT_CENTER
		fv.add_theme_constant_override("separation", -2)
		h.add_child(fv)
		var fl := UI.title(str(f.get("name", f.handle)), UI.FS_METIN, UI.METIN)
		fl.clip_text = true
		fl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		fv.add_child(fl)
		fv.add_child(UI.label("@" + str(f.handle), UI.FS_KUCUK, UI.METIN_SOLUK))
		var send := UI.button("GÖNDER", "yesil", UI.DOKUNMA, UI.FS_METIN, "gift", 200)
		send.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		send.disabled = kalan <= 0 or sv < min_sv or profile.gems < price
		h.add_child(send)
		var adim := {"onay": false}
		var hh := str(f.handle)
		send.pressed.connect(func() -> void:
			if not bool(adim.onay):
				adim.onay = true
				UI.set_button_text(send, "ONAYLA")
				UI.set_button_kind(send, "ana")
				return
			send.disabled = true
			UI.set_button_text(send, "...")
			var res: Array = await islem_bekle(self, account, {"t": "hediye", "handle": hh, "kat": cat, "id": id, "fiyat": price}, "hediye_gitti")
			if not is_instance_valid(m):
				return
			if bool(res[0]):
				m.close()
				_play("kasa/satin_al")
				_play("odul", -6.0)
				UI.toast(tr("Hediye gönderildi: @%s") % hh, null, 2.4, "basari")
				Fx.confetti(_kok, get_viewport().get_visible_rect().size * Vector2(0.5, 0.4), [UI.AMBER, "#ff4d6d", "#5be37d", "#ffffff"])
			else:
				_play("hata", -4.0)
				UI.toast(str((res[1] as Dictionary).get("m", "")), null, 2.6, "hata")
				adim.onay = false
				send.disabled = false
				UI.set_button_kind(send, "yesil")
				UI.set_button_text(send, "GÖNDER"))
	add_child(m)


func _pick(id: String) -> void:
	_deal_price = -1
	_play("kumas", -4.0)
	var geri := _onizleme_geri_al(false)  # önceki satın alınmamış önizleme (başka kategoride olsa da) çıkar
	if _cat == "hareket":
		_preview_item = id
		if geri:
			_body.set_look(_look)
		_body.play_emote(id)
	else:
		_preview_item = ""
		_look[_cat] = id
	_pending = [_cat, id]
	_apply()
	if _cat == "dovme":
		_focus_tattoo(id)


# Satın alma onayı: kart önizlemesi, ad, fiyat; "X elmasa satın al?" ve SATIN AL.
func _buy() -> void:
	var cat: String = _pending[0]
	var id: String = _pending[1]
	if cat == "" or profile.owns(cat, id):
		return
	var price := _price_now(cat, id)
	if profile.gems < price:
		open_gem_store(self)
		return
	var tier: Array = Catalog.rarity(Catalog.price(cat, id))
	var rk := UI.rarity_key(str(tier[1]))
	var m := UI.modal("SATIN AL", 600)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_L)
	m.body.add_child(h)
	var card := item_card(cat, id, Catalog.item_name(cat, id), rk, _thumbs, profile.look, 230)
	card.custom_minimum_size.x = 176
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_card_selected(card, true)
	h.add_child(card)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UI.B_S)
	h.add_child(v)
	var pill := E.pill(str(tier[1]), UI.rarity_color(rk), UI.FS_KUCUK)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(pill)
	var nm := UI.title(Catalog.item_name(cat, id), UI.FS_BUYUK, UI.METIN)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 6)
	if price < Catalog.price(cat, id):
		pr.add_child(_old_price(Catalog.price(cat, id), UI.FS_METIN))
	price_row(pr, price, true, UI.FS_BUYUK)
	v.add_child(pr)
	v.add_child(UI.label(tr("%s elmasa satın al?") % E.sayi(price), UI.FS_METIN, UI.METIN_SOLUK))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", UI.B_S)
	btns.alignment = BoxContainer.ALIGNMENT_END
	m.body.add_child(btns)
	var no := UI.button("VAZGEÇ", "ikincil", UI.DOKUNMA, UI.FS_ORTA, "", 180)
	no.pressed.connect(m.close)
	btns.add_child(no)
	var ok := UI.button("SATIN AL", "yesil", UI.DOKUNMA, UI.FS_ORTA, "elmas", 230)
	ok.pressed.connect(func() -> void: _do_buy(m, ok, cat, id))
	btns.add_child(ok)
	add_child(m)


func _do_buy(m: Control, ok: Button, cat: String, id: String) -> void:
	if not account or not account.connected:
		_play("hata", -4.0)
		UI.toast("Sunucuya bağlanılamadı", null, 2.2, "hata")
		return
	ok.disabled = true
	UI.set_button_text(ok, "...")
	var st := {"r": []}
	var on_res := func(good: bool, msg: String) -> void: st.r = [good, msg]
	account.purchase_result.connect(on_res)
	account.buy(cat, id, true, _price_now(cat, id))
	var t0 := Time.get_ticks_msec()
	while (st.r as Array).is_empty() and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	account.purchase_result.disconnect(on_res)
	var res: Array = st.r
	if res.is_empty():
		res = [false, "Sunucu yanıt vermedi"]
	if is_instance_valid(m):
		(m as UI.Modal).close()
	if bool(res[0]):
		_play("kasa/satin_al")
		_play("odul", -6.0)
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_thumbs.request(profile.look, cat, id, pic)
		var tier: Array = Catalog.rarity(Catalog.price(cat, id))
		Fx.reward_popup(self, "SATIN ALINDI!", Catalog.item_name(cat, id), str(tier[1]), UI.rarity_color(str(tier[1])), pic)
		if cat != "hareket":
			_look[cat] = id
			_body.set_look(_look)
	else:
		_play("hata", -4.0)
		UI.toast(str(res[1]) if str(res[1]) != "" else "Satın alınamadı", null, 2.4, "hata")
	_refresh_selection()


func _apply() -> void:
	if _cat != "hareket":
		_body.set_look(_look)
	_refresh_selection()


# Seçimi koruyarak kartları ve alt çubuğu yeniler (kaydırma yeri korunur).
func _refresh_selection() -> void:
	var sv := _scroll.scroll_vertical
	_refresh(false)
	await get_tree().process_frame
	_scroll.scroll_vertical = sv


# Sahip olunmayan parçalar kaydedilmez; görünüş kayıtlıdan farklıysa ya da ad değiştiyse değişiklik var.
func _owned_look() -> Dictionary:
	var l := _look.duplicate()
	for c in ["govde", "sac", "kas", "sakal", "kiyafet", "aksesuar", "sapka", "dovme"]:
		if not profile.owns(c, str(l[c])):
			l[c] = profile.look[c]
	return l


# Satın alınmamış eşya yalnız önizlemedir: başka karta, sekmeye geçince karakter kayıtlı görünüşüne döner
# (sahip olunan, henüz kaydedilmemiş değişiklikler kalır). Hareket önizlemesi de durur. Görünüş değiştiyse true.
func _onizleme_geri_al(uygula := true) -> bool:
	var o := _owned_look()
	var degisti := o != _look
	_look = o
	if _preview_item != "" and _body:
		_body.stop_emote()
	_preview_item = ""
	if degisti and uygula and _body:
		_body.set_look(_look)
	return degisti


func _dirty() -> bool:
	return _owned_look() != profile.look or (_name_edit.text.strip_edges() != "" and _name_edit.text.strip_edges() != profile.player_name)


func _back() -> void:
	if _opening:
		return
	if not _dirty():
		_close(false)
		return
	var m := UI.modal("ÇIKIŞ", 560)
	m.body.add_child(UI.label("Değişiklikler kaydedilsin mi?", UI.FS_METIN, UI.METIN, true))
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", UI.B_S)
	m.body.add_child(btns)
	var no := UI.button("KAYDETME", "tehlike", UI.DOKUNMA, UI.FS_ORTA, "", 210)
	no.pressed.connect(func() -> void:
		m.close()
		_close(false))
	btns.add_child(no)
	var yes := UI.button("KAYDET", "ana", UI.DOKUNMA, UI.FS_ORTA, "", 210)
	yes.pressed.connect(func() -> void:
		m.close()
		_save())
	btns.add_child(yes)
	add_child(m)


func _close(saved: bool) -> void:
	preload("res://scripts/telemetri.gd").ekran("menu")
	E.outro(_kok, func() -> void:
		closed.emit(saved)
		queue_free())


func _save() -> void:
	var reverted := []
	for c in ["govde", "sac", "kas", "sakal", "kiyafet", "aksesuar", "sapka", "dovme"]:
		if not profile.owns(c, _look[c]):
			reverted.append(Catalog.item_name(c, _look[c]))
	_look = _owned_look()
	var n := _name_edit.text.strip_edges()
	if n != "":
		profile.player_name = n
	profile.look = _look.duplicate()
	profile.save()
	if not reverted.is_empty():
		_body.set_look(_look)
		UI.toast("Satın alınmamış parçalar çıkarıldı", null, 1.6, "bilgi")
		await get_tree().create_timer(1.2).timeout
	else:
		UI.toast("Kaydedildi", null, 1.2, "basari")
	_close(true)


# ---------------------------------------------------------------------
# Kasa
# ---------------------------------------------------------------------

# Nadirlik zarı: ağırlıklara göre 0-3 arası bir kademe (SIRADAN/NADİR/EPİK/EFSANE).
static func _roll_tier(weights: Array) -> int:
	var roll := randi() % 100
	var acc := 0
	for i in 4:
		acc += int(weights[i])
		if roll < acc:
			return i
	return 0


# Havuzdan istenen kademede rastgele bir parça; o kademede yoksa en yakın kademeye bakar.
static func _pick_tier(pool: Array, tier: int) -> Array:
	for step in [0, 1, -1, 2, -2, 3, -3]:
		var t := clampi(tier + int(step), 0, 3)
		var opts := pool.filter(func(it: Array) -> bool: return Catalog.rarity(it[3])[1] == RARITY[t][1])
		if not opts.is_empty():
			return opts[randi() % opts.size()]
	return pool[randi() % pool.size()]


func _set_chest_busy(ch: Array, busy: bool) -> void:
	for b in _chest_btns:
		if is_instance_valid(b) and b.get_meta("ch") == ch:
			(b as Button).disabled = busy
			UI.set_button_text(b, "..." if busy else "AÇ")


func _open_chest(ch: Array) -> void:
	if _opening:
		return
	var kind := chest_kind(ch)
	# ücretsiz hak (seviye yolu) ya da hediye kasa varsa önce o kullanılır
	var free := _free_chests(kind) > 0
	if kind == "nadir" and not free:
		return
	if not free and profile.gems < int(ch[1]):
		_play("hata", -6.0)
		UI.toast("Elmas yetmiyor", null, 1.8, "hata")
		open_gem_store(self)
		return
	# sonuç SUNUCUDA belirlenir (elması da sunucu düşer, eşyayı o verir)
	if not account or not account.connected:
		_play("hata", -4.0)
		UI.toast("Sunucuya bağlanılamadı", null, 2.2, "hata")
		return
	_opening = true
	_set_chest_busy(ch, true)
	var st := {"d": {}, "err": ""}
	var on_res := func(d: Dictionary) -> void: st.d = d
	var on_msg := func(t: String) -> void: st.err = t
	account.chest_result.connect(on_res)
	account.message.connect(on_msg)
	account.send({"t": "kasa_ac", "kasa": kind, "hak": free and kind != "nadir"})
	var t0 := Time.get_ticks_msec()
	while (st.d as Dictionary).is_empty() and str(st.err) == "" and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
	account.chest_result.disconnect(on_res)
	account.message.disconnect(on_msg)
	_opening = false
	_set_chest_busy(ch, false)
	var d: Dictionary = st.d
	if d.is_empty():
		_play("hata", -4.0)
		UI.toast(str(st.err) if str(st.err) != "" else "Sunucu yanıt vermedi", null, 2.4, "hata")
		return
	var won: Array = []
	_refund = int(d.get("iade", 0))
	_last_garanti = bool(d.get("garanti", false))
	if not bool(d.get("kopya", false)):
		var cat := str(d.kat)
		var id := str(d.id)
		won = [cat, id, Catalog.item_name(cat, id), Catalog.price(cat, id)]
	# gösteri: sonucun nereden geldiğini bilmez
	spin(ch, won)


func _refund_amount(ch: Array) -> int:
	return _refund if _refund > 0 else int(ch[1]) / 2


# Kasa açılış gösterisi. ch: CHESTS içindeki kasa; won: [kategori, kimlik, ad, fiyat] (boşsa elmas iadesi).
# 1) kasa yukarıdan düşer, 2) gittikçe sertleşen sarsıntı ve aralıktan sızan ışık, 3) kilit kopar,
# 4) kapak açılır, ışık patlar, kasa kameraya doğru uçar; ardından şerit döner (_spin_reel).
func spin(ch: Array, won: Array) -> void:
	_opening = true
	_sahne_ciz(false)  # kasa gösterisi ekranı kaplarken arkadaki 3D vitrin çizilmez
	preload("res://scripts/telemetri.gd").ekran("kasa_acilis")
	var gold: bool = ch[2]
	var accent := Color("#ffc23a") if gold else Color("#ffcf6a")
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ov)
	var vs := ov.get_viewport_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.012, 0.018, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(dim)
	ov.set_meta("dim", dim)
	dim.create_tween().tween_property(dim, "color:a", 0.95, 0.25)
	var halo := E.glow(accent, 0.3)
	halo.size = Vector2(vs.y * 1.5, vs.y * 1.5)
	halo.position = vs / 2.0 - halo.size / 2.0
	halo.pivot_offset = halo.size / 2.0
	halo.modulate.a = 0.0
	ov.add_child(halo)
	halo.create_tween().tween_property(halo, "modulate:a", 1.0, 0.4)
	ov.add_child(E.vignette(0.0, 0.85))
	var head := UI.title(tr_upper(str(ch[0])), UI.FS_DEV, UI.NADIRLIK.efsane if gold else UI.METIN, true)
	head.position = Vector2(0, 28)
	head.size = Vector2(vs.x, 60)
	head.modulate.a = 0.0
	ov.add_child(head)
	ov.set_meta("head", head)
	head.create_tween().tween_property(head, "modulate:a", 1.0, 0.3).set_delay(0.15)
	# sandığın arkasından sızan dönen huzmeler
	var leak := Fx.Rays.new()
	leak.color = accent
	leak.size = Vector2.ONE * 620.0
	leak.position = vs / 2.0 - leak.size / 2.0 + Vector2(0, 10)
	leak.pivot_offset = leak.size / 2.0
	leak.modulate.a = 0.0
	leak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(leak)
	# kasa: üretilmiş resim (kapalı / açık), yoksa çizim
	var art: Array = CHEST_ART[1 if gold else 0]
	var tex_closed := UI.texture(art[0], 560)
	var tex_open := UI.texture(art[1], 560)
	var chest: Control
	var pic := TextureRect.new()
	if tex_closed and tex_open:
		pic.texture = tex_closed
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chest = pic
	else:
		var drawn := Fx.Chest.new()
		drawn.gold = gold
		chest = drawn
	chest.size = Vector2(440, 330)
	chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(chest)
	var home := vs / 2.0 - chest.size / 2.0 + Vector2(0, 26)
	chest.position = home + Vector2(0, -vs.y * 0.75)
	chest.pivot_offset = chest.size * Vector2(0.5, 0.85)
	var lock_at := home + chest.size * Vector2(0.38, 0.62)
	var tw := create_tween()
	# 0) düşer, yere çarpar (ezilip toparlanır), toz kalkar
	tw.tween_interval(0.12)
	tw.tween_property(chest, "position", home, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_play("kasa/inis")
		_shake(ov, 9.0, 0.22)
		_sparks(ov, home + chest.size * Vector2(0.5, 0.92), Color(0.7, 0.66, 0.58), 40, 420.0, true, 3.0, 7.0)
		chest.scale = Vector2(1.14, 0.84))
	tw.tween_property(chest, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.12)
	# 1) sarsılır: gittikçe sertleşir, aralıktan ışık sızar, hale nabız atar
	tw.tween_callback(func() -> void: _play("kasa/sallanma"))
	tw.tween_method(func(k: float) -> void:
		var a := k * k
		chest.rotation = sin(k * 46.0) * 0.07 * (0.3 + a)
		chest.position = home + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 8.0 * a
		leak.modulate.a = 0.35 * a
		halo.scale = Vector2.ONE * (1.0 + 0.12 * a + 0.04 * sin(k * 30.0)), 0.0, 1.0, 0.9)
	# 2) kilit kopar: sert vuruş, kıvılcım ve metal parçalar, kısa flaş
	tw.tween_callback(func() -> void:
		chest.rotation = 0.0
		chest.position = home
		_play("kasa/kilit")
		_sparks(ov, lock_at, Color("#ffb347"), 56, 620.0, true)
		_sparks(ov, lock_at, Color(0.62, 0.62, 0.6), 18, 520.0, true, 6.0, 11.0)
		_flash(ov, Color(1, 0.88, 0.65, 0.35), 0.25)
		_shake(ov, 7.0, 0.22)
		if bool(profile.settings.get("titresim", true)):
			Input.vibrate_handheld(30))
	tw.tween_property(chest, "scale", Vector2.ONE * 1.1, 0.07)
	tw.tween_property(chest, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.1)
	# 3) kapak açılır: ışık patlar, yükselen kıvılcımlar
	tw.tween_callback(func() -> void:
		_play("kasa/acilis")
		if chest is TextureRect:
			pic.texture = tex_open
		_flash(ov, Color(1, 0.95, 0.82, 0.6), 0.5)
		_sparks(ov, home + chest.size * Vector2(0.5, 0.35), Color("#ffe08a"), 80, 760.0, false)
		_motes(ov, home + chest.size * Vector2(0.5, 0.4), accent, 2.0)
		var rg := Ring.new()
		rg.position = home + chest.size * Vector2(0.5, 0.4)
		rg.color = accent
		rg.max_r = 520.0
		rg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.add_child(rg))
	if chest is TextureRect:
		tw.tween_property(chest, "scale", Vector2.ONE * 1.12, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_method(func(t: float) -> void:
			chest.set("lid", t)
			chest.set("glow", t)
			chest.queue_redraw(), 0.0, 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(leak, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(leak, "scale", Vector2.ONE * 1.8, 0.7)
	tw.tween_interval(0.45)
	# 4) kasa kameraya doğru uçar, şerit gelir
	tw.tween_callback(func() -> void: _play("kasa/serit", -2.0))
	tw.tween_property(chest, "scale", Vector2.ONE * 2.6, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(chest, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(leak, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(halo, "modulate:a", 0.45, 0.35)
	tw.tween_callback(func() -> void:
		chest.queue_free()
		leak.queue_free()
		_spin_reel(ov, ch, won))


# CS:GO tarzı kasa şeridi: kartlar hızla kayar, yavaşlar ve ortadaki ibrenin altında durur.
# Kazanan önceden belli; şeritte tam ibreye denk gelecek yere konur, kartın içinde rastgele bir noktada durur.
func _spin_reel(ov: Control, ch: Array, won: Array) -> void:
	var vs := ov.get_viewport_rect().size
	var gold: bool = ch[2]
	var step := REEL_CARD.x + REEL_GAP
	var band_h := REEL_CARD.y + 36.0
	var band_y := vs.y * 0.5 - band_h / 2.0
	var cx := vs.x / 2.0
	var dim: ColorRect = ov.get_meta("dim")
	var head: Label = ov.get_meta("head")

	# şerit bandı: koyu zemin, üstte ve altta renkli çizgi (ibrenin altındaki kartın renginde)
	var band := Control.new()
	band.position = Vector2(0, band_y)
	band.size = Vector2(vs.x, band_h)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(band)
	var band_bg := ColorRect.new()
	band_bg.color = Color(0.02, 0.024, 0.022, 0.94)
	band_bg.size = band.size
	band_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(band_bg)
	var clip := Control.new()
	clip.clip_contents = true
	clip.size = band.size
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(clip)
	var strip := Control.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position.y = (band_h - REEL_CARD.y) / 2.0
	clip.add_child(strip)
	var lines: Array = []
	for y in [0.0, band_h - 3.0]:
		var ln := ColorRect.new()
		ln.color = Color(UI.AMBER, 0.6)
		ln.position = Vector2(0, y)
		ln.size = Vector2(vs.x, 3)
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(ln)
		lines.append(ln)

	# şeritteki eşyalar: kasanın oranlarıyla rastgele; kazanan REEL_WIN sırasında
	var all := Catalog.shop_items()
	var items: Array = []
	for i in REEL_N:
		items.append(_pick_tier(all, _roll_tier(ch[3])))
	if won.is_empty():
		items[REEL_WIN] = ["elmas", "", tr("+%d elmas") % _refund_amount(ch), 0]
	else:
		items[REEL_WIN] = won
	# yakın kaçış: kazananın hemen yanına bazen daha nadir bir parça düşer
	if randf() < 0.6:
		items[REEL_WIN + (1 if randf() < 0.5 else -1)] = _pick_tier(all, 3 if randf() < 0.5 else 2)
	var cards: Array = []
	for i in REEL_N:
		var c := loot_card(items[i], null, profile.look)
		c.size = REEL_CARD
		c.position = Vector2(-(i + 1) * step + REEL_GAP, 0)
		strip.add_child(c)
		cards.append(c)
	# küçük resimler: önce kazanana yakın kartlar (şerit yavaşlarken görünenler)
	var order: Array = range(REEL_N)
	order.sort_custom(func(a: int, b: int) -> bool: return absi(a - REEL_WIN) > absi(b - REEL_WIN))
	for i in order:
		var it: Array = items[i]
		if it[0] != "elmas" and it[0] != "dovme":
			_thumbs.request(profile.look, it[0], it[1], (cards[i] as LootCard).thumb, true)

	# kenarlarda kararma
	for side in 2:
		var edge := TextureRect.new()
		var gt := GradientTexture2D.new()
		gt.width = 64
		gt.height = 4
		var g := Gradient.new()
		g.set_color(0, Color(0.01, 0.012, 0.012, 0.98 if side == 0 else 0.0))
		g.set_color(1, Color(0.01, 0.012, 0.012, 0.0 if side == 0 else 0.98))
		gt.gradient = g
		edge.texture = gt
		edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		edge.stretch_mode = TextureRect.STRETCH_SCALE
		edge.size = Vector2(minf(320.0, vs.x * 0.22), band_h)
		edge.position = Vector2(0.0 if side == 0 else vs.x - edge.size.x, 0)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(edge)

	# ortadaki ibre
	var ptr := ReelPointer.new()
	ptr.band_top = 26.0
	ptr.band_h = band_h
	ptr.size = Vector2(48, band_h + 52)
	ptr.position = Vector2(cx - 24, band_y - 26)
	ptr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ptr.z_index = 2
	ov.add_child(ptr)

	band.modulate.a = 0.0
	ptr.modulate.a = 0.0
	band.scale = Vector2(1.0, 0.2)
	band.pivot_offset = band.size / 2.0
	var bt := band.create_tween().set_parallel()
	bt.tween_property(band, "modulate:a", 1.0, 0.2)
	bt.tween_property(band, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ptr.create_tween().tween_property(ptr, "modulate:a", 1.0, 0.25).set_delay(0.15)

	# tık sesleri: ibre her kart sınırını geçince (hızlıyken sık, yavaşken seyrek); üç çeşit sırayla
	var ticks: Array = []
	for k in 6:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/ses/kasa/tik_%d.ogg" % (k % 3 + 1))
		p.volume_db = -3.0
		ov.add_child(p)
		ticks.append(p)
	var vibrate: bool = bool(profile.settings.get("titresim", true))
	var s0 := vs.x + randf_range(-30.0, 30.0)
	var off := randf_range(0.12, 0.88) * REEL_CARD.x
	var s1 := cx + (REEL_WIN + 1) * step - REEL_GAP - off
	var st := {"idx": int(floor((s0 - cx + REEL_GAP) / step)), "k": 0, "last": 0}
	strip.position.x = s0
	ptr.pivot_offset = Vector2(ptr.size.x / 2.0, band_y + band_h / 2.0 - ptr.position.y)
	var move := func(t: float) -> void:
		# kübik yavaşlama: başta çok hızlı, sonda son kartın üstünde süzülerek durur
		var s := lerpf(s0, s1, 1.0 - pow(1.0 - t, 3.0))
		strip.position.x = s
		# son anlarda ağır çekim: şerit yaklaşır, perde koyulaşır
		var z := clampf((t - 0.7) / 0.3, 0.0, 1.0)
		z = z * z * (3.0 - 2.0 * z)
		band.scale = Vector2.ONE * (1.0 + 0.05 * z)
		ptr.scale = band.scale
		dim.color.a = 0.95 + 0.04 * z
		var idx := int(floor((s - cx + REEL_GAP) / step))
		if idx != int(st.idx):
			st.idx = idx
			# bandın çizgileri ibrenin altındaki kartın nadirlik renginde
			if idx >= 0 and idx < REEL_N:
				var rk := UI.rarity_key(str(_tier_of(items[idx])[1]))
				var lc := UI.rarity_color(rk) if rk != "" else UI.ELMAS
				for ln in lines:
					(ln as ColorRect).color = Color(lc, 0.85)
				ptr.color = lc.lerp(Color("#ffd23a"), 0.35)
			var now := Time.get_ticks_msec()
			var gap := now - int(st.last)
			if gap >= 30:
				st.last = now
				var p: AudioStreamPlayer = ticks[int(st.k) % ticks.size()]
				st.k = int(st.k) + 1
				p.pitch_scale = lerpf(0.88, 1.14, clampf(1.0 - gap / 260.0, 0.0, 1.0)) + randf_range(-0.03, 0.03)
				p.play()
				ptr.flash = 1.0
				if vibrate and gap > 160:
					Input.vibrate_handheld(12)

	# durmaya yakın gerilim sesi (yükselen uğultu); duruş vuruşu onu keser
	var riser := {"p": null}
	var ov_wr: WeakRef = weakref(ov)  # pencere erken kapanırsa lambda silinmiş düğümü yakalamasın
	get_tree().create_timer(0.3 + REEL_TIME - 2.8).timeout.connect(func() -> void:
		if ov_wr.get_ref():
			riser.p = _play("kasa/gerilim", -5.0))

	var finish := func() -> void:
		_reveal(ov, band, ptr, cards, ch, won, riser.p)

	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_method(move, 0.0, 1.0, REEL_TIME)
	tw.tween_callback(finish)


# Kazanan kart: çevrilir, öne fırlar, ortaya taşınır; nadirliğe göre şok dalgası, ışınlar, flaş, konfeti.
# Altta TAMAM ve TEKRAR AÇ düğmeleri.
func _reveal(ov: Control, band: Control, ptr: Control, cards: Array, ch: Array, won: Array, riser: Variant) -> void:
	var vs := ov.get_viewport_rect().size
	var win_card: LootCard = cards[REEL_WIN]
	var tier: Array = ["", "ELMAS", "#3fd6f0"] if won.is_empty() else Catalog.rarity(int(won[3]))
	var tier_i := 1
	for i in 4:
		if RARITY[i][1] == tier[1]:
			tier_i = i
	var rk := UI.rarity_key(str(tier[1]))
	var col := UI.rarity_color(rk) if rk != "" else UI.ELMAS
	var vibrate: bool = bool(profile.settings.get("titresim", true))
	var head: Label = ov.get_meta("head")
	if is_instance_valid(riser):
		(riser as AudioStreamPlayer).create_tween().tween_property(riser, "volume_db", -40.0, 0.18)
	# vuruş sesi nadirliğe göre
	if won.is_empty():
		_play("kasa/vurus_nadir", -2.0)
		_play("kasa/elmas", -2.0)
	else:
		_play("kasa/" + ["vurus_siradan", "vurus_nadir", "vurus_epik", "vurus_efsane"][tier_i])
	# diğer kartlar kararır
	for c in cards:
		if c != win_card:
			(c as Control).create_tween().tween_property(c, "modulate", Color(0.3, 0.3, 0.32), 0.3)
	var center := win_card.get_global_rect().get_center()
	# kazananın arkasında dönen ışınlar
	var rays := Fx.Rays.new()
	rays.color = col
	rays.size = Vector2.ONE * [420.0, 560.0, 720.0, maxf(vs.x, 900.0)][tier_i]
	rays.position = center - rays.size / 2.0
	rays.pivot_offset = rays.size / 2.0
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.modulate.a = 0.0
	rays.scale = Vector2.ONE * 0.4
	ov.add_child(rays)
	var rt0 := rays.create_tween().set_parallel()
	rt0.tween_property(rays, "modulate:a", [0.45, 0.7, 0.9, 1.0][tier_i], 0.35)
	rt0.tween_property(rays, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# kazanan kart şeritten öne fırlar ve döner (flip)
	win_card.reparent(ov)
	win_card.z_index = 3
	win_card.pivot_offset = REEL_CARD / 2.0
	var wt := win_card.create_tween()
	wt.tween_property(win_card, "scale", Vector2(1.12, 1.12), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	wt.tween_callback(func() -> void: _play("kasa/kart_cevir", -3.0))
	wt.tween_property(win_card, "scale", Vector2(0.0, 1.17), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	wt.tween_callback(func() -> void:
		win_card.glow = 1.0
		win_card.queue_redraw()
		_sparks(ov, center, col, [20, 40, 70, 110][tier_i], [380.0, 500.0, 640.0, 820.0][tier_i], false)
		for k in (1 if tier_i < 3 else 2):
			var rg := Ring.new()
			rg.position = center
			rg.color = col.lightened(0.3)
			rg.max_r = [300.0, 420.0, 560.0, 760.0][tier_i] * (1.0 + 0.4 * k)
			rg.dur = 0.6 + 0.25 * k
			rg.width = [8.0, 12.0, 18.0, 24.0][tier_i]
			rg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ov.add_child(rg)
		if tier_i >= 1:
			_shake(ov, [0.0, 5.0, 10.0, 18.0][tier_i], 0.35))
	wt.tween_property(win_card, "scale", Vector2(1.2, 1.2), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if tier_i >= 3:
		_flash(ov, Color(1, 0.93, 0.7, 0.55), 0.7)
		_pillars(ov, center, col)
		var ov_wr: WeakRef = weakref(ov)
		get_tree().create_timer(0.22).timeout.connect(func() -> void:
			var o: Control = ov_wr.get_ref()
			if o:
				Fx.confetti(o, center + Vector2(0, 40), ["#ffd23a", "#ffb020", "#fff4c2", "#ffffff", col]))
		if vibrate:
			Input.vibrate_handheld(90)
	elif tier_i == 2:
		_flash(ov, Color(col.lightened(0.5), 0.35), 0.45)
		if vibrate:
			Input.vibrate_handheld(45)
	elif vibrate:
		Input.vibrate_handheld(20)
	# epik ve efsanede nadirlik adı yukarıdan iner (başlığın yerine)
	if tier_i >= 2:
		var slam := UI.title(tr(str(tier[1])) + "!", 72, col.lightened(0.15), true)
		slam.add_theme_constant_override("outline_size", 14)
		slam.position = Vector2(0, 14)
		slam.size = Vector2(vs.x, 96)
		slam.pivot_offset = slam.size / 2.0
		slam.scale = Vector2.ONE * 2.4
		slam.modulate.a = 0.0
		slam.z_index = 4
		ov.add_child(slam)
		head.create_tween().tween_property(head, "modulate:a", 0.0, 0.15)
		var sl := slam.create_tween().set_parallel()
		sl.tween_property(slam, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.25)
		sl.tween_property(slam, "modulate:a", 1.0, 0.15).set_delay(0.25)
	# kısa bekleyiş, sonra şerit söner, kart ortaya taşınır; sonuç ve düğmeler gelir
	var target := Vector2(vs.x / 2.0, vs.y * 0.44)
	var big := 1.5 if vs.y >= 700.0 else 1.35
	var mt := create_tween()
	mt.tween_interval(1.0)
	mt.tween_callback(func() -> void:
		_motes(ov, target + Vector2(0, 40), col, 6.0)
		var ft := band.create_tween().set_parallel()
		ft.tween_property(band, "modulate:a", 0.0, 0.3)
		ft.tween_property(ptr, "modulate:a", 0.0, 0.2))
	mt.tween_property(win_card, "position", target - REEL_CARD / 2.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	mt.parallel().tween_property(win_card, "scale", Vector2.ONE * big, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	mt.parallel().tween_property(rays, "position", target - rays.size / 2.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	mt.tween_callback(func() -> void: _reveal_footer(ov, ch, won, tier, col, target.y + REEL_CARD.y * big / 2.0))
	# hafif nefes alan parıltı
	var pulse := win_card.create_tween().set_loops()
	pulse.tween_interval(0.5)
	pulse.tween_method(func(g: float) -> void:
		win_card.glow = g
		win_card.queue_redraw(), 1.0, 0.6, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_method(func(g: float) -> void:
		win_card.glow = g
		win_card.queue_redraw(), 0.6, 1.0, 0.7).set_trans(Tween.TRANS_SINE)


# Sonuç satırı (nadirlik hapı + ad) ve düğmeler: TAMAM / TEKRAR AÇ.
func _reveal_footer(ov: Control, ch: Array, won: Array, tier: Array, col: Color, y: float) -> void:
	var vs := ov.get_viewport_rect().size
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", UI.B_XS)
	box.position = Vector2(0, y + UI.B_M)
	box.size = Vector2(vs.x, vs.y - y - UI.B_M)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.z_index = 4
	ov.add_child(box)
	var nm := UI.title((tr("+%d elmas geri") % _refund_amount(ch)) if won.is_empty() else str(won[2]), UI.FS_DEV - 4, col.lightened(0.35), true)
	box.add_child(nm)
	if won.is_empty():
		box.add_child(UI.label("Hepsi sende", UI.FS_METIN, UI.METIN_SOLUK, true))
	if _last_garanti:
		# şans güvencesinden geldi
		var gp := E.pill("GÜVENCE", UI.AMBER, UI.FS_KUCUK + 2)
		gp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(gp)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", UI.B_M)
	box.add_child(btns)
	var ok := UI.button("TAMAM", "ikincil", UI.DOKUNMA, UI.FS_ORTA, "", 200)
	btns.add_child(ok)
	# tekrar: ücretsiz hak kaldıysa ÜCRETSİZ, yoksa fiyat (hediye kasada hak bittiyse düğme yok)
	var kind := chest_kind(ch)
	var free_left := _free_chests(kind)
	var again := UI.button("TEKRAR" if free_left <= 0 else "ÜCRETSİZ", "yesil", UI.DOKUNMA, UI.FS_ORTA, "", 0)
	var ar: HBoxContainer = again.get_meta("row")
	if free_left > 0:
		var xl := UI.title(tr("×%d") % free_left, UI.FS_ORTA, Color.WHITE)
		xl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ar.add_child(xl)
	else:
		var gi := UI.icon("elmas", 30)
		gi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ar.add_child(gi)
		var pl := UI.title(E.sayi(int(ch[1])), UI.FS_ORTA, Color.WHITE)
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ar.add_child(pl)
	again.custom_minimum_size.x = 280
	again.visible = kind != "nadir" or free_left > 0
	btns.add_child(again)
	box.modulate.a = 0.0
	var bt := box.create_tween().set_parallel()
	bt.tween_property(box, "modulate:a", 1.0, 0.25)
	bt.tween_property(box, "position:y", box.position.y, 0.35).from(box.position.y + 30.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var done := {"v": false}
	var finish := func(again_open: bool) -> void:
		if bool(done.v):
			return
		done.v = true
		_opening = false
		_sahne_ciz(true)
		var out := ov.create_tween()
		out.tween_property(ov, "modulate:a", 0.0, 0.2)
		out.tween_callback(ov.queue_free)
		_chest_reward(ch, won)
		if again_open:
			get_tree().create_timer(0.25).timeout.connect(func() -> void: _open_chest(ch))
	ok.pressed.connect(finish.bind(false))
	again.pressed.connect(finish.bind(true))


# Kasadan çıkan eşya karakterde önizlenir (Kaydet'e basınca üstünde kalır); elmas iadesi bildirilir.
func _chest_reward(ch: Array, won: Array) -> void:
	_refund = -1
	if won.is_empty():
		UI.toast(tr("+%d elmas geri") % _refund_amount(ch), null, 2.0, "basari")
		_refresh_selection()
		return
	if won[0] == "hareket":
		_body.play_emote(won[1])
	else:
		_look[won[0]] = won[1]
		_body.set_look(_look)
	_pending = [str(won[0]), str(won[1])]
	_deal_price = -1
	_refresh_selection()


# Kıvılcım patlaması: merkezden saçılan, sönerek kaybolan parçacıklar.
func _sparks(parent: Control, at: Vector2, color: Color, amount: int, speed: float, falling: bool, smin := 2.5, smax := 6.0) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.9
	p.spread = 180.0
	p.direction = Vector2.UP
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.4
	p.damping_max = speed * 0.9
	p.gravity = Vector2(0, 1300) if falling else Vector2(0, 120)
	p.scale_amount_min = smin * 0.13
	p.scale_amount_max = smax * 0.13
	var g := Gradient.new()
	g.set_color(0, color.lightened(0.6))
	g.set_color(1, Color(color, 0.0))
	p.color_ramp = g
	p.texture = _dot()
	p.z_index = 5
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


static var _dot_tex: Texture2D


# Parçacıklar için yumuşak kenarlı yuvarlak nokta (kare piksel görünmesin).
static func _dot() -> Texture2D:
	if _dot_tex == null:
		var gt := GradientTexture2D.new()
		gt.width = 16
		gt.height = 16
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.add_point(0.45, Color(1, 1, 1, 0.85))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		gt.gradient = g
		_dot_tex = gt
	return _dot_tex


# Yavaşça yükselen ışık zerreleri (bir süre akar, sonra durur).
func _motes(parent: Control, at: Vector2, color: Color, dur: float) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = 46
	p.lifetime = 2.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(220, 60)
	p.direction = Vector2.UP
	p.spread = 25.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 140.0
	p.gravity = Vector2(0, -30)
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.7
	var g := Gradient.new()
	g.set_color(0, Color(color.lightened(0.6), 0.0))
	g.add_point(0.2, Color(color.lightened(0.5), 0.9))
	g.set_color(g.get_point_count() - 1, Color(color, 0.0))
	p.color_ramp = g
	p.texture = _dot()
	p.z_index = 1
	parent.add_child(p)
	p.emitting = true
	var p_wr: WeakRef = weakref(p)  # parçacık erken silinirse lambda silinmiş düğümü yakalamasın
	get_tree().create_timer(dur).timeout.connect(func() -> void:
		var pp: CPUParticles2D = p_wr.get_ref()
		if pp:
			pp.emitting = false)


# Efsanede yukarıdan inen ışık sütunları.
func _pillars(parent: Control, at: Vector2, color: Color) -> void:
	var vs := parent.get_viewport_rect().size
	for k in 3:
		var r := TextureRect.new()
		var gt := GradientTexture2D.new()
		gt.width = 8
		gt.height = 64
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(1, 0)
		var g := Gradient.new()
		g.set_color(0, Color(color, 0.0))
		g.add_point(0.5, Color(color.lightened(0.5), 0.55))
		g.set_color(g.get_point_count() - 1, Color(color, 0.0))
		gt.gradient = g
		r.texture = gt
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		var w: float = [260.0, 90.0, 90.0][k]
		var x: float = at.x + float([0.0, -300.0, 300.0][k])
		r.size = Vector2(w, vs.y)
		r.position = Vector2(x - w / 2.0, 0)
		r.pivot_offset = Vector2(w / 2.0, 0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.scale = Vector2(0.0, 1.0)
		parent.add_child(r)
		var tw := r.create_tween()
		tw.tween_property(r, "scale", Vector2.ONE, 0.25).set_delay(0.08 * k).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(r, "modulate:a", 0.0, 1.6).set_delay(0.3)
		tw.tween_callback(r.queue_free)


# Tam ekran kısa flaş.
func _flash(parent: Control, color: Color, dur: float) -> void:
	var f := ColorRect.new()
	f.color = color
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 6
	parent.add_child(f)
	var t := f.create_tween()
	t.tween_property(f, "color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(f.queue_free)


# Ekran sarsıntısı: sönümlenen rastgele kayma.
func _shake(node: Control, strength: float, dur: float) -> void:
	var base := Vector2.ZERO
	var t := node.create_tween()
	t.tween_method(func(k: float) -> void:
		node.position = base + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * (1.0 - k), 0.0, 1.0, dur)
	t.tween_callback(func() -> void: node.position = base)


# Sol 3D vitrinin çizimi: kasa gösterisi ekranı kapladığında durur (boşa GPU / pil harcamasın).
func _sahne_ciz(acik: bool) -> void:
	if is_instance_valid(_sahne_sv):
		_sahne_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS if acik else SubViewport.UPDATE_DISABLED
