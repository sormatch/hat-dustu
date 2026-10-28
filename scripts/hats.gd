# Şapkalar: kafanın ölçülen şekline (Hair._head_min/_head_max) oturan, koddan kurulan modeller.
# Saç bırakılırsa (uzun saçlar) şapka saçın kutusunu da kapsayacak kadar büyür.
extends RefCounted

const Hair := preload("res://scripts/hair.gd")
# Bu saçlar şapkanın altında kalır (gizlenir); diğerleri şapkayla birlikte görünür.
const HIDDEN_HAIR := ["kisa", "asker", "dalgali", "yandan", "mohawk", "kivircik", "kel", "kazi", "kazi_k", "ayrik"]
# Kafayı örtmeyen şapkalar: saç her zaman görünür, şapka saçın üstüne oturur
const OPEN := ["tilki", "hale", "parti", "koni", "ordek"]
# "kapuson" kıyafet modelinden gelir (model_body.gd, Quaternius ranger kapüşonu): burada kurulmaz, bütün saçı örter


static func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _dome(parent: Node3D, mat: Material, at: Vector3, rx: float, h: float, rz: float) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 1.0  # yarıçap = yükseklik: düzgün yarım küre, y 0..1
	s.is_hemisphere = true
	s.radial_segments = 32
	s.rings = 12
	return _add(parent, s, mat, at, Vector3.ZERO, Vector3(rx, h, rz))


