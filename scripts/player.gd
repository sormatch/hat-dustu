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
const Titresim := preload("res://scripts/titresim.gd")

const SPEED := 2.4
const EYE_STAND := 1.6
const EYE_SEAT := 1.05
const RUN_MULT := 1.9
const EYE_CROUCH := 1.05
const EYE_BEHIND := 0.11  # gövdenin kafa kemiği kameranın bu kadar arkasında durur (göz hizası)
const FP_LAYER := 1 << 16  # birinci şahıs gövdesi (mirror.gd ile aynı): ayna kamerası görmez
const LEASH_SOFT := 1.7  # kablo bu mesafeden sonra gerilmeye başlar (m)
const LEASH_HARD := 2.5  # bunu aşınca ahize elden kayar
# ---- kontrol hissi ----
# Joystick (hud.gd 0-1 arası verir; kendi ölü bölgesi var): bundan küçük itme yok sayılır, gerisi 0-1'e yayılır.
const OLU_BOLGE := 0.06
# Yürüme kademeleri: YAVAS_ESIK'ten az itince yavaş yürüyüş (sessiz, temkinli), fazlası tam yürüyüş.
# Arada kısa bir geçiş bandı var (TAM_ESIK); koşma joystick'in üstündeki KOŞ halkasıyla (sprint).
const YAVAS_ESIK := 0.55
const TAM_ESIK := 0.72
const YAVAS_HIZ := 0.45  # yavaş yürüyüş, tam yürüyüşün bu kadarı
const IVME := 9.0  # hızlanma (1/sn): ~0,25 sn'de tam hıza
const FREN := 18.0  # durma (1/sn): parmağı kaldırınca ~0,2 sn içinde durur, ~12 cm kayar (buzda gibi değil)
# Bakış: dokunma olayları kareye düzensiz gelir; çok kısa yumuşatma (sn) titremeyi alır, gecikme hissettirmez.
const BAKIS_YUMUSAK := 0.016
const PITCH_MIN := -76.0  # aşağı bakış sınırı (derece)
const PITCH_MAX := 75.0
# Aşağı bakınca kendi gövden biraz geri kayar: kamera yakanın/boynun içine değil göğsüne, bacaklarına bakar.
const ASAGI_GERI := 0.2  # en fazla (m), PITCH_MIN'de
const ASAGI_BASLA := -30.0  # bu açıdan sonra kaymaya başlar (derece)
# Kafa sallanması (adım başına bir iniş-çıkış, iki adımda bir yana salınım), metre.
const BOB_DIKEY := 0.018
const BOB_YAN := 0.011
const GOZ_HIZI := 9.0  # eğilip kalkarken göz yüksekliği geçişi (1/sn)
# Hareket (emote) birinci şahısta oynar: kamera göz hizasında kalır, kafa kemiğini yalnızca hafifçe izler
# (baş dönüşünün küçük bir kısmı, birkaç derece; yana yatma yok). Diğer oyuncular ve ayna hareketi tam gövdeyle görür.
# Yuvarlanan, yere düşen, çömelen, kolunu yüzüne getiren hareketlerde kendi gövden birinci şahısta baştan
# gizlenir (kamera kafanın, boynun, gövdenin içine girmesin; dev kol olmasın). Listede olmayan bir harekette
# el kameraya çok yaklaşır ya da baş çok inerse gövde o anda gizlenir (yedek güvence).
const EMOTE_HIDE_BODY := ["takla", "bayil", "kalk", "ninja", "tamir", "comel", "sandik", "super", "isaret", "dans", "tuh",
	"telefon", "agla", "firlat", "zombi", "kasin", "odun", "it", "gozcu"]
