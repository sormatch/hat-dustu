# Menü ekranlarının ortak parçaları (ui.gd takımının üstüne): kutucuk düğme, avatar, seviye rozeti, parıltı,
# tam ekran çerçeve (arka plan + üst çubuk + geri), açılma animasyonları, aç/kapa anahtarı, kaydırıcı.
# Kullanan: menu.gd, settings.gd, giris.gd, gorevler.gd, liderlik.gd
extends RefCounted

const UI := preload("res://scripts/ui.gd")

# Avatar renkleri (oyuncunun baş harfi dairesinde) — ad/kullanıcı adından sabit seçilir
# Liderlik kürsüsü (1. / 2. / 3.)
const KURSU_RENK := [Color("#ffc23a"), Color("#c9d2da"), Color("#d0874a")]
const AVATAR_RENK := ["#e0822a", "#3fa8ff", "#4cc23a", "#b05cff", "#e0322a", "#d4a020", "#2bb3a3", "#d0558a"]


# ---------------------------------------------------------------------
# Kutucuk düğme: üstte büyük ikon, altında kısa başlık (menüdeki MAĞAZA / GÖREVLER ...)
# ---------------------------------------------------------------------
static func tile(text: String, icon_name: String, w := 128.0, h := 116.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	var hh := int(h)
	var st: StyleBox = UI.kit_sbox(UI.KIT + "btn_ikincil", 76, UI.KESIM.btn, Vector4.ZERO)
	var bas: StyleBox = UI.kit_sbox(UI.KIT + "btn_ikincil_basili", 76, UI.KESIM.btn, Vector4.ZERO)
	if st == null:
		st = UI.flat(Color(UI.YUZEY_2), Color(UI.CIZGI), UI.R_ORTA)
	for k in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	b.add_theme_stylebox_override("pressed", bas if bas else st)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 8
	v.offset_bottom = -12
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UI.icon(icon_name, minf(64.0, hh * 0.52))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UI.title(text, 18, UI.METIN, true)
	v.add_child(l)
	b.add_child(v)
	b.set_meta("label", l)
	b.set_meta("icon", ic)
	UI._basma_hissi(b, v)
	return b


# ---------------------------------------------------------------------
# Avatar: renkli daire + baş harf (+ durum noktası). durum: "" yok, "acik" yeşil, "kapali" gri, "oda" amber
# ---------------------------------------------------------------------
static func avatar(name: String, key: String, px := 52.0, durum := "") -> Control:
	var kok := Control.new()
	kok.custom_minimum_size = Vector2(px, px)
	kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := 7
	for i in key.length():
		hs = (hs * 31 + key.unicode_at(i)) % 100003
	var renk := Color(AVATAR_RENK[hs % AVATAR_RENK.size()])
	var p := Panel.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = renk.darkened(0.15)
	st.border_color = renk.lightened(0.35)
	st.set_border_width_all(3)
	st.set_corner_radius_all(int(px / 2))
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 4
	st.shadow_offset = Vector2(0, 2)
	p.add_theme_stylebox_override("panel", st)
	kok.add_child(p)
	var harf := name.strip_edges().substr(0, 1).to_upper()
	var l := UI.title(harf if harf != "" else "?", int(px * 0.46), Color.WHITE, true)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kok.add_child(l)
	if durum != "":
		var d := Panel.new()
		var ds := px * 0.3
		d.position = Vector2(px - ds * 0.9, px - ds * 0.9)
		d.size = Vector2(ds, ds)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dst := StyleBoxFlat.new()
		dst.bg_color = {"acik": UI.YESIL, "oda": UI.AMBER}.get(durum, Color("#5d6563"))
		dst.border_color = UI.ZEMIN
		dst.set_border_width_all(3)
		dst.set_corner_radius_all(int(ds))
		d.add_theme_stylebox_override("panel", dst)
		kok.add_child(d)
	return kok


# ---------------------------------------------------------------------
# Seviye rozeti: rütbe kalkanı (çaylak / kıdemli / patron / efsane) ve üstünde seviye sayısı
# ---------------------------------------------------------------------
static func rutbe(seviye: int) -> String:
	if seviye >= 30:
		return "rozet_efsane"
	if seviye >= 15:
		return "rozet_patron"
	if seviye >= 5:
		return "rozet_kidemli"
	return "rozet_caylak"


static func level_shield(seviye: int, px := 56.0) -> Control:
	var kok := Control.new()
	kok.custom_minimum_size = Vector2(px, px)
	kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UI.texture(rutbe(seviye), int(px * 2))
	if t:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kok.add_child(r)
	else:
		kok.add_child(UI.icon("xp", px))
	var l := UI.title(str(seviye), int(px * 0.4), Color.WHITE, true)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.offset_top = px * 0.06
	l.add_theme_constant_override("outline_size", maxi(5, int(px / 8)))
	kok.add_child(l)
	kok.set_meta("label", l)
	return kok


# ---------------------------------------------------------------------
# Yumuşak ışık halesi (radyal), arkaya koymak için
# ---------------------------------------------------------------------
static func glow(color: Color, alpha := 0.5) -> TextureRect:
	var r := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var g := Gradient.new()
	g.set_color(0, Color(color, alpha))
	g.set_color(1, Color(color, 0.0))
	g.add_point(0.45, Color(color, alpha * 0.35))
	gt.gradient = g
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# Kenarları karartan sinematik gölge
static func vignette(ic := 0.15, dis := 0.85) -> TextureRect:
	var vig := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.05, 1.05)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, ic))
	g.set_color(1, Color(0, 0, 0, dis))
	gt.gradient = g
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return vig


