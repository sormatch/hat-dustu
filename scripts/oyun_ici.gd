# Oyun içi ekran parçaları (7 mini oyunun ortak 2D arayüzü): oyun rozeti, sol üst oyun hapı, görev bandı,
# rol kartı (rozetli, tek cümle, kendiliğinden kapanır), büyük bildirim, kara tahta penceresi, tebeşir
# düğmeleri/çizimleri ve "bilgisayar" yardım ekranı. Renk, yazı ölçüsü ve düğmeler scripts/ui.gd takımından.
# Kullanım: const OI := preload("res://scripts/oyun_ici.gd") ; OI.rol_karti(kok, "rulet", "BAŞLIK", renk, "Tek cümle")
extends RefCounted

const UI := preload("res://scripts/ui.gd")
const CHALK_FONT := preload("res://assets/fonts/CabinSketch-Bold.ttf")
const CHALK := Color(0.95, 0.96, 0.9)
const CHALK_YESIL := Color(0.72, 1.0, 0.78)
const CHALK_SARI := Color(1.0, 0.86, 0.5)
const CHALK_KIRMIZI := Color(1.0, 0.62, 0.56)
# sunucudaki oyun adı -> görev anahtarı (rozet için)
const GOREV := {"KARA TAHTA": "tahta", "KISA DEVRE": "devre", "KİM KİM?": "kimkim", "YALANCI": "yalanci",
	"RUS RULETİ": "rulet", "C4": "c4", "ORTALAMA SAYI": "ortalama", "PROJEKTÖR AVI": "projektor", "BÜYÜK KAÇIŞ": "kacis"}


static func gorev_of(title: String) -> String:
	return str(GOREV.get(title.strip_edges(), ""))


static func ses(host: Node, n: String, vol := 0.0, pitch := 1.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	p.pitch_scale = pitch
	host.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# ---------- rozet, hap, bant ----------

static func rozet_tex(task: String, px: int) -> Texture2D:
	var ad := "uretim/oyun_" + task
	if task == "" or not UI.has(ad):
		return null
	return UI.texture(ad, px * 2)


# Oyun rozeti (assets/ui/uretim/oyun_*.png); glow verilirse arkasında o renkte yumuşak parıltı.
static func rozet(task: String, px: float, glow := Color(0, 0, 0, 0)) -> Control:
	var kok := Control.new()
	kok.custom_minimum_size = Vector2(px, px)
	kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if glow.a > 0.0:
		var g := TextureRect.new()
		var gt := GradientTexture2D.new()
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		var gr := Gradient.new()
		gr.set_color(0, glow)
		gr.set_color(1, Color(glow, 0.0))
		gt.gradient = gr
		g.texture = gt
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.position = Vector2(-px * 0.45, -px * 0.45)
		g.size = Vector2(px * 1.9, px * 1.9)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kok.add_child(g)
	var t := rozet_tex(task, int(px))
	var r: Control
	if t:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r = tr
	else:
		r = UI.icon("oyna", px * 0.8)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kok.add_child(r)
	kok.set_meta("resim", r)
	return kok


# Sol üstteki oyun hapı: rozet + oyunun adı.
static func hap() -> PanelContainer:
	var p := PanelContainer.new()
	var st := UI.flat(Color(0.03, 0.035, 0.035, 0.8), Color(1, 1, 1, 0.1), UI.R_BUYUK)
	st.set_border_width_all(1)
	st.shadow_size = 0
	st.content_margin_left = 4
	st.content_margin_right = UI.B_M + 2
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_XS)
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(48, 48)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(ic)
	var l := UI.title("", 22, UI.METIN)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	p.add_child(row)
	p.set_meta("icon", ic)
	p.set_meta("label", l)
	return p


static func hap_ayarla(p: PanelContainer, title: String) -> void:
	var l: Label = p.get_meta("label")
	var ic: TextureRect = p.get_meta("icon")
	if l.text == title and ic.texture != null:
		return
	l.text = title
	ic.texture = rozet_tex(gorev_of(title), 48)
	ic.visible = ic.texture != null