const EMOTE_TURN := 0.3  # baş dönüşünün kameraya geçen oranı
const EMOTE_TURN_MAX := 6.0  # kamera başla en fazla bu kadar döner (derece)
const EMOTE_DROP := 0.4  # baş inip kalkınca kamera bunun kadarıyla izler
const EMOTE_DROP_MAX := 0.1  # en fazla (m)
const EMOTE_DIP := 0.2  # baş başlangıçtakinden bu kadar inerse gövde gizlenir (derin eğilme, çökme)
const ARM_NEAR := 0.24  # el ya da ön kol kameraya bundan yakın ve önündeyse gövde gizlenir (m)
# Hareket sırasında boyun, yaka, göğüs ve omuzlar kameranın en az bu kadar arkasında kalır (m): baş geriye
# yatınca ya da gövde öne eğilince kamera boynun, yakanın içini görmesin; gövde gerekirse geriye kayar.
# Değerler, normal birinci şahıs duruşundaki uzaklıklar (ayakta dururken gövde hiç kaymaz).
const EMOTE_CLEAR := {"mixamorig_Neck": 0.13, "mixamorig_Spine2": 0.07, "mixamorig_LeftShoulder": 0.06,
	"mixamorig_RightShoulder": 0.06, "mixamorig_LeftArm": 0.02, "mixamorig_RightArm": 0.02}
# Kolu kameraya doğru uzanan hareketlerde gövde baştan bu kadar geri durur (m): yumruk, işaret ekranın
# altında normal boyda görünür, kameraya yapışmaz.
const EMOTE_SHIFT := {"boks": 0.12, "yumruk": 0.12, "selamla": 0.2, "kiz": 0.25}
const EMOTE_SHOW_DELAY := 0.4  # hareket bitince gizlenen gövde, yürüyüşe geçiş bitince görünür (sn)

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
	# kendine: namlu sağ şakakta (kameranın yanında, biraz arkasında). El göz hizasında sağ kenarda, namlu
	# ekranın sağ kenarından çaprazlama girer; silah ekranın önünü kaplamaz (eskiden 27 cm önde, kocamandı)
	"sakak": {"obj": "silah", "p": Vector3(0.228, -0.035, -0.195), "at": Vector3(0.075, -0.03, 0.018), "u": Vector3(0.0, 1.0, 0.2), "e": Vector3(1.0, -0.3, 0.3), "c": [0.95, 0.55, 1.0, 1.0, 1.0], "r": 6.0},
	# C4 sol avucun üstünde (avuç altta, parmaklar uzak kenarı kavrar), ekranın sol altında, sayacı sana dönük
	"c4": {"obj": "c4", "p": Vector3(-0.1, -0.165, -0.38), "f": Vector3(0.12, 0.6, -1.0), "u": Vector3(0.0, 1.0, 0.6), "e": Vector3(-0.7, -1.0, 0.2), "c": [0.25, 0.7, 0.75, 0.8, 0.85], "r": 8.0},
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
var alcak_tavan := false  # tünel gibi alçak yerde ayağa kalkılmaz (Büyük Kaçış)
var head_bob := true  # ayarlardan
signal emote_stopped
var _eye := 1.6
var _steps: AudioStreamPlayer
var _step_t := 0.0
var _speed := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _emote_t := 0.0

# birinci şahıs hareketi
var _em_hide := false  # kendi gövden (birinci şahısta) geçici gizli
var _em_show_t := 0.0
var _em_ref := Quaternion.IDENTITY  # hareket başında kafa kemiğinin dönüşü (oyuncuya göre)
var _em_ref_y := 0.0  # ... ve yüksekliği
var _em_ref_ok := false
var _em_drop := 0.0  # kameranın başla birlikte inişi (m)
var _em_back := 0.0  # hareket sırasında gövdenin fazladan geri kayması (m)
var _em_shift := 0.0  # bu harekette gövdenin en az geri kayması (EMOTE_SHIFT)

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

