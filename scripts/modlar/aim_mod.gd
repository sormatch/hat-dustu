# Karakter iskeletine animasyondan SONRA uygulanan poz (Skeleton3D'nin çocuğu olarak eklenir):
# - İki kol için iki kemikli IK: avucun ortası hedefe gider, dirsek doğal yöne (aşağı-dışarı ya da
#   verilen yöne) bakar; bilek istenen yöne döner (parmak yönü + başparmak yönü), dönüşün yarısı
#   ön kola dağıtılır (bilek burulmaz); parmaklar verilen oranda kıvrılıp kavrar.
# - Eldeki eşya (silah, ahize, bomba) her karede, kemikler pozlandıktan SONRA avuca oturtulur.
# - Ölünce gövde oturduğu yerde vurulduğu yöne yığılır (omurga, boyun, baş, kollar sarkar).
# Ağırlıklar (aim, aim_l, slump) 0-1 arası; 0 iken animasyon olduğu gibi kalır.
#
# Avuç çerçevesi (dünya uzayında, `frame(taraf)`): orijin avucun ortası, -Z parmaklara doğru (bilekten
# boğumlara), +Y başparmak tarafı (eldeki silahın üstü). Sağ elde avuç -X'e, sol elde +X'e bakar.
extends SkeletonModifier3D

const SIDE_NAMES := ["Left", "Right"]
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]
# tam kavrayışta her boğumun kıvrılma açısı (derece): 1., 2., 3. boğum
const CURL_DEG := [[22.0, 20.0, 25.0], [62.0, 88.0, 52.0], [70.0, 92.0, 55.0], [72.0, 92.0, 55.0], [74.0, 88.0, 52.0]]
const PALM_ALONG := 0.5  # avuç ortası: bilek ile orta parmak boğumu arasında
const PALM_DEPTH := 0.016  # avuç yüzeyi: kemik çizgisinden avuç tarafına

# taraf dizileri: 0 = sol, 1 = sağ
var weights := [0.0, 0.0]  # 0: animasyon, 1: el tamamen hedefte
var targets := [Vector3.ZERO, Vector3.ZERO]  # avuç ortasının dünya konumu
var forwards := [Vector3.ZERO, Vector3.ZERO]  # parmak yönü (dünya); ZERO: bilek animasyondaki gibi
var ups := [Vector3.ZERO, Vector3.ZERO]  # başparmak yönü (dünya)
var poles := [Vector3.ZERO, Vector3.ZERO]  # dirseğin bakacağı yön (dünya); ZERO: aşağı-dışarı
var curls := [[0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0]]  # başparmak..serçe, 0-1
var helds: Array = [null, null]  # avuca oturtulan düğümler
var held_offsets := [Transform3D.IDENTITY, Transform3D.IDENTITY]  # avuç çerçevesine göre
var frames := [Transform3D.IDENTITY, Transform3D.IDENTITY]  # çıktı: avuç çerçeveleri (dünya)

var slump := 0.0  # 0: dik, 1: tamamen yığılmış
var slump_dir := Vector3.ZERO  # gövdenin yığılacağı yön (dünya uzayında, yatay)

# Uzaktaki oyuncular için hazır tutma pozları (hedefler her karede gövdenin o anki kemiklerinden hesaplanır):
# "silah" altıpatar elde, namlu masaya; "sakak" namlu sağ şakakta; "hedef" kol mode_target'e uzanır;
# "c4" bomba sol avuçta, göğüs önünde. Ağırlığı aim (silah) ya da aim_l (c4) belirler.
var mode := ""
var mode_target := Vector3.ZERO
var _mode_xf := Transform3D.IDENTITY  # yumuşatılmış eşya çerçevesi (iskelet uzayında)
var _mode_kind := ""
var _last_us := 0

# sağ kol için kısa adlar
var aim: float:
	get:
		return weights[1]
	set(v):
		weights[1] = v
var hand_target: Vector3:
	get:
		return targets[1]
	set(v):
		targets[1] = v
var hand_forward: Vector3:
	get:
		return forwards[1]
	set(v):
		forwards[1] = v
var hand_up: Vector3:
	get:
		return ups[1]
	set(v):
		ups[1] = v
var aim_l: float:
	get:
		return weights[0]
	set(v):
		weights[0] = v
var palm: Vector3:  # sağ avucun dünya konumu
	get:
		return (frames[1] as Transform3D).origin
