# Gerçek mahkum modeli (Mixamo iskeletli) + Mixamo animasyonları.
# Tulum/ten/saç rengi dokunun üstünde bir gölgelendirici ile değişir; ek saç modelleri,
# sakal ve gözlük kafa kemiğine takılır. body.gd ile aynı arayüzü kullanır.
extends "res://scripts/body.gd"

const MODEL := "res://assets/karakter/mahkum.fbx"
const TEXTURE := "res://assets/karakter/PowerPlantA.png"
const ANIMS := ["durma", "yurume", "kosma", "oturma", "selam", "super", "isaret", "omuz", "alkis", "off", "selamla", "dans"]
const LOOPS := ["durma", "yurume", "kosma", "oturma"]
const BASE_SKIN := Color(0.86, 0.66, 0.55)
const Hair := preload("res://scripts/hair.gd")
const CARD_STYLES := ["kisa", "uzun", "atkuyrugu", "mohawk", "kivircik"]  # tel tel saç kartlarıyla
const Hats := preload("res://scripts/hats.gd")
# Dövme yeri ve boyu (metre): yuz = göz altı, kafa = kafanın yanı (şakak/kulak üstü), el = sağ elin üstü
const TATTOO_PLACE := {
	"gozyasi": ["yuz", 0.026], "kalp": ["el", 0.07], "kafatasi": ["el", 0.07], "gul": ["kafa", 0.075],
	"orumcek": ["kafa", 0.08], "kartal": ["kafa", 0.095], "ejderha": ["kafa", 0.095], "kaplan": ["kafa", 0.09],
}
const TATTOO_FILE := {"orumcek": "orumcek_agi"}
const DECAL_LAYER := 1 << 10  # dövme sadece vücut modeline yapışsın (saç/şapka değil)
static var _ink := {}

const SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D regions : filter_nearest;  // R gövde, G kol (omuzdan uzaklık), B bacak
uniform vec3 outfit : source_color = vec3(0.7, 0.31, 0.1);
uniform vec3 legs : source_color = vec3(0.7, 0.31, 0.1);
uniform int pattern = 0;
uniform int leg_pattern = 0;
uniform int arms = 0;  // 0 kollu, 1 çıplak kol, 2 kısa kol
uniform vec3 skin_tint = vec3(1.0);
uniform vec3 hair : source_color = vec3(0.1);
uniform int beard = 0;
uniform bool bald = false;
varying vec3 lpos;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

void vertex() { lpos = VERTEX; }

