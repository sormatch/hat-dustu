# Dikey mağaza görseli birleştirici: 3D plaka + karartma + süs katmanları + başlık (RussoOne, Godot çizer).
# Kullanım: Godot --path . --resolution 270x480 -s D:/HatDustu/magaza/araclar/dikey_afis.gd -- is=<isler.json>
# İş biçimi: magaza/araclar/dikey_isler.mjs üretir. Çıktı opak RGB PNG.
extends SceneTree

const AMBER := Color("#ffb020")
const METIN := Color("#f7f0e0")
const SARI := Color("#f5c518")
const ZEMIN := Color("#0b0e0f")

var font: Font


class Baslik extends Control:
	var font: Font
	var satirlar: Array = []  # {parca: [[metin, renk]], fs, x, y}
	var etiket := ""
	var etiket_rect := Rect2()
	var etiket_fs := 40
	var aci := -0.03
	var egim := 0.07
	var merkez := Vector2.ZERO
	var dolgu := false  # true: yalnız harf dolgusu (degrade gölgelendirici bu düğümde)

	func _xf() -> Transform2D:
		var t := Transform2D(Vector2(1, 0), Vector2(-egim, 1), Vector2.ZERO)
		return Transform2D(aci, merkez) * t * Transform2D(0.0, -merkez)

	func _draw() -> void:
		draw_set_transform_matrix(_xf())
		if not dolgu and etiket != "":
			_etiket_ciz()
		for s in satirlar:
			var fs: int = s.fs
			var derin: int = maxi(3, int(fs * 0.055))
			var x: float = s.x
			for p in s.parca:
				var yazi: String = p[0]
				var w := font.get_string_size(yazi, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var at := Vector2(x, s.y)
				if dolgu:
					draw_string(font, at, yazi, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, p[1])
				else:
					var cizgi: int = maxi(6, int(fs * 0.17))
					# yumuşak gölge
					for k in 3:
						var g := float(k + 1) * fs * 0.035
						draw_string_outline(font, at + Vector2(g * 0.4, g * 1.3), yazi, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cizgi + int(g), Color(0, 0, 0, 0.22))
					# kabartma (aşağı kalın kenar)
					for i in range(derin, 0, -1):
						draw_string_outline(font, at + Vector2(i * 0.35, i), yazi, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cizgi, Color(0.03, 0.025, 0.02))
					draw_string_outline(font, at, yazi, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cizgi, Color(0.02, 0.02, 0.02))
				x += w

	func _etiket_ciz() -> void:
		var r := etiket_rect
		draw_rect(r.grow(maxf(3.0, r.size.y * 0.07)), Color(0.02, 0.02, 0.02))
		draw_rect(r, AMBER)
		# iki uçta tehlike şeridi
		var adim := r.size.y * 0.42
		var genis := r.size.y * 0.95
		for uc in [0, 1]:
			var bx: float = r.position.x if uc == 0 else r.end.x - genis
			draw_rect(Rect2(bx, r.position.y, genis, r.size.y), Color("#141414"))
			var i := -1
			while i * adim < genis + r.size.y:
				var x0: float = bx + i * adim
				var pts := PackedVector2Array([
					Vector2(clampf(x0, bx, bx + genis), r.position.y),
					Vector2(clampf(x0 + adim * 0.5, bx, bx + genis), r.position.y),
					Vector2(clampf(x0 + adim * 0.5 - r.size.y * 0.6, bx, bx + genis), r.end.y),
					Vector2(clampf(x0 - r.size.y * 0.6, bx, bx + genis), r.end.y)])
				if pts[0].x < pts[1].x or pts[3].x < pts[2].x:
					draw_colored_polygon(pts, SARI)
				i += 1
		var w := font.get_string_size(etiket, HORIZONTAL_ALIGNMENT_LEFT, -1, etiket_fs).x
		var asc := font.get_ascent(etiket_fs)
		var des := font.get_descent(etiket_fs)
		draw_string(font, Vector2(r.position.x + (r.size.x - w) * 0.5, r.position.y + (r.size.y + asc - des) * 0.5), etiket, HORIZONTAL_ALIGNMENT_LEFT, -1, etiket_fs, Color("#141008"))


# Maç sonu konfetisi (oyundaki gibi amber + beyaz dikdörtgenler, biraz da renk)
class Konfeti extends Control:
	var adet := 60
	var olcek := 1.0
	var alt_sinir := 0.7
	var kacin: Array = []  # [x, y, yarıçap] (genişliğe oranla): yüzlerin üstüne konfeti düşmesin

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1337
		var renkler := [AMBER, AMBER, Color("#ffd86a"), METIN, Color("#e0322a"), Color("#3fa8ff"), Color("#4cc23a")]
		for i in adet:
			var p := Vector2(rng.randf() * size.x, (0.24 + pow(rng.randf(), 0.8) * (alt_sinir - 0.24)) * size.y)
			var u := rng.randf_range(16.0, 44.0) * olcek
			var y := u * rng.randf_range(0.4, 0.75)
			var aci := rng.randf() * TAU
			var r: Color = renkler[rng.randi() % renkler.size()]
			r = r.darkened(rng.randf() * 0.25)
			var atla := false
			for c in kacin:
				if p.distance_to(Vector2(float(c[0]) * size.x, float(c[1]) * size.y)) < float(c[2]) * size.x:
					atla = true
			if atla:
				continue
			draw_set_transform(p, aci, Vector2.ONE)
			draw_rect(Rect2(-u * 0.5, -y * 0.5, u, y), r)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Konuşma rozeti: yuvarlak mikrofon ikonu + iki yana ses dalgası
class Rozet extends Control:
	var ikon: Texture2D
	var yaricap := 60.0

	func _draw() -> void:
		draw_circle(Vector2(0, yaricap * 0.12), yaricap * 1.08, Color(0, 0, 0, 0.45))
		draw_circle(Vector2.ZERO, yaricap, Color(0.04, 0.05, 0.05))
		draw_circle(Vector2.ZERO, yaricap * 0.9, AMBER)
		var s := yaricap * 1.25
		draw_texture_rect(ikon, Rect2(-s * 0.5, -s * 0.5, s, s), false, Color(0.05, 0.04, 0.02))
		for k in 3:
			var rr := yaricap * (1.32 + k * 0.3)
			var kal := maxf(3.0, yaricap * 0.1)
			var c := Color(AMBER, 0.95 - k * 0.27)
			draw_arc(Vector2.ZERO, rr, -0.55, 0.55, 18, c, kal, true)
			draw_arc(Vector2.ZERO, rr, PI - 0.55, PI + 0.55, 18, c, kal, true)


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var isler: Array = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("is", ""))))
	_calistir(isler)