static func _ring(parent: Node3D, mat: Material, at: Vector3, rx: float, rz: float, height: float, top_k := 1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top_k
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 32
	return _add(parent, c, mat, at, Vector3.ZERO, Vector3(rx, height, rz))


# style: şapka kimliği; hair_box: bırakılan saçın kutusu (kafa çerçevesinde) ya da boş.
static func build(parent: Node3D, style: String, hair_box: AABB) -> void:
	if style == "yok" or style == "":
		return
	var hmin: Vector3 = Hair._head_min
	var hmax: Vector3 = Hair._head_max
	var root := Node3D.new()
	root.rotation.x = 0.2  # arkası biraz aşağıda, alnı açık
	parent.add_child(root)
	var cx := (hmin.x + hmax.x) * 0.5
	var cz := (hmin.z + hmax.z) * 0.5 + 0.006
	var rx := (hmax.x - hmin.x) * 0.5 * 1.07
	var rz := (hmax.z - hmin.z) * 0.5 * 1.07
	var top := hmax.y + 0.012
	if hair_box.size != Vector3.ZERO:
		rx = maxf(rx, hair_box.size.x * 0.5 * 1.04)
		rz = maxf(rz, hair_box.size.z * 0.5 * 1.02)
		top = maxf(top, hair_box.end.y + 0.008)
	var rim := lerpf(hmin.y, hmax.y, 0.42)
	var h := top - rim
	var at := Vector3(cx, rim, cz)
	match style:
		"bere", "ponpon":
			var knit := _mat(Color("#1d1f24") if style == "bere" else Color("#a8262a"), 0.98)
			_dome(root, knit, at, rx * 1.02, h * 1.12, rz * 1.02)
			_ring(root, _mat(knit.albedo_color.darkened(0.15), 1.0), at + Vector3(0, 0.012, 0), rx * 1.07, rz * 1.07, 0.04)
			if style == "ponpon":
				var p := SphereMesh.new()
				p.radius = 0.035
				p.height = 0.07
				_add(root, p, _mat(Color("#f2efe6"), 1.0), Vector3(cx, top + h * 0.12 + 0.02, cz))
		"kep", "ters_kep":
			var cloth := _mat(Color("#1f3e78"), 0.9)
			_dome(root, cloth, at, rx * 1.01, h * 0.98, rz * 1.01)
			var visor := CylinderMesh.new()
			visor.top_radius = 1.0
			visor.bottom_radius = 1.0
			visor.height = 1.0
			visor.radial_segments = 24
			var dir := -1.0 if style == "kep" else 1.0
			_add(root, visor, _mat(Color("#14294f"), 0.85), Vector3(cx, rim + 0.008, cz + dir * rz * 0.92), Vector3(dir * -0.12, 0, 0), Vector3(rx * 0.8, 0.008, rz * 0.62))
			var b := SphereMesh.new()
			b.radius = 0.012
			b.height = 0.012
			_add(root, b, cloth, Vector3(cx, top - 0.002, cz))
		"bandana":
			var red := _mat(Color("#b3202a"), 0.95)
			_dome(root, red, at + Vector3(0, -0.004, 0), rx * 1.0, h * 0.97, rz * 1.0)
			_ring(root, _mat(Color("#8f1820"), 0.95), at + Vector3(0, 0.006, 0), rx * 1.02, rz * 1.02, 0.03)
			for s in [-1.0, 1.0]:
				_add(root, BoxMesh.new(), red, Vector3(cx + s * 0.018, rim - 0.035, cz + rz * 1.0), Vector3(0.35, 0, s * 0.25), Vector3(0.025, 0.08, 0.006))
		"fotr":
			var felt := _mat(Color("#2a2622"), 0.9)
			_ring(root, felt, at + Vector3(0, 0.05, 0), rx * 0.98, rz * 0.98, 0.1 + maxf(0.0, h - 0.09), 0.86)
			_ring(root, _mat(Color("#121212"), 0.7), at + Vector3(0, 0.022, 0), rx * 1.0, rz * 1.0, 0.024)
			_ring(root, felt, at + Vector3(0, 0.004, 0), rx * 1.7, rz * 1.6, 0.008)
		"baret":
			var yellow := _mat(Color("#f2b81c"), 0.35)
			_dome(root, yellow, at + Vector3(0, -0.004, 0), rx * 1.08, h * 1.15, rz * 1.08)
			_ring(root, yellow, at + Vector3(0, -0.002, -0.012), rx * 1.32, rz * 1.32, 0.008)
		"kulaklik":
			var black := _mat(Color("#141418"), 0.4, 0.2)
			# kafa bandı: elips yay boyunca birbirine değen ince parçalar
			var seg := BoxMesh.new()
			var ax := rx + 0.014
			var ay := top - rim + 0.08
			for i in 24:
				var a := PI * (i + 0.5) / 24.0
				var p := Vector3(cx + cos(a) * ax, rim - 0.07 + sin(a) * ay, cz)
				var tan := Vector2(-sin(a) * ax, cos(a) * ay)
				_add(root, seg, black, p, Vector3(0, 0, tan.angle() - PI / 2), Vector3(0.012, tan.length() * PI / 24.0 * 1.15, 0.03))
			for s in [-1.0, 1.0]:
				var cup := CylinderMesh.new()
				cup.top_radius = 0.042
				cup.bottom_radius = 0.046
				cup.height = 0.03
				_add(root, cup, _mat(Color("#d0263a"), 0.4), Vector3(cx + s * (rx + 0.012), rim - 0.07, cz), Vector3(0, 0, PI / 2))
		"tac":
			var gold := _mat(Color("#e8b33a"), 0.25, 0.9)
			var y := top - 0.02
			_ring(root, gold, Vector3(cx, y, cz), rx * 0.78, rz * 0.78, 0.04)
			for i in 8:
				var a := TAU * i / 8.0
				var spike := CylinderMesh.new()
				spike.top_radius = 0.0
				spike.bottom_radius = 0.016
				spike.height = 0.045
				_add(root, spike, gold, Vector3(cx + cos(a) * rx * 0.76, y + 0.04, cz + sin(a) * rz * 0.76))
				var gem := SphereMesh.new()
				gem.radius = 0.008
				gem.height = 0.016
				_add(root, gem, _mat(Color("#c0182a") if i % 2 == 0 else Color("#1e5ad8"), 0.1, 0.3), Vector3(cx + cos(a) * rx * 0.79, y, cz + sin(a) * rz * 0.79))
		"asci":
			# aşçı şapkası: beyaz bant + yukarı genişleyen gövde + kabarık, pileli tepe
			var white := _mat(Color("#f4f2ec"), 0.95)
			_ring(root, white, at + Vector3(0, 0.03, 0), rx * 1.02, rz * 1.02, 0.06)
			var body := CylinderMesh.new()
			body.top_radius = 1.22
			body.bottom_radius = 1.0
			body.height = 1.0
			body.radial_segments = 24
			_add(root, body, white, at + Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(rx, 0.14, rz))
			var puff := SphereMesh.new()
			puff.radius = 1.0
			puff.height = 2.0
			puff.radial_segments = 12
			puff.rings = 6
			for i in 10:
				var a := TAU * i / 10.0
				_add(root, puff, white, at + Vector3(cos(a) * rx * 0.88, 0.215, sin(a) * rz * 0.88), Vector3.ZERO, Vector3(0.046, 0.04, 0.046))
			_dome(root, white, at + Vector3(0, 0.2, 0), rx * 1.12, 0.07, rz * 1.12)
		"parti":
			# parti külahı: renkli şeritli koni, tepede ponpon; saçın üstünde hafif yana yatık
			var cone := Node3D.new()
			cone.position = Vector3(cx + rx * 0.18, top - 0.012, cz)
			cone.rotation.z = -0.28
			root.add_child(cone)
			var hh := 0.17
			# şeritler köşe renginde: tek mesh, tek çizim
			var vm := _mat(Color.WHITE, 0.6)
			vm.vertex_color_use_as_albedo = true
			vm.vertex_color_is_srgb = true
			_add(cone, _striped_cone(0.06, hh, [Color("#e83a6a"), Color("#f5d03b"), Color("#3aa0e8"), Color("#f5d03b")]), vm, Vector3.ZERO)
			var pom := SphereMesh.new()
			pom.radius = 0.022
			pom.height = 0.044
			_add(cone, pom, _mat(Color("#f2efe6"), 1.0), Vector3(0, hh + 0.012, 0))
		"tilki":
			# tilki kulakları: saçın üstünden geçen ince taç ve iki üçgen kulak (turuncu, içi krem, uçları koyu)
			var band_m := _mat(Color("#1d1b1a"), 0.5)
			var seg := BoxMesh.new()
			var ax := rx + 0.008
			var ay := top - rim + 0.035
			var bz := cz - rz * 0.08
			for i in 22:
				var a := PI * (i + 0.5) / 22.0
				var p := Vector3(cx + cos(a) * ax, rim - 0.035 + sin(a) * ay, bz)
				var tan := Vector2(-sin(a) * ax, cos(a) * ay)
				_add(root, seg, band_m, p, Vector3(0, 0, tan.angle() - PI / 2), Vector3(0.008, tan.length() * PI / 22.0 * 1.15, 0.014))
			var fur := _mat(Color("#d9692a"), 0.95)
			var inner := _mat(Color("#f3dcc0"), 0.95)
			var tip := _mat(Color("#2a1d17"), 0.95)
			var c1 := CylinderMesh.new()
			c1.top_radius = 0.0
			c1.bottom_radius = 1.0
			c1.height = 1.0
			c1.radial_segments = 4
			for s in [-1.0, 1.0]:
				var a: float = PI * 0.5 - s * 0.62
				var ear := Node3D.new()
				ear.position = Vector3(cx + cos(a) * ax, rim - 0.035 + sin(a) * ay - 0.004, bz)
				ear.rotation = Vector3(-0.15, 0, s * -0.42)
				root.add_child(ear)
				_add(ear, c1, fur, Vector3(0, 0.045, 0), Vector3(0, PI / 4, 0), Vector3(0.042, 0.09, 0.012))
				_add(ear, c1, inner, Vector3(0, 0.04, -0.008), Vector3(0, PI / 4, 0), Vector3(0.026, 0.065, 0.006))
				_add(ear, c1, tip, Vector3(0, 0.077, 0), Vector3(0, PI / 4, 0), Vector3(0.0125, 0.026, 0.0136))
		"kask":
			# asker kaskı: mat zeytin yeşili kubbe, hafif taşan kenar, yan kayış tokaları
			var olive := _mat(Color("#4b5232"), 0.82)
			_dome(root, olive, at + Vector3(0, -0.012, 0.004), rx * 1.14, h * 1.22, rz * 1.15)
			_ring(root, olive, at + Vector3(0, -0.014, 0.004), rx * 1.2, rz * 1.21, 0.012)
			var strap := _mat(Color("#2c2a22"), 0.7)
			var b := BoxMesh.new()
			b.size = Vector3(0.006, 0.07, 0.016)
			for s in [-1.0, 1.0]:
				_add(root, b, strap, Vector3(cx + s * rx * 1.13, rim - 0.04, cz + 0.004), Vector3(0, 0, s * 0.08))
		"kovboy":
			# kovboy şapkası: ortası çökük tepe, iki yanı kalkık geniş kenar, deri bant
			var felt := _mat(Color("#8a5a32"), 0.88)
			var cy := CylinderMesh.new()
			cy.top_radius = 0.86
			cy.bottom_radius = 1.0
			cy.height = 1.0
			cy.radial_segments = 24
			var ch := 0.1 + maxf(0.0, h - 0.085)
			_add(root, cy, felt, at + Vector3(0, ch * 0.5, 0), Vector3.ZERO, Vector3(rx * 0.98, ch, rz * 1.02))
			_dome(root, felt, at + Vector3(0, ch - 0.004, 0), rx * 0.84, 0.025, rz * 0.86)
			_add(root, BoxMesh.new(), _mat(Color("#5e3b1f"), 0.9), at + Vector3(0, ch + 0.012, 0), Vector3.ZERO, Vector3(0.012, 0.012, rz * 1.3))
			_ring(root, _mat(Color("#3a2414"), 0.6), at + Vector3(0, 0.02, 0), rx * 1.0, rz * 1.04, 0.022)
			_add(root, _brim_mesh(rx * 1.0, rz * 1.04, rx * 1.95, rz * 1.8, 0.0, 0.06), felt, at + Vector3(0, 0.002, 0))
		"korsan":
			# korsan şapkası (üç köşeli): siyah tepe, üç yanı kalkık kenar, altın sırma, önde kafatası
			var black := _mat(Color("#18171a"), 0.85)
			_dome(root, black, at + Vector3(0, -0.006, 0), rx * 1.06, h * 1.18, rz * 1.06)
			_add(root, _brim_mesh(rx * 1.04, rz * 1.04, rx * 1.75, rz * 1.75, 0.075, 0.0), black, at)
			_add(root, _brim_edge(rx * 1.75, rz * 1.75, 0.075), _mat(Color("#d9b25a"), 0.3, 0.9), at)
			var bone_m := _mat(Color("#efeae0"), 0.6)
			var skull := SphereMesh.new()
			skull.radius = 0.016
			skull.height = 0.03
			_add(root, skull, bone_m, at + Vector3(0, 0.07, -rz * 1.2), Vector3.ZERO, Vector3(1, 1, 0.4))
			var bone := BoxMesh.new()
			bone.size = Vector3(0.042, 0.006, 0.004)
			for s in [-1.0, 1.0]:
				_add(root, bone, bone_m, at + Vector3(0, 0.046, -rz * 1.22), Vector3(0, 0, s * 0.6))
		"pervane":
			# pervaneli bere: renkli dilimli kubbe, tepede sap ve dönen iki kanat
			_dome(root, _mat(Color("#2f6fe0"), 0.75), at, rx * 1.03, h * 1.1, rz * 1.03)
			_ring(root, _mat(Color("#f5c531"), 0.8), at + Vector3(0, 0.012, 0), rx * 1.07, rz * 1.07, 0.03)
			var sap := CylinderMesh.new()
			sap.top_radius = 0.004
			sap.bottom_radius = 0.006
			sap.height = 0.035
			var tepe := at + Vector3(0, h * 1.08 + 0.012, 0)
			_add(root, sap, _mat(Color("#2b2b2e"), 0.4, 0.6), tepe)
			var pervane := Node3D.new()
			pervane.position = tepe + Vector3(0, 0.02, 0)
			root.add_child(pervane)
			var kanat := BoxMesh.new()
			kanat.size = Vector3(0.11, 0.004, 0.03)
			_add(pervane, kanat, _mat(Color("#e8402f"), 0.5), Vector3(0.058, 0, 0), Vector3(0.25, 0, 0))
			_add(pervane, kanat, _mat(Color("#f5c531"), 0.5), Vector3(-0.058, 0, 0), Vector3(-0.25, 0, 0))
			var tw := pervane.create_tween().set_loops()
			tw.tween_property(pervane, "rotation:y", TAU, 0.45).from(0.0)
		"koni":
			# kafada trafik konisi: turuncu koni, iki beyaz yansıtıcı şerit, kare taban
			var turuncu := _mat(Color("#ff5a14"), 0.55)
			var beyaz := _mat(Color("#f2f2ee"), 0.35)
			var kok := Node3D.new()
			kok.position = Vector3(cx, top - 0.025, cz)
			kok.rotation.z = 0.12
			root.add_child(kok)
			var taban := BoxMesh.new()
			taban.size = Vector3(rx * 2.5, 0.02, rz * 2.5)
			_add(kok, taban, _mat(Color("#d9480f"), 0.6), Vector3(0, 0.01, 0))
			var koni := CylinderMesh.new()
			koni.top_radius = 0.012
			koni.bottom_radius = rx * 0.95
			koni.height = 0.28
			koni.radial_segments = 20
			_add(kok, koni, turuncu, Vector3(0, 0.16, 0))
			for k in [0.36, 0.62]:
				var serit := CylinderMesh.new()
				serit.top_radius = lerpf(rx * 0.95, 0.012, k + 0.06) + 0.002
				serit.bottom_radius = lerpf(rx * 0.95, 0.012, k) + 0.002
				serit.height = 0.28 * 0.06
				serit.radial_segments = 20
				_add(kok, serit, beyaz, Vector3(0, 0.02 + 0.28 * (k + 0.03), 0))
		"ordek":
			# kafada oturan lastik ördek: sarı gövde ve kafa, turuncu gaga, siyah gözler
			var sari := _mat(Color("#ffd21f"), 0.35)
			var kok := Node3D.new()
			kok.position = Vector3(cx, top - 0.01, cz + 0.01)
			kok.rotation.y = 0.35
			root.add_child(kok)
			var top_m := SphereMesh.new()
			top_m.radius = 1.0
			top_m.height = 2.0
			_add(kok, top_m, sari, Vector3(0, 0.045, 0.01), Vector3.ZERO, Vector3(0.075, 0.055, 0.095))
			_add(kok, top_m, sari, Vector3(0, 0.115, -0.05), Vector3.ZERO, Vector3(0.045, 0.045, 0.045))
			_add(kok, top_m, sari, Vector3(0, 0.07, 0.09), Vector3(-0.6, 0, 0), Vector3(0.03, 0.02, 0.035))  # kuyruk
			var gaga := BoxMesh.new()
			gaga.size = Vector3(0.045, 0.012, 0.04)
			_add(kok, gaga, _mat(Color("#ff7b14"), 0.4), Vector3(0, 0.108, -0.1), Vector3(0.15, 0, 0))
			for s in [-1.0, 1.0]:
				_add(kok, top_m, _mat(Color("#121212"), 0.2), Vector3(s * 0.025, 0.128, -0.083), Vector3.ZERO, Vector3.ONE * 0.007)
		"kova":
			# kafaya geçirilmiş ters metal kova: konik gövde, kenar halkası, yanda sap
			var metal := _mat(Color("#9aa0a6"), 0.45, 0.85)
			var kova := CylinderMesh.new()
			kova.top_radius = rx * 0.82
			kova.bottom_radius = rx * 1.12
			kova.height = h * 1.6
			kova.radial_segments = 24
			_add(root, kova, metal, at + Vector3(0, h * 0.62, 0), Vector3.ZERO, Vector3(1, 1, rz / rx))
			_ring(root, _mat(Color("#7d838a"), 0.4, 0.9), at + Vector3(0, -0.14 * h + 0.004, 0), rx * 1.15, rz * 1.15, 0.014)
			var sap := TorusMesh.new()
			sap.inner_radius = rx * 1.12
			sap.outer_radius = rx * 1.16
			sap.rings = 24
			sap.ring_segments = 4
			_add(root, sap, _mat(Color("#5d6268"), 0.4, 0.9), at + Vector3(0, h * 0.3, 0), Vector3(0, 0, PI / 2 - 0.5), Vector3(1, 1, rz / rx))
		"viking":
			# viking kaskı: metal kubbe, deri alın bandı, iki yana kıvrılan boynuz
			var metal := _mat(Color("#8c8f94"), 0.4, 0.85)
			_dome(root, metal, at + Vector3(0, -0.01, 0), rx * 1.12, h * 1.2, rz * 1.12)
			_ring(root, _mat(Color("#5a3a22"), 0.8), at + Vector3(0, -0.008, 0), rx * 1.16, rz * 1.16, 0.028)
			var burun := BoxMesh.new()
			burun.size = Vector3(0.016, 0.06, 0.008)
			_add(root, burun, metal, at + Vector3(0, -0.03, -rz * 1.14), Vector3(-0.15, 0, 0))
			var boynuz_m := _mat(Color("#efe4c8"), 0.55)
			for s in [-1.0, 1.0]:
				# iki parçalı boynuz: kökü yana-yukarı, ucu yukarı kıvrılır (parçalar uç uca)
				var p0 := at + Vector3(s * rx * 1.02, h * 0.5, 0)
				var a1: float = -s * 0.95
				var d1 := Vector3(-sin(a1), cos(a1), 0)
				var kok := CylinderMesh.new()
				kok.top_radius = 0.014
				kok.bottom_radius = 0.024
				kok.height = 0.085
				_add(root, kok, boynuz_m, p0 + d1 * 0.0425, Vector3(0, 0, a1))
				var e1 := p0 + d1 * 0.085
				var a2: float = -s * 0.3
				var d2 := Vector3(-sin(a2), cos(a2), 0)
				var uc := CylinderMesh.new()
				uc.top_radius = 0.002
				uc.bottom_radius = 0.0145
				uc.height = 0.075
				_add(root, uc, boynuz_m, e1 + d2 * 0.035, Vector3(0, 0, a2))
		"buyucu":
			# büyücü şapkası: geniş kenarlı, ucu hafif bükük lacivert koni, sarı yıldızlar
			var mor := _mat(Color("#2b2464"), 0.8)
			var kenar := CylinderMesh.new()
			kenar.top_radius = 1.0
			kenar.bottom_radius = 1.0
			kenar.height = 0.01
			kenar.radial_segments = 28
			_add(root, kenar, mor, at + Vector3(0, 0.004, 0), Vector3.ZERO, Vector3(rx * 1.75, 1.0, rz * 1.75))
			var g1 := CylinderMesh.new()
			g1.top_radius = rx * 0.55
			g1.bottom_radius = rx * 1.0
			g1.height = 0.16
			g1.radial_segments = 24
			_add(root, g1, mor, at + Vector3(0, 0.085, 0), Vector3.ZERO, Vector3(1, 1, rz / rx))
			var g2 := CylinderMesh.new()
			g2.top_radius = 0.004
			g2.bottom_radius = rx * 0.55
			g2.height = 0.14
			g2.radial_segments = 20
			_add(root, g2, mor, at + Vector3(0.018, 0.225, 0.01), Vector3(0.12, 0, -0.25))
			var yildiz_m := _mat(Color("#ffd447"), 0.3, 0.3)
			yildiz_m.emission_enabled = true
			yildiz_m.emission = Color("#ffcc33")
			yildiz_m.emission_energy_multiplier = 1.2
			var yildiz := SphereMesh.new()
			yildiz.radius = 0.009
			yildiz.height = 0.018
			yildiz.radial_segments = 5
			yildiz.rings = 2
			for i in 6:
				var a := TAU * i / 6.0 + 0.4
				var yk := 0.05 + (i % 3) * 0.04
				var r := lerpf(rx * 1.0, rx * 0.6, yk / 0.16)
				_add(root, yildiz, yildiz_m, at + Vector3(cos(a) * r * 1.01, yk, sin(a) * r * 1.01), Vector3.ZERO, Vector3(1, 1, 0.5))
		"hale":
			# melek halesi: kafanın üstünde süzülen, kendiliğinden parlayan altın halka
			var glow := _mat(Color("#ffd75e"), 0.3, 0.6)
			glow.emission_enabled = true
			glow.emission = Color("#ffcf4a")
			glow.emission_energy_multiplier = 2.2
			var t := TorusMesh.new()
			t.inner_radius = 0.085
			t.outer_radius = 0.1
			t.rings = 40
			t.ring_segments = 8
			# saç kutusuna değil kafaya göre: at kuyruğu/topuz haleyi geriye kaçırmasın
			_add(root, t, glow, Vector3(cx, maxf(hmax.y + 0.03, minf(top, hmax.y + 0.06)) + 0.045, cz + 0.02), Vector3(-0.2, 0, 0))


# Renk şeritli koni (taban y = 0, tepe y = h): her şerit kendi renginde, keskin geçişli.
static func _striped_cone(r: float, h: float, cols: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 20
	var bands := cols.size()
	for b in bands:
		var f0 := float(b) / bands
		var f1 := float(b + 1) / bands
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var q := [Vector3(cos(a0) * r * (1.0 - f0), h * f0, sin(a0) * r * (1.0 - f0)), Vector3(cos(a1) * r * (1.0 - f0), h * f0, sin(a1) * r * (1.0 - f0)),
				Vector3(cos(a1) * r * (1.0 - f1), h * f1, sin(a1) * r * (1.0 - f1)), Vector3(cos(a0) * r * (1.0 - f1), h * f1, sin(a0) * r * (1.0 - f1))]
			for k in [0, 2, 1, 0, 3, 2]:
				var v: Vector3 = q[k]
				st.set_color(cols[b])
				st.set_normal(Vector3(v.x, r * r / h, v.z).normalized())
				st.add_vertex(v)
	return st.commit()


# Şapka kenarı (halka levha): iç elips (rx0, rz0) ile dış elips (rx1, rz1) arası. up3: üç köşeli kalkıklık (korsan),
# up_side: iki yanın kalkması (kovboy). Alt ve üst yüzü olan ince levha.
static func _brim_mesh(rx0: float, rz0: float, rx1: float, rz1: float, up3: float, up_side: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	var rows := 5
	var pts := []
	for j in rows + 1:
		var f := float(j) / rows
		var row := []
		for i in n + 1:
			var a := TAU * i / n
			var p := Vector3(cos(a) * lerpf(rx0, rx1, f), 0.0, sin(a) * lerpf(rz0, rz1, f))
			p.y = _brim_y(a, f, up3, up_side)
			row.append(p)
		pts.append(row)
	for j in rows:
		for i in n:
			var q := [pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]
			var nrm := ((q[1] - q[0]) as Vector3).cross((q[3] - q[0]) as Vector3).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nrm)
				st.add_vertex(q[k] + Vector3(0, 0.003, 0))
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_normal(-nrm)
				st.add_vertex(q[k] - Vector3(0, 0.003, 0))
	return st.commit()


static func _brim_y(a: float, f: float, up3: float, up_side: float) -> float:
	# a = 0 sağ yan (+x), -PI/2 ön (-z)
	var y := 0.0
	if up3 > 0.0:
		# önde bir köşe, arkada iki köşe: köşeler alçak, aralar dik kalkık
		var c := cos(3.0 * (a + PI / 2.0))
		y += up3 * pow(f, 1.4) * (0.55 - 0.45 * c)
	if up_side > 0.0:
		y += up_side * pow(f, 2.0) * pow(absf(cos(a)), 1.5) - 0.012 * f * absf(sin(a))
	return y


static func _brim_edge(rx: float, rz: float, up3: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var path := PackedVector3Array()
	for i in 49:
		var a := TAU * i / 48.0
		path.append(Vector3(cos(a) * rx, _brim_y(a, 1.0, up3, 0.0), sin(a) * rz))
	var radii := PackedFloat32Array()
	radii.resize(path.size())
	radii.fill(0.0035)
	Hair._tube(st, path, radii, 5)
	return st.commit()
