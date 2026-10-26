# Bir hapishane hücresi: duvarlar, koltuk, ranza, raf, pencere, kırmızı telefon, lamba ve kapı.
# Hücrenin içi yerel koordinatlarda kurulur; hücre koridor boyunca z ekseninde dizilir.
extends Node3D

const Sfx := preload("res://scripts/sfx.gd")
const Dunya := preload("res://scripts/dunya.gd")
const Telefon := preload("res://scripts/telefon.gd")

const H := 3.2
const CHAIR_POS := Vector3(0.0, 0.0, -1.5)
const CHAIR_YAW := 0.8  # koltuk kapıya doğru dönük
const PHONE_POS := Vector3(1.98, 1.45, -2.25)
const DOOR_CENTER := Vector3(2.1, 1.1, 0.5)
const BED_TOP := 0.5
const LAMP_SCALE := 0.75

var w: Node3D  # main.gd: malzemeler ve yardımcılar
var index := 0
var number := 14
var detailed := false  # sadece oyuncunun kendi hücresinde gölge ve toz

var door_pivot: AnimatableBody3D
var door_open := false
var door_busy := false
var door_sfx: AudioStreamPlayer3D
var door_sfx2: AudioStreamPlayer3D
var handset: Node3D
var phone_root: Node3D
var phone_jack: Node3D  # kablonun gövdeden çıktığı nokta
var cord: Node3D  # spiral kablo (telefon.gd Cord)
var cord_end: Node3D  # kablonun ahizedeki ucu (çatalda ya da oyuncunun elinde)
var handset_home := true  # ahize çatalda
var phone_sfx: AudioStreamPlayer3D
var _slip_t := -1.0
var _slip_from := Transform3D.IDENTITY
var phone_light: OmniLight3D
var ring_player: AudioStreamPlayer3D
var ringing := false
var ring_t := 0.0
var lamp_light: SpotLight3D
var lamp_fill: OmniLight3D
var bulb_mat: StandardMaterial3D
var flicker_left := 0.0
var locked := false
var moon: OmniLight3D
var dust: CPUParticles3D


# Oyuncunun kendi hücresi: gölgeler, ay ışığı ve toz açılır (telefonu yormamak için diğerlerinde kapalı).
# Kimsenin olmadığı hücre: ışık kapalı, kapı kilitli.
func lock_empty() -> void:
	locked = true
	lamp_light.visible = false
	lamp_fill.visible = false
	bulb_mat.emission_energy_multiplier = 0.0
	if mirror_light:
		mirror_light.visible = false
		mirror_bulb_mat.emission_energy_multiplier = 0.0
	set_process(false)


func set_detailed(on: bool) -> void:
	detailed = on
	lamp_light.shadow_enabled = on
	moon.visible = on
	dust.visible = on
	dust.emitting = on


func build() -> void:
	_build_room()
	w.model("modern_arm_chair_01", CHAIR_POS, CHAIR_YAW, 1.0, NAN, self)
	w.solid(Vector3(0.8, 0.9, 0.9), CHAIR_POS + Vector3(0, 0.45, 0), CHAIR_YAW, self)
	_build_bed_and_shelf()
	_build_window()
	_build_phone()
	_build_lamp()
	_build_door()
	_build_locker()
	_build_mirror()
	_decorate()
	# aynı malzemeli sabit kutular tek meshte (her mesh bir çizim çağrısı; 8 hücre koridordan görünür)
	Dunya.birlestir(self)
	Dunya.birlestir(door_pivot)


# Her hücreye farklı birkaç eşya (hücre numarasıyla tohumlanan rastgele seçim, herkes aynısını görür):
# kova, yerde kitaplar, masa ve teneke bardak, çelik tuvalet-lavabo, kağıtlar, koli, kitaplık (kitaplar, bazen
# radyo), ağırlık seti, saksı çiçeği, duvar saati. Hazır modeller Poly Haven CC0 (assets/models/LISANS.txt);
# küçük parçalar aynı malzemeyle kurulur, build() sonunda Dunya.birlestir ile tek meshte birleşir.
const PROP_RANGE := 9.0  # bu uzaklıktan sonra küçük eşyalar çizilmez (koridordan başka hücrelere bakınca)
static var _prop_mats := {}
static var _reduced_cache := {}
const BodyScript := preload("res://scripts/model_body.gd")


# Hazır modelin tek yüzeyli parçalarına kendi malzemesini "override" olarak verir: hücrenin sonundaki
# Dunya.birlestir aynı malzemeli parçaları tek meshte birleştirir (saksının 4 parçası, saatin 3 ibresi -> 1 çizim).
# lod < 1: birleşen mesh LOD'suz kalacağı için içe aktarmada üretilen daha seyrek LOD'u kullanır (üçgen oranı).
func _flat_model(holder: Node3D, lod := 1.0) -> void:
	for n in holder.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		if lod < 1.0:
			mi.mesh = _reduced(mi.mesh, lod)
		if mi.mesh.get_surface_count() == 1:
			mi.material_override = mi.mesh.surface_get_material(0)


static func _reduced(mesh: Mesh, ratio: float) -> Mesh:
	var key := "%d/%.2f" % [mesh.get_instance_id(), ratio]
	if _reduced_cache.has(key):
		return _reduced_cache[key]
	if not mesh is ArrayMesh:
		return mesh
	# her yüzey için içe aktarmada üretilmiş LOD'lardan üçgen sayısı orana en yakın olanı (yoksa yüzey aynen kalır)
	var am := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var full := (mesh as ArrayMesh).surface_get_array_index_len(si)
		var lods: Dictionary = BodyScript._lods_of(mesh, si)
		var best := PackedInt32Array()
		for k in lods:
			var idx: PackedInt32Array = lods[k]
			if best.is_empty() or absf(idx.size() - full * ratio) < absf(best.size() - full * ratio):
				best = idx
		if not best.is_empty() and best.size() < full:
			arr[Mesh.ARRAY_INDEX] = best
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(si, mesh.surface_get_material(si))
	_reduced_cache[key] = am
	return am


