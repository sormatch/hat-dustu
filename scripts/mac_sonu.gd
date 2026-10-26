# Maç sonu ekranı: puan tablosu (satırlar oyuncular, sütunlar oynanan oyunlar, sağda toplam) sondan başa
# satır satır açılır. En son davul çalar, 1. karanlıkta siluet olarak belirir, ışıklar yanar, kafasına
# yukarıdan altın kral tacı düşer, konfeti patlar. Ekrana dokunmak açılışı hızlandırır.
# game_ui.on_over açar: setup(d, my_id, net.players) ve "back" sinyali (ANA MENÜYE DÖN).
extends Control

signal back

const UI := preload("res://scripts/ui.gd")
const Fx := preload("res://scripts/store_fx.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")

const GREEN := Color("#5be37d")
const RED := Color("#ff5a5a")
const GRAY := Color(0.55, 0.57, 0.64)
const GOLD := Color("#ffc23a")
const SILVER := Color("#cfd6e0")
const BRONZE := Color("#d98a4a")
const TEAL := Color("#5ff0ff")
const RATE := 22050

var data: Dictionary = {}
var my_id := 0
var looks: Dictionary = {}  # oyuncu kimliği -> görünüş

var _rows: Array = []  # sunucunun sıraladığı tablo (0 = kazanan)
var _games: Array = []
var _row_nodes: Array = []  # her sıranın satırı
var _table: Control
var _table_final_x := 0.0
var _title: Label
var _header: Control
var _stage: Control
var _stage_rays: Control
var _win_title: Label
var _win_name: Label
var _back_btn: Button
var _flash: ColorRect
var _fast := false
var _done := false
var _sz := Vector2(1280, 720)

# 3D sahne
var _body: Node3D
var _crown: Node3D
var _key: DirectionalLight3D
var _spot: SpotLight3D
var _env: Environment
var _fall_t := -1.0
var _fall_from := Vector3.ZERO
var _crown_ba: BoneAttachment3D


func setup(d: Dictionary, me: int, players: Array) -> void:
	data = d
	my_id = me
	for p in players:
		if typeof(p) == TYPE_DICTIONARY:
			looks[int(p.get("id", 0))] = p.get("g", {})
	_rows = d.get("table", [])
	_games = d.get("oyunlar", [])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sz = get_viewport_rect().size
	_build_background()
	_build_stage()
	_build_table()
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.95, 0.8, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_back_btn = UI.button("ANA MENÜYE DÖN", "primary", 66, 24, "play", 360)
	_back_btn.position = Vector2(_table_final_x + _table.size.x / 2.0 - 180, _sz.y - 92)
	_back_btn.modulate.a = 0.0
	_back_btn.visible = false
	_back_btn.pressed.connect(func() -> void: back.emit())
	add_child(_back_btn)
	_run()


func _gui_input(e: InputEvent) -> void:
	if not _done and ((e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed)):
		_fast = true


# ---------- kurulum ----------

func _build_background() -> void:
	var bg := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.42)
	gt.fill_to = Vector2(1.05, 1.05)
	var gr := Gradient.new()
	gr.set_color(0, Color("#2a1f3d"))
	gr.set_color(1, Color("#06050b"))
	gt.gradient = gr
	gt.width = 256
	gt.height = 256
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)


func _stage_w() -> float:
	# çok oyun oynandıysa tabloya yer açmak için sahne daralır
	return clampf(_sz.x * (0.31 if _games.size() < 6 else 0.27), 320.0, 440.0)


func _build_stage() -> void:
	var w := _stage_w()
	_stage = Control.new()
	_stage.position = Vector2(12, 0)
	_stage.size = Vector2(w, _sz.y)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.modulate.a = 0.0
	add_child(_stage)
	_stage_rays = Fx.Rays.new()
	_stage_rays.color = GOLD
	_stage_rays.size = Vector2(w, w)
	_stage_rays.position = Vector2(0, _sz.y * 0.42 - w / 2.0)
	_stage_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_rays.modulate.a = 0.0
	_stage.add_child(_stage_rays)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.position = Vector2(0, 70)
	svc.size = Vector2(w, _sz.y - 70 - 128)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)
	_build_3d(sv)
	_win_title = UI.title("", 46, GOLD, true)
	_win_title.position = Vector2(0, 14)
	_win_title.size = Vector2(w, 60)
	_win_title.modulate.a = 0.0
	_stage.add_child(_win_title)
	_win_name = UI.title("", 38, Color.WHITE, true)
	_win_name.position = Vector2(0, _sz.y - 122)
	_win_name.size = Vector2(w, 50)
	_win_name.clip_text = true
	_win_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_win_name.modulate.a = 0.0
	_stage.add_child(_win_name)