# kontrol hissi
var _yatay := Vector3.ZERO  # yumuşatılmış yürüme hızı (dünya, yatay); çarpışma bunu değiştirmez (duvarda takılmaz)
var _bakis := Vector2.ZERO  # henüz uygulanmamış bakış (radyan): x sağa dönüş, y yukarı
var _eye_s := 1.6  # göz yüksekliği (eğilip kalkarken yumuşak geçer)
var _bob_g := 0.0  # kafa sallanmasının şu anki gücü (0-1; durunca yavaşça söner)
var _asagi_geri := 0.0  # aşağı bakınca gövdenin geri kayması (m)
var _sars_guc := 0.0  # kamera sarsıntısı (m)
var _sars_sure := 0.0
var _sars_t := 0.0  # kalan süre
var _sars_faz := 0.0
var _otur_gec := false  # koltuğa doğru giderken gövde henüz oturma pozuna geçmez (havada oturmasın)
var _kalk := false  # koltuktan kalkıyor (gövde ayağa kalkma pozunda, kamera yükseliyor)
var _tweenler: Array = []  # oturma / kalkma / telefona adım geçişleri (sıfırlanınca durdurulur)
var _konum_id := 0  # son konum geçişinin numarası (eskisi ya da ışınlanmadan sonrası konuma dokunmaz)
var _konum_son := Vector3.INF  # geçişin en son yazdığı konum (başka yerden değiştiyse: ışınlandı)


func _ready() -> void:
	col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	# duvara sürtünerek yürürken takılma olmasın: neredeyse dik itişte de kayar, kutu birleşimlerine takılmaz
	wall_min_slide_angle = deg_to_rad(4.0)
	safe_margin = 0.01
	floor_snap_length = 0.2  # eşikten inerken havada kalıp sekmesin
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
	fill.light_color = Color(1.0, 0.88, 0.76)
	fill.light_energy = 0.55
	fill.omni_range = 1.1
	fill.omni_attenuation = 1.4
	fill.light_cull_mask = FP_LAYER
	fill.light_specular = 0.3
	fill.position = Vector3(0.05, 0.18, 0.05)
	camera.add_child(fill)
	_fp_layers(held_handset, true)
	_steps = AudioStreamPlayer.new()
	# gerçek beton ayak sesi kayıtları (6 yürüme + 6 koşma), her adımda rastgele biri (sfx.gd adim_cal)
	_steps.stream = Sfx.adim_sesi(false)
	_steps.max_polyphony = 2
	add_child(_steps)


# Eğil / kalk: göz hizası ve çarpışma boyu küçülür, karakter çömelir.
func toggle_crouch() -> void:
	if seated or busy or (crouched and alcak_tavan):
		return
	crouched = not crouched
	body.crouched = crouched
	_eye = EYE_CROUCH if crouched else EYE_STAND
	var cap: CapsuleShape3D = col.shape
	cap.height = 1.15 if crouched else 1.7
	col.position.y = cap.height / 2.0


# Maçtan bekleme salonuna dönüş: oturma, çömelme, hareket, el pozları önceki maçtan kalmasın.
func reset_state() -> void:
	_gecisleri_kes()
	if emote_active:
		stop_emote()
	seated = false
	busy = false
	col.disabled = false
	if crouched:
		toggle_crouch()
	_eye = EYE_STAND
	_eye_s = EYE_STAND
	head.position.y = EYE_STAND
	head.position.x = 0.0
	head.rotation = Vector3.ZERO
	_yatay = Vector3.ZERO
	_bakis = Vector2.ZERO
	_sars_t = 0.0
	_otur_gec = false
	_kalk = false
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	for side in 2:
		set_hand_pose(side, "")
		if _held[side] != null and not is_instance_valid(_held[side]):
			_held[side] = null


# Süren oturma / kalkma / adım geçişleri durur (oyuncuyu eski yerine sürüklemesin).
func _gecisleri_kes() -> void:
	for tw in _tweenler:
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
	_tweenler.clear()
	_konum_id += 1
	_konum_son = Vector3.INF


func _gecis(tw: Tween) -> Tween:
	_tweenler = _tweenler.filter(func(t) -> bool: return t is Tween and (t as Tween).is_valid())
	_tweenler.append(tw)
	return tw