func _prop_mat(key: String, c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	if not _prop_mats.has(key):
		_prop_mats[key] = w._flat(c, rough, metal)
	return _prop_mats[key]


func _decorate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + index
	var tin: StandardMaterial3D = w._flat(Color("#8c8f93"), 0.45, 0.8)
	var white: StandardMaterial3D = w._flat(Color("#d9d6cf"), 0.35)
	var wood: StandardMaterial3D = w._flat(Color("#5b4630"), 0.8)
	var kinds := ["kova", "kitap", "masa", "lavabo", "kagit", "kutu", "raf", "agirlik", "saksi", "saat"]
	_posters(rng)
	_build_board()
	_build_computer()
	_build_fusebox()
	_lekeler()
	for i in kinds.size():
		var j := rng.randi_range(i, kinds.size() - 1)
		var tmp = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	var chosen: Array = kinds.slice(0, 6)
	var radio := rng.randf() < 0.65
	var props := Node3D.new()  # hazır modeller (uzakta gizlenir)
	add_child(props)
	for kind in chosen:
		match kind:
			"kova":
				var b: MeshInstance3D = w._disc(self, Vector3(-0.75, 0.16, -2.72), 0.15, 0.32, tin)
				b.rotation.x = 0.0
			"kitap":
				for k in 4:
					var bk: MeshInstance3D = w.box(Vector3(0.22, 0.04, 0.16), Vector3(-0.6, 0.02 + k * 0.042, 2.55), w._flat(Color.from_hsv(rng.randf(), 0.5, 0.45), 0.8), false, self)
					bk.rotation.y = rng.randf_range(-0.3, 0.3)
			"masa":
				w.box(Vector3(0.7, 0.04, 0.45), Vector3(1.55, 0.72, 2.6), wood, true, self)
				for x in [-0.3, 0.3]:
					for z in [-0.18, 0.18]:
						w.box(Vector3(0.04, 0.7, 0.04), Vector3(1.55 + x, 0.35, 2.6 + z), wood, false, self)
				var cup: MeshInstance3D = w._disc(self, Vector3(1.32, 0.79, 2.5), 0.04, 0.1, tin)
				cup.rotation.x = 0.0
				if radio and not "raf" in chosen:
					_flat_model(w.model("boombox", Vector3(1.62, 0.74, 2.66), PI + rng.randf_range(-0.2, 0.2), 0.55, NAN, props), 0.4)
				if "saksi" in chosen:
					_flat_model(w.model("potted_plant_04", Vector3(1.3, 0.74, 2.72), rng.randf() * TAU, 1.1, NAN, props), 0.5)
			"lavabo":
				_build_toilet_sink(Vector3(1.5, 0, -2.74), props)
			"kagit":
				for k in 5:
					var pp: MeshInstance3D = w.box(Vector3(0.18, 0.004, 0.25), Vector3(rng.randf_range(-0.8, 1.2), 0.003, rng.randf_range(0.3, 2.4)), white, false, self)
					pp.rotation.y = rng.randf() * TAU
			"kutu":
				w.box(Vector3(0.45, 0.35, 0.35), Vector3(-0.9, 0.175, 2.75), w._flat(Color("#9a7a4f"), 0.95), true, self)
			"raf":
				_build_bookshelf(rng, radio, props)
			"agirlik":
				_build_weights(rng, props)
			"saksi":
				if not "masa" in chosen:
					_flat_model(w.model("potted_plant_04", Vector3(1.7, 0, 1.3), rng.randf() * TAU, 1.5, NAN, props), 0.5)
			"saat":
				# duvar saati: sağ duvarda, kapı ile telefon arasında, yüksekte
				_flat_model(w.model("wall_clock", Vector3(1.965, 2.2, -1.05), -PI / 2, 0.85, NAN, props))
	Dunya.uzakta_gizle(props, PROP_RANGE)


# Kitaplık (Poly Haven wooden_bookshelf_worn, küçültülmüş): sağ duvara dayalı; raflarda renkli kitap sıraları
# (aynı renkteki kitaplar birleştirilir), bazen tepesinde radyo (Poly Haven boombox).
func _build_bookshelf(rng: RandomNumberGenerator, radio: bool, props: Node3D) -> void:
	const S := 0.62
	const H := 2.063 * S
	var pos := Vector3(1.78, 0, -0.98)
	_flat_model(w.model("wooden_bookshelf_worn", pos, -PI / 2, S, NAN, props), 0.5)
	w.solid(Vector3(0.38, H, 0.86), pos + Vector3(0, H * 0.5, 0), 0.0, self)
	# raf tahtalarının üst yüzeyi (yüksekliğin oranı; modelin görüntüsünden ölçüldü)
	var shelves := [0.08, 0.2, 0.325, 0.44, 0.57, 0.71]
	var cols := [Color("#7a2a22"), Color("#2c4a6b"), Color("#3f5a2e"), Color("#8a6a2a"), Color("#4a3a5e"), Color("#1f2224"), Color("#a08a62")]
	# bütün kitaplar tek mesh (renk köşelerde): tek çizim çağrısı
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for si in shelves.size():
		if rng.randf() < 0.3:
			continue
		var y: float = shelves[si] * H
		var z := -0.36
		var end := rng.randf_range(0.1, 0.36)
		while z < end:
			var bw := rng.randf_range(0.018, 0.034)
			var bh := rng.randf_range(0.085, 0.125)
			var bd := rng.randf_range(0.1, 0.13)
			var tilt := 0.22 if rng.randf() < 0.12 else 0.0  # yaslanmış kitap
			_book(st, Vector3(bd, bh, bw), pos + Vector3(0.0, y + bh * 0.5, z + bw * 0.5), tilt, cols[rng.randi() % cols.size()])
			z += bw + 0.002 + tilt * 0.12
	var books := MeshInstance3D.new()
	books.mesh = st.commit()
	if not _prop_mats.has("kitaplar"):
		var bm := StandardMaterial3D.new()
		bm.vertex_color_use_as_albedo = true
		bm.vertex_color_is_srgb = true
		bm.roughness = 0.85
		_prop_mats["kitaplar"] = bm
	books.material_override = _prop_mats["kitaplar"]
	props.add_child(books)
	if radio:
		_flat_model(w.model("boombox", pos + Vector3(-0.02, H + 0.001, 0.1), -PI / 2 + rng.randf_range(-0.25, 0.25), 0.5, NAN, props), 0.4)


# Kutu biçimli kitap (köşe renkli), x ekseni etrafında eğik olabilir.
static func _book(st: SurfaceTool, size: Vector3, c: Vector3, tilt: float, col: Color) -> void:
	var b := Basis(Vector3.RIGHT, tilt)
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for fa in faces:
		var n: Vector3 = fa[0]
		var u: Vector3 = fa[1]
		var v: Vector3 = fa[2]
		var pts := []
		for q in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			pts.append(c + b * ((n + u * q[0] + v * q[1]) * h))
		# sırt (dış yüz, -x) biraz açık: kitap sırtı
		var fc := col.lightened(0.12) if n == Vector3.LEFT else col
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(fc)
			st.set_normal(b * n)
			st.add_vertex(pts[k])


# Hapishane tipi paslanmaz çelik tuvalet-lavabo: arka gövdenin üstünde küçük lavabo ve basmalı musluk, önde klozet.
func _build_toilet_sink(p: Vector3, parent: Node3D) -> void:
	var steel := _prop_mat("celik", Color("#b7bbc0"), 0.32, 0.9)
	var dark := _prop_mat("celik_koyu", Color("#3c4044"), 0.5, 0.6)
	w.solid(Vector3(0.6, 1.05, 0.56), p + Vector3(0, 0.52, 0.08), 0.0, self)
	w.box(Vector3(0.56, 1.0, 0.2), p + Vector3(0, 0.5, -0.07), steel, false, parent)  # arka gövde
	w.box(Vector3(0.6, 0.06, 0.34), p + Vector3(0, 1.0, 0.04), steel, false, parent)  # lavabo tezgahı
	w.box(Vector3(0.36, 0.012, 0.2), p + Vector3(0, 1.027, 0.06), dark, false, parent)  # lavabo çukuru
	var tap: MeshInstance3D = w._disc(parent, p + Vector3(0, 1.07, -0.06), 0.02, 0.07, steel)
	tap.rotation.x = 0.0
	var spout: MeshInstance3D = w.box(Vector3(0.025, 0.02, 0.07), p + Vector3(0, 1.09, -0.02), steel, false, parent)
	spout.rotation.x = 0.1
	w.box(Vector3(0.42, 0.36, 0.36), p + Vector3(0, 0.18, 0.2), steel, false, parent)  # klozet gövdesi
	var rim: MeshInstance3D = w._disc(parent, p + Vector3(0, 0.38, 0.22), 0.2, 0.05, steel)
	rim.rotation.x = 0.0
	var hole: MeshInstance3D = w._disc(parent, p + Vector3(0, 0.403, 0.22), 0.14, 0.006, dark)
	hole.rotation.x = 0.0


# Ağırlık seti: yerde halter (iki yanında plakalar) ve iki dambıl (siyah plakalar, çelik çubuk).
func _build_weights(rng: RandomNumberGenerator, parent: Node3D) -> void:
	var steel := _prop_mat("celik", Color("#b7bbc0"), 0.32, 0.9)
	var plate := _prop_mat("plaka", Color("#18191b"), 0.6, 0.2)
	var root := Node3D.new()
	root.position = Vector3(0.35, 0, 2.64)  # doğma noktası (0, 1.9) önünde kalsın
	root.rotation.y = rng.randf_range(-0.25, 0.25)
	parent.add_child(root)
	w.solid(Vector3(1.3, 0.42, 0.6), root.position + Vector3(0, 0.21, -0.08), root.rotation.y, self)
	var bar: MeshInstance3D = w._disc(root, Vector3(0, 0.2, 0), 0.014, 1.3, steel)
	bar.rotation = Vector3(0, 0, PI / 2)
	for s in [-1.0, 1.0]:
		for k in 2:
			var pl: MeshInstance3D = w._disc(root, Vector3(s * (0.48 + k * 0.045), 0.2, 0), 0.2 - k * 0.04, 0.035, plate)
			pl.rotation = Vector3(0, 0, PI / 2)
		var col: MeshInstance3D = w._disc(root, Vector3(s * 0.43, 0.2, 0), 0.03, 0.03, steel)
		col.rotation = Vector3(0, 0, PI / 2)
	for d in 2:
		var c := Vector3(-0.15 + d * 0.32, 0.06, -0.27 + d * 0.05)
		var h: MeshInstance3D = w._disc(root, c, 0.012, 0.3, steel)
		h.rotation = Vector3(0, 0, PI / 2)
		for s in [-1.0, 1.0]:
			var dp: MeshInstance3D = w._disc(root, c + Vector3(s * 0.11, 0, 0), 0.06, 0.05, plate)
			dp.rotation = Vector3(0, 0, PI / 2)


# Yıpranmışlık: zeminde kir ve su lekesi, duvarda çatlak ve pas akıntısı, bazı hücrelerde duvara çizilmiş gün çentikleri.
# Lekeler (decal) "yüksek" kalitede görünür; her hücrede yerleri biraz farklı.
func _lekeler() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + index * 13
	var floor_spots := [Vector3(0.9, 0, -2.3), Vector3(1.3, 0, 1.6), Vector3(-0.6, 0, 0.6), Vector3(0.4, 0, -0.4), Vector3(-0.9, 0, 2.2)]
	for i in 3:
		var s: Vector3 = floor_spots[(index + i * 2) % floor_spots.size()]
		Dunya.leke_zemin(self, "kir", s + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)), Vector2(1.3, 1.0) * rng.randf_range(0.8, 1.3), rng.randf() * TAU, Color(1, 1, 1, 0.75))
	# kapı önü ve boru dibinde ıslaklık
	Dunya.leke_zemin(self, "su", Vector3(1.55, 0, 0.5), Vector2(0.9, 0.7), rng.randf() * TAU)
	if index % 2 == 0:
		Dunya.leke_zemin(self, "su", Vector3(1.6, 0, -2.6), Vector2(0.8, 0.6), rng.randf() * TAU)
	Dunya.leke_zemin(self, "catlak", Vector3(rng.randf_range(-0.6, 0.8), 0, rng.randf_range(-0.5, 1.8)), Vector2(1.2, 1.2), rng.randf() * TAU, Color(1, 1, 1, 0.8))
	Dunya.leke_duvar(self, "pas", Vector3(1.55, H - 0.35, -2.985), Vector3.BACK, Vector2(0.55, 1.7))
	Dunya.leke_duvar(self, "catlak", Vector3(-1.985, 2.3, -1.4 + rng.randf_range(-0.3, 0.3)), Vector3.RIGHT, Vector2(1.0, 1.0), Color(1, 1, 1, 0.7))
	Dunya.leke_duvar(self, "catlak", Vector3(rng.randf_range(-1.2, 0.6), 2.55, 2.985), Vector3.FORWARD, Vector2(0.9, 0.9), Color(1, 1, 1, 0.6))
	if index % 3 != 1:
		var tally := Label3D.new()
		var n := 4 + (index * 7) % 9
		var t := ""
		for k in n:
			t += "I" if (k + 1) % 5 != 0 else "/  "
		tally.text = t.strip_edges()
		tally.font = CHALK_FONT
		tally.font_size = 46
		tally.pixel_size = 0.0016
		tally.modulate = Color(0.85, 0.83, 0.78, 0.55)
		tally.outline_size = 0
		tally.position = Vector3(-1.976, 1.05, -2.45)
		tally.rotation.y = PI / 2
		add_child(tally)


