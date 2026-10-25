# Kısa Devre: sigortanın yakın çekim paneli. Koyu metal kasa; üstte yeşil ekranda kutu kodu ve adım ışıkları,
# altta dört bölüm: kesilecek kablolar, takılacak fişler, şalterler ve tuş takımı.
# Her işlem "action" sinyaliyle sunucuya gider; doğru/yanlış sonucu sunucudan gelir (set_result).
extends Control

signal action(v: Dictionary)
signal closed

const UI := preload("res://scripts/ui.gd")
const COLORS := {
	"KIRMIZI": "#d62828", "TURUNCU": "#f77f00", "SARI": "#f6c343", "YEŞİL": "#2a9d4b", "AÇIK MAVİ": "#6ec6ff",
	"KOYU MAVİ": "#1d3f8f", "MOR": "#8e44ad", "BEYAZ": "#efefef", "SİYAH": "#1b1b1b", "GRİ": "#8a8f98",
}
const LCD := Color("#7dff9f")
# renk adı -> görsel dosya eki (assets/ui/kablo_<ek>.png)
const FILE := {
	"KIRMIZI": "kirmizi", "TURUNCU": "turuncu", "SARI": "sari", "YEŞİL": "yesil", "AÇIK MAVİ": "acik_mavi",
	"KOYU MAVİ": "koyu_mavi", "MOR": "mor", "BEYAZ": "beyaz", "SİYAH": "siyah", "GRİ": "gri",
}

var code := "K7"
var wires: Array = []
var plugs: Array = []
var steps := 2
var moduller: Array = ["kes", "tak", "salter", "kod"]  # bu kutuda olan bölümler (sadece gerekenler gösterilir)
var done_steps := 0
var status := "acik"  # acik, tamir, kilit
var cut: Array = []
var plugged := {}  # renk -> soket
var switches: Array = []
var _held_plug := ""
var _keys := ""

var _body: VBoxContainer
var _leds: HBoxContainer
var _status_label: Label
var _key_display: Label


static func color_of(n: String) -> Color:
	return Color(COLORS.get(n, "#888888"))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := PanelContainer.new()
	# ChatGPT görseli varsa (assets/ui/sigorta_bg.png) panel onunla giydirilir
	var tex_st := UI.sbox("sigorta_bg", 520, 0.12, Vector4(48, 40, 48, 40))
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#2b2f35")
	st.border_color = Color("#5a6069")
	st.set_border_width_all(6)
	st.set_corner_radius_all(14)
	st.shadow_color = Color(0, 0, 0, 0.7)
	st.shadow_size = 24
	st.content_margin_left = 26
	st.content_margin_right = 26
	st.content_margin_top = 18
	st.content_margin_bottom = 20
	box.add_theme_stylebox_override("panel", tex_st if tex_st else st)
	box.custom_minimum_size = Vector2(minf(1200, 360 + 310 * moduller.size()), 0)
	center.add_child(box)
	var screws := Screws.new()
	screws.set_anchors_preset(Control.PRESET_FULL_RECT)
	screws.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(screws)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	box.add_child(_body)
	_build()