func _calistir(isler: Array) -> void:
	await process_frame
	for j in isler:
		var vp := SubViewport.new()
		vp.size = Vector2i(int(j.w), int(j.h))
		vp.transparent_bg = false
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var kok := Control.new()
		kok.size = Vector2(vp.size)
		vp.add_child(kok)
		_kur(kok, j)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)  # saydamlık yok (App Store şartı)
		DirAccess.make_dir_recursive_absolute(str(j.cikti).get_base_dir())
		img.save_png(str(j.cikti))
		print("yazildi ", j.cikti, " ", img.get_size())
		vp.queue_free()
		await process_frame
	OS.kill(OS.get_process_id())


func _doku(yol: String) -> ImageTexture:
	var img := Image.load_from_file(yol)
	img.convert(Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)


func _resim(tex: Texture2D, r: Rect2, kapla := true) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if kapla else TextureRect.STRETCH_SCALE
	t.position = r.position
	t.size = r.size
	return t


func _gradyan(renkler: Array, oranlar: Array, dikey := true) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(oranlar)
	g.colors = PackedColorArray(renkler)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 8
	gt.height = 512
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1) if dikey else Vector2(1, 0)
	return gt


func _kenar_karartma(k: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, k)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 512
	gt.height = 512
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 1.08)
	return gt


