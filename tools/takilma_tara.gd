# Takılma denetimi: gerçek oyuncu kapsülüyle (yarıçap 0,3, boy 1,7) hücrelerin, koridorun ve yemekhanenin
# yürünebilir alanını ızgarayla tarar. Görüntü gerekmez (--headless çalışır).
#   Godot --headless --path . --script res://tools/takilma_tara.gd -- server=ws://127.0.0.1:8794 profil=takilmatest cikti=build/takilma/once.txt [adim=0.1]
# Her ızgara noktasında:
#   * kapsül çarpışmanın içine gömülü mü (intersect_shape),
#   * oradan 8 yönde gerçek hareketle (body_test_motion + kayma, oyuncunun kendi cismi) çıkılabiliyor mu,
#   * ana alandan (spawn) kapsülle ulaşılabiliyor mu (kapalı cepler),
#   * dar geçit: yarıçap 0,36 ile kapanan ya da yarıçap 0,1 sığıp 0,3 sığmayan boşluklar.
# Klozet hem kapalı hem Büyük Kaçış'taki gibi çekilmiş (açık) durumda taranır; oyunun gerçek ışınlama noktaları ayrıca denenir.
extends SceneTree

const R := 0.3
const BOY := 1.7
const Y0 := 0.03  # ayaklar zeminin hemen üstünde (zemin teması gömülme sayılmasın)

var args := {}
var main: Node
var space: PhysicsDirectSpaceState3D
var sh := {}  # yarıçap -> kapsül şekli
var q := PhysicsShapeQueryParameters3D.new()
var mp := PhysicsTestMotionParameters3D.new()
var mres := PhysicsTestMotionResult3D.new()
var prid: RID
var out := PackedStringArray()
var adim := 0.1


class Bolge:
	var ad := ""
	var x0 := 0.0
	var z0 := 0.0
	var nx := 0
	var nz := 0
	var oyun: PackedByteArray  # 1: oynanabilir bölge içinde
	var bos: PackedByteArray  # 1: kapsül sığıyor (yarıçap 0,3)
	var erisim: PackedByteArray  # 1: ana alandan ulaşılıyor
	var isaret := Callable()  # (x, z) -> bool oynanabilir mi


func _init() -> void:
	_calis.call_deferred()


func _calis() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	adim = float(args.get("adim", "0.1"))
	await process_frame
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	if not bool(main.get("hazir_mi")):
		await main.hazir
	for i in 30:
		await process_frame
	var pl: CharacterBody3D = main.player
	prid = pl.get_rid()
	for c in main.cells:
		c.set_door(true, true)
	for i in 4:
		await physics_frame
	space = pl.get_world_3d().direct_space_state
	for r in [0.1, 0.3, 0.36]:
		var cap := CapsuleShape3D.new()
		cap.radius = r
		cap.height = BOY
		sh[r] = cap
	q.collide_with_areas = false
	q.exclude = [prid]
	q.margin = 0.0
	mp.margin = pl.safe_margin
	mp.recovery_as_collision = false
	out.append("TAKILMA TARAMASI  kapsul r=%.2f boy=%.2f  izgara=%.2f m  hucre=%d" % [R, BOY, adim, main.cells.size()])
	out.append("")
	await _durum("kapali")
	for c in main.cells:
		c.klozet_ac(true, false)
	for i in 4:
		await physics_frame
	await _durum("acik")
	for c in main.cells:
		c.klozet_ac(false, false)
	for i in 4:
		await physics_frame
	_rulet_notu()
	var txt := "\n".join(out)
	print(txt)
	var path := str(args.get("cikti", ""))
	if path != "":
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(txt + "\n")
	quit()


# ---------- yardımcılar ----------

func bos_mu(p: Vector3, r: float) -> bool:
	q.shape = sh[r]
	q.transform = Transform3D(Basis(), Vector3(p.x, Y0 + BOY / 2.0, p.z))
	return space.intersect_shape(q, 1).is_empty()


func gecer(a: Vector3, b: Vector3, r: float) -> bool:
	q.shape = sh[r]
	q.transform = Transform3D(Basis(), Vector3(a.x, Y0 + BOY / 2.0, a.z))
	q.motion = b - a
	var f := space.cast_motion(q)
	q.motion = Vector3.ZERO
	return f.size() >= 2 and f[0] >= 0.999


