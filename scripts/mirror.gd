# Duvardaki gerçek ayna: oyuncunun kamerasının ayna düzlemine göre yansıması ayrı bir kamerayla çizilir
# (eğik izdüşüm, ayna camı tam pencere olur). Birinci şahısta kendi kafan gizli olduğu için aynada
# görünmek üzere tam bir "ikiz" gövde sadece ayna kamerasına çizilir. Sadece yakındayken çalışır.
extends Node3D

const ModelScript := preload("res://scripts/model_body.gd")
const MIRROR_LAYER := 1 << 15  # ikiz gövde: sadece ayna görür
const FP_LAYER := 1 << 16  # birinci şahıs gövdesi/kolları: ayna görmez

var w: Node3D  # main.gd
var width := 0.55
var height := 0.75
var _vp: SubViewport
var _cam: Camera3D
var _glass: MeshInstance3D
var _twin: Node3D
var _twin_look := ""
var active := false


func build() -> void:
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color("#3b3f45")
	frame.metallic = 0.8
	frame.roughness = 0.35
	for s in [-1.0, 1.0]:
		w.box(Vector3(0.03, height + 0.06, 0.03), Vector3(0.0, 0, s * (width / 2 + 0.015)), frame, false, self)
		w.box(Vector3(0.03, 0.03, width + 0.06), Vector3(0.0, s * (height / 2 + 0.015), 0), frame, false, self)
	w.box(Vector3(0.01, height, width), Vector3(-0.012, 0, 0), frame, false, self)
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(width * 700), int(height * 700))
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_2X
	# 3D tamponu görüntüden 1 piksel küçük: Mobile çizici parlama (glow) kapalıyken ayna görüntüsünü doğrudan
	# hedef dokuya çizince her karede ~14 ms bekliyordu (kalite 0'da hücrede 60 fps sınırı); ara tamponla
	# ölçülen maliyet ~0,5 ms. Görüntüde fark yok (tools/fps_olc.gd sahne=ayna kalite=0).
	_vp.scaling_3d_scale = 0.997
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = 0xFFFFF & ~FP_LAYER
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_vp.add_child(_cam)
	_glass = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	_glass.mesh = q
	_glass.rotation.y = PI / 2  # cam +x yönüne (odaya) bakar
	_glass.position = Vector3(0.006, 0, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _vp.get_texture()
	m.albedo_color = Color(0.92, 0.95, 0.97)
	m.uv1_scale = Vector3(-1, 1, 1)  # ayna görüntüsü yatayda ters
	m.uv1_offset = Vector3(1, 0, 0)
	_glass.material_override = m
	add_child(_glass)


static func set_layers(n: Node, mask: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = mask
	for c in n.get_children():
		set_layers(c, mask)


func _process(_delta: float) -> void:
	var p: CharacterBody3D = w.player
	# hareket yaparken (3. şahıs) etkin kamera cam3p'dir; yansıma ona göre hesaplanır
	var pc: Camera3D = p.camera
	var c3 = p.get("cam3p")
	if c3 is Camera3D and is_instance_valid(c3) and (c3 as Camera3D).current:
		pc = c3
	var normal := global_transform.basis.x.normalized()  # odaya dönük
	var center := global_position
	var rel := pc.global_position - center
	var dist := rel.dot(normal)
	var near: bool = w.playing and dist > 0.05 and rel.length() < 5.0 and (-pc.global_transform.basis.z).dot(-normal) > 0.1
	if near != active:
		active = near
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
		if is_instance_valid(_twin):
			_twin.visible = near
	if not near:
		return
	if _cam.environment == null and w.get("env") is Environment:
		# ayna görüntüsü camda bir kez daha ana ortamın ton eşlemesinden geçer; iki kez ACES uygulanınca
		# yansıma çok koyu kalıyordu. Ayna kamerası doğrusal (ton eşlemesiz, parlamasız) çizer.
		var e2: Environment = (w.get("env") as Environment).duplicate()
		e2.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		e2.tonemap_exposure = 1.0
		e2.glow_enabled = false
		_cam.environment = e2
	_update_twin(p)
	# yansıyan kamera aynanın arkasında, odaya bakar; ayna camı tam görüş penceresi
	var refl := pc.global_position - 2.0 * dist * normal
	var up := Vector3.UP
	var fwd := normal  # kamera -z = odaya
	var right := up.cross(-fwd).normalized()
	_cam.global_transform = Transform3D(Basis(right, up, -fwd), refl)
	var off := center - refl
	_cam.set_frustum(height, Vector2(off.dot(right), off.dot(up)), dist, 40.0)


# Aynadaki sen: tam gövde (kafalı), görünüşün ve hareketin kopyası.
func _update_twin(p: CharacterBody3D) -> void:
	if not is_instance_valid(_twin):
		_twin = ModelScript.new()
		w.add_child(_twin)
		set_layers(_twin, MIRROR_LAYER)
		# birinci şahıs gövdesini ve kolları ayna görmesin; ana kamera da ikizi görmesin
		set_layers(p.body, FP_LAYER)
		p.camera.cull_mask = p.camera.cull_mask & ~MIRROR_LAYER
	var look: Dictionary = p.body.get_meta("look") if p.body.has_meta("look") else {}
	var lj := JSON.stringify(look)
	if lj != _twin_look:
		_twin_look = lj
		_twin.set_look(look)
		await get_tree().process_frame
		if is_instance_valid(_twin):
			set_layers(_twin, MIRROR_LAYER)
			set_layers(p.body, FP_LAYER)
	_twin.global_position = p.body.global_position
	_twin.rotation.y = p.rotation.y
	_twin.walk = p.body.walk
	_twin.seated = p.body.seated
	_twin.crouched = p.body.crouched
	_copy_hands(p)


# İkizin kolları da senin ellerinle aynı pozda (ahize kulakta, silah elde...).
func _copy_hands(p: CharacterBody3D) -> void:
	var src: Node = p.hand_mod()
	var sks: Array = _twin.find_children("*", "Skeleton3D", true, false)
	if not src or sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	var dst: Node = null
	for c in sk.get_children():
		if c.get_script() == src.get_script():
			dst = c
	if dst == null:
		dst = (src.get_script() as GDScript).new()
		sk.add_child(dst)
	for side in 2:
		dst.set_hand(side, src.weights[side], src.targets[side], src.forwards[side], src.ups[side], src.poles[side], src.curls[side])
