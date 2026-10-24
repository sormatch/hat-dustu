# Oyunun tasarım sistemi: assets/ui/ içindeki görsellerden (yapay zekâ ile üretilmiş) 9 parçalı
# panel/buton/kart kaplamaları, ikonlar, başlık yazıları. Bir görsel yoksa kodla çizilen yedek kullanılır.
extends RefCounted

const DIR := "res://assets/ui/"
const TITLE_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const ORANGE := Color("#ff7a1a")
const TEAL := Color("#5ff0ff")
const CREAM := Color("#f3e6d0")
const MUTED := Color(0.72, 0.74, 0.8)

static var _tex := {}


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


static func label(text: String, size := 22, color := CREAM, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# Başlık yazısı: kalın askeri yazı tipi, koyu dış çizgi ve gölge.
static func title(text: String, size := 34, color := CREAM, center := false) -> Label:
	var l := label(text, size, color, center)
	l.add_theme_font_override("font", TITLE_FONT)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 4)
	return l


const ICON_COLORS := {"play": "#5ff0ff", "store": "#ff7a1a", "friends": "#ffcf8a", "settings": "#c9cfd8", "exit": "#ff6b57"}


# İkon: görseli varsa resim, yoksa basit çizim.
static func icon(name: String, px: float) -> Control:
	var t := texture("icon_" + name, int(px * 2))
	if t:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(px, px)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var d := DrawnIcon.new()
	d.kind = name
	d.color = Color(ICON_COLORS.get(name, "#ffcf8a"))
	d.custom_minimum_size = Vector2(px, px)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


static func gem(px: float) -> Control:
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


# Büyük oyun butonu: kaplama (btn_normal/primary/orange/red), solda ikon, ortada başlık yazısı.
# Basınca hafifçe küçülüp geri büyür.
static func button(text: String, kind := "normal", h := 72, font := 28, icon_name := "", w := 0.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	var st := sbox("btn_" + kind, h + 18, 0.32, Vector4(28, 6, 28, 6))
	if st == null:
		var cols := {"normal": ["#2b2f38", "#7b8494"], "primary": ["#1d3a42", "#5ff0ff"], "orange": ["#b9530f", "#ffb46b"], "red": ["#5a1616", "#d0463a"]}
		var c: Array = cols.get(kind, cols.normal)
		st = flat(Color(c[0]), Color(c[1]), 16, Color(TEAL, 0.4) if kind == "primary" else Color(0, 0, 0, 0))
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.add_theme_stylebox_override("focus", st)
	b.add_theme_stylebox_override("disabled", st)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 26
	row.offset_right = -26
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		var ic := icon(icon_name, h * 0.62)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := title(text, font, Color.WHITE, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if icon_name != "" else Control.SIZE_FILL
	row.add_child(l)
	if icon_name != "":
		var pad := Control.new()
		pad.custom_minimum_size.x = h * 0.62
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pad)
	b.add_child(row)
	b.set_meta("label", l)
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.95, 0.06))
	b.button_up.connect(func() -> void:
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))
	return b


static func set_button_text(b: Button, text: String) -> void:
	(b.get_meta("label") as Label).text = text


# Metal panel (panel.png) — içerik kenardan biraz içeride başlar.
static func panel(min_size := Vector2.ZERO, pad := 30) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	var st := sbox("panel", 300, 0.16, Vector4(pad, pad - 4, pad, pad))
	if st == null:
		st = flat(Color(0.09, 0.1, 0.13, 0.92), Color("#6b7383"))
	p.add_theme_stylebox_override("panel", st)
	return p


# Uyarı şeritli başlık plakası (panel_header.png) ve üstünde başlık yazısı.
static func header(text: String, font := 30) -> Control:
	var p := PanelContainer.new()
	var st := sbox("panel_header", 74, 0.3, Vector4(40, 8, 40, 10))
	if st == null:
		st = flat(Color("#262a33"), ORANGE, 12)
	p.add_theme_stylebox_override("panel", st)
	p.add_child(title(text, font, CREAM, true))
	return p


# Kategori sekmesi (tab_on / tab_off).
static func tab(text: String, on: bool, icon_name := "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 58)
	var st := sbox("tab_on" if on else "tab_off", 64, 0.3, Vector4(16, 4, 16, 4))
	if st == null:
		st = flat(ORANGE if on else Color("#262a3a"), Color("#ffb46b") if on else Color("#3d4460"), 14)
	for k in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(k, st)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		row.add_child(icon(icon_name, 34))
	row.add_child(title(text, 19, Color.WHITE if on else MUTED))
	b.add_child(row)
	b.custom_minimum_size.x = 64 + text.length() * 12 + (40 if icon_name != "" else 0)
	return b


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
		c.color = Color("#141626")
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(c)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.05, dim)
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


# Yazı kutusu: belirgin turuncu çerçeve, koyu iç, büyük yazı.
static func style_edit(e: LineEdit, size := 22) -> void:
	var st := flat(Color(0.03, 0.03, 0.05, 0.95), Color(ORANGE, 0.85), 12)
	st.set_border_width_all(2)
	st.content_margin_left = 16
	var foc := st.duplicate()
	foc.border_color = TEAL
	e.add_theme_stylebox_override("normal", st)
	e.add_theme_stylebox_override("focus", foc)
	e.add_theme_font_size_override("font_size", size)
	e.add_theme_color_override("font_placeholder_color", Color(0.75, 0.72, 0.68, 0.8))
	e.add_theme_color_override("caret_color", ORANGE)
	e.custom_minimum_size.y = maxf(e.custom_minimum_size.y, 54)


static func place(c: Control, preset: int, ofs: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = ofs.x
	c.offset_top = ofs.y
	c.offset_right = ofs.x + sz.x
	c.offset_bottom = ofs.y + sz.y


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
			_:
				draw_circle(c, s.x * 0.35, color)