# Oyuncunun kendi cismiyle bir kare hareket (kayarak): move_and_slide'a yakın.
func kay(p0: Vector3, hareket: Vector3) -> Vector3:
	var p := p0
	var m := hareket
	for i in 4:
		mp.from = Transform3D(Basis(), p)
		mp.motion = m
		if not PhysicsServer3D.body_test_motion(prid, mp, mres):
			p += m
			break
		p += mres.get_travel()
		var n := mres.get_collision_normal(0)
		n.y = 0.0
		var rem := mres.get_remainder()
		rem.y = 0.0
		if n.length() < 0.01:
			break
		m = rem.slide(n.normalized())
		if m.length() < 0.0005:
			break
	p.y = p0.y
	return p


# 8 yönde ~0,5 sn basılı tutunca ne kadar ilerler; en iyi yön mesafesi, çıkış yönü sayısı, son nokta bos mu
func cikis(p0: Vector3) -> Dictionary:
	var iyi := 0.0
	var yon := 0
	var bos_son := false
	for k in 8:
		var a := TAU * k / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var p := p0
		for f in 8:
			p = kay(p, d * 0.06)
		var dist := Vector2(p.x - p0.x, p.z - p0.z).length()
		if dist > 0.25:
			yon += 1
		if dist > iyi:
			iyi = dist
		if bos_mu(p, R):
			bos_son = true
	return {"en_iyi": iyi, "yon": yon, "bos_son": bos_son}


func yer(p: Vector3) -> String:
	var lp: Vector3 = main.lobby.to_local(p)
	if absf(lp.x) < 7.3 and absf(lp.z) < 6.3:
		return "yemekhane(%.2f, %.2f)" % [lp.x, lp.z]
	for c in main.cells:
		var l: Vector3 = c.to_local(p)
		if absf(l.x) < 2.2 and absf(l.z) < 3.2:
			return "hucre %d [i%d] yerel(%.2f, %.2f)" % [c.number, c.index, l.x, l.z]
	if p.x > 2.2 and p.x < 5.7:
		return "koridor(%.2f, %.2f)" % [p.x, p.z]
	return "dunya(%.2f, %.2f)" % [p.x, p.z]


# Noktaya değen çarpışma cisimleri: kısa tarif (kutu merkezi/boyu hücre yerelinde)
func yakin(p: Vector3) -> String:
	q.shape = _genis()
	q.transform = Transform3D(Basis(), Vector3(p.x, Y0 + BOY / 2.0, p.z))
	var hits := space.intersect_shape(q, 8)
	var parts: Array = []
	var seen := {}
	for h in hits:
		var co: Object = h.collider
		if not (co is CollisionObject3D) or seen.has(co):
			continue
		seen[co] = true
		parts.append(_tarif(co as CollisionObject3D))
	return "; ".join(parts) if not parts.is_empty() else "-"


var _gs: CapsuleShape3D


func _genis() -> CapsuleShape3D:
	if _gs == null:
		_gs = CapsuleShape3D.new()
		_gs.radius = R + 0.12
		_gs.height = BOY
	return _gs


func _tarif(co: CollisionObject3D) -> String:
	var ad := ""
	var n: Node = co
	while n != null and n != main:
		if str(n.name) == "Klozet":
			ad = "KLOZET"
			break
		n = n.get_parent()
	for ch in co.get_children():
		if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
			var s: Vector3 = ((ch as CollisionShape3D).shape as BoxShape3D).size
			var g: Vector3 = co.global_transform * (ch as CollisionShape3D).position
			var yz := yer(g)
			return "%s%s kutu %.2fx%.2fx%.2f @%s y=%.2f" % [ad + " " if ad != "" else "", co.get_class(), s.x, s.y, s.z, yz, g.y]
	return "%s%s" % [ad + " " if ad != "" else "", co.get_class()]


# ---------- bölgeler ----------

