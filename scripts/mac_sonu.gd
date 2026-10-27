# Maç sonu ekranı: puan tablosu (satırlar oyuncular, sütunlar oynanan oyunlar, sağda toplam) sondan başa
# satır satır açılır: satır kayarak gelir, sıra madalyası damga gibi iner, oyun puanları tek tek yanar, toplam
# sayarak yazar. En son ekran kararır, sinema bantları iner, davul çalar; BAM ile ışıklar yanar, 1. sahnede
# belirir, kafasına altın kral tacı düşer, konfeti patlar, birincinin satırında altın parıltı geçer.
# Ekrana dokunmak açılışı hızlandırır.
# game_ui.on_over açar: setup(d, my_id, net.players); "again" (TEKRAR OYNA: aynı odanın bekleme salonu)
# ve "back" (ÇIKIŞ: ana menü) sinyalleri. Diğer oyuncuların durumu satırların köşesinde: LOBİDE / ÇIKTI.
extends Control

signal back
signal again

const UI := preload("res://scripts/ui.gd")
const Fx := preload("res://scripts/store_fx.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")

const GREEN := Color("#5be37d")
const RED := Color("#ff5a5a")
const GRAY := Color(0.55, 0.57, 0.56)
const GOLD := Color("#ffc23a")
const SILVER := Color("#cfd6e0")
const BRONZE := Color("#d98a4a")
const TEAL := Color("#5ff0ff")
const RATE := 22050
const BASLIK_H := 74.0   # sütun başlıkları (oyun rozeti + kısa ad)
const BANT_H := 58.0     # sinema bantları

var data: Dictionary = {}
var my_id := 0
var looks: Dictionary = {}  # oyuncu kimliği -> görünüş

var _rows: Array = []  # sunucunun sıraladığı tablo (0 = kazanan)
var _games: Array = []
var _row_nodes: Array = []  # her sıranın satırı
var _table: Control
var _table_final_x := 0.0
var _title: Control
var _header: Control
var _stage: Control
var _stage_rays: Control
var _win_title: Label
var _win_name: Control
var _back_btn: Button  # ÇIKIŞ (ikincil)
var _again_btn: Button  # TEKRAR OYNA (ana)
var _btns: HBoxContainer
var _donus_rozet: PanelContainer  # TEKRAR OYNA köşesinde: kaç saniye sonra kendiliğinden lobiye dönülecek
var _donus := -1.0
var _bots := {}  # bot oyuncuların kimlikleri (durum etiketi almazlar)
var _flash: ColorRect
var _karanlik: ColorRect  # davul sırasında ekran kararır
var _bant_ust: ColorRect
var _bant_alt: ColorRect
var _fast := false
var _done := false
var _sz := Vector2(1280, 720)
var _pay := Vector4.ZERO  # güvenli alan (çentik): sol, üst, sağ, alt

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
			if bool(p.get("bot", false)):
				_bots[int(p.get("id", 0))] = true
	_rows = d.get("table", [])
	_games = d.get("oyunlar", [])
	_donus = float(d.get("donus", -1))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sz = get_viewport_rect().size
	var g := UI.guvenli_pay()
	_pay = Vector4(maxf(g.x, 12.0), g.y, maxf(g.z, 12.0), g.w)
	_build_background()
	_build_stage()
	_build_table()
	_karanlik = ColorRect.new()
	_karanlik.color = Color(0, 0, 0, 0)
	_karanlik.set_anchors_preset(Control.PRESET_FULL_RECT)
	_karanlik.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_karanlik)
	move_child(_stage, get_child_count() - 1)  # sahne karanlığın önünde: kararınca yalnız kazanan aydınlık kalır
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.95, 0.8, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	for ust in [true, false]:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0, 0.92)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.size = Vector2(_sz.x, BANT_H)
		b.position = Vector2(0, -BANT_H if ust else _sz.y)
		add_child(b)
		if ust:
			_bant_ust = b
		else:
			_bant_alt = b
	# alt: ÇIKIŞ (ana menü) + TEKRAR OYNA (aynı odada yeni maç; ekranın tek ana eylemi)
	_btns = HBoxContainer.new()
	_btns.add_theme_constant_override("separation", UI.B_M)
	_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	_back_btn = UI.button("ÇIKIŞ", "ikincil", UI.BTN_H, UI.FS_ORTA, "geri", 210)
	_back_btn.pressed.connect(func() -> void: _sec(back))
	_btns.add_child(_back_btn)
	_again_btn = UI.button("TEKRAR OYNA", "ana", UI.BTN_H, UI.FS_BUYUK - 4, "oyna", 340)
	_again_btn.pressed.connect(func() -> void: _sec(again))
	_btns.add_child(_again_btn)
	_donus_rozet = UI.badge_on(_again_btn, maxi(0, ceili(_donus)), 34)
	var bw := 210.0 + 340.0 + UI.B_M
	_btns.size = Vector2(bw, UI.BTN_H)
	var bx := clampf(_table_final_x + _table.size.x / 2.0 - bw / 2.0, _pay.x, _sz.x - _pay.z - bw)
	_btns.position = Vector2(bx, _sz.y - _pay.w - UI.BTN_H - 14.0)
	_btns.modulate.a = 0.0
	_btns.visible = false
	add_child(_btns)
	# Android geri tuşu / Esc: gösteri bitip düğmeler çıktıysa ana menüye döner (ÇIKIŞ)
	UI.geri_tusu(self, func() -> void:
		if _btns.visible:
			_sec(back))
	_run()


