# Kısa Devre: tahtadaki şema (başka birinin kutusu için), tebeşirle çizilmiş görsel liste.
# Her satır: o renkte tebeşirle kablo kıvrımı + renk adı  ->  sembol çizimi ya da daire içinde numara.
# Okuyan kişi telefonda "kırmızı yıldıza, mavi üç numaraya" diye anlatır.
extends Control

signal closed

const UI := preload("res://scripts/ui.gd")
const DevreBox := preload("res://scripts/devre_box.gd")
const Dil := preload("res://scripts/dil.gd")
const CHALK_FONT := preload("res://assets/fonts/CabinSketch-Bold.ttf")
const CHALK := Color(0.95, 0.96, 0.9)
const W := 1080.0
const H := 680.0
const WAVE_W := 156.0  # şemadaki kablo kıvrımının boyu
const ARROW_W := 108.0

var kimin := "?"  # şema kimin kutusu için
var rows: Array = []  # [renk, "S"|"N", sembol|numara]
var _t := 0.0
var _xf := Transform2D.IDENTITY
var _board: Texture2D
var _seed := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_board = load("res://assets/ui/chalkboard.png")
	_seed = randi()


func _process(delta: float) -> void:
	_t += delta
	var sc := minf(size.x / (W + 40.0), size.y / (H + 20.0))
	_xf = Transform2D(0.0, Vector2(sc, sc), 0.0, (size - Vector2(W, H) * sc) / 2.0)
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = _xf.affine_inverse() * e.position
		if p.distance_to(Vector2(W - 20, 20)) < 50.0 or not Rect2(Vector2.ZERO, Vector2(W, H)).has_point(p):
			closed.emit()
		accept_event()


# Tebeşir çizgisi: birkaç ince, titrek, yarı saydam çizginin üst üste binmesi.
func _chalk_line(pts: PackedVector2Array, col: Color, w: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + int(pts[0].x * 7 + pts[0].y * 13)
	for pass_i in 4:
		var q := PackedVector2Array()
		for p in pts:
			q.append(p + Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6)))
		draw_polyline(q, Color(col, 0.42), w * rng.randf_range(0.5, 0.9), true)
	# toz: çizgi kenarında küçük noktalar. Hepsi tek üçgen dizisinde, _draw sonunda bir çizim çağrısıyla
	# çizilir (her nokta ayrı draw_circle iken şema ~300 çizim çağrısı tutuyordu)
	for k in pts.size() * 2:
		var p := pts[rng.randi() % pts.size()]
		_dot(p + Vector2(rng.randf_range(-w, w), rng.randf_range(-w, w)), rng.randf_range(0.6, 1.4), Color(col, 0.25))


var _dot_pts := PackedVector2Array()
var _dot_cols := PackedColorArray()
var _dot_idx := PackedInt32Array()


func _dot(c: Vector2, r: float, col: Color) -> void:
	const SEG := 10
	var base := _dot_pts.size()
	_dot_pts.append(c)
	_dot_cols.append(col)
	for k in SEG:
		_dot_pts.append(c + Vector2(cos(k * TAU / SEG), sin(k * TAU / SEG)) * r)
		_dot_cols.append(col)
		_dot_idx.append_array([base, base + 1 + k, base + 1 + (k + 1) % SEG])


func _flush_dots() -> void:
	if not _dot_pts.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _dot_idx, _dot_pts, _dot_cols)
	_dot_pts = PackedVector2Array()
	_dot_cols = PackedColorArray()
	_dot_idx = PackedInt32Array()