func _serit(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var adim := h * 2
	for y in h:
		for x in w:
			var k := int(floor((x + y) / float(adim))) % 2
			img.set_pixel(x, y, SARI if k == 0 else Color("#141414"))
	return ImageTexture.create_from_image(img)


func _kur(kok: Control, j: Dictionary) -> void:
	var W := float(j.w)
	var H := float(j.h)
	kok.add_child(_resim(_doku(str(j.plaka)), Rect2(0, 0, W, H)))
	# süs katmanları (duman, kıvılcım): toplamalı
	for k in j.get("sus", []):
		var t := _resim(_doku(str(k.yol)), Rect2(float(k.get("x", 0.0)) * W, float(k.get("y", 0.0)) * H, float(k.get("g", 1.0)) * W, float(k.get("u", 1.0)) * H))
		var cm := CanvasItemMaterial.new()
		cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		t.material = cm
		t.modulate = Color.from_string(str(k.get("renk", "#ffffff")), Color.WHITE)
		t.modulate.a = float(k.get("a", 1.0))
		kok.add_child(t)
	# karartma: başlık bölgesi + alt + kenarlar
	var ust := float(j.get("ust_koyu", 0.8))
	var alt := float(j.get("alt_koyu", 0.6))
	var ust_bit := float(j.get("ust_bit", 0.36))
	var alt_bas := float(j.get("alt_bas", 0.78))
	kok.add_child(_resim(_gradyan([Color(ZEMIN, ust), Color(ZEMIN, ust * 0.72), Color(ZEMIN, 0.0)], [0.0, ust_bit * 0.55, ust_bit]), Rect2(0, 0, W, H), false))
	kok.add_child(_resim(_gradyan([Color(ZEMIN, 0.0), Color(ZEMIN, alt)], [alt_bas, 1.0]), Rect2(0, 0, W, H), false))
	kok.add_child(_resim(_kenar_karartma(float(j.get("kenar", 0.55))), Rect2(0, 0, W, H), false))
	# ek görseller (gerçek oyun arayüz parçaları)
	for e in j.get("ek", []):
		var t := _resim(_doku(str(e.yol)), Rect2(float(e.x) * W, float(e.y) * H, float(e.g) * W, float(e.u) * H), false)
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.pivot_offset = t.size * 0.5
		t.rotation = deg_to_rad(float(e.get("aci", 0.0)))
		if bool(e.get("cerceve", false)):
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			var c := Panel.new()
			var cs := StyleBoxFlat.new()
			cs.draw_center = false
			cs.border_color = AMBER
			cs.set_border_width_all(maxi(5, int(W * 0.007)))
			cs.shadow_color = Color(0, 0, 0, 0.7)
			cs.shadow_size = int(W * 0.03)
			c.add_theme_stylebox_override("panel", cs)
			c.size = t.size
			t.add_child(c)
		kok.add_child(t)
	if j.has("konfeti"):
		var kf := Konfeti.new()
		kf.size = Vector2(W, H)
		kf.adet = int(j.konfeti)
		kf.olcek = W / 1290.0
		kf.alt_sinir = float(j.get("konfeti_alt", 0.7))
		kf.kacin = j.get("kacin", [])
		kok.add_child(kf)
	for z in j.get("rozet", []):
		var rz := Rozet.new()
		rz.ikon = _doku(str(z.yol))
		rz.yaricap = float(z.r) * W
		rz.position = Vector2(float(z.x) * W, float(z.y) * H)
		kok.add_child(rz)
	# alt kenarda ince tehlike şeridi (seri imzası)
	var sh := int(maxf(10.0, H * 0.0065))
	kok.add_child(_resim(_serit(int(W), sh), Rect2(0, H - sh, W, sh), false))
	_baslik_kur(kok, j, W, H)
	# logo
	if j.has("logo"):
		var lg := Image.load_from_file(str(j.logo))
		lg = lg.get_region(lg.get_used_rect())
		var lw := W * float(j.get("logo_g", 0.36))
		var lh := lw * lg.get_height() / lg.get_width()
		var ly := H * 0.945 - lh
		if j.has("logo_y"):
			ly = H * float(j.logo_y)
		kok.add_child(_resim(ImageTexture.create_from_image(lg), Rect2((W - lw) * 0.5, ly, lw, lh), false))


func _baslik_kur(kok: Control, j: Dictionary, W: float, H: float) -> void:
	var vurgu := Color.from_string(str(j.get("vurgu", "#ffb020")), AMBER)
	var en_boy := W / H
	var yan := W * 0.055
	var fs_ust: int = int(minf(W * float(j.get("fs_w", 0.17)), H * float(j.get("fs_h", 0.09))))
	var y := H * float(j.get("baslik_y", 0.085))
	var etiket := str(j.get("etiket", ""))
	var etiket_rect := Rect2()
	var etiket_fs := int(H * (0.0185 if en_boy < 0.7 else 0.021))
	if etiket != "":
		var ew := font.get_string_size(etiket, HORIZONTAL_ALIGNMENT_LEFT, -1, etiket_fs).x
		var eh := etiket_fs * 1.62
		var eg := ew + eh * 2.9
		etiket_rect = Rect2((W - eg) * 0.5, y, eg, eh)
		y += eh + H * 0.012
	var satirlar := []
	var alt_kenar := y
	for sat in j.satirlar:
		var duz := ""
		for p in sat:
			duz += str(p[0])
		var fs := fs_ust
		while fs > 20 and font.get_string_size(duz, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > W - 2.0 * yan:
			fs -= 2
		var asc := font.get_ascent(fs)
		var des := font.get_descent(fs)
		var gen := font.get_string_size(duz, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var parca := []
		for p in sat:
			parca.append([str(p[0]), vurgu if int(p[1]) == 1 else METIN])
		var taban := alt_kenar + asc * 0.93
		satirlar.append({"parca": parca, "fs": fs, "x": (W - gen) * 0.5, "y": taban, "y0": taban - asc * 0.78, "y1": taban + des * 0.2})
		alt_kenar = taban + des * 0.42
	var merkez := Vector2(W * 0.5, (y + alt_kenar) * 0.5)
	var aci := deg_to_rad(float(j.get("aci", -2.0)))
	var egim := float(j.get("egim", 0.07))
	var cizgi := Baslik.new()
	cizgi.font = font
	cizgi.size = Vector2(W, H)
	cizgi.satirlar = satirlar
	cizgi.merkez = merkez
	cizgi.aci = aci
	cizgi.egim = egim
	cizgi.etiket = etiket
	cizgi.etiket_rect = etiket_rect
	cizgi.etiket_fs = etiket_fs
	kok.add_child(cizgi)
	var dolgu := Baslik.new()
	dolgu.font = font
	dolgu.size = Vector2(W, H)
	dolgu.satirlar = satirlar
	dolgu.merkez = merkez
	dolgu.aci = aci
	dolgu.egim = egim
	dolgu.dolgu = true
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;
uniform vec2 a = vec2(0.0, 1.0);
uniform vec2 b = vec2(0.0, 1.0);
uniform float bol = 100000.0;
uniform float yuk = 1.0;
void fragment() {
	float y = SCREEN_UV.y * yuk;
	vec2 r = y < bol ? a : b;
	float t = clamp((y - r.x) / (r.y - r.x), 0.0, 1.0);
	COLOR.rgb *= mix(1.16, 0.80, t);
}"
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("yuk", H)
	var s0: Dictionary = satirlar[0]
	m.set_shader_parameter("a", Vector2(s0.y0, s0.y1))
	if satirlar.size() > 1:
		var s1: Dictionary = satirlar[1]
		m.set_shader_parameter("b", Vector2(s1.y0, s1.y1))
		m.set_shader_parameter("bol", (float(s0.y1) + float(s1.y0)) * 0.5)
	else:
		m.set_shader_parameter("b", Vector2(s0.y0, s0.y1))
	dolgu.material = m
	kok.add_child(dolgu)