# Düğmeye bir kez basılır (ikinci dokunuş ikinci kez göndermesin).
func _sec(sig: Signal) -> void:
	if _back_btn.disabled:
		return
	_back_btn.disabled = true
	_again_btn.disabled = true
	sig.emit()


# Diğer oyuncuların durumu (net.players her değiştiğinde): listede ve maç sonu ekranında değilse LOBİDE,
# listede yoksa ÇIKTI. Kendi satırın ve botlar etiket almaz.
func set_players(players: Array) -> void:
	var durum := {}
	for p in players:
		if typeof(p) == TYPE_DICTIONARY:
			durum[int(p.get("id", 0))] = "" if bool(p.get("ms", false)) or bool(p.get("kopuk", false)) else "lobi"
	for i in _row_nodes.size():
		var id := int((_rows[i] as Dictionary).get("id", 0))
		if id == my_id or _bots.has(id):
			continue
		_etiket(_row_nodes[i], str(durum.get(id, "cikti")))


# Satırın sağ üst köşesinde küçük durum etiketi ("" kaldırır).
func _etiket(row: Control, kind: String) -> void:
	var host: Control = row.get_meta("tag_host")
	var old: Control = row.get_meta("tag") if row.has_meta("tag") else null
	if old and str(old.get_meta("kind", "")) == kind:
		return
	if is_instance_valid(old):
		old.queue_free()
	row.remove_meta("tag")
	if kind == "":
		return
	var renk := UI.YESIL if kind == "lobi" else UI.KIRMIZI
	var pill := PanelContainer.new()
	var st := UI.flat(Color(renk.darkened(0.55), 0.96), renk, 10)
	st.set_border_width_all(2)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", st)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.title("LOBİDE" if kind == "lobi" else "ÇIKTI", UI.FS_KUCUK - 2, Color.WHITE, true)
	pill.add_child(l)
	pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pill.offset_right = -6
	pill.offset_left = -6
	pill.offset_top = -16
	pill.set_meta("kind", kind)
	host.add_child(pill)
	row.set_meta("tag", pill)
	pill.pivot_offset = Vector2(40, 12)
	pill.scale = Vector2.ONE * 0.6
	pill.create_tween().tween_property(pill, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(e: InputEvent) -> void:
	if not _done and ((e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed)):
		_fast = true


# ---------- kurulum ----------

func _build_background() -> void:
	# menüdeki koridor görseli, iyice karartılmış; kazananın sahnesinin arkasında sıcak amber ışık
	add_child(UI.background("bg_menu", 0.8))
	var hale := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(UI.AMBER, 0.28))
	gr.set_color(1, Color(UI.AMBER, 0.0))
	gt.gradient = gr
	hale.texture = gt
	hale.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hale.stretch_mode = TextureRect.STRETCH_SCALE
	var w := _stage_w()
	hale.position = Vector2(_pay.x + w / 2.0 - w * 0.9, _sz.y * 0.5 - w * 0.9)
	hale.size = Vector2(w, w) * 1.8
	hale.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hale)
	var vig := TextureRect.new()
	var vt := GradientTexture2D.new()
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.45)
	vt.fill_to = Vector2(1.05, 1.05)
	var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0.05))
	vg.set_color(1, Color(0, 0, 0, 0.85))
	vt.gradient = vg
	vig.texture = vt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)


