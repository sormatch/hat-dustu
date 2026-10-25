# Arızalı neon tabela gibi yazı: kırmızı/camgöbeği kayma (glitch), titreyen parlaklık, etrafında çakan
# elektrik arkları. Kısa Devre açılışındaki "IŞIKLAR KESİLDİ" için.
extends Control

const UI := preload("res://scripts/ui.gd")

var text := "IŞIKLAR KESİLDİ"
var sub := ""
var font_size := 120
var color := Color("#ff2a2a")
var life := 3.2  # saniye; sonunda söner

var _t := 0.0
var _glitch := 0.0
var _arcs: Array = []
var _arc_t := 0.0
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UI.TITLE_FONT


func _process(delta: float) -> void:
	_t += delta
	if _t > life:
		queue_free()
		return
	# ara sıra sert kayma
	_glitch = maxf(0.0, _glitch - delta * 6.0)
	if randf() < delta * 7.0:
		_glitch = randf_range(0.4, 1.0)
	_arc_t -= delta
	if _arc_t <= 0.0:
		_arc_t = randf_range(0.05, 0.12)
		_make_arcs()
	queue_redraw()


func _make_arcs() -> void:
	_arcs.clear()
	var c := size / 2.0
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	for i in randi_range(1, 3):
		var a := c + Vector2(randf_range(-w * 0.55, w * 0.55), randf_range(-90, 70))
		var b := a + Vector2(randf_range(-180, 180), randf_range(-120, 120))
		var pts := PackedVector2Array([a])
		var n := 8
		for k in range(1, n):
			var p := a.lerp(b, float(k) / n) + Vector2(randf_range(-18, 18), randf_range(-18, 18))
			pts.append(p)
		pts.append(b)
		_arcs.append(pts)


func _draw() -> void:
	var fade := 1.0
	if _t < 0.12:
		fade = _t / 0.12
	elif _t > life - 0.5:
		fade = (life - _t) / 0.5
	# neon titremesi: kısa sönmeler
	var flick := 1.0
	if fmod(_t * 13.0, 1.0) < 0.08 or (_t > 0.4 and _t < 0.5):
		flick = 0.25
	var alpha := fade * flick
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2((size.x - sz.x) / 2.0, size.y / 2.0 + font_size * 0.3 - 30)
	var off := Vector2(randf_range(4, 14), randf_range(-3, 3)) * _glitch
	# kırmızı ışık hâlesi (kalın, saydam)
	for r in [16, 10]:
		draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, r, Color(color, 0.12 * alpha))
	# renk kayması: camgöbeği sola, kırmızı sağa
	draw_string(_font, pos - off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.2, 0.95, 1.0, 0.55 * alpha * (0.4 + _glitch)))
	draw_string(_font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.1, 0.15, 0.65 * alpha))
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10, Color(0, 0, 0, 0.85 * alpha))
	# beyaz-sıcak çekirdek ilk anda, sonra kırmızıya döner
	var core := Color.WHITE.lerp(color, clampf(_t / 0.35, 0.0, 1.0))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(core, alpha))
	# yatay tarama çizgisi (bozuk ekran)
	if _glitch > 0.5:
		var y := pos.y - randf_range(0, font_size * 0.8)
		draw_rect(Rect2(pos.x - 20, y, sz.x + 40, randf_range(3, 10)), Color(1, 1, 1, 0.25 * alpha))
	# elektrik arkları
	for pts in _arcs:
		draw_polyline(pts, Color(0.6, 0.85, 1.0, 0.35 * alpha), 7.0)
		draw_polyline(pts, Color(0.95, 0.98, 1.0, 0.95 * alpha), 2.0)
	if sub != "":
		var ss := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 36)
		var sp := Vector2((size.x - ss.x) / 2.0, pos.y + 70)
		draw_string_outline(_font, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, 8, Color(0, 0, 0, 0.8 * fade))
		draw_string(_font, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1.0, 0.85, 0.8, fade))