func _build_3d(sv: SubViewport) -> void:
	var root := Node3D.new()
	sv.add_child(root)
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.58, 0.75)
	_env.ambient_light_energy = 0.04
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# altın parlasın diye yansımalar için gökyüzü (arka plan şeffaf kalır)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#4a3a7a")
	sm.sky_horizon_color = Color("#ffcf8a")
	sm.ground_bottom_color = Color("#120c08")
	sm.ground_horizon_color = Color("#8a5a20")
	sky.sky_material = sm
	_env.sky = sky
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = _env
	root.add_child(we)
	_key = DirectionalLight3D.new()
	_key.rotation = Vector3(deg_to_rad(-30), deg_to_rad(200), 0)
	_key.light_color = Color("#ffe2c0")
	_key.light_energy = 0.0
	root.add_child(_key)
	_spot = SpotLight3D.new()
	_spot.position = Vector3(0, 4.6, -1.6)
	_spot.light_color = Color("#ffd27a")
	_spot.light_energy = 0.0
	_spot.spot_range = 9.0
	_spot.spot_angle = 24.0
	_spot.shadow_enabled = true
	root.add_child(_spot)
	_spot.look_at_from_position(_spot.position, Vector3(0, 1.0, 0))
	# arkadan mavi kenar ışığı: ışıklar sönükken karakter siluet gibi görünür
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.0, 2.2, 1.3)
	rim.light_color = Color("#6f9bff")
	rim.light_energy = 3.0
	rim.omni_range = 4.0
	root.add_child(rim)
	# kürsü
	var ped := CylinderMesh.new()
	ped.top_radius = 0.62
	ped.bottom_radius = 0.7
	ped.height = 0.5
	ped.radial_segments = 48
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#1c1a24")
	pm.metallic = 0.5
	pm.roughness = 0.35
	var pmi := MeshInstance3D.new()
	pmi.mesh = ped
	pmi.material_override = pm
	pmi.position.y = 0.25
	root.add_child(pmi)
	var rim_ring := TorusMesh.new()
	rim_ring.inner_radius = 0.6
	rim_ring.outer_radius = 0.65
	rim_ring.rings = 48
	var gm := _gold_mat()
	var rmi := MeshInstance3D.new()
	rmi.mesh = rim_ring
	rmi.material_override = gm
	rmi.position.y = 0.5
	root.add_child(rmi)
	var one := Label3D.new()
	one.text = "1"
	one.font = UI.TITLE_FONT
	one.font_size = 160
	one.pixel_size = 0.0022
	one.modulate = GOLD
	one.outline_size = 0
	one.position = Vector3(0, 0.25, -0.69)
	one.rotation.y = PI
	one.shaded = true
	root.add_child(one)
	# kazanan (tacı biz takacağız; kendi şapkası çıkarılır)
	var wid := _winner_id()
	var lk: Dictionary = Catalog.sanitize(looks.get(wid, _row_of(wid).get("g", {})))
	lk["sapka"] = "yok"
	_body = BodyScript.new()
	_body.look = lk
	_body.position = Vector3(0, 0.5, 0)
	_body.rotation.y = 0.18
	root.add_child(_body)
	var cam := Camera3D.new()
	cam.fov = 36.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.75, -4.6), Vector3(0, 1.32, 0))
	_crown = _make_crown()
	_crown.visible = false
	root.add_child(_crown)


static func _gold_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#ffc640")
	m.metallic = 0.9
	m.roughness = 0.22
	m.emission_enabled = true
	m.emission = Color("#ff9a20")
	m.emission_energy_multiplier = 0.18
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