func _stage_w() -> float:
	# çok oyun oynandıysa tabloya yer açmak için sahne daralır
	var k := 0.31 if _games.size() < 6 else (0.27 if _games.size() < 8 else 0.24)
	return clampf((_sz.x - _pay.x - _pay.z) * k, 290.0, 440.0)


func _build_stage() -> void:
	var w := _stage_w()
	_stage = Control.new()
	_stage.position = Vector2(_pay.x, _pay.y)
	_stage.size = Vector2(w, _sz.y - _pay.y - _pay.w)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.modulate.a = 0.0
	add_child(_stage)
	var sh := _stage.size.y
	_stage_rays = Fx.Rays.new()
	_stage_rays.color = GOLD
	_stage_rays.size = Vector2(w, w)
	_stage_rays.position = Vector2(0, sh * 0.42 - w / 2.0)
	_stage_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_rays.modulate.a = 0.0
	_stage.add_child(_stage_rays)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.position = Vector2(0, 70)
	svc.size = Vector2(w, sh - 70 - 120)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)
	_build_3d(sv)
	_win_title = UI.title("", UI.FS_DEV + 2, GOLD, true)
	_win_title.add_theme_constant_override("outline_size", 10)
	_win_title.position = Vector2(0, 14)
	_win_title.size = Vector2(w, 60)
	_win_title.modulate.a = 0.0
	_stage.add_child(_win_title)
	# kazananın adı: altın kenarlı isim plakası
	var plaka := PanelContainer.new()
	var pst := UI.flat(Color(0.05, 0.04, 0.02, 0.92), GOLD, UI.R_BUYUK, Color(GOLD, 0.35))
	pst.set_border_width_all(3)
	pst.content_margin_left = 22
	pst.content_margin_right = 22
	pst.content_margin_top = 4
	pst.content_margin_bottom = 6
	plaka.add_theme_stylebox_override("panel", pst)
	plaka.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UI.title("", 34, Color.WHITE, true)
	plaka.add_child(nl)
	plaka.set_meta("label", nl)
	var pc := CenterContainer.new()
	pc.position = Vector2(0, sh - 112)
	pc.size = Vector2(w, 64)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(plaka)
	_stage.add_child(pc)
	_win_name = plaka
	_win_name.modulate.a = 0.0


func _build_3d(sv: SubViewport) -> void:
	var root := Node3D.new()
	sv.add_child(root)
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.6, 0.62, 0.7)
	_env.ambient_light_energy = 0.04
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# altın parlasın diye yansımalar için gökyüzü (arka plan şeffaf kalır)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#3a4a40")
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
	# arkadan soğuk kenar ışığı: ışıklar sönükken karakter siluet gibi görünür
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.0, 2.2, 1.3)
	rim.light_color = Color("#8fb8ff")
	rim.light_energy = 3.0
	rim.omni_range = 4.0
	root.add_child(rim)
	# kürsü: koyu çelik, altın kenar
	var ped := CylinderMesh.new()
	ped.top_radius = 0.62
	ped.bottom_radius = 0.7
	ped.height = 0.5
	ped.radial_segments = 48
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#1c201d")
	pm.metallic = 0.6
	pm.roughness = 0.4
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


# Oyunun rozeti (assets/ui/uretim/oyun_<görev>.png); görev adı gelmediyse oyunun adından bulunur.
static func _oyun_rozet(task: String, px: float, baslik := "") -> Control:
	if task == "":
		var b := baslik.to_lower().replace("ı", "i").replace("İ", "i").replace("i̇", "i")
		for k in [["kim", "kimkim"], ["tahta", "tahta"], ["devre", "devre"], ["yalanc", "yalanci"], ["rulet", "rulet"], ["c4", "c4"], ["ortalama", "ortalama"], ["projekt", "projektor"]]:
			if b.contains(k[0]):
				task = k[1]
				break
	var ad := "uretim/oyun_" + task
	if task != "" and UI.has(ad):
		var t := TextureRect.new()
		t.texture = UI.texture(ad, int(px * 2))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(px, px)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return t
	return UI.icon("oyna", px * 0.8)


