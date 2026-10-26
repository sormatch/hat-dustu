# Birinci şahıs oyuncu: yürür, etrafa bakar, koltuğa oturup kalkar.
# Kendi gövdesi gerçek karakter modelidir (kafası gizli): aşağı bakınca bacaklarını görür; ahize,
# silah, bomba tutarken ya da kapı iterken gördüğü kollar ve eller de bu modelin gerçek kollarıdır
# (iskelete IK ile poz verilir, parmaklar kavrar, eşya gerçek avuca oturur).
extends CharacterBody3D

const BodyScript := preload("res://scripts/body.gd")
const ModelScript := preload("res://scripts/model_body.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const Telefon := preload("res://scripts/telefon.gd")
const Sfx := preload("res://scripts/sfx.gd")

const SPEED := 2.4
const EYE_STAND := 1.6
const EYE_SEAT := 1.05
const RUN_MULT := 1.9
const EYE_CROUCH := 1.05
const EYE_BEHIND := 0.11  # gövdenin kafa kemiği kameranın bu kadar arkasında durur (göz hizası)
const FP_LAYER := 1 << 16  # birinci şahıs gövdesi (mirror.gd ile aynı): ayna kamerası görmez
const LEASH_SOFT := 1.7  # kablo bu mesafeden sonra gerilmeye başlar (m)
const LEASH_HARD := 2.5  # bunu aşınca ahize elden kayar
# Hareket (emote) sırasında üçüncü şahıs kamera: karakterin önüne-yanına döner, kendini görürsün.
const TP_TIME := 0.35  # geçiş süresi (sn)
const TP_MIN := 1.6  # kısa hareketlerde bile kamera en az bu kadar dışarıda kalır (sn)
const TP_DIST := 2.2  # istenen uzaklık (m); hücre dar gelirse kısalır ya da yukarıdan bakar
const TP_RADIUS := 0.14  # kamera küresi: duvara bu kadar yaklaşmaz
# karakterin önünden sapma (derece); önü duvarsa en sonda arkadan-yandan
const TP_YAWS := [35.0, -35.0, 55.0, -55.0, 15.0, -15.0, 80.0, -80.0, 0.0, 115.0, -115.0, 150.0, -150.0]
const TP_PITCHES := [8.0, 28.0, 50.0]  # göğüs hizasından yukarı açı (derece)

# El pozları, kamera uzayında (x sağ, y yukarı, -z ileri; metre).
# "obj" verilmişse p/f/u o eşyanın çerçevesidir (silahta p silahın kökü, f namlu, u silahın üstü) ve
# avuç buna göre hesaplanır; yoksa doğrudan avucun çerçevesidir (p avuç ortası, f parmak yönü,
# u başparmak yönü). "at": f yerine eşya o noktaya döner. e: dirseğin bakacağı yön,
# c: parmak kıvrımı [başparmak, işaret, orta, yüzük, serçe] 0-1, r: geçiş hızı (büyük = hızlı).
const HAND_POSES := {
	# ahize kulakta: kulaklık kulağa, ağızlık çeneye; el yanağın yanında (birinci şahısta çoğu görünmez)
	"ahize": {"obj": "ahize", "p": Vector3(0.08, -0.07, 0.025), "f": Vector3(1.0, 0.1, -0.25), "u": Vector3(0.15, 0.7, 0.6), "e": Vector3(0.3, -1.0, 0.35), "c": [0.6, 0.8, 0.85, 0.85, 0.85], "r": 7.0},
	# kapıyı itme: avuç öne, parmaklar yukarı
	"itme": {"p": Vector3(0.11, -0.1, -0.44), "f": Vector3(-0.05, 1.0, -0.25), "u": Vector3(-1.0, 0.0, 0.0), "e": Vector3(0.5, -1.0, 0.2), "c": [0.1, 0.1, 0.12, 0.15, 0.18], "r": 16.0},
	# altıpatar elde, namlu ileri-aşağı (ekranın sağ altında)
	"silah": {"obj": "silah", "p": Vector3(0.15, -0.14, -0.5), "f": Vector3(-0.1, -0.2, -1.0), "u": Vector3(0.0, 1.0, 0.0), "e": Vector3(0.35, -1.0, 0.1), "c": [0.95, 0.55, 1.0, 1.0, 1.0], "r": 8.0},
	# kendine: namlu sağ şakağa döner (ekranın sağ kenarında)
	"sakak": {"obj": "silah", "p": Vector3(0.17, -0.09, -0.27), "at": Vector3(0.05, 0.03, 0.02), "u": Vector3(0.0, 1.0, 0.2), "e": Vector3(1.0, -0.3, 0.1), "c": [0.95, 0.55, 1.0, 1.0, 1.0], "r": 6.0},
	# C4 sol elde kitap gibi ucundan tutulur (başparmak üstte), ekranı sana dönük
	"c4": {"obj": "c4", "p": Vector3(-0.02, -0.17, -0.44), "f": Vector3(0.1, 0.4, -1.0), "u": Vector3(0.0, 1.0, 0.4), "e": Vector3(-0.7, -1.0, 0.1), "c": [0.35, 0.6, 0.65, 0.7, 0.75], "r": 8.0},
}

var head: Node3D
var camera: Camera3D
var col: CollisionShape3D
var body: Node3D

var held_handset: Node3D
var move_input := Vector2.ZERO  # ekrandaki joystick'ten gelir
var seated := false
var busy := false
var on_call := false
var bob_t := 0.0
var emote_active := false
var sensitivity := 1.0  # ayarlardan
var sprint := false
var crouched := false
var head_bob := true  # ayarlardan
signal emote_stopped
var _eye := 1.6
var _steps: AudioStreamPlayer
var _step_t := 0.0
var _speed := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _emote_t := 0.0

# üçüncü şahıs kamera (yalnız hareket sırasında çizer; birinci şahıs kamerası yerinde kalır, eller ona göre)
var cam3p: Camera3D
var tap_filter: Callable  # dokunuş bir düğmenin üstündeyse true (main.gd -> hud): o dokunuş kamerayı geri almaz
var _tp_on := false
var _tp := 0.0  # 0 birinci şahıs, 1 üçüncü şahıs
var _tp_dir := Vector3.BACK  # göğüsten kameraya (birim, dünya)
var _tp_dist := TP_DIST
var _tp_hips := Vector3.ZERO  # göğüs noktası, oyuncuya göre (kalça kemiğinden; takla gibi yer değiştiren hareketler)
var _tp_peek := false
var _tp_q: PhysicsShapeQueryParameters3D
var _ear: AudioListener3D  # sesler kamera uzaklaşsa da kafandan duyulsun
var _fill: OmniLight3D

# eller: 0 = sol, 1 = sağ
var _hand_mod: Node  # gövde iskeletindeki AimMod
var _want: Array = [{}, {}]  # istenen poz ({}: animasyon olduğu gibi)
var _cur: Array = [{}, {}]  # şu anki (yumuşatılmış) poz
var _held: Array = [null, null]  # avuçtaki eşyalar
var _held_off: Array = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var _push_t := 0.0
var _line: AudioStreamPlayer  # kulaklıktaki hat sesi
var phone_cell: Node3D  # ahizesi elimizde olan telefonun hücresi
var _phone_step := ""  # "uzan" (ahizeye uzanıyor), "kulak" (konuşuyor), "birak" (çatala koyuyor)
var _phone_t := 0.0
var cord_tension := 0.0  # 0: kablo gevşek, 1: sınırda
signal cord_snapped  # kablo sınırı aşıldı: ahize elden kaydı


func _ready() -> void:
	col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	head = Node3D.new()
	head.position = Vector3(0, EYE_STAND, -0.16)
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.02
	head.add_child(camera)
	camera.current = true

	# kendi gövden gerçek karakter modeli: aşağı bakınca gerçek bacak ve eller, kafa gizli
	body = ModelScript.new()
	body.hide_head = true
	body.position.z = 0.03
	add_child(body)
	for i in 2:
		_cur[i] = {"w": 0.0, "xf": Transform3D.IDENTITY, "e": Vector3.ZERO, "c": [0.0, 0.0, 0.0, 0.0, 0.0]}
	_build_handset()
	# birinci şahıs el ışığı: sadece kendi kolunu, elini ve tuttuğun eşyayı hafifçe aydınlatır (oda etkilenmez)
	var fill := OmniLight3D.new()
	_fill = fill
	fill.light_color = Color(1.0, 0.88, 0.76)
	fill.light_energy = 0.55
	fill.omni_range = 1.1
	fill.omni_attenuation = 1.4
	fill.light_cull_mask = FP_LAYER
	fill.light_specular = 0.3
	fill.position = Vector3(0.05, 0.18, 0.05)
	camera.add_child(fill)
	_fp_layers(held_handset, true)
	cam3p = Camera3D.new()
	cam3p.top_level = true
	cam3p.near = 0.05
	add_child(cam3p)
	_ear = AudioListener3D.new()
	camera.add_child(_ear)
	_tp_q = PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = TP_RADIUS
	_tp_q.shape = ball
	_steps = AudioStreamPlayer.new()
	# gerçek beton ayak sesi kayıtları, her adımda rastgele biri
	var steps := AudioStreamRandomizer.new()
	for i in 5:
		steps.add_stream(-1, load("res://assets/ses/adim_%d.ogg" % i))
	steps.random_pitch = 1.08
	_steps.stream = steps
	_steps.volume_db = -2.0
	add_child(_steps)


# Eğil / kalk: göz hizası ve çarpışma boyu küçülür, karakter çömelir.
func toggle_crouch() -> void:
	if seated or busy:
		return
	crouched = not crouched
	body.crouched = crouched
	_eye = EYE_CROUCH if crouched else EYE_STAND
	var cap: CapsuleShape3D = col.shape
	cap.height = 1.15 if crouched else 1.7
	col.position.y = cap.height / 2.0


func stop_emote() -> void:
	emote_active = false
	body.stop_emote()
	_tp_on = false
	emote_stopped.emit()


func set_look(look: Dictionary) -> void:
	body.set_meta("look", look)  # aynadaki ikiz de aynı görünsün
	body.set_look(look)


# Elde eşya (silah, C4, ahize) var mı: varken hareket yapılmaz.
func hands_full() -> bool:
	for h in _held:
		if h != null and is_instance_valid(h):
			return true
	return held_handset.visible or _phone_step != ""


# Hareket yapılabilir mi (oturmuyor, telefonda değil, eli boş, başka bir işte değil).
func can_emote() -> bool:
	return not (seated or busy or on_call or hands_full())


# Hareket (emote): kamera kısa süre üçüncü şahsa geçer, kendini hareket ederken görürsün; hareket bitince,
# joystick oynayınca ya da ekrana yeniden dokununca birinci şahsa döner. Diğerleri hareketi zaten görür.
# Hareket sürerken yenisi seçilirse onunla değişir.
func play_emote(id: String) -> void:
	if not can_emote():
		return
	body.play_emote(id)
	if str(body.get("emote")) != id:
		return  # bu gövdede böyle bir animasyon yok
	emote_active = true
	_emote_t = 0.0
	_tp_enter()


func _emote_tick(delta: float) -> void:
	if not (emote_active or _tp_on):
		return
	_emote_t += delta
	# gövde, animasyon bitince hareketi kendisi bırakır
	if emote_active and (str(body.get("emote")) == "" or _emote_t > 12.0):
		emote_active = false
	# kısa hareketlerde (el sallama yarım saniye) kamera hemen geri dönmesin: en az TP_MIN kalır
	if _tp_on and not emote_active and _emote_t >= TP_MIN:
		_tp_on = false


# ---------- üçüncü şahıs kamera ----------

func _tp_enter() -> void:
	_tp_on = true
	_tp_pick()
	cam3p.fov = camera.fov
	cam3p.cull_mask = camera.cull_mask
	if _tp <= 0.0:
		cam3p.global_transform = camera.global_transform
	cam3p.current = true
	_ear.make_current()


func third_person() -> bool:
	return _tp > 0.0


# Göğüs hizası: kameranın baktığı ve çarpışma atışlarının çıktığı nokta.
func _tp_pivot() -> Vector3:
	return global_position + _tp_hips


# Kalça kemiğinden göğüs noktası (oyuncuya göre): takla atınca, bayılınca, çömelince kamera da iner, kayar.
func _chest_now() -> Vector3:
	var sk = body.get("_skel")
	if sk is Skeleton3D and is_instance_valid(sk):
		var hb: int = (sk as Skeleton3D).find_bone("mixamorig_Hips")
		if hb >= 0:
			var hp: Vector3 = (sk as Skeleton3D).global_transform * (sk as Skeleton3D).get_bone_global_pose(hb).origin - global_position
			var flat := Vector3(hp.x, 0.0, hp.z).limit_length(2.5)
			return Vector3(flat.x, clampf(hp.y + 0.33, 0.45, 1.35), flat.z)
	return Vector3(0.0, 0.82 if crouched else 1.28, 0.0)


# Göğüsten bir yöne kamera küresi ne kadar gidebilir (duvar, tavan, kapı, eşya).
func _tp_free(from: Vector3, dir: Vector3) -> float:
	var reach := TP_DIST + 0.1
	_tp_q.transform = Transform3D(Basis(), from)
	_tp_q.motion = dir * reach
	_tp_q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.cast_motion(_tp_q)
	return r[0] * reach


# Hareket başında en iyi açıyı seç: önce önden-yandan göğüs hizası; sığmazsa diğer yan, daha yan, yukarıdan.
func _tp_pick() -> void:
	_tp_hips = _chest_now()
	var piv := _tp_pivot()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var best := -INF
	for p in TP_PITCHES:
		for y in TP_YAWS:
			var flat := fwd.rotated(Vector3.UP, deg_to_rad(y))
			var dir := (flat * cos(deg_to_rad(p)) + Vector3.UP * sin(deg_to_rad(p))).normalized()
			var free := minf(_tp_free(piv, dir), TP_DIST)
			var score: float = free - absf(absf(y) - 35.0) * 0.004 - (p - 8.0) * 0.005
			if score > best:
				best = score
				_tp_dir = dir
	_tp_dist = clampf(_tp_free(piv, _tp_dir), 0.45, TP_DIST)


func _tp_process(delta: float) -> void:
	if not _tp_on and _tp <= 0.0:
		return
	_tp = move_toward(_tp, 1.0 if _tp_on else 0.0, delta / TP_TIME)
	var s := smoothstep(0.0, 1.0, _tp)
	# yer değiştiren hareketlerde (takla, bayılma) kamera kalçayı yumuşakça izler
	_tp_hips = _tp_hips.lerp(_chest_now(), minf(1.0, delta * 3.0))
	var piv := _tp_pivot()
	# her karede tek küre atışı (kapı açılır, yanına biri gelir): kamera duvara girmez
	var free := clampf(_tp_free(piv, _tp_dir), 0.45, TP_DIST)
	_tp_dist = free if free < _tp_dist else move_toward(_tp_dist, free, delta * 3.0)
	var pos := piv + _tp_dir * _tp_dist
	var tgt := Basis.looking_at(piv + Vector3(0.0, 0.08, 0.0) - pos, Vector3.UP)
	var fp := camera.global_transform
	var q := fp.basis.get_rotation_quaternion().slerp(tgt.get_rotation_quaternion(), s)
	cam3p.global_transform = Transform3D(Basis(q), fp.origin.lerp(pos, s))
	cam3p.fov = camera.fov
	cam3p.cull_mask = camera.cull_mask
	# kafa, kamera yüzden biraz uzaklaşınca görünür (yüzün içi görünmesin); el ışığı kafayı yakmasın
	var peek := s > 0.2
	if peek != _tp_peek:
		_tp_peek = peek
		body.call("set_head_peek", peek)
	_fill.visible = _tp <= 0.0
	if _tp <= 0.0:
		# birinci şahsa dönüldü
		camera.current = true
		_ear.clear_current()


# Ekrana yeniden dokununca (düğmeler hariç) kamera birinci şahsa döner; hareket sürer.
func _input(event: InputEvent) -> void:
	if not _tp_on:
		return
	var pos := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed:
		pos = event.position
	if pos == Vector2.INF:
		return
	if tap_filter.is_valid() and tap_filter.call(pos):
		return
	_tp_on = false


# Elde tutulan ahize: duvardaki telefonun ahizesiyle aynı model ve boy (sadece konuşurken görünür).
func _build_handset() -> void:
	held_handset = Node3D.new()
	add_child(held_handset)
	var h: Node3D = Telefon.handset(held_handset)
	h.scale = Vector3.ONE * Telefon.SCALE
	# kablonun ucu ahizenin içindeki düğüm; dışarıdan kolay bulunsun diye üst düğüme taşınır
	var end: Node3D = h.get_node("kablo_ucu")
	end.reparent(held_handset)
	held_handset.visible = false
	_line = AudioStreamPlayer.new()
	_line.volume_db = -10.0
	add_child(_line)


# ---------- eller ----------

# Gövde iskeletindeki el pozlayıcısı (gövde yeniden giydirilince yeni iskelete yeniden takılır).
func hand_mod() -> Node:
	var sk = body.get("_skel")
	if not (sk is Skeleton3D) or not is_instance_valid(sk) or (sk as Node).is_queued_for_deletion():
		return null
	if not is_instance_valid(_hand_mod) or _hand_mod.get_parent() != sk:
		_hand_mod = AimMod.new()
		(sk as Node).add_child(_hand_mod)
		# gövde yeniden kuruldu: birinci şahıs katmanına al (ayna görmez, el ışığı aydınlatır)
		_fp_layers(body, false)
	return _hand_mod


# Bir elin pozu: HAND_POSES'tan ad, ya da aynı anahtarlarla sözlük ("aim_at": dünya noktası da olur).
# "" / {} verilirse el animasyona (doğal duruşa) döner.
func set_hand_pose(side: int, pose) -> void:
	if pose is String:
		_want[side] = HAND_POSES.get(pose, {})
	else:
		_want[side] = pose


func hand_pose(side: int) -> Dictionary:
	return _want[side]


# Eşyayı avuca bağlar (offset avuç çerçevesine göre); null bırakır. Eşya oyuncunun çocuğu olur.
func hold_item(side: int, node: Node3D, offset := Transform3D.IDENTITY) -> void:
	if node and (emote_active or _tp_on):
		stop_emote()  # eline bir şey verildi (silah, C4): hareket biter
	_held[side] = node
	_held_off[side] = offset
	if node and node.get_parent() == null:
		add_child(node)
	if node:
		_fp_layers(node, true)


# Avucun dünya çerçevesi (-Z parmaklar, +Y başparmak).
func hand_frame(side: int) -> Transform3D:
	var m := hand_mod()
	return m.frame(side) if m else camera.global_transform


func _process(delta: float) -> void:
	_emote_tick(delta)
	_tp_process(delta)
	var m := hand_mod()
	if not m:
		return
	if _tp <= 0.0:
		_align_body(delta)  # üçüncü şahısta gövde kafaya göre çekilmez (hareket olduğu gibi görünsün)
	if _push_t > 0.0:
		_push_t -= delta
		if _push_t <= 0.0 and _want[1] == HAND_POSES.itme:
			_want[1] = HAND_POSES.ahize if on_call else {}
	_phone_process(delta)
	var cam := camera.global_transform
	var inv := cam.affine_inverse()
	for side in 2:
		var want: Dictionary = _want[side]
		if emote_active:
			want = {}
		var cur: Dictionary = _cur[side]
		var k := 1.0 - exp(-delta * float(want.get("r", 7.0)))
		if not want.is_empty():
			var p: Vector3 = want.get("p", Vector3(0.15, -0.2, -0.35))
			var f: Vector3 = want.get("f", Vector3.FORWARD)
			if want.has("wxf"):
				# dünyadaki bir eşya duruşu (ör. çataldaki ahize): her karede kamera uzayına çevrilir
				var ox: Transform3D = inv * (want.wxf as Transform3D).orthonormalized()
				p = ox.origin
				f = -ox.basis.z
				want = want.duplicate()
				want.u = ox.basis.y
			elif want.has("aim_at"):
				# hedefe nişan: kol hedef yönüne uzanır, namlu hedefe bakar
				var t: Vector3 = inv * (want.aim_at as Vector3)
				var base := Vector3(0.13, -0.15, 0.0)
				var dir := (t - base).normalized()
				p = base + dir * float(want.get("reach", 0.4))
				f = t - p
			elif want.has("at"):
				f = (want.at as Vector3) - p
			# yürürken hafif sallanma, dururken nefes
			p += Vector3(sin(bob_t * 0.5) * 0.01, absf(cos(bob_t * 0.5)) * 0.012, 0) * _speed
			p.y += sin(Time.get_ticks_msec() * 0.0021) * 0.003
			var want_b := AimMod._basis(f, want.get("u", Vector3.UP))
			if float(cur.w) < 0.02:
				cur.xf = Transform3D(want_b, p)
				cur.e = want.get("e", Vector3.ZERO)
			var obj := str(want.get("obj", ""))
			if obj != str(cur.get("obj", "")):
				# eşya değişti: şu anki avuç çerçevesini yeni eşyanın çerçevesine çevir (sıçramasın)
				var hand_xf: Transform3D = cur.xf
				if str(cur.get("obj", "")) != "":
					hand_xf = AimMod.hand_for_item(hand_xf, cur.obj, side)
				cur.xf = hand_xf * AimMod.item_offset(obj, side) if obj != "" else hand_xf
				cur.obj = obj
			var cq: Quaternion = (cur.xf as Transform3D).basis.get_rotation_quaternion()
			cur.xf = Transform3D(Basis(cq.slerp(want_b.get_rotation_quaternion(), k)), (cur.xf as Transform3D).origin.lerp(p, k))
			cur.e = (cur.e as Vector3).lerp(want.get("e", Vector3.ZERO), k)
			var wc: Array = want.get("c", [0.0, 0.0, 0.0, 0.0, 0.0])
			for i in 5:
				cur.c[i] = lerpf(cur.c[i], wc[i], k)
		cur.w = lerpf(cur.w, 0.0 if want.is_empty() else 1.0, k)
		if want.is_empty() and float(cur.w) < 0.01:
			cur.w = 0.0
		var xf: Transform3D = cur.xf
		if str(cur.get("obj", "")) != "":
			xf = AimMod.hand_for_item(xf, cur.obj, side)
		m.set_hand(side, cur.w, cam * xf.origin, cam.basis * -xf.basis.z, cam.basis * xf.basis.y, cam.basis * (cur.e as Vector3), cur.c)
		var h = _held[side]
		if h != null and not is_instance_valid(h):
			_held[side] = null
		m.hold(side, _held[side], _held_off[side])
	# ahize her zaman sağ avuçta (görünürken)
	if held_handset.visible and _held[1] == null:
		m.hold(1, held_handset, AimMod.item_offset("ahize", 1))


func look(delta_px: Vector2, sens := 0.005) -> void:
	if busy or emote_active or _tp_on:
		return
	sens *= sensitivity
	rotate_y(-delta_px.x * sens)
	head.rotation.x = clampf(head.rotation.x - delta_px.y * sens, deg_to_rad(-80.0), deg_to_rad(75.0))


func _physics_process(delta: float) -> void:
	body.seated = seated
	if (emote_active or _tp_on) and (move_input.length() > 0.15 or Input.get_vector("sol", "sag", "ileri", "geri").length() > 0.1):
		if emote_active:
			stop_emote()
		_tp_on = false
	if seated or busy or emote_active:
		velocity = Vector3.ZERO
		body.walk = 0.0
		_speed = 0.0
		return
	var dir2 := move_input
	var keys := Input.get_vector("sol", "sag", "ileri", "geri")
	if keys.length() > 0.0:
		dir2 = keys
	# KOŞ halkası (ya da Shift) hızlı koşturur, eğilince yavaşlar
	var run := RUN_MULT if (sprint or Input.is_action_pressed("kos")) and not crouched else 1.0
	if crouched:
		run = 0.5
	var dir := transform.basis * Vector3(dir2.x, 0.0, dir2.y)
	velocity.x = dir.x * SPEED * run
	velocity.z = dir.z * SPEED * run
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	_leash(delta)
	move_and_slide()
	var speed := Vector2(velocity.x, velocity.z).length() / SPEED
	body.walk = speed
	_speed = minf(speed, 1.5)
	# yürürken hafif kafa sallanması
	if speed > 0.1:
		# ayak sesi: koşarken daha sık
		_step_t -= delta * speed
		if _step_t <= 0.0 and is_on_floor():
			_step_t = 0.52
			_steps.play()
		bob_t += delta * 9.0
		head.position.y = _eye + sin(bob_t) * (0.025 if head_bob else 0.0)
	else:
		head.position.y = lerpf(head.position.y, _eye, delta * 8.0)


# ---------- telefon ----------
# Ahizeyi al: gerekirse telefonun önüne adım atar, sağ el çataldaki ahizeye uzanır, kavrar, kulağa götürür.
func lift_handset(cell: Node3D) -> void:
	if phone_cell == cell and on_call:
		return
	if emote_active or _tp_on:
		stop_emote()
	phone_cell = cell
	on_call = true
	_phone_step = "uzan"
	_phone_t = 0.0
	held_handset.visible = false
	var rest: Transform3D = cell.handset_rest_world()
	# telefonun önünde dur (sağ el telefona yakın)
	var f: Vector3 = rest.origin - global_position
	f.y = 0.0
	var wall_n: Vector3 = -(cell.global_transform.basis.x)  # telefon sağ duvarda, odaya bakar
	var spot: Vector3 = rest.origin + wall_n * 0.56 + wall_n.cross(Vector3.UP) * 0.27
	spot.y = global_position.y
	var face := -wall_n
	var yaw := atan2(-face.x, -face.z)
	if not seated and (global_position.distance_to(spot) > 0.3 or absf(wrapf(yaw - rotation.y, -PI, PI)) > 0.5):
		busy = true
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(self, "global_position", spot, 0.32)
		tw.tween_property(self, "rotation:y", _turn_to(yaw), 0.32)
		tw.tween_property(head, "rotation:x", deg_to_rad(-12.0), 0.32)
		_phone_t = -0.3  # adım bitince uzanmaya başlar
	set_hand_pose(1, {"obj": "ahize", "wxf": rest, "e": Vector3(0.8, -1.0, 0.3), "c": [0.25, 0.3, 0.3, 0.3, 0.3], "r": 11.0})


# Ahizeyi bırak: yakınsa el ahizeyi çatala geri koyar; uzaksa ya da kablo çektiyse ahize elden kayıp çatala çarpar.
func hang_up_handset(slip := false) -> void:
	if not on_call:
		return
	on_call = false
	line_tone("")
	var cell: Node3D = phone_cell
	if not is_instance_valid(cell):
		held_handset.visible = false
		set_hand_pose(1, "")
		_phone_step = ""
		return
	var rest: Transform3D = cell.handset_rest_world()
	if _phone_step == "uzan":
		# henüz kavramadan vazgeçti: el geri iner
		_phone_step = ""
		busy = false
		set_hand_pose(1, "")
		return
	var near := global_position.distance_to(Vector3(rest.origin.x, global_position.y, rest.origin.z)) < 1.0
	if slip or not near or seated:
		cell.slip_handset(held_handset.global_transform)
		held_handset.visible = false
		set_hand_pose(1, "")
		_phone_step = ""
		return
	_phone_step = "birak"
	_phone_t = 0.0
	set_hand_pose(1, {"obj": "ahize", "wxf": rest, "e": Vector3(0.8, -1.0, 0.3), "c": [0.6, 0.8, 0.85, 0.85, 0.85], "r": 10.0})


# Eski ad: telefon sahnesi testleri ve basit çağrılar için.
func set_call(active: bool, cell: Node3D = null) -> void:
	if active and cell:
		lift_handset(cell)
	elif not active:
		hang_up_handset()


# Kulaklıktan gelen hat sesi: "cevir_sesi", "calma_sesi", "mesgul" ya da "" (sus).
func line_tone(id: String) -> void:
	if id == "":
		_line.stop()
		return
	_line.stream = Telefon.sound(id)
	_line.play()


func _phone_process(delta: float) -> void:
	if _phone_step == "":
		return
	_phone_t += delta
	match _phone_step:
		"uzan":
			if _phone_t >= 0.0:
				busy = false
			if _phone_t > 0.34:
				# kavradı: ahize çataldan kalkar, kablo eldeki ahizeye bağlanır, kulağa gider
				_phone_step = "kulak"
				held_handset.visible = true
				var m := hand_mod()
				if m:
					held_handset.global_transform = m.frame(1) * AimMod.item_offset("ahize", 1)
				if is_instance_valid(phone_cell):
					phone_cell.set_handset_lifted(true, held_handset)
				set_hand_pose(1, "ahize")
				# ahizeyi alınca telefondan yarım adım geri çekil (telefon ekranı kaplamasın)
				if not seated and is_instance_valid(phone_cell):
					var wall_n: Vector3 = -(phone_cell.global_transform.basis.x)
					create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(self, "global_position", global_position + wall_n * 0.32, 0.55)
		"birak":
			if _phone_t > 0.36:
				_phone_step = ""
				held_handset.visible = false
				if is_instance_valid(phone_cell):
					phone_cell.set_handset_lifted(false)
				set_hand_pose(1, "")


# Kablo tasması: konuşurken telefondan uzaklaştıkça yürüyüş zorlaşır; sınırı aşınca cord_snapped.
func _leash(delta: float) -> void:
	cord_tension = 0.0
	if not on_call or not is_instance_valid(phone_cell) or _phone_step == "uzan":
		return
	var c: Vector3 = phone_cell.handset_rest_world().origin
	var off := global_position + velocity * delta - c
	off.y = 0.0
	var d := off.length()
	if d <= LEASH_SOFT:
		return
	cord_tension = clampf((d - LEASH_SOFT) / (LEASH_HARD - LEASH_SOFT), 0.0, 1.0)
	var radial := off / d
	var out := velocity.x * radial.x + velocity.z * radial.z
	if out > 0.0:
		var keep := clampf(1.0 - cord_tension, 0.12, 1.0)
		velocity.x -= radial.x * out * (1.0 - keep)
		velocity.z -= radial.z * out * (1.0 - keep)
	if d > LEASH_HARD:
		cord_snapped.emit()


# Kapıyı iterken sağ el ileri uzanır (avuç kapıya).
func push() -> void:
	if on_call or _held[1] != null:
		return
	set_hand_pose(1, "itme")
	_push_t = 0.42


func _turn_to(yaw: float) -> float:
	return rotation.y + wrapf(yaw - rotation.y, -PI, PI)


func sit(seat: Vector3, yaw: float) -> void:
	if emote_active or _tp_on:
		stop_emote()
	seated = true
	busy = true
	col.disabled = true
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "global_position", seat, 0.7)
	tw.tween_property(self, "rotation:y", _turn_to(yaw), 0.7)
	tw.tween_property(head, "position:y", EYE_SEAT, 0.7)
	tw.tween_property(head, "rotation:x", deg_to_rad(-4.0), 0.7)
	tw.chain().tween_callback(_sat)


