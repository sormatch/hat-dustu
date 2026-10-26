# Efekt ve kir dokularını üretir (koddan, CC0 sayılır: dış kaynak yok).
#   assets/textures/efekt/duman.png  : 128x128 dikişsiz gürültü (duman, toz, ateş topu kenarları)
#   assets/textures/kir/kir_detay.png : 512x512 dikişsiz kir/küf lekeleri (malzemelerde dünya koordinatlı ikinci katman:
#                                       tekrarlayan doku desenini kırar; beyaz = değişmez, koyu = kirli)
# Kullanım: Godot --headless --path . --script res://tools/efekt_doku_uret.gd
extends SceneTree


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/textures/efekt")
	DirAccess.make_dir_recursive_absolute("res://assets/textures/kir")
	_duman()
	_kir()
	quit()


func _gurultu(sd: int, freq: float, oct: int, n: int) -> Image:
	var f := FastNoiseLite.new()
	f.seed = sd
	f.frequency = freq
	f.fractal_octaves = oct
	return f.get_seamless_image(n, n, false, false, 0.1, true)


func _duman() -> void:
	var a := _gurultu(11, 0.035, 4, 128)
	var b := _gurultu(29, 0.09, 3, 128)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := a.get_pixel(x, y).r * 0.72 + b.get_pixel(x, y).r * 0.28
			v = clampf((v - 0.5) * 1.35 + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.save_png("res://assets/textures/efekt/duman.png")
	print("duman.png")


func _kir() -> void:
	var n := 512
	var buyuk := _gurultu(3, 0.006, 5, n)  # büyük lekeler (birkaç metre)
	var orta := _gurultu(17, 0.022, 4, n)
	var kuf := _gurultu(41, 0.012, 3, n)  # küf / nem
	var ince := _gurultu(5, 0.18, 2, n)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var kirli := Color(0.6, 0.53, 0.44)
	var kufl := Color(0.74, 0.78, 0.66)
	for y in n:
		for x in n:
			var v := buyuk.get_pixel(x, y).r * 0.65 + orta.get_pixel(x, y).r * 0.35
			var d := smoothstep(0.46, 0.82, v) * 0.75
			var c := Color(1, 1, 1).lerp(kirli, d)
			var m := smoothstep(0.52, 0.92, kuf.get_pixel(x, y).r) * 0.4
			c = c.lerp(c * kufl, m)
			var s := (ince.get_pixel(x, y).r - 0.5) * 0.08
			c = Color(clampf(c.r + s, 0, 1), clampf(c.g + s, 0, 1), clampf(c.b + s, 0, 1), 1.0)
			img.set_pixel(x, y, c)
	img.save_png("res://assets/textures/kir/kir_detay.png")
	print("kir_detay.png")