func _build_table() -> void:
	var ng := _games.size()
	var x_min := _pay.x + _stage_w() + 12.0
	var x_max := _sz.x - _pay.z - 22.0
	var tw := minf(x_max - x_min, 960.0)
	var rank_w := 54.0
	var total_w := 104.0
	var inner := tw - 28.0 - rank_w - total_w - 10.0 * (ng + 2)
	var col_w := 0.0
	if ng > 0:
		# 8-9 oyunda sütunlar daralır, ada en az ~170 px kalır (adlar kesilmesin)
		col_w = clampf((inner - 190.0) / ng, 60.0, 118.0) if ng < 8 else clampf((inner - 170.0) / ng, 44.0, 118.0)
	var name_w := inner - col_w * ng
	var n := _rows.size()
	var top := _pay.y + 104.0
	var bottom := _sz.y - _pay.w - 112.0
	var row_h := clampf((bottom - top - BASLIK_H) / maxf(1.0, n), 46.0, 68.0)
	var block := BASLIK_H + row_h * n
	top = maxf(top, (top + bottom) / 2.0 - block / 2.0)
	_table = Control.new()
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.size = Vector2(tw, block)
	_table_final_x = x_max - tw
	_table.position = Vector2((_sz.x - tw) / 2.0, top)
	add_child(_table)
	# çelik panel (tablonun arkası)
	var pan := UI.panel(Vector2(tw + 36.0, block + 30.0), 18)
	pan.position = Vector2(-18.0, -12.0)
	pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan.modulate.a = 0.0
	_table.add_child(pan)
	_table.set_meta("panel", pan)
	# başlık plakası (tehlike şeritli)
	var hp := UI.header("MAÇ SONU", 34)
	hp.custom_minimum_size.x = minf(420.0, tw)
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.add_child(hp)
	hp.reset_size()
	hp.position = Vector2((tw - hp.size.x) / 2.0, _pay.y + 14.0 - top)
	hp.pivot_offset = hp.size / 2.0
	_title = hp
	# sütun başlıkları: oyunun rozeti + kısa adı
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	hrow.position = Vector2(14, 0)
	hrow.size = Vector2(tw - 28, BASLIK_H)
	hrow.modulate.a = 0.0
	hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.add_child(hrow)
	_header = hrow
	hrow.add_child(_spacer(rank_w + name_w + 10.0))
	# tüm başlıklar aynı boyda (en uzun ada göre; çok darsa biraz taşabilir)
	var hfs := UI.FS_KUCUK
	for g in _games:
		hfs = mini(hfs, _fit(str((g as Dictionary).get("ad", "?")), UI.FS_KUCUK, col_w + 14.0))
	hfs = maxi(hfs, 11)
	var rp := minf(46.0, col_w - 8.0)
	for gi in ng:
		var gd: Dictionary = _games[gi]
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(col_w, BASLIK_H)
		v.alignment = BoxContainer.ALIGNMENT_END
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rz := _oyun_rozet(str(gd.get("task", "")), rp, str(gd.get("ad", "")))
		rz.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(rz)
		# ad sütundan biraz genişse komşu boşluğa taşabilir (kırpılmaz)
		var hk := Control.new()
		hk.custom_minimum_size = Vector2(col_w, hfs + 6)
		hk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hl := UI.title(str(gd.get("ad", "?")), hfs, Color("#ffcf8a"), true)
		hl.add_theme_constant_override("outline_size", 4)
		hl.position = Vector2(-24.0, 0)
		hl.size = Vector2(col_w + 48.0, hfs + 6)
		hk.add_child(hl)
		v.add_child(hk)
		hrow.add_child(v)
	var tl := UI.title("TOPLAM", UI.FS_KUCUK + 2, UI.AMBER, true)
	tl.custom_minimum_size = Vector2(total_w, BASLIK_H)
	tl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	UI.sigdir(tl, total_w)
	hrow.add_child(tl)
	for i in n:
		var r: Dictionary = _rows[i]
		var row := _make_row(r, i, Vector2(tw, row_h - 8.0), rank_w, name_w, col_w, total_w)
		row.position = Vector2(0, BASLIK_H + 6.0 + row_h * i)
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
	while s > 11 and UI.TITLE_FONT.get_string_size(TranslationServer.translate(text), HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > w:
		s -= 1
	return s


static func _rank_color(i: int) -> Color:
	return [GOLD, SILVER, BRONZE][i] if i < 3 else Color(0.36, 0.4, 0.38)


func _make_row(r: Dictionary, i: int, sz: Vector2, rank_w: float, name_w: float, col_w: float, total_w: float) -> Control:
	var me := int(r.get("id", 0)) == my_id
	var row := PanelContainer.new()
	row.size = sz
	row.custom_minimum_size = sz
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Color(UI.YUZEY_2, 0.95)
	var border := Color(UI.CIZGI, 0.9)
	var glow := Color(0, 0, 0, 0)
	if i == 0:
		bg = Color(0.24, 0.17, 0.04, 0.97)
		border = GOLD
		glow = Color(GOLD, 0.45)
	elif me:
		bg = Color(0.04, 0.14, 0.15, 0.96)
		border = TEAL
	var st := UI.flat(bg, border, UI.R_ORTA, glow)
	st.set_border_width_all(3 if (i == 0 or me) else 2)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	row.add_theme_stylebox_override("panel", st)
	# birincinin satırında geçen altın parıltı için kırpılan katman
	var parilti := Control.new()
	parilti.clip_contents = true
	parilti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(parilti)
	row.set_meta("parilti", parilti)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var fs := int(clampf(sz.y * 0.48, 20, 30))
	# sıra madalyası
	var badge := UI.title(str(i + 1), int(fs * 0.9), Color.WHITE if i >= 3 else Color(0.12, 0.08, 0.02), true)
	var bs := StyleBoxFlat.new()
	bs.bg_color = _rank_color(i)
	bs.set_corner_radius_all(100)
	if i < 3:
		bs.border_color = _rank_color(i).lightened(0.45)
		bs.set_border_width_all(3)
		bs.shadow_color = Color(_rank_color(i), 0.45)
		bs.shadow_size = 6
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
	row.set_meta("madalya", badge)
	# ad (kendi satırında altında küçük "SEN")
	var name_col := GOLD.lightened(0.3) if i == 0 else (TEAL if me else UI.METIN)
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
	var tot := UI.title("0", int(fs * 1.15), Color.WHITE if i > 0 else GOLD.lightened(0.4), true)
	var ts := UI.flat(Color(0, 0, 0, 0.4), Color(UI.AMBER, 0.55 if i == 0 else 0.3), UI.R_KUCUK + 2)
	ts.set_border_width_all(2)
	ts.shadow_size = 0
	tot.add_theme_stylebox_override("normal", ts)
	tot.custom_minimum_size = Vector2(total_w, sz.y - 14.0)
	tot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(tot)
	# durum etiketi (LOBİDE / ÇIKTI) için satırın üstünde serbest katman: kenarın dışına taşabilir
	var tag_host := Control.new()
	tag_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag_host)
	row.set_meta("tag_host", tag_host)
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

