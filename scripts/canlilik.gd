# Karakter canlılığı (uzak oyuncular, botlar, ayna ikizi, menü / maç sonu karakteri):
#  - göz kırpma (2-6 sn arayla; ölünce gözler kapalı),
#  - nefes (göğüs ve omuzlar çok hafif inip kalkar; duruş animasyonunun üstüne),
#  - konuşurken çene iner kalkar, baş hafifçe sallanır, serbest el küçük jestler yapar,
#  - bakış: baş ve gözler yakındaki konuşana / silahı tutana / kameraya (oyuncuya) sınırlı ve yumuşak döner,
#  - boşta çeşitlilik: uzun süre duran karakter ara sıra ağırlık değiştirir, omuz silker, ensesini kaşır.
#
# Modellerde göz kapağı, çene ya da göz kemiği yok (Quaternius CC0 kafası tek "Head" kemiğine bağlı). Bu yüzden
# kafa kemiğinin altına dört küçük kemik eklenir:
#   canli_Cene  : kafa meshinin alt dudak + çene köşeleri bu kemiğe yumuşak geçişle bağlanır (kopya mesh)
#   canli_Goz0/1: göz küreleri (kopya mesh) kendi merkezlerinde döner
#   canli_Kapak : iki gözün önünde, göz küresini saran ince deri kapak (yalnız kırparken / ölüyken çizilir);
#                 göz merkezinden geçen yatay eksende döner (gerçek göz kapağı gibi yukarıdan iner)
# Kopya meshler gövde (kafa meshi) başına bir kez kurulur ve paylaşılır.
#
# İskelette düzenleyici sırası: GovdeDuzen (kamburluk) -> Canlilik -> aim_mod (el IK'sı, ölüm yığılması).
# El IK'sı bundan sonra çalıştığı için nefes ve jestler eldeki silahı / ahizeyi kaydırmaz. Ahize ve şakaktaki
# silah baş konumuna göre yerleştiği için o pozlarda baş neredeyse hiç dönmez (yalnız gözler).
#
# Performans: yalnız kameraya ~8 m'den yakın ve ekranda olan karakterlerde çalışır (uzakta düzenleyici kapalı,
# kapak gizli); kare başına birkaç kemik dönüşü.
extends SkeletonModifier3D

const MESAFE := 8.0  # bu uzaklıktan (m) ötede çalışmaz
const KAPAK_ACIK := 88.0  # göz açıkken kapağın yukarı dönüş açısı (derece)
const KEMIKLER := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "RightShoulder",
	"LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand", "LeftUpLeg", "RightUpLeg"]
const AIM_PATH := "res://scripts/modlar/aim_mod.gd"

static var _hepsi: Array = []  # sahnedeki canlılar (birbirine bakmak için)
static var _geo := {}  # kafa meshi + göz meshi -> paylaşılan kopyalar ve ölçüler
static var kapat := false  # test/ölçüm: canlılık hiç kurulmaz (karşılaştırma için)

var body: Node3D  # model_body
var _b := {}
var _cene := -1
var _goz := [-1, -1]
var _kapak := -1
var _kapak_mi: MeshInstance3D
var _agiz_mi: MeshInstance3D
static var _agiz_mat: StandardMaterial3D
var _mesafe := 0.0  # kameraya uzaklık (m)
var _g: Dictionary  # paylaşılan ölçüler
var _rest := {}  # eklenen kemiklerin dinlenme dönüşleri
var _aim: Node = null
var _aim_t := 0.0
var _sakal := 0.0  # sakallıda çene daha az iner (sakal kafaya sabit)

# zaman ve durum
var _uyanik := 0.0  # kurulumdan sonra geçen süre (ilk anlarda hiçbir şey oynamaz: küçük resim çekimleri)
var _kontrol := 0.0
var _yakin := false
var _dt := 0.016
var _t := 0.0
var _kirp_bekle := 2.0
var _kirp_t := -1.0
var _kirp_cift := false
var kapali := 0.0  # 0 göz açık, 1 kapalı (test için de okunur)
var kapali_zorla := -1.0  # test: >=0 ise göz kapağı bu değerde kalır
var _nefes := 0.0
var _konus := 0.0  # yumuşatılmış konuşma
var _konus_hizli := 0.0
var _hedef: Variant = null  # bakılan nokta (dünya) ya da null
var _hedef_kim: Variant = null
var _hedef_sec := 0.0
var _bak := Vector2.ZERO  # uygulanan baş dönüşü (yaw, pitch, radyan)
var _goz_bak := [Vector2.ZERO, Vector2.ZERO]
var _sakkad := Vector2.ZERO
var _sakkad_t := 1.0
var _bos := 0.0  # boşta geçen süre
var _jest := ""
var _jest_t := 0.0
var _jest_len := 0.0
var _jest_bekle := 9.0
var _jest_yon := 1.0
var _faz := Vector4.ZERO  # konuşma jestleri için rastgele fazlar
var bas_dunya := Vector3.ZERO  # gözlerin ortası (dünya), başkaları buna bakar
var jest_zorla := ""  # test: bu boşta hareketini hemen başlatır
var cene_zorla := -1.0  # test: çene açısı (derece)


static func kur(b: Node3D, sk: Skeleton3D) -> Node:
	if kapat or _test_arg("canli") == "0":
		return null
	var bas: MeshInstance3D = null
	var goz: MeshInstance3D = null
	for c in sk.get_children():
		if c is MeshInstance3D:
			if String(c.name) == "Bas":
				bas = c
			elif String(c.name) == "Goz":
				goz = c
	if bas == null or goz == null or bas.skin == null or goz.skin == null:
		return null
	var g := _geo_of(b, bas, goz)
	if g.is_empty():
		return null
	var c: Node = load("res://scripts/canlilik.gd").new()
	c.body = b
	c._g = g
	sk.add_child(c)
	# el IK'sından önce çalışsın
	for i in sk.get_child_count():
		var o := sk.get_child(i)
		if o.get_script() != null and (o.get_script() as Script).resource_path == AIM_PATH:
			sk.move_child(c, i)
			break
	c._kemikler(sk, bas, goz)
	return c


# ---------- kurulum ----------