const POSTERS := ["sahil", "araba", "boks", "aranan", "takvim", "harita", "uzay", "kedi", "dag", "konser", "futbol", "motor"]


# Duvara bantlanmış 1-2 poster (her hücrede farklı), hafif yamuk.
func _posters(rng: RandomNumberGenerator) -> void:
	# arka duvar (tahtanın solu) her hücrede; ön duvar (kapının iç yanı, ağırlıkların üstü) her iki hücreden birinde
	var spots := [Vector3(-1.45, 1.75, -2.985), Vector3(0.3, 1.85, 2.985)]
	var first := (index * 5) % POSTERS.size()
	for k in (2 if index % 2 == 0 else 1):
		var tex: Texture2D = load("res://assets/poster/poster_%s.png" % POSTERS[(first + k * 6) % POSTERS.size()])
		if not tex:
			continue
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.5 * tex.get_height() / tex.get_width())
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.roughness = 0.9
		mi.material_override = mat
		mi.position = spots[k] + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.08, 0.08), 0)
		mi.rotation.z = rng.randf_range(-0.06, 0.06)
		if k == 1:
			mi.rotation.y = PI  # ön duvar: içeri bakar
		add_child(mi)


const BOARD_POS := Vector3(0.35, 1.68, -2.97)
const CHALK_FONT := preload("res://assets/fonts/CabinSketch-Bold.ttf")
var board_label: Label3D


# Arka duvarda yeşil tebeşir tahtası (Kara Tahta oyunu): yazdığın kelime tebeşirle görünür.
func _build_board() -> void:
	var tex: Texture2D = load("res://assets/ui/chalkboard.png") if ResourceLoader.exists("res://assets/ui/chalkboard.png") else null
	var wdt := 1.55
	if tex:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(wdt, wdt * tex.get_height() / float(tex.get_width()))
		q.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.roughness = 0.9
		q.material_override = mat
		q.position = BOARD_POS
		add_child(q)
	else:
		w.box(Vector3(wdt, 1.0, 0.04), BOARD_POS, w._flat(Color("#5a3a20"), 0.8), false, self)
		w.box(Vector3(wdt - 0.12, 0.88, 0.05), BOARD_POS + Vector3(0, 0, 0.01), w._flat(Color("#2e5a3c"), 0.95), false, self)
	board_label = Label3D.new()
	board_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # oyuncunun yazdığı kelime çevrilmesin; yazanlar zaten dilinde verir
	board_label.font = CHALK_FONT
	board_label.font_size = 150
	board_label.pixel_size = 0.0018
	board_label.modulate = Color(0.95, 0.96, 0.9, 0.92)
	board_label.outline_size = 0
	board_label.shaded = false
	board_label.width = 700
	board_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board_label.position = BOARD_POS + Vector3(0, 0.02, 0.03)
	add_child(board_label)


var _board_tween: Tween
var _chalk_sfx: AudioStreamPlayer3D


