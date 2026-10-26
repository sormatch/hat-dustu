# Hat Düştü TASARIM SİSTEMİ (arayüz takımı / UI kit).
# Rehber: docs/TASARIM.md   ·   Görseller: assets/ui/kit/ (tools/arayuz_uret.mjs ile üretildi)
# Görsel yoksa her parça kodla çizilen düz bir yedeğe düşer; oyun asla görselsiz kırılmaz.
# Kullanım: const UI := preload("res://scripts/ui.gd")  ->  UI.button("OYNA", "ana", UI.BTN_H, UI.FS_BUYUK, "oyna")
extends RefCounted

# =====================================================================
# BELİRTEÇLER (design tokens) — renk, yazı, boşluk, köşe, boyut
# =====================================================================

# --- Palet ---
const ZEMIN := Color("#0b0e0f")        # ekran zemini (en koyu)
const YUZEY := Color("#161b19")        # panel içi
const YUZEY_2 := Color("#212826")      # panel içinde kart / satır
const CIZGI := Color("#3a4240")        # ince ayraç, pasif kenar
const ZEYTIN := Color("#4b5a3c")       # boyalı yeşil metal (marka rengi)
const AMBER := Color("#ffb020")        # ANA vurgu: birincil düğme, seçili sekme, ilerleme
const AMBER_KOYU := Color("#b86f00")
const TEHLIKE_SARI := Color("#f5c518") # sarı-siyah şerit sarısı
const KIRMIZI := Color("#e0322a")      # tehlike / sil / çık
const YESIL := Color("#4cc23a")        # onay / satın al / hazır
const MAVI := Color("#3fa8ff")         # bilgi, bağlantı
const ELMAS := Color("#5ff0ff")        # elmas para birimi
const METIN := Color("#f3ead8")        # ana yazı (krem)
const METIN_SOLUK := Color(0.66, 0.68, 0.64)  # ikincil yazı
const METIN_KOYU := Color("#1a1206")   # amber zemin üstünde koyu yazı gerekirse
const PERDE := Color(0.0, 0.0, 0.0, 0.72)      # modal arka perdesi

# Nadirlik renkleri (kart çerçevesi, yazı, parıltı)
const NADIRLIK := {
	"siradan": Color("#9aa3ab"),
	"nadir": Color("#3fa8ff"),
	"epik": Color("#b05cff"),
	"efsane": Color("#ffc23a"),
}

# --- Yazı tipleri ---
const TITLE_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")  # başlık, düğme, sayı
const METIN_FONT := preload("res://assets/fonts/metin.tres")            # Rubik 500 — gövde metni (tema varsayılanı)

# --- Yazı boyutu ölçeği (px, 1280x720 tabanında) ---
const FS_KUCUK := 16   # dipnot, rozet, ipucu
const FS_METIN := 20   # gövde metni
const FS_ORTA := 24    # alt başlık, küçük düğme
const FS_BUYUK := 32   # panel başlığı, ana düğme
const FS_DEV := 44     # ekran başlığı, sonuç yazısı

# --- Boşluk ölçeği ---
const B_XS := 8
const B_S := 12
const B_M := 16
const B_L := 24
const B_XL := 32

# --- Köşe yarıçapları (kodla çizilen kutular için) ---
const R_KUCUK := 8
const R_ORTA := 14
const R_BUYUK := 22

# --- Boyutlar ---
const DOKUNMA := 64        # en küçük dokunma alanı (px)
const BTN_H := 76          # standart düğme yüksekliği
const BTN_H_KUCUK := 64    # sıkışık yerler (asla bunun altına inme)
const BTN_H_BUYUK := 92    # ekranın tek büyük eylemi (OYNA)
const IKON_KUCUK := 24     # yazı içi
const IKON_ORTA := 40      # düğme / sekme içi
const IKON_BUYUK := 64     # menü kutucuğu
const IKON_DEV := 120      # boş durum, ödül
const UST_BAR_H := 72

# --- Eski adlar (başka ekranlar kullanıyor; silme) ---
const ORANGE := Color("#ff7a1a")
const TEAL := Color("#5ff0ff")
const CREAM := Color("#f3e6d0")
const MUTED := Color(0.72, 0.74, 0.8)

const DIR := "res://assets/ui/"
const KIT := "kit/"
const TIK_SES := "res://assets/ses/tik_ui.ogg"

# Düğme türleri. Eski türler yenilere eşlenir.
const TUR_ESLE := {"primary": "ana", "orange": "ana", "normal": "ikincil", "red": "tehlike", "green": "yesil",
	"ana": "ana", "ikincil": "ikincil", "tehlike": "tehlike", "yesil": "yesil"}
# tür -> [yedek zemin, yedek kenar, yazı dış çizgisi]
const TUR_RENK := {
	"ana": ["#e09a10", "#ffd36b", "#5a3300"],
	"ikincil": ["#2c3231", "#59625f", "#07090a"],
	"tehlike": ["#b82218", "#ff7a6b", "#4a0806"],
	"yesil": ["#2f9a26", "#8ff07a", "#0f3a08"],
}

# 9 parçalı kesim ölçüleri: ad -> (sol, üst, sağ, alt); sol/sağ genişliğin, üst/alt yüksekliğin oranı
const KESIM := {
	"panel": Vector4(0.11, 0.11, 0.11, 0.11),
	"panel_baslik": Vector4(0.09, 0.3, 0.09, 0.3),
	"ust_bar": Vector4(0.085, 0.26, 0.085, 0.34),
	"btn": Vector4(0.08, 0.28, 0.08, 0.28),
	"sekme": Vector4(0.27, 0.42, 0.27, 0.14),
	"cubuk_bos": Vector4(0.06, 0.3, 0.06, 0.3),
	"cubuk_dolu": Vector4(0.055, 0.3, 0.055, 0.3),
	"rozet": Vector4(0.48, 0.48, 0.48, 0.48),
	"kart": Vector4(0.1, 0.07, 0.1, 0.07),
	"kart_nadirlik": Vector4(0.14, 0.095, 0.14, 0.095),
}