func _bolge_kur(ad: String, x0: float, x1: float, z0: float, z1: float, isaret: Callable) -> Bolge:
	var b := Bolge.new()
	b.ad = ad
	b.x0 = x0
	b.z0 = z0
	b.nx = int(ceil((x1 - x0) / adim)) + 1
	b.nz = int(ceil((z1 - z0) / adim)) + 1
	b.isaret = isaret
	b.oyun = PackedByteArray()
	b.oyun.resize(b.nx * b.nz)
	b.bos = PackedByteArray()
	b.bos.resize(b.nx * b.nz)
	b.erisim = PackedByteArray()
	b.erisim.resize(b.nx * b.nz)
	return b


func _nokta(b: Bolge, i: int, j: int) -> Vector3:
	return Vector3(b.x0 + i * adim, 0.0, b.z0 + j * adim)


func _hucre_ici(x: float, z: float) -> bool:
	var cz0: float = main.cells[0].position.z
	for k in main.cells.size():
		var cz: float = main.cells[k].position.z
		if x > -1.99 and x < 1.99 and absf(z - cz) < 2.99:
			return true
		if x >= 1.99 and x <= 2.21 and z > cz - 0.02 and z < cz + 1.02:
			return true
	if x > 2.21 and x < 5.59 and absf(z) < 27.9:
		return true
	return false


func _tara(b: Bolge) -> void:
	for j in b.nz:
		for i in b.nx:
			var p := _nokta(b, i, j)
			var ok: bool = b.isaret.call(p.x, p.z)
			b.oyun[j * b.nx + i] = 1 if ok else 0
			if ok and bos_mu(p, R):
				b.bos[j * b.nx + i] = 1


# seed'den kapsülle ulaşılabilir düğümler (gerçek süpürme sorgusuyla)
func _erisim(b: Bolge, tohum: Vector3, r: float) -> PackedByteArray:
	var res := PackedByteArray()
	res.resize(b.nx * b.nz)
	var si := int(round((tohum.x - b.x0) / adim))
	var sj := int(round((tohum.z - b.z0) / adim))
	# ızgarada tohuma en yakın boş düğüm
	var best := -1
	var bd := 1e9
	for dj in range(-4, 5):
		for di in range(-4, 5):
			var i := si + di
			var j := sj + dj
			if i < 0 or j < 0 or i >= b.nx or j >= b.nz:
				continue
			if b.oyun[j * b.nx + i] == 1 and bos_mu(_nokta(b, i, j), r):
				var d := float(di * di + dj * dj)
				if d < bd:
					bd = d
					best = j * b.nx + i
	if best < 0:
		return res
	var stack: Array = [best]
	res[best] = 1
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		var ci := cur % b.nx
		var cj := cur / b.nx
		var pc := _nokta(b, ci, cj)
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var i: int = ci + di
				var j: int = cj + dj
				if i < 0 or j < 0 or i >= b.nx or j >= b.nz:
					continue
				var ni := j * b.nx + i
				if res[ni] == 1 or b.oyun[ni] == 0:
					continue
				var pn := _nokta(b, i, j)
				if not bos_mu(pn, r):
					continue
				if not gecer(pc, pn, r):
					continue
				res[ni] = 1
				stack.append(ni)
	return res


# kümeler: sınıf(i,j) true olan düğümlerin 8-komşu bağlı bileşenleri
func _kumeler(b: Bolge, uygun: PackedByteArray) -> Array:
	var seen := PackedByteArray()
	seen.resize(b.nx * b.nz)
	var list: Array = []
	for j in b.nz:
		for i in b.nx:
			var idx := j * b.nx + i
			if uygun[idx] == 0 or seen[idx] == 1:
				continue
			var comp: Array = []
			var st: Array = [idx]
			seen[idx] = 1
			while not st.is_empty():
				var cur: int = st.pop_back()
				comp.append(cur)
				var ci := cur % b.nx
				var cj := cur / b.nx
				for dj in [-1, 0, 1]:
					for di in [-1, 0, 1]:
						var ii: int = ci + di
						var jj: int = cj + dj
						if ii < 0 or jj < 0 or ii >= b.nx or jj >= b.nz:
							continue
						var ni := jj * b.nx + ii
						if uygun[ni] == 1 and seen[ni] == 0:
							seen[ni] = 1
							st.append(ni)
			list.append(comp)
	return list