var fingers: Vector3:  # sağ avuçtan parmaklara (dünya yönü)
	get:
		return -(frames[1] as Transform3D).basis.z

var _b := {}


func _bone(sk: Skeleton3D, n: String) -> int:
	if not _b.has(n):
		_b[n] = sk.find_bone("mixamorig_" + n)
	return _b[n]


func frame(side: int) -> Transform3D:
	return frames[side]


# Bir tarafın tüm el pozunu tek seferde ayarlar (dünya uzayı).
func set_hand(side: int, weight: float, target: Vector3, fwd := Vector3.ZERO, up := Vector3.ZERO, pole := Vector3.ZERO, curl: Array = []) -> void:
	weights[side] = weight
	targets[side] = target
	forwards[side] = fwd
	ups[side] = up
	poles[side] = pole
	curls[side] = curl if curl.size() == 5 else [0.0, 0.0, 0.0, 0.0, 0.0]


# Eşyayı avuca bağlar; offset avuç çerçevesine göre (null: bırak).
func hold(side: int, node: Node3D, offset := Transform3D.IDENTITY) -> void:
	helds[side] = node
	held_offsets[side] = offset


func _process_modification() -> void:
	var sk := get_skeleton()
	if not sk:
		return
	if mode != "":
		_apply_mode(sk)
	for side in 2:
		var w: float = weights[side]
		if w > 0.001:
			_arm(sk, side, w)
		var c: Array = curls[side]
		if w > 0.001 and (c[0] + c[1] + c[2] + c[3] + c[4]) > 0.001:
			_curl(sk, side, w)
	if slump > 0.001:
		_slump(sk)
	for side in 2:
		frames[side] = sk.global_transform * _hand_frame_sk(sk, side)
		var h = helds[side]
		if h != null:
			if is_instance_valid(h):
				(h as Node3D).global_transform = (frames[side] as Transform3D) * (held_offsets[side] as Transform3D)
			else:
				helds[side] = null


func _pos(sk: Skeleton3D, n: String) -> Vector3:
	var b := _bone(sk, n)
	return sk.get_bone_global_pose(b).origin if b >= 0 else Vector3.ZERO


# Avuç çerçevesi iskelet uzayında (kemiklerin şu anki pozundan).
func _hand_frame_sk(sk: Skeleton3D, side: int) -> Transform3D:
	var s: String = SIDE_NAMES[side]
	var h := _pos(sk, s + "Hand")
	var m := _pos(sk, s + "HandMiddle1")
	var i := _pos(sk, s + "HandIndex1")
	var p := _pos(sk, s + ("HandPinky1" if _bone(sk, s + "HandPinky1") >= 0 else "HandRing1"))  # serçesi olmayan modelde yüzük parmağı
	var f := m - h
	if f.length() < 1e-5:
		return Transform3D(Basis.IDENTITY, h)
	f = f.normalized()
	var b := _basis(f, i - p)
	return Transform3D(b, h + (m - h) * PALM_ALONG + _palm_normal(side, b) * PALM_DEPTH)


# Parmak yönü (f) ve başparmak yönünden (a) avuç çerçevesi: -Z = f, Y = a.
static func _basis(f: Vector3, a: Vector3) -> Basis:
	var z := -f.normalized()
	var y := a - z * a.dot(z)
	if y.length() < 1e-4:
		y = Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT
		y = y - z * y.dot(z)
	y = y.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


# Avucun baktığı yön: sağ elde -X, sol elde +X.
static func _palm_normal(side: int, b: Basis) -> Vector3:
	return -b.x if side == 1 else b.x


# Bir kemiği global dönüşü `new_g` olacak şekilde (ağırlıkla) döndürür.
func _set_global_rot(sk: Skeleton3D, b: int, new_g: Basis, w: float) -> void:
	var p := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var local := (pg.inverse() * new_g.orthonormalized()).get_rotation_quaternion()
	var cur := sk.get_bone_pose_rotation(b)
	sk.set_bone_pose_rotation(b, cur.slerp(local, w) if w < 0.999 else local)


# Bir kemiği, kendi yönü (çocuğuna doğru) iskelet uzayındaki `to_dir` yönüne bakacak şekilde döndürür.
func _point(sk: Skeleton3D, b: int, from_dir: Vector3, to_dir: Vector3, w: float) -> void:
	if b < 0 or from_dir.length() < 1e-5 or to_dir.length() < 1e-5:
		return
	var q := Quaternion(from_dir.normalized(), to_dir.normalized())
	var g := sk.get_bone_global_pose(b)
	_set_global_rot(sk, b, Basis(q) * g.basis.orthonormalized(), w)


