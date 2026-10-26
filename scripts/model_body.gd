# Oyuncu karakteri: gerçek iskeletli insan modelleri + animasyonlar. body.gd ile aynı arayüzü kullanır.
# Gövdeler (look.govde):
#   "erkek" / "kadin": Quaternius Universal Base Characters (CC0) kafası + Modular Character Outfits (CC0)
#                      kıyafeti (gömlek, pantolon, çizme); kıyafet rengi/deseni gölgelendiriciyle boyanır.
#   Bilinmeyen/eski değerler (ör. eski "mahkum" modeli kaldırıldı) erkek gövdesine düşer.
# Bütün modeller ve animasyonlar içe aktarılırken aynı insansı profile (assets/karakter/mixamo_profil.tres)
# yeniden hedeflenir: kemik adları her gövdede "mixamorig_*" olur, animasyonlar (Mixamo + Quaternius UAL +
# koddan üretilenler) her gövdede oynar. Saç, sakal, şapka, aksesuar ve dövme kafa/el kemiklerine takılır.
extends "res://scripts/body.gd"

const ANIMS := ["durma", "yurume", "kosma", "oturma", "selam", "super", "isaret", "omuz", "alkis", "off", "selamla", "dans"]
const LOOPS := ["durma", "yurume", "kosma", "oturma"]
# Quaternius Universal Animation Library (CC0) animasyonları: oyundaki ad -> dosya (assets/karakter/anim_ual)
const UAL := {
	"dans2": "Dance", "konus": "Idle_Talking", "comel": "Crouch_Idle", "comel_yuru": "Crouch_Fwd",
	"bayil": "Death01", "yumruk": "Punch_Cross", "buyu": "Spell_Simple_Shoot", "takla": "Roll",
	"evet": "Yes", "hayir": "Idle_No", "kollar": "Idle_FoldArms", "telefon": "Idle_TalkingPhone",
	"ic": "Consume", "zombi": "Zombie_Idle", "gozcu": "Idle_Rail_Call", "firlat": "OverhandThrow",
}
# Döngülü hareketler bu kadar saniye sürer (döngüsüzler animasyon bitince biter)
const EMOTE_LEN := {"dans2": 5.0, "konus": 4.0, "hayir": 2.5, "kollar": 4.0, "telefon": 4.5, "zombi": 4.0, "comel": 4.0}
const Hair := preload("res://scripts/hair.gd")
const CARD_STYLES := ["kisa", "uzun", "atkuyrugu", "mohawk", "kivircik"]  # tel tel saç kartlarıyla
const Hats := preload("res://scripts/hats.gd")
const Acc := preload("res://scripts/aksesuar.gd")
const Emotes := preload("res://scripts/hareketler.gd")
# Dövme yeri ve boyu (metre): yuz = göz altı, kafa = kafanın yanı (şakak/kulak üstü), el = sağ elin üstü
const TATTOO_PLACE := {
	"gozyasi": ["yuz", 0.026], "kalp": ["el", 0.07], "kafatasi": ["el", 0.07], "gul": ["kafa", 0.075],
	"orumcek": ["kafa", 0.08], "kartal": ["kafa", 0.095], "ejderha": ["kafa", 0.095], "kaplan": ["kafa", 0.09],
}
const TATTOO_FILE := {"orumcek": "orumcek_agi"}
const DECAL_LAYER := 1 << 10  # dövme sadece vücut modeline yapışsın (saç/şapka değil)
# Karakterler dünya katmanında (1) değil kendi katmanlarında çizilir: duvar lekeleri (Decal, cull_mask = 1)
# ve sadece dünyayı aydınlatması gereken ışıklar (light_cull_mask = 1, ör. bilgisayar ekranının yeşil ışığı)
# karaktere vurmasın. Kameralar ve diğer ışıklar bütün katmanları gördüğü için başka bir şey değişmez.
const CHAR_LAYER := 1 << 11
static var _ink := {}