func _kutu(b: Bolge, comp: Array) -> String:
	var mn := Vector3(1e9, 0, 1e9)
	var mx := Vector3(-1e9, 0, -1e9)
	for idx in comp:
		var p := _nokta(b, int(idx) % b.nx, int(idx) / b.nx)
		mn.x = minf(mn.x, p.x)
		mn.z = minf(mn.z, p.z)
		mx.x = maxf(mx.x, p.x)
		mx.z = maxf(mx.z, p.z)
	var c := (mn + mx) / 2.0
	return "%s | boy %.1fx%.1f m | %d nokta" % [yer(c), mx.x - mn.x + adim, mx.z - mn.z + adim, comp.size()]


func _komsu_var(b: Bolge, idx: int, kume: PackedByteArray, mesafe: int) -> bool:
	var ci := idx % b.nx
	var cj := idx / b.nx
	for dj in range(-mesafe, mesafe + 1):
		for di in range(-mesafe, mesafe + 1):
			var i := ci + di
			var j := cj + dj
			if i < 0 or j < 0 or i >= b.nx or j >= b.nz:
				continue
			if kume[j * b.nx + i] == 1:
				return true
	return false


# ---------- ana tarama ----------

var toplam_takili := 0


func _durum(ad: String) -> void:
	out.append("==================== KLOZET: %s ====================" % ad.to_upper())
	var cz0: float = main.cells[0].position.z
	var czn: float = main.cells[main.cells.size() - 1].position.z
	var bA := _bolge_kur("hucreler+koridor", -2.0, 5.6, -28.0, 28.0, Callable(self, "_hucre_ici"))
	# koridor dışında çok uzun alan taranmasın: koridor z sınırı 28, hücreler bunun içinde
	var lob: Node3D = main.lobby
	var lo := lob.global_position
	var bB := _bolge_kur("yemekhane", lo.x - 6.9, lo.x + 6.9, lo.z - 5.9, lo.z + 5.9, func(x: float, z: float) -> bool:
		return absf(x - lo.x) < 6.9 and absf(z - lo.z) < 5.9)
	for b in [bA, bB]:
		_tara(b)
	var tA: Vector3 = main.cells[0].spawn_world()
	var tB: Vector3 = lob.spawn_point(0)
	bA.erisim = _erisim(bA, tA, R)
	bB.erisim = _erisim(bB, tB, R)
	for b in [bA, bB]:
		_bolge_raporu(b)
	_senaryolar(ad)
	out.append("")