# Tahtaya tebeşirle yazılıyormuş gibi: harfler tek tek belirir, her harfte tebeşir sesi.
func set_board_text(t: String) -> void:
	if not board_label:
		return
	if _board_tween:
		_board_tween.kill()
	if t == "":
		board_label.text = ""
		return
	if not _chalk_sfx:
		_chalk_sfx = AudioStreamPlayer3D.new()
		var r := AudioStreamRandomizer.new()
		for i in 3:
			r.add_stream(-1, load("res://assets/ses/tebesir_%d.ogg" % (i + 1)))
		r.random_pitch = 1.15
		_chalk_sfx.stream = r
		_chalk_sfx.position = BOARD_POS
		_chalk_sfx.unit_size = 3.0
		add_child(_chalk_sfx)
	board_label.text = ""
	var multi := t.contains("
")
	board_label.font_size = 64 if multi else 150
	board_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if multi else HORIZONTAL_ALIGNMENT_CENTER
	_board_tween = create_tween()
	var per := 0.035 if multi else 0.16
	for i in t.length():
		_board_tween.tween_callback(func() -> void:
			board_label.text = t.substr(0, i + 1)
			if not multi or i % 4 == 0:
				_chalk_sfx.play())
		_board_tween.tween_interval(per)


# Süre bitti: lamba bir an söner, titreyip geri yanar.
func flicker() -> void:
	var lights: Array[Light3D] = []
	for l in [lamp_light, lamp_fill]:
		if l and l.visible:
			lights.append(l)
	var tw := create_tween()
	for step in [[false, 0.09], [true, 0.06], [false, 0.35], [true, 0.08], [false, 0.12], [true, 0.0]]:
		tw.tween_callback(func() -> void:
			for l in lights:
				l.visible = step[0])
		if step[1] > 0.0:
			tw.tween_interval(step[1])


const PC_POS := Vector3(-1.62, 0.0, 1.05)


# Sol duvarın önünde eski metal ofis masası ve üstünde eski dizüstü bilgisayar (Poly Haven, CC0).
# Ekranında "NASIL OYNANIR?" yanıp söner; tıklayınca oyunu kısaca anlatır.
var pc_screen_pos := Vector3.ZERO


func _build_computer() -> void:
	var p := PC_POS
	var desk: Node3D = w.model("metal_office_desk", p, PI / 2, 1.0, NAN, self)
	var db: AABB = w._bounds(desk, self)
	w.solid(db.size, db.get_center(), 0.0, self)
	var top := db.end.y
	var laptop: Node3D = w.model("classic_laptop", Vector3(p.x + 0.05, top, p.z), PI / 2, 1.0, NAN, self)
	var lb: AABB = w._bounds(laptop, self)
	pc_screen_pos = Vector3(lb.position.x + lb.size.x * 0.3, lb.position.y + lb.size.y * 0.62, lb.get_center().z)
	var txt := Label3D.new()
	txt.text = "NASIL
OYNANIR?"
	txt.font = CHALK_FONT
	txt.font_size = 48
	txt.pixel_size = 0.0009
	txt.modulate = Color("#7dff9f")
	txt.outline_size = 0
	txt.shaded = false
	txt.position = pc_screen_pos + Vector3(0.02, 0, 0)
	txt.rotation.y = PI / 2
	add_child(txt)
	var blink := txt.create_tween().set_loops()
	blink.tween_property(txt, "modulate:a", 0.35, 0.7)
	blink.tween_property(txt, "modulate:a", 1.0, 0.7)
	var glow := OmniLight3D.new()
	glow.light_color = Color("#3cff7a")
	glow.light_energy = 0.15
	glow.omni_range = 1.0
	glow.light_cull_mask = 1  # yalnız dünyayı boyar; karakterlerin yüzü yeşile dönmesin
	glow.position = pc_screen_pos + Vector3(0.25, 0, 0)
	add_child(glow)


# ---------- Kısa Devre: sigorta kutusu ve acil durum ışığı ----------

const FUSE_POS := Vector3(1.97, 1.5, 1.85)  # sağ duvar, kapının arkasında
var power := true
var emergency: OmniLight3D
var emergency_t := 0.0
var fuse_state := "normal"
var fuse_door: Node3D  # modelin kapağı (power_box_01_door); kapalıyken dönüşü 0
var fuse_sign: Label3D
var fuse_lamp: MeshInstance3D
var fuse_lamp_mat: StandardMaterial3D
var _fuse_tw: Tween
var _door_plain: BaseMaterial3D  # etiketsiz kapak malzemesi (oyun dışı)
const FUSE_AJAR := -0.62  # kesintide kapak aralanır (radyan)
var fuse_sparks: CPUParticles3D
var fuse_sfx: AudioStreamPlayer3D


func _build_fusebox() -> void:
	var p := FUSE_POS
	# gerçek elektrik panosu modeli (Poly Haven "Power Box 01", CC0), sağ duvarda odaya bakar
	var box: Node3D = w.model("power_box_01", Vector3(p.x, 0, p.z), -PI / 2, 1.0, NAN, self)
	# oyun dışında kutu KAPALI ve sıradan durur (oyuncular Kısa Devre'yi önceden sezmesin)
	fuse_door = box.find_child("power_box_01_door", true, false) as Node3D
	if fuse_door:
		fuse_door.rotation = Vector3.ZERO
		# kapaktaki yıldırım etiketi yalnızca kesintide görünür: sakin hâlde etiketsiz doku
		var dm := fuse_door as MeshInstance3D
		if dm and dm.get_active_material(0) is BaseMaterial3D:
			_door_plain = (dm.get_active_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
			_door_plain.albedo_texture = load("res://assets/models/power_box_01/textures/power_box_01_diff_temiz.jpg")
			dm.material_override = _door_plain
	var bb: AABB = w._bounds(box, self)
	# duvara yasla ve göz hizasına kaldır
	box.position.x += 2.0 - bb.end.x
	box.position.y += p.y - bb.get_center().y
	bb = w._bounds(box, self)
	if not fuse_door:
		fuse_door = Node3D.new()  # kapak bulunamazsa boş düğüm (kod çalışmaya devam eder)
		add_child(fuse_door)
	var sign := Label3D.new()
	sign.text = "YÜKSEK GERİLİM"
	sign.font_size = 40
	sign.pixel_size = 0.0012
	sign.modulate = Color("#ffcf3a")
	sign.outline_size = 6
	sign.position = Vector3(bb.position.x - 0.005, bb.end.y + 0.06, bb.get_center().z)
	sign.rotation.y = -PI / 2
	sign.visible = false  # uyarı yazısı yalnızca kesintide görünür
	add_child(sign)
	fuse_sign = sign
	p = Vector3(bb.position.x, bb.get_center().y, bb.get_center().z)
	# durum lambası
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.025
	lm.height = 0.05
	lamp.mesh = lm
	fuse_lamp_mat = StandardMaterial3D.new()
	fuse_lamp_mat.albedo_color = Color("#2a9d4b")
	fuse_lamp_mat.emission_enabled = true
	fuse_lamp_mat.emission = Color("#3cff7a")
	fuse_lamp_mat.emission_energy_multiplier = 1.5
	lamp.material_override = fuse_lamp_mat
	lamp.position = Vector3(p.x - 0.02, p.y + 0.27, p.z + 0.15)
	lamp.visible = false
	add_child(lamp)
	fuse_lamp = lamp
	# kıvılcımlar
	fuse_sparks = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.006)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_color = Color(1.0, 0.85, 0.4)
	q.material = sm
	fuse_sparks.mesh = q
	fuse_sparks.amount = 40
	fuse_sparks.lifetime = 0.6
	fuse_sparks.explosiveness = 0.6
	fuse_sparks.direction = Vector3(-1, 0.5, 0)
	fuse_sparks.spread = 50.0
	fuse_sparks.initial_velocity_min = 0.8
	fuse_sparks.initial_velocity_max = 1.4
	fuse_sparks.gravity = Vector3(0, -6, 0)
	fuse_sparks.position = p + Vector3(-0.04, 0.0, 0)
	fuse_sparks.emitting = false
	add_child(fuse_sparks)
	fuse_sfx = AudioStreamPlayer3D.new()
	fuse_sfx.position = p
	fuse_sfx.unit_size = 2.5
	add_child(fuse_sfx)
	# kırmızı acil durum ışığı (elektrik gidince)
	emergency = OmniLight3D.new()
	emergency.light_color = Color("#ff2a1a")
	emergency.omni_range = 6.5
	emergency.position = Vector3(0, H - 0.3, 0)
	emergency.visible = false
	add_child(emergency)


func fuse_world() -> Vector3:
	return to_global(FUSE_POS)


# Elektrik: kapalıyken lamba söner, kırmızı acil durum ışığı nabız gibi yanar.
func set_power(on: bool) -> void:
	power = on
	if emergency:
		emergency.visible = not on
	bulb_mat.emission_energy_multiplier = 6.0 if on else 0.0
	if mirror_light and not locked:
		mirror_light.visible = on
		mirror_bulb_mat.emission_energy_multiplier = 1.5 if on else 0.0


# Sigorta: normal (kapalı, sade, uyarısız), bozuk (kapak aralanır, uyarı, kıvılcım, cızırtı),
# tamir (yeşil), kilit (kırmızı, yanık). Oyun bitince yeniden "normal": kapak kapanır, her şey söner.
func set_fuse(state: String) -> void:
	var was := fuse_state
	fuse_state = state
	if not fuse_door:
		return
	fuse_sparks.emitting = state == "bozuk"
	var alarm := state != "normal"
	fuse_sign.visible = alarm
	if fuse_door is MeshInstance3D and _door_plain:
		(fuse_door as MeshInstance3D).material_override = null if alarm else _door_plain
	fuse_lamp.visible = alarm
	if _fuse_tw:
		_fuse_tw.kill()
		_fuse_tw = null
	# kapak zaten aralıksa (ör. bozuk -> tamir) yeni hareket yok: boş Tween "started with no Tweeners" hatası verir
	var oynar := (state == "bozuk" and was == "normal") or state == "normal" or fuse_door.rotation.y > FUSE_AJAR * 0.5
	if oynar:
		_fuse_tw = create_tween()
	if state == "bozuk" and was == "normal":
		# kapak patlarcasına aralanır, biraz sekip durur
		Sfx.tek3d(self, fuse_sfx.position, "sigorta_ac", -2.0, 2.5)
		_fuse_tw.tween_property(fuse_door, "rotation:y", FUSE_AJAR, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	elif state == "normal":
		if was != "normal":
			get_tree().create_timer(0.5).timeout.connect(Sfx.tek3d.bind(self, fuse_sfx.position, "sigorta_kapa", -2.0, 2.5))
		_fuse_tw.tween_property(fuse_door, "rotation:y", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif fuse_door.rotation.y > FUSE_AJAR * 0.5:
		_fuse_tw.tween_property(fuse_door, "rotation:y", FUSE_AJAR, 0.3)
	match state:
		"bozuk":
			fuse_lamp_mat.emission = Color("#ff2a1a")
			fuse_lamp_mat.albedo_color = Color("#d62828")
			var cr: AudioStreamOggVorbis = load("res://assets/ses/cizirti.ogg")
			cr.loop = true
			fuse_sfx.stream = cr
			fuse_sfx.volume_db = -6.0
			fuse_sfx.play()
		"tamir":
			fuse_lamp_mat.emission = Color("#3cff7a")
			fuse_lamp_mat.albedo_color = Color("#2a9d4b")
			fuse_lamp_mat.emission_energy_multiplier = 4.0
			fuse_sfx.stop()
		"kilit":
			fuse_lamp_mat.emission = Color("#ff2a1a")
			fuse_lamp_mat.emission_energy_multiplier = 5.0
			fuse_sfx.stop()
			# son bir kıvılcım patlaması
			fuse_sparks.amount = 80
			fuse_sparks.one_shot = true
			fuse_sparks.emitting = true
		"normal":
			fuse_lamp_mat.emission = Color("#3cff7a")
			fuse_lamp_mat.emission_energy_multiplier = 1.5
			fuse_sfx.stop()


# Şalter kalktı: önce kutunun lambası yeşile döner, sonra hücre ışıkları cızırdayıp tek tek yanar.
func power_on_sequence() -> void:
	set_fuse("tamir")
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_callback(func() -> void: set_power(true))
	tw.tween_interval(0.08)
	tw.tween_callback(func() -> void: set_power(false))
	tw.tween_interval(0.18)
	tw.tween_callback(func() -> void: set_power(true))
	tw.tween_interval(0.06)
	tw.tween_callback(func() -> void: set_power(false))
	tw.tween_interval(0.12)
	tw.tween_callback(func() -> void: set_power(true))


func pc_world() -> Vector3:
	return to_global(pc_screen_pos)


func board_world() -> Vector3:
	return to_global(BOARD_POS)


func chair_world() -> Vector3:
	return to_global(CHAIR_POS)


func phone_world() -> Vector3:
	return to_global(PHONE_POS)


func door_world() -> Vector3:
	return to_global(DOOR_CENTER)


func spawn_world() -> Vector3:
	return to_global(Vector3(0.0, 0.0, 1.9))


func _build_room() -> void:
	var t := 0.2
	var m: Dictionary = w.mats
	w.box(Vector3(4.4, t, 6.4), Vector3(0, -t / 2, 0), m.floor, true, self)
	w.box(Vector3(4.4, t, 6.4), Vector3(0, H + t / 2, 0), m.ceiling, true, self)
	w.box(Vector3(4.4, H, t), Vector3(0, H / 2, -3.1), m.wall, true, self)
	w.box(Vector3(4.4, H, t), Vector3(0, H / 2, 3.1), m.wall, true, self)
	w.box(Vector3(t, H, 6.4), Vector3(-2.1, H / 2, 0), m.wall, true, self)
	# sağ duvar: z 0..1 arası kapı boşluğu
	w.box(Vector3(t, H, 3.2), Vector3(2.1, H / 2, -1.6), m.wall, true, self)
	w.box(Vector3(t, H, 2.2), Vector3(2.1, H / 2, 2.1), m.wall, true, self)
	w.box(Vector3(t, H - 2.2, 1.0), Vector3(2.1, 2.2 + (H - 2.2) / 2, 0.5), m.wall, true, self)
	# alt yarısı yeşil boyalı (her hücrede boya tonu biraz farklı), üstünde koyu şerit
	var b := 1.25
	var paint: Material = [m.paint, m.paint_b, m.paint_c][index % 3]
	for pw in [[Vector3(4.0, 0, 0.02), Vector3(0, 0, -2.99)], [Vector3(4.0, 0, 0.02), Vector3(0, 0, 2.99)],
			[Vector3(0.02, 0, 6.0), Vector3(-1.99, 0, 0)], [Vector3(0.02, 0, 3.0), Vector3(1.99, 0, -1.5)],
			[Vector3(0.02, 0, 2.0), Vector3(1.99, 0, 2.0)]]:
		var sz: Vector3 = pw[0]
		var ps: Vector3 = pw[1]
		# ince levha: üst yüzü lamba altında parlayıp kırpışmasın (ön yüz yine aynı yerde)
		var inward := Vector3(-signf(ps.x), 0, 0) if sz.x < 0.1 else Vector3(0, 0, -signf(ps.z))
		var thin := Vector3(0.006 if sz.x < 0.1 else sz.x, 0, 0.006 if sz.z < 0.1 else sz.z)
		w.box(Vector3(thin.x, b, thin.z), ps + inward * 0.007 + Vector3(0, b / 2, 0), paint, false, self)
		w.box(Vector3(thin.x + (0.004 if sz.x < 0.1 else 0.0), 0.05, thin.z + (0.004 if sz.z < 0.1 else 0.0)), ps + inward * 0.009 + Vector3(0, b, 0), m.stripe, false, self)
	# kapı kasası
	for z in [0.0, 1.0]:
		w.box(Vector3(0.24, 2.25, 0.07), Vector3(2.1, 1.12, z), m.metal_dark, false, self)
	w.box(Vector3(0.24, 0.07, 1.07), Vector3(2.1, 2.22, 0.5), m.metal_dark, false, self)
	# koridordan görünen hücre numarası: koyu plaka üstünde şablon yazı
	w.box(Vector3(0.02, 0.22, 0.4), Vector3(2.212, 2.66, 0.5), m.stripe, false, self)
	var l := Label3D.new()
	l.text = str(number)
	l.font = Dunya.STENCIL_FONT
	l.font_size = 96
	l.pixel_size = 0.0016
	l.modulate = Color("#e6d8b4")
	l.outline_size = 0
	l.position = Vector3(2.225, 2.66, 0.5)
	l.rotation.y = PI / 2
	add_child(l)
	# duvarlar arkasındaki hücreler çizilmesin (telefonda büyük kazanç): kutu gölgeleyiciler
	for oc in [[Vector3(4.4, H, 0.1), Vector3(0, H / 2, -3.1)], [Vector3(4.4, H, 0.1), Vector3(0, H / 2, 3.1)],
			[Vector3(0.1, H, 6.4), Vector3(-2.1, H / 2, 0)], [Vector3(0.1, H, 3.2), Vector3(2.1, H / 2, -1.6)],
			[Vector3(0.1, H, 2.2), Vector3(2.1, H / 2, 2.1)], [Vector3(0.1, H - 2.2, 1.0), Vector3(2.1, 2.2 + (H - 2.2) / 2, 0.5)]]:
		var oi := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = oc[0]
		oi.occluder = bo
		oi.position = oc[1]
		add_child(oi)
	# sahte ortam gölgesi: duvar dipleri, tavan ve dikey köşeler koyulaşır (tek ağ)
	Dunya.ao_ag(self, Dunya.oda_ao_kenarlari(Vector3(-1.98, 0, -2.98), Vector3(1.98, H, 2.98), 0.38, 0.5, [[-0.05, 1.05]]), 0.55)
	# tavanda boru: arka duvar boyunca, köşeden yere inen ince boru; altında pas akıntısı
	Dunya.boru(self, Vector3(-2.0, H - 0.2, -2.86), Vector3(2.0, H - 0.2, -2.86), 0.055, m.pipe)
	Dunya.boru(self, Vector3(1.9, 0.0, -2.9), Vector3(1.9, H - 0.2, -2.9), 0.035, m.pipe)
	var clamp_mesh := BoxMesh.new()
	clamp_mesh.size = Vector3(0.05, 0.05, 0.16)
	var cl: Array = []
	for x in [-1.3, 0.0, 1.3]:
		cl.append(Transform3D(Basis(), Vector3(x, H - 0.2, -2.93)))
	Dunya.coklu(self, clamp_mesh, m.metal_dark, cl)


func _build_bed_and_shelf() -> void:
	var m: Dictionary = w.mats
	w.model("old_bed_frame", Vector3(-1.5, 0, -1.95), 0.0, 1.0, NAN, self)
	w.solid(Vector3(0.9, 0.55, 2.0), Vector3(-1.5, 0.27, -1.95), 0.0, self)
	w.box(Vector3(0.8, 0.12, 1.85), Vector3(-1.5, BED_TOP, -1.95), m.mattress, false, self)
	# battaniye rengi hücreden hücreye değişir (gri, haki, lacivert, kahve)
	var blanket: Material = m.blanket
	if index % 4 != 0:
		blanket = w._surface([Color("#5a5a3c"), Color("#2f3a4e"), Color("#5a3f2e")][index % 4 - 1], 1.0, 1.5, 10 + index)
	w.box(Vector3(0.84, 0.05, 1.2), Vector3(-1.5, BED_TOP + 0.075, -1.55), blanket, false, self)
	var pillow: MeshInstance3D = w.box(Vector3(0.55, 0.1, 0.35), Vector3(-1.5, BED_TOP + 0.1, -2.6), m.mattress, false, self)
	pillow.rotation.y = deg_to_rad(4)
	w.model("Shelf_01", Vector3(-1.35, 0, 2.85), PI, 0.85, NAN, self)
	w.solid(Vector3(0.9, 1.8, 0.25), Vector3(-1.35, 0.9, 2.85), 0.0, self)


func _build_window() -> void:
	var p := Vector3(-1.99, 2.45, 0.9)
	w.box(Vector3(0.03, 0.55, 0.8), p, w.glow_window, false, self)
	for i in 5:
		w.box(Vector3(0.05, 0.6, 0.03), p + Vector3(0.03, 0, -0.32 + i * 0.16), w.mats.metal_dark, false, self)
	moon = OmniLight3D.new()
	moon.light_color = Color("#7f9fd0")
	moon.light_energy = 0.5
	moon.omni_range = 3.0
	moon.position = p + Vector3(0.4, -0.2, 0)
	moon.visible = detailed
	add_child(moon)
	# pencereden süzülen soğuk ay ışığı huzmesi (ışık hesabı yok, sadece görüntü)
	var shaft: MeshInstance3D = Dunya.huzme(self, p + Vector3(0.05, 0, 0), 2.6, 0.3, 0.75, Color("#6f8fc4"), 0.09, null, Vector3(1.0, -0.75, 0.15))
	shaft.reparent(moon)


func _build_phone() -> void:
	# gerçekçi duvar telefonu (telefon.gd): kalıp gövde, çevirmeli kadran, çataldaki ahize, spiral kablo
	var d: Dictionary = Telefon.build(self)
	phone_root = d.root
	phone_root.position = PHONE_POS
	phone_root.rotation.y = -PI / 2
	handset = d.handset
	phone_jack = d.jack
	cord = Telefon.Cord.new()
	add_child(cord)
	cord_end = handset.get_node("kablo_ucu")
	phone_light = OmniLight3D.new()
	phone_light.light_color = Color("#ff5a2a")
	phone_light.light_energy = 0.0
	phone_light.omni_range = 2.2
	phone_light.position = PHONE_POS + Vector3(-0.6, 0.15, 0)
	add_child(phone_light)
	ring_player = AudioStreamPlayer3D.new()
	ring_player.stream = w.ring_stream
	ring_player.position = PHONE_POS
	ring_player.unit_size = 4.0
	add_child(ring_player)
	phone_sfx = AudioStreamPlayer3D.new()
	phone_sfx.position = PHONE_POS
	phone_sfx.unit_size = 3.0
	add_child(phone_sfx)
	_update_cord.call_deferred()


func _build_lamp() -> void:
	var p := Vector3(0, H, CHAIR_POS.z + 0.2)
	var lamp: Node3D = w.model("hanging_industrial_lamp", Vector3(p.x, 0, p.z), 0.0, LAMP_SCALE, H, self)
	var lamp_bottom: float = H - w._bounds(lamp, lamp).size.y
	bulb_mat = w._glow(Color("#ffd27a"), 6.0)
	var bulb := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.06
	bs.height = 0.12
	bulb.mesh = bs
	bulb.material_override = bulb_mat
	bulb.position = Vector3(p.x, lamp_bottom + 0.1, p.z)
	add_child(bulb)
	p.y = lamp_bottom - 0.04

	lamp_light = SpotLight3D.new()
	lamp_light.light_color = Color("#ffc46b")
	lamp_light.light_energy = 5.5
	lamp_light.spot_range = 7.0
	lamp_light.spot_angle = 62.0
	lamp_light.spot_attenuation = 0.8
	lamp_light.shadow_enabled = detailed
	lamp_light.position = p
	lamp_light.rotation.x = -PI / 2
	add_child(lamp_light)
	lamp_fill = OmniLight3D.new()
	lamp_fill.light_color = Color("#ffb860")
	lamp_fill.light_energy = 0.45
	lamp_fill.omni_range = 6.0
	lamp_fill.position = p - Vector3(0, 0.24, 0)
	lamp_fill.omni_range = 7.5
	lamp_fill.omni_attenuation = 0.55  # hücrenin kapı tarafı da zifiri karanlık kalmasın
	add_child(lamp_fill)
	# ampul parıltısı ve lambanın altında tozlu ışık konisi (lamba titreyince/sönünce onlar da söner)
	Dunya.halo(self, Vector3(p.x, lamp_bottom + 0.06, p.z), Color("#ffc070"), 0.8, 0.4, lamp_light)
	Dunya.huzme(self, Vector3(p.x, lamp_bottom + 0.02, p.z), 2.7, 0.16, 1.35, Color("#ffb45c"), 0.11, lamp_light)

	if true:
		# ışıkta uçuşan toz (sadece oyuncunun kendi hücresinde açık)
		dust = CPUParticles3D.new()
		dust.visible = detailed
		dust.emitting = detailed
		var q := QuadMesh.new()
		q.size = Vector2(0.007, 0.007)
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_color = Color(1.0, 0.86, 0.6, 0.35)
		q.material = dm
		dust.mesh = q
		dust.amount = 40
		dust.lifetime = 10.0
		dust.preprocess = 10.0
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		dust.emission_box_extents = Vector3(1.1, 1.2, 1.1)
		dust.gravity = Vector3(0, -0.01, 0)
		dust.initial_velocity_min = 0.01
		dust.initial_velocity_max = 0.05
		dust.direction = Vector3(0, 1, 0)
		dust.spread = 180.0
		dust.position = Vector3(0, 1.4, CHAIR_POS.z + 0.2)
		add_child(dust)


func _build_door() -> void:
	var m: Dictionary = w.mats
	# menteşe noktasının kendisi hareketli gövde; döndükçe çarpışması da döner
	door_pivot = AnimatableBody3D.new()
	door_pivot.sync_to_physics = false
	door_pivot.position = Vector3(2.1, 0, 0.0)
	add_child(door_pivot)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.08, 2.2, 0.98)
	cs.shape = sh
	cs.position = Vector3(0, 1.1, 0.5)
	door_pivot.add_child(cs)
	w.box(Vector3(0.08, 2.18, 0.98), Vector3(0, 1.1, 0.5), m.door, false, door_pivot)
	# kapı da gölgeleyici (kapıyla birlikte döner): kapalı kapılı hücrelerin içi koridordan çizilmez
	# (koridor boyunca bakınca ~700 çizim çağrısı kapı aralığından görünen hücre içlerinden geliyordu)
	var door_oc := OccluderInstance3D.new()
	var door_box := BoxOccluder3D.new()
	door_box.size = Vector3(0.06, 2.16, 0.96)
	door_oc.occluder = door_box
	door_oc.position = Vector3(0, 1.1, 0.5)
	door_pivot.add_child(door_oc)
	for y in [0.25, 1.1, 1.95]:
		w.box(Vector3(0.1, 0.05, 0.98), Vector3(0, y, 0.5), m.metal_dark, false, door_pivot)
	w.box(Vector3(0.1, 0.36, 0.42), Vector3(0, 1.62, 0.5), m.door_window, false, door_pivot)
	for i in 4:
		w.box(Vector3(0.12, 0.36, 0.025), Vector3(0, 1.62, 0.34 + i * 0.105), m.metal_dark, false, door_pivot)
	w.box(Vector3(0.1, 0.07, 0.36), Vector3(0, 1.0, 0.5), m.metal_dark, false, door_pivot)
	w.box(Vector3(0.14, 0.05, 0.12), Vector3(0, 1.1, 0.9), m.dial, false, door_pivot)
	door_sfx = AudioStreamPlayer3D.new()
	door_sfx.position = DOOR_CENTER
	door_sfx.unit_size = 4.0
	add_child(door_sfx)
	door_sfx2 = AudioStreamPlayer3D.new()
	door_sfx2.position = DOOR_CENTER
	door_sfx2.unit_size = 4.0
	add_child(door_sfx2)


func set_door(open: bool, instant := false) -> void:
	if open == door_open:
		return
	door_open = open
	if instant:
		door_pivot.rotation.y = deg_to_rad(100.0) if open else 0.0
		return
	door_busy = true
	# gerçek kayıtlar: açarken kilit sonra gıcırtı, kapatırken ağır metal çarpma sonra kilit tıkı
	door_sfx.stream = w.snd_latch if open else w.snd_slam
	door_sfx.play()
	door_sfx2.stream = w.snd_creak if open else w.snd_click
	# kapanışta kilit tıkı çarpmadan sonra (kapi_carp.ogg'da çarpma 0.72 sn'de, kapı 0.8 sn'de kapanır)
	get_tree().create_timer(0.18 if open else 0.84).timeout.connect(door_sfx2.play)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(door_pivot, "rotation:y", deg_to_rad(100.0) if open else 0.0, 0.8)
	tw.tween_callback(func() -> void: door_busy = false)


func set_ringing(on: bool) -> void:
	if on == ringing:
		return
	ringing = on
	ring_t = 0.0
	if on:
		ring_player.play()
	else:
		ring_player.stop()
		if handset_home:
			handset.transform = Transform3D.IDENTITY
		phone_light.light_energy = 0.0


# Ahizenin çataldaki dünya duruşu (oyuncunun eli buraya uzanır, ahize buraya geri konur).
func handset_rest_world() -> Transform3D:
	return (handset.get_parent() as Node3D).global_transform


# Ahize kalktı (holder: artık elde tutulan ahize düğümü; kablo ona bağlanır) ya da çatala kondu.
func set_handset_lifted(lifted: bool, holder: Node3D = null) -> void:
	_slip_t = -1.0
	if lifted:
		handset_home = false
		handset.visible = false
		var end: Node3D = holder.get_node_or_null("kablo_ucu") if holder else null
		cord_end = end if end else handset.get_node("kablo_ucu")
		_phone_snd("catal", -4.0)
	else:
		var was_home := handset_home
		handset_home = true
		handset.visible = true
		handset.transform = Transform3D.IDENTITY
		cord_end = handset.get_node("kablo_ucu")
		if not was_home:
			_phone_snd("klak", 0.0)
	_update_cord()


# Ahize elden kaydı (kablo çok gerildi / hücreden çıkıldı): kablonun çekmesiyle sallanarak çatala geri çarpar.
func slip_handset(from_world: Transform3D) -> void:
	handset_home = false
	handset.visible = true
	_slip_from = handset_rest_world().affine_inverse() * from_world.orthonormalized()
	_slip_t = 0.0
	cord_end = handset.get_node("kablo_ucu")


func _phone_snd(id: String, db: float) -> void:
	phone_sfx.stream = Telefon.sound(id)
	phone_sfx.volume_db = db
	phone_sfx.play()


func _update_cord() -> void:
	if is_instance_valid(cord) and is_instance_valid(phone_jack) and is_instance_valid(cord_end):
		cord.update(phone_jack.global_position, cord_end.global_position)


# Telefonun her karesi: çalarken ahize çatalda titrer ve ışık yanıp söner; kayan ahize çatala döner; kablo örülür.
func _process_phone(delta: float) -> void:
	if ringing:
		ring_t += delta
		var on := fmod(ring_t, 3.0) < 1.05
		if handset_home:
			handset.transform = Transform3D(Basis(Vector3.BACK, sin(ring_t * 70.0) * 0.05 if on else 0.0), Vector3(0, absf(sin(ring_t * 70.0)) * 0.003 if on else 0.0, 0))
		phone_light.light_energy = (0.7 + sin(ring_t * 40.0) * 0.25) if on else 0.12
	if _slip_t >= 0.0:
		# yerçekimi + kablonun çekişi: önce aşağı sarkar, sonra kablo toplanırken çatala çarpar
		_slip_t += delta
		var k := clampf(_slip_t / 0.55, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var sag := sin(k * PI) * 0.25
		var q := _slip_from.basis.get_rotation_quaternion().slerp(Quaternion.IDENTITY, e)
		handset.transform = Transform3D(Basis(q), _slip_from.origin * (1.0 - e) + Vector3.DOWN * sag)
		if k >= 1.0:
			_slip_t = -1.0
			set_handset_lifted(false)
			_phone_snd("klak", 3.0)
	if handset.visible or not handset_home:
		_update_cord()


func _process(delta: float) -> void:
	_process_phone(delta)
	# lamba ara sıra titrer
	if flicker_left <= 0.0 and randf() < delta * 0.12:
		flicker_left = randf_range(0.2, 0.5)
	var k := 1.0
	if flicker_left > 0.0:
		flicker_left -= delta
		k = 0.15 if randf() < 0.5 else 1.0
	if not power:
		k = 0.0
		emergency_t += delta
		if emergency:
			emergency.light_energy = 1.1 + sin(emergency_t * 3.2) * 0.7
	if fuse_lamp_mat and fuse_state == "bozuk":
		fuse_lamp_mat.emission_energy_multiplier = 4.0 if fmod(emergency_t * 2.0, 1.0) < 0.5 else 0.3
	lamp_light.light_energy = 5.5 * k
	lamp_fill.light_energy = 0.45 * k
	bulb_mat.emission_energy_multiplier = 6.0 * k


# ---------- dolap (Yalancı oyunu: içinde bir eşya) ----------

const LOCKER_POS := Vector3(-1.76, 0.0, -0.22)  # sol duvar, ranza ile bilgisayar arası
const Hats := preload("res://scripts/hats.gd")
var locker_door: Node3D
var locker_open := false
var locker_item: Node3D
var locker_light: OmniLight3D
var locker_sfx: AudioStreamPlayer3D


func _build_locker() -> void:
	# sıradan, yıpranmış yeşil metal dolap (oyun gelene kadar dikkat çekmesin)
	var paint: StandardMaterial3D = w.mats.green_metal
	var dark: StandardMaterial3D = w._flat(Color("#1b2220"), 0.8, 0.3)
	var p := LOCKER_POS
	var wd := 0.62  # z
	var dp := 0.48  # x
	var ht := 1.86
	# gövde: arka, yanlar, üst, alt (içi boş, kapı açılınca görünür)
	w.box(Vector3(0.03, ht, wd), p + Vector3(-dp / 2, ht / 2, 0), paint, false, self)
	for s in [-1.0, 1.0]:
		w.box(Vector3(dp, ht, 0.03), p + Vector3(0, ht / 2, s * wd / 2), paint, false, self)
	w.box(Vector3(dp, 0.03, wd), p + Vector3(0, ht, 0), paint, false, self)
	w.box(Vector3(dp, 0.08, wd), p + Vector3(0, 0.04, 0), paint, false, self)
	w.box(Vector3(dp - 0.04, 0.01, wd - 0.04), p + Vector3(0, ht - 0.02, 0), dark, false, self)
	w.box(Vector3(0.01, ht - 0.1, wd - 0.05), p + Vector3(-dp / 2 + 0.03, ht / 2, 0), dark, false, self)
	# raf
	w.box(Vector3(dp - 0.05, 0.025, wd - 0.05), p + Vector3(0, 1.0, 0), paint, false, self)
	w.solid(Vector3(dp, ht, wd), p + Vector3(0, ht / 2, 0), 0.0, self)
	# kapı: menteşe ön-arka kenarda; açılınca koridora doğru (dışa) döner
	locker_door = Node3D.new()
	locker_door.position = p + Vector3(dp / 2 + 0.015, 0, wd / 2)
	add_child(locker_door)
	w.box(Vector3(0.025, ht - 0.04, wd), Vector3(0, ht / 2, -wd / 2), paint, false, locker_door)
	for i in 5:
		w.box(Vector3(0.03, 0.018, wd * 0.55), Vector3(0.006, 1.55 + i * 0.045, -wd / 2), dark, false, locker_door)
	w.box(Vector3(0.05, 0.16, 0.035), Vector3(0.03, 1.05, -wd + 0.08), w.mats.metal_dark, false, locker_door)
	var nl := Label3D.new()
	nl.text = str(number)
	nl.font_size = 22
	nl.pixel_size = 0.004
	nl.modulate = Color(0.9, 0.9, 0.85)
	nl.position = Vector3(0.02, 1.4, -wd / 2)
	nl.rotation.y = PI / 2
	locker_door.add_child(nl)
	locker_light = OmniLight3D.new()
	locker_light.position = p + Vector3(0.05, 1.45, 0)
	locker_light.light_color = Color(1.0, 0.92, 0.75)
	locker_light.omni_range = 0.9
	locker_light.light_energy = 0.0
	locker_light.visible = false
	add_child(locker_light)
	locker_sfx = AudioStreamPlayer3D.new()
	locker_sfx.position = p + Vector3(0.2, 1.2, 0)
	locker_sfx.stream = load("res://assets/ses/dolap.ogg")
	locker_sfx.unit_size = 4.0
	add_child(locker_sfx)


func locker_world() -> Vector3:
	return to_global(LOCKER_POS + Vector3(0.35, 1.2, 0))


# Dolabın içine bir şapka koyar ("" boşaltır).
func set_locker_item(style: String) -> void:
	if is_instance_valid(locker_item):
		locker_item.queue_free()
	locker_item = null
	if style == "":
		return
	locker_item = Node3D.new()
	add_child(locker_item)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * 1.7
	locker_item.add_child(holder)
	Hats.build(holder, style, AABB())
	# kafa çerçevesine göre kurulan şapkayı rafın ortasına oturt: gerçek ağ kutusunun altı rafın üstünde
	# (sabit kaydırma yeni gövdelerde eşyanın yarısını rafın altına gömüyordu)
	locker_item.rotation.y = PI / 2 + 0.35
	var raf_ust := 1.0 + 0.0125
	var kutu := _agac_kutusu(locker_item, Transform3D(Basis.from_euler(locker_item.rotation), Vector3.ZERO))
	if kutu.size == Vector3.ZERO:
		locker_item.position = LOCKER_POS + Vector3(0.02, raf_ust, 0)
	else:
		var orta := kutu.get_center()
		locker_item.position = LOCKER_POS + Vector3(0.02 - orta.x, raf_ust + 0.004 - kutu.position.y, -orta.z)


# Bir düğümün altındaki bütün ağların birleşik kutusu (xf: düğümden istenen çerçeveye dönüşüm).
static func _agac_kutusu(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var bos := true
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = xf * (n as MeshInstance3D).mesh.get_aabb()
		bos = false
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var b := _agac_kutusu(c, xf * (c as Node3D).transform)
		if b.size == Vector3.ZERO and b.position == Vector3.ZERO:
			continue
		out = b if bos else out.merge(b)
		bos = false
	return out


func set_locker(open: bool) -> void:
	if open == locker_open or not locker_door:
		return
	locker_open = open
	locker_sfx.stream = load("res://assets/ses/dolap.ogg" if open else "res://assets/ses/dolap_kapa.ogg")
	locker_sfx.play()
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(locker_door, "rotation:y", deg_to_rad(-105.0) if open else 0.0, 0.6)
	# kapalıyken ışık tamamen gizli: telefonda ışık sayısı boşa artmasın
	if open:
		locker_light.visible = true
	var tl := create_tween()
	tl.tween_property(locker_light, "light_energy", 0.55 if open else 0.0, 0.4)
	if not open:
		tl.tween_callback(func() -> void: locker_light.visible = locker_open)


# ---------- ayna (sol duvar, bilgisayar masasının üstü) ----------

var mirror: Node3D


func _build_mirror() -> void:
	mirror = preload("res://scripts/mirror.gd").new()
	mirror.w = w
	mirror.position = Vector3(-1.985, 1.78, 1.05)
	add_child(mirror)
	mirror.build()
	_build_mirror_lamp()


# Aynanın yanında küçük ayna apliki: loş, soğuk-nötr beyaz (tavandaki sıcak sarı lambadan ayrı durur).
# Kısa menzilli, gölgesiz (telefonda ucuz); elektrik kesilince söner. Pencere aynanın tam üstünde
# olduğu için aplik aynanın kapı tarafındaki kenarında, göz hizasının biraz üstünde.
const MIRROR_LAMP_POS := Vector3(-2.0, 1.98, 1.47)  # duvar yüzeyi (x = -2), aynanın +z kenarı
const MIRROR_LAMP_RENK := Color(0.95, 0.97, 1.0)
var mirror_light: OmniLight3D
var mirror_bulb_mat: StandardMaterial3D


func _build_mirror_lamp() -> void:
	var p := MIRROR_LAMP_POS
	var metal: Material = w.mats.metal_dark
	w.box(Vector3(0.016, 0.16, 0.075), p + Vector3(0.008, 0, 0), metal, false, self)  # duvar tabanı
	w.box(Vector3(0.06, 0.014, 0.014), p + Vector3(0.045, 0, 0), metal, false, self)  # kısa kol
	# buzlu cam silindir (kendi ışığıyla parlar) + üst ve alt metal başlık
	mirror_bulb_mat = w._glow(Color(0.86, 0.92, 1.0), 1.5)
	var glass := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.032
	cm.bottom_radius = 0.032
	cm.height = 0.11
	cm.radial_segments = 14
	cm.rings = 1
	glass.mesh = cm
	glass.material_override = mirror_bulb_mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = p + Vector3(0.08, 0, 0)
	add_child(glass)
	for s in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.036 if s < 0 else 0.026
		cc.bottom_radius = 0.026 if s < 0 else 0.036
		cc.height = 0.016
		cc.radial_segments = 14
		cc.rings = 1
		cap.mesh = cc
		cap.material_override = metal
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cap.position = p + Vector3(0.08, s * 0.063, 0)
		add_child(cap)
	mirror_light = OmniLight3D.new()
	mirror_light.light_color = MIRROR_LAMP_RENK
	mirror_light.light_energy = 0.55
	mirror_light.omni_range = 1.9
	mirror_light.omni_attenuation = 1.3
	mirror_light.light_specular = 0.25
	mirror_light.shadow_enabled = false
	mirror_light.position = p + Vector3(0.2, -0.02, -0.12)  # biraz aynanın önüne: aynaya bakan yüzü aydınlatır
	add_child(mirror_light)
	# hafif parıltı (kalite 0'da da görünür; ışık sönünce o da söner)
	Dunya.halo(self, p + Vector3(0.09, 0, 0), MIRROR_LAMP_RENK, 0.3, 0.3, mirror_light)


func mirror_world() -> Vector3:
	return mirror.global_position