const G := "res://assets/govde/"
# CC0 gövdeler: giysi = iskelet + kıyafet parçaları (kafa yok), bas = kafası alınan tam gövde modeli.
const BODIES := {
	"erkek": {
		"giysi": G + "kiyafet/Male_Peasant.gltf", "bas": G + "Superhero_Male_FullBody.gltf",
		"ten": [G + "T_Superhero_Male_Ligh.png", G + "T_Superhero_Male_Dark.png"],
		"ten_n": G + "T_Superhero_Male_Normal.png", "ten_r": G + "T_Superhero_Male_Roughness.png",
		"el": G + "kiyafet/T_Regular_Male_Dark_BaseColor.png", "el_n": G + "kiyafet/T_Regular_Male_Normal.png",
		"kas": G + "T_Hair_1_BaseColor.png", "olcek": 0.955,
	},
	"kadin": {
		"giysi": G + "kiyafet/Female_Peasant.gltf", "bas": G + "Superhero_Female_FullBody.gltf",
		"ten": [G + "T_Superhero_Female_Light_BaseColor.png", G + "T_Superhero_Female_Dark_BaseColor.png"],
		"ten_n": G + "T_Superhero_Female_Normal.png", "ten_r": G + "T_Superhero_Female_Roughness.png",
		"el": G + "kiyafet/T_Regular_Female_Dark_BaseColor.png", "el_n": G + "kiyafet/T_Regular_Female_Normal.png",
		"kas": G + "T_Hair_2_BaseColor.png", "olcek": 0.97,
	},
}
const CLOTH_TEX := G + "kiyafet/T_Peasant_BaseColor.png"
const CLOTH_N := G + "kiyafet/T_Peasant_Normal.png"
const CLOTH_ORM := G + "kiyafet/T_Peasant_ORM.png"
const EYE_TEX := G + "T_Eye_Brown.png"