# İkon adları: eski İngilizce ad -> kit ikonu (assets/ui/kit/ikon_<ad>.png)
const IKON_KIT := {"play": "oyna", "store": "magaza", "friends": "arkadas", "settings": "ayarlar", "gem": "elmas",
	"lock": "kilit", "phone": "telefon", "crown": "tac", "invite": "davet", "sound": "ses", "mic": "mikrofon",
	"chest": "kasa", "inventory": "envanter", "back": "geri", "close": "kapat", "quest": "gorev",
	"leaderboard": "liderlik", "achievement": "basarim", "xp": "xp"}
# Türkçe ad -> eski ikon (kit ikonu yoksa yedek)
const IKON_ESKI := {"oyna": "play", "magaza": "store", "arkadas": "friends", "ayarlar": "settings", "elmas": "gem",
	"kilit": "lock", "telefon": "phone", "tac": "crown", "davet": "invite", "ses": "sound", "mikrofon": "mic",
	"kasa": "chest", "basarim": "trophy", "liderlik": "trophy"}
# Kit ikonlarının tamamı (tasarım panosu ve rehber için)
const KIT_IKONLAR := ["oyna", "magaza", "envanter", "arkadas", "ayarlar", "gorev", "liderlik", "basarim", "elmas", "xp",
	"kilit", "telefon", "kapat", "geri", "tac", "davet", "ses", "mikrofon", "kasa"]

static var _tex := {}
static var _tik: AudioStreamPlayer
static var ses_acik := true   # tüm düğme tıklama sesleri (ayarlardan kapatılabilir)


# =====================================================================
# DOKULAR
# =====================================================================

# İçe aktarılmış ya da klasöre yeni atılmış (henüz içe aktarılmamış) görsel var mı?
static func has(name: String) -> bool:
	return ResourceLoader.exists(DIR + name + ".png") or FileAccess.file_exists(DIR + name + ".png")


# Görseli yükler, şeffaf kenarlarını kırpar, isteğe göre yüksekliği h piksele ölçekler.
static func texture(name: String, h := 0) -> Texture2D:
	var key := "%s@%d" % [name, h]
	if _tex.has(key):
		return _tex[key]
	if not has(name):
		return null
	var img: Image
	if ResourceLoader.exists(DIR + name + ".png"):
		img = (load(DIR + name + ".png") as Texture2D).get_image()
	else:
		img = Image.load_from_file(ProjectSettings.globalize_path(DIR + name + ".png"))
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var used := img.get_used_rect()
	if used.size.x > 4 and used.size.y > 4:
		img = img.get_region(used)
	if h > 0 and img.get_height() != h:
		img.resize(maxi(1, int(img.get_width() * float(h) / img.get_height())), h, Image.INTERPOLATE_LANCZOS)
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


# Gri (devre dışı) kopya: renk doygunluğu alınır, biraz karartılır.
static func _gri(name: String, h: int) -> Texture2D:
	var key := "%s@%d#gri" % [name, h]
	if _tex.has(key):
		return _tex[key]
	var t := texture(name, h)
	if t == null:
		return null
	var img := t.get_image()
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := (c.r * 0.3 + c.g * 0.59 + c.b * 0.11) * 0.62
			img.set_pixel(x, y, Color(l, l, l * 1.04, c.a))
	var g := ImageTexture.create_from_image(img)
	_tex[key] = g
	return g


# 9 parçalı kaplama: görsel "nominal_h" yüksekliğe ölçeklenir, kenarların "frac" kadarı esnemez.
static func sbox(name: String, nominal_h: int, frac := 0.3, pad := Vector4(24, 12, 24, 12)) -> StyleBox:
	var t := texture(name, nominal_h)
	if t == null:
		return null
	var st := StyleBoxTexture.new()
	st.texture = t
	var mh := t.get_height() * frac
	var mw := minf(t.get_width() * 0.3, mh * 1.4)
	st.texture_margin_left = mw
	st.texture_margin_right = mw
	st.texture_margin_top = mh
	st.texture_margin_bottom = mh
	st.content_margin_left = pad.x
	st.content_margin_top = pad.y
	st.content_margin_right = pad.z
	st.content_margin_bottom = pad.w
	return st


# Kit parçası için 9 parçalı kaplama. kesim: KESIM tablosundaki gibi (sol/sağ genişlik, üst/alt yükseklik oranı).
# Görsel nominal_h yüksekliğe ölçeklenir: kenar süsleri ekranda bu ölçekte görünür.
static func kit_sbox(name: String, nominal_h: int, kesim: Vector4, pad := Vector4(16, 8, 16, 8), gri := false) -> StyleBoxTexture:
	var t := _gri(name, nominal_h) if gri else texture(name, nominal_h)
	if t == null:
		return null
	var st := StyleBoxTexture.new()
	st.texture = t
	var w := float(t.get_width())
	var hh := float(t.get_height())
	st.texture_margin_left = roundf(w * kesim.x)
	st.texture_margin_top = roundf(hh * kesim.y)
	st.texture_margin_right = roundf(w * kesim.z)
	st.texture_margin_bottom = roundf(hh * kesim.w)
	st.content_margin_left = pad.x
	st.content_margin_top = pad.y
	st.content_margin_right = pad.z
	st.content_margin_bottom = pad.w
	return st