func _bolge_raporu(b: Bolge) -> void:
	var bos_n := 0
	var er_n := 0
	for i in b.bos.size():
		bos_n += b.bos[i]
		er_n += b.erisim[i]
	out.append("--- %s: oynanabilir bolgede kapsul sigan nokta %d, ana alandan ulasilan %d ---" % [b.ad, bos_n, er_n])
	# 1) kapalı cepler: sığan ama ulaşılamayan
	var cep := PackedByteArray()
	cep.resize(b.bos.size())
	for i in b.bos.size():
		if b.bos[i] == 1 and b.erisim[i] == 0:
			cep[i] = 1
	var cepler := _kumeler(b, cep)
	out.append("[KAPALI CEP] ana alandan ulasilamayan bos bolge: %d" % cepler.size())
	for comp in cepler:
		var p := _nokta(b, int(comp[0]) % b.nx, int(comp[0]) / b.nx)
		out.append("   " + _kutu(b, comp) + " | yakin: " + yakin(p))
	# 2) dar geçit: r=0,36 ile kapanan
	var er36 := _erisim_tohumlu(b, 0.36)
	var fark := PackedByteArray()
	fark.resize(b.bos.size())
	for i in b.bos.size():
		if b.erisim[i] == 1 and er36[i] == 0:
			fark[i] = 1
	var dar := PackedByteArray()
	dar.resize(b.bos.size())
	for i in b.bos.size():
		if fark[i] == 1 and not _komsu_var(b, i, er36, 1):
			dar[i] = 1  # kenar şeridi değil: iç düğüm
	var darlar := _kumeler(b, _genislet(b, dar, fark))
	out.append("[DAR GECIT] kapsul yaricapi 0,36'da kapanan (genislik 0,60-0,72 m): %d" % darlar.size())
	for comp in darlar:
		var p := _nokta(b, int(comp[0]) % b.nx, int(comp[0]) / b.nx)
		out.append("   " + _kutu(b, comp) + " | yakin: " + yakin(p))
	# 3) yarıçap 0,1 sığıp 0,3 sığmayan, ana alandan görünen dar yarıklar
	var er10 := _erisim_tohumlu(b, 0.1)
	var yarik := PackedByteArray()
	yarik.resize(b.bos.size())
	for i in b.bos.size():
		if er10[i] == 1 and b.erisim[i] == 0 and not _komsu_var(b, i, b.erisim, 3):
			yarik[i] = 1
	var yarikler := _kumeler(b, yarik)
	var buyuk: Array = []
	for comp in yarikler:
		if comp.size() >= 3:
			buyuk.append(comp)
	out.append("[DAR YARIK] ince bir cisim girer ama kapsul sigmaz (kapsul genisliginden dar bosluk, >=3 nokta): %d" % buyuk.size())
	for comp in buyuk:
		var p := _nokta(b, int(comp[0]) % b.nx, int(comp[0]) / b.nx)
		out.append("   " + _kutu(b, comp) + " | yakin: " + yakin(p))
	# 4) hareket testi: her boş düğümde 8 yönde; engele komşu olanlarda çıkış yok mu
	var takili: Array = []
	var yon_az: Array = []
	for j in b.nz:
		for i in b.nx:
			var idx := j * b.nx + i
			if b.bos[idx] == 0:
				continue
			# yalnız çevresinde engel olan düğümleri dene (açık alanda zaten serbest)
			var kenar := false
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var ii: int = i + di
					var jj: int = j + dj
					if ii < 0 or jj < 0 or ii >= b.nx or jj >= b.nz:
						continue
					if b.oyun[jj * b.nx + ii] == 1 and b.bos[jj * b.nx + ii] == 0:
						kenar = true
			if not kenar:
				continue
			var p := _nokta(b, i, j)
			var c := cikis(p)
			if c.en_iyi < 0.15:
				takili.append(idx)
			elif c.yon <= 2:
				yon_az.append(idx)
	var tk := PackedByteArray()
	tk.resize(b.bos.size())
	for idx in takili:
		tk[idx] = 1
	var tkum := _kumeler(b, tk)
	out.append("[TAKILI] bos noktada 8 yonun hicbirinde 0,15 m bile ilerlenemiyor: %d nokta, %d kume" % [takili.size(), tkum.size()])
	toplam_takili += takili.size()
	for comp in tkum:
		var p := _nokta(b, int(comp[0]) % b.nx, int(comp[0]) / b.nx)
		out.append("   " + _kutu(b, comp) + " | yakin: " + yakin(p))
	var ya := PackedByteArray()
	ya.resize(b.bos.size())
	for idx in yon_az:
		ya[idx] = 1
	var yakum := _kumeler(b, ya)
	out.append("[DAR KOSE] 8 yonden en cok 2'sine ilerlenebiliyor (kose/kama): %d nokta, %d kume" % [yon_az.size(), yakum.size()])
	for comp in yakum:
		if comp.size() < 2:
			continue
		var p := _nokta(b, int(comp[0]) % b.nx, int(comp[0]) / b.nx)
		out.append("   " + _kutu(b, comp) + " | yakin: " + yakin(p))
	# 5) gömülü noktalar: kapsül çekirdeği (r=0,1) çarpışmanın içinde; oyun içinde buraya ışınlanırsa çıkabilir mi
	var gom := PackedByteArray()
	gom.resize(b.bos.size())
	var gom_n := 0
	var gom_cik := 0
	var gom_takili: Array = []
	for j in b.nz:
		for i in b.nx:
			var idx := j * b.nx + i
			if b.oyun[idx] == 0 or b.bos[idx] == 1:
				continue
			var p := _nokta(b, i, j)
			if bos_mu(p, 0.1):
				continue
			# yalnız gömülü ama duvar içi olmayan: oda içinde (kutu eşyaların içi)
			gom_n += 1
			var c := cikis(p)
			if c.bos_son:
				gom_cik += 1
			else:
				gom_takili.append(idx)
				gom[idx] = 1
	out.append("[GOMULU] kapsul cekirdegi cismin icinde (eşya ici) %d nokta; 8 yonde itince bos yere cikan %d, cikamayan %d" % [gom_n, gom_cik, gom_takili.size()])
	var gk := _kumeler(b, gom)
	for comp in gk:
		var p := _nokta(b, int(comp[0]) % b.nx, int(comp[0]) / b.nx)
		out.append("   " + _kutu(b, comp) + " | yakin: " + yakin(p))