# CC0 gövdelerin teni: doku, seçilen ten rengine göre boyanır (dokunun ortalama ten rengine oranla).
# Yüz dokusundaki boyalı saç gölgesi ve kirli sakal seçime göre tene karışır.
const SKIN_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
uniform sampler2D rgh : hint_default_white, filter_linear_mipmap;
uniform vec3 tint = vec3(1.0);
uniform vec3 base_avg = vec3(0.7, 0.5, 0.4);
uniform float stubble = 1.0;  // yüzdeki boyalı kirli sakal (0 = temiz yüz)
uniform float scalp = 1.0;  // kafa derisindeki boyalı saç gölgesi (0 = ten)
uniform vec4 face_box = vec4(0.0, 0.0, 0.36, 0.38);  // dokuda yüz bölgesi (x0, y0, x1, y1)
uniform vec3 hair_col = vec3(0.1);

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 o = c * tint;
	if (UV.x > face_box.x && UV.x < face_box.z && UV.y > face_box.y && UV.y < face_box.w) {
		// dokuya boyanmış saç gölgesi ve kirli sakal gri/düşük doygunluktadır: önce tene çevrilir,
		// sonra seçime göre saç renginde yeniden boyanır
		float lum = dot(c, vec3(0.3, 0.59, 0.11));
		float blum = dot(base_avg, vec3(0.3, 0.59, 0.11));
		float mx = max(c.r, max(c.g, c.b));
		float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.001);
		float bmx = max(base_avg.r, max(base_avg.g, base_avg.b));
		float bsat = (bmx - min(base_avg.r, min(base_avg.g, base_avg.b))) / max(bmx, 0.001);
		float gray = clamp((bsat - sat) / (bsat * 0.55), 0.0, 1.0);
		float fy = (UV.y - face_box.y) / (face_box.w - face_box.y);
		float is_scalp = smoothstep(0.34, 0.2, fy);
		float is_jaw = smoothstep(0.56, 0.72, fy);
		vec3 clean = base_avg * tint * clamp(lum / blum, 0.6, 1.15);
		vec3 painted = mix(clean, hair_col * (0.35 + lum * 0.8), 0.7);
		float a_s = is_scalp * gray;
		float a_j = is_jaw * gray;
		o = mix(o, clean, clamp(a_s + a_j, 0.0, 1.0));
		o = mix(o, painted, clamp(a_s * scalp + a_j * stubble, 0.0, 1.0));
	}
	ALBEDO = o;
	NORMAL_MAP = texture(nrm, UV).rgb;
	ROUGHNESS = texture(rgh, UV).r * 0.9 + 0.08;
	SPECULAR = 0.35;
}
"""

# Kıyafet: kumaş dokusu gri tonlara çevrilip seçilen renge boyanır; deri (kemer, çizme) kahverengi kalır.
# pattern: 0 düz, 1 çizgili, 2 kamuflaj, 3 altın, 4 kot, 5 ekose, 6 leopar, 7 puantiye
const CLOTH_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
uniform sampler2D orm : hint_default_white, filter_linear_mipmap;
uniform vec3 color : source_color = vec3(0.7, 0.31, 0.1);
uniform int pattern = 0;
uniform int part = 0;  // 0 üst (gömlek, kollar), 1 pantolon, 2 ayakkabı
varying vec3 lpos;
varying float glove;  // eldiven (köşe rengi siyah işaretli)

void vertex() {
	lpos = VERTEX;
	glove = 1.0 - COLOR.r;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	vec3 m = texture(orm, UV).rgb;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	// kumaş kıvrımları korunsun diye parlaklık, dokunun bulanık (yakın çevre ortalaması) haline oranlanır
	vec3 cb = textureLod(tex, UV, 5.0).rgb;
	float lb = max(dot(cb, vec3(0.3, 0.59, 0.11)), 0.015);
	float shade = clamp(lum / lb, 0.45, 1.6);
	float mx = max(cb.r, max(cb.g, cb.b));
	float sat = (mx - min(cb.r, min(cb.g, cb.b))) / max(mx, 0.001);
	// boyanacak kısım: üstte açık renkli gömlek kumaşı, altta pantolon; deri (kemer, yelek, bilek, çizme) kalır
	float k = 1.0;
	if (part == 0) {
		k = smoothstep(0.07, 0.13, lb) * (1.0 - smoothstep(0.65, 0.85, sat));
	} else if (part == 2) {
		k = 0.0;
	}
	vec3 base = color;
	float rough = 0.88;
	float metal = 0.0;
	if (pattern == 1) {
		base = mix(vec3(0.07), color, step(0.5, fract(lpos.y * 9.0)));
	} else if (pattern == 2) {
		float n = noise(lpos.xy * 9.0 + lpos.z * 3.0) + 0.5 * noise(lpos.zy * 17.0);
		base = n > 0.95 ? vec3(0.17, 0.2, 0.13) : (n < 0.55 ? vec3(0.42, 0.36, 0.24) : vec3(0.31, 0.35, 0.23));
	} else if (pattern == 3) {
		rough = 0.28;
		metal = 0.9;
	} else if (pattern == 4) {
		base = color * (0.86 + 0.14 * sin((lpos.x + lpos.y + lpos.z) * 420.0));
	} else if (pattern == 5) {
		vec2 g = fract(vec2(lpos.x + lpos.z, lpos.y) * 7.0);
		float a = step(0.7, g.x) * 0.5 + step(0.7, g.y) * 0.5;
		base = mix(color, color * 0.35, a) + vec3(0.06) * step(0.93, max(g.x, g.y));
	} else if (pattern == 6) {
		vec2 q = vec2(lpos.x + lpos.z * 0.7, lpos.y) * 22.0;
		float n = noise(q);
		float spot = smoothstep(0.62, 0.66, n);
		float core = smoothstep(0.7, 0.74, n);
		base = mix(color, vec3(0.08, 0.06, 0.04), spot - core * 0.8);
	} else if (pattern == 7) {
		vec2 g = fract(vec2(lpos.x + lpos.z, lpos.y) * 16.0) - 0.5;
		base = mix(color, vec3(0.95, 0.93, 0.88), step(length(g), 0.18));
	}
	// deri kısımlar (kemer, yelek/korse, kol bantları) kıyafetin koyu tonuna, eldiven ve ayakkabılar siyah iş
	// botu tonuna boyanır: herkes tek parça mahkum kıyafetli görünsün
	vec3 dark = base * 0.68;  // desen de devam etsin: korse/yelek kıyafetin bir parçası gibi
	if (glove > 0.5 || part == 2) {
		dark = vec3(0.02, 0.02, 0.023);
	}
	vec3 o = mix(dark * clamp(lum / lb, 0.55, 1.5), base * shade, k);
	rough = mix(0.55, rough, k);
	metal *= k;
	if (pattern == 99) { o = c; }
	ALBEDO = o;
	NORMAL_MAP = texture(nrm, UV).rgb;
	ROUGHNESS = rough * m.g + 0.05;
	METALLIC = metal;
	AO = m.r;
}
"""