func _kemikler(sk: Skeleton3D, bas: MeshInstance3D, goz: MeshInstance3D) -> void:
	for n in KEMIKLER:
		_b[n] = sk.find_bone("mixamorig_" + n)
	var head: int = _b.Head
	var hb: Transform3D = _g.hb
	var ekle := func(ad: String, merkez: Vector3) -> int:
		var i := sk.find_bone(ad)
		if i < 0:
			sk.add_bone(ad)
			i = sk.get_bone_count() - 1
			sk.set_bone_parent(i, head)
			sk.set_bone_rest(i, Transform3D(hb.basis, hb * merkez))
			sk.reset_bone_pose(i)
		_rest[i] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
		return i
	_cene = ekle.call("canli_Cene", _g.pivot)
	_goz[0] = ekle.call("canli_Goz0", _g.goz[0])
	_goz[1] = ekle.call("canli_Goz1", _g.goz[1])
	_kapak = ekle.call("canli_Kapak", (_g.goz[0] + _g.goz[1]) * 0.5)
	bas.mesh = _g.bas_mesh
	bas.skin = _g.bas_skin
	goz.mesh = _g.goz_mesh
	goz.skin = _g.goz_skin
	_kapak_mi = MeshInstance3D.new()
	_kapak_mi.name = "Kapak"
	_kapak_mi.mesh = _g.kapak_mesh
	_kapak_mi.skin = _g.kapak_skin
	_kapak_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_kapak_mi.layers = bas.layers
	_kapak_mi.visible = false
	sk.add_child(_kapak_mi)
	_kapak_mi.skeleton = NodePath("..")
	# ağız içi: yalnız ağız açıkken çizilir (kapalıyken dudaklar birleşik, arkası görünmez)
	_agiz_mi = MeshInstance3D.new()
	_agiz_mi.name = "AgizIci"
	_agiz_mi.mesh = _g.agiz_mesh
	_agiz_mi.skin = _g.agiz_skin
	_agiz_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_agiz_mi.layers = bas.layers
	_agiz_mi.visible = false
	sk.add_child(_agiz_mi)
	_agiz_mi.skeleton = NodePath("..")
	if _agiz_mat == null:
		_agiz_mat = StandardMaterial3D.new()
		_agiz_mat.vertex_color_use_as_albedo = true
		_agiz_mat.vertex_color_is_srgb = true
		_agiz_mat.roughness = 0.75
		_agiz_mat.metallic_specular = 0.15
		_agiz_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_agiz_mi.material_override = _agiz_mat
	# yüz: aynı deri malzemesi, ağız içi koyuluğu eklenmiş gölgelendiriciyle (gövde başına bir kopya)
	var ym := _yuz_malzemesi(bas.material_override)
	if ym != null:
		bas.material_override = ym
	# kapak derisi yüzle aynı malzeme, biraz daha koyu ve pembe (açık renkli alın derisi gibi bembeyaz durmasın)
	var km: Material = bas.material_override
	if km is ShaderMaterial:
		km = (km as ShaderMaterial).duplicate()
		var tn: Variant = (km as ShaderMaterial).get_shader_parameter("tint")
		if tn is Vector3:
			(km as ShaderMaterial).set_shader_parameter("tint", (tn as Vector3) * Vector3(0.9, 0.84, 0.84))
		elif tn is Color:
			var tc := tn as Color
			(km as ShaderMaterial).set_shader_parameter("tint", Color(tc.r * 0.9, tc.g * 0.84, tc.b * 0.84))
	_kapak_mi.set_surface_override_material(0, km)
	var kirpik := StandardMaterial3D.new()
	kirpik.albedo_color = Color(0.07, 0.05, 0.045)
	kirpik.roughness = 0.9
	_kapak_mi.set_surface_override_material(1, kirpik)
	var lk: Dictionary = body.get("look") if body.get("look") is Dictionary else {}
	var sakal := str(lk.get("sakal", "yok"))
	_sakal = 0.0 if sakal in ["yok", "biyik"] else 1.0
	_nefes = randf() * TAU
	_kirp_bekle = randf_range(1.5, 4.5)
	_jest_bekle = randf_range(6.0, 12.0)
	_faz = Vector4(randf() * TAU, randf() * TAU, randf() * TAU, randf() * TAU)
	active = false


func _enter_tree() -> void:
	if not self in _hepsi:
		_hepsi.append(self)


func _exit_tree() -> void:
	_hepsi.erase(self)