# fark düğümleri iç düğümlerden büyütülür (yalnız iç düğümü olan bileşenler kalır)
func _genislet(b: Bolge, tohum: PackedByteArray, fark: PackedByteArray) -> PackedByteArray:
	var kum := _kumeler(b, fark)
	var res := PackedByteArray()
	res.resize(fark.size())
	for comp in kum:
		var var_mi := false
		for idx in comp:
			if tohum[idx] == 1:
				var_mi = true
				break
		if var_mi:
			for idx in comp:
				res[idx] = 1
	return res


var _er_onbellek := {}


func _erisim_tohumlu(b: Bolge, r: float) -> PackedByteArray:
	var t: Vector3 = main.cells[0].spawn_world() if b.ad.begins_with("hucre") else main.lobby.spawn_point(0)
	return _erisim(b, t, r)


# ---------- oyunun gerçek ışınlama noktaları ----------

func _senaryolar(durum: String) -> void:
	out.append("--- oyun icindeki gercek konumlar (durum: klozet %s) ---" % durum)
	for c in main.cells:
		var noktalar := {
			"dogma (spawn_world)": c.spawn_world(),
			"uzak oyuncu dogma": c.spawn_world() + Vector3(0.3, 0, -0.6),
			"kuyudan cikis (kacis_ui _yukari_cik)": c.klozet_delik.global_position + Vector3(-0.7, 0.05, 0.6),
			"kuyunun tam ustu": c.klozet_delik.global_position,
			"kuyudan cikis (YENI, kuyu_cikis_world)": c.kuyu_cikis_world() if c.has_method("kuyu_cikis_world") else c.klozet_delik.global_position + Vector3(0.0, 0.05, 0.6),
		}
		for k in noktalar:
			var p: Vector3 = noktalar[k]
			p.y = Y0
			var bos := bos_mu(p, R)
			var cs := cikis(p)
			var dur := "BOS" if bos else "GOMULU"
			var sonuc := ""
			if not bos:
				sonuc = "cikis: %s (en iyi %.2f m, %d yon)" % ["EVET" if cs.bos_son else "HAYIR", cs.en_iyi, cs.yon]
			else:
				sonuc = "serbest (en iyi %.2f m, %d yon)" % [cs.en_iyi, cs.yon]
			var bayrak := "" if (bos or cs.bos_son) else "  <<< TAKILIR"
			if not bos and cs.bos_son:
				bayrak = "  <<< gomulu (itilerek kurtulur)"
			out.append("   hucre %d | %-40s | %s | %s%s | yakin: %s" % [c.number, k, dur, sonuc, bayrak, yakin(p)])
			if not bos and not cs.bos_son:
				toplam_takili += 1


func _rulet_notu() -> void:
	var c := Vector3(3.9, 0.0, 0.0)
	var sayi := 0
	var q2 := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 1.2
	q2.shape = s
	q2.transform = Transform3D(Basis(), c + Vector3(0, 0.9, 0))
	for h in space.intersect_shape(q2, 16):
		var co: Object = h.collider
		if co is CollisionObject3D and not (co is CharacterBody3D):
			sayi += 1
	out.append("RULET MASASI: koridor ortasinda (3.9, 0, 0) 1,2 m yaricap icinde sabit cisim sayisi = %d (masa ve tabureler gorsel; oyun sirasinda oyuncular oturur)" % sayi)
	out.append("TOPLAM TAKILI/GOMULU-CIKAMAZ: %d" % toplam_takili)