# Göz: dokudaki kahverengi iris seçilen göz rengine boyanır.
const EYE_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 iris : source_color = vec3(0.3, 0.2, 0.1);
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float d = length(UV - vec2(0.5, 0.5));
	float k = smoothstep(0.17, 0.13, d) * step(0.18, sat) * step(lum, 0.5);
	ALBEDO = mix(c, iris * (0.35 + lum * 1.6), k);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
}
"""

static var _library: AnimationLibrary
static var _skin_shader: Shader
static var _cloth_shader: Shader
static var _eye_shader: Shader
static var _parts := {}  # govde -> kafa/göz/kaş parçaları (bir kez çıkarılır)
static var _avg := {}  # doku yolu -> ortalama ten rengi

var hide_head := false
var crouched := false  # çömelme
var _head_bone := -1
var _player: AnimationPlayer
var _skel: Skeleton3D
var _current := ""
var _govde := "erkek"
var _cloth_mats: Array = []  # [malzeme, bacak mı]


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
		_add_pinky(anim)
		_library.add_animation(n, anim)
		inst.free()
	for id in UAL:
		var path := "res://assets/karakter/anim_ual/%s.res" % UAL[id]
		if ResourceLoader.exists(path):
			var anim: Animation = (load(path) as Animation).duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR if EMOTE_LEN.has(id) or id == "comel_yuru" else Animation.LOOP_NONE
			_library.add_animation(id, anim)
	# koddan üretilen hareketler (gülme, ağlama, kızma...) duruş animasyonunun üstüne kurulur
	if _library.has_animation("durma"):
		for id in Emotes.IDS:
			_library.add_animation(id, Emotes.make(id, _library.get_animation("durma")))
	return _library


# Mixamo animasyonlarında serçe parmak yok (4 parmaklı iskeletle indirildi): yüzük parmağının hareketi kopyalanır.
static func _add_pinky(anim: Animation) -> void:
	for side in ["Left", "Right"]:
		for j in [1, 2, 3]:
			var ring := NodePath("%%GeneralSkeleton:mixamorig_%sHandRing%d" % [side, j])
			var pinky := NodePath("%%GeneralSkeleton:mixamorig_%sHandPinky%d" % [side, j])
			var t := anim.find_track(ring, Animation.TYPE_ROTATION_3D)
			if t < 0 or anim.find_track(pinky, Animation.TYPE_ROTATION_3D) >= 0:
				continue
			var nt := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(nt, pinky)
			for k in anim.track_get_key_count(t):
				anim.rotation_track_insert_key(nt, anim.track_get_key_time(t, k), anim.track_get_key_value(t, k))


func _build() -> void:
	if _rig:
		_rig.queue_free()
	_rig = Node3D.new()
	add_child(_rig)
	_cloth_mats.clear()
	_govde = str(look.get("govde", "erkek"))
	if not BODIES.has(_govde):
		_govde = "erkek"
	var model := _build_cc0(_govde)
	model.rotation.y = PI  # modeller +z'ye bakıyor, oyunda karakterler -z'ye bakar
	# boy ~1,75 m kalsın: kamera, oturma ve kol hizaları buna göre ayarlı
	model.scale = Vector3.ONE * float(BODIES[_govde].olcek)
	_rig.add_child(model)
	if not _player.has_animation_library("hd"):
		_player.add_animation_library("hd", _get_library())
	_apply_colors()
	_head_bone = _skel.find_bone("mixamorig_Head")
	if hide_head:
		_player.mixer_applied.connect(func() -> void:
			_skel.set_bone_pose_scale(_head_bone, Vector3.ONE * 0.001))
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_current = ""
	_play("durma")
	_char_layers(_rig)
	_attach_head_props.call_deferred()


# CC0 gövde: kıyafet modelinin iskeletine (gövde ölçüleri) aynı setin kafası, gözleri ve kaşları takılır.
func _build_cc0(id: String) -> Node3D:
	var def: Dictionary = BODIES[id]
	var model: Node3D = load(def.giysi).instantiate()
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	var parts := _head_info(id)
	# kafa tepesi kemiği (Mixamo iskeletlerindeki gibi): taç ve maç sonu ekranı bunu kullanır
	if _skel.find_bone("mixamorig_HeadTop_End") < 0:
		var head := _skel.find_bone("mixamorig_Head")
		_skel.add_bone("mixamorig_HeadTop_End")
		var top := _skel.get_bone_count() - 1
		_skel.set_bone_parent(top, head)
		var tp: Vector3 = parts.head
		_skel.set_bone_rest(top, Transform3D(Basis(), (parts.bind as Transform3D) * Vector3(tp.x, float(parts.top), tp.z)))
		_skel.reset_bone_pose(top)
	# kıyafet meshlerine eldiven işareti (köşe rengi) eklenmiş kopyaları takılır
	for mi in _skel.get_children():
		if mi is MeshInstance3D:
			(mi as MeshInstance3D).mesh = _masked((mi as MeshInstance3D).mesh)
	for key in ["bas", "goz", "kas"]:
		if not parts.has(key):
			continue
		var p: Array = parts[key]
		var mi := MeshInstance3D.new()
		mi.name = {"bas": "Bas", "goz": "Goz", "kas": "Kas"}[key]
		mi.mesh = p[0]
		mi.skin = p[1]
		_skel.add_child(mi)
		mi.skeleton = NodePath("..")
	_player = AnimationPlayer.new()
	model.add_child(_player)
	return model


static var _mask_cache := {}

# Kıyafet meshinin köşe rengine işaret: beyaz = kumaş/deri, siyah = eldiven (bilekten sonrası, |x| > 0,56 m;
# modeller T duruşunda çizilmiş). Gölgelendirici eldivenleri siyaha boyar. Mesh başına bir kez yapılır.
static func _masked(mesh: Mesh) -> Mesh:
	if _mask_cache.has(mesh):
		return _mask_cache[mesh]
	var am := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		for i in verts.size():
			cols[i] = Color.BLACK if absf(verts[i].x) > 0.56 else Color.WHITE
		arr[Mesh.ARRAY_COLOR] = cols
		for ci in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arr[ci] = null
		var flags: int = mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		am.surface_set_material(si, mesh.surface_get_material(si))
	am.resource_name = mesh.resource_name
	_mask_cache[mesh] = am
	return am


# Görünen parçaları dünya katmanından karakter katmanına taşır (başka katman bitleri korunur).
static func _char_layers(n: Node) -> void:
	if n is VisualInstance3D and not n is Decal:
		var v := n as VisualInstance3D
		if v.layers & 1:
			v.layers = (v.layers & ~1) | CHAR_LAYER
	for c in n.get_children():
		_char_layers(c)


static func _bind_of(skin: Skin, bone: String) -> Variant:
	for i in skin.get_bind_count():
		if String(skin.get_bind_name(i)) == bone:
			return skin.get_bind_pose(i)
	return null


# Gövdenin kafa bilgisi (modelin kendi çizildiği uzayda = bağlama/bind uzayı, yüz +z):
#   bind: model uzayından kafa kemiği uzayına dönüşüm (kafaya takılan her şey bununla kemiğe bağlanır),
#   head: kafa kemiğinin yeri, top: kafa tepesinin yüksekliği, mesh: kafayı içeren mesh.
# CC0 gövdelerde ayrıca tam gövde modelinden ayrılan kafa+boyun, göz ve kaş meshleri (bas/goz/kas).
static func _head_info(id: String) -> Dictionary:
	if _parts.has(id):
		return _parts[id]
	var path: String = BODIES[id].bas
	var sc: Node = load(path).instantiate()
	var out := {}
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := String(m.name).to_lower()
		if m.skin == null:
			continue
		if n.contains("eyebrow"):
			out.kas = [m.mesh, m.skin]
		elif n.contains("eye"):
			out.goz = [m.mesh, m.skin]
		elif _bind_of(m.skin, "mixamorig_Head") != null and not out.has("bind"):
			out.bind = _bind_of(m.skin, "mixamorig_Head")
			out.head = (out.bind as Transform3D).affine_inverse().origin
			var nb: Variant = _bind_of(m.skin, "mixamorig_Neck")
			var neck: Vector3 = (nb as Transform3D).affine_inverse().origin if nb != null else (out.head as Vector3) + Vector3(0, -0.08, 0)
			var cb: Variant = _bind_of(m.skin, "mixamorig_Spine2")
			if cb != null and nb != null:
				out.chest_bind = cb
				out.neck = (nb as Transform3D).affine_inverse().origin
			var r := _cut_head(m.mesh, m.skin, neck)
			out.top = r[1]
			out.mesh = r[0]
			out.bas = [r[0], m.skin]
	sc.free()
	_parts[id] = out
	return out


# Kafa çerçevesi model uzayında: dik, kafa ortasında; yüz -z'ye bakar (model +z'ye baktığı için y ekseninde
# 180° dönük), ölçek kafa yarıçapı ~0.115 olacak şekilde (saç/şapka/sakal kodu bu çerçevede çalışır).
static func _frame_model(info: Dictionary) -> Transform3D:
	var head: Vector3 = info.head
	var top := Vector3(head.x, float(info.top), head.z)
	var r := head.distance_to(top) * 0.5
	return Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * (r / 0.115)), head.lerp(top, 0.45))


# Kafa ve boyun (ağırlığı kafa/boyun kemiğinde olan üçgenler) + gömleğin altına çekilmiş boyun/omuz kökü.
static func _cut_head(mesh: Mesh, skin: Skin, neck: Vector3) -> Array:
	var keep := {}
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		if bn == "mixamorig_Head" or bn == "mixamorig_Neck":
			keep[i] = true
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var nverts := verts.duplicate()
	var ok := PackedByteArray()
	ok.resize(verts.size())
	var top := -1e9
	for v in verts.size():
		var w := 0.0
		for k in per:
			if keep.has(bones[v * per + k]):
				w += weights[v * per + k]
		# boyun altı, omuz üstü ve göğsün üstü de alınır ama içeri (normalin tersine) çekilir: yaka
		# açıklıklarını doldurur, kollar kalkınca bile gömleğin altında kalır, kesik kenarı görünmez
		var p := verts[v]
		var dz := p.z - neck.z
		var hd := Vector2(p.x - neck.x, dz * (0.6 if dz > 0.0 else 1.0)).length()
		var in_neck := hd < 0.075 and p.y > neck.y - 0.06
		ok[v] = 1 if (w >= 0.5 and (p.y > neck.y + 0.03 or hd < 0.075)) or in_neck else 0
		if p.y < neck.y + 0.05:
			# boyun kökü yakanın altına doğru içeri çekilir
			var sink := clampf((neck.y + 0.05 - p.y) / 0.08, 0.0, 1.0) * 0.014
			nverts[v] = p - norms[v] * sink
		if w >= 0.5:
			top = maxf(top, verts[v].y)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nidx := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if ok[idx[t]] and ok[idx[t + 1]] and ok[idx[t + 2]]:
			nidx.append_array([idx[t], idx[t + 1], idx[t + 2]])
	arr[Mesh.ARRAY_INDEX] = nidx
	arr[Mesh.ARRAY_VERTEX] = nverts
	for ci in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arr[ci] = null
	var am := ArrayMesh.new()
	var flags: int = mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return [am, top]


# Bir gövdenin kafa şeklini (model uzayında) ölçüp saklar; saçlar hangi kafaya göre yapıldıysa ona göre taşınır.
static func _ensure_profile(id: String) -> void:
	if Hair.has_profile(id):
		return
	var info := _head_info(id)
	var frame := _frame_model(info)
	Hair.fit_head([[info.mesh, frame.affine_inverse()]], id, frame, false)


# Dokudaki ortalama ten rengi (ten pikselleri): boyama oranı buna göre hesaplanır.
static func _avg_skin(path: String) -> Color:
	if _avg.has(path):
		return _avg[path]
	var img := (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var sum := Vector3.ZERO
	var n := 0
	for y in 64:
		for x in 64:
			var c := img.get_pixel(x, y)
			if c.r > c.b * 1.12 and c.r > 0.25:  # ten pikseli (gri iç çamaşırı / koyu saç değil)
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	var avg := Color(sum.x / n, sum.y / n, sum.z / n) if n > 0 else Color(0.7, 0.5, 0.4)
	_avg[path] = avg
	return avg


static func _shaders() -> void:
	if _skin_shader:
		return
	_skin_shader = Shader.new()
	_skin_shader.code = SKIN_SHADER
	_cloth_shader = Shader.new()
	_cloth_shader.code = CLOTH_SHADER
	_eye_shader = Shader.new()
	_eye_shader.code = EYE_SHADER


func _skin_mat(tex: String, nrm: String, rgh: String, face: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _skin_shader
	m.set_shader_parameter("tex", load(tex))
	m.set_shader_parameter("nrm", load(nrm))
	if rgh != "":
		m.set_shader_parameter("rgh", load(rgh))
	var avg := _avg_skin(tex)
	var sk := Color(Catalog.SKIN[look.ten])
	m.set_shader_parameter("base_avg", Vector3(avg.r, avg.g, avg.b))
	m.set_shader_parameter("tint", Vector3(sk.r / avg.r, sk.g / avg.g, sk.b / avg.b))
	m.set_shader_parameter("hair_col", Color(Catalog.HAIR_COLORS[look.sac_renk]))
	if not face:
		m.set_shader_parameter("face_box", Vector4(-1, -1, -1, -1))
	else:
		# boyalı saç gölgesi kel seçilince silinir; kirli sakal sakallı seçimlerde kalır
		var sac := str(look.sac)
		m.set_shader_parameter("scalp", 0.0 if sac == "kel" else (1.0 if sac in ["asker", "kazi"] else 0.35))
		m.set_shader_parameter("stubble", 1.0 if look.sakal in ["kirli", "sakal", "keci", "hipster"] else (0.0 if _govde == "kadin" else 0.25))
	return m


func _cloth_mat(part: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _cloth_shader
	m.set_shader_parameter("tex", load(CLOTH_TEX))
	m.set_shader_parameter("nrm", load(CLOTH_N))
	m.set_shader_parameter("orm", load(CLOTH_ORM))
	m.set_shader_parameter("part", part)
	_cloth_mats.append([m, part == 1])
	return m


func _apply_colors() -> void:
	_shaders()
	var def: Dictionary = BODIES[_govde]
	var dark := int(look.ten) >= 3
	var o: Dictionary = Catalog.OUTFITS.get(look.kiyafet, Catalog.OUTFITS.turuncu)
	var hair_col := Color(Catalog.HAIR_COLORS[look.sac_renk])
	for mi in _skel.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := String(m.name)
		if n == "Bas":
			m.material_override = _skin_mat(def.ten[1 if dark else 0], def.ten_n, def.ten_r, true)
		elif n == "Goz":
			var e := ShaderMaterial.new()
			e.shader = _eye_shader
			e.set_shader_parameter("tex", load(EYE_TEX))
			e.set_shader_parameter("iris", Color(Catalog.EYE_COLORS[look.goz]))
			m.material_override = e
		elif n == "Kas":
			m.material_override = Hair.brow_material(def.kas, hair_col)
		else:
			for s in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(s)
				var sname := src.resource_name if src else ""
				var mat: Material
				if sname.contains("Regular"):
					mat = _skin_mat(def.el, def.el_n, "", false)
				else:
					mat = _cloth_mat(1 if n.contains("Legs") else (2 if n.contains("Feet") else 0))
				m.set_surface_override_material(s, mat)
	for c in _cloth_mats:
		var cm: ShaderMaterial = c[0]
		var leg: bool = c[1]
		cm.set_shader_parameter("color", Color(o.alt if leg else o.ust))
		cm.set_shader_parameter("pattern", int(o.get("ad" if leg else "ud", 0)))


# Kafa kemiğine bir düğüm takar; saç/sakal/gözlük kafa ölçüsüne göre kurulur, modele göre ölçeklenir.
func _attach_head_props() -> void:
	if not is_instance_valid(_skel):
		return
	var head_i := _skel.find_bone("mixamorig_Head")
	if head_i < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_idx = head_i
	_skel.add_child(ba)
	# kafa çerçevesi model uzayında kurulur, kafa kemiğine bağlama (bind) dönüşümüyle takılır:
	# gövdenin dünyadaki dönüşünden ve yeniden hedeflemenin dinlenme pozundan bağımsız
	var info := _head_info(_govde)
	var frame := _frame_model(info)
	_head = Node3D.new()
	_head.transform = (info.bind as Transform3D) * frame
	ba.add_child(_head)
	var hair_col := Color(Catalog.HAIR_COLORS[look.sac_renk])
	# saç/sakal kökleri gerçek kafa yüzeyine otursun diye kafa şekilleri ölçülür (gövde başına bir kez);
	# Quaternius saçları kadın/erkek kafasına göre yapıldığından iki kafa da ölçülür.
	for id in BODIES:
		_ensure_profile(id)
	_ensure_profile(_govde)
	Hair.use(_govde)
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
		# şapka, saçın ilk (taban) parçasını örter; örgü/kuyruk gibi sarkan ekler kutuya katılmaz
		for i in range(before, _head.get_child_count()):
			var mi := _head.get_child(i) as MeshInstance3D
			if mi:
				hair_box = mi.transform * mi.get_aabb()
				break
	Hats.build(_head, hat, hair_box)
	_apply_tattoo()
	if look.sakal != "yok":
		Hair.build_beard_any(_head, str(look.sakal), hair_col, true)
	Acc.build(_head, _skel, str(look.get("aksesuar", "yok")), info)
	_head.visible = not hide_head
	_char_layers(self)


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
		if not (mi as MeshInstance3D).get_parent() is BoneAttachment3D and _head and not _head.is_ancestor_of(mi) \
				and not String(mi.name) in ["Goz", "Kas"]:
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


func set_first_person(on: bool) -> void:
	show_head = not on
	_rig.visible = not on


func _apply_visibility() -> void:
	pass


func play_emote(id: String) -> void:
	if _player and _player.has_animation("hd/" + id):
		emote = id
		emote_t = 0.0
		_current = ""
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
		var max_t: float = EMOTE_LEN.get(emote, Emotes.LEN.get(emote, 999.0))
		if emote_t > max_t or not _player.is_playing() or _player.current_animation != "hd/" + emote:
			emote = ""
		else:
			return
	if seated:
		_play("oturma", 0.4)
		_player.speed_scale = 1.0
	elif crouched:
		_play("comel_yuru" if walk > 0.08 else "comel", 0.3)
		_player.speed_scale = clampf(walk * 1.2, 0.6, 1.3) if walk > 0.08 else 1.0
	elif walk > 1.15:
		_play("kosma")
		_player.speed_scale = clampf(walk / 1.5, 0.7, 1.3)
	elif walk > 0.08:
		_play("yurume")
		_player.speed_scale = clampf(walk * 1.1, 0.6, 1.4)
	else:
		_play("durma")
		_player.speed_scale = 1.0