static func flat(bg: Color, border: Color, radius := 16, glow := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(2)
	st.border_width_top = 3
	st.set_corner_radius_all(radius)
	st.shadow_color = glow if glow.a > 0.0 else Color(0, 0, 0, 0.45)
	st.shadow_size = 16 if glow.a > 0.0 else 6
	st.content_margin_left = 20
	st.content_margin_right = 20
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	return st


# =====================================================================
# YAZI
# =====================================================================

static func label(text: String, size := 22, color := CREAM, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# Yazı max_w genişliğine sığmazsa yazı boyutu küçülür (İngilizce metinler Türkçeden uzun olabilir); en çok
# ilk boyutun %65'ine kadar. Sabit genişlikli düğme ve kutucuklarda kullanılır. Yazı değişince
# set_button_text, dil değişince sigdir_hepsi yeniden sığdırır.
static func sigdir(l: Label, max_w: float) -> void:
	if not l.has_meta("fs0"):
		l.set_meta("fs0", l.get_theme_font_size("font_size"))
	l.set_meta("max_w", max_w)
	var fs0: int = l.get_meta("fs0")
	var f := l.get_theme_font("font")
	var t := TranslationServer.translate(l.text)
	var w := max_w - l.get_theme_constant("outline_size")
	var fs := fs0
	while fs > maxi(11, int(fs0 * 0.65)) and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)


# Dil değişince ağaçtaki tüm sığdırılmış yazılar yeni dile göre yeniden sığdırılır.
static func sigdir_hepsi(n: Node) -> void:
	if n is Label and n.has_meta("max_w"):
		sigdir(n, float(n.get_meta("max_w")))
	for c in n.get_children():
		sigdir_hepsi(c)


# Başlık yazısı: kalın askeri yazı tipi (RussoOne), koyu dış çizgi ve alta düşen gölge.
static func title(text: String, size := 34, color := CREAM, center := false) -> Label:
	var l := label(text, size, color, center)
	l.add_theme_font_override("font", TITLE_FONT)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.03, 0.92))
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 12))
	return l


# =====================================================================
# İKONLAR
# =====================================================================

const ICON_COLORS := {"play": "#5ff0ff", "store": "#ff7a1a", "friends": "#ffcf8a", "settings": "#c9cfd8", "exit": "#ff6b57"}


# İkon görselini bulur: önce kit (kit/ikon_<türkçe ad>), sonra eski icon_<ad>. Yoksa null.
static func icon_texture(name: String, px := 64) -> Texture2D:
	var kn: String = IKON_KIT.get(name, name)
	if has(KIT + "ikon_" + kn):
		return texture(KIT + "ikon_" + kn, int(px * 2))
	var en: String = IKON_ESKI.get(name, name)
	if has("icon_" + en):
		return texture("icon_" + en, int(px * 2))
	return null


# İkon: ad Türkçe (oyna, magaza, kapat...) ya da eski İngilizce (play, store...) olabilir.
static func icon(name: String, px: float) -> Control:
	var t := icon_texture(name, int(px))
	if t:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(px, px)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var d := DrawnIcon.new()
	d.kind = IKON_ESKI.get(name, name)
	d.color = Color(ICON_COLORS.get(d.kind, "#ffcf8a"))
	d.custom_minimum_size = Vector2(px, px)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


static func gem(px: float) -> Control:
	if has(KIT + "ikon_elmas"):
		return icon("elmas", px)
	var t := texture("gem", int(px * 2))
	if t:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(px, px)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var d := DrawnIcon.new()
	d.kind = "gem"
	d.custom_minimum_size = Vector2(px, px)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


# =====================================================================
# SES
# =====================================================================

# Arayüz tıklama sesi (tik_ui.ogg). Tek oynatıcı, kök düğüme bir kez eklenir.
static func tik(vol_db := -7.0) -> void:
	if not ses_acik:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if not is_instance_valid(_tik):
		_tik = AudioStreamPlayer.new()
		_tik.stream = load(TIK_SES)
		_tik.max_polyphony = 3
		_tik.volume_db = vol_db
		_tik.ready.connect(_tik.play, CONNECT_ONE_SHOT)
		tree.root.add_child.call_deferred(_tik)
		return
	if not _tik.is_inside_tree():
		return
	_tik.volume_db = vol_db
	_tik.pitch_scale = randf_range(0.96, 1.05)
	_tik.play()


# =====================================================================
# DÜĞMELER
# =====================================================================

static func _tur(kind: String) -> String:
	return TUR_ESLE.get(kind, "ikincil")


# Düğmeye tür kaplamalarını (normal / basılı / devre dışı) giydirir. Seçim değişince yeniden çağrılabilir
# (ör. ayarlarda seçili seçenek "ana", diğeri "ikincil").
static func set_button_kind(b: Button, kind: String) -> void:
	var k := _tur(kind)
	var h := int(maxf(b.custom_minimum_size.y, 40.0))
	var pad := Vector4(18, 4, 18, 4)
	var st := kit_sbox(KIT + "btn_" + k, h, KESIM.btn, pad)
	var c: Array = TUR_RENK[k]
	if st == null:
		var f := flat(Color(c[0]), Color(c[1]), R_ORTA)
		b.add_theme_stylebox_override("normal", f)
		b.add_theme_stylebox_override("hover", f)
		b.add_theme_stylebox_override("focus", f)
		var fb := flat(Color(c[0]).darkened(0.25), Color(c[1]).darkened(0.2), R_ORTA)
		fb.shadow_size = 0
		b.add_theme_stylebox_override("pressed", fb)
		b.add_theme_stylebox_override("disabled", flat(Color("#2a2c2e"), Color("#45494b"), R_ORTA))
	else:
		var bas := kit_sbox(KIT + "btn_" + k + "_basili", h, KESIM.btn, pad)
		var kapali := kit_sbox(KIT + "btn_ikincil", h, KESIM.btn, pad, true)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("focus", st)
		b.add_theme_stylebox_override("pressed", bas if bas else st)
		b.add_theme_stylebox_override("disabled", kapali if kapali else st)
	b.set_meta("kind", k)
	if b.has_meta("label"):
		var l: Label = b.get_meta("label")
		l.add_theme_color_override("font_outline_color", Color(c[2]))