// Kumaş deseni: 0 düz, 1 çizgili, 2 kamuflaj, 3 altın (metal), 4 kot (çapraz örgü)
vec3 cloth(int p, vec3 base, float l, inout float rough, inout float metal) {
	vec3 b = base;
	if (p == 1) {
		b = mix(vec3(0.08), vec3(0.88, 0.86, 0.82), step(0.5, fract(lpos.y * 9.0)));
	} else if (p == 2) {
		float n = sin(lpos.x * 23.0 + sin(lpos.y * 17.0) * 2.0) + sin(lpos.y * 19.0 + lpos.z * 21.0);
		b = n > 0.6 ? vec3(0.18, 0.21, 0.14) : (n < -0.5 ? vec3(0.42, 0.36, 0.24) : vec3(0.31, 0.35, 0.23));
	} else if (p == 3) {
		rough = 0.3;
		metal = 0.85;
	} else if (p == 4) {
		float tw = 0.88 + 0.12 * sin((lpos.x + lpos.y + lpos.z) * 420.0);
		b = base * tw;
	}
	return b * l;
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 h = rgb2hsv(c);
	vec3 o = c;
	float rough = 0.85;
	float metal = 0.0;
	// dokudaki bölgeler: sol üst yüz/saç, sağında kulak, alt ortada eller
	bool head_zone = UV.x < 0.62 && UV.y < 0.42;
	bool skin_zone = head_zone || (UV.x > 0.62 && UV.x < 0.72 && UV.y > 0.2 && UV.y < 0.4) || (UV.x > 0.44 && UV.x < 0.72 && UV.y > 0.7);
	bool suit = !skin_zone && h.y > 0.42 && (h.x < 0.12 || h.x > 0.94) && h.z > 0.1;
	bool face_core = UV.x > 0.2 && UV.x < 0.56 && UV.y > 0.12;
	bool hair_px = head_zone && !face_core && h.z < 0.32;
	if (suit) {
		float l = clamp(h.z / 0.78, 0.0, 1.3);
		vec3 reg = texture(regions, UV).rgb;
		bool arm = reg.g > 0.004;
		bool leg = reg.b > 0.5;
		if (arm && (arms == 1 || (arms == 2 && reg.g > 0.38))) {
			// çıplak kol: ten rengi, kumaşın gölgesiyle
			o = vec3(0.86, 0.66, 0.55) * skin_tint * (0.55 + l * 0.5);
		} else if (leg) {
			o = cloth(leg_pattern, legs, l, rough, metal);
		} else {
			o = cloth(pattern, outfit, l, rough, metal);
		}
	} else if (hair_px && bald) {
		o = vec3(0.86, 0.66, 0.55) * skin_tint * (0.75 + h.z * 0.6);
	} else if (hair_px) {
		o = hair * (0.45 + h.z * 1.8);
	} else if (skin_zone && h.x < 0.13 && h.y > 0.1 && h.y < 0.72 && h.z > 0.18) {
		o = c * skin_tint;
	}
	// yüze boyanan sakal: dokuda ağız ve çene çevresi (yüz ön tarafta, ortası x≈0.38)
	if (beard > 0) {
		vec2 f = vec2((UV.x - 0.38) / 0.2, (UV.y - 0.36) / 0.09);
		float grain = 0.75 + 0.25 * fract(sin(dot(UV * 512.0, vec2(12.9898, 78.233))) * 43758.5453);
		float m = 0.0;
		float moust = step(abs(f.x), 0.55) * step(abs(f.y + 0.25), 0.22);
		if (beard == 1) m = moust;
		if (beard == 2) m = max(moust, step(length(vec2(f.x / 0.35, (f.y - 0.55) / 0.5)), 1.0));
		if (beard == 3) m = step(length(vec2(f.x, max(f.y, 0.0) * 0.6)), 1.0) * step(-0.4, f.y);
		o = mix(o, hair * 0.6 * grain, m * 0.3);
	}
	ALBEDO = o;
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""

static var _library: AnimationLibrary
static var _shader: Shader

var hide_head := false
var crouched := false  # çömelme: oturma pozuyla gösterilir  # birinci şahıs: kafa küçültülür, kamera içinden görünmez
var _head_bone := -1
var _player: AnimationPlayer
var _skel: Skeleton3D
var _mat_model: ShaderMaterial
var _current := ""


static func _get_library() -> AnimationLibrary:
	if _library:
		return _library
	_library = AnimationLibrary.new()
	for n in ANIMS:
		var path := "res://assets/karakter/anim/%s.fbx" % n
		if not ResourceLoader.exists(path):
			continue
		var inst: Node = load(path).instantiate()
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR if n in LOOPS else Animation.LOOP_NONE
		_library.add_animation(n, anim)
		inst.free()
	return _library


func _build() -> void:
	if _rig:
		_rig.queue_free()
	_rig = Node3D.new()
	add_child(_rig)
	var model: Node3D = load(MODEL).instantiate()
	model.rotation.y = PI  # model +z'ye bakıyor, oyunda karakterler -z'ye bakar
	_rig.add_child(model)
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	if not _player.has_animation_library("hd"):
		_player.add_animation_library("hd", _get_library())
	if not _shader:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat_model = ShaderMaterial.new()
	_mat_model.shader = _shader
	_mat_model.set_shader_parameter("tex", load(TEXTURE))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _mat_model
	_apply_colors()
	_head_bone = _skel.find_bone("mixamorig_Head")
	if hide_head:
		_player.mixer_applied.connect(func() -> void:
			_skel.set_bone_pose_scale(_head_bone, Vector3.ONE * 0.001))
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_current = ""
	_play("durma")
	_attach_head_props.call_deferred()


func _apply_colors() -> void:
	var o: Dictionary = Catalog.OUTFITS.get(look.kiyafet, Catalog.OUTFITS.turuncu)
	_mat_model.set_shader_parameter("regions", load("res://assets/karakter/bolgeler.png"))
	_mat_model.set_shader_parameter("outfit", Color(o.ust))
	_mat_model.set_shader_parameter("legs", Color(o.alt))
	_mat_model.set_shader_parameter("pattern", int(o.get("ud", 0)))
	_mat_model.set_shader_parameter("leg_pattern", int(o.get("ad", 0)))
	_mat_model.set_shader_parameter("arms", int(o.get("kol", 0)))
	var sk := Color(Catalog.SKIN[look.ten])
	_mat_model.set_shader_parameter("skin_tint", Vector3(sk.r / BASE_SKIN.r, sk.g / BASE_SKIN.g, sk.b / BASE_SKIN.b))
	_mat_model.set_shader_parameter("hair", Color(Catalog.HAIR_COLORS[look.sac_renk]))
	_mat_model.set_shader_parameter("bald", look.sac == "kel")
	_mat_model.set_shader_parameter("beard", {"biyik": 1, "keci": 2, "sakal": 3}.get(look.sakal, 0))


# Kafa kemiğine bir düğüm takar; saç/sakal/gözlük body.gd'deki kafa ölçüsüne göre kurulur, modele göre ölçeklenir.
func _attach_head_props() -> void:
	if not is_instance_valid(_skel):
		return
	var head_i := _skel.find_bone("mixamorig_Head")
	var top_i := _skel.find_bone("mixamorig_HeadTop_End")
	if head_i < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_idx = head_i
	_skel.add_child(ba)
	var head_pos := _skel.global_transform * _skel.get_bone_global_rest(head_i).origin
	var top_pos := _skel.global_transform * _skel.get_bone_global_rest(top_i).origin if top_i >= 0 else head_pos + Vector3.UP * 0.2
	var r := head_pos.distance_to(top_pos) * 0.5
	_head = Node3D.new()
	ba.add_child(_head)
	# kafa düğümünü dik ve -z'ye bakan çerçeveye oturt (dinlenme pozuna göre)
	var rest_global := _skel.global_transform * _skel.get_bone_global_rest(head_i)
	var want := Transform3D(global_transform.basis.scaled(Vector3.ONE * (r / 0.115)), head_pos.lerp(top_pos, 0.45))
	_head.transform = rest_global.affine_inverse() * want
	var hair := _mat(Color(Catalog.HAIR_COLORS[look.sac_renk]), 0.8)
	var hair_col := Color(Catalog.HAIR_COLORS[look.sac_renk])
	# saç/sakal kökleri gerçek kafa yüzeyine otursun diye kafa şeklini ölç (dinlenme pozunda)
	Hair.fit_head(_rig.find_children("*", "MeshInstance3D", true, false), want)
	var hat := str(look.get("sapka", "yok"))
	var hair_box := AABB()
	if hat != "yok" and look.sac in Hats.HIDDEN_HAIR:
		pass  # kısa saç şapkanın altında kalır
	else:
		var before := _head.get_child_count()
		if Hair.build_real(_head, look.sac, hair_col):
			pass  # gerçek saç modeli
		elif look.sac in CARD_STYLES:
			Hair.build_hair(_head, look.sac, hair_col)
		for i in range(before, _head.get_child_count()):
			var mi := _head.get_child(i) as MeshInstance3D
			if mi:
				var b := mi.transform * mi.get_aabb()
				hair_box = b if hair_box.size == Vector3.ZERO else hair_box.merge(b)
	Hats.build(_head, hat, hair_box)
	_apply_tattoo()
	if look.sakal != "yok":
		Hair.build_beard_shells(_head, look.sakal, hair_col)
	_build_extras(hair)
	if look.aksesuar == "zincir":
		var chain := TorusMesh.new()
		chain.inner_radius = 0.095
		chain.outer_radius = 0.108
		_mesh(_head, chain, Vector3(0, -0.2, 0.0), _mat(Color("#d4af37"), 0.25, 0.9), Vector3(deg_to_rad(-15), 0, 0))
	_head.visible = not hide_head


# Dövme resmini mürekkebe çevirir: beyaz/açık kısımlar şeffaf, koyu çizgiler lacivert-siyah mürekkep.
static func ink_texture(id: String) -> Texture2D:
	if _ink.has(id):
		return _ink[id]
	var path := "res://assets/dovme/dovme_%s.png" % TATTOO_FILE.get(id, id)
	var src: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if src == null:
		return null
	var img := src.get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			var a := c.a * clampf((0.82 - lum) / 0.62, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.07, 0.09, 0.13, a * 0.92))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_ink[id] = t
	return t