# Güvenli bekleme: ekran sahneden çıktıysa (ör. açılış bitmeden ÇIKIŞ ya da TEKRAR OYNA) false döner ve açılış durur.
# Kullanım: if not await _wait(0.3): return
func _wait(t: float) -> bool:
	if not is_inside_tree():
		return false
	await get_tree().create_timer(t * (0.12 if _fast else 1.0)).timeout
	return is_inside_tree()


# Tam süre bekler (dokununca hızlanmaz); aynı güvenlik.
func _wait_real(t: float) -> bool:
	if not is_inside_tree():
		return false
	await get_tree().create_timer(t).timeout
	return is_inside_tree()


func _frame() -> bool:
	if not is_inside_tree():
		return false
	await get_tree().process_frame
	return is_inside_tree()


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
	if not await _frame() or not await _frame():
		return
	# başlık plakası yukarıdan iner, panel belirir
	var pan: Control = _table.get_meta("panel")
	pan.create_tween().tween_property(pan, "modulate:a", 1.0, 0.3)
	var y0 := _title.position.y
	_title.position.y = y0 - 90.0
	_title.modulate.a = 0.0
	var ttw := _title.create_tween().set_parallel()
	ttw.tween_property(_title, "position:y", y0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	ttw.tween_property(_title, "modulate:a", 1.0, 0.2)
	_play("anons", -4.0)
	if not await _wait(0.45):
		return
	var htw := _header.create_tween()
	htw.tween_property(_header, "modulate:a", 1.0, 0.3)
	_baslik_sirala(_header, 0.05)
	_play("tik", -6.0)
	if not await _wait(0.5):
		return
	var n := _row_nodes.size()
	# kalabalık maçta alt sıralar hızlı açılır (8 kişide kazanan ~10 sn beklemesin); ilk üç hep aynı tempoda
	var alt_k := 1.0 if n <= 5 else 0.5
	for i in range(n - 1, 0, -1):
		var k := 1.0 if i < 3 else alt_k
		if not await _reveal_row(i, i == n - 1 and n > 2, k):
			return
		if not await _wait((0.2 if i > 3 else 0.55) * k):
			return
	await _winner()


# Sütun başlıkları sırayla hafifçe zıplayarak belirir.
func _baslik_sirala(box: Control, adim: float) -> void:
	var k := 0
	for c in box.get_children():
		if not (c is VBoxContainer):
			continue
		var cc := c as Control
		cc.modulate.a = 0.0
		var tw := cc.create_tween()
		tw.tween_interval(k * adim * (0.2 if _fast else 1.0))
		tw.tween_property(cc, "modulate:a", 1.0, 0.18)
		k += 1


# Bir sırayı sağdan kaydırarak getirir, madalya damga gibi iner, oyun puanlarını tek tek yakar, toplamı
# sayarak yazar. Ekran kapandıysa false döner.
func _reveal_row(i: int, last: bool, k_hiz := 1.0) -> bool:
	var row: Control = _row_nodes[i]
	var x0 := row.position.x
	row.position.x = x0 + 260.0
	var tw := row.create_tween().set_parallel()
	tw.tween_property(row, "position:x", x0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(row, "modulate:a", 1.0, 0.2)
	_play("sec", -2.0, 0.9 + 0.05 * (_row_nodes.size() - i))
	if not await _wait(0.22 * k_hiz):
		return false
	var md: Control = row.get_meta("madalya")
	_pop(md, 2.3, 0.26)
	if i < 3:
		_play("kilit", -9.0, 1.2 - 0.1 * i)
	var cells: Array = row.get_meta("cells")
	var dt := minf(0.09, 0.55 / maxf(1.0, cells.size())) * k_hiz
	for k in cells.size():
		_pop(cells[k], 0.3, 0.18)
		_play("tik_ui", -6.0, 1.0 + 0.06 * k)
		if not await _wait(dt):
			return false
	var tot: Label = row.get_meta("total")
	var score: int = int(row.get_meta("score"))
	var ttw := tot.create_tween()
	ttw.tween_method(func(v: float) -> void: tot.text = str(roundi(v)), 0.0, float(score), 0.3 * k_hiz if not _fast else 0.05)
	if not await _wait(0.3 * k_hiz):
		return false
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
	return true


# Birincinin satırında soldan sağa geçen altın parıltı.
func _parilti(row: Control) -> void:
	var kap: Control = row.get_meta("parilti")
	var r := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 0.9, 0.55, 0.0))
	gr.add_point(0.5, Color(1, 0.92, 0.6, 0.55))
	gr.set_color(gr.get_point_count() - 1, Color(1, 0.9, 0.55, 0.0))
	gt.gradient = gr
	gt.width = 64
	gt.height = 4
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ek := CanvasItemMaterial.new()
	ek.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	r.material = ek
	r.size = Vector2(140, row.size.y + 40.0)
	r.rotation = 0.25
	kap.add_child(r)
	var tw := r.create_tween().set_loops(3)
	tw.tween_property(r, "position", Vector2(row.size.x + 60.0, -20.0), 0.9).from(Vector2(-200.0, -20.0)).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(1.4)
	tw.finished.connect(r.queue_free)