# Panel içinde koyu satır/kart zemini (YUZEY_2, ince çizgi, isteğe göre solda renkli şerit)
static func row_box(accent := Color(0, 0, 0, 0), pad := Vector4(16, 10, 16, 10)) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(UI.YUZEY_2, 0.92)
	st.border_color = Color(UI.CIZGI, 0.9)
	st.set_border_width_all(2)
	if accent.a > 0.0:
		st.border_color = Color(accent, 0.75)
		st.border_width_left = 6
	st.set_corner_radius_all(UI.R_ORTA)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 4
	st.shadow_offset = Vector2(0, 2)
	st.content_margin_left = pad.x
	st.content_margin_top = pad.y
	st.content_margin_right = pad.z
	st.content_margin_bottom = pad.w
	p.add_theme_stylebox_override("panel", st)
	return p


# Küçük renkli hap (ör. "EFSANE", "HAFTALIK"): ince kenar, koyu iç, renkli yazı
static func pill(text: String, color: Color, size := 16) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(color.darkened(0.75), 0.92)
	st.border_color = color
	st.set_border_width_all(2)
	st.set_corner_radius_all(40)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.title(text, size, color.lightened(0.15), true)
	l.add_theme_constant_override("outline_size", 3)
	p.add_child(l)
	p.set_meta("label", l)
	return p