# Konum geçişi: global_position yerine adım adım yazılır; arada biri oyuncuyu ışınladıysa (maç başı, salona
# dönüş, oyun pozu) geçiş konuma artık dokunmaz (diğer parçaları ve geri çağrıları sürer).
func _konum_gecis(tw: Tween, to: Vector3, t: float) -> MethodTweener:
	_konum_id += 1
	var from := global_position
	_konum_son = from
	return tw.tween_method(_konum_adim.bind(from, to, _konum_id), 0.0, 1.0, t)


func _konum_adim(k: float, from: Vector3, to: Vector3, id: int) -> void:
	if id != _konum_id:
		return
	if _konum_son != Vector3.INF and global_position.distance_to(_konum_son) > 0.6:
		_konum_id += 1  # ışınlandı
		return
	global_position = from.lerp(to, k)
	_konum_son = global_position


func stop_emote() -> void:
	emote_active = false
	body.stop_emote()
	_em_show_t = EMOTE_SHOW_DELAY
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


# Hareket (emote) birinci şahısta oynar; bitince ya da joystick oynayınca biter (gövde yürüyüşe yumuşakça geçer).
# Diğerleri hareketi tam gövdeyle görür. Hareket sürerken yenisi seçilirse onunla değişir.
func play_emote(id: String) -> void:
	if not can_emote():
		return
	if crouched:
		toggle_crouch()  # hareket ayakta oynar (çömelik göz hizasında kamera göğsün içinde kalırdı)
	body.play_emote(id)
	if str(body.get("emote")) != id:
		return  # bu gövdede böyle bir animasyon yok
	emote_active = true
	_emote_t = 0.0
	_em_ref_ok = false
	_em_show_t = 0.0
	_em_shift = float(EMOTE_SHIFT.get(id, 0.0))
	_set_em_hide(id in EMOTE_HIDE_BODY)


func _emote_tick(delta: float) -> void:
	if emote_active:
		_emote_t += delta
		# gövde, animasyon bitince hareketi kendisi bırakır
		if str(body.get("emote")) == "" or _emote_t > 12.0:
			emote_active = false
			_em_show_t = EMOTE_SHOW_DELAY
	elif _em_hide:
		_em_show_t -= delta
		if _em_show_t <= 0.0:
			_set_em_hide(false)


func _set_em_hide(on: bool) -> void:
	_em_hide = on
	if body.has_method("set_fp_hide"):
		body.call("set_fp_hide", on)


# Birinci şahıs hareket görünüşü: kamera baş kemiğini hafifçe izler (dönüşün küçük bir kısmı, biraz iniş).
# Gövde gizliyken (takla, bayılma) kamera göz hizasında sabit kalır.
func _emote_view(delta: float, sk: Skeleton3D) -> void:
	var turn := Vector3.ZERO
	var drop := 0.0
	if emote_active and not _em_hide:
		var hb := sk.find_bone("mixamorig_Head")
		if hb >= 0:
			var g: Transform3D = global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(hb)
			var q := g.basis.get_rotation_quaternion()
			if not _em_ref_ok:
				_em_ref_ok = true
				_em_ref = q
				_em_ref_y = g.origin.y
			var rel := (q * _em_ref.inverse()).get_euler()
			var lim := deg_to_rad(EMOTE_TURN_MAX)
			turn = Vector3(clampf(rel.x * EMOTE_TURN, -lim, lim), clampf(rel.y * EMOTE_TURN, -lim, lim), 0.0)
			var dy := g.origin.y - _em_ref_y
			drop = clampf(dy * EMOTE_DROP, -EMOTE_DROP_MAX, EMOTE_DROP_MAX * 0.5)
			if dy < -EMOTE_DIP:
				_set_em_hide(true)  # çok eğildi/çöktü
		if not _em_hide:
			_clear_guard(delta, sk)
			if _arm_close(sk):
				_set_em_hide(true)
	else:
		_em_back = move_toward(_em_back, 0.0, delta * 0.8)
	var k := 1.0 - exp(-delta * 5.0)
	camera.rotation = camera.rotation.lerp(turn, k)
	_em_drop = lerpf(_em_drop, drop, k)