# Görev bandı: tek satır. Solda amber etiket (ne yapıyorsun), sağda kısa bilgi. İsteğe bağlı rozet.
static func bant() -> PanelContainer:
	var p := PanelContainer.new()
	var st := UI.flat(Color(0.03, 0.035, 0.035, 0.86), Color(UI.AMBER, 0.85), UI.R_BUYUK)
	st.set_border_width_all(0)
	st.border_width_bottom = 3
	st.shadow_size = 10
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.content_margin_left = UI.B_M + 4
	st.content_margin_right = UI.B_L
	st.content_margin_top = 4
	st.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size.y = 56
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_S)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(44, 44)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.visible = false
	row.add_child(ic)
	var tag := UI.title("", 22, UI.AMBER)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tag)
	var ayrac := ColorRect.new()
	ayrac.color = Color(1, 1, 1, 0.18)
	ayrac.custom_minimum_size = Vector2(2, 26)
	ayrac.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ayrac)
	var info := UI.label("", UI.FS_METIN, UI.METIN)
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(info)
	p.add_child(row)
	p.set_meta("icon", ic)
	p.set_meta("tag", tag)
	p.set_meta("info", info)
	p.set_meta("ayrac", ayrac)
	# yazı değişince bant hafifçe "zıplar" (göz yeni bilgiyi yakalasın)
	var son := {"t": ""}
	var bak := func() -> void:
		var simdi := tag.text + "|" + info.text
		ayrac.visible = tag.text != "" and info.text != ""
		info.visible = info.text != ""
		if simdi == son.t:
			return
		var ilk: bool = son.t == ""
		son.t = simdi
		if ilk or not p.is_visible_in_tree():
			return
		p.pivot_offset = p.size / 2.0
		var tw := p.create_tween()
		tw.tween_property(p, "scale", Vector2.ONE * 1.08, 0.08)
		tw.tween_property(p, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tag.draw.connect(bak)
	info.draw.connect(bak)
	p.resized.connect(func() -> void: p.pivot_offset = p.size / 2.0)
	return p


# ---------- rol kartı ----------

# Rozetli rol kartı: rozet, büyük başlık, (isteğe bağlı görsel), tek cümle; alttaki çizgi erirken kendiliğinden
# kapanır, dokununca hemen kapanır. Dönen: tam ekran katman (queue_free ile de kapatılabilir).
static func rol_karti(parent: Control, task: String, title: String, col: Color, line: String, extra: Control = null, sure := 4.5) -> Control:
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var perde := ColorRect.new()
	perde.color = Color(0, 0, 0, 0.62)
	perde.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	perde.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(perde)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(cc)
	var kart := VBoxContainer.new()
	kart.add_theme_constant_override("separation", 0)
	kart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(kart)
	var ust := Control.new()  # rozet panelin üst kenarından taşar; ortalama için üstte boşluk
	ust.custom_minimum_size.y = 74
	ust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kart.add_child(ust)
	var pad := UI.B_L + 4
	var p := UI.panel(Vector2(600, 0), pad)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kart.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	# rozet panelin İÇİNDE (negatif kenar payıyla yukarı taşar): z_index gerekmez, üstüne açılan
	# başka bir pencere (ör. sigorta kutusu) rozeti de örter
	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_top", -(74 + pad))
	rm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rm)
	var rz := rozet(task, 184, Color(col, 0.5))
	rz.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rm.add_child(rz)
	var t := UI.title(title, UI.FS_DEV, col, true)
	v.add_child(t)
	if extra:
		extra.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(extra)
	if line != "":
		var l := UI.label(line, UI.FS_ORTA, UI.METIN, true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 520
		v.add_child(l)
	# kendiliğinden kapanma çizgisi
	var iz := ColorRect.new()
	iz.color = Color(1, 1, 1, 0.08)
	iz.custom_minimum_size = Vector2(440, 6)
	iz.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	iz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dolgu := ColorRect.new()
	dolgu.color = col
	dolgu.size = Vector2(440, 6)
	dolgu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iz.add_child(dolgu)
	var ara := Control.new()
	ara.custom_minimum_size.y = 4
	v.add_child(ara)
	v.add_child(iz)
	parent.add_child(ov)
	# açılış: perde kararır, kart aşağıdan büyüyerek gelir, rozet sekerek yerine oturur
	perde.modulate.a = 0.0
	kart.modulate.a = 0.0
	ov.resized.connect(func() -> void: kart.pivot_offset = kart.size / 2.0)
	kart.pivot_offset = Vector2(300, 200)
	kart.scale = Vector2.ONE * 0.86
	rz.pivot_offset = Vector2(92, 92)
	rz.scale = Vector2.ONE * 0.3
	rz.rotation = -0.25
	var tw := ov.create_tween().set_parallel()
	tw.tween_property(perde, "modulate:a", 1.0, 0.18)
	tw.tween_property(kart, "modulate:a", 1.0, 0.15)
	tw.tween_property(kart, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(rz, "scale", Vector2.ONE, 0.45).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(rz, "rotation", 0.0, 0.45).set_delay(0.08).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	ses(ov, "parilti", -9.0)
	var kapat := func() -> void:
		if ov.get_meta("kapaniyor", false):
			return
		ov.set_meta("kapaniyor", true)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kt := ov.create_tween().set_parallel()
		kt.tween_property(ov, "modulate:a", 0.0, 0.2)
		kt.tween_property(kart, "scale", Vector2.ONE * 0.92, 0.2)
		kt.chain().tween_callback(ov.queue_free)
	ov.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			kapat.call())
	var at := ov.create_tween()
	at.tween_interval(0.3)
	at.tween_property(dolgu, "size:x", 0.0, maxf(0.5, sure - 0.3))
	at.tween_callback(kapat)
	return ov


# ---------- büyük bildirim ----------

# Ekranın üst-ortasında sinematik şerit üstünde büyük yazı; kısa süre sonra kaybolur. host: game_ui (CanvasLayer).
static func flash(host: Node, title: String, sub: String, col: Color, t := 1.6) -> Control:
	var k := Control.new()
	k.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k.set_meta("flash", true)
	host.add_child(k)
	var sz := k.get_viewport_rect().size
	var bh := 190.0 if sub != "" else 150.0
	var by := sz.y * 0.34 - bh / 2.0
	var serit := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.22, 0.78, 1.0])
	gr.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.66), Color(0, 0, 0, 0.66), Color(0, 0, 0, 0)])
	gt.gradient = gr
	serit.texture = gt
	serit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	serit.stretch_mode = TextureRect.STRETCH_SCALE
	serit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k.add_child(serit)
	serit.position = Vector2(0, by)
	serit.size = Vector2(sz.x, bh)
	serit.custom_minimum_size = Vector2(sz.x, bh)
	# şeridin üst ve altında oyunun renginde ince çizgi
	for yy in [by, by + bh - 3.0]:
		var c := TextureRect.new()
		var ct := GradientTexture2D.new()
		ct.fill_to = Vector2(1, 0)
		var cg := Gradient.new()
		cg.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
		cg.colors = PackedColorArray([Color(col, 0), Color(col, 0.85), Color(col, 0.85), Color(col, 0)])
		ct.gradient = cg
		c.texture = ct
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.position = Vector2(0, float(yy) - by)
		c.size = Vector2(sz.x, 3)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		serit.add_child(c)
	var fs := clampi(int((sz.x - 160.0) / maxf(1.0, title.length()) / 0.64), 40, 80)
	var big := UI.title(title, fs, col, true)
	big.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	big.add_theme_constant_override("outline_size", 12)
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big.position = Vector2(0, by + (12.0 if sub != "" else 0.0))
	big.size = Vector2(sz.x, bh - (60.0 if sub != "" else 0.0))
	big.pivot_offset = big.size / 2.0
	k.add_child(big)
	if sub != "":
		var sl := UI.title(sub, 28, UI.METIN, true)
		sl.position = Vector2(0, by + bh - 66.0)
		sl.size = Vector2(sz.x, 44)
		sl.clip_text = true
		k.add_child(sl)
	serit.pivot_offset = Vector2(sz.x / 2.0, bh / 2.0)
	serit.scale = Vector2(1, 0)
	big.scale = Vector2.ONE * 1.5
	big.modulate.a = 0.0
	var tw := k.create_tween()
	tw.tween_property(serit, "scale:y", 1.0, 0.14).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(big, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(big, "modulate:a", 1.0, 0.12)
	tw.tween_interval(t)
	tw.tween_property(k, "modulate:a", 0.0, 0.35)
	tw.tween_callback(k.queue_free)
	return k


# ---------- tebeşir ----------

static func chalk_label(text: String, size: int, col := CHALK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", CHALK_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func chalk_draw(kind: String, sz: Vector2, col := CHALK) -> ChalkDraw:
	var d := ChalkDraw.new()
	d.kind = kind
	d.col = col
	d.custom_minimum_size = sz
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


# Tebeşirle elle çizilmiş çerçeveli düğme (dolu: tebeşir taramalı). İçinde tebeşir simgesi ve yazı.
static func chalk_button(text: String, icon_kind: String, filled: bool, w: float, h := 76.0, col := CHALK) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, maxf(h, UI.DOKUNMA))
	var bos := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, bos)
	var kutu := ChalkDraw.new()
	kutu.kind = "kutu_dolu" if filled else "kutu"
	kutu.col = col
	kutu.tohum = randi() % 1000
	kutu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	kutu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(kutu)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_kind != "":
		var ic := chalk_draw(icon_kind, Vector2(44, 44), col)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := chalk_label(text, 34, col)
	l.visible = text != ""
	row.add_child(l)
	b.add_child(row)
	b.set_meta("kutu", kutu)
	b.set_meta("label", l)
	b.set_meta("ic_w", w - (64.0 if icon_kind != "" else 20.0))  # yazı için kalan genişlik
	_chalk_sigdir(l, float(b.get_meta("ic_w")))
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.94, 0.05)
		kutu.basili = true
		kutu.queue_redraw()
		UI.tik(-12.0))
	b.button_up.connect(func() -> void:
		b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(b, "scale", Vector2.ONE, 0.14)
		kutu.basili = false
		kutu.queue_redraw())
	b.draw.connect(func() -> void: row.modulate.a = 0.45 if b.disabled else 1.0)
	return b