# Ödül hapı: elmas ikonu + sayı
static func reward(n: int, px := 30) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UI.icon("elmas", px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := UI.title("+%d" % n, int(px * 0.75), UI.ELMAS)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


# Sayıyı binlik ayraçla yazar: 10025 -> "10.025"
static func sayi(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ---------------------------------------------------------------------
# Tam ekran çerçeve: arka plan + üst çubuk (geri, ikon, başlık, sağda yer) + gövde
# Dönen sözlük: kok (Control), bar_sag (HBoxContainer, sağ uçtaki öğeler için), govde (Control), geri (Button)
# ---------------------------------------------------------------------
static func screen(baslik: String, icon_name: String, bg := "bg_menu", dim := 0.7) -> Dictionary:
	var kok := Control.new()
	kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	kok.add_child(UI.background(bg, dim))
	kok.add_child(vignette(0.1, 0.8))
	var govde := Control.new()
	govde.set_anchors_preset(Control.PRESET_FULL_RECT)
	govde.offset_top = UI.UST_BAR_H + 8
	govde.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kok.add_child(govde)
	var bar := UI.top_bar()
	kok.add_child(bar)
	var row: HBoxContainer = bar.get_meta("row")
	var geri := UI.icon_button("geri", "ikincil", 56)
	geri.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(geri)
	if icon_name != "":
		var ic := UI.icon(icon_name, 44)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var t := UI.title(baslik, FS_BASLIK, UI.METIN)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var sag := HBoxContainer.new()
	sag.add_theme_constant_override("separation", UI.B_M)
	sag.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(sag)
	# genişlik için dokunma alanı: geri düğmesi 56 px görünür, 64 px'lik kutu içinde
	geri.custom_minimum_size = Vector2(64, 56)
	return {"kok": kok, "bar_sag": sag, "govde": govde, "geri": geri, "baslik": t, "bar": bar}

const FS_BASLIK := 30


# ---------------------------------------------------------------------
# Animasyonlar
# ---------------------------------------------------------------------

# Ekran açılışı: hafif kararmadan belirir, gövde aşağıdan kayar
static func intro(kok: Control, govde: Control = null) -> void:
	kok.modulate.a = 0.0
	var tw := kok.create_tween()
	tw.tween_property(kok, "modulate:a", 1.0, 0.2)
	if govde:
		var y0 := govde.position.y
		govde.position.y = y0 + 30.0
		tw.parallel().tween_property(govde, "position:y", y0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# Kapanış: soluklaşır, sonra callback
static func outro(kok: Control, done: Callable) -> void:
	kok.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := kok.create_tween()
	tw.tween_property(kok, "modulate:a", 0.0, 0.16)
	tw.tween_callback(done)


# Kutudaki çocuklar sırayla aşağıdan belirir (liste satırları, düğmeler)
static func stagger(box: Control, adim := 0.045) -> void:
	var i := 0
	for c in box.get_children():
		if not (c is Control) or not (c as Control).visible:
			continue
		var cc := c as Control
		cc.modulate.a = 0.0
		var tw := cc.create_tween()
		tw.tween_interval(i * adim)
		tw.tween_property(cc, "modulate:a", 1.0, 0.18)
		# kap içindeki öğenin konumu kaba ait; bu yüzden kaydırma yerine ölçekle belirir
		cc.pivot_offset = Vector2(cc.size.x / 2.0, cc.size.y)
		cc.scale = Vector2(0.96, 0.96)
		tw.parallel().tween_property(cc, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


# Sürekli hafif nabız (ödül hazır, alınabilir görev)
static func pulse(c: Control, olcek := 1.05, sure := 0.7) -> void:
	c.resized.connect(func() -> void: c.pivot_offset = c.size / 2.0)
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "scale", Vector2.ONE * olcek, sure).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, sure).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------------
# Ayar denetimleri
# ---------------------------------------------------------------------

# Aç/kapa anahtarı (iOS tarzı ama oyunun renklerinde). on_change(bool)
static func switch(on: bool, on_change: Callable) -> Anahtar:
	var s := Anahtar.new()
	s.acik = on
	s.on_change = on_change
	return s


# Kaydırıcı: amber dolgu, yuvarlak tutamak
static func style_slider(s: HSlider) -> void:
	var iz := StyleBoxFlat.new()
	iz.bg_color = Color(0.02, 0.025, 0.025, 0.95)
	iz.border_color = UI.CIZGI
	iz.set_border_width_all(2)
	iz.set_corner_radius_all(10)
	iz.content_margin_top = 9
	iz.content_margin_bottom = 9
	var dolu := StyleBoxFlat.new()
	dolu.bg_color = UI.AMBER
	dolu.set_corner_radius_all(10)
	dolu.content_margin_top = 9
	dolu.content_margin_bottom = 9
	dolu.shadow_color = Color(UI.AMBER, 0.35)
	dolu.shadow_size = 6
	s.add_theme_stylebox_override("slider", iz)
	s.add_theme_stylebox_override("grabber_area", dolu)
	s.add_theme_stylebox_override("grabber_area_highlight", dolu)
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 40:
		for x in 40:
			var d := Vector2(x - 19.5, y - 19.5).length()
			if d <= 17.0:
				var c := Color("#fff4dc") if d < 12.0 else Color("#c98a1a")
				c.a = clampf(17.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, c)
	var t := ImageTexture.create_from_image(img)
	s.add_theme_icon_override("grabber", t)
	s.add_theme_icon_override("grabber_highlight", t)
	s.custom_minimum_size.y = UI.DOKUNMA


class Anahtar extends Button:
	var acik := false
	var on_change := Callable()
	var _t := 0.0:  # 0 kapalı .. 1 açık (animasyon)
		set(v):
			_t = v
			queue_redraw()

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(104, 64)
		size_flags_horizontal = Control.SIZE_SHRINK_END
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bos := StyleBoxEmpty.new()
		for k in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(k, bos)
		pressed.connect(_bas)

	func _ready() -> void:
		_t = 1.0 if acik else 0.0

	func _bas() -> void:
		acik = not acik
		UI.tik()
		var tw := create_tween()
		tw.tween_property(self, "_t", 1.0 if acik else 0.0, 0.16).set_trans(Tween.TRANS_CUBIC)
		if on_change.is_valid():
			on_change.call(acik)

	func _draw() -> void:
		var h := 44.0
		var w := 96.0
		var r := Rect2(Vector2((size.x - w) / 2.0, (size.y - h) / 2.0), Vector2(w, h))
		var zemin := Color("#2a302e").lerp(Color("#2f8a24"), _t)
		var kenar := Color("#4d5653").lerp(Color("#8ff07a"), _t)
		var st := StyleBoxFlat.new()
		st.bg_color = zemin
		st.border_color = kenar
		st.set_border_width_all(2)
		st.set_corner_radius_all(int(h / 2))
		st.shadow_color = Color(0, 0, 0, 0.5)
		st.shadow_size = 3
		st.shadow_offset = Vector2(0, 2)
		draw_style_box(st, r)
		var cx := lerpf(r.position.x + h / 2.0, r.end.x - h / 2.0, _t)
		var c := Vector2(cx, r.position.y + h / 2.0)
		draw_circle(c + Vector2(0, 2), h / 2.0 - 5.0, Color(0, 0, 0, 0.4))
		draw_circle(c, h / 2.0 - 5.0, Color("#f3ead8"))
		draw_circle(c, h / 2.0 - 11.0, Color("#d9cfba"))


# ---------------------------------------------------------------------
# Elmas sayacı + yeşil "+" (elmas mağazası). Hapın tamamı dokunulabilir (64 px).
# Sayıyı değiştirmek: b.get_meta("label").text = "1.250"
# ---------------------------------------------------------------------
static func gem_counter(n: int, kaynak: Node) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UI.DOKUNMA)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bos := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, bos)
	var hap := PanelContainer.new()
	var st := UI.flat(Color(0, 0, 0, 0.55), Color(UI.ELMAS, 0.28), UI.R_BUYUK)
	st.shadow_size = 0
	st.content_margin_left = 2
	st.content_margin_right = 4
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	hap.add_theme_stylebox_override("panel", st)
	hap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hap.set_anchors_preset(Control.PRESET_FULL_RECT)
	hap.offset_top = 8
	hap.offset_bottom = -8
	b.add_child(hap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hap.add_child(row)
	var ic := UI.icon("elmas", 42)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := UI.title(sayi(n), UI.FS_ORTA, UI.ELMAS)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 64
	row.add_child(l)
	var arti := PanelContainer.new()
	var ast: StyleBox = UI.kit_sbox(UI.KIT + "btn_yesil", 40, UI.KESIM.btn, Vector4(0, 0, 0, 0))
	if ast == null:
		ast = UI.flat(UI.YESIL, UI.YESIL.lightened(0.4), UI.R_KUCUK)
	arti.add_theme_stylebox_override("panel", ast)
	arti.custom_minimum_size = Vector2(40, 40)
	arti.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var al := UI.title("+", 30, Color.WHITE, true)
	al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	al.add_theme_color_override("font_outline_color", Color("#0f3a08"))
	al.offset_top = -2
	arti.add_child(al)
	row.add_child(arti)
	# genişlik içeriğe göre
	row.minimum_size_changed.connect(func() -> void:
		b.custom_minimum_size.x = row.get_combined_minimum_size().x + 8)
	b.custom_minimum_size.x = 42 + 6 + 64 + 6 + 40 + 8
	b.set_meta("label", l)
	UI._basma_hissi(b, hap)
	b.pressed.connect(func() -> void: open_gem_store(kaynak))
	return b


# Elmas mağazasını açar (main.gd open_gem_store; yoksa bilgi verir)
static func open_gem_store(kaynak: Node) -> void:
	if kaynak == null or not kaynak.is_inside_tree():
		return
	var m := kaynak.get_tree().current_scene
	if m and m.has_method("open_gem_store"):
		m.call("open_gem_store")
	else:
		UI.toast("Elmas mağazası çok yakında!", null, 1.8, "bilgi")


# Telefon titreşimi gibi küçük bir "ödül hazır" parıltısı: öğenin arkasında yanıp sönen hale
static func halo(hedef: Control, color: Color) -> TextureRect:
	var g := glow(color, 0.55)
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.offset_left = -26
	g.offset_right = 26
	g.offset_top = -22
	g.offset_bottom = 22
	g.show_behind_parent = true
	hedef.add_child(g)
	var tw := g.create_tween().set_loops()
	tw.tween_property(g, "modulate:a", 0.35, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(g, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	return g
