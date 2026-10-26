# Duvar/zemin lekeleri (decal) için dokuları üretir: kir, su birikintisi, çatlak, pas akıntısı, sarı-siyah uyarı şeridi.
# Hepsi bu betikle sıfırdan çizilir (kendi işimiz, CC0). Kullanım:
#   Godot --headless --path . --script res://tools/leke_uret.gd
extends SceneTree

const OUT := "res://assets/textures/leke/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_kir()
	_su()
	_catlak()
	_pas()
	_tehlike()
	_orm()
	print("leke dokuları yazıldı")
	quit()


func _noise(sd: int, freq: float, oct := 5) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = sd
	n.frequency = freq
	n.fractal_octaves = oct
	return n


# Koyu kir/is lekesi: kenara doğru sönen, gürültülü leke.
func _kir() -> void:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var n := _noise(3, 0.02)
	var n2 := _noise(9, 0.09, 3)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			var fall := clampf(1.0 - d, 0.0, 1.0)
			var v := (n.get_noise_2d(x, y) + 1.0) * 0.5
			var v2 := (n2.get_noise_2d(x, y) + 1.0) * 0.5
			var a := clampf((v * 1.4 - 0.35) * fall * 1.8, 0.0, 1.0) * (0.6 + v2 * 0.4)
			img.set_pixel(x, y, Color(0.09 + v2 * 0.05, 0.075 + v2 * 0.04, 0.05, a * 0.85))
	img.save_png(OUT + "kir.png")


# Su birikintisi: yumuşak kenarlı, düzensiz biçimli koyu leke (alfa = ıslak bölge).
func _su() -> void:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var n := _noise(21, 0.012, 3)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, (y - s / 2.0) * 1.3).length() / (s / 2.0)
			var v := n.get_noise_2d(x, y) * 0.55
			var a := clampf((0.85 - d + v) * 4.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.05, 0.05, 0.045, a))
	img.save_png(OUT + "su.png")


# Çatlak: dallanan ince koyu çizgiler.
func _catlak() -> void:
	var s := 512
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var stack: Array = [[Vector2(s * 0.5, s * 0.5), rng.randf() * TAU, 3.2, 0]]
	stack.append([Vector2(s * 0.5, s * 0.5), (stack[0][1] as float) + PI, 3.0, 0])
	while stack.size() > 0:
		var it: Array = stack.pop_back()
		var p: Vector2 = it[0]
		var ang: float = it[1]
		var wd: float = it[2]
		var depth: int = it[3]
		var steps := rng.randi_range(40, 90) if depth == 0 else rng.randi_range(15, 45)
		for i in steps:
			ang += rng.randf_range(-0.35, 0.35)
			p += Vector2(cos(ang), sin(ang)) * 2.5
			wd = maxf(0.6, wd * 0.985)
			if p.x < 4 or p.y < 4 or p.x > s - 5 or p.y > s - 5:
				break
			var fade := 1.0 - float(i) / steps * 0.5
			_dot(img, p, wd, Color(0.04, 0.035, 0.03, 0.95 * fade))
			_dot(img, p + Vector2(1.2, 1.2), wd * 1.8, Color(0.1, 0.09, 0.08, 0.25 * fade))
			if depth < 3 and rng.randf() < 0.04:
				stack.append([p, ang + rng.randf_range(0.5, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0), wd * 0.7, depth + 1])
	img.save_png(OUT + "catlak.png")


func _dot(img: Image, p: Vector2, r: float, c: Color) -> void:
	var ri := int(ceil(r))
	for y in range(-ri, ri + 1):
		for x in range(-ri, ri + 1):
			var px := int(p.x) + x
			var py := int(p.y) + y
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			var d := Vector2(x, y).length()
			if d > r:
				continue
			var k := c.a * clampf(r - d, 0.0, 1.0)
			var old := img.get_pixel(px, py)
			var a := maxf(old.a, k)
			img.set_pixel(px, py, Color(c.r, c.g, c.b, a))


# Pas/su akıntısı: üstte koyu, aşağı doğru sönen dikey izler (duvar ve boru altları).
func _pas() -> void:
	var w := 256
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := _noise(5, 0.05, 2)
	var n2 := _noise(13, 0.015)
	for y in h:
		for x in w:
			var t := float(y) / h
			var streak := (n.get_noise_2d(x * 1.0, y * 0.04) + 1.0) * 0.5
			var edge := clampf(1.0 - absf(x - w / 2.0) / (w / 2.0), 0.0, 1.0)
			var top := clampf(1.0 - t * 1.15, 0.0, 1.0)
			var v := (n2.get_noise_2d(x, y) + 1.0) * 0.5
			var a := clampf(streak * 1.6 - 0.45 + (0.25 if t < 0.08 else 0.0), 0.0, 1.0) * pow(top, 1.3) * pow(edge, 0.6)
			img.set_pixel(x, y, Color(0.32 + v * 0.12, 0.16 + v * 0.06, 0.06, a * 0.9))
	img.save_png(OUT + "pas.png")


# Sarı-siyah çapraz uyarı şeridi, yıpranmış.
func _tehlike() -> void:
	var w := 256
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := _noise(31, 0.06, 4)
	for y in h:
		for x in w:
			var band := int(floor((x + y) / 32.0)) % 2 == 0
			var v := (n.get_noise_2d(x, y) + 1.0) * 0.5
			var c := Color(0.85, 0.62, 0.08) if band else Color(0.06, 0.06, 0.06)
			if v > 0.68:
				c = c.lerp(Color(0.28, 0.27, 0.25), clampf((v - 0.68) * 4.0, 0.0, 0.85))
			c = c.darkened(v * 0.25)
			img.set_pixel(x, y, c)
	img.save_png(OUT + "tehlike.png")


# Islak zemin için ORM: AO=1, pürüzlülük çok düşük, metal yok.
func _orm() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, 0.06, 0.0))
	img.save_png(OUT + "islak_orm.png")
