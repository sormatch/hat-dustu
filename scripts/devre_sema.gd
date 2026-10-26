# Kısa Devre: tahtadaki şema (başka birinin kutusu için), tebeşirle çizilmiş görsel liste.
# Her satır: o renkte tebeşirle kablo kıvrımı + renk adı  ->  sembol çizimi ya da daire içinde numara.
# Okuyan kişi telefonda "kırmızı yıldıza, mavi üç numaraya" diye anlatır.
extends Control

signal closed

const UI := preload("res://scripts/ui.gd")
const DevreBox := preload("res://scripts/devre_box.gd")
const CHALK_FONT := preload("res://assets/fonts/CabinSketch-Bold.ttf")
const CHALK := Color(0.95, 0.96, 0.9)
const W := 1080.0
const H := 680.0

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
	# toz: çizgi kenarında küçük noktalar
	for k in pts.size() * 2:
		var p := pts[rng.randi() % pts.size()]
		draw_circle(p + Vector2(rng.randf_range(-w, w), rng.randf_range(-w, w)), rng.randf_range(0.6, 1.4), Color(col, 0.25))


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
	var title := "%s İÇİN" % kimin.replace("i", "İ").replace("ı", "I").to_upper()
	var ts := CHALK_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 60)
	draw_string(CHALK_FONT, Vector2(W / 2 - ts.x / 2, 128), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color(CHALK, 0.95))
	_chalk_line(PackedVector2Array([Vector2(W / 2 - ts.x / 2, 146), Vector2(W / 2 + ts.x / 2, 142)]), CHALK, 4.0)
	# satırlar
	var n := rows.size()
	for i in n:
		var row: Array = rows[i]
		var y := 222.0 + i * 92.0
		var col := DevreBox.color_of(str(row[0]))
		var ccol := col.lightened(0.4)
		# kablo kıvrımı (o renkte tebeşir)
		var wave := PackedVector2Array()
		for k in 13:
			var x := 190.0 + k * 13.0
			wave.append(Vector2(x, y + sin(k * 0.9) * 9.0))
		_chalk_line(wave, ccol, 14.0)
		draw_string(CHALK_FONT, Vector2(375, y + 15), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(ccol, 0.95))
		# ok
		_chalk_line(PackedVector2Array([Vector2(610, y), Vector2(720, y)]), CHALK, 6.0)
		_chalk_line(PackedVector2Array([Vector2(698, y - 16), Vector2(722, y), Vector2(698, y + 16)]), CHALK, 6.0)
		# hedef: sembol ya da numara
		var tc := Vector2(800, y)
		if str(row[1]) == "N":
			var circle := PackedVector2Array()
			for k in 33:
				circle.append(tc + Vector2(cos(k * TAU / 32), sin(k * TAU / 32)) * 34.0)
			_chalk_line(circle, CHALK, 5.0)
			var num := str(int(row[2])) if typeof(row[2]) in [TYPE_INT, TYPE_FLOAT] else str(row[2])
			var nsz := CHALK_FONT.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 54)
			draw_string(CHALK_FONT, tc + Vector2(-nsz.x / 2, 19), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, CHALK)
			draw_string(CHALK_FONT, tc + Vector2(48, 14), "NO", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(CHALK, 0.7))
		else:
			_chalk_shape(tc, str(row[2]), 30.0)
	# alt: telefon ipucu
	var ic := UI.icon_texture("telefon", 44)
	var hint := "ARA VE OKU"
	var hs := CHALK_FONT.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 32)
	var hx := W / 2 - (hs.x + 56) / 2
	if ic:
		draw_texture_rect(ic, Rect2(Vector2(hx, 530), Vector2(44, 44)), false, Color(1, 1, 1, 0.85))
	draw_string(CHALK_FONT, Vector2(hx + 56, 564), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(CHALK, 0.75 + 0.2 * sin(_t * 3.0)))
	# kapat (tebeşir çarpı)
	var cp := Vector2(W - 20, 20)
	draw_circle(cp, 30, Color(0, 0, 0, 0.55))
	_chalk_line(PackedVector2Array([cp - Vector2(12, 12), cp + Vector2(12, 12)]), CHALK, 5.0)
	_chalk_line(PackedVector2Array([cp + Vector2(-12, 12), cp + Vector2(12, -12)]), CHALK, 5.0)