# Kral tacı: altın bant, 5 sivri uç (uçlarında top), bantta kırmızı/mavi taşlar.
static func _make_crown() -> Node3D:
	var root := Node3D.new()
	var gold := _gold_mat()
	var r := 0.105
	var band := CylinderMesh.new()
	band.top_radius = r * 1.06
	band.bottom_radius = r
	band.height = 0.06
	band.radial_segments = 40
	band.cap_top = false
	band.cap_bottom = false
	_mesh(root, band, gold, Vector3(0, 0.03, 0))
	var lip := TorusMesh.new()
	lip.inner_radius = r * 0.97
	lip.outer_radius = r * 1.09
	lip.rings = 40
	_mesh(root, lip, gold, Vector3(0, 0.002, 0))
	var n := 5
	for i in n:
		var a := TAU * i / float(n) + PI / 2.0
		var dir := Vector3(cos(a), 0, sin(a))
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.034
		spike.height = 0.085
		spike.radial_segments = 4
		var sp := _mesh(root, spike, gold, dir * r * 1.02 + Vector3(0, 0.1, 0))
		sp.rotation = Vector3(dir.z * 0.18, -a, -dir.x * 0.18)
		var ball := SphereMesh.new()
		ball.radius = 0.014
		ball.height = 0.028
		_mesh(root, ball, gold, dir * r * 1.1 + Vector3(0, 0.148, 0))
		var gem := SphereMesh.new()
		gem.radius = 0.016
		gem.height = 0.032
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color("#e0182e") if i % 2 == 0 else Color("#2a6cff")
		gmat.metallic = 0.3
		gmat.roughness = 0.08
		gmat.emission_enabled = true
		gmat.emission = gmat.albedo_color
		gmat.emission_energy_multiplier = 0.35
		var gp := _mesh(root, gem, gmat, dir * r * 1.06 + Vector3(0, 0.032, 0))
		gp.scale = Vector3(1, 1, 0.55)
		gp.rotation.y = -a + PI / 2.0
	var glow := OmniLight3D.new()
	glow.light_color = Color("#ffcf6a")
	glow.light_energy = 0.8
	glow.omni_range = 0.6
	glow.position = Vector3(0, 0.1, -0.25)
	root.add_child(glow)
	return root


func _build_table() -> void:
	var ng := _games.size()
	var avail := _sz.x - _stage_w() - 40.0
	var tw := minf(avail, 960.0)
	var rank_w := 54.0
	var total_w := 104.0
	var inner := tw - 28.0 - rank_w - total_w - 10.0 * (ng + 2)
	var col_w := 0.0
	if ng > 0:
		col_w = clampf((inner - 190.0) / ng, 60.0, 118.0)
	var name_w := inner - col_w * ng
	var n := _rows.size()
	var top := 120.0
	var bottom := _sz.y - 108.0
	var row_h := clampf((bottom - top - 44.0) / maxf(1.0, n), 44.0, 66.0)
	var block := 44.0 + row_h * n
	top = maxf(top, (top + bottom) / 2.0 - block / 2.0)
	_table = Control.new()
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.size = Vector2(tw, block)
	_table_final_x = _sz.x - 20.0 - tw
	_table.position = Vector2((_sz.x - tw) / 2.0, top)
	add_child(_table)
	_title = UI.title("MAÇ SONU", 48, Color.WHITE, true)
	_title.position = Vector2(0, -top + 18)
	_title.size = Vector2(tw, 64)
	_title.pivot_offset = Vector2(tw / 2.0, 32)
	_table.add_child(_title)
	# sütun başlıkları: kısa oyun adları
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	hrow.position = Vector2(14, 0)
	hrow.size = Vector2(tw - 28, 40)
	hrow.modulate.a = 0.0
	_table.add_child(hrow)
	_header = hrow
	hrow.add_child(_spacer(rank_w + name_w + 10.0))
	# tüm başlıklar aynı boyda (en uzun ada göre; çok darsa biraz taşabilir)
	var hfs := 18
	for g in _games:
		hfs = mini(hfs, _fit(str((g as Dictionary).get("ad", "?")), 18, col_w + 6.0))
	hfs = maxi(hfs, 14)
	for g in _games:
		var ad := str((g as Dictionary).get("ad", "?"))
		var hl := UI.title(ad, hfs, Color("#ffcf8a"), true)
		hl.custom_minimum_size = Vector2(col_w, 40)
		hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hrow.add_child(hl)
	var tl := UI.title("TOPLAM", 18, Color.WHITE, true)
	tl.custom_minimum_size = Vector2(total_w, 40)
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(tl)
	for i in n:
		var r: Dictionary = _rows[i]
		var row := _make_row(r, i, Vector2(tw, row_h - 8.0), rank_w, name_w, col_w, total_w)
		row.position = Vector2(0, 44.0 + row_h * i)
		row.modulate.a = 0.0
		_table.add_child(row)
		_row_nodes.append(row)


