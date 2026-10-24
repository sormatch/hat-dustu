# Bir kerelik araç: mahkum modelinin dokusu (UV) üzerinde vücut bölgesi maskesi üretir.
# R = gövde, G = kol (değer omuzdan bileğe uzaklık), B = bacak. Model T-pozunda: kollar yana açık.
extends SceneTree

const N := 512

func _init() -> void:
	var root: Node = load("res://assets/karakter/mahkum.fbx").instantiate()
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))
	var hip_y := 0.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		var xf: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := -lo
			for q in v:
				var w := xf * q
				lo = lo.min(w)
				hi = hi.max(w)
			print("boyut ", lo, " ", hi)
			var height := hi.y - lo.y
			for t in range(0, idx.size(), 3):
				var a := xf * v[idx[t]]
				var b := xf * v[idx[t + 1]]
				var c := xf * v[idx[t + 2]]
				var cen := (a + b + c) / 3.0
				var hy := (cen.y - lo.y) / height  # 0 ayak, 1 baş
				var half_w := (hi.x - lo.x) / 2.0
				var ax := absf(cen.x - (lo.x + hi.x) / 2.0) / half_w  # 0 orta, 1 parmak ucu
				var col := Color(0, 0, 0)
				if ax > 0.2 and hy > 0.7:
					col = Color(0, clampf((ax - 0.2) / 0.8, 0.01, 1.0), 0)  # kol
				elif hy > 0.53:
					col = Color(1, 0, 0)  # gövde
				else:
					col = Color(0, 0, 1)  # bacak
				_fill(img, uv[idx[t]], uv[idx[t + 1]], uv[idx[t + 2]], col)
	img.save_png("res://assets/karakter/bolgeler.png")
	print("bitti")
	quit()

func _fill(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var pa := a * N
	var pb := b * N
	var pc := c * N
	var mn := pa.min(pb).min(pc).floor()
	var mx := pa.max(pb).max(pc).ceil()
	for y in range(maxi(0, int(mn.y) - 1), mini(N, int(mx.y) + 2)):
		for x in range(maxi(0, int(mn.x) - 1), mini(N, int(mx.x) + 2)):
			var p := Vector2(x + 0.5, y + 0.5)
			if _inside(p, pa, pb, pc, 1.2):
				img.set_pixel(x, y, col)

func _inside(p: Vector2, a: Vector2, b: Vector2, c: Vector2, grow: float) -> bool:
	var cen := (a + b + c) / 3.0
	a = cen + (a - cen) * (1.0 + grow / maxf(1.0, (a - cen).length()))
	b = cen + (b - cen) * (1.0 + grow / maxf(1.0, (b - cen).length()))
	c = cen + (c - cen) * (1.0 + grow / maxf(1.0, (c - cen).length()))
	var d1 := (p - b).cross(a - b)
	var d2 := (p - c).cross(b - c)
	var d3 := (p - a).cross(c - a)
	return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
