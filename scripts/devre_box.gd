# Kısa Devre: sigorta kutusunun yakın çekimi. Solda 4 renkli kablo, sağda 4 sembollü uç (yıldız, üçgen,
# daire, kare). Kabloyu parmakla sürükleyip doğru sembole bırak (ya da önce kabloya sonra sembole dokun).
# Doğru bağlantı yeşil parlar ve içinden akım akar; yanlış bağlantı kıvılcım saçar, kutu kilitlenir.
# Hangi kablonun nereye gideceği başkasının tahtasında yazar; sonuç sunucudan gelir (set_result).
extends Control

signal action(v: Dictionary)
signal closed

const UI := preload("res://scripts/ui.gd")
const COLORS := {
	"KIRMIZI": "#e03131", "MAVİ": "#2f7bf5", "SARI": "#f5c518", "YEŞİL": "#2fb344", "MOR": "#9b4dca", "TURUNCU": "#f08c00",
}
const LCD := Color("#7dff9f")

var code := "K7"
var wires: Array = []  # renkler (soldan, yukarıdan aşağı)
var symbols: Array = []  # semboller (sağda, yukarıdan aşağı)
var steps := 4
var done_steps := 0
var status := "acik"  # acik, tamir, kilit
var connected := {}  # renk -> sembol (sunucunun onayladığı bağlantılar)

var _body: VBoxContainer
var _leds: HBoxContainer
var _status_label: Label
var _board: WireBoard


static func color_of(n: String) -> Color:
	return Color(COLORS.get(n, "#888888"))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := PanelContainer.new()
	var tex_st := UI.sbox("sigorta_bg", 520, 0.12, Vector4(48, 40, 48, 40))
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#2b2f35")
	st.border_color = Color("#5a6069")
	st.set_border_width_all(6)
	st.set_corner_radius_all(14)
	st.content_margin_left = 30
	st.content_margin_right = 30
	st.content_margin_top = 20
	st.content_margin_bottom = 22
	box.add_theme_stylebox_override("panel", tex_st if tex_st else st)
	box.custom_minimum_size = Vector2(1080, 0)
	center.add_child(box)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	box.add_child(_body)
	# üst şerit: uyarı, kod ekranı, ilerleme ışıkları, kapat
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var warn_row := HBoxContainer.new()
	warn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warn_row.add_theme_constant_override("separation", 10)
	if UI.has("uyari"):
		warn_row.add_child(_tex_rect("uyari", 46))
	warn_row.add_child(UI.title("SİGORTA KUTUSU", 26, Color("#ffcf3a")))
	top.add_child(warn_row)
	top.add_child(_lcd("KUTU  " + code, 30))
	_leds = HBoxContainer.new()
	_leds.add_theme_constant_override("separation", 6)
	top.add_child(_leds)
	var close := UI.button("KAPAT", "normal", 48, 18, "", 130)
	close.pressed.connect(func() -> void: closed.emit())
	top.add_child(close)
	_body.add_child(top)
	_status_label = UI.title("", 24, Color.WHITE, true)
	_body.add_child(_status_label)
	_board = WireBoard.new()
	_board.owner_box = self
	_board.custom_minimum_size = Vector2(0, 430)
	_body.add_child(_board)
	_refresh_status()


func _lcd(text: String, size: int) -> PanelContainer:
	var p := PanelContainer.new()
	var lcd_tex := UI.sbox("lcd", 90, 0.25, Vector4(18, 6, 18, 6))
	if lcd_tex:
		p.add_theme_stylebox_override("panel", lcd_tex)
	else:
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#07170c")
		st.border_color = Color("#14361d")
		st.set_border_width_all(3)
		st.set_corner_radius_all(6)
		st.content_margin_left = 14
		st.content_margin_right = 14
		p.add_theme_stylebox_override("panel", st)
	p.add_child(UI.title(text, size, LCD, true))
	return p