# El, parmak ya da ön kol kameranın hemen önünde mi (ekranı kaplayan dev kol).
func _arm_close(sk: Skeleton3D) -> bool:
	var inv := camera.global_transform.affine_inverse() * sk.global_transform
	for pre in ["mixamorig_Left", "mixamorig_Right"]:
		var prev := Vector3.INF
		for bn in ["ForeArm", "Hand", "HandMiddle1"]:
			var b := sk.find_bone(pre + bn)
			if b < 0:
				continue
			var p: Vector3 = inv * sk.get_bone_global_pose(b).origin
			if _arm_near(p) or (prev != Vector3.INF and _arm_near((p + prev) * 0.5)):
				return true
			prev = p
	return false


# Kamera uzayındaki nokta yakın ve görüşte mi (yanında ya da arkasında kalan dirsek sayılmaz).
func _arm_near(p: Vector3) -> bool:
	return p.length() < ARM_NEAR and camera.is_position_in_frustum(camera.global_transform * p)


# Boyun, yaka, göğüs, omuz kameranın önüne geçmesin: eksik kalan kadar gövde geri kayar, fazlası yavaşça geri alınır.
func _clear_guard(delta: float, sk: Skeleton3D) -> void:
	var inv := camera.global_transform.affine_inverse() * sk.global_transform
	var need := -INF
	for bn in EMOTE_CLEAR:
		var b := sk.find_bone(bn)
		if b >= 0:
			need = maxf(need, float(EMOTE_CLEAR[bn]) - (inv * sk.get_bone_global_pose(b).origin).z)
	if need == -INF:
		return
	if need > 0.0:
		_em_back = minf(_em_back + need * minf(1.0, delta * 14.0), 0.5)
	else:
		_em_back = maxf(_em_back + maxf(need, -delta * 0.3), 0.0)
	if _em_back < _em_shift:
		_em_back = move_toward(_em_back, _em_shift, delta * 1.5)




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
	if node and emote_active:
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
	_bakis_uygula(delta)
	_kamera_his(delta)
	var m := hand_mod()
	if not m:
		return
	_align_body(delta)
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
			var u: Vector3 = want.get("u", Vector3.UP)
			if want.has("wxf"):
				# dünyadaki bir eşya duruşu (ör. çataldaki ahize): her karede kamera uzayına çevrilir
				var ox: Transform3D = inv * (want.wxf as Transform3D).orthonormalized()
				p = ox.origin
				f = -ox.basis.z
				u = ox.basis.y  # (eskiden her karede sözlük kopyalanıyordu)
			elif want.has("aim_at"):
				# hedefe nişan: kol hedef yönüne uzanır, namlu hedefe bakar
				var t: Vector3 = inv * (want.aim_at as Vector3)
				var base := Vector3(0.13, -0.15, 0.0)
				var dir := (t - base).normalized()
				p = base + dir * float(want.get("reach", 0.4))
				# el (ve silah) ekranın sağ alt çeyreğinde kalır, ön kol kameraya yaklaşmaz: yakındaki ya da
				# yandaki birine nişan alınca kol ekranın ortasına uzanıp sağ alt köşeyi kaplıyordu
				p.x = clampf(p.x, 0.12, 0.24)
				p.y = clampf(p.y, -0.24, -0.1)
				p.z = minf(p.z, -0.4)
				f = t - p
			elif want.has("at"):
				f = (want.at as Vector3) - p
			# yürürken hafif sallanma, dururken nefes
			p += Vector3(sin(bob_t * 0.5) * 0.01, absf(cos(bob_t * 0.5)) * 0.012, 0) * _speed
			p.y += sin(Time.get_ticks_msec() * 0.0021) * 0.003
			var want_b := AimMod._basis(f, u)
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