# Kafa meshinin (çene ağırlıklı) ve göz meshinin (göz kemikli) kopyaları, göz kapağı meshi ve ölçüler.
static func _geo_of(b: Node3D, bas: MeshInstance3D, goz: MeshInstance3D) -> Dictionary:
	var key := "%d|%d" % [bas.mesh.get_instance_id(), goz.mesh.get_instance_id()]
	if _geo.has(key):
		return _geo[key]
	_geo[key] = {}
	var head_i := -1
	for i in bas.skin.get_bind_count():
		if String(bas.skin.get_bind_name(i)) == "mixamorig_Head":
			head_i = i
	if head_i < 0 or not bas.mesh is ArrayMesh:
		return {}
	var hb: Transform3D = bas.skin.get_bind_pose(head_i)
	var head_pos := hb.affine_inverse().origin
	# göz küreleri: x işaretine göre iki küme (mesh uzayında yüz +z'ye bakar)
	var garr := goz.mesh.surface_get_arrays(0)
	var gv: PackedVector3Array = garr[Mesh.ARRAY_VERTEX]
	var mn := [Vector3.ONE * 1e9, Vector3.ONE * 1e9]
	var mx := [-Vector3.ONE * 1e9, -Vector3.ONE * 1e9]
	for p in gv:
		var s := 0 if p.x < 0.0 else 1
		mn[s] = (mn[s] as Vector3).min(p)
		mx[s] = (mx[s] as Vector3).max(p)
	var gc := [((mn[0] as Vector3) + (mx[0] as Vector3)) * 0.5, ((mn[1] as Vector3) + (mx[1] as Vector3)) * 0.5]
	var r: float = ((mx[0] as Vector3).y - (mn[0] as Vector3).y) * 0.5
	if r < 0.004 or r > 0.04:
		return {}
	# ağız çizgisi: dudakların arkasındaki ağız içi köşeleri (yüzün orta çizgisinde, dudak önünden >1,2 cm içeride,
	# gözlerin 6-9,5 cm altında). Bulunamazsa gözlerin 7,6 cm altı.
	var arr := bas.mesh.surface_get_arrays(0)
	var bv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ey: float = (gc[0] as Vector3).y
	var on_z := -1e9
	for p in bv:
		if absf(p.x) < 0.004 and p.y > ey - 0.095 and p.y < ey - 0.06:
			on_z = maxf(on_z, p.z)
	# en üstteki derin köşe kümesi (daha aşağıdaki derin köşeler alt dudakla çene arasındaki çukurdur)
	var en_ust := -1e9
	for p in bv:
		if absf(p.x) < 0.004 and p.y > ey - 0.095 and p.y < ey - 0.06 and p.z < on_z - 0.015 and p.z > head_pos.z + 0.05:
			en_ust = maxf(en_ust, p.y)
	var ys := 0.0
	var yn := 0
	for p in bv:
		if absf(p.x) < 0.004 and p.y > en_ust - 0.003 and p.y <= en_ust and p.z < on_z - 0.015 and p.z > head_pos.z + 0.05:
			ys += p.y
			yn += 1
	var agiz_y: float = ys / yn if yn > 0 else ey - 0.076
	# dudakların önü (x'e göre) ve ağız genişliği: ağız köşesinde dudak önü belirgin geri çekilir
	var dudak_z := []
	for xi in 13:
		var x := xi * 0.0025
		var mz := -1e9
		for p in bv:
			if absf(absf(p.x) - x) < 0.0015 and absf(p.y - agiz_y) < 0.004 and p.z > head_pos.z + 0.05:
				mz = maxf(mz, p.z)
		dudak_z.append(mz)
	for pass_i in 3:
		for xi in 13:
			if float(dudak_z[xi]) < -1e8:
				dudak_z[xi] = dudak_z[xi - 1] if xi > 0 and float(dudak_z[xi - 1]) > -1e8 else (dudak_z[xi + 1] if xi < 12 else on_z)
	var kose := 0.024
	for xi in range(4, 13):
		if float(dudak_z[xi]) < float(dudak_z[0]) - 0.011:
			kose = xi * 0.0025
			break
	var pivot := Vector3(0.0, agiz_y + 0.035, head_pos.z + 0.005)  # çene eklemi (kulağın önü)
	# kafa meshinin kopyası: alt dudak ve çene, kafa ağırlığının bir kısmını çene kemiğine verir
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(1, bv.size())
	var jaw_i := bas.skin.get_bind_count()
	var neck_i := -1
	for i in bas.skin.get_bind_count():
		if String(bas.skin.get_bind_name(i)) == "mixamorig_Neck":
			neck_i = i
	var orj_b := bones.duplicate()
	var orj_w := weights.duplicate()
	var wv := PackedFloat32Array()
	wv.resize(bv.size())
	# Dudaklar içe kıvrılıp ağız çizgisinde düz bir iç dikişte birleşiyor: dikişin altı (alt dudak) çeneye bağlanır.
	var agirlik := func(p: Vector3) -> float:
		var w := 1.0 if p.y < agiz_y - 0.0004 else 0.0
		# ağız köşelerinde dudaklar birleşik kalır (ağız ortadan açılır), aşağıda çenenin tamamı iner
		var yakin_agiz := 1.0 - smoothstep(0.006, 0.02, agiz_y - p.y)
		w *= lerpf(1.0, 1.0 - smoothstep(kose * 0.5, kose * 1.05, absf(p.x)), yakin_agiz)
		w *= smoothstep(head_pos.z - 0.015, head_pos.z + 0.05, p.z)  # yüzün önü (kulak/ense değil)
		w *= smoothstep(agiz_y - 0.08, agiz_y - 0.045, p.y)  # çene altından boyuna doğru söner
		w *= 1.0 - smoothstep(0.045, 0.068, absf(p.x))  # yanaklar / çene köşesi
		return w
	for v in bv.size():
		var w: float = agirlik.call(bv[v])
		wv[v] = w
		if w > 0.001:
			_cene_agirligi(bones, weights, v, per, orj_b, orj_w, w, head_i, neck_i, jaw_i)
	# Dudaklar ayrılsın: ağız çizgisindeki ortak köşeler alt dudak üçgenleri için kopyalanır (kopya tam çeneye,
	# asıl köşe kafaya bağlı). Ağız kapalıyken ikisi aynı yerde (dikiş görünmez); açılınca gerçek bir aralık açılır,
	# arkasındaki koyu ağız içi ve dişler görünür (gerilip dudak dokusuyla dolan üçgen perdesi olmaz).
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var kopya := {}  # asıl köşe -> kopya
	var n0 := bv.size()
	for t in range(0, idx.size(), 3):
		var cy := (bv[idx[t]].y + bv[idx[t + 1]].y + bv[idx[t + 2]].y) / 3.0
		var cx := absf((bv[idx[t]].x + bv[idx[t + 1]].x + bv[idx[t + 2]].x) / 3.0)
		var cz := (bv[idx[t]].z + bv[idx[t + 1]].z + bv[idx[t + 2]].z) / 3.0
		if cx > kose * 1.1 or absf(cy - agiz_y) > 0.008 or cz < head_pos.z + 0.04:
			continue
		# her üçgen tek tarafa bağlı olsun: köşelerinin çoğu çenedeyse alt dudak (kafadaki köşeleri çene kopyasıyla
		# değişir), değilse üst dudak (çenedeki köşeleri kafa kopyasıyla değişir)
		# dikişin altında köşesi olan üçgen alt dudağındır (dikişten aşağı sarkan üst dudak parçası kalmasın)
		var alt := minf(bv[idx[t]].y, minf(bv[idx[t + 1]].y, bv[idx[t + 2]].y)) < agiz_y - 0.0004
		for e in 3:
			var vi := idx[t + e]
			if vi >= n0 or (bv[vi].y < agiz_y - 0.0004) == alt:
				continue
			var anahtar := vi * 2 + (1 if alt else 0)
			if not kopya.has(anahtar):
				kopya[anahtar] = n0 + kopya.size()
			idx[t + e] = kopya[anahtar]
	if not kopya.is_empty():
		var ekle_dizi := func(ai: int, adet: int) -> void:
			var d: Variant = arr[ai]
			if d == null:
				return
			for an in kopya:
				var vi: int = an / 2
				for k in adet:
					d.append(d[vi * adet + k])
			arr[ai] = d
		ekle_dizi.call(Mesh.ARRAY_VERTEX, 1)
		ekle_dizi.call(Mesh.ARRAY_NORMAL, 1)
		ekle_dizi.call(Mesh.ARRAY_TANGENT, 4)
		ekle_dizi.call(Mesh.ARRAY_TEX_UV, 1)
		ekle_dizi.call(Mesh.ARRAY_COLOR, 1)
		for an in kopya:
			var vi: int = an / 2
			for k in per:
				bones.append(orj_b[vi * per + k])
				weights.append(orj_w[vi * per + k])
				orj_b.append(orj_b[vi * per + k])
				orj_w.append(orj_w[vi * per + k])
			if an % 2 == 1:
				var pd := bv[vi]
				var wd: float = agirlik.call(Vector3(pd.x, agiz_y - 0.001, pd.z))
				_cene_agirligi(bones, weights, kopya[an], per, orj_b, orj_w, wd, head_i, neck_i, jaw_i)
		arr[Mesh.ARRAY_INDEX] = idx
		bv = arr[Mesh.ARRAY_VERTEX]
	# ağız içi karanlığı (UV2.x, canlilik yüz gölgelendiricisi): dudakların içe kıvrılan yüzü koyulaşır
	var uv2 := PackedVector2Array()
	uv2.resize(bv.size())
	for v in bv.size():
		var p := bv[v]
		var ax := absf(p.x)
		if ax > kose * 0.97 or absf(p.y - agiz_y) > 0.0065 or p.z < head_pos.z + 0.04:
			continue
		var f := clampf(ax / 0.0025, 0.0, 12.0)
		var zi := mini(int(f), 11)
		var onz: float = lerpf(float(dudak_z[zi]), float(dudak_z[zi + 1]), f - zi)
		var k := smoothstep(0.004, 0.011, onz - p.z) * (1.0 - smoothstep(kose * 0.7, kose * 0.97, ax))
		uv2[v] = Vector2(k, 0.0)
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	var bas_mesh := ArrayMesh.new()
	var flags: int = bas.mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	bas_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], b._lods_of(bas.mesh, 0), flags)
	bas_mesh.surface_set_material(0, bas.mesh.surface_get_material(0))
	var bas_skin: Skin = bas.skin.duplicate()
	bas_skin.add_named_bind("canli_Cene", Transform3D(Basis(), -pivot))
	# göz meshinin kopyası: her göz küresi kendi kemiğine tam bağlı
	var gb := PackedInt32Array()
	var gw := PackedFloat32Array()
	gb.resize(gv.size() * 4)
	gw.resize(gv.size() * 4)
	for v in gv.size():
		gb[v * 4] = 0 if gv[v].x < 0.0 else 1
		gw[v * 4] = 1.0
	garr[Mesh.ARRAY_BONES] = gb
	garr[Mesh.ARRAY_WEIGHTS] = gw
	for ci in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		garr[ci] = null
	var goz_mesh := ArrayMesh.new()
	goz_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, garr)
	goz_mesh.surface_set_material(0, goz.mesh.surface_get_material(0))
	var goz_skin := Skin.new()
	goz_skin.add_named_bind("canli_Goz0", Transform3D(Basis(), -(gc[0] as Vector3)))
	goz_skin.add_named_bind("canli_Goz1", Transform3D(Basis(), -(gc[1] as Vector3)))
	# göz kapağı: göz küresini saran ince küre kabuğu (kapalı hali), doku yeri gözün üstündeki deriden
	var kmid: Vector3 = ((gc[0] as Vector3) + (gc[1] as Vector3)) * 0.5
	var kapak := _kapak_mesh(gc, r, bv, arr[Mesh.ARRAY_TEX_UV], arr[Mesh.ARRAY_NORMAL])
	var kapak_skin := Skin.new()
	kapak_skin.add_named_bind("canli_Kapak", Transform3D(Basis(), -kmid))
	var agiz := _agiz_mesh(agiz_y, kose, dudak_z)
	var agiz_skin := Skin.new()
	agiz_skin.add_named_bind("mixamorig_Head", hb)
	agiz_skin.add_named_bind("canli_Cene", Transform3D(Basis(), -pivot))
	_geo[key] = {"agiz_mesh": agiz, "agiz_skin": agiz_skin, "hb": hb, "goz": gc, "r": r, "pivot": pivot, "agiz_y": agiz_y,
		"bas_mesh": bas_mesh, "bas_skin": bas_skin, "goz_mesh": goz_mesh, "goz_skin": goz_skin,
		"kapak_mesh": kapak, "kapak_skin": kapak_skin}
	return _geo[key]