func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# Yazı sütuna sığana kadar yazı boyunu küçültür.
static func _fit(text: String, size: int, w: float) -> int:
	var s := size
	while s > 11 and UI.TITLE_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > w:
		s -= 1
	return s


static func _rank_color(i: int) -> Color:
	return [GOLD, SILVER, BRONZE][i] if i < 3 else Color(0.42, 0.44, 0.52)


func _make_row(r: Dictionary, i: int, sz: Vector2, rank_w: float, name_w: float, col_w: float, total_w: float) -> Control:
	var me := int(r.get("id", 0)) == my_id
	var row := PanelContainer.new()
	row.size = sz
	row.custom_minimum_size = sz
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Color(0.09, 0.09, 0.14, 0.92)
	var border := Color(1, 1, 1, 0.1)
	var glow := Color(0, 0, 0, 0)
	if i == 0:
		bg = Color(0.24, 0.17, 0.04, 0.95)
		border = GOLD
		glow = Color(GOLD, 0.45)
	elif me:
		bg = Color(0.05, 0.16, 0.19, 0.95)
		border = TEAL
	var st := UI.flat(bg, border, 14, glow)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	row.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var fs := int(clampf(sz.y * 0.48, 20, 30))
	# sıra rozeti
	var badge := UI.title(str(i + 1), int(fs * 0.9), Color.WHITE if i >= 3 else Color(0.12, 0.08, 0.02), true)
	var bs := StyleBoxFlat.new()
	bs.bg_color = _rank_color(i)
	bs.set_corner_radius_all(100)
	badge.add_theme_stylebox_override("normal", bs)
	if i < 3:
		badge.add_theme_constant_override("outline_size", 0)
		badge.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.25))
		badge.add_theme_constant_override("shadow_offset_y", 2)
		badge.add_theme_constant_override("shadow_offset_x", 0)
	var bsz := minf(rank_w, sz.y - 10.0)
	badge.custom_minimum_size = Vector2(bsz, bsz)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bwrap := CenterContainer.new()
	bwrap.custom_minimum_size = Vector2(rank_w, 0)
	bwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bwrap.add_child(badge)
	h.add_child(bwrap)
	# ad
	var name_col := GOLD.lightened(0.3) if i == 0 else (TEAL if me else Color.WHITE)
	var nl := UI.title(str(r.get("name", "?")), fs, name_col)
	nl.custom_minimum_size = Vector2(name_w, 0)
	nl.size_flags_vertical = Control.SIZE_FILL
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(nl)
	if bool(r.get("left", false)):
		nl.modulate.a = 0.5
	# oyun oyun puanlar
	var cells: Array = []
	var pts: Array = r.get("p", [])
	for k in _games.size():
		var v: int = int(pts[k]) if k < pts.size() else 0
		var c := UI.title(("+%d" % v) if v > 0 else str(v), fs, GREEN if v > 0 else (RED if v < 0 else GRAY), true)
		c.custom_minimum_size = Vector2(col_w, 0)
		c.size_flags_vertical = Control.SIZE_FILL
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if v == 0:
			c.add_theme_font_size_override("font_size", int(fs * 0.8))
		h.add_child(c)
		cells.append(c)
	# toplam
	var tot := UI.title("0", int(fs * 1.15), Color.WHITE, true)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0, 0, 0, 0.35)
	ts.set_corner_radius_all(10)
	tot.add_theme_stylebox_override("normal", ts)
	tot.custom_minimum_size = Vector2(total_w, sz.y - 14.0)
	tot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(tot)
	row.set_meta("cells", cells)
	row.set_meta("total", tot)
	row.set_meta("score", int(r.get("score", 0)))
	for c in cells:
		(c as Control).modulate.a = 0.0
	return row