# Dövmeyi gerçek dövme gibi vücut yüzeyine yansıtır (Decal); kafa ya da el kemiğiyle birlikte hareket eder.
func _apply_tattoo() -> void:
	var id := str(look.get("dovme", "yok"))
	if id == "yok" or not TATTOO_PLACE.has(id):
		return
	var tex := ink_texture(id)
	if tex == null:
		return
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).get_parent() is BoneAttachment3D and _head and not _head.is_ancestor_of(mi):
			(mi as MeshInstance3D).layers |= DECAL_LAYER
	var place: String = TATTOO_PLACE[id][0]
	var size: float = TATTOO_PLACE[id][1]
	var d := Decal.new()
	d.texture_albedo = tex
	d.cull_mask = DECAL_LAYER
	d.normal_fade = 0.35
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	var aspect := float(tex.get_height()) / tex.get_width()
	# kafa çerçevesi metre değil: ölçülen kafa genişliğine (gerçekte ~15,5 cm) göre ölçekle
	var k := (Hair._head_max.x - Hair._head_min.x) / 0.155
	match place:
		"yuz":
			var dir := Vector3(0.3, 0.1, -1.0).normalized()
			var p := dir * Hair.radius_at(dir)
			size *= k
			d.size = Vector3(size / aspect, 0.05 * k, size)
			d.transform = Transform3D(_decal_basis(dir, Vector3.UP), p)
			_head.add_child(d)
		"kafa":
			var dir := Vector3(1.0, 0.12, 0.15).normalized()
			size *= k
			d.size = Vector3(size / aspect, 0.06 * k, size)
			d.transform = Transform3D(_decal_basis(dir, Vector3.UP), dir * Hair.radius_at(dir))
			_head.add_child(d)
		"el":
			var hand := _skel.find_bone("mixamorig_RightHand")
			var finger := _skel.find_bone("mixamorig_RightHandMiddle1")
			if hand < 0 or finger < 0:
				return
			var hr := _skel.global_transform * _skel.get_bone_global_rest(hand)
			var fr := _skel.global_transform * _skel.get_bone_global_rest(finger)
			var along := (fr.origin - hr.origin).normalized()
			var ba := BoneAttachment3D.new()
			ba.bone_idx = hand
			_skel.add_child(ba)
			d.size = Vector3(size, 0.08, size * aspect)
			var want := Transform3D(_decal_basis(Vector3.UP, along), hr.origin.lerp(fr.origin, 0.55))
			d.transform = hr.affine_inverse() * want
			ba.add_child(d)