func _winner() -> void:
	var wid := _winner_id()
	var row: Control = _row_nodes[0] if _row_nodes.size() > 0 else null
	# tablo sağa kayar; ekran kararır, sinema bantları iner, sahne karanlıkta belirir (siluet), davul çalar
	var tw := _table.create_tween()
	tw.tween_property(_table, "position:x", _table_final_x, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var kt := _karanlik.create_tween().set_parallel()
	kt.tween_property(_karanlik, "color:a", 0.55, 0.5)
	kt.tween_property(_bant_ust, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	kt.tween_property(_bant_alt, "position:y", _sz.y - BANT_H, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	kt.tween_property(_title, "modulate:a", 0.0, 0.3)  # başlık plakası bantların altında kalmasın
	var stw := _stage.create_tween()
	stw.tween_property(_stage, "modulate:a", 1.0, 0.5)
	# karakter girişten itibaren seçilebilir aydınlıkta: davul boyunca loş bir ön ışık, BAM ile tam ışık
	var pre := create_tween().set_parallel()
	pre.tween_property(_key, "light_energy", 0.55, 0.45)
	pre.tween_property(_spot, "light_energy", 3.0, 0.45)
	pre.tween_property(_env, "ambient_light_energy", 0.28, 0.45)
	var roll := _play_stream(_drumroll(1.9 if not _fast else 0.5), -3.0)
	if not await _wait(1.9):
		return
	if is_instance_valid(roll):
		roll.stop()
	# BAM: ışıklar yanar, beyaz parlama, ziller; karanlık ve bantlar çekilir
	_play_stream(_crash(), -2.0)
	_flash.color.a = 0.75
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, 0.6)
	var at := _karanlik.create_tween().set_parallel()
	at.tween_property(_karanlik, "color:a", 0.0, 0.8).set_delay(0.3)
	at.tween_property(_bant_ust, "position:y", -BANT_H, 0.5).set_delay(0.9).set_trans(Tween.TRANS_CUBIC)
	at.tween_property(_bant_alt, "position:y", _sz.y, 0.5).set_delay(0.9).set_trans(Tween.TRANS_CUBIC)
	at.tween_property(_title, "modulate:a", 1.0, 0.4).set_delay(1.2)
	var ltw := create_tween().set_parallel()
	ltw.tween_property(_key, "light_energy", 1.25, 0.25)
	ltw.tween_property(_spot, "light_energy", 7.0, 0.25)
	ltw.tween_property(_env, "ambient_light_energy", 0.5, 0.4)
	_stage_rays.create_tween().tween_property(_stage_rays, "modulate:a", 0.75, 0.5)
	if row:
		var x0 := row.position.x
		row.position.x = x0 + 260.0
		var rtw := row.create_tween().set_parallel()
		rtw.tween_property(row, "position:x", x0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rtw.tween_property(row, "modulate:a", 1.0, 0.2)
		_pop(row.get_meta("madalya"), 2.6, 0.3)
		for c in row.get_meta("cells"):
			_pop(c, 0.3, 0.25)
		var tot: Label = row.get_meta("total")
		tot.text = str(int(row.get_meta("score")))
		_pop(tot, 1.8, 0.3)
	_win_title.text = "KAZANDIN!" if wid == my_id else "KAZANAN"
	_pop(_win_title, 2.2, 0.4)
	var wl: Label = _win_name.get_meta("label")
	wl.text = str(_row_of(wid).get("name", "?"))
	UI.sigdir(wl, _stage.size.x - 70.0)  # uzun ad plakaya sığsın
	_pop(_win_name, 0.6, 0.35)
	if not await _wait(0.55):
		return
	if row:
		_parilti(row)
	# taç yukarıdan düşer
	_drop_crown()
	if not await _wait(0.95):
		return
	_on_crown_landed()
	_done = true
	if not await _wait_real(0.9):
		return
	_btns.visible = true
	var y1 := _btns.position.y
	var btw := _btns.create_tween().set_parallel()
	btw.tween_property(_btns, "modulate:a", 1.0, 0.35)
	btw.tween_property(_btns, "position:y", y1, 0.4).from(y1 + 40.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# birkaç kez daha konfeti
	for k in 3:
		if not await _wait_real(1.6):
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
	if _donus > 0.0:
		# kendiliğinden lobiye dönüşe kalan süre (sunucu süre dolunca herkesi lobiye alır)
		var once := ceili(_donus)
		_donus = maxf(0.0, _donus - delta)
		if ceili(_donus) != once and is_instance_valid(_donus_rozet):
			UI.set_badge(_donus_rozet, ceili(_donus))
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