func _chalk_shape(c: Vector2, kind: String, r: float) -> void:
	var pts := PackedVector2Array()
	match kind:
		"YILDIZ":
			for k in 11:
				var ang := -PI / 2 + k * PI / 5
				pts.append(c + Vector2(cos(ang), sin(ang)) * (r * 1.1 if k % 2 == 0 else r * 0.46))
		"ÜÇGEN":
			pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8), c + Vector2(0, -r)])
		"DAİRE":
			for k in 33:
				pts.append(c + Vector2(cos(k * TAU / 32), sin(k * TAU / 32)) * r * 0.9)
		"KARE":
			var h := r * 0.82
			pts = PackedVector2Array([c + Vector2(-h, -h), c + Vector2(h, -h), c + Vector2(h, h), c + Vector2(-h, h), c + Vector2(-h, -h)])
	_chalk_line(pts, CHALK, 7.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.03, 0.72))
	draw_set_transform_matrix(_xf)
	if _board:
		draw_texture_rect(_board, Rect2(Vector2(-40, -30), Vector2(W + 80, H + 60)), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Color("#2c4a35"))
	# başlık: kimin için
	var title := tr("%s İÇİN") % Dil.buyuk(kimin)
	var tfs := 60
	var ts := CHALK_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs)
	if ts.x > W - 220.0:  # uzun ad: başlık küçülür, çarpıya değmez
		tfs = int(tfs * (W - 220.0) / ts.x)
		ts = CHALK_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs)
	draw_string(CHALK_FONT, Vector2(W / 2 - ts.x / 2, 128), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(CHALK, 0.95))
	_chalk_line(PackedVector2Array([Vector2(W / 2 - ts.x / 2, 146), Vector2(W / 2 + ts.x / 2, 142)]), CHALK, 4.0)
	# satırlar: blok (kıvrım + ad + ok + hedef) ölçülüp tahtanın tam ortasına konur. "NO" dairenin altında
	# durur (eskiden sağda sarkıyordu, ad sütunu da sabit genişlikteydi: blok sağa kaymış görünüyordu).
	# Satır aralığı satır sayısına göre daralır; az satırda blok dikeyde de ortalanır.
	var n := rows.size()
	var fs := 44
	var name_w := 0.0
	for row in rows:
		name_w = maxf(name_w, CHALK_FONT.get_string_size(tr(str(row[0])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	if name_w > 300.0:  # çok uzun renk adı: yazı küçülür, blok tahtadan taşmaz
		fs = int(fs * 300.0 / name_w)
		name_w = 300.0
	var tr_r := 34.0 if n <= 4 else 27.0  # hedef dairesinin yarıçapı (5 satırda küçük: "NO" alttaki satıra değmesin)
	var block := WAVE_W + 30.0 + name_w + 46.0 + ARROW_W + 34.0 + tr_r * 2.0
	var x0 := W / 2.0 - block / 2.0
	var name_x := x0 + WAVE_W + 30.0
	var arrow_x := name_x + name_w + 46.0
	var tx := arrow_x + ARROW_W + 34.0 + tr_r
	var step := minf(96.0, (504.0 - 206.0) / maxf(1.0, n - 1.0))
	var y_top := 206.0 + maxf(0.0, 96.0 * (4 - n)) / 2.0
	for i in n:
		var row: Array = rows[i]
		var y := y_top + i * step
		var col := DevreBox.color_of(str(row[0]))
		var ccol := col.lightened(0.4)
		# kablo kıvrımı (o renkte tebeşir)
		var wave := PackedVector2Array()
		for k in 13:
			wave.append(Vector2(x0 + k * WAVE_W / 12.0, y + sin(k * 0.9) * 9.0))
		_chalk_line(wave, ccol, 14.0)
		draw_string(CHALK_FONT, Vector2(name_x, y + fs * 0.34), tr(str(row[0])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ccol, 0.95))
		# ok
		_chalk_line(PackedVector2Array([Vector2(arrow_x, y), Vector2(arrow_x + ARROW_W, y)]), CHALK, 6.0)
		_chalk_line(PackedVector2Array([Vector2(arrow_x + ARROW_W - 24, y - 16), Vector2(arrow_x + ARROW_W + 2, y), Vector2(arrow_x + ARROW_W - 24, y + 16)]), CHALK, 6.0)
		# hedef: sembol ya da numara
		var tc := Vector2(tx, y)
		if str(row[1]) == "N":
			tc.y -= 6.0  # altındaki "NO" için biraz yukarı
			var circle := PackedVector2Array()
			for k in 33:
				circle.append(tc + Vector2(cos(k * TAU / 32), sin(k * TAU / 32)) * tr_r)
			_chalk_line(circle, CHALK, 5.0)
			var num := str(int(row[2])) if typeof(row[2]) in [TYPE_INT, TYPE_FLOAT] else str(row[2])
			var nfs := int(tr_r * 1.55)
			var nsz := CHALK_FONT.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs)
			draw_string(CHALK_FONT, tc + Vector2(-nsz.x / 2, nfs * 0.35), num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, CHALK)
			var no := tr("NO")
			var no_fs := 20 if n <= 4 else 17
			var nos := CHALK_FONT.get_string_size(no, HORIZONTAL_ALIGNMENT_LEFT, -1, no_fs)
			draw_string(CHALK_FONT, tc + Vector2(-nos.x / 2, tr_r + no_fs + 1.0), no, HORIZONTAL_ALIGNMENT_LEFT, -1, no_fs, Color(CHALK, 0.7))
		else:
			_chalk_shape(tc, str(row[2]), tr_r * 0.88)
	# alt: telefon ipucu (ikon + yazı birlikte ortada)
	var ic := UI.icon_texture("telefon", 44)
	var hint := tr("ARA VE OKU")
	var hs := CHALK_FONT.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 32)
	var icon_w := 56.0 if ic else 0.0
	var hx := W / 2 - (hs.x + icon_w) / 2
	var hy := 580.0
	if ic:
		draw_texture_rect(ic, Rect2(Vector2(hx, hy - 34), Vector2(44, 44)), false, Color(1, 1, 1, 0.85))
	draw_string(CHALK_FONT, Vector2(hx + icon_w, hy), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(CHALK, 0.75 + 0.2 * sin(_t * 3.0)))
	# kapat (tebeşir çarpı)
	var cp := Vector2(W - 20, 20)
	draw_circle(cp, 30, Color(0, 0, 0, 0.55))
	_chalk_line(PackedVector2Array([cp - Vector2(12, 12), cp + Vector2(12, 12)]), CHALK, 5.0)
	_chalk_line(PackedVector2Array([cp + Vector2(-12, 12), cp + Vector2(12, -12)]), CHALK, 5.0)
	_flush_dots()
