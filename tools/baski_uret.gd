# Bir kerelik araç: kıyafet baskı dokusunu üretir (assets/govde/kiyafet/baski.png, saydam, 1024x512).
#   üst şerit (0-256): sırta "1337"   alt sol (0-512 x 256-512): göğüs etiketi "No.1337"   alt sağ: gardiyan rozeti (kalkan + yıldız)
# Kıyafet gölgelendiricisi (model_body.gd CLOTH_SHADER) bu bölgeleri bağlama pozunda sırta/göğse yansıtır.
# Çalıştırma (görüntü gerekir, --headless değil): Godot --path . --script res://tools/baski_uret.gd
extends SceneTree

const FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")


func _init() -> void:
	_run.call_deferred()


func _label(sv: Node, text: String, rect: Rect2, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	sv.add_child(l)


func _run() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(1024, 512)
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	_label(sv, "1337", Rect2(0, 0, 1024, 256), 230)
	_label(sv, "No.1337", Rect2(0, 256, 512, 256), 118)
	# rozet: kalkan + içinde yıldız (yazısız: her dilde aynı)
	var c := Vector2(768, 384)
	var shield := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		var x := lerpf(-1.0, 1.0, t)
		shield.append(c + Vector2(x * 92, -100 + 12 * sin(t * PI)))
	for i in 25:
		var t := i / 24.0
		var x := lerpf(1.0, -1.0, t)
		var y := 10.0 + (1.0 - x * x) * 0.0 + 108.0 * pow(1.0 - absf(x), 0.55)
		shield.append(c + Vector2(x * 92, y))
	var p := Polygon2D.new()
	p.polygon = shield
	p.color = Color.WHITE
	sv.add_child(p)
	var inner := PackedVector2Array()
	for v in shield:
		inner.append(c + (v - c) * 0.8)
	var p2 := Polygon2D.new()
	p2.polygon = inner
	p2.color = Color(0.8, 0.8, 0.8)
	sv.add_child(p2)
	var star := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		star.append(c + Vector2(cos(a), sin(a)) * (52.0 if i % 2 == 0 else 22.0) + Vector2(0, 2))
	var p3 := Polygon2D.new()
	p3.polygon = star
	p3.color = Color(0.12, 0.12, 0.12)  # yıldız koyu: gölgelendirici baskı rengiyle çarpar
	sv.add_child(p3)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	print("baski -> ", img.save_png("res://assets/govde/kiyafet/baski.png"))
	quit()