func _build() -> void:
	for c in _body.get_children():
		c.queue_free()
	# üst şerit: uyarı, kod ekranı, adım ışıkları, kapat
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var warn_row := HBoxContainer.new()
	warn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warn_row.add_theme_constant_override("separation", 10)
	if UI.has("uyari"):
		warn_row.add_child(_tex_rect("uyari", 50))
	warn_row.add_child(UI.title("YÜKSEK GERİLİM", 22, Color("#ffcf3a")))
	top.add_child(warn_row)
	top.add_child(_lcd("KUTU  " + code, 30))
	_leds = HBoxContainer.new()
	_leds.add_theme_constant_override("separation", 8)
	top.add_child(_leds)
	var close := UI.button("KAPAT", "normal", 48, 18, "", 130)
	close.pressed.connect(func() -> void: closed.emit())
	top.add_child(close)
	_body.add_child(top)
	_status_label = UI.title("", 26, Color.WHITE, true)
	_body.add_child(_status_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if "kes" in moduller:
		row.add_child(_section("KABLOLAR", _wires_ui(), 420))
	if "tak" in moduller:
		row.add_child(_section("FİŞLER", _plugs_ui(), 330))
	if "salter" in moduller:
		row.add_child(_section("ŞALTERLER", _switches_ui(), 290))
	if "kod" in moduller:
		row.add_child(_section("TUŞ TAKIMI", _keypad_ui(), 290))
	_body.add_child(row)
	_refresh_status()


func _lcd(text: String, size: int) -> PanelContainer:
	var p := PanelContainer.new()
	var lcd_tex := UI.sbox("lcd", 90, 0.25, Vector4(18, 6, 18, 6))
	if lcd_tex:
		p.add_theme_stylebox_override("panel", lcd_tex)
		p.add_child(UI.title(text, size, LCD, true))
		return p
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#07170c")
	st.border_color = Color("#14361d")
	st.set_border_width_all(3)
	st.set_corner_radius_all(6)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	var l := UI.title(text, size, LCD, true)
	p.add_child(l)
	return p


func _section(title: String, content: Control, w: float) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#1d2025")
	st.border_color = Color("#3c424b")
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size.x = w
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(UI.title(title, 18, Color(0.82, 0.85, 0.9)))
	v.add_child(content)
	p.add_child(v)
	return p


# ---------- kablolar ----------

class Wire extends Button:
	var color := Color.RED
	var is_cut := false
	var tex: Texture2D

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var x := w / 2.0
		if tex:
			var ts := tex.get_size()
			var sc := minf(w / ts.x, h / ts.y)
			var dw := ts.x * sc
			var dh := ts.y * sc
			var ox := (w - dw) / 2.0
			var oy := (h - dh) / 2.0
			if not is_cut:
				draw_texture_rect(tex, Rect2(ox, oy, dw, dh), false)
				return
			var copper: Texture2D = UI.texture("kablo_kesik", 128)
			draw_texture_rect_region(tex, Rect2(ox - 4, oy, dw, dh * 0.42), Rect2(0, 0, ts.x, ts.y * 0.42))
			draw_texture_rect_region(tex, Rect2(ox + 4, oy + dh * 0.58, dw, dh * 0.42), Rect2(0, ts.y * 0.58, ts.x, ts.y * 0.42))
			if copper:
				var cs := Vector2(dw * 0.6, dw * 0.6)
				draw_texture_rect(copper, Rect2(Vector2(x - 4 - cs.x / 2, oy + dh * 0.42 - cs.y * 0.3), cs), false)
				draw_texture_rect(copper, Rect2(Vector2(x + 4 - cs.x / 2, oy + dh * 0.58 - cs.y * 0.7), cs), false, Color.WHITE, true)
			return
		# üst ve alt vida terminali
		for y in [10.0, h - 10.0]:
			draw_circle(Vector2(x, y), 9, Color("#b8bcc4"))
			draw_circle(Vector2(x, y), 4, Color("#6a6f78"))
		var dark := color.darkened(0.45)
		var sag := 16.0
		var curve := func(a: float, b: float, side: float) -> PackedVector2Array:
			var pts := PackedVector2Array()
			for i in 13:
				var t := lerpf(a, b, i / 12.0)
				pts.append(Vector2(x + sin(t * PI) * sag * side, lerpf(18.0, h - 18.0, t)))
			return pts
		if is_cut:
			var top: PackedVector2Array = curve.call(0.0, 0.42, 1.0)
			var bot: PackedVector2Array = curve.call(0.58, 1.0, 1.0)
			for seg in [top, bot]:
				draw_polyline(seg, dark, 16, true)
				draw_polyline(seg, color, 10, true)
			draw_circle(top[top.size() - 1], 5, Color("#d08a3a"))
			draw_circle(bot[0], 5, Color("#d08a3a"))
		else:
			var full: PackedVector2Array = curve.call(0.0, 1.0, 1.0)
			draw_polyline(full, dark, 16, true)
			draw_polyline(full, color, 10, true)
			var hl := PackedVector2Array()
			for q in full:
				hl.append(q + Vector2(-3, 0))
			draw_polyline(hl, color.lightened(0.45), 2.5, true)


func _wires_ui() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for n in wires:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var b := Wire.new()
		b.color = color_of(n)
		b.tex = UI.texture("kablo_" + str(FILE.get(n, "")), 512)
		b.is_cut = n in cut
		b.custom_minimum_size = Vector2(74, 250)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = b.is_cut or status != "acik"
		b.pressed.connect(func() -> void:
			cut.append(n)
			b.is_cut = true
			b.disabled = true
			b.queue_redraw()
			_play("pense")
			action.emit({"islem": "kes", "renk": n}))
		col.add_child(b)
		var l := UI.label(n, 13, Color(0.85, 0.87, 0.9), true)
		l.custom_minimum_size.x = 74
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		col.add_child(l)
		h.add_child(col)
	return h


# ---------- fişler ----------

func _plugs_ui() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	for n in plugs:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(140, 66)
		var st := UI.flat(color_of(n).darkened(0.1), Color.WHITE if _held_plug == n else color_of(n).darkened(0.5), 33)
		st.set_border_width_all(5 if _held_plug == n else 3)
		for k in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(k, st)
		var plug_tex: Texture2D = UI.texture("fis", 256)
		if plug_tex:
			var st2 := StyleBoxEmpty.new()
			for k in ["normal", "hover", "pressed", "disabled"]:
				b.add_theme_stylebox_override(k, st2)
			b.icon = plug_tex
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 54)
			b.add_theme_color_override("icon_normal_color", color_of(n))
			b.add_theme_color_override("icon_pressed_color", color_of(n))
			b.add_theme_color_override("icon_hover_color", color_of(n).lightened(0.2))
			b.add_theme_color_override("icon_disabled_color", color_of(n).darkened(0.3))
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
			if _held_plug == n:
				b.modulate = Color(1.3, 1.3, 1.3)
		var lbl: String = n + ("  → " + str(plugged[n]) if plugged.has(n) else "")
		b.text = lbl
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", Color.BLACK if color_of(n).get_luminance() > 0.55 else Color.WHITE)
		b.add_theme_color_override("font_disabled_color", Color.BLACK if color_of(n).get_luminance() > 0.55 else Color.WHITE)
		b.disabled = plugged.has(n) or status != "acik"
		b.pressed.connect(func() -> void:
			_held_plug = n
			_play("sec")
			_build())
		left.add_child(b)
	h.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	for so in ["A", "B", "C", "D"]:
		var s := Button.new()
		s.focus_mode = Control.FOCUS_NONE
		s.custom_minimum_size = Vector2(110, 52)
		var used: bool = so in plugged.values()
		var st: StyleBox = UI.sbox("soket", 120, 0.3, Vector4(10, 6, 10, 6))
		if st == null:
			var fs := UI.flat(Color("#0e1013"), Color("#ffcf3a") if _held_plug != "" and not used else Color("#4a505a"), 10)
			fs.set_border_width_all(3)
			st = fs
		elif _held_plug != "" and not used:
			s.modulate = Color(1.25, 1.15, 0.7)
		for k in ["normal", "hover", "pressed", "disabled"]:
			s.add_theme_stylebox_override(k, st)
		s.text = "●  " + so
		s.add_theme_font_size_override("font_size", 22)
		s.disabled = used or _held_plug == "" or status != "acik"
		s.pressed.connect(func() -> void:
			var n := _held_plug
			plugged[n] = so
			_held_plug = ""
			_play("fis")
			action.emit({"islem": "tak", "renk": n, "soket": so})
			_build())
		right.add_child(s)
	h.add_child(right)
	return h