func _arm(sk: Skeleton3D, side: int, w: float) -> void:
	var s: String = SIDE_NAMES[side]
	var ua := _bone(sk, s + "Arm")
	var fa := _bone(sk, s + "ForeArm")
	var ha := _bone(sk, s + "Hand")
	var other := _bone(sk, SIDE_NAMES[1 - side] + "Arm")
	if ua < 0 or fa < 0 or ha < 0 or other < 0:
		return
	var inv := sk.global_transform.affine_inverse()
	var S := sk.get_bone_global_pose(ua).origin
	var E := sk.get_bone_global_pose(fa).origin
	var H := sk.get_bone_global_pose(ha).origin
	var l1 := S.distance_to(E)
	var l2 := E.distance_to(H)
	# istenen bilek yönü (iskelet uzayında)
	var want_basis := Basis()
	var fwd_w: Vector3 = forwards[side]
	var has_dir := fwd_w.length() > 0.01
	if has_dir:
		var up_w: Vector3 = ups[side]
		if up_w.length() < 0.01:
			up_w = Vector3.UP
		want_basis = _basis(inv.basis * fwd_w, inv.basis * up_w)
	# avuç ortası hedefte olsun: bilek hedefi = avuç - (avucun bileğe göre konumu)
	var cur_frame := _hand_frame_sk(sk, side)
	var palm_off := cur_frame.origin - H
	if has_dir:
		palm_off = want_basis * (cur_frame.basis.inverse() * palm_off)
	var T: Vector3 = inv * (targets[side] as Vector3) - palm_off
	var d := T - S
	var dist := clampf(d.length(), absf(l1 - l2) + 0.02, l1 + l2 - 0.004)
	var n := d.normalized()
	T = S + n * dist
	# dirsek yönü
	var outward := (S - sk.get_bone_global_pose(other).origin).normalized()
	var down_sk := (inv.basis * Vector3.DOWN).normalized()
	var pole_w: Vector3 = poles[side]
	var pole_sk := (inv.basis * pole_w).normalized() if pole_w.length() > 0.01 else (down_sk * 0.8 + outward * 0.5).normalized()
	var pp := pole_sk - n * pole_sk.dot(n)
	if pp.length() < 1e-3:
		pp = down_sk - n * down_sk.dot(n)
		if pp.length() < 1e-3:
			pp = outward
	pp = pp.normalized()
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var E2 := S + n * (l1 * ca) + pp * (l1 * sqrt(1.0 - ca * ca))
	_point(sk, ua, E - S, E2 - S, w)
	var E_now := sk.get_bone_global_pose(fa).origin
	var H_now := sk.get_bone_global_pose(ha).origin
	_point(sk, fa, H_now - E_now, T - E_now, w)
	if not has_dir:
		return
	# bilek: avuç çerçevesi istenen çerçeveye dönsün; burulmanın yarısını ön kol alır
	var frame_now := _hand_frame_sk(sk, side)
	var rot := Quaternion((want_basis * frame_now.basis.inverse()).orthonormalized())
	var want_hand := Basis(rot) * sk.get_bone_global_pose(ha).basis.orthonormalized()
	var axis := (sk.get_bone_global_pose(ha).origin - sk.get_bone_global_pose(fa).origin).normalized()
	var v := Vector3(rot.x, rot.y, rot.z)
	var tw := Quaternion(axis.x * v.dot(axis), axis.y * v.dot(axis), axis.z * v.dot(axis), rot.w)
	if tw.length() > 1e-5:
		var half := Quaternion.IDENTITY.slerp(tw.normalized(), 0.5)
		var fg := sk.get_bone_global_pose(fa).basis.orthonormalized()
		_set_global_rot(sk, fa, Basis(half) * fg, w)
	_set_global_rot(sk, ha, want_hand, w)