# Kapalı göz kapağı (iki göz): göz merkezli küre kabuğu, gözün dış köşesinden iç köşesine; alt kenarında
# koyu kirpik şeridi (2. yüzey). Doku yeri: her köşe gözün hemen üstündeki deriye denk gelen yüz köşesinden.
static func _kapak_mesh(gc: Array, r: float, bv: PackedVector3Array, uv: PackedVector2Array, nrm: PackedVector3Array) -> ArrayMesh:
	const NA := 10  # yatay dilim
	const NE := 7  # dikey dilim
	const R_K := 1.07  # kabuk yarıçapı (göz yarıçapına oran)
	const ALT := -24.0  # kapalı kapağın alt kenarı (derece, göz merkezinden)
	var am := ArrayMesh.new()
	for yuzey in 2:
		var st := SurfaceTool.new()
		st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var e0 := ALT if yuzey == 1 else ALT + 4.0
		var e1 := ALT + 5.0 if yuzey == 1 else 88.0
		var rk := R_K + (0.012 if yuzey == 1 else 0.0)
		for s in 2:
			var c: Vector3 = gc[s]
			var pts := []
			# doku yeri: gözün üstündeki derinin dört köşesi bulunur, aradakiler düzgünce karıştırılır
			# (her köşeye ayrı en yakın nokta alınınca doku lekeli, teğetler bozuk çıkıyordu)
			var kose := []
			for jj in [0, 1]:
				for ii in [0, 1]:
					var aa := deg_to_rad(lerpf(-70.0, 70.0, float(ii)))
					kose.append(uv[_en_yakin(bv, nrm, c + Vector3(sin(aa) * 1.1 * r, -r * lerpf(2.4, 3.0, float(jj)), r * 0.55), c)])
			for j in NE + 1:
				var row := []
				var e := deg_to_rad(lerpf(e0, e1, float(j) / NE))
				for i in NA + 1:
					var a := deg_to_rad(lerpf(-78.0, 78.0, float(i) / NA))
					var d := Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e))
					var p := c + d * r * rk
					var u := Vector2.ZERO
					if yuzey == 0:
						# gözün üstündeki deri (kaş altı): kapağın yukarısı kaşa, aşağısı kapak çizgisine doğru
						var fi := float(i) / NA
						var fj := float(j) / NE
						u = ((kose[0] as Vector2).lerp(kose[1], fi)).lerp((kose[2] as Vector2).lerp(kose[3], fi), fj)
					row.append([p, d, u, Vector3(cos(a), 0.0, -sin(a))])
				pts.append(row)
			for j in NE:
				for i in NA:
					var q4 := [pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]
					for k in [0, 2, 1, 0, 3, 2]:
						var vtx: Array = q4[k]
						st.set_normal(((vtx[1] as Vector3) * 0.45 + Vector3(0, -0.15, 1.0) * 0.55).normalized())  # yüz derisi gibi önden ışık alsın
						st.set_tangent(Plane(vtx[3], 1.0))
						st.set_uv(vtx[2])
						st.set_bones(PackedInt32Array([0, 0, 0, 0]))
						st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
						st.add_vertex(vtx[0])
		st.commit(am)
	return am


static var _yuz_shader: Shader = null

