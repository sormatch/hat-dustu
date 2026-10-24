# Bekleme salonu: hapishane ortak alanı. Duvarda yeşil tebeşir tahtasında oda kodu, uzun masalar ve banklar,
# sarkan lambalar, televizyon, içecek makinesi, parmaklıklı pencereler. Oyuncular oyun başlayana kadar burada.
extends Node3D

const UI := preload("res://scripts/ui.gd")
const W := 14.0
const D := 12.0
const H := 3.6

var w: Node3D  # main.gd: malzemeler ve yardımcılar
var _code: Label3D
var _count: Label3D
var _tv_mat: StandardMaterial3D
var _tv_t := 0.0


func build() -> void:
	var m: Dictionary = w.mats
	var t := 0.2
	# zemin, tavan, duvarlar (altı yeşil boyalı)
	w.box(Vector3(W + 0.4, t, D + 0.4), Vector3(0, -t / 2, 0), m.floor, true, self)
	w.box(Vector3(W + 0.4, t, D + 0.4), Vector3(0, H + t / 2, 0), m.ceiling, true, self)
	for side in [-1.0, 1.0]:
		w.box(Vector3(W + 0.4, H, t), Vector3(0, H / 2, side * (D / 2 + 0.1)), m.wall, true, self)
		w.box(Vector3(t, H, D + 0.4), Vector3(side * (W / 2 + 0.1), H / 2, 0), m.wall, true, self)
		w.box(Vector3(W, 1.3, 0.02), Vector3(0, 0.65, side * (D / 2 - 0.01)), m.paint, false, self)
		w.box(Vector3(0.02, 1.3, D), Vector3(side * (W / 2 - 0.01), 0.65, 0), m.paint, false, self)

	_build_board()
	for x in [-3.6, 0.0, 3.6]:
		_table(Vector3(x, 0, 1.2))
	for x in [-3.6, 3.6]:
		_table(Vector3(x, 0, 4.0))
	# sarkan lambalar
	for p in [Vector3(-3.6, 0, 1.2), Vector3(0, 0, 1.2), Vector3(3.6, 0, 1.2), Vector3(0, 0, -3.5)]:
		w.model("hanging_industrial_lamp", p, 0.0, 0.7, H, self)
		var l := OmniLight3D.new()
		l.light_color = Color("#ffc47a")
		l.light_energy = 2.2
		l.omni_range = 7.0
		l.position = p + Vector3(0, H - 1.2, 0)
		l.shadow_enabled = p.z < 0.0
		add_child(l)
	_build_tv()
	_build_vending()
	_build_windows()


# Yeşil tebeşir tahtası (yapay zekâ görseli varsa o), üstünde tebeşirle oda kodu.
func _build_board() -> void:
	var z := -D / 2 + 0.06
	var tex := UI.texture("chalkboard")
	if tex:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(5.2, 5.2 * tex.get_height() / float(tex.get_width()))
		q.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.roughness = 0.9
		q.material_override = mat
		q.position = Vector3(0, 1.95, z)
		add_child(q)
	else:
		w.box(Vector3(4.8, 2.5, 0.06), Vector3(0, 1.95, z), w._flat(Color("#5a3a20"), 0.8), false, self)
		w.box(Vector3(4.4, 2.1, 0.07), Vector3(0, 1.95, z + 0.01), w._flat(Color("#2e5a3c"), 0.95), false, self)
	var chalk := Color(0.96, 0.96, 0.9)
	var head := _chalk_text("BEKLEME SALONU", 70, Vector3(0, 2.65, z + 0.06), chalk.darkened(0.15))
	head.modulate.a = 0.8
	_code = _chalk_text("----", 260, Vector3(0, 1.95, z + 0.06), chalk)
	_count = _chalk_text("0/8 oyuncu", 70, Vector3(0, 1.2, z + 0.06), chalk.darkened(0.1))


func _chalk_text(text: String, size: int, pos: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.TITLE_FONT
	l.font_size = size
	l.pixel_size = 0.0035
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.shaded = false
	add_child(l)
	return l


func set_code(code: String) -> void:
	_code.text = code


func set_count(n: int) -> void:
	_count.text = "%d/8 oyuncu" % n


# Uzun yemekhane masası ve iki yanında bank.
func _table(p: Vector3) -> void:
	var wood: StandardMaterial3D = w._flat(Color("#6a5034"), 0.75)
	var metal: StandardMaterial3D = w.mats.metal_dark
	w.box(Vector3(2.6, 0.07, 0.95), p + Vector3(0, 0.76, 0), wood, true, self)
	for x in [-1.15, 1.15]:
		w.box(Vector3(0.07, 0.74, 0.8), p + Vector3(x, 0.37, 0), metal, false, self)
	for side in [-1.0, 1.0]:
		w.box(Vector3(2.6, 0.06, 0.34), p + Vector3(0, 0.45, side * 0.78), wood, true, self)
		for x in [-1.1, 1.1]:
			w.box(Vector3(0.06, 0.44, 0.06), p + Vector3(x, 0.22, side * 0.78), metal, false, self)


# Duvarda eski televizyon: ekranı yavaşça renk değiştirir.
func _build_tv() -> void:
	var p := Vector3(W / 2 - 0.12, 2.3, -1.5)
	w.box(Vector3(0.18, 1.0, 1.6), p, w._flat(Color("#1a1a1c"), 0.5), false, self)
	_tv_mat = w._glow(Color("#4a7fc0"), 1.4)
	w.box(Vector3(0.02, 0.82, 1.42), p + Vector3(-0.1, 0, 0), _tv_mat, false, self)
	var l := Label3D.new()
	l.text = "HAT DÜŞTÜ TV"
	l.font = UI.TITLE_FONT
	l.font_size = 64
	l.pixel_size = 0.004
	l.position = p + Vector3(-0.13, 0, 0)
	l.rotation.y = -PI / 2
	add_child(l)


# İçecek makinesi: kırmızı gövde, ışıklı ön panel.
func _build_vending() -> void:
	var p := Vector3(-W / 2 + 0.5, 1.0, -3.8)
	w.box(Vector3(0.9, 2.0, 1.1), p, w._flat(Color("#8f1d1d"), 0.4), true, self)
	w.box(Vector3(0.02, 1.2, 0.8), p + Vector3(0.46, 0.25, 0), w._glow(Color("#ffd98a"), 1.2), false, self)
	var l := Label3D.new()
	l.text = "SODA"
	l.font = UI.TITLE_FONT
	l.font_size = 90
	l.pixel_size = 0.004
	l.modulate = Color("#ffffff")
	l.position = p + Vector3(0.48, 0.85, 0)
	l.rotation.y = PI / 2
	add_child(l)


# Arka duvarda parmaklıklı, ay ışığı sızan pencereler.
func _build_windows() -> void:
	for x in [-4.5, 4.5]:
		var p := Vector3(x, 2.5, D / 2 - 0.02)
		w.box(Vector3(1.4, 0.8, 0.03), p, w._glow(Color("#5d7fa8"), 1.3), false, self)
		for i in 7:
			w.box(Vector3(0.04, 0.85, 0.05), p + Vector3(-0.6 + i * 0.2, 0, -0.03), w.mats.metal_dark, false, self)


func spawn_point(i: int) -> Vector3:
	return to_global(Vector3(-2.0 + (i % 4) * 1.3, 0, 3.0 + (i / 4) * 1.0))


func _process(delta: float) -> void:
	_tv_t += delta
	_tv_mat.emission = Color.from_hsv(fmod(_tv_t * 0.05, 1.0), 0.5, 0.9)