# Ekranda parmakla bakış (hud.gd sürükleme olaylarını piksel olarak verir). Dönüş hemen uygulanmaz,
# biriktirilir ve _process'te çok kısa yumuşatmayla işlenir (_bakis_uygula): düzensiz gelen dokunma
# olayları titreme yapmaz. Hassasiyet: ayarlardaki "hassasiyet" (sensitivity, main.gd apply_settings).
func look(delta_px: Vector2, sens := 0.005) -> void:
	if busy or emote_active:
		return
	var a := delta_px * (sens * sensitivity)
	_bakis.x += a.x
	# eğim sınırının ötesine biriken bakış, geri dönüşü yutmasın
	_bakis.y = clampf(_bakis.y + a.y, head.rotation.x - deg_to_rad(PITCH_MAX), head.rotation.x - deg_to_rad(PITCH_MIN))


func _bakis_uygula(delta: float) -> void:
	if _bakis == Vector2.ZERO:
		return
	if busy or emote_active:
		_bakis = Vector2.ZERO
		return
	var a := _bakis
	if absf(a.x) + absf(a.y) > 0.0004:
		a *= 1.0 - exp(-delta / BAKIS_YUMUSAK)
	_bakis -= a
	rotate_y(-a.x)
	head.rotation.x = clampf(head.rotation.x - a.y, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))


# Joystick değeri (0-1) -> yürüme: ölü bölge, yavaş yürüyüş kademesi, tam yürüyüş (kısa geçişle).
func _joystick(v: Vector2) -> Vector2:
	var m := v.length()
	if m <= OLU_BOLGE:
		return Vector2.ZERO
	var y := minf(1.0, (m - OLU_BOLGE) / (1.0 - OLU_BOLGE))
	var h := 1.0
	if y < YAVAS_ESIK:
		h = lerpf(0.25, YAVAS_HIZ, y / YAVAS_ESIK)
	elif y < TAM_ESIK:
		h = lerpf(YAVAS_HIZ, 1.0, smoothstep(YAVAS_ESIK, TAM_ESIK, y))
	return v * (h / m)


func _physics_process(delta: float) -> void:
	body.seated = seated and not _otur_gec and not _kalk
	# joystick oynayınca hareket biter, gövde yürüyüşe yumuşakça geçer
	if emote_active and (move_input.length() > 0.15 or Input.get_vector("sol", "sag", "ileri", "geri").length() > 0.1):
		stop_emote()
	if seated or busy or emote_active:
		velocity = Vector3.ZERO
		_yatay = Vector3.ZERO
		body.walk = 0.0
		_speed = 0.0
		return
	var dir2 := _joystick(move_input)
	var keys := Input.get_vector("sol", "sag", "ileri", "geri")
	if keys.length() > 0.0:
		dir2 = keys
	# KOŞ halkası (ya da Shift) hızlı koşturur, eğilince yavaşlar
	var run := RUN_MULT if (sprint or Input.is_action_pressed("kos")) and not crouched else 1.0
	if crouched:
		run = 0.5
	# hız oyuncuya göre (yerel) yumuşar: bakınca yön hemen döner, ama hızlanma/durma doğal.
	# Çarpışma bu hızı kesmez (yalnız o karedeki hareketi): duvar bitince takılmadan devam eder.
	var hedef := Vector3(dir2.x, 0.0, dir2.y) * (SPEED * run)
	var oran := FREN
	if hedef.length_squared() > _yatay.length_squared() and hedef.dot(_yatay) >= 0.0:
		oran = IVME
	_yatay = _yatay.lerp(hedef, 1.0 - exp(-oran * delta))
	if hedef == Vector3.ZERO and _yatay.length_squared() < 0.0009:
		_yatay = Vector3.ZERO
	var dir := transform.basis * _yatay
	velocity.x = dir.x
	velocity.z = dir.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	_leash(delta)
	move_and_slide()
	var speed := Vector2(velocity.x, velocity.z).length() / SPEED
	body.walk = speed
	_speed = minf(speed, 1.5)