# Yüz malzemesinin kopyası: model_body deri gölgelendiricisine ağız içi koyuluğu (UV2.x) eklenir.
static func _yuz_malzemesi(m: Material) -> Material:
	if not m is ShaderMaterial or (m as ShaderMaterial).shader == null:
		return null
	if _yuz_shader == null:
		var kod := (m as ShaderMaterial).shader.code
		if not kod.contains("void fragment() {") or not kod.contains("	ALBEDO = o;"):
			return null
		kod = kod.replace("void fragment() {", "varying float agiz_ic;
void vertex() {
	agiz_ic = UV2.x;
}

void fragment() {")
		kod = kod.replace("	ALBEDO = o;", "	ALBEDO = mix(o, vec3(0.075, 0.022, 0.02), agiz_ic);")
		_yuz_shader = Shader.new()
		_yuz_shader.code = kod
	var y := (m as ShaderMaterial).duplicate() as ShaderMaterial
	y.shader = _yuz_shader
	return y


# Ağız içi (dudakların arkasında, ağız kapalıyken görünmez): koyu kırmızı-kahve ağız boşluğu (üstü kafada, altı
# çenede; kenarlara doğru açılan yumuşak gölge) ve uçlara doğru incelen yuvarlak bir üst diş sırası. Dudaklar
# ayrılınca aralıktan görünür. Tek yüzey (renk köşede): tek çizim.
static func _agiz_mesh(y: float, kose: float, dudak_z: Array) -> ArrayMesh:
	const N := 16
	var on_z := func(x: float) -> float:
		var f := clampf(absf(x) / 0.0025, 0.0, 12.0)
		var zi := mini(int(f), 11)
		return lerpf(float(dudak_z[zi]), float(dudak_z[zi + 1]), f - zi)
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var koyu := Color(0.17, 0.05, 0.045)
	var acik := Color(0.4, 0.14, 0.12)
	# ağız boşluğu: 3 sıra (üst kafada, orta yarı yarıya, alt çenede)
	var bos := []
	for r in 3:
		var row := []
		for i in N + 1:
			var u := float(i) / N
			var x := lerpf(-kose, kose, u) * 0.85
			var yy: float = y + [0.004, -0.004, -0.012][r] - 0.0012 * pow(absf(x) / kose, 2.0)
			var z: float = on_z.call(x) - [0.011, 0.016, 0.011][r]
			var kenar := maxf(absf(u - 0.5) * 2.0, 0.0 if r == 1 else 0.6)
			row.append([Vector3(x, yy, z), [0.0, 0.5, 1.0][r], koyu.lerp(acik, kenar)])
		bos.append(row)
	var dortgen := func(q: Array) -> void:
		for k in [0, 1, 2, 0, 2, 3]:
			var vt: Array = q[k]
			st.set_normal(Vector3(0, 0, 1))
			st.set_color(vt[2])
			st.set_bones(PackedInt32Array([0, 1, 0, 0]))
			st.set_weights(PackedFloat32Array([1.0 - float(vt[1]), float(vt[1]), 0.0, 0.0]))
			st.add_vertex(vt[0])
	for r in 2:
		for i in N:
			dortgen.call([bos[r][i], bos[r][i + 1], bos[r + 1][i + 1], bos[r + 1][i]])
	# üst dişler: kafaya bağlı, uçlara doğru incelip yuvarlanan bir şerit (alt kenarı hafif gölgeli)
	var dis := []
	for r in 2:
		var row := []
		for i in N + 1:
			var u := float(i) / N
			var x := lerpf(-kose, kose, u) * 0.5
			var t := sqrt(maxf(0.0, 1.0 - pow(u * 2.0 - 1.0, 2.0)))  # elips: uçlarda sıfır
			var yy: float = y + 0.0008 - (0.0 if r == 0 else 0.0032 * t) - 0.001 * pow(absf(x) / kose, 2.0)
			row.append([Vector3(x, yy, on_z.call(x) - 0.0068), 0.0, Color(0.8, 0.77, 0.7) if r == 0 else Color(0.62, 0.58, 0.52)])
		dis.append(row)
	for i in N:
		dortgen.call([dis[0][i], dis[0][i + 1], dis[1][i + 1], dis[1][i]])
	st.commit(am)
	return am


# Köşenin (orijinal) kafa + boyun ağırlığının w kadarı çene kemiğine geçer; en büyük dört ağırlık kalır (toplamı 1).
# Bu modelde çene derisi çoğunlukla boyun kemiğine bağlı olduğundan ikisinden de alınır.
static func _cene_agirligi(bones: PackedInt32Array, weights: PackedFloat32Array, v: int, per: int, orj_b: PackedInt32Array, orj_w: PackedFloat32Array, w: float, head_i: int, neck_i: int, jaw_i: int) -> void:
	var ag := {}
	for k in per:
		var bi: int = orj_b[v * per + k]
		var ww: float = orj_w[v * per + k]
		if ww > 0.0:
			ag[bi] = float(ag.get(bi, 0.0)) + ww
	var hn: float = float(ag.get(head_i, 0.0)) + float(ag.get(neck_i, 0.0))
	if hn <= 0.0:
		return
	for bi in [head_i, neck_i]:
		if ag.has(bi):
			ag[bi] = float(ag[bi]) * (1.0 - w)
	ag[jaw_i] = hn * w
	var sirali: Array = ag.keys()
	sirali.sort_custom(func(x, y) -> bool: return float(ag[x]) > float(ag[y]))
	var top := 0.0
	for k in mini(per, sirali.size()):
		top += float(ag[sirali[k]])
	for k in per:
		if k < sirali.size():
			bones[v * per + k] = sirali[k]
			weights[v * per + k] = float(ag[sirali[k]]) / maxf(top, 1e-6)
		else:
			bones[v * per + k] = 0
			weights[v * per + k] = 0.0


static func _en_yakin(bv: PackedVector3Array, nrm: PackedVector3Array, q: Vector3, c: Vector3) -> int:
	var en := 0
	var ed := 1e9
	for i in bv.size():
		var p := bv[i]
		if absf(p.x - c.x) > 0.04 or p.y > c.y - 0.022 or p.y < c.y - 0.06 or nrm[i].z < 0.2:
			continue
		var d := p.distance_squared_to(q)
		if d < ed:
			ed = d
			en = i
	return en


# ---------- her kare ----------

func _process(delta: float) -> void:
	if _test_arg("canli_olc") == "":
		_surec(delta)
		return
	var t0 := Time.get_ticks_usec()
	_surec(delta)
	_olc[1] += Time.get_ticks_usec() - t0
	if _hepsi.size() > 0 and _hepsi[0] == self:
		_olc[2] += 1
		if _olc[2] % 120 == 0:
			print("[canli_olc] kare başına: düzenleyici %.3f ms, süreç %.3f ms (%d canlı, %d etkin)" % [_olc[0] / 120000.0, _olc[1] / 120000.0, _hepsi.size(), _hepsi.filter(func(o) -> bool: return o.active).size()])
			_olc[0] = 0
			_olc[1] = 0


func _surec(delta: float) -> void:
	if not is_instance_valid(body):
		return
	_dt = minf(delta, 0.05)
	_uyanik += _dt
	_kontrol -= _dt
	if _kontrol <= 0.0:
		_kontrol = 0.25 + randf() * 0.1
		_yakin = _uyanik > 0.4 and _yakin_mi()
		if active != _yakin:
			active = _yakin
			if not _yakin:
				_kapak_mi.visible = false
				_agiz_mi.visible = false
		_aim_t -= 0.3
		if _aim_t <= 0.0 or (_aim != null and not is_instance_valid(_aim)):
			_aim_t = 1.0
			_aim = _aim_bul()
	if not _yakin:
		return
	_t += _dt
	var olu := _olu()
	# konuşma
	var lvl := clampf(float(body.get("talk")) if body.get("talk") != null else 0.0, 0.0, 1.0)
	if _test_arg("canli_konus") != "":
		# test: sahte konuşma sesi (hece hece iner kalkar); canli_konus=1 herkes, canli_konus=yari bazıları
		var hepsi := _test_arg("canli_konus") == "1" or (get_instance_id() % 2 == 0)
		if hepsi:
			lvl = clampf(0.55 + 0.45 * sin(_t * 9.0 + _faz.x) * sin(_t * 2.3 + _faz.y), 0.0, 1.0) * (1.0 if fmod(_t, 5.0) < 3.6 else 0.0)
	_konus_hizli = lerpf(_konus_hizli, lvl, 1.0 - exp(-_dt * (22.0 if lvl > _konus_hizli else 10.0)))
	_konus = lerpf(_konus, 1.0 if lvl > 0.06 else 0.0, 1.0 - exp(-_dt * (4.0 if lvl > 0.06 else 1.2)))
	# nefes (konuşurken / yürürken biraz daha hızlı)
	_nefes += _dt * TAU * (0.26 + 0.08 * _konus + 0.15 * clampf(float(body.walk), 0.0, 1.0))
	# göz kırpma
	if olu:
		kapali = move_toward(kapali, 1.0, _dt * 4.0)
	elif kapali_zorla >= 0.0 or _test_arg("canli_kirp") != "":
		if kapali_zorla < 0.0:
			kapali_zorla = float(_test_arg("canli_kirp"))
		kapali = kapali_zorla
	else:
		_kirp_bekle -= _dt
		if _kirp_t < 0.0 and _kirp_bekle <= 0.0:
			_kirp_t = 0.0
			_kirp_cift = randf() < 0.15
			_kirp_bekle = randf_range(2.0, 6.0)
		if _kirp_t >= 0.0:
			_kirp_t += _dt
			var k := _kirp_egri(_kirp_t)
			if _kirp_t > 0.18:
				if _kirp_cift:
					_kirp_cift = false
					_kirp_t = 0.0
				else:
					_kirp_t = -1.0
					k = 0.0
			kapali = k
		else:
			kapali = 0.0
	_kapak_mi.visible = kapali > 0.02
	_agiz_mi.visible = (_konus_hizli > 0.03 and not olu) or cene_zorla > 0.0 or _test_arg("canli_cene") != ""
	# bakış hedefi
	_hedef_sec -= _dt
	if _hedef_sec <= 0.0:
		_hedef_sec = randf_range(1.2, 2.8)
		var once: Variant = _hedef_kim
		_hedef_sec_et()
		if not is_same(_hedef_kim, once) and randf() < 0.4 and _kirp_t < 0.0 and _kirp_bekle > 0.6:
			_kirp_bekle = 0.05  # bakış değişince çoğu zaman göz kırpılır
	_sakkad_t -= _dt
	if _sakkad_t <= 0.0:
		_sakkad_t = randf_range(0.6, 2.2)
		_sakkad = Vector2(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6)) * (0.045 if _hedef != null else 0.09)
	# boşta hareketleri
	var bos := _bos_mu()
	_bos = _bos + _dt if bos else 0.0
	if _jest != "":
		_jest_t += _dt
		if _jest_t >= _jest_len or (not bos and _jest != "omuz"):
			_jest = "" if _jest_t >= _jest_len else _jest
			if _jest != "":
				_jest_len = minf(_jest_len, _jest_t + 0.5)  # yarıda kesilen hareket yumuşakça biter
	elif jest_zorla != "":
		_jest_baslat(jest_zorla)
		jest_zorla = ""
	elif bos and _bos > _jest_bekle:
		_bos = 0.0
		_jest_bekle = randf_range(7.0, 15.0)
		var secenek := ["omuz"]
		if not bool(body.seated):
			secenek.append_array(["agirlik", "agirlik"])
		if _el_bos(1):
			secenek.append("ense")
		_jest_baslat(secenek[randi() % secenek.size()])


func _jest_baslat(id: String) -> void:
	_jest = id
	_jest_t = 0.0
	_jest_len = {"omuz": 1.3, "agirlik": 3.6, "ense": 3.4}.get(id, 2.0)
	_jest_yon = -1.0 if randf() < 0.5 else 1.0


static var _targs: Variant = null

# Test parametresi (komut satırı: ad=değer), yoksa "".
static func _test_arg(ad: String) -> String:
	if _targs == null:
		_targs = {}
		for a in OS.get_cmdline_user_args():
			var kv := a.split("=", true, 1)
			if kv.size() == 2 and kv[0].begins_with("canli"):
				_targs[kv[0]] = kv[1]
	return str((_targs as Dictionary).get(ad, ""))


static func _kirp_egri(t: float) -> float:
	# hızlı kapanır (0,06 sn), kısa kalır, daha yavaş açılır
	if t < 0.06:
		return smoothstep(0.0, 1.0, t / 0.06)
	if t < 0.09:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (t - 0.09) / 0.09)


