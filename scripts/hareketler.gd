# Koddan üretilen hareketler (emote): gülme, ağlama, kızma, "tüh" (avuç yüzde), düşünme.
# Hazır CC0 animasyonu olmayan duygular, duruş (durma) animasyonunun üstüne kurulur:
#  - gövde/baş: kemiğin kendi ekseninde açı (+ titreşim: gülerken sarsılma gibi),
#  - kollar: üst kol ve ön kolun gövdeye göre bakacağı YÖN verilir (+y yukarı, +z ön, +x karakterin solu);
#    kemik dönüşü bu yöne çevrilerek hesaplanır (basit yön IK'sı),
#  - yumruk: parmaklar kıvrılır.
# Bütün iskeletler aynı insansı profile yeniden hedeflendiğinden (eksenler aynı) her gövdede aynı görünür.
extends RefCounted

const P := "%GeneralSkeleton:mixamorig_"
const FPS := 30.0
const PROFILE := "res://assets/karakter/mixamo_profil.tres"

# eksen dönüşleri: [kemik, eksen, sabit açı, salınım genliği, frekans (Hz), faz]
const TURNS := {
	"gul": [
		["Spine", Vector3.RIGHT, -6.0, 4.0, 3.2, 0.0], ["Spine1", Vector3.RIGHT, -5.0, 3.0, 3.2, 0.3],
		["Spine2", Vector3.RIGHT, -3.0, 3.0, 3.2, 0.6], ["Neck", Vector3.RIGHT, -10.0, 3.0, 3.2, 0.9],
		["Head", Vector3.RIGHT, -16.0, 5.0, 3.2, 1.2],
	],
	"agla": [
		["Spine1", Vector3.RIGHT, 10.0, 1.5, 4.5, 0.0], ["Spine2", Vector3.RIGHT, 8.0, 1.5, 4.5, 0.4],
		["Neck", Vector3.RIGHT, 12.0, 0.0, 0.0, 0.0], ["Head", Vector3.RIGHT, 16.0, 2.0, 4.5, 0.8],
	],
	"kiz": [
		["Spine1", Vector3.RIGHT, 8.0, 0.0, 0.0, 0.0], ["Head", Vector3.RIGHT, 6.0, 3.0, 5.0, 0.0],
	],
	"tuh": [
		["Spine1", Vector3.RIGHT, 6.0, 0.0, 0.0, 0.0], ["Head", Vector3.RIGHT, 20.0, 0.0, 0.0, 0.0],
		["Head", Vector3.UP, 0.0, 9.0, 1.3, 0.0],
	],
	"dusun": [
		["Head", Vector3.RIGHT, -5.0, 0.0, 0.0, 0.0], ["Head", Vector3.FORWARD, 7.0, 0.0, 0.0, 0.0],
		["Head", Vector3.UP, 0.0, 4.0, 0.6, 0.0],
	],
}
# kol yönleri: [kemik, yön (gövdeye göre), titreşim ekseni, titreşim açısı, frekans]
const AIMS := {
	"gul": [
		["RightArm", Vector3(-0.3, -0.85, 0.42), Vector3.RIGHT, 4.0, 3.2], ["RightForeArm", Vector3(0.8, 0.05, 0.6), Vector3.UP, 5.0, 3.2],
		["LeftArm", Vector3(0.3, -0.85, 0.42), Vector3.RIGHT, 4.0, 3.2], ["LeftForeArm", Vector3(-0.8, 0.05, 0.6), Vector3.UP, 5.0, 3.2],
	],
	"agla": [
		["RightArm", Vector3(-0.25, -0.5, 0.83), Vector3.RIGHT, 2.0, 4.5], ["RightForeArm", Vector3(0.38, 0.86, 0.34), Vector3.UP, 0.0, 0.0],
		["LeftArm", Vector3(0.25, -0.5, 0.83), Vector3.RIGHT, 2.0, 4.5], ["LeftForeArm", Vector3(-0.38, 0.86, 0.34), Vector3.UP, 0.0, 0.0],
	],
	"kiz": [
		["RightArm", Vector3(-0.35, 0.2, 0.9), Vector3.RIGHT, 6.0, 5.0], ["RightForeArm", Vector3(0.1, 0.95, 0.3), Vector3.RIGHT, 18.0, 5.0],
		["LeftArm", Vector3(0.18, -0.96, 0.1), Vector3.RIGHT, 0.0, 0.0], ["LeftForeArm", Vector3(0.12, -0.75, 0.6), Vector3.RIGHT, 0.0, 0.0],
	],
	"tuh": [
		["RightArm", Vector3(-0.22, -0.32, 0.92), Vector3.RIGHT, 0.0, 0.0], ["RightForeArm", Vector3(0.42, 0.86, 0.28), Vector3.UP, 0.0, 0.0],
	],
	"dusun": [
		["RightArm", Vector3(-0.12, -0.62, 0.6), Vector3.RIGHT, 0.0, 0.0], ["RightForeArm", Vector3(0.28, 0.9, 0.33), Vector3.UP, 0.0, 0.0],
		["LeftArm", Vector3(0.12, -0.72, 0.5), Vector3.RIGHT, 0.0, 0.0], ["LeftForeArm", Vector3(-0.85, 0.12, 0.5), Vector3.UP, 0.0, 0.0],
	],
}
# yumruk yapılan eller
const FISTS := {"kiz": ["Right", "Left"], "dusun": ["Right"], "agla": [], "gul": [], "tuh": []}
const LEN := {"gul": 3.2, "agla": 3.6, "kiz": 2.8, "tuh": 2.6, "dusun": 3.4}
const IDS: Array[String] = ["gul", "agla", "kiz", "tuh", "dusun"]
# kol zinciri (kök -> el): kolun dünya yönü hesaplanırken ebeveyn dönüşleri sırayla çarpılır
const CHAIN := ["Hips", "Spine", "Spine1", "Spine2"]


