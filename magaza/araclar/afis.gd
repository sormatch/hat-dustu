# Mağaza görselleri birleştirici: oyun ekran görüntüsünün üstüne büyük başlık bandı koyar,
# Play "öne çıkan görsel"i (1024x500) hazırlar. Godot pencereli çalışır (SubViewport çizimi için).
# Kullanım (Git Bash, D:/HatDustu içinde):
#   /d/Godot/Godot_v4.7.2-stable_win64_console.exe --path . -s D:/HatDustu/magaza/araclar/afis.gd -- is=D:/HatDustu/magaza/araclar/isler.json
# isler.json: [{"tur": "ekran", "girdi": png, "cikti": png, "w": 2796, "h": 1290, "baslik": "...", "vurgu": "..."},
#              {"tur": "one_cikan", "girdi": png, "cikti": png, "w": 1024, "h": 500, "logo": png, "baslik": "...", "vurgu": "..."}]
extends SceneTree

const ZEMIN := Color("#0b0e0f")
const AMBER := Color("#ffb020")
const METIN := Color("#f3ead8")
const SARI := Color("#f5c518")

var font: Font


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
		var tur := str(j.get("tur", "ekran"))
		var vp := SubViewport.new()
		vp.size = Vector2i(int(j.w), int(j.h))
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var kok := Control.new()
		kok.size = Vector2(vp.size)
		vp.add_child(kok)
		if tur == "one_cikan":
			_one_cikan(kok, j)
		else:
			_ekran(kok, j)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)  # saydamlık yok (App Store şartı)
		img.save_png(str(j.cikti))
		print("yazildi ", j.cikti, " ", img.get_size())
		vp.queue_free()
		await process_frame
	quit()


func _resim(yol: String) -> Image:
	var img := Image.load_from_file(yol)
	img.convert(Image.FORMAT_RGBA8)
	return img


# Hızlı bulanıklık: küçült, sonra yumuşak büyüt
func _bulanik(img: Image, k := 24) -> Image:
	var b: Image = img.duplicate()
	b.resize(maxi(4, img.get_width() / k), maxi(4, img.get_height() / k), Image.INTERPOLATE_BILINEAR)
	b.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_CUBIC)
	return b


func _tex_rect(tex: Texture2D, r: Rect2, kaplama := true) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if kaplama else TextureRect.STRETCH_SCALE
	t.position = r.position
	t.size = r.size
	return t


func _gradyan(renkler: Array, oranlar: Array, dikey := true) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(oranlar)
	g.colors = PackedColorArray(renkler)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1) if dikey else Vector2(1, 0)
	return gt