func _yakin_mi() -> bool:
	if not body.is_visible_in_tree():
		return false
	var ap: Variant = body.get("_player")
	if ap is AnimationPlayer and not (ap as AnimationPlayer).active:
		return false  # ekranda değil (model_body görünürlük denetleyicisi)
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return false
	_mesafe = cam.global_position.distance_to(body.global_position)
	return _mesafe < MESAFE


func _aim_bul() -> Node:
	var sk := get_skeleton()
	if sk == null:
		return null
	for c in sk.get_children():
		if c.get_script() != null and (c.get_script() as Script).resource_path == AIM_PATH:
			return c
	return null


func _olu() -> bool:
	if _aim != null and is_instance_valid(_aim) and float(_aim.get("slump")) > 0.3:
		return true
	return str(body.get("emote")) == "bayil"


func _mod() -> String:
	if _aim == null or not is_instance_valid(_aim):
		return ""
	var m := str(_aim.get("mode"))
	if m != "":
		return m
	var w: Array = _aim.get("weights")
	return "el" if (float(w[0]) > 0.05 or float(w[1]) > 0.05) else ""


func _el_bos(side: int) -> bool:
	if _aim == null or not is_instance_valid(_aim):
		return true
	return float((_aim.get("weights") as Array)[side]) < 0.02


func _bos_mu() -> bool:
	return str(body.get("emote")) == "" and float(body.walk) < 0.05 and not bool(body.get("crouched")) \
		and _mod() == "" and _konus < 0.2 and not _olu()


# Bakılacak kişi/nokta: silahı tutan > konuşan > kamera (oyuncu) > hiçbiri (önüne bakar).
func _hedef_sec_et() -> void:
	var ben := body.global_position
	var ileri := -body.global_transform.basis.z.normalized()
	var zorla: Variant = body.get("bakis")
	if zorla is Vector3 and zorla != Vector3.ZERO:
		_hedef = zorla
		_hedef_kim = "zorla"
		return
	var mod := _mod()
	if mod == "hedef" and _aim.get("mode_target") is Vector3 and _aim.get("mode_target") != Vector3.ZERO:
		_hedef = _aim.get("mode_target")
		_hedef_kim = "nisan"
		return
	var en: Variant = null
	var en_p := 0.0
	for o in _hepsi:
		if o == self or not is_instance_valid(o) or not o._yakin:
			continue
		var p: Vector3 = o.bas_dunya
		var d := p - ben
		if d.length() > 5.0 or d.length() < 0.3:
			continue
		var on := Vector2(d.x, d.z).normalized().dot(Vector2(ileri.x, ileri.z))
		if on < -0.2:
			continue  # arkamda
		var puan := 0.0
		var om: String = o._mod()
		if om in ["silah", "sakak", "hedef"]:
			puan = 3.0
		elif o._konus > 0.3:
			puan = 2.0 + float(o._konus_hizli)
		if puan > en_p:
			en_p = puan
			en = o
	if en != null:
		_hedef_kim = en
		_hedef = null  # her karede kişinin o anki baş konumu
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var d := cam.global_position - ben
		var on := Vector2(d.x, d.z).normalized().dot(Vector2(ileri.x, ileri.z))
		# kameraya hep değil, çoğu zaman bakar; arada başka yere (önüne) bakar
		if d.length() < 4.5 and d.length() > 0.45 and on > 0.35 and randf() < 0.75:
			_hedef_kim = cam
			_hedef = null
			return
	_hedef_kim = null
	_hedef = null


func _hedef_noktasi() -> Variant:
	if _hedef_kim == null:
		return null
	if _hedef_kim is String:
		return _hedef
	if not is_instance_valid(_hedef_kim):
		_hedef_kim = null
		return null
	if _hedef_kim is Camera3D:
		return (_hedef_kim as Camera3D).global_position
	if _hedef_kim is Node and _hedef_kim.get("bas_dunya") is Vector3:
		return _hedef_kim.bas_dunya
	return null


static var _olc := [0, 0, 0]  # ölçüm: düzenleyici us, süreç us, kare


func _process_modification() -> void:
	if _test_arg("canli_olc") == "":
		_uygula()
		return
	var t0 := Time.get_ticks_usec()
	_uygula()
	_olc[0] += Time.get_ticks_usec() - t0


