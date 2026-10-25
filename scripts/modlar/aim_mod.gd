# Karakter iskeletine animasyondan SONRA uygulanan poz: sağ kol hedefe uzanır (iki kemikli IK),
# ölünce gövde oturduğu yerde vurulduğu yöne yığılır (omurga, boyun, baş, kollar sarkar).
# Skeleton3D'nin çocuğu olarak eklenir; ağırlıklar (aim, slump) 0-1 arası yumuşakça değiştirilir.
extends SkeletonModifier3D

var aim := 0.0  # 0: animasyon, 1: el tamamen hedefte
var hand_target := Vector3.ZERO  # dünya konumu
var slump := 0.0  # 0: dik, 1: tamamen yığılmış
var slump_dir := Vector3.ZERO  # gövdenin yığılacağı yön (dünya uzayında, yatay)

var palm := Vector3.ZERO  # sağ avucun dünya konumu (pozlandıktan sonra); silah buraya oturur
var fingers := Vector3.ZERO  # avuçtan parmaklara doğru (dünya yönü): silah namlusu buna hizalanır
var _b := {}


func _bone(sk: Skeleton3D, n: String) -> int:
	if not _b.has(n):
		_b[n] = sk.find_bone("mixamorig_" + n)
	return _b[n]


func _process_modification() -> void:
	var sk := get_skeleton()
	if not sk:
		return
	if aim > 0.001:
		_ik(sk)
	if slump > 0.001:
		_slump(sk)
	var h := _bone(sk, "RightHand")
	var m := _bone(sk, "RightHandMiddle1")
	if h >= 0 and m >= 0:
		var hp := sk.global_transform * sk.get_bone_global_pose(h).origin
		var mp := sk.global_transform * sk.get_bone_global_pose(m).origin
		palm = hp.lerp(mp, 0.6)
		fingers = (mp - hp).normalized()


# Bir kemiği, kendi Y ekseni (çocuğuna doğru) iskelet uzayındaki `to` yönüne bakacak şekilde döndürür.
func _point(sk: Skeleton3D, b: int, from_dir: Vector3, to_dir: Vector3, w: float) -> void:
	if b < 0 or from_dir.length() < 1e-4 or to_dir.length() < 1e-4:
		return
	var q := Quaternion(from_dir.normalized(), to_dir.normalized())
	var g := sk.get_bone_global_pose(b)
	var p := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(p) if p >= 0 else Transform3D.IDENTITY
	var new_g := Basis(q) * g.basis
	var local := (pg.basis.inverse() * new_g).get_rotation_quaternion()
	var cur := sk.get_bone_pose_rotation(b)
	sk.set_bone_pose_rotation(b, cur.slerp(local, w))


func _ik(sk: Skeleton3D) -> void:
	var ua := _bone(sk, "RightArm")
	var fa := _bone(sk, "RightForeArm")
	var ha := _bone(sk, "RightHand")
	if ua < 0 or fa < 0 or ha < 0:
		return
	var inv := sk.global_transform.affine_inverse()
	var S := sk.get_bone_global_pose(ua).origin
	var E := sk.get_bone_global_pose(fa).origin
	var H := sk.get_bone_global_pose(ha).origin
	var l1 := S.distance_to(E)
	var l2 := E.distance_to(H)
	var T := inv * hand_target
	var d := T - S
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
	var n := d.normalized()
	T = S + n * dist
	# dirsek aşağı ve biraz dışarı baksın
	var right := (S - sk.get_bone_global_pose(_bone(sk, "LeftArm")).origin).normalized()
	var down_sk := (inv.basis * Vector3.DOWN).normalized()  # iskelet döndürülmüş/ölçekli olabilir
	var pole := (down_sk * 0.8 + right * 0.5).normalized()
	var pp := (pole - n * pole.dot(n))
	if pp.length() < 1e-3:
		pp = right
	pp = pp.normalized()
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var E2 := S + n * (l1 * ca) + pp * (l1 * sqrt(1.0 - ca * ca))
	_point(sk, ua, E - S, E2 - S, aim)
	var E_now := sk.get_bone_global_pose(fa).origin
	var H_now := sk.get_bone_global_pose(ha).origin
	_point(sk, fa, H_now - E_now, T - E_now, aim)


func _slump(sk: Skeleton3D) -> void:
	# gövde zinciri vurulduğu yöne (dünya yönü, iskelet uzayına çevrilir) eğilir, baş düşer
	var inv := sk.global_transform.basis.inverse()
	var dir_sk := (inv * slump_dir).normalized() if slump_dir.length() > 0.01 else Vector3.ZERO
	var down_b := (inv * Vector3.DOWN).normalized()
	var chain := [["Spine", "Spine1", 0.22], ["Spine1", "Spine2", 0.28], ["Spine2", "Neck", 0.32], ["Neck", "Head", 0.55], ["Head", "HeadTop_End", 0.75]]
	for c in chain:
		var b := _bone(sk, c[0])
		var ch := _bone(sk, c[1])
		if b < 0 or ch < 0:
			continue
		var from := sk.get_bone_global_pose(ch).origin - sk.get_bone_global_pose(b).origin
		var k: float = c[2] * slump
		var to := (from.normalized() + dir_sk * k * 1.6 + down_b * k * 0.5).normalized()
		_point(sk, b, from, to, 1.0)
	# kollar gevşeyip aşağı sarkar
	var down_sk := (sk.global_transform.basis.inverse() * Vector3.DOWN).normalized()
	for arm in [["RightArm", "RightForeArm"], ["LeftArm", "LeftForeArm"]]:
		var ua := _bone(sk, arm[0])
		var fa := _bone(sk, arm[1])
		if ua < 0 or fa < 0:
			continue
		var S := sk.get_bone_global_pose(ua).origin
		var E := sk.get_bone_global_pose(fa).origin
		var down := down_sk
		_point(sk, ua, E - S, down, slump * 0.85)
		var E_now := sk.get_bone_global_pose(fa).origin
		var H_now := sk.get_bone_global_pose(_bone(sk, arm[0].replace("Arm", "Hand"))).origin
		_point(sk, fa, H_now - E_now, down, slump * 0.85)