# Parmakları avuca doğru kıvırır (kavrama).
func _curl(sk: Skeleton3D, side: int, w: float) -> void:
	var s: String = SIDE_NAMES[side]
	var c: Array = curls[side]
	var fr := _hand_frame_sk(sk, side)
	var palm_n := _palm_normal(side, fr.basis)
	for f in 5:
		var k: float = c[f] * w
		if k < 0.001:
			continue
		# başparmak avucun içine, serçe parmak tarafına doğru kapanır
		var to := palm_n if f > 0 else (palm_n * 0.75 - fr.basis.z * 0.45 - fr.basis.y * 0.25).normalized()
		# kıvrılma ekseni parmağın ilk boğumundan bir kez hesaplanır (kıvrıldıkça eksen dönmesin)
		var b1 := _bone(sk, "%sHand%s1" % [s, FINGERS[f]])
		var b2 := _bone(sk, "%sHand%s2" % [s, FINGERS[f]])
		if b1 < 0 or b2 < 0:
			continue
		var axis := (sk.get_bone_global_pose(b2).origin - sk.get_bone_global_pose(b1).origin).cross(to)
		if axis.length() < 1e-6:
			continue
		axis = axis.normalized()
		for j in 3:
			var b := _bone(sk, "%sHand%s%d" % [s, FINGERS[f], j + 1])
			if b < 0:
				break
			var g := sk.get_bone_global_pose(b)
			var ang := deg_to_rad(CURL_DEG[f][j]) * k
			_set_global_rot(sk, b, Basis(axis, ang) * g.basis.orthonormalized(), 1.0)


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
	for arm in [["RightArm", "RightForeArm", "RightHand"], ["LeftArm", "LeftForeArm", "LeftHand"]]:
		var ua := _bone(sk, arm[0])
		var fa := _bone(sk, arm[1])
		var ha := _bone(sk, arm[2])
		if ua < 0 or fa < 0 or ha < 0:
			continue
		var S := sk.get_bone_global_pose(ua).origin
		var E := sk.get_bone_global_pose(fa).origin
		_point(sk, ua, E - S, down_b, slump * 0.85)
		var E_now := sk.get_bone_global_pose(fa).origin
		var H_now := sk.get_bone_global_pose(ha).origin
		_point(sk, fa, H_now - E_now, down_b, slump * 0.85)


# ---------- avuçtaki eşyalar ----------
# Eşyanın avuç çerçevesine göre duruşu (avuç -> eşya). Eşyanın kendi ekseni: altıpatarda namlu -Z, üstü +Y;
# C4'te uzun kenar X, ekran +Y; ahizede sap Y, kulaklık +Z.
static func item_offset(kind: String, side := 1) -> Transform3D:
	var s := -1.0 if side == 1 else 1.0  # avucun baktığı yön (X ekseninde)
	match kind:
		"silah":
			# kabza avucun içinde, kabza ekseni elin başparmak-serçe ekseninde; namlu buna göre ~24° yukarı
			var b := Basis(Vector3.RIGHT, 0.42)
			var grip := Vector3(0, -0.02, 0.006)  # kabzanın ortası (altıpatar kök ekseninde)
			return Transform3D(b, Vector3(s * 0.017, -0.005, 0.004) - b * grip)
		"c4":
			# bomba kitap gibi ucundan tutulur: avuç bombanın yan yüzünde, başparmak üstte, parmaklar altında
			return Transform3D(Basis.IDENTITY, Vector3(s * 0.105, -0.004, 0.0))
		"ahize":
			# sap avuç boyunca, kulaklık avuçtan dışarı (yüze) bakar
			return Transform3D(Basis(Vector3(0, 0, -s), Vector3(0, 1, 0), Vector3(s, 0, 0)), Vector3(s * 0.03, 0, 0))
	return Transform3D.IDENTITY


# Eşyanın istenen çerçevesinden avucun olması gereken çerçeve.
static func hand_for_item(item: Transform3D, kind: String, side := 1) -> Transform3D:
	return item * item_offset(kind, side).affine_inverse()