# Göz yüksekliği (eğilip kalkarken yumuşak), kafa sallanması + ayak sesi (adımla aynı anda), kamera sarsıntısı.
# Oturma/kalkma gibi tween'ler sürerken (seated/busy) göz yüksekliğine dokunmaz.
func _kamera_his(delta: float) -> void:
	if seated or busy:
		_eye_s = head.position.y
		_bob_g = 0.0
		head.position.x = 0.0
	else:
		_eye_s = lerpf(_eye_s, _eye, 1.0 - exp(-delta * GOZ_HIZI))
		_bob_g = lerpf(_bob_g, minf(_speed, 1.3) if head_bob else 0.0, 1.0 - exp(-delta * 6.0))
		if _speed > 0.1:
			# adım başına bir iniş-çıkış; en alçak noktada ayak sesi (koşarken daha sık)
			var once := bob_t
			bob_t += delta * _speed * TAU / Sfx.ADIM_ARALIK
			if floorf(bob_t / TAU) != floorf(once / TAU) and is_on_floor():
				Sfx.adim_cal(_steps, _speed, crouched)  # koşarken ağır, çömelirken çok kısık
		head.position.y = _eye_s - cos(bob_t) * BOB_DIKEY * _bob_g
		head.position.x = sin(bob_t * 0.5) * BOB_YAN * _bob_g
	# aşağı bakınca gövde geri kayar (yaka, boyun, omuz kameranın görüşüne girmesin)
	var asagi := 0.0
	if not seated and not emote_active:
		asagi = smoothstep(ASAGI_BASLA, PITCH_MIN, rad_to_deg(head.rotation.x)) * ASAGI_GERI
	_asagi_geri = lerpf(_asagi_geri, asagi, 1.0 - exp(-delta * 12.0))
	_sars_tick(delta)


# ---------- kamera sarsıntısı (tek yer) ----------
# Kapı çarpması, patlama, silah atışı, elektrik çarpması: hepsi buradan. guc: en büyük kayma (m; 0,03 hafif,
# 0,12 sert, 0,22 çok sert), sure: sn. titret: telefon da titresin (Titresim; ayarlardan kapatılabilir).
# Üst üste gelirse güçlüsü kalır. main.gd _shake(t, amp) de buraya yönlenir.
func sars(guc: float, sure: float, titret := false) -> void:
	if guc <= 0.0 or sure <= 0.0:
		return
	if guc >= _sars_guc * _sars_kalan():
		_sars_guc = guc
		_sars_sure = sure
		_sars_t = sure
	if titret:
		Titresim.vur("guclu" if guc >= 0.1 else ("orta" if guc >= 0.04 else "hafif"))


# Bir noktadaki olayın sarsıntısı: uzaklaştıkça zayıflar, menzil dışında hiç yok.
func sars_yakin(nokta: Vector3, guc: float, sure: float, menzil := 5.0, titret := false) -> void:
	var d := global_position.distance_to(nokta)
	if d < menzil:
		sars(guc * (1.0 - d / menzil), sure, titret)


func _sars_kalan() -> float:
	if _sars_t <= 0.0 or _sars_sure <= 0.0:
		return 0.0
	var k := _sars_t / _sars_sure
	return k * k


func _sars_tick(delta: float) -> void:
	if _sars_t <= 0.0:
		return
	_sars_t = maxf(0.0, _sars_t - delta)
	_sars_faz += delta
	var g := _sars_guc * _sars_kalan()
	if _sars_t <= 0.0:
		g = 0.0
		_sars_guc = 0.0
	var f := _sars_faz
	camera.h_offset = (sin(f * 71.0) * 0.6 + sin(f * 113.0 + 1.7) * 0.4) * g
	camera.v_offset = (sin(f * 83.0 + 0.6) * 0.6 + sin(f * 127.0 + 2.9) * 0.4) * g
	head.rotation.z = sin(f * 37.0 + 0.3) * minf(g * 0.25, 0.03)