# Büyük oyun düğmesi: kaplama türü ana / ikincil / tehlike / yesil (eski primary/orange/normal/red de olur),
# solda ikon, ortada başlık yazısı. Basınca küçülür, içe göçer, tık sesi çıkar; devre dışıyken gri.
# Sesi kapatmak için: b.set_meta("sessiz", true)
static func button(text: String, kind := "normal", h := 72, font := 28, icon_name := "", w := 0.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = maxf(16.0, h * 0.4)  # perçinli kenarın içinde kal
	row.offset_right = -maxf(16.0, h * 0.4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", B_S)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic_px := h * 0.58
	if icon_name != "":
		var ic := icon(icon_name, ic_px)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := title(text, font, Color.WHITE, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if icon_name != "" else Control.SIZE_FILL
	row.add_child(l)
	if icon_name != "" and text != "":
		var pad := Control.new()
		pad.custom_minimum_size.x = ic_px * 0.3
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pad)
	if text == "":
		l.visible = false
	elif w > 0.0:
		# genişliği sabit düğme: uzun (ör. İngilizce) yazı küçülerek sığar
		sigdir(l, w - 28.0 - ((ic_px * 1.3 + B_S * 2.0) if icon_name != "" else 0.0))
	b.add_child(row)
	b.set_meta("label", l)
	b.set_meta("row", row)
	set_button_kind(b, kind)
	_basma_hissi(b, row)
	return b


# Basınca küçülme + içerik aşağı kayma + ses; devre dışıyken içerik soluk.
static func _basma_hissi(b: BaseButton, row: Control) -> void:
	var cek := maxf(2.0, b.custom_minimum_size.y * 0.04)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.94, 0.05)
		if row:
			row.offset_top = cek
			row.offset_bottom = cek
		if not b.get_meta("sessiz", false):
			tik())
	b.button_up.connect(func() -> void:
		b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(b, "scale", Vector2.ONE, 0.14)
		if row:
			row.offset_top = 0
			row.offset_bottom = 0)
	if row:
		b.draw.connect(func() -> void:
			row.modulate = Color(0.8, 0.8, 0.8, 0.55) if b.disabled else Color.WHITE)


static func set_button_text(b: Button, text: String) -> void:
	var l := b.get_meta("label") as Label
	l.text = text
	if l.has_meta("max_w"):
		sigdir(l, float(l.get_meta("max_w")))


# Kare ikon düğmesi (kapat, geri, ayarlar...). px en az DOKUNMA olmalı.
static func icon_button(icon_name: String, kind := "ikincil", px := 64) -> Button:
	var b := button("", kind, px, FS_ORTA, "", px)
	var row: HBoxContainer = b.get_meta("row")
	row.offset_left = 0
	row.offset_right = 0
	for c in row.get_children():
		row.remove_child(c)
		c.free()
	var ic := icon(icon_name, px * 0.52)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	b.set_meta("label", Label.new())
	return b


# =====================================================================
# PANELLER, BAŞLIK, SEKME, ÜST ÇUBUK
# =====================================================================

# Çelik panel (kit/panel) — içerik kenardan "pad" kadar içeride başlar.
static func panel(min_size := Vector2.ZERO, pad := 30) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	var st: StyleBox = kit_sbox(KIT + "panel", 300, KESIM.panel, Vector4(pad, pad, pad, pad))
	if st == null:
		st = sbox("panel", 300, 0.16, Vector4(pad, pad - 4, pad, pad))
	if st == null:
		st = flat(Color(YUZEY, 0.95), CIZGI, R_BUYUK)
	p.add_theme_stylebox_override("panel", st)
	return p


# Uyarı şeritli başlık plakası (kit/panel_baslik) ve üstünde başlık yazısı.
static func header(text: String, font := 30) -> Control:
	var p := PanelContainer.new()
	var hh := maxi(56, int(font * 2.0))
	var st: StyleBox = kit_sbox(KIT + "panel_baslik", hh, KESIM.panel_baslik, Vector4(hh * 0.9, 2, hh * 0.9, 4))
	if st == null:
		st = sbox("panel_header", 74, 0.3, Vector4(40, 8, 40, 10))
	if st == null:
		st = flat(Color("#262a33"), AMBER, 12)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size.y = hh
	var t := title(text, font, METIN, true)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(t)
	p.set_meta("label", t)
	return p


# Kategori sekmesi (kit/sekme, kit/sekme_secili).
static func tab(text: String, on: bool, icon_name := "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, DOKUNMA)
	var st: StyleBox = kit_sbox(KIT + ("sekme_secili" if on else "sekme"), DOKUNMA, KESIM.sekme, Vector4(B_M, 6, B_M, 2))
	if st == null:
		st = sbox("tab_on" if on else "tab_off", 64, 0.3, Vector4(16, 4, 16, 4))
	if st == null:
		st = flat(AMBER if on else Color("#262a2a"), Color("#ffd36b") if on else CIZGI, R_ORTA)
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 6
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		row.add_child(icon(icon_name, 34))
	var l := title(text, 19, Color.WHITE if on else METIN_SOLUK)
	if on:
		l.add_theme_color_override("font_outline_color", Color("#5a3300"))
	row.add_child(l)
	b.add_child(row)
	b.set_meta("label", l)
	b.custom_minimum_size.x = 72 + text.length() * 12 + (40 if icon_name != "" else 0)
	_basma_hissi(b, null)
	return b


# Ekranın üst şeridi (kit/ust_bar). İçine öğe eklemek için: UI.top_bar().get_meta("row") (HBoxContainer).
# Üst kenara yaslanmış gelir; tam ekran bir kabın içine doğrudan eklenebilir.
static func top_bar(h := UST_BAR_H) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_TOP_WIDE)
	p.offset_bottom = h
	p.custom_minimum_size.y = h
	var st: StyleBox = kit_sbox(KIT + "ust_bar", h, KESIM.ust_bar, Vector4(h * 0.95, 4, h * 0.95, 10))
	if st == null:
		st = flat(Color(YUZEY, 0.95), AMBER_KOYU, 0)
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", B_M)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	p.add_child(row)
	p.set_meta("row", row)
	return p