# Hazır pozun eşya çerçevesini gövdenin o anki kemiklerinden hesaplar, yumuşatır ve el hedefine çevirir.
func _apply_mode(sk: Skeleton3D) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1000000.0, 0.0, 0.1) if _last_us > 0 else 0.0
	_last_us = now
	var g := sk.global_transform
	var head := g * _pos(sk, "Head")
	var S := g * _pos(sk, "RightArm")
	var L := g * _pos(sk, "LeftArm")
	var chest := g * _pos(sk, "Spine2")
	var right := S - L
	right.y = 0.0
	right = right.normalized()
	var up := Vector3.UP
	var fwd := up.cross(right).normalized()  # karakterin baktığı yön
	var kind := "c4" if mode == "c4" else ("ahize" if mode == "ahize" else "silah")
	var side := 0 if kind == "c4" else 1
	var item := Transform3D.IDENTITY
	var pole := Vector3.ZERO
	var curl: Array = [0.6, 0.45, 1.0, 1.0, 1.0]
	match mode:
		"silah":
			# boşta: el masanın üstünde, namlu masanın ortasına doğru eğik
			var d := (fwd * 0.9 - right * 0.25 - up * 0.42).normalized()
			item = Transform3D(_basis(d, up), S + fwd * 0.36 - up * 0.2 - right * 0.03)
			pole = (right * 0.6 - up * 0.8).normalized()
		"sakak":
			# namlu sağ şakağa dayalı: silah başın yanında yatay, namlu başa bakar, bilek bükük
			var temple := head + up * 0.085 + right * 0.08 + fwd * 0.045
			var d := (-right + fwd * 0.12 + up * 0.05).normalized()
			var b := _basis(d, (up - fwd * 0.25).normalized())
			var muzzle := b * Vector3(0, 0.03, -0.192)
			item = Transform3D(b, temple - muzzle + d * -0.004)
			pole = (right * 0.85 - up * 0.45 + fwd * 0.1).normalized()
		"hedef":
			# kol hedefe uzanır, namlu hedefe bakar
			var t := mode_target if mode_target != Vector3.ZERO else S + fwd
			var dir := (t - S).normalized()
			var o := S + dir * 0.46 - up * 0.035
			item = Transform3D(_basis(t - o, up), o)
			pole = (-up * 0.85 + right * 0.4).normalized()
		"ahize":
			# telefonda: ahize kulakta, dirsek yana ve aşağı
			item = handset_at_head(head, right, fwd)
			pole = (right * 0.8 - up * 0.6).normalized()
			curl = [0.6, 0.8, 0.85, 0.85, 0.85]
		"c4":
			# bomba sol avuçta, göğsün önünde, ekranı yukarı
			var o := chest + fwd * 0.34 - up * 0.1 - right * 0.06
			item = Transform3D(_basis((fwd - right * 0.2).normalized(), (up + fwd * 0.25).normalized()), o)
			pole = (-up * 0.85 - right * 0.4).normalized()
			curl = [0.3, 0.5, 0.5, 0.55, 0.6]
	var want := g.affine_inverse() * item
	if kind != _mode_kind or dt <= 0.0:
		_mode_xf = want
		_mode_kind = kind
	else:
		var k := 1.0 - exp(-dt * 7.0)
		var q := _mode_xf.basis.get_rotation_quaternion().slerp(want.basis.get_rotation_quaternion(), k)
		_mode_xf = Transform3D(Basis(q), _mode_xf.origin.lerp(want.origin, k))
	var hand := hand_for_item(g * _mode_xf, kind, side)
	targets[side] = hand.origin
	forwards[side] = -hand.basis.z
	ups[side] = hand.basis.y
	poles[side] = pole
	curls[side] = curl


# Bir karakter gövdesinin iskeletindeki pozlayıcı (yoksa takılır); iskelet yoksa null.
static func of_body(body: Node) -> Node:
	if not is_instance_valid(body):
		return null
	var sks: Array = body.find_children("*", "Skeleton3D", true, false)
	var sk: Skeleton3D = null
	for s in sks:
		var n: Node = s
		while n and n != body and not n.is_queued_for_deletion():
			n = n.get_parent()
		if n == body:
			sk = s
			break
	if sk == null:
		return null
	for c in sk.get_children():
		if c.get_script() == load("res://scripts/modlar/aim_mod.gd"):
			return c
	var m: Node = load("res://scripts/modlar/aim_mod.gd").new()
	sk.add_child(m)
	return m


# Telefondaki uzak oyuncu için ahize duruşu (kulaklık kulakta, ağızlık çenede); _apply_mode'un "ahize" kolu.
static func handset_at_head(head: Vector3, right: Vector3, fwd: Vector3) -> Transform3D:
	var up := Vector3.UP
	var ear := head + up * 0.085 + right * 0.08 - fwd * 0.005
	var mouth := head + up * 0.015 + fwd * 0.09 + right * 0.035
	var axis := (ear - mouth).normalized()
	var out := (right - axis * right.dot(axis)).normalized()  # ahizenin sırtı dışarı, kapaklar yüze
	return Transform3D(_basis(out, axis), (ear + mouth) * 0.5 + out * 0.035)