# Sarı-siyah tehlike şeridi dokusu
func _serit(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var adim := h * 2
	for y in h:
		for x in w:
			var k := int(floor((x + y) / float(adim))) % 2
			img.set_pixel(x, y, SARI if k == 0 else Color("#141414"))
	return ImageTexture.create_from_image(img)


# Başlık: [önce][vurgu][sonra] üç parça, vurgu amber. Genişliğe sığana dek küçülür.
func _baslik(ust: Control, metin: String, vurgu: String, alan: Rect2, boyut: int) -> void:
	var parcalar := [[metin, METIN]]
	if vurgu != "" and metin.find(vurgu) >= 0:
		var i := metin.find(vurgu)
		parcalar = [[metin.substr(0, i), METIN], [vurgu, AMBER], [metin.substr(i + vurgu.length()), METIN]]
	var fs := boyut
	while fs > 12 and font.get_string_size(metin, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > alan.size.x * 0.94:
		fs -= 2
	var kutu := HBoxContainer.new()
	kutu.add_theme_constant_override("separation", 0)
	kutu.alignment = BoxContainer.ALIGNMENT_CENTER
	kutu.position = alan.position
	kutu.size = alan.size
	ust.add_child(kutu)
	for p in parcalar:
		if str(p[0]) == "":
			continue
		var l := Label.new()
		l.text = str(p[0])
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", p[1])
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		l.add_theme_constant_override("outline_size", maxi(4, fs / 7))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", maxi(3, fs / 14))
		l.add_theme_constant_override("shadow_outline_size", maxi(4, fs / 7))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_FILL
		kutu.add_child(l)


func _ekran(kok: Control, j: Dictionary) -> void:
	var W := float(j.w)
	var H := float(j.h)
	var shot := _resim(str(j.girdi))
	var s := H / 1290.0  # ölçü birimi
	var en_boy := W / H
	# 1) zemin: bulanık, karartılmış ekran
	var bg := _tex_rect(ImageTexture.create_from_image(_bulanik(shot)), Rect2(0, 0, W, H))
	bg.modulate = Color(0.42, 0.42, 0.42)
	kok.add_child(bg)
	var perde := _tex_rect(_gradyan([Color(ZEMIN, 0.92), Color(ZEMIN, 0.55), Color(ZEMIN, 0.85)], [0.0, 0.45, 1.0]), Rect2(0, 0, W, H), false)
	kok.add_child(perde)
	# 2) bant ölçüleri
	var bant := H * (0.19 if en_boy > 1.6 else 0.15)
	var alt_pay := H * (0.05 if en_boy > 1.6 else 0.04)
	var yan_pay := W * 0.035
	# 3) ekran görüntüsü çerçevesi
	var alan := Rect2(yan_pay, bant, W - 2 * yan_pay, H - bant - alt_pay)
	var oran := float(shot.get_width()) / shot.get_height()
	var sw := alan.size.x
	var sh := sw / oran
	if sh > alan.size.y:
		sh = alan.size.y
		sw = sh * oran
	var r := Rect2(alan.position.x + (alan.size.x - sw) / 2.0, alan.position.y + (alan.size.y - sh) / 2.0, sw, sh)
	var kose := int(34 * s)
	var kenar := maxi(3, int(6 * s))
	var golge := Panel.new()
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0, 0, 0, 0.9)
	gs.set_corner_radius_all(kose)
	gs.shadow_color = Color(0, 0, 0, 0.7)
	gs.shadow_size = int(40 * s)
	gs.shadow_offset = Vector2(0, 14 * s)
	golge.add_theme_stylebox_override("panel", gs)
	golge.position = r.position
	golge.size = r.size
	kok.add_child(golge)
	var maske := Panel.new()
	var ms := StyleBoxFlat.new()
	ms.bg_color = Color.WHITE
	ms.set_corner_radius_all(kose)
	ms.anti_aliasing = true
	maske.add_theme_stylebox_override("panel", ms)
	maske.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	maske.position = r.position
	maske.size = r.size
	kok.add_child(maske)
	maske.add_child(_tex_rect(ImageTexture.create_from_image(shot), Rect2(Vector2.ZERO, r.size), false))
	var cerceve := Panel.new()
	var cs := StyleBoxFlat.new()
	cs.draw_center = false
	cs.border_color = AMBER
	cs.set_border_width_all(kenar)
	cs.set_corner_radius_all(kose)
	cs.anti_aliasing = true
	cerceve.add_theme_stylebox_override("panel", cs)
	cerceve.position = r.position
	cerceve.size = r.size
	kok.add_child(cerceve)
	# 4) üstte ince tehlike şeridi
	var sh_h := int(14 * s)
	kok.add_child(_tex_rect(_serit(int(W), sh_h), Rect2(0, 0, W, sh_h), false))
	# 5) başlık
	var fs := int(118 * s) if en_boy > 1.6 else int(132 * s)
	_baslik(kok, str(j.baslik), str(j.get("vurgu", "")), Rect2(yan_pay, sh_h, W - 2 * yan_pay, bant - sh_h), fs)


func _one_cikan(kok: Control, j: Dictionary) -> void:
	var W := float(j.w)
	var H := float(j.h)
	var bg_img := _resim(str(j.girdi))
	var bg := _tex_rect(ImageTexture.create_from_image(bg_img), Rect2(0, 0, W, H))
	kok.add_child(bg)
	# sol tarafı logo ve yazı için karart
	var g := _tex_rect(_gradyan([Color(ZEMIN, 0.88), Color(ZEMIN, 0.55), Color(ZEMIN, 0.0)], [0.0, 0.33, 0.5], false), Rect2(0, 0, W, H), false)
	kok.add_child(g)
	var logo := _resim(str(j.logo))
	logo = logo.get_region(logo.get_used_rect())
	var lw := W * 0.46
	var lh := lw * logo.get_height() / logo.get_width()
	if lh > H * 0.62:
		lh = H * 0.62
		lw = lh * logo.get_width() / logo.get_height()
	var sol := W * 0.04
	var ust := H * 0.08
	kok.add_child(_tex_rect(ImageTexture.create_from_image(logo), Rect2(sol + (W * 0.46 - lw) / 2.0, ust, lw, lh), false))
	_baslik(kok, str(j.baslik), str(j.get("vurgu", "")), Rect2(sol, ust + lh + H * 0.02, W * 0.46, H * 0.18), int(H * 0.085))