# Para / sayaç hapı: ikon + sayı (üst çubukta elmas, XP vb.). Yazıyı değiştirmek: get_meta("label").text
static func counter(icon_name: String, text: String, px := 40) -> PanelContainer:
	var p := PanelContainer.new()
	var st := flat(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.1), R_BUYUK)
	st.shadow_size = 0
	st.content_margin_left = 4
	st.content_margin_right = B_M
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(icon(icon_name, px))
	var l := title(text, FS_ORTA, METIN)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	p.add_child(row)
	p.set_meta("label", l)
	return p


# =====================================================================
# KART, İLERLEME, ROZET
# =====================================================================

const NADIRLIK_ESLE := {"siradan": "siradan", "SIRADAN": "siradan", "common": "siradan",
	"nadir": "nadir", "NADİR": "nadir", "NADIR": "nadir", "rare": "nadir",
	"epik": "epik", "EPİK": "epik", "EPIK": "epik", "epic": "epik",
	"efsane": "efsane", "EFSANE": "efsane", "legend": "efsane", "legendary": "efsane"}


# Nadirlik adını (Türkçe/İngilizce, büyük/küçük) siradan/nadir/epik/efsane'ye çevirir; bilinmiyorsa "".
static func rarity_key(rarity: String) -> String:
	return NADIRLIK_ESLE.get(rarity, "")


static func rarity_color(rarity: String) -> Color:
	return NADIRLIK.get(rarity_key(rarity), METIN_SOLUK)


# Eşya kartı çerçevesi. rarity: "" (nötr) / siradan / nadir / epik / efsane (İngilizce ve büyük harf adlar da olur).
# İçine eşya resmi/yazısı eklenir (PanelContainer; içerik çerçevenin içinde kalır).
static func card_frame(rarity := "", min_size := Vector2(150, 206)) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	var r := rarity_key(rarity)
	var nom := int(maxf(min_size.y, 160.0))
	var st: StyleBox = null
	if r != "":
		st = kit_sbox("uretim/kart_" + r, nom, KESIM.kart_nadirlik, Vector4(nom * 0.1, nom * 0.075, nom * 0.1, nom * 0.075))
	if st == null:
		st = kit_sbox(KIT + "kart", nom, KESIM.kart, Vector4(nom * 0.075, nom * 0.06, nom * 0.075, nom * 0.06))
	if st == null:
		var c: Color = NADIRLIK.get(r, CIZGI)
		st = flat(YUZEY_2, c, R_ORTA, Color(c, 0.35) if r != "" else Color(0, 0, 0, 0))
	p.add_theme_stylebox_override("panel", st)
	p.set_meta("rarity", r)
	return p


# İlerleme çubuğu (kit/cubuk_bos + cubuk_dolu). value 0..1.
# Değiştirmek: bar.value = 0.5  ·  animasyonlu: bar.animate_to(0.8)  ·  ortada yazı: bar.text = "35/100"
static func progress(value := 0.0, w := 320.0, h := 34, text := "") -> Cubuk:
	var c := Cubuk.new()
	c.custom_minimum_size = Vector2(w, h)
	c.kur(h)
	c.value = value
	c.text = text
	return c