func _winner_id() -> int:
	var w: int = int(data.get("winner", 0))
	if w == 0 and _rows.size() > 0:
		w = int((_rows[0] as Dictionary).get("id", 0))
	return w


func _row_of(id: int) -> Dictionary:
	for r in _rows:
		if int((r as Dictionary).get("id", 0)) == id:
			return r
	return {}


# ---------- açılış sırası ----------

func _wait(t: float) -> void:
	await get_tree().create_timer(t * (0.12 if _fast else 1.0)).timeout


func _play(n: String, vol := 0.0, pitch := 1.0) -> void:
	var path := "res://assets/ses/%s.ogg" % n
	if not ResourceLoader.exists(path):
		return
	_play_stream(load(path), vol, pitch)


func _play_stream(s: AudioStream, vol := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = vol
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p


func _pop(c: Control, from := 0.4, t := 0.22) -> void:
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2.ONE * from
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "scale", Vector2.ONE, t).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, t * 0.6)


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# başlık yukarıdan düşer
	_title.modulate.a = 0.0
	_pop(_title, 1.8, 0.35)
	_play("anons", -4.0)
	await _wait(0.45)
	var htw := _header.create_tween()
	htw.tween_property(_header, "modulate:a", 1.0, 0.3)
	_play("tik", -6.0)
	await _wait(0.45)
	var n := _row_nodes.size()
	for i in range(n - 1, 0, -1):
		await _reveal_row(i, i == n - 1 and n > 2)
		await _wait(0.2 if i > 3 else 0.55)
	await _winner()


