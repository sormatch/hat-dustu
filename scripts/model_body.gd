# Gerçek mahkum modeli (Mixamo iskeletli) + Mixamo animasyonları.
# Tulum/ten/saç rengi dokunun üstünde bir gölgelendirici ile değişir; ek saç modelleri,
# sakal ve gözlük kafa kemiğine takılır. body.gd ile aynı arayüzü kullanır.
extends "res://scripts/body.gd"

const MODEL := "res://assets/karakter/mahkum.fbx"
const TEXTURE := "res://assets/karakter/PowerPlantA.png"
const ANIMS := ["durma", "yurume", "kosma", "oturma", "selam", "super", "isaret", "omuz", "alkis", "off", "selamla", "dans"]
const LOOPS := ["durma", "yurume", "kosma", "oturma", "dans"]
const BASE_SKIN := Color(0.86, 0.66, 0.55)
const PROP_STYLES := ["uzun", "atkuyrugu", "mohawk", "kivircik", "bere"]  # modelin kendi saçının üstüne

const SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 outfit : source_color = vec3(0.7, 0.31, 0.1);
uniform int pattern = 0;
uniform vec3 skin_tint = vec3(1.0);
uniform vec3 hair : source_color = vec3(0.1);
uniform int beard = 0;
varying vec3 lpos;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

void vertex() { lpos = VERTEX; }

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
	bool hair_px = head_zone && h.z < 0.32;
	if (suit) {
		float l = clamp(h.z / 0.78, 0.0, 1.3);
		vec3 base = outfit;
		if (pattern == 1) {
			base = mix(vec3(0.08), vec3(0.88, 0.86, 0.82), step(0.5, fract(lpos.y * 9.0)));
		} else if (pattern == 2) {
			float n = sin(lpos.x * 23.0 + sin(lpos.y * 17.0) * 2.0) + sin(lpos.y * 19.0 + lpos.z * 21.0);
			base = n > 0.6 ? vec3(0.18, 0.21, 0.14) : (n < -0.5 ? vec3(0.42, 0.36, 0.24) : vec3(0.31, 0.35, 0.23));
		} else if (pattern == 3) {
			rough = 0.3;
			metal = 0.85;
		}
		o = base * l;
	} else if (hair_px) {
		o = hair * (0.45 + h.z * 1.8);
	} else if (skin_zone) {
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
		o = mix(o, hair * 0.55 * grain, m * 0.88);
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
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_current = ""
	_play("durma")
	_attach_head_props.call_deferred()


func _apply_colors() -> void:
	var id: String = look.kiyafet
	_mat_model.set_shader_parameter("outfit", Color(Catalog.OUTFIT_COLORS.get(id, "#B4501A")))
	_mat_model.set_shader_parameter("pattern", {"cizgili": 1, "kamuflaj": 2, "altin": 3}.get(id, 0))
	var sk := Color(Catalog.SKIN[look.ten])
	_mat_model.set_shader_parameter("skin_tint", Vector3(sk.r / BASE_SKIN.r, sk.g / BASE_SKIN.g, sk.b / BASE_SKIN.b))
	_mat_model.set_shader_parameter("hair", Color(Catalog.HAIR_COLORS[look.sac_renk]))
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
	if look.sac in PROP_STYLES:
		_build_hair(hair, _mat(Color(Catalog.SKIN[look.ten]), 0.7))
	_build_extras(hair)
	if look.aksesuar == "zincir":
		var chain := TorusMesh.new()
		chain.inner_radius = 0.095
		chain.outer_radius = 0.108
		_mesh(_head, chain, Vector3(0, -0.2, 0.0), _mat(Color("#d4af37"), 0.25, 0.9), Vector3(deg_to_rad(-15), 0, 0))
	_head.visible = not hide_head


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