# Küçük sayı rozeti (kırmızı). n <= 0 ise gizlenir, 99'dan büyükse "99+". Güncellemek: UI.set_badge(rozet, n)
static func badge(n: int, px := 30) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(px, px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st: StyleBox = kit_sbox(KIT + "rozet", px, KESIM.rozet, Vector4(px * 0.24, 0, px * 0.24, 0))
	if st == null:
		st = flat(KIRMIZI, Color("#ffd0c8"), px / 2)
		st.shadow_size = 2
		st.content_margin_top = 0
		st.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", st)
	var l := title("", int(px * 0.58), Color.WHITE, true)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", maxi(3, px / 8))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_color_override("font_outline_color", Color("#4a0806"))
	p.add_child(l)
	p.set_meta("label", l)
	set_badge(p, n)
	return p


static func set_badge(b: Control, n: int) -> void:
	(b.get_meta("label") as Label).text = "99+" if n > 99 else str(n)
	b.visible = n > 0


# Bir öğenin sağ üst köşesine rozet iliştirir (ikon, düğme, sekme...). Rozeti döndürür.
static func badge_on(target: Control, n: int, px := 28) -> PanelContainer:
	var b := badge(n, px)
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	b.offset_left = -px * 0.75
	b.offset_right = px * 0.25
	b.offset_top = -px * 0.25
	b.offset_bottom = px * 0.75
	b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	target.add_child(b)
	return b


# =====================================================================
# MODAL VE BİLDİRİM
# =====================================================================

# Modal pencere: koyu perde + çelik panel + uyarı şeritli başlık + kapat düğmesi.
#   var m := UI.modal("SATIN AL")  ;  m.body.add_child(...)  ;  ekran.add_child(m)
# Açılırken büyüyerek belirir; m.close() ile (ya da kapat düğmesi / perdeye dokunma) ters animasyonla kapanır,
# "closed" sinyali gelir ve kendini siler. Perdeye dokununca kapanmasın: m.perde_kapatir = false
static func modal(title_text: String, w := 640.0) -> Modal:
	var m := Modal.new()
	m.kur(title_text, w)
	return m


# Kısa bildirim: ekranın üst ortasında belirir, kendiliğinden kaybolur. kind: bilgi / basari / hata
# parent verilmezse en üstte yeni bir katmana eklenir (her ekrandan çağrılabilir). y: parent üstünden uzaklık.
static func toast(text: String, parent: Node = null, sure := 2.2, kind := "bilgi", y := 92.0) -> Control:
	var renk: Color = {"bilgi": AMBER, "basari": YESIL, "hata": KIRMIZI}.get(kind, AMBER)
	var host: Node = parent
	var layer: CanvasLayer = null
	if host == null:
		var tree := Engine.get_main_loop() as SceneTree
		layer = CanvasLayer.new()
		layer.layer = 120
		tree.root.add_child(layer)
		host = layer
	var kok := Control.new()
	kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(kok)
	var p := PanelContainer.new()
	var st := flat(Color(0.05, 0.06, 0.06, 0.95), Color(renk, 0.9), R_BUYUK, Color(renk, 0.22))
	st.set_border_width_all(2)
	st.border_width_left = 8
	st.content_margin_left = B_L
	st.content_margin_right = B_L
	st.content_margin_top = B_S
	st.content_margin_bottom = B_S
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var l := label(text, FS_METIN, METIN, true)
	l.add_theme_font_override("font", TITLE_FONT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	p.add_child(l)
	kok.add_child(p)
	var y0 := y
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(p, "offset_top", y0, 0.28).from(y0 - 28.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(sure)
	tw.tween_property(p, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		if layer:
			layer.queue_free()
		else:
			kok.queue_free())
	return kok


# =====================================================================
# DİĞER
# =====================================================================

# Tam ekran arka plan resmi (bg_*.png); yoksa koyu renk.
static func background(name: String, dim := 0.35) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := texture(name)
	if t:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(r)
	else:
		var c := ColorRect.new()
		c.color = ZEMIN
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(c)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.02, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	return root


# Telefonda listeyi parmakla aşağı/yukarı çekerek kaydırma (çubuğu tutmaya gerek yok).
# İçine eklenen her düğme sürüklemeyi kaydırmaya bırakır; kısa dokunuş yine tıklama sayılır.
static func touch_scroll(sc: ScrollContainer) -> void:
	sc.scroll_deadzone = 14
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var hook := func(n: Node) -> void:
		if n is Control and sc.is_ancestor_of(n) and (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			(n as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	sc.tree_entered.connect(func() -> void:
		sc.get_tree().node_added.connect(hook)
		for n in sc.find_children("*", "Control", true, false):
			hook.call(n))
	sc.tree_exiting.connect(func() -> void:
		if sc.get_tree().node_added.is_connected(hook):
			sc.get_tree().node_added.disconnect(hook))


# Yazı kutusu: koyu iç, ince çelik çerçeve, odakta amber.
static func style_edit(e: LineEdit, size := 22) -> void:
	var st := flat(Color(0.03, 0.035, 0.035, 0.95), Color("#59625f"), R_KUCUK + 2)
	st.set_border_width_all(2)
	st.content_margin_left = B_M
	st.shadow_size = 0
	var foc := st.duplicate()
	foc.border_color = AMBER
	e.add_theme_stylebox_override("normal", st)
	e.add_theme_stylebox_override("focus", foc)
	e.add_theme_font_size_override("font_size", size)
	e.add_theme_color_override("font_placeholder_color", Color(METIN_SOLUK, 0.8))
	e.add_theme_color_override("caret_color", AMBER)
	e.custom_minimum_size.y = maxf(e.custom_minimum_size.y, 54)


static func place(c: Control, preset: int, ofs: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = ofs.x
	c.offset_top = ofs.y
	c.offset_right = ofs.x + sz.x
	c.offset_bottom = ofs.y + sz.y


# =====================================================================
# TASARIM PANOSU (main.gd: pose=kit) — takımın bütün parçaları tek ekranda
# =====================================================================

static func kit_board() -> Control:
	var kok := Control.new()
	kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	kok.add_child(background("uretim/acilis", 0.82))
	# üst çubuk
	var bar := top_bar()
	kok.add_child(bar)
	var br: HBoxContainer = bar.get_meta("row")
	var bt := title("TASARIM TAKIMI", FS_ORTA, METIN)
	bt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(bt)
	br.add_child(counter("xp", "SEVİYE 12", 40))
	br.add_child(counter("elmas", "10.025", 40))
	var ayar := icon_button("ayarlar", "ikincil", 56)
	ayar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(ayar)
	badge_on(ayar, 3, 26)
	# iki sütun
	var cols := HBoxContainer.new()
	place(cols, Control.PRESET_TOP_LEFT, Vector2(20, 82), Vector2(1240, 630))
	cols.add_theme_constant_override("separation", B_L)
	kok.add_child(cols)
	var sol := VBoxContainer.new()
	sol.custom_minimum_size.x = 590
	sol.add_theme_constant_override("separation", 6)
	cols.add_child(sol)
	var sag := VBoxContainer.new()
	sag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sag.add_theme_constant_override("separation", 6)
	cols.add_child(sag)
	var bolum := func(v: VBoxContainer, t: String) -> void:
		var l := label(t, FS_KUCUK, AMBER)
		l.add_theme_font_override("font", TITLE_FONT)
		v.add_child(l)
	# düğmeler: tür x durum
	bolum.call(sol, "DÜĞMELER  ·  normal / basılı / devre dışı")
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", B_S)
	g.add_theme_constant_override("v_separation", B_XS)
	sol.add_child(g)
	for k in [["ana", "OYNA", "oyna"], ["ikincil", "GERİ", "geri"], ["tehlike", "SİL", "kapat"], ["yesil", "ONAY", "elmas"]]:
		for durum in 3:
			var b := button(k[1], k[0], DOKUNMA, FS_ORTA, k[2] if durum == 0 else "", 188)
			if durum == 1:
				for s in ["normal", "hover"]:
					b.add_theme_stylebox_override(s, b.get_theme_stylebox("pressed"))
				var r: Control = b.get_meta("row")
				r.offset_top = 3
				r.offset_bottom = 3
			elif durum == 2:
				b.disabled = true
			g.add_child(b)
	# sekmeler
	bolum.call(sol, "SEKMELER")
	var ts := HBoxContainer.new()
	ts.add_theme_constant_override("separation", 4)
	sol.add_child(ts)
	ts.add_child(tab("SAÇ", true, "envanter"))
	ts.add_child(tab("ŞAPKA", false))
	var t3 := tab("KIYAFET", false)
	ts.add_child(t3)
	badge_on(t3, 2, 24)
	ts.add_child(tab("DÖVME", false))
	# ilerleme + rozet
	bolum.call(sol, "İLERLEME  ·  ROZET")
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", B_M)
	sol.add_child(pr)
	pr.add_child(progress(0.35, 220, 32, "35/100"))
	pr.add_child(progress(0.85, 160, 32))
	for n in [1, 12, 150]:
		var ic := icon("magaza" if n == 1 else ("arkadas" if n == 12 else "gorev"), 48)
		pr.add_child(ic)
		badge_on(ic, n, 24)
	# yazı ölçeği
	bolum.call(sol, "YAZI ÖLÇEĞİ  ·  RussoOne başlık / Rubik metin")
	var ty := HBoxContainer.new()
	ty.add_theme_constant_override("separation", B_M)
	sol.add_child(ty)
	ty.add_child(title("Başlık 44", FS_DEV, METIN))
	ty.add_child(title("32", FS_BUYUK, AMBER))
	ty.add_child(title("24 ÇĞİÖŞÜ", FS_ORTA, METIN))
	var tx := HBoxContainer.new()
	tx.add_theme_constant_override("separation", B_M)
	sol.add_child(tx)
	tx.add_child(label("Metin 20 · Türkçe: ığüşöç İĞÜŞÖÇ", FS_METIN, METIN))
	tx.add_child(label("Dipnot 16", FS_KUCUK, METIN_SOLUK))
	# sağ: kartlar
	bolum.call(sag, "KARTLAR  ·  nötr / sıradan / nadir / epik / efsane")
	var ks := HBoxContainer.new()
	ks.add_theme_constant_override("separation", B_S)
	sag.add_child(ks)
	for r in ["", "siradan", "nadir", "epik", "efsane"]:
		var c := card_frame(r, Vector2(110, 150))
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		c.add_child(v)
		var ic := icon(["kasa", "kilit", "envanter", "tac", "elmas"][["", "siradan", "nadir", "epik", "efsane"].find(r)], 56)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var nm := title({"": "KİLİTLİ", "siradan": "SIRADAN", "nadir": "NADİR", "epik": "EPİK", "efsane": "EFSANE"}[r], 13, rarity_color(r) if r != "" else METIN_SOLUK, true)
		v.add_child(nm)
		ks.add_child(c)
	# ikonlar
	bolum.call(sag, "İKONLAR  ·  kit/ikon_*  (48 px)")
	var ig := GridContainer.new()
	ig.columns = 10
	ig.add_theme_constant_override("h_separation", 12)
	ig.add_theme_constant_override("v_separation", 4)
	sag.add_child(ig)
	for n in KIT_IKONLAR:
		ig.add_child(icon(n, 48))
	# modal örneği (sağ alt bölgede canlı)
	bolum.call(sag, "MODAL  ·  perde + panel + başlık şeridi + kapat")
	var alan := Control.new()
	alan.custom_minimum_size = Vector2(0, 236)
	alan.clip_contents = true
	sag.add_child(alan)
	var m := modal("SATIN AL", 420)
	m.perde_kapatir = false
	var sat := HBoxContainer.new()
	sat.add_theme_constant_override("separation", B_S)
	sat.alignment = BoxContainer.ALIGNMENT_CENTER
	sat.add_child(button("VAZGEÇ", "ikincil", DOKUNMA, FS_ORTA, "", 150))
	sat.add_child(button("250", "yesil", DOKUNMA, FS_ORTA, "elmas", 150))
	m.body.add_child(label("Efsane kasayı açmak istiyor musun?", FS_METIN, METIN, true))
	m.body.add_child(sat)
	alan.add_child(m)
	# bildirim
	var tost_alan := Control.new()
	place(tost_alan, Control.PRESET_TOP_LEFT, Vector2(640, 0), Vector2(620, 720))
	tost_alan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kok.add_child(tost_alan)
	toast("Kasa açıldı: EFSANE şapka!", tost_alan, 30.0, "basari", 664.0)
	return kok


# =====================================================================
# İÇ SINIFLAR
# =====================================================================

# İlerleme çubuğu: iz (boş kanal) + içinde dolgu.
class Cubuk extends Control:
	# iç sınıftan dış betiğin statik fonksiyonları doğrudan çağrılamıyor; betik yüklenip onun üstünden çağrılır
	var U: GDScript = load("res://scripts/ui.gd")
	var value := 0.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			_yerlestir()
	var text := "":
		set(v):
			text = v
			if _yazi:
				_yazi.text = v
				_yazi.visible = v != ""
	var _dolgu: Panel
	var _yazi: Label
	var _ic := Vector2.ZERO  # dolgunun kenardan içeri payı

	func kur(h: int) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var iz := Panel.new()
		iz.set_anchors_preset(Control.PRESET_FULL_RECT)
		iz.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ist: StyleBox = U.kit_sbox(KIT + "cubuk_bos", h, KESIM.cubuk_bos, Vector4.ZERO)
		if ist == null:
			var f: StyleBoxFlat = U.flat(Color(0.02, 0.02, 0.02, 0.9), CIZGI, h / 2)
			f.shadow_size = 0
			ist = f
		iz.add_theme_stylebox_override("panel", ist)
		add_child(iz)
		_ic = Vector2(roundf(h * 0.32), roundf(h * 0.28))
		var fh := maxi(4, int(h - _ic.y * 2))
		_dolgu = Panel.new()
		_dolgu.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fst: StyleBox = U.kit_sbox(KIT + "cubuk_dolu", fh, KESIM.cubuk_dolu, Vector4.ZERO)
		if fst == null:
			var f2: StyleBoxFlat = U.flat(AMBER, AMBER.lightened(0.3), fh / 2)
			f2.shadow_size = 0
			fst = f2
		_dolgu.add_theme_stylebox_override("panel", fst)
		add_child(_dolgu)
		_yazi = U.title(text, maxi(12, int(h * 0.5)), Color.WHITE, true)
		_yazi.set_anchors_preset(Control.PRESET_FULL_RECT)
		_yazi.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_yazi.visible = text != ""
		add_child(_yazi)
		resized.connect(_yerlestir)

	func _yerlestir() -> void:
		if _dolgu == null:
			return
		var ici := size.x - _ic.x * 2.0
		var minw := size.y - _ic.y * 2.0  # yuvarlak uçlar için en az bir yükseklik kadar
		_dolgu.visible = value > 0.001 and ici > 0.0
		_dolgu.position = Vector2(_ic.x, _ic.y)
		_dolgu.size = Vector2(maxf(minw, ici * value), size.y - _ic.y * 2.0)

	func animate_to(v: float, sure := 0.45) -> void:
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(self, "value", v, sure)


# Modal pencere.
class Modal extends Control:
	var U: GDScript = load("res://scripts/ui.gd")
	signal closed
	var body: VBoxContainer       # içeriği buraya ekle
	var box: PanelContainer       # panel
	var title_label: Label
	var close_button: Button
	var perde_kapatir := true
	var _perde: ColorRect
	var _kapaniyor := false

	func kur(baslik: String, w: float) -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_perde = ColorRect.new()
		_perde.color = PERDE
		_perde.set_anchors_preset(Control.PRESET_FULL_RECT)
		_perde.gui_input.connect(func(e: InputEvent) -> void:
			if perde_kapatir and e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
				close())
		add_child(_perde)
		var cc := CenterContainer.new()
		cc.set_anchors_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cc)
		box = U.panel(Vector2(w, 0), B_L)
		cc.add_child(box)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", B_M)
		box.add_child(v)
		var ust := HBoxContainer.new()
		ust.add_theme_constant_override("separation", B_S)
		v.add_child(ust)
		var h: Control = U.header(baslik, FS_ORTA + 2)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_label = h.get_meta("label")
		ust.add_child(h)
		close_button = U.icon_button("kapat", "ikincil", DOKUNMA)
		close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		close_button.pressed.connect(close)
		ust.add_child(close_button)
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", B_M)
		v.add_child(body)
		box.resized.connect(func() -> void: box.pivot_offset = box.size / 2.0)

	func _ready() -> void:
		_perde.modulate.a = 0.0
		box.modulate.a = 0.0
		box.scale = Vector2.ONE * 0.86
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_perde, "modulate:a", 1.0, 0.18)
		tw.tween_property(box, "modulate:a", 1.0, 0.16)
		tw.tween_property(box, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func close() -> void:
		if _kapaniyor:
			return
		_kapaniyor = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_perde, "modulate:a", 0.0, 0.18)
		tw.tween_property(box, "modulate:a", 0.0, 0.16)
		tw.tween_property(box, "scale", Vector2.ONE * 0.88, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(func() -> void:
			closed.emit()
			queue_free())


# Görsel gelmeden önce kullanılan basit çizim ikonlar.
class DrawnIcon extends Control:
	var kind := ""
	var color := Color.WHITE

	func _draw() -> void:
		var s := size
		var c := s / 2.0
		match kind:
			"play":
				draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.3, s.y * 0.2), Vector2(s.x * 0.8, c.y), Vector2(s.x * 0.3, s.y * 0.8)]), color)
			"gem", "store":
				var p := PackedVector2Array([Vector2(c.x, s.y * 0.1), Vector2(s.x * 0.9, s.y * 0.4), Vector2(c.x, s.y * 0.92), Vector2(s.x * 0.1, s.y * 0.4)])
				draw_colored_polygon(p, Color("#3fd6f0"))
				draw_colored_polygon(PackedVector2Array([p[0], p[1], Vector2(c.x, s.y * 0.4), p[3]]), Color("#a8f2ff"))
			"friends", "profile":
				for k in 2:
					var x := s.x * (0.36 + k * 0.3)
					draw_circle(Vector2(x, s.y * 0.32), s.x * 0.13, color)
					draw_circle(Vector2(x, s.y * 0.82), s.x * 0.22, color)
			"settings", "controls", "graphics", "sound":
				for k in 8:
					var a := k * TAU / 8.0
					draw_line(c + Vector2.from_angle(a) * s.x * 0.22, c + Vector2.from_angle(a) * s.x * 0.44, color, s.x * 0.14)
				draw_circle(c, s.x * 0.3, color)
				draw_circle(c, s.x * 0.13, Color(0.15, 0.16, 0.2))
			"exit":
				draw_rect(Rect2(s.x * 0.45, s.y * 0.12, s.x * 0.42, s.y * 0.76), Color("#b06a2c"))
				draw_line(Vector2(s.x * 0.08, c.y), Vector2(s.x * 0.4, c.y), Color("#5be37d"), s.x * 0.1)
			"kapat", "close":
				draw_line(s * 0.22, s * 0.78, Color("#e0322a"), s.x * 0.16)
				draw_line(Vector2(s.x * 0.78, s.y * 0.22), Vector2(s.x * 0.22, s.y * 0.78), Color("#e0322a"), s.x * 0.16)
			"geri", "back":
				draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.15, c.y), Vector2(s.x * 0.55, s.y * 0.2), Vector2(s.x * 0.55, s.y * 0.8)]), Color("#ffb020"))
				draw_rect(Rect2(s.x * 0.5, s.y * 0.4, s.x * 0.35, s.y * 0.2), Color("#ffb020"))
			_:
				draw_circle(c, s.x * 0.35, color)
