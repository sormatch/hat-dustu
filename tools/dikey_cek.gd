# Mağaza dikey tanıtım görselleri: yazısız 3D plaka çekimleri (oyunun gerçek sahnesi, karakterleri, eşyaları).
# Çalıştırma: magaza/araclar/dikey_cek.sh <iphone|ipad|play> <sahne>   (fragman_cek.gd "d_" ile başlayan sahneleri buraya yollar)
# Yazı yok: başlıklar magaza/araclar/dikey_afis.gd ile plakanın üstüne yazılır.
# Oyunun davranışını değiştirmez: sadece çekim anında sahneye kamera, oyuncu kuklası ve ek ışık koyar.
extends RefCounted

const FC := preload("res://tools/fragman_cek.gd")
const TT := preload("res://tools/tiktok_cek.gd")
const Props := preload("res://scripts/modlar/props.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const TelefonScript := preload("res://scripts/telefon.gd")

static var oran := "iphone"
static var sv: SubViewport = null
static var hedef_boyut := Vector2i(1290, 2796)


static func run(w: Node3D, args: Dictionary, sahne: String) -> void:
	oran = str(args.get("oran", "iphone"))
	if w.walker:
		w.walker.visible = false
		w.walker.global_position = Vector3(3.9, -20, 0)
	# Pencere ekrana sığmak zorunda; asıl kare ayrı çizim yüzeyinde (aynı 3D dünya), istenen çözünürlükte çizilir.
	hedef_boyut = Vector2i(int(args.get("gen", "1290")), int(args.get("yuk", "2796")))
	var ss := float(args.get("ss", "1.5"))
	sv = SubViewport.new()
	sv.size = Vector2i(Vector2(hedef_boyut) * ss)
	sv.world_3d = w.get_viewport().find_world_3d()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	sv.handle_input_locally = false
	w.add_child(sv)
	w.get_viewport().disable_3d = true
	_kalite(w)
	match sahne:
		"d_kimkim":
			await _kimkim(w, args)
		_:
			await load("res://tools/dikey_cek2.gd").sahne(w, args, sahne)
	await _oturt(w)
	for l in w.find_children("*", "Label3D", true, false):  # oyuncu ad etiketleri görünmesin (kapı numaraları kalır)
		if str((l as Label3D).text) in ["Sen", "Kara Ali", "Sinsi Necmi", "Deli Rıza"]:
			(l as Label3D).visible = false
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if img.get_size() != hedef_boyut:
		img.resize(hedef_boyut.x, hedef_boyut.y, Image.INTERPOLATE_LANCZOS)
	img.save_png(str(args.get("shot", "")))
	print("yazildi ", img.get_size(), " ", Time.get_ticks_msec())
	OS.kill(OS.get_process_id())  # çıkış temizliğinde takılmasın


# Kare keskinliği: oyunun en yüksek ayarının üstü (yalnız çekimde)
static func _kalite(w: Node3D) -> void:
	var vp: Viewport = sv
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = 8192
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	vp.mesh_lod_threshold = 0.0
	var env: Environment = w.get("env")
	if env:
		env.glow_enabled = true
		env.glow_bloom = 0.05
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 3.0
		if RenderingServer.get_current_rendering_method() == "forward_plus":
			env.ssao_enabled = true
			env.ssao_intensity = 1.6
			env.ssao_radius = 0.5


static func _oturt(w: Node3D) -> void:
	for i in 6:
		await w.get_tree().process_frame


static func _sec(iphone, ipad, play):
	match oran:
		"ipad":
			return ipad
		"play":
			return play
	return iphone


static func _kamera(w: Node3D) -> Camera3D:
	var cam := Camera3D.new()
	cam.near = 0.03
	sv.add_child(cam)
	cam.current = true
	cam.cull_mask &= ~int(w.player.FP_LAYER)  # birinci şahıs el/silah katmanı bu kamerada yok
	w.player.body.visible = false
	return cam


# Yatay görüş açısıyla kamera (dikey kadraj: genişlik sabit; en-boy değişince üst/alt açılır)
static func _kam(cam: Camera3D, pos: Vector3, hedef: Vector3, fov_yatay: float) -> void:
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.global_transform = TT._bak_xf(pos, hedef)
	cam.fov = fov_yatay


static func _omni(w: Node3D, pos: Vector3, renk: Color, guc: float, menzil: float, golge := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = renk
	l.light_energy = guc
	l.omni_range = menzil
	l.shadow_enabled = golge
	w.add_child(l)
	l.global_position = pos
	return l


static func _spot(w: Node3D, pos: Vector3, hedef: Vector3, renk: Color, guc: float, aci: float, menzil: float, golge := true) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = renk
	l.light_energy = guc
	l.spot_angle = aci
	l.spot_range = menzil
	l.shadow_enabled = golge
	w.add_child(l)
	l.global_position = pos
	l.look_at(hedef, Vector3.UP)
	return l


# Sahneye süs dokusu (AI: gökyüzü, ateş). Kameraya dönük düz yüzey; karakterlerin arkasında kalır, derinlik doğru olur.
static func _pano(w: Node3D, ad: String, pos: Vector3, boyut: Vector2, bakis: Vector3, toplamali := false, renk := Color.WHITE) -> MeshInstance3D:
	var img := Image.load_from_file("D:/HatDustu/magaza/araclar/sus/%s.png" % ad)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = renk
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if toplamali:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var q := QuadMesh.new()
	q.size = boyut
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	mi.global_position = pos
	mi.look_at(bakis, Vector3.UP, true)
	return mi


# Görünür ışık huzmesi (kenarları yumuşak koni, tepeden aşağı söner). Oyundaki huzmenin çekime özel güçlü hali.
static func _huzme(w: Node3D, top: Vector3, hedef: Vector3, r1: float, r2: float, renk: Color, guc: float) -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 renk;
uniform float guc;
varying float h;
void vertex() {
	h = VERTEX.y + 0.5;
}
void fragment() {
	float kenar = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	ALBEDO = renk * guc * kenar * pow(clamp(h, 0.0, 1.0), 1.7);
	ALPHA = 1.0;
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("renk", Vector3(renk.r, renk.g, renk.b))
	m.set_shader_parameter("guc", guc)
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r2
	c.height = 1.0
	c.radial_segments = 48
	c.cap_top = false
	c.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	var y := (top - hedef).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(x, y * top.distance_to(hedef), x.cross(y)), (top + hedef) / 2.0)
	return mi


# --- 1) KİM KİM: hücresinde kırmızı telefonla konuşan mahkûm ---
# Telefon sağ duvarda (+x), arka köşeye yakın. Mahkûm sırtı duvara yakın, sağ eli telefon tarafında; kamera odanın içinden bakar.
static func _kimkim(w: Node3D, args: Dictionary) -> void:
	for cc in w.cells:
		cc.set_door(false, true)
	var c: Node3D = w.cells[w.my_cell]
	c.set_detailed(true)
	c.dust.visible = false
	c.dust.emitting = false
	var cam := _kamera(w)
	w.player.global_position = c.to_global(Vector3(-1.0, 0, 1.6))
	var mp: Vector3 = c.to_global(Vector3(1.42, 0, -1.55))
	var yaw := PI / 2.0 - 0.15  # yüzü -x (kameraya)
	var look: Dictionary = TT.LOOKS[int(args.get("kim", "2"))]
	var b: Node3D = FC._mahkum(w, look, mp, yaw)
	await w.get_tree().process_frame
	var pose: Node = AimMod.of_body(b)
	var ahize := Node3D.new()
	ahize.name = "UzakAhize"
	w.add_child(ahize)
	var h: Node3D = TelefonScript.handset(ahize)
	h.scale = Vector3.ONE * TelefonScript.SCALE
	h.get_node("kablo_ucu").reparent(ahize)
	if pose:
		pose.mode = "ahize"
		pose.aim = 1.0
		pose.hold(1, ahize, AimMod.item_offset("ahize", 1))
	c.set_handset_lifted(true, ahize)
	var pos: Vector3 = c.to_global(Vector3(0.28, 1.28, -1.2))
	var hedef: Vector3 = c.to_global(Vector3(1.42, _sec(1.47, 1.46, 1.46), -1.6))
	_kam(cam, pos, hedef, _sec(36.0, 52.0, 41.0))
	b.set("bakis", pos + Vector3(0, 0.25, 0.5))
	# sinematik ek ışık: sıcak ana ışık + telefon tarafından kırmızı kontur
	_spot(w, c.to_global(Vector3(0.1, 2.3, -0.2)), mp + Vector3(0, 1.5, 0), Color(1.0, 0.9, 0.8), 0.5, 26.0, 5.0)
	_spot(w, c.to_global(Vector3(0.35, 1.6, -1.2)), mp + Vector3(0, 1.58, -0.05), Color(1.0, 0.93, 0.85), 0.5, 11.0, 3.0, false)
	_omni(w, c.to_global(Vector3(1.75, 1.7, -2.5)), Color(1.0, 0.16, 0.08), 0.7, 1.8)
	_omni(w, c.to_global(Vector3(0.9, 1.4, -0.3)), Color(0.45, 0.6, 1.0), 0.5, 2.0)
	var env: Environment = w.get("env")
	env.tonemap_exposure = 0.62
	env.tonemap_white = 5.0
	await FC._bekle(w, 1.5)
	b.set("talk", 0.35)
	await w.get_tree().process_frame