func _uygula() -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(body) or int(_b.get("Head", -1)) < 0:
		return
	var olu := _olu()
	var head: int = _b.Head
	var hb: Transform3D = _g.hb
	var inv := sk.global_transform.affine_inverse()
	var up := Vector3.UP
	var ra := _gpos(sk, "RightArm")
	var la := _gpos(sk, "LeftArm")
	var right := (ra - la)
	right.y = 0.0
	right = right.normalized() if right.length() > 0.01 else Vector3(-1, 0, 0)
	var fwd := up.cross(right).normalized()
	var mod := _mod()
	if not olu:
		if _mesafe < 4.0:
			_nefes_uygula(sk, up)  # uzakta görünmez: hesaplanmaz
		_jest_uygula(sk, up, right, fwd)
		_konus_uygula(sk, right)
	# ---- baş ve göz ----
	var hg := sk.get_bone_global_pose(head)
	var gm: Vector3 = hb * (((_g.goz[0] as Vector3) + (_g.goz[1] as Vector3)) * 0.5)
	bas_dunya = sk.global_transform * (hg * gm)
	var nokta: Variant = null if olu else _hedef_noktasi()
	var frac := 0.55
	var lim_y := deg_to_rad(24.0)
	var lim_p := deg_to_rad(14.0)
	if _hedef_kim is String and _hedef_kim == "zorla":
		frac = 0.9  # ayna ikizi: başı oyuncunun bakışıyla
		lim_y = deg_to_rad(45.0)
		lim_p = deg_to_rad(35.0)
	match mod:
		"ahize", "sakak":
			frac = 0.06
		"silah", "hedef", "c4", "el":
			frac = 0.3
	if str(body.get("emote")) != "":
		frac = 0.0
	frac *= 1.0 - 0.5 * clampf(float(body.walk), 0.0, 1.0)
	frac *= clampf((_uyanik - 0.4) / 1.0, 0.0, 1.0)  # kurulumdan sonra yavaşça devreye girer
	var istek := Vector2.ZERO
	var hedef_sk := Vector3.ZERO
	if nokta != null:
		hedef_sk = inv * (nokta as Vector3)
		var d := hedef_sk - hg * gm
		var yaw_t := atan2(d.x, d.z)
		var pit_t := atan2(d.y, Vector2(d.x, d.z).length())
		var f := (hg.basis.orthonormalized() * hb.basis * Vector3(0, 0, 1)).normalized()
		var yaw_a := atan2(f.x, f.z)
		var pit_a := atan2(f.y, Vector2(f.x, f.z).length())
		if absf(yaw_t) < deg_to_rad(75.0):
			istek = Vector2(clampf(wrapf(yaw_t - yaw_a, -PI, PI) * frac, -lim_y, lim_y), clampf((pit_t - pit_a) * frac, -lim_p, lim_p))
		else:
			nokta = null
	_bak = _bak.lerp(istek, 1.0 - exp(-_dt * 4.0))
	if _test_arg("canli_log") == "1" and Engine.get_process_frames() % 30 == 0:
		print("[canli] ", body.get("look").get("govde"), " kim=", _hedef_kim, " istek=", istek, " bak=", _bak, " nokta=", nokta)
	if _bak.length() > 0.001:
		var f := (hg.basis.orthonormalized() * hb.basis * Vector3(0, 0, 1)).normalized()
		var ax := f.cross(up)
		ax = ax.normalized() if ax.length() > 0.01 else Vector3.RIGHT
		var R := Quaternion(up, _bak.x) * Quaternion(ax, _bak.y)
		var neck: int = _b.Neck
		if neck >= 0:
			_global_dondur(sk, neck, Quaternion.IDENTITY.slerp(R, 0.4))
		_global_dondur(sk, head, Quaternion.IDENTITY.slerp(R, 0.6))
	# gözler: hedefe (başın dönüşünden sonra), sınırlı; hedef yokken küçük sıçramalar
	for s in 2:
		var gi: int = _goz[s]
		if gi < 0:
			continue
		var istek_g := _sakkad
		if nokta != null and not olu:
			var eg := sk.get_bone_global_pose(gi)
			var ld := eg.basis.orthonormalized().inverse() * (hedef_sk - eg.origin)
			istek_g += Vector2(atan2(ld.x, ld.z), atan2(ld.y, Vector2(ld.x, ld.z).length())) * clampf((_uyanik - 0.4) / 0.6, 0.0, 1.0)
		elif olu:
			istek_g = Vector2.ZERO
		istek_g = Vector2(clampf(istek_g.x, -0.38, 0.38), clampf(istek_g.y, -0.24, 0.24))
		_goz_bak[s] = (_goz_bak[s] as Vector2).lerp(istek_g, 1.0 - exp(-_dt * 18.0))
		var gb: Vector2 = _goz_bak[s]
		sk.set_bone_pose_rotation(gi, (_rest[gi] as Quaternion) * Quaternion(Vector3.UP, gb.x) * Quaternion(Vector3.RIGHT, -gb.y))
	# göz kapağı: göz merkezinden geçen yatay eksende yukarıdan iner
	if _kapak >= 0:
		var aci := deg_to_rad(KAPAK_ACIK * (1.0 - kapali))
		sk.set_bone_pose_rotation(_kapak, (_rest[_kapak] as Quaternion) * Quaternion(Vector3.RIGHT, -aci))
	# çene
	if _cene >= 0:
		var ac := 0.0
		if not olu and _konus_hizli > 0.03:
			var hece := 0.55 + 0.45 * sin(_t * 15.0 + sin(_t * 3.7) * 2.0)
			ac = clampf(_konus_hizli * 1.6, 0.0, 1.0) * hece * deg_to_rad(6.0 - 2.0 * _sakal)
		if cene_zorla < 0.0 and _test_arg("canli_cene") != "":
			cene_zorla = float(_test_arg("canli_cene"))
		if cene_zorla >= 0.0:
			ac = deg_to_rad(cene_zorla)
		sk.set_bone_pose_rotation(_cene, (_rest[_cene] as Quaternion) * Quaternion(Vector3.RIGHT, ac))


func _gpos(sk: Skeleton3D, n: String) -> Vector3:
	var i: int = _b.get(n, -1)
	return sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO


# Kemiği iskelet uzayındaki R dönüşüyle (kendi ekleminde) döndürür.
func _global_dondur(sk: Skeleton3D, bi: int, R: Quaternion) -> void:
	if bi < 0:
		return
	var p := sk.get_bone_parent(bi)
	var pg := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var g := sk.get_bone_global_pose(bi).basis.orthonormalized()
	sk.set_bone_pose_rotation(bi, (pg.inverse() * Basis(R) * g).get_rotation_quaternion())


func _yerel_dondur(sk: Skeleton3D, n: String, eksen: Vector3, derece: float) -> void:
	var bi: int = _b.get(n, -1)
	if bi < 0 or absf(derece) < 0.001:
		return
	sk.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi) * Quaternion(eksen, deg_to_rad(derece)))