# Decal tabanı: Y ekseni yüzeyden dışarı (yansıtma yönünün tersi), resmin üstü "up" yönünde.
static func _decal_basis(normal: Vector3, up: Vector3) -> Basis:
	var y := normal.normalized()
	var z := -(up - y * up.dot(y)).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


# Sakal/bıyık blok olarak değil, yüz dokusuna boyanır (gölgelendiricide); burada sadece gözlük ve bant.
func _build_extras(hair: StandardMaterial3D) -> void:
	var s: String = look.sakal
	look.sakal = "yok"
	super(hair)
	look.sakal = s


func set_first_person(on: bool) -> void:
	show_head = not on
	_rig.visible = not on


func _apply_visibility() -> void:
	pass


func play_emote(id: String) -> void:
	if _player and _player.has_animation("hd/" + id):
		emote = id
		emote_t = 0.0
		_play(id, 0.2)


func stop_emote() -> void:
	emote = ""
	_current = ""


func _play(n: String, blend := 0.25) -> void:
	var full := "hd/" + n
	if _current == n or not _player.has_animation(full):
		return
	_current = n
	_player.play(full, blend)


func _process(delta: float) -> void:
	if not _player:
		return
	if emote != "":
		emote_t += delta
		if not _player.is_playing() or _player.current_animation != "hd/" + emote:
			emote = ""
		else:
			return
	if seated or crouched:
		_play("oturma", 0.4)
		_player.speed_scale = 1.0
	elif walk > 1.15:
		_play("kosma")
		_player.speed_scale = clampf(walk / 1.5, 0.7, 1.3)
	elif walk > 0.08:
		_play("yurume")
		_player.speed_scale = clampf(walk * 1.1, 0.6, 1.4)
	else:
		_play("durma")
		_player.speed_scale = 1.0