func _tex_rect(name: String, px: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = UI.texture(name, int(px * 2))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(px, px)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


# Kablo bırakıldı: sunucuya sor; sonuç gelene kadar kablo "bekliyor" çizilir.
func _try_connect(renk: String, sembol: String) -> void:
	if status != "acik" or connected.has(renk) or sembol in connected.values():
		return
	_board.pending = [renk, sembol]
	_board.queue_redraw()
	_play("fis")
	action.emit({"islem": "bagla", "renk": renk, "sembol": sembol})


# Sunucunun cevabı: adim (doğru bağlantı), tamir (hepsi doğru), yanlis/kilit (kısa devre).
func set_result(olay: String, adim: int, renk := "", sembol := "") -> void:
	done_steps = adim
	if renk == "" and _board.pending.size() == 2:
		renk = _board.pending[0]
		sembol = _board.pending[1]
	match olay:
		"adim", "tamir":
			if renk != "":
				connected[renk] = sembol
				_board.pulse(renk)
			if olay == "tamir":
				status = "tamir"
		"yanlis", "kilit":
			if status != "kilit" and renk != "":
				_board.wrong = [renk, sembol]
			status = "kilit"
			_spark_burst()
	_board.pending = []
	_board.queue_redraw()
	_refresh_status()
	if olay in ["tamir", "yanlis"]:
		var badge := "onay" if olay == "tamir" else "carpi"
		if UI.has(badge):
			var b := _tex_rect(badge, 200)
			b.set_anchors_preset(Control.PRESET_CENTER)
			b.position = -b.custom_minimum_size / 2.0
			add_child(b)
			b.pivot_offset = b.custom_minimum_size / 2.0
			b.scale = Vector2.ONE * 0.3
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.9)
			tw.tween_property(b, "modulate:a", 0.0, 0.4)
			tw.tween_callback(b.queue_free)


func _spark_burst() -> void:
	if not UI.has("kivilcim"):
		return
	var sp := _tex_rect("kivilcim", 380)
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
			tr.custom_minimum_size = Vector2(32, 32)
			if status == "kilit":
				tr.modulate = Color(1.6, 0.35, 0.35)
			_leds.add_child(tr)
		else:
			var led := Panel.new()
			led.custom_minimum_size = Vector2(24, 24)
			led.add_theme_stylebox_override("panel", UI.flat(Color("#5be37d") if on else Color("#30343b"), Color("#15171b"), 12))
			_leds.add_child(led)
	match status:
		"tamir":
			_status_label.text = "KUTU ONARILDI! +1 · IŞIKLAR GERİ GELDİ"
			_status_label.add_theme_color_override("font_color", Color("#5be37d"))
		"kilit":
			_status_label.text = "KISA DEVRE! KUTU KİLİTLENDİ · -1"
			_status_label.add_theme_color_override("font_color", Color("#ff4a4a"))
		_:
			_status_label.text = "Kabloyu sürükle, doğru sembole bırak · %d / %d bağlandı" % [done_steps, steps]
			_status_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95))