# ---------- şalterler ----------

class Lever extends Button:
	var on := false
	var no := 1

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var img: Texture2D = UI.texture("salter_acik" if on else "salter_kapali", 256)
		if img:
			var ts := img.get_size()
			var sc := minf(w / ts.x, (h - 24) / ts.y)
			draw_texture_rect(img, Rect2(Vector2((w - ts.x * sc) / 2, 0), ts * sc), false)
			draw_string(get_theme_default_font(), Vector2(w / 2 - 6, h + 12), str(no), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
			return
		draw_rect(Rect2(w * 0.2, 6, w * 0.6, h - 34), Color("#111317"))
		draw_rect(Rect2(w * 0.2, 6, w * 0.6, h - 34), Color("#4a505a"), false, 2)
		var ky := 10.0 if on else h - 34 - 34
		draw_rect(Rect2(w * 0.24, ky, w * 0.52, 30), Color("#5be37d") if on else Color("#c9ccd2"))
		draw_circle(Vector2(w / 2, h - 12), 6, Color("#5be37d") if on else Color("#3a3f47"))
		draw_string(get_theme_default_font(), Vector2(w / 2 - 6, h + 12), str(no), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


func _switches_ui() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.custom_minimum_size.y = 150
	for i in 4:
		var b := Lever.new()
		b.no = i + 1
		b.on = (i + 1) in switches
		b.custom_minimum_size = Vector2(56, 120)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = b.on or status != "acik"
		b.pressed.connect(func() -> void:
			switches.append(b.no)
			b.on = true
			b.disabled = true
			b.queue_redraw()
			_play("salter")
			action.emit({"islem": "salter", "no": b.no}))
		h.add_child(b)
	return h


# ---------- tuş takımı ----------

func _keypad_ui() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var disp := _lcd(_keys if _keys != "" else "----", 30)
	_key_display = disp.get_child(0)
	v.add_child(disp)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for k in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "SİL", "0", "ONAY"]:
		var b := Button.new()
		b.text = k
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(80, 44)
		var st: StyleBox = UI.sbox("tus", 90, 0.3, Vector4(8, 4, 8, 4))
		if st == null:
			st = UI.flat(Color("#5be37d").darkened(0.5) if k == "ONAY" else (Color("#7a2a2a") if k == "SİL" else Color("#3a3f47")), Color("#15171b"), 8)
		elif k == "ONAY":
			b.modulate = Color(0.7, 1.3, 0.75)
		elif k == "SİL":
			b.modulate = Color(1.3, 0.7, 0.7)
		for s in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(s, st)
		b.add_theme_font_size_override("font_size", 20)
		b.disabled = status != "acik"
		b.pressed.connect(func() -> void:
			_play("tik_ui", -6.0)
			if k == "SİL":
				_keys = ""
			elif k == "ONAY":
				if _keys.length() == 4:
					action.emit({"islem": "kod", "kod": _keys})
				_keys = ""
			elif _keys.length() < 4:
				_keys += k
			_key_display.text = _keys if _keys != "" else "----")
		grid.add_child(b)
	v.add_child(grid)
	return v


# ---------- durum ----------

func _tex_rect(name: String, px: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = UI.texture(name, int(px * 2))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(px, px)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func set_result(olay: String, adim: int) -> void:
	done_steps = adim
	match olay:
		"tamir":
			status = "tamir"
		"yanlis", "kilit":
			status = "kilit"
			_spark_burst()
	_build()
	if status != "acik":
		var badge := "onay" if status == "tamir" else "carpi"
		if UI.has(badge):
			var b := _tex_rect(badge, 220)
			b.set_anchors_preset(Control.PRESET_CENTER)
			b.position = -b.custom_minimum_size / 2.0
			add_child(b)
			b.pivot_offset = b.custom_minimum_size / 2.0
			b.scale = Vector2.ONE * 0.3
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_interval(1.0)
			tw.tween_property(b, "modulate:a", 0.0, 0.4)
			tw.tween_callback(b.queue_free)


# Yanlış adımda ekranın ortasında kıvılcım patlaması (görsel varsa).
func _spark_burst() -> void:
	if not UI.has("kivilcim"):
		return
	var sp := _tex_rect("kivilcim", 420)
	sp.set_anchors_preset(Control.PRESET_CENTER)
	sp.position = -sp.custom_minimum_size / 2.0
	add_child(sp)
	sp.pivot_offset = sp.custom_minimum_size / 2.0
	var tw := sp.create_tween()
	for i in 4:
		tw.tween_property(sp, "modulate:a", 1.0 if i % 2 == 0 else 0.3, 0.06)
		tw.parallel().tween_property(sp, "rotation", randf_range(-0.3, 0.3), 0.06)
	tw.tween_property(sp, "modulate:a", 0.0, 0.3)
	tw.tween_callback(sp.queue_free)


func _refresh_status() -> void:
	for c in _leds.get_children():
		c.queue_free()
	for i in steps:
		var on := i < done_steps
		var led_tex: Texture2D = UI.texture("led_acik" if on else "led_kapali", 96)
		if led_tex:
			var tr := TextureRect.new()
			tr.texture = led_tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(34, 34)
			if status == "kilit":
				tr.modulate = Color(1.6, 0.35, 0.35)
			_leds.add_child(tr)
			continue
		var led := Panel.new()
		led.custom_minimum_size = Vector2(26, 26)
		var st := UI.flat(Color("#5be37d") if on else Color("#30343b"), Color("#5be37d").lightened(0.3) if on else Color("#15171b"), 13)
		if status == "kilit":
			st.bg_color = Color("#d62828")
		led.add_theme_stylebox_override("panel", st)
		_leds.add_child(led)
	match status:
		"tamir":
			_status_label.text = "✓ KUTU ONARILDI · IŞIKLAR GERİ GELDİ"
			_status_label.add_theme_color_override("font_color", Color("#5be37d"))
		"kilit":
			_status_label.text = "KISA DEVRE! KUTU KİLİTLENDİ"
			_status_label.add_theme_color_override("font_color", Color("#ff4a4a"))
		_:
			_status_label.text = "Adım %d / %d · talimat başkasının tahtasında, telefonla öğren!" % [done_steps + 1, steps]
			_status_label.add_theme_color_override("font_color", Color(0.85, 0.87, 0.92))


func _play(n: String, vol := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


class Screws extends Control:
	func _draw() -> void:
		for p in [Vector2(14, 14), Vector2(size.x - 14, 14), Vector2(14, size.y - 14), Vector2(size.x - 14, size.y - 14)]:
			draw_circle(p, 8, Color("#9aa0a8"))
			draw_line(p - Vector2(5, 0), p + Vector2(5, 0), Color("#4a4f57"), 2)