func _sat() -> void:
	busy = false


func stand(to: Vector3) -> void:
	busy = true
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "global_position", to, 0.6)
	tw.tween_property(head, "position:y", EYE_STAND, 0.6)
	tw.chain().tween_callback(_stood)


func _stood() -> void:
	col.disabled = false
	seated = false
	busy = false


# Gövde kameraya göre hizalanır: kafa kemiği hep kameranın biraz arkasında (göz hizasında) kalır.
# Böylece ayakta, otururken ya da çömelirken kamera gövdenin içine girmez, kollar doğru yerden çıkar.
func _align_body(delta: float) -> void:
	var sk = body.get("_skel")
	if not (sk is Skeleton3D) or not is_instance_valid(sk):
		return
	var hb: int = (sk as Skeleton3D).find_bone("mixamorig_Head")
	if hb < 0:
		return
	var hp: Vector3 = to_local((sk as Skeleton3D).global_transform * (sk as Skeleton3D).get_bone_global_pose(hb).origin)
	var want := Vector3(0.0, 0.0, head.position.z + EYE_BEHIND)
	var k := minf(1.0, delta * 12.0)
	body.position.x = clampf(body.position.x + (want.x - hp.x) * k, -0.2, 0.2)
	body.position.z = clampf(body.position.z + (want.z - hp.z) * k, -0.3, 0.3)
	# otururken/çömelirken göz, modelin gerçek göz hizasına çıkar (kamera boynun içinde kalmasın)
	var lift := 0.0
	if seated or crouched:
		lift = clampf(hp.y + 0.075 - head.position.y, 0.0, 0.3)
	camera.position.y = lerpf(camera.position.y, lift, minf(1.0, delta * 6.0))


# Birinci şahıs katmanı: gövde sadece bu katmanda (ayna görmez); eldeki eşyalar dünyada da görünür (aynada ikizin elinde).
func _fp_layers(n: Node, world_too: bool) -> void:
	if n is VisualInstance3D and not (n is Light3D) and not (n is Decal):
		var v := n as VisualInstance3D
		v.layers = (v.layers | FP_LAYER) if world_too else ((v.layers | FP_LAYER) & ~1)
	for c in n.get_children():
		_fp_layers(c, world_too)