func _play(n: String, vol := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# ---------- kablo tahtası: çizim ve sürükle-bırak ----------

class WireBoard extends Control:
	var owner_box: Control
	var pending: Array = []  # [renk, sembol] sunucu cevabı bekleniyor
	var wrong: Array = []  # [renk, sembol] yanlış bağlantı (kırmızı)
	var _drag := ""  # sürüklenen kablonun rengi
	var _picked := ""  # dokun-dokun: seçili kablo
	var _mouse := Vector2.ZERO
	var _t := 0.0
	var _pulses := {}  # renk -> akım animasyonu başlangıcı

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	static func _col(n: String) -> Color:
		return Color(COLORS.get(n, "#888888"))

	func pulse(renk: String) -> void:
		_pulses[renk] = _t

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _rows() -> int:
		return maxi(1, owner_box.wires.size())

	func _left(i: int) -> Vector2:
		return Vector2(size.x * 0.2, size.y * (i + 0.5) / _rows())

	func _right(i: int) -> Vector2:
		return Vector2(size.x * 0.74, size.y * (i + 0.5) / maxi(1, owner_box.symbols.size()))

	func _wire_at(p: Vector2) -> String:
		for i in owner_box.wires.size():
			if p.distance_to(_left(i)) < 60.0:
				return owner_box.wires[i]
		return ""

	func _symbol_at(p: Vector2) -> String:
		for i in owner_box.symbols.size():
			if Rect2(_right(i) + Vector2(-90, -44), Vector2(300, 88)).has_point(p):
				return owner_box.symbols[i]
		return ""

	func _gui_input(e: InputEvent) -> void:
		if owner_box.status != "acik":
			return
		if e is InputEventMouseMotion:
			_mouse = e.position
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_mouse = e.position
			if e.pressed:
				var w := _wire_at(e.position)
				if w != "" and not owner_box.connected.has(w) and pending.is_empty():
					_drag = w
					_picked = w
				elif _picked != "":
					var s := _symbol_at(e.position)
					if s != "":
						owner_box._try_connect(_picked, s)
						_picked = ""
			elif _drag != "":
				var s2 := _symbol_at(e.position)
				if s2 != "":
					owner_box._try_connect(_drag, s2)
					_picked = ""
				_drag = ""
			accept_event()

	# kalın plastik kılıflı kablo: koyu dış hat, renkli gövde, parlak çizgi
	func _cable(a: Vector2, b: Vector2, col: Color, glow := 0.0, sag := 18.0) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var c1 := a + Vector2((b.x - a.x) * 0.45, 0)
		var c2 := b - Vector2((b.x - a.x) * 0.45, 0)
		for k in 25:
			var t := k / 24.0
			var u := 1.0 - t
			pts.append(u * u * u * a + 3 * u * u * t * c1 + 3 * u * t * t * c2 + t * t * t * b + Vector2(0, sin(t * PI) * sag))
		if glow > 0.0:
			draw_polyline(pts, Color(col, 0.25 * glow), 30, true)
		draw_polyline(pts, col.darkened(0.55), 20, true)
		draw_polyline(pts, col, 14, true)
		var hl := PackedVector2Array()
		for q in pts:
			hl.append(q + Vector2(0, -4))
		draw_polyline(hl, col.lightened(0.5), 3, true)
		return pts

	func _symbol(c: Vector2, kind: String, r: float, col: Color) -> void:
		match kind:
			"YILDIZ":
				var pts := PackedVector2Array()
				for k in 10:
					var ang := -PI / 2 + k * PI / 5
					pts.append(c + Vector2(cos(ang), sin(ang)) * (r if k % 2 == 0 else r * 0.45))
				draw_colored_polygon(pts, col)
			"ÜÇGEN":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.95, r * 0.7), c + Vector2(-r * 0.95, r * 0.7)]), col)
			"DAİRE":
				draw_circle(c, r * 0.85, col)
			"KARE":
				draw_rect(Rect2(c - Vector2(r, r) * 0.75, Vector2(r, r) * 1.5), col)

	func _draw() -> void:
		var font := get_theme_default_font()
		var wires: Array = owner_box.wires
		var syms: Array = owner_box.symbols
		var locked: bool = owner_box.status == "kilit"
		# arka plan: koyu metal levha ve kanal
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.1, 0.85))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.37, 0.4, 0.6), false, 2.0)
		# sağdaki uçlar: metal plaka, parlayan sembol, adı
		for i in syms.size():
			var p := _right(i)
			var plate := Rect2(p + Vector2(-70, -40), Vector2(280, 80))
			var used: bool = syms[i] in owner_box.connected.values()
			draw_rect(plate, Color("#1b1e22"))
			draw_rect(plate, Color("#5a6069"), false, 3.0)
			for sc in [plate.position + Vector2(10, 10), plate.position + Vector2(plate.size.x - 10, 10), plate.end - Vector2(10, 10), Vector2(plate.position.x + 10, plate.end.y - 10)]:
				draw_circle(sc, 4, Color("#8a9099"))
			var sc_col := Color("#5be37d") if used else Color(0.9, 0.93, 1.0)
			if wrong.size() == 2 and wrong[1] == syms[i]:
				sc_col = Color("#ff4a4a")
			draw_circle(p + Vector2(-30, 0), 22, Color(0.02, 0.02, 0.03))
			draw_circle(p + Vector2(-30, 0), 22, Color("#8a9099"), false, 3.0)
			_symbol(p + Vector2(28, 0), syms[i], 24, sc_col)
			draw_string(font, p + Vector2(66, 9), str(syms[i]), HORIZONTAL_ALIGNMENT_LEFT, 140, 24, sc_col)
		# bağlanmış kablolar
		for i in wires.size():
			var w: String = wires[i]
			var col: Color = _col(w)
			var a := _left(i) + Vector2(40, 0)
			var target := ""
			var glow := 0.0
			if owner_box.connected.has(w):
				target = owner_box.connected[w]
				glow = 1.0
			elif pending.size() == 2 and pending[0] == w:
				target = pending[1]
			elif wrong.size() == 2 and wrong[0] == w:
				target = wrong[1]
				col = col.lerp(Color("#ff3030"), 0.4 + 0.3 * sin(_t * 18.0))
			if target != "":
				var j := syms.find(target)
				var pts := _cable(a, _right(j) + Vector2(-30, 0), col, glow)
				# akım: kablo boyunca kayan parlak noktalar
				if glow > 0.0:
					var since: float = _t - float(_pulses.get(w, -10.0))
					var n := 3
					for k in n:
						var f := fmod(_t * 0.6 + float(k) / n, 1.0)
						var q := pts[int(f * (pts.size() - 1))]
						draw_circle(q, 5.0 if since > 1.0 else 9.0, Color(1, 1, 0.8, 0.85))
		# sürüklenen kablo
		var active := _drag if _drag != "" else _picked
		if active != "" and not locked:
			var i2 := wires.find(active)
			var end := _mouse if _drag != "" else _left(i2) + Vector2(120, 0)
			_cable(_left(i2) + Vector2(40, 0), end, _col(active), 0.6)
			draw_circle(end, 12, Color("#c98a3a"))
		# soldaki kablo uçları: terminal bloğu, kısa kablo, bakır uç, renk adı
		for i in wires.size():
			var w2: String = wires[i]
			var p2 := _left(i)
			var col2: Color = _col(w2)
			var blk := Rect2(p2 + Vector2(-110, -34), Vector2(70, 68))
			draw_rect(blk, Color("#2a2e33"))
			draw_rect(blk, Color("#6a7079"), false, 3.0)
			draw_circle(blk.get_center(), 12, Color("#9aa0a8"))
			draw_line(blk.get_center() - Vector2(8, 0), blk.get_center() + Vector2(8, 0), Color("#4a4f57"), 3)
			if not owner_box.connected.has(w2) and w2 != active and not (wrong.size() == 2 and wrong[0] == w2) and not (pending.size() == 2 and pending[0] == w2):
				# bağlanmamış kablo: bloktan çıkan kıvrık kısa uç, ucu bakır
				_cable(p2 + Vector2(-40, 0), p2 + Vector2(40, 0), col2, 0.0, 5.0)
				draw_circle(p2 + Vector2(46, 0), 9, Color("#d08a3a"))
				if w2 == _picked:
					draw_arc(p2 + Vector2(10, 0), 52, 0, TAU, 32, Color(1, 1, 1, 0.5 + 0.4 * sin(_t * 8.0)), 3.0)
			else:
				draw_line(p2 + Vector2(-40, 0), p2 + Vector2(40, 0), col2.darkened(0.5), 20)
				draw_line(p2 + Vector2(-40, 0), p2 + Vector2(40, 0), col2, 14)
			draw_string(font, blk.position + Vector2(-20, 86), w2, HORIZONTAL_ALIGNMENT_CENTER, 110, 17, Color(0.85, 0.87, 0.9))