# ---------- telefon ----------
# Ahizeyi al: gerekirse telefonun önüne adım atar, sağ el çataldaki ahizeye uzanır, kavrar, kulağa götürür.
func lift_handset(cell: Node3D) -> void:
	if phone_cell == cell and on_call:
		return
	if emote_active:
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
		var tw := _gecis(create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))
		_konum_gecis(tw, spot, 0.32)
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
					var gt := _gecis(create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
					_konum_gecis(gt, global_position + wall_n * 0.32, 0.55)
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
	if emote_active:
		stop_emote()
	if crouched:
		toggle_crouch()  # çömelik oturulmaz (kalkınca çömelik göz hizasına inmesin)
	Sfx.tek(self, "koltuk_otur", -6.0)
	seated = true
	busy = true
	col.disabled = true
	_yatay = Vector3.ZERO
	_bakis = Vector2.ZERO
	# koltuğa dönüp yaklaşırken göz biraz gecikmeyle iner; sonunda minder hafifçe yaylanır.
	# Gövde oturma pozuna yol yarılanınca geçer (havada oturmasın).
	_otur_gec = true
	var tw := _gecis(create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))
	_konum_gecis(tw, seat, 0.7)
	tw.tween_property(self, "rotation:y", _turn_to(yaw), 0.6)
	tw.tween_property(head, "position:y", EYE_SEAT - 0.025, 0.62).set_trans(Tween.TRANS_CUBIC).set_delay(0.08)
	tw.tween_property(head, "rotation:x", deg_to_rad(-4.0), 0.7)
	tw.tween_callback(func() -> void: _otur_gec = false).set_delay(0.25)
	tw.chain().tween_property(head, "position:y", EYE_SEAT, 0.16).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_sat)


func _sat() -> void:
	busy = false


func stand(to: Vector3) -> void:
	busy = true
	_otur_gec = false
	_kalk = true  # gövde kalkma pozuna hemen geçer (kamera yükselirken gövde oturur kalmasın)
	_bakis = Vector2.ZERO
	Sfx.tek(self, "koltuk_kalk", -6.0)
	# önce doğrulur (göz yükselir), hemen ardından koltuktan bir adım uzaklaşır
	var tw := _gecis(create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))
	tw.tween_property(head, "position:y", EYE_STAND, 0.55).set_trans(Tween.TRANS_CUBIC)
	_konum_gecis(tw, to, 0.5).set_delay(0.12)
	tw.chain().tween_callback(_stood)


func _stood() -> void:
	col.disabled = false
	seated = false
	busy = false
	_kalk = false


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
	var want := Vector3(0.0, 0.0, head.position.z + EYE_BEHIND + _em_back + _asagi_geri)
	var k := minf(1.0, delta * 12.0)
	# hareket sırasında baş daha çok öne/yana gider (eğilme, boks, dans): gövde daha geniş kayar, kamera başa girmez
	var reach := 0.45 if emote_active else 0.0
	body.position.x = clampf(body.position.x + (want.x - hp.x) * k, -0.2 - reach, 0.2 + reach)
	body.position.z = clampf(body.position.z + (want.z - hp.z) * k, -0.3 - reach, 0.3 + reach)
	_emote_view(delta, sk)
	# otururken/çömelirken göz, modelin gerçek göz hizasına çıkar (kamera boynun içinde kalmasın)
	var lift := 0.0
	if seated or crouched:
		lift = clampf(hp.y + 0.075 - head.position.y, 0.0, 0.3)
	camera.position.y = lerpf(camera.position.y, lift + _em_drop, minf(1.0, delta * 6.0))


# Birinci şahıs katmanı: gövde sadece bu katmanda (ayna görmez); eldeki eşyalar dünyada da görünür (aynada ikizin elinde).
func _fp_layers(n: Node, world_too: bool) -> void:
	if n is VisualInstance3D and not (n is Light3D) and not (n is Decal):
		var v := n as VisualInstance3D
		v.layers = (v.layers | FP_LAYER) if world_too else ((v.layers | FP_LAYER) & ~1)
	for c in n.get_children():
		_fp_layers(c, world_too)