# Kemiğin çocuğuna giden yönünü iskelet uzayında `to` yönüne (ağırlıkla) çevirir.
func _yonelt(sk: Skeleton3D, bi: int, cocuk: int, to: Vector3, w: float) -> void:
	if bi < 0 or cocuk < 0 or w <= 0.001:
		return
	var from := sk.get_bone_global_pose(cocuk).origin - sk.get_bone_global_pose(bi).origin
	if from.length() < 1e-5 or to.length() < 1e-5:
		return
	var q := Quaternion(from.normalized(), to.normalized())
	_global_dondur(sk, bi, Quaternion.IDENTITY.slerp(q, w))


func _nefes_uygula(sk: Skeleton3D, up: Vector3) -> void:
	var n := sin(_nefes)  # +1 nefes almış
	_yerel_dondur(sk, "Spine1", Vector3.RIGHT, -0.5 * n)
	_yerel_dondur(sk, "Spine2", Vector3.RIGHT, -0.7 * n)
	_yerel_dondur(sk, "Neck", Vector3.RIGHT, 0.9 * n)  # baş sabit kalsın
	# omuzlar nefes alırken çok az kalkar
	var k := 0.012 * (n * 0.5 + 0.5)
	for s in ["Left", "Right"]:
		_omuz_kaldir(sk, s, up, k, 1.0)


# Omuzu kaldırır; kol aynı yöne sarkmaya devam eder (kol açılıp A duruşuna dönmesin).
func _omuz_kaldir(sk: Skeleton3D, s: String, up: Vector3, k: float, w: float) -> void:
	var sh: int = _b[s + "Shoulder"]
	var ar: int = _b[s + "Arm"]
	var fa: int = _b[s + "ForeArm"]
	if sh < 0 or ar < 0 or fa < 0 or w <= 0.001:
		return
	var kol := sk.get_bone_global_pose(fa).origin - sk.get_bone_global_pose(ar).origin
	var d := sk.get_bone_global_pose(ar).origin - sk.get_bone_global_pose(sh).origin
	_yonelt(sk, sh, ar, d.normalized() + up * k, w)
	_yonelt(sk, ar, fa, kol, 1.0)


func _konus_uygula(sk: Skeleton3D, right: Vector3) -> void:
	if _konus < 0.01:
		return
	var k := _konus
	# baş: hafif onaylar gibi iner kalkar, yana eğilir
	_yerel_dondur(sk, "Head", Vector3.RIGHT, k * (1.6 * sin(_t * 2.3 + _faz.x) + 0.8 * sin(_t * 5.1 + _faz.y) * _konus_hizli))
	_yerel_dondur(sk, "Head", Vector3.FORWARD, k * 1.2 * sin(_t * 1.3 + _faz.z))
	_yerel_dondur(sk, "Neck", Vector3.UP, k * 1.5 * sin(_t * 0.9 + _faz.w))
	# serbest eller küçük jestler yapar (ön kol kalkar iner, bilek döner); yürürken / el doluyken yok
	if float(body.walk) > 0.3 or str(body.get("emote")) != "":
		return
	for side in 2:
		if not _el_bos(side):
			continue
		var s := "Right" if side == 1 else "Left"
		var fa: int = _b[s + "ForeArm"]
		var ha: int = _b[s + "Hand"]
		var ph: float = _faz.x if side == 1 else _faz.z
		var kalk := k * deg_to_rad(6.0 + 5.0 * sin(_t * 1.7 + ph) + 3.0 * sin(_t * 4.3 + ph * 2.0) * _konus_hizli)
		_global_dondur(sk, fa, Quaternion(right, kalk))
		if ha >= 0 and fa >= 0:
			var ax := (sk.get_bone_global_pose(ha).origin - sk.get_bone_global_pose(fa).origin).normalized()
			_global_dondur(sk, ha, Quaternion(ax, k * deg_to_rad(12.0) * sin(_t * 2.1 + ph)))


func _jest_uygula(sk: Skeleton3D, up: Vector3, right: Vector3, fwd: Vector3) -> void:
	if _jest == "":
		return
	var t := _jest_t
	var T := _jest_len
	match _jest:
		"omuz":
			# omuz silkme: çabuk kalkar, kısa kalır, iner; baş hafif yana
			var e := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(T - 0.55, T, t))
			for s in ["Left", "Right"]:
				_omuz_kaldir(sk, s, up, 0.32, e)
			_yerel_dondur(sk, "Head", Vector3.FORWARD, 5.0 * e * _jest_yon)
		"agirlik":
			# ağırlık değiştirme: kalça bir yana eğilir, üst gövde dik kalır, bacaklar yere basmaya devam eder
			var e := smoothstep(0.0, 0.9, t) * (1.0 - smoothstep(T - 1.0, T, t))
			var a := deg_to_rad(2.6) * e * _jest_yon
			var R := Quaternion(fwd, a)
			_global_dondur(sk, _b.Hips, R)
			for s in ["LeftUpLeg", "RightUpLeg"]:
				_global_dondur(sk, _b[s], R.inverse())
			_global_dondur(sk, _b.Spine1, Quaternion(fwd, -a * 0.9))
			_global_dondur(sk, _b.Head, Quaternion(fwd, a * 0.4))
		"ense":
			_ense(sk, up, right, fwd, t, T)


# Ensesini kaşıma: sağ el ensenin arkasına gider (iki kemikli IK), parmaklar birkaç kez kaşır, el iner.
func _ense(sk: Skeleton3D, up: Vector3, right: Vector3, fwd: Vector3, t: float, T: float) -> void:
	var ua: int = _b.RightArm
	var fa: int = _b.RightForeArm
	var ha: int = _b.RightHand
	if ua < 0 or fa < 0 or ha < 0 or not _el_bos(1):
		return
	var e := smoothstep(0.0, 0.75, t) * (1.0 - smoothstep(T - 0.8, T, t))
	if e <= 0.001:
		return
	var neck := _gpos(sk, "Neck")
	var kas := 0.012 * sin(t * TAU * 3.2) * smoothstep(0.7, 1.0, e)
	var W := neck + right * 0.085 + up * (0.05 + kas) - fwd * 0.1  # bilek: ensenin sağ arkası
	var S := sk.get_bone_global_pose(ua).origin
	var E := sk.get_bone_global_pose(fa).origin
	var H := sk.get_bone_global_pose(ha).origin
	var l1 := S.distance_to(E)
	var l2 := E.distance_to(H)
	var d := W - S
	var dist := clampf(d.length(), absf(l1 - l2) + 0.02, l1 + l2 - 0.005)
	var n := d.normalized()
	var pole := (right * 0.75 + up * 0.25 + fwd * 0.35).normalized()
	var pp := (pole - n * pole.dot(n)).normalized()
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var E2 := S + n * (l1 * ca) + pp * (l1 * sqrt(1.0 - ca * ca))
	_yonelt(sk, ua, fa, E2 - S, e)
	var E_now := sk.get_bone_global_pose(fa).origin
	_yonelt(sk, fa, ha, (S + n * dist) - E_now, e)
	# avuç enseye: parmaklar boynun arkasına doğru
	var mid: int = sk.find_bone("mixamorig_RightHandMiddle1")
	if mid >= 0:
		var hand_now := sk.get_bone_global_pose(ha).origin
		var to := (neck + up * 0.05 - fwd * 0.06) - hand_now
		_yonelt(sk, ha, mid, to, e * 0.8)
	_yerel_dondur(sk, "Head", Vector3.RIGHT, 7.0 * e)  # baş biraz öne eğilir