static func chalk_set_text(b: Button, t: String) -> void:
	if b.has_meta("label"):
		var l: Label = b.get_meta("label")
		l.text = t
		l.visible = t != ""
		_chalk_sigdir(l, float(b.get_meta("ic_w", 9999.0)))


# Tebeşir yazısı düğmeye sığmazsa küçülür (uzun adlar: "Kıvırcık Ahmet"); en fazla 34, en az 22 px.
static func _chalk_sigdir(l: Label, max_w: float) -> void:
	var f: Font = CHALK_FONT
	var t := l.tr(l.text) if l.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else l.text
	var fs := 34
	while fs > 22 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 2
	l.add_theme_font_size_override("font_size", fs)


static func chalk_set_filled(b: Button, on: bool) -> void:
	if b.has_meta("kutu"):
		var k: ChalkDraw = b.get_meta("kutu")
		k.kind = "kutu_dolu" if on else "kutu"
		k.queue_redraw()


# Ahşap çerçeveli gerçek kara tahta penceresi (assets/ui/chalkboard.png). Başlık tebeşirle, altı el çizimi
# çizgiyle; sağ üstte tebeşir çarpı (64 px). Dönen: [katman, içerik kutusu, kapat düğmesi, tahta]
static func chalk_board(parent: Control, title: String, sub := "", bw := 1000.0) -> Array:
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = Color(0.0, 0.0, 0.02, 0.62)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(d)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var vh := 720.0
	if parent.is_inside_tree():
		vh = parent.get_viewport_rect().size.y
	bw = minf(bw, (vh - 24.0) * 1476.0 / 905.0)
	var bh := bw * 905.0 / 1476.0
	var board := Control.new()
	board.custom_minimum_size = Vector2(bw, bh)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(board)
	# gölge
	var sh := Panel.new()
	var sst := StyleBoxFlat.new()
	sst.bg_color = Color(0, 0, 0, 0.0)
	sst.shadow_color = Color(0, 0, 0, 0.6)
	sst.shadow_size = 36
	sst.shadow_offset = Vector2(0, 14)
	sst.set_corner_radius_all(24)
	sh.add_theme_stylebox_override("panel", sst)
	sh.position = Vector2(bw * 0.02, bh * 0.03)
	sh.size = Vector2(bw * 0.96, bh * 0.94)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(sh)
	var src: Texture2D = load("res://assets/ui/chalkboard.png") if ResourceLoader.exists("res://assets/ui/chalkboard.png") else null
	if src:
		var at := AtlasTexture.new()
		at.atlas = src
		at.region = Rect2(30, 50, 1476, 905)
		var tr := TextureRect.new()
		tr.texture = at
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(tr)
	else:
		var bg := Panel.new()
		var bst := UI.flat(Color("#2c4a35"), Color("#6b4a2b"), 10)
		bst.set_border_width_all(30)
		bg.add_theme_stylebox_override("panel", bst)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.add_child(bg)
	# alt çerçevede tebeşir ve silgi (süs)
	var t1 := chalk_draw("tebesir", Vector2(70, 40))
	t1.position = Vector2(bw * 0.2, bh * 0.905)
	t1.size = Vector2(70, 40)
	board.add_child(t1)
	var s1 := chalk_draw("silgi", Vector2(90, 46))
	s1.position = Vector2(bw * 0.72, bh * 0.895)
	s1.size = Vector2(90, 46)
	board.add_child(s1)
	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("margin_left", int(bw * 0.085))
	inner.add_theme_constant_override("margin_right", int(bw * 0.085))
	inner.add_theme_constant_override("margin_top", int(bh * 0.1))
	inner.add_theme_constant_override("margin_bottom", int(bh * 0.13))
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(inner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tl := chalk_label(title, 50)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hv.add_child(tl)
	var alt := chalk_draw("alti", Vector2(minf(460.0, 40.0 + title.length() * 24.0), 12))
	alt.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hv.add_child(alt)
	head.add_child(hv)
	var close := Button.new()
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(UI.DOKUNMA, UI.DOKUNMA)
	for k in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	var cx := ChalkDraw.new()
	cx.kind = "carpi"
	cx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close.add_child(cx)
	close.button_down.connect(func() -> void: UI.tik(-12.0))  # tebeşir düğmeleriyle aynı ses
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(close)
	v.add_child(head)
	if sub != "":
		var sl := chalk_label(sub, 28, CHALK_SARI)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		sl.modulate.a = 0.9
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sl)
	parent.add_child(ov)
	# açılış: tahta hafif eğik ve yukarıdan iner, yerine oturur
	board.pivot_offset = Vector2(bw, bh) / 2.0
	board.scale = Vector2.ONE * 0.9
	board.rotation = deg_to_rad(-2.5)
	board.modulate.a = 0.0
	d.modulate.a = 0.0
	var tin := board.create_tween().set_parallel()
	tin.tween_property(d, "modulate:a", 1.0, 0.18)
	tin.tween_property(board, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tin.tween_property(board, "rotation", 0.0, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tin.tween_property(board, "modulate:a", 1.0, 0.14)
	ses(ov, "tebesir_%d" % (randi() % 3 + 1), -8.0)
	return [ov, v, close, board]


# ---------- yardım ("bilgisayar") ----------

# Oyunun amacı: rozet + 3 adım kartı (büyük ikon, birkaç kelime) + ANLADIM. rows: [[ikon, yazı], ...]
static func yardim(task: String, title: String, rows: Array) -> Control:
	var m := UI.modal(title, 980.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UI.B_L)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	m.body.add_child(row)
	var rz := rozet(task, 190, Color(UI.AMBER, 0.28))
	rz.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rz)
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", UI.B_S)
	row.add_child(steps)
	var n := mini(rows.size(), 3)
	var kartlar: Array = []
	for i in n:
		var r: Array = rows[i]
		var k := PanelContainer.new()
		var st := UI.flat(UI.YUZEY_2, UI.CIZGI, UI.R_ORTA)
		st.set_border_width_all(1)
		st.shadow_size = 0
		st.content_margin_left = UI.B_S
		st.content_margin_right = UI.B_S
		st.content_margin_top = UI.B_S
		st.content_margin_bottom = UI.B_M
		k.add_theme_stylebox_override("panel", st)
		k.custom_minimum_size = Vector2(200, 236)
		var kv := VBoxContainer.new()
		kv.add_theme_constant_override("separation", UI.B_XS)
		k.add_child(kv)
		var no := UI.title(str(i + 1), UI.FS_ORTA, UI.AMBER)
		kv.add_child(no)
		var ic := UI.icon(str(r[0]), 84)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		kv.add_child(ic)
		var l := UI.title(str(r[1]), UI.FS_METIN, UI.METIN, true)
		l.add_theme_constant_override("outline_size", 3)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 176
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		kv.add_child(l)
		steps.add_child(k)
		kartlar.append(k)
	var ok := UI.button("ANLADIM", "ana", UI.BTN_H, 28, "", 340)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(m.close)
	m.body.add_child(ok)
	m.set_meta("ok", ok)
	# adım kartları sırayla belirir
	for i in kartlar.size():
		var k: Control = kartlar[i]
		k.modulate.a = 0.0
		var tw := k.create_tween()
		tw.tween_interval(0.18 + 0.12 * i)
		tw.tween_property(k, "modulate:a", 1.0, 0.2)
	return m


# Tebeşirle çizilmiş simgeler, elle çizilmiş kutu ve çizgiler. Her çizgi hafif titrek ve iki geçişli (tebeşir izi).
class ChalkDraw extends Control:
	var kind := "cizgi"  # cizgi, alti, tebesir, silgi, carpi, kutu, kutu_dolu, kisi, onay, daire, yildiz, ok, ahize, tac
	var col := Color(0.95, 0.96, 0.9)
	var tohum := 7
	var basili := false
	var _rng := RandomNumberGenerator.new()

	func _cizgi(a: Vector2, b: Vector2, w: float, alpha := 0.9) -> void:
		var L := a.distance_to(b)
		var n := maxi(1, int(L / 14.0))
		var dir := (b - a) / maxf(L, 0.001)
		var nor := Vector2(-dir.y, dir.x)
		var prev := a
		for i in range(1, n + 1):
			var p := a.lerp(b, float(i) / n) + nor * _rng.randf_range(-1.1, 1.1)
			var al := alpha * _rng.randf_range(0.72, 1.0)
			draw_line(prev, p, Color(col, al), w)
			draw_line(prev + Vector2(0.9, 0.7), p + Vector2(0.9, 0.7), Color(col, al * 0.35), w * 0.6)
			prev = p

	func _yay(c: Vector2, r: Vector2, a0: float, a1: float, w: float, alpha := 0.9) -> void:
		var n := maxi(8, int(absf(a1 - a0) * maxf(r.x, r.y) / 10.0))
		var prev := c + Vector2(cos(a0) * r.x, sin(a0) * r.y)
		for i in range(1, n + 1):
			var a := lerpf(a0, a1, float(i) / n)
			var j := _rng.randf_range(-0.9, 0.9)
			var p := c + Vector2(cos(a) * (r.x + j), sin(a) * (r.y + j))
			draw_line(prev, p, Color(col, alpha * _rng.randf_range(0.72, 1.0)), w)
			prev = p

	func _draw() -> void:
		_rng.seed = hash(kind) + tohum
		var w := size.x
		var h := size.y
		var c := size / 2.0
		match kind:
			"cizgi":
				var x := 0.0
				var i := 0
				while x < w:
					var seg := 26.0 + float(i % 3) * 6.0
					_cizgi(Vector2(x, h / 2), Vector2(minf(x + seg, w), h / 2 + sin(i * 2.3) * 1.5), 3.0, 0.75)
					x += seg + 12.0
					i += 1
			"alti":
				_cizgi(Vector2(2, h * 0.55), Vector2(w * 0.6, h * 0.35), 3.0, 0.8)
				_cizgi(Vector2(w * 0.6, h * 0.35), Vector2(w - 2, h * 0.6), 3.0, 0.8)
			"tebesir":
				var r := Vector2(w * 0.78, h * 0.3)
				draw_set_transform(c, -0.25, Vector2.ONE)
				draw_rect(Rect2(-r / 2, r), Color("#f4f1e6"))
				draw_rect(Rect2(Vector2(r.x / 2 - 7, -r.y / 2), Vector2(7, r.y)), Color("#d9d4c3"))
				draw_rect(Rect2(Vector2(-r.x / 2, r.y * 0.1), Vector2(r.x, r.y * 0.4)), Color(0, 0, 0, 0.12))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			"silgi":
				draw_set_transform(c, -0.12, Vector2.ONE)
				draw_rect(Rect2(-w * 0.4, -h * 0.24, w * 0.8, h * 0.28), Color("#8a5a32"))
				draw_rect(Rect2(-w * 0.4, -h * 0.24, w * 0.8, h * 0.06), Color("#a8743f"))
				draw_rect(Rect2(-w * 0.4, h * 0.04, w * 0.8, h * 0.2), Color("#3a3d44"))
				draw_rect(Rect2(-w * 0.4, h * 0.18, w * 0.8, h * 0.06), Color(0.9, 0.9, 0.85, 0.5))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			"carpi":
				_cizgi(Vector2(w * 0.3, h * 0.3), Vector2(w * 0.7, h * 0.7), 4.0)
				_cizgi(Vector2(w * 0.7, h * 0.3), Vector2(w * 0.3, h * 0.7), 4.0)
				_yay(c, Vector2(w, h) * 0.42, -0.4, TAU - 0.1, 3.0, 0.65)
			"kutu", "kutu_dolu":
				var ins := 5.0
				if kind == "kutu_dolu" or basili:
					var fill := Color(col, 0.16 if basili else 0.1)
					draw_rect(Rect2(ins + 2, ins + 2, w - (ins + 2) * 2, h - (ins + 2) * 2), fill)
					# tebeşir taraması
					var L := ins + 3.0
					var R := w - ins - 3.0
					var T := ins + 3.0
					var B := h - ins - 3.0
					var x0 := -h
					while x0 < w:
						var p1 := Vector2(x0, h)
						var p2 := Vector2(x0 + h, 0)
						if p1.x < L:
							p1 = Vector2(L, p1.y - (L - p1.x))
						if p1.y > B:
							p1 = Vector2(p1.x + (p1.y - B), B)
						if p2.x > R:
							p2 = Vector2(R, p2.y + (p2.x - R))
						if p2.y < T:
							p2 = Vector2(p2.x - (T - p2.y), T)
						if p2.x > p1.x + 4.0:
							draw_line(p1, p2, Color(col, 0.07), 2.0)
						x0 += 10.0
				var o := 4.0  # köşelerde çizgiler biraz taşar (elle çizilmiş)
				_cizgi(Vector2(ins - o, ins), Vector2(w - ins + o * 0.5, ins + 1), 3.0)
				_cizgi(Vector2(w - ins, ins - o * 0.5), Vector2(w - ins - 1, h - ins + o), 3.0)
				_cizgi(Vector2(w - ins + o * 0.5, h - ins), Vector2(ins - o, h - ins - 1), 3.0)
				_cizgi(Vector2(ins + 1, h - ins + o * 0.5), Vector2(ins, ins - o), 3.0)
			"kisi":
				_yay(Vector2(c.x, h * 0.33), Vector2(w, h) * 0.17, 0, TAU, 3.5)
				_yay(Vector2(c.x, h * 0.98), Vector2(w * 0.34, h * 0.36), PI, TAU, 3.5)
			"onay":
				_cizgi(Vector2(w * 0.18, h * 0.52), Vector2(w * 0.42, h * 0.76), 5.0)
				_cizgi(Vector2(w * 0.42, h * 0.76), Vector2(w * 0.84, h * 0.22), 5.0)
			"daire":
				_yay(c, Vector2(w * 0.48, h * 0.44), -0.6, TAU + 0.2, 3.5, 0.85)
			"yildiz":
				var pts: Array = []
				for k in 5:
					var a := -PI / 2 + k * TAU * 2.0 / 5.0
					pts.append(c + Vector2(cos(a), sin(a)) * minf(w, h) * 0.44)
				for k in 5:
					_cizgi(pts[k], pts[(k + 1) % 5], 3.5)
			"ok":
				_cizgi(Vector2(w * 0.1, c.y), Vector2(w * 0.88, c.y), 3.5)
				_cizgi(Vector2(w * 0.88, c.y), Vector2(w * 0.62, h * 0.22), 3.5)
				_cizgi(Vector2(w * 0.88, c.y), Vector2(w * 0.62, h * 0.78), 3.5)
			"ahize":
				_yay(Vector2(c.x, h * 0.62), Vector2(w * 0.36, h * 0.34), PI * 1.05, TAU - 0.05, 4.0)
				_yay(Vector2(w * 0.17, h * 0.66), Vector2(w * 0.12, h * 0.1), 0, TAU, 3.5)
				_yay(Vector2(w * 0.83, h * 0.66), Vector2(w * 0.12, h * 0.1), 0, TAU, 3.5)
			"tac":
				var p := [Vector2(w * 0.12, h * 0.78), Vector2(w * 0.16, h * 0.28), Vector2(w * 0.34, h * 0.56), Vector2(c.x, h * 0.18), Vector2(w * 0.66, h * 0.56), Vector2(w * 0.84, h * 0.28), Vector2(w * 0.88, h * 0.78)]
				for k in p.size() - 1:
					_cizgi(p[k], p[k + 1], 3.5)
				_cizgi(p[p.size() - 1], p[0], 3.5)