# Bir sırayı sağdan kaydırarak getirir, oyun puanlarını tek tek yakar, toplamı sayarak yazar.
func _reveal_row(i: int, last: bool) -> void:
	var row: Control = _row_nodes[i]
	var x0 := row.position.x
	row.position.x = x0 + 260.0
	var tw := row.create_tween().set_parallel()
	tw.tween_property(row, "position:x", x0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(row, "modulate:a", 1.0, 0.2)
	_play("sec", -2.0, 0.9 + 0.05 * (_row_nodes.size() - i))
	await _wait(0.25)
	var cells: Array = row.get_meta("cells")
	var dt := minf(0.09, 0.55 / maxf(1.0, cells.size()))
	for k in cells.size():
		_pop(cells[k], 0.3, 0.18)
		_play("tik_ui", -6.0, 1.0 + 0.06 * k)
		await _wait(dt)
	var tot: Label = row.get_meta("total")
	var score: int = int(row.get_meta("score"))
	var ttw := tot.create_tween()
	ttw.tween_method(func(v: float) -> void: tot.text = str(roundi(v)), 0.0, float(score), 0.3 if not _fast else 0.05)
	await _wait(0.3)
	tot.text = str(score)
	_pop(tot, 1.5, 0.25)
	if last:
		# sonuncuya küçük bir "üzgünüz" sesi ve titreme
		_play("vizilti", -10.0)
		var sh := row.create_tween()
		for k in 4:
			sh.tween_property(row, "position:x", x0 + (8.0 if k % 2 == 0 else -8.0), 0.05)
		sh.tween_property(row, "position:x", x0, 0.05)
	else:
		_play("tik", -8.0)


func _winner() -> void:
	var wid := _winner_id()
	var row: Control = _row_nodes[0] if _row_nodes.size() > 0 else null
	# tablo sağa kayar, sahne karanlıkta belirir (siluet), davul çalar
	var tw := _table.create_tween()
	tw.tween_property(_table, "position:x", _table_final_x, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var stw := _stage.create_tween()
	stw.tween_property(_stage, "modulate:a", 1.0, 0.5)
	var roll := _play_stream(_drumroll(1.9 if not _fast else 0.5), -3.0)
	await _wait(1.9)
	if is_instance_valid(roll):
		roll.stop()
	# BAM: ışıklar yanar, beyaz parlama, ziller
	_play_stream(_crash(), -2.0)
	_flash.color.a = 0.75
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, 0.6)
	var ltw := create_tween().set_parallel()
	ltw.tween_property(_key, "light_energy", 1.25, 0.25)
	ltw.tween_property(_spot, "light_energy", 7.0, 0.25)
	ltw.tween_property(_env, "ambient_light_energy", 0.5, 0.4)
	_stage_rays.create_tween().tween_property(_stage_rays, "modulate:a", 1.0, 0.5)
	if row:
		var x0 := row.position.x
		row.position.x = x0 + 260.0
		var rtw := row.create_tween().set_parallel()
		rtw.tween_property(row, "position:x", x0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rtw.tween_property(row, "modulate:a", 1.0, 0.2)
		for c in row.get_meta("cells"):
			_pop(c, 0.3, 0.25)
		var tot: Label = row.get_meta("total")
		tot.text = str(int(row.get_meta("score")))
		_pop(tot, 1.8, 0.3)
	_win_title.text = "KAZANDIN!" if wid == my_id else "KAZANAN"
	_pop(_win_title, 2.2, 0.4)
	_win_name.text = str(_row_of(wid).get("name", "?"))
	_win_name.create_tween().tween_property(_win_name, "modulate:a", 1.0, 0.4)
	await _wait(0.55)
	# taç yukarıdan düşer
	_drop_crown()
	await _wait(0.95)
	_on_crown_landed()
	_done = true
	await get_tree().create_timer(0.9).timeout
	_back_btn.visible = true
	_back_btn.create_tween().tween_property(_back_btn, "modulate:a", 1.0, 0.35)
	# birkaç kez daha konfeti
	for k in 3:
		await get_tree().create_timer(1.6).timeout
		if not is_inside_tree():
			return
		Fx.confetti(self, Vector2(_stage.position.x + _stage.size.x * randf_range(0.2, 0.8), _sz.y * 0.95), ["#ffc23a", "#ffffff", "#5be37d", "#3fd6f0", "#ff5a8a"])


func _head_top() -> Vector3:
	var skel: Skeleton3D = _body.get("_skel")
	if not is_instance_valid(skel):
		return _body.global_position + Vector3(0, 1.75, 0)
	var top_i := skel.find_bone("mixamorig_HeadTop_End")
	var head_i := skel.find_bone("mixamorig_Head")
	if top_i < 0:
		return skel.global_transform * skel.get_bone_global_pose(head_i).origin + Vector3(0, 0.18, 0)
	return skel.global_transform * skel.get_bone_global_pose(top_i).origin


func _crown_target() -> Vector3:
	return _head_top() + Vector3(0, -0.05, 0)


func _drop_crown() -> void:
	_crown.visible = true
	_fall_from = _crown_target() + Vector3(0, 1.6, 0)
	_crown.global_position = _fall_from
	_fall_t = 0.0
	_play("isinlan", -8.0, 1.4)


func _process(delta: float) -> void:
	if _fall_t < 0.0 or not is_instance_valid(_crown):
		return
	_fall_t = minf(1.0, _fall_t + delta / (0.85 if not _fast else 0.2))
	var e := _bounce(_fall_t)
	var target := _crown_target()
	_crown.global_position = _fall_from.lerp(target, e)
	_crown.rotation = Vector3(0, _body.rotation.y + (1.0 - _fall_t) * TAU * 2.0, (1.0 - _fall_t) * 0.6 + 0.12 * _fall_t)
	if _fall_t >= 1.0:
		_fall_t = -1.0


# Yere düşen topun sekmesi gibi (0..1)
static func _bounce(t: float) -> float:
	var n1 := 7.5625
	var d1 := 2.75
	if t < 1.0 / d1:
		return n1 * t * t
	elif t < 2.0 / d1:
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elif t < 2.5 / d1:
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	t -= 2.625 / d1
	return n1 * t * t + 0.984375


func _on_crown_landed() -> void:
	_fall_t = -1.0
	_crown.global_position = _crown_target()
	_crown.rotation = Vector3(0, _body.rotation.y, 0.12)
	# tacı kafa kemiğine bağla: karakter dans ederken kafasında kalsın
	var skel: Skeleton3D = _body.get("_skel")
	if is_instance_valid(skel):
		var head_i := skel.find_bone("mixamorig_Head")
		if head_i >= 0:
			_crown_ba = BoneAttachment3D.new()
			_crown_ba.bone_idx = head_i
			skel.add_child(_crown_ba)
			_crown.reparent(_crown_ba, true)
	_play("kilit", -2.0)
	_play("parilti", 0.0)
	_play_stream(_fanfare(), -4.0)
	_play("odul", -3.0)
	if _body.has_method("play_emote"):
		_body.play_emote("dans")
	var cols := ["#ffc23a", "#ffffff", "#5be37d", "#3fd6f0", "#ff5a8a"]
	var cx := _stage.position.x + _stage.size.x / 2.0
	Fx.confetti(self, Vector2(cx, _sz.y * 0.55), cols)
	Fx.confetti(self, Vector2(40, _sz.y), cols)
	Fx.confetti(self, Vector2(_sz.x - 40, _sz.y), cols)


# ---------- koddan üretilen sesler ----------

static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data_b := PackedByteArray()
	data_b.resize(s.size() * 2)
	for i in s.size():
		data_b.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data_b
	return w


# Trampet davulu: vuruşlar gittikçe sıklaşır ve güçlenir.
static func _drumroll(len: float) -> AudioStreamWAV:
	var n := int(RATE * len)
	var s := PackedFloat32Array()
	s.resize(n)
	var next_hit := 0.0
	var last_hit := -1.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / len
		if t >= next_hit:
			last_hit = t
			next_hit = t + lerpf(1.0 / 11.0, 1.0 / 32.0, k)
		var since := t - last_hit
		var noise := randf_range(-1.0, 1.0)
		lp = lp * 0.55 + noise * 0.45
		var env := exp(-since * 38.0)
		var amp := 0.18 + 0.62 * pow(k, 1.6)
		s[i] = (lp * 0.75 + sin(TAU * 190.0 * since) * 0.35) * env * amp
	return _wav(s)


# Zil + bas vuruşu (karanlıktan ışığa geçişte).
static func _crash() -> AudioStreamWAV:
	var len := 1.6
	var n := int(RATE * len)
	var s := PackedFloat32Array()
	s.resize(n)
	var hp_prev := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		hp = 0.92 * (hp + noise - hp_prev)  # tiz: zil
		hp_prev = noise
		var cym := hp * exp(-t * 2.6) * 0.45
		var boom := sin(TAU * (55.0 + 40.0 * exp(-t * 18.0)) * t) * exp(-t * 5.0) * 0.8
		s[i] = cym + boom
	return _wav(s)


# Kısa zafer borusu: do-mi-sol-DO (son nota akor ve titreşimli).
static func _fanfare() -> AudioStreamWAV:
	var notes := [[261.63, 0.0, 0.13], [329.63, 0.13, 0.13], [392.0, 0.26, 0.13], [523.25, 0.42, 0.9]]
	var len := 1.45
	var n := int(RATE * len)
	var s := PackedFloat32Array()
	s.resize(n)
	for nt in notes:
		var f: float = nt[0]
		var st: float = nt[1]
		var d: float = nt[2]
		var chord: Array = [1.0] if d < 0.5 else [1.0, 1.25, 1.5]
		var i0 := int(st * RATE)
		var i1 := mini(n, int((st + d + 0.12) * RATE))
		for i in range(i0, i1):
			var t := float(i - i0) / RATE
			var env := minf(1.0, t / 0.02) * (1.0 if t < d else exp(-(t - d) * 30.0))
			if d > 0.5:
				env *= 1.0 - 0.35 * (t / d)
			var vib := 1.0 + (0.006 * sin(TAU * 5.5 * t) if t > 0.15 else 0.0)
			var v := 0.0
			for c in chord:
				var ff: float = f * float(c) * vib
				for hh in range(1, 7):
					v += sin(TAU * ff * hh * t) / float(hh * hh) * (1.0 if hh < 4 else 0.6)
			s[i] += v * env * 0.22 / float(chord.size()) * 1.4
	return _wav(s)