static func _env(t: float, dur: float) -> float:
	var a := clampf(t / 0.35, 0.0, 1.0)
	var b := clampf((dur - t) / 0.4, 0.0, 1.0)
	return smoothstep(0.0, 1.0, minf(a, b))


static func make(id: String, base: Animation) -> Animation:
	var prof: SkeletonProfile = load(PROFILE)
	var dur: float = LEN.get(id, 3.0)
	var a := Animation.new()
	a.length = dur
	a.loop_mode = Animation.LOOP_NONE
	var turns := {}
	for s in TURNS.get(id, []):
		turns[s[0]] = turns.get(s[0], []) + [s]
	var aims := {}
	for s in AIMS.get(id, []):
		aims[s[0]] = s
	var fist := {}
	for side in FISTS.get(id, []):
		for f in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for j in [1, 2, 3]:
				fist["%sHand%s%d" % [side, f, j]] = f == "Thumb"
	var tracks := {}  # kemik -> duruş izi
	for t in base.get_track_count():
		var bone := String(base.track_get_path(t)).get_slice(":", 1).trim_prefix("mixamorig_")
		if base.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			tracks[bone] = t
	var n := int(dur * FPS) + 1
	# her karede yerel dönüşler: duruş + eksen dönüşleri + kol yönleri
	var keys := {}  # kemik -> Array[Quaternion]
	var all_bones := {}
	for b in tracks:
		all_bones[b] = true
	for b in turns:
		all_bones[b] = true
	for b in aims:
		all_bones[b] = true
	for b in fist:
		all_bones[b] = true
	for b in all_bones:
		keys[b] = []
	for k in n:
		var time := k / FPS
		var bt := fmod(time, base.length)
		var e := _env(time, dur)
		var local := {}
		for b in all_bones:
			var q: Quaternion
			if tracks.has(b):
				q = base.rotation_track_interpolate(tracks[b], bt)
			else:
				q = _ref(prof, b)
			if turns.has(b):
				q = q * _turn(turns[b], time, e)
			if fist.has(b):
				q = q * Quaternion(Vector3.UP if fist[b] else Vector3.RIGHT, deg_to_rad((30.0 if fist[b] else 75.0) * e))
			local[b] = q
		# kollar: omuz -> üst kol -> ön kol, gövdenin o anki dönüşüne göre
		for side in ["Left", "Right"]:
			var g := Quaternion.IDENTITY
			for c in CHAIN:
				g = g * (local[c] if local.has(c) else _ref(prof, c))
			var sh: String = side + "Shoulder"
			g = g * (local[sh] if local.has(sh) else _ref(prof, sh))
			for part in [side + "Arm", side + "ForeArm"]:
				var lq: Quaternion = local[part] if local.has(part) else _ref(prof, part)
				if aims.has(part):
					var s: Array = aims[part]
					var cur: Quaternion = g * lq
					var want: Vector3 = (s[1] as Vector3).normalized()
					if float(s[3]) != 0.0:
						want = Quaternion((s[2] as Vector3).normalized(), deg_to_rad(float(s[3]) * sin(TAU * float(s[4]) * time))) * want
					var from := cur * Vector3.UP
					var turn := Quaternion.IDENTITY.slerp(Quaternion(from.normalized(), want.normalized()), e)
					lq = g.inverse() * (turn * cur)
					local[part] = lq
				g = g * lq
		for b in all_bones:
			keys[b].append(local[b])
	for b in all_bones:
		var nt := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(nt, NodePath(P + b))
		var arr: Array = keys[b]
		for k in n:
			a.rotation_track_insert_key(nt, k / FPS, arr[k])
	# kalça konumu (duruştaki hafif salınım)
	for t in base.get_track_count():
		if base.track_get_type(t) == Animation.TYPE_POSITION_3D:
			var nt := a.add_track(Animation.TYPE_POSITION_3D)
			a.track_set_path(nt, base.track_get_path(t))
			for k in n:
				a.position_track_insert_key(nt, k / FPS, base.position_track_interpolate(t, fmod(k / FPS, base.length)))
	return a


static func _ref(prof: SkeletonProfile, bone: String) -> Quaternion:
	var i := prof.find_bone("mixamorig_" + bone)
	return prof.get_reference_pose(i).basis.get_rotation_quaternion() if i >= 0 else Quaternion.IDENTITY


static func _turn(list: Array, time: float, e: float) -> Quaternion:
	var q := Quaternion.IDENTITY
	for s in list:
		var ang: float = (float(s[2]) + float(s[3]) * sin(TAU * float(s[4]) * time + float(s[5]))) * e
		q = q * Quaternion((s[1] as Vector3).normalized(), deg_to_rad(ang))
	return q
