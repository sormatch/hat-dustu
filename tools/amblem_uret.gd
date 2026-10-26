# Açılış amblemi: yazısız taban (OpenAI, assets/ui/uretim/kaynak/amblem_taban.png; tools/gorsel_uret.mjs amblem_taban)
# üstüne logodaki (assets/ui/uretim/logo.png) paslı-perçinli "HAT" üst yay, "DÜŞTÜ" alt yay boyunca bükülerek
# konur (model Türkçe harfleri bozabildiği için harfler logodan alınır: Ü noktaları ve Ş çengeli logodakiyle aynı).
# Çıktılar:
#   kaynak/amblem.png                 tam amblem 1024x1024 (önizleme; açılış ekranı bundan yapılır)
#   assets/ui/uretim/amblem_zemin.png  ahizesi silinmiş taban (scripts/acilis.gd katmanı)
#   assets/ui/uretim/amblem_tel.png    ahize (kırpık; titreyerek çalar)
#   assets/ui/uretim/amblem_hat.png    "HAT" (kırpık; gölge + turuncu ışıma dahil)
#   assets/ui/uretim/amblem_dustu.png  "DÜŞTÜ" (kırpık)
# Kırpık katmanların 1024'lük tuvaldeki yeri sonda yazdırılır; scripts/acilis.gd KATMAN sabitiyle AYNI olmalı.
# Kullanım: Godot --path . --headless --script res://tools/amblem_uret.gd  [-- hata=1 (ara görüntüler build/amblem/)]
extends SceneTree

const N := 1024
const MERKEZ := Vector2(511.5, 501.5)  # tabanın daire merkezi (saydamlık kutusundan)
const R_UST := 360.0  # "HAT" gövdesinin ortası (gri bant ~290-370, neon ~390; harfler neona taşar, iç daireye taşmaz)
const R_ALT := 354.0  # "DÜŞTÜ" (alt bant biraz dar: ~286-352, neon ~375)
const OLCEK_R := 0.62  # logo pikseli -> amblem pikseli (yarıçap yönünde)
const OLCEK_T := 0.74  # logo pikseli -> yay uzunluğu (biraz geniş: kavis boyunca daha iyi okunur)
# logodaki kelime kutuları (saydamlık bileşenleri: HAT x40-497, DÜŞTÜ x514-1170, y40-305)
const HAT_KUTU := Rect2i(36, 36, 466, 274)
const DUSTU_KUTU := Rect2i(510, 36, 664, 274)
const HAT_GOVDE := Vector2(67, 304)  # HAT harflerinin üst/alt satırı (yaya ortalamak için)
const DUSTU_GOVDE := Vector2(67, 304)  # DÜŞTÜ gövdesi (Ü noktaları ve Ş çengeli bunun dışında taşar)

var hata := false
var KAYNAK := ProjectSettings.globalize_path("res://assets/ui/uretim/kaynak/")
var URETIM := ProjectSettings.globalize_path("res://assets/ui/uretim/")
var HATA_DIR := ProjectSettings.globalize_path("res://build/amblem/")


func _init() -> void:
	hata = OS.get_cmdline_user_args().has("hata=1")
	DirAccess.make_dir_recursive_absolute(HATA_DIR)
	var taban := Image.load_from_file(KAYNAK + "amblem_taban.png")
	taban.convert(Image.FORMAT_RGBA8)
	var logo := Image.load_from_file(URETIM + "logo.png")
	logo.convert(Image.FORMAT_RGBA8)
	# --- yazılar ---
	var hat := _kelime(logo.get_region(HAT_KUTU), true, HAT_GOVDE - Vector2(HAT_KUTU.position.y, HAT_KUTU.position.y))
	var dustu := _kelime(logo.get_region(DUSTU_KUTU), false, DUSTU_GOVDE - Vector2(DUSTU_KUTU.position.y, DUSTU_KUTU.position.y))
	# --- ahize: kırmızı plastik (ton ~0°) tabandan ayrılır, deliği çevresinden doldurulur ---
	var maske := _ahize_maskesi(taban)
	var tel := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var zemin := taban.duplicate() as Image
	for y in N:
		for x in N:
			var m := maske.get_pixel(x, y).r
			if m > 0.0:
				var c := taban.get_pixel(x, y)
				tel.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * m))
	_doldur(zemin, maske)
	# --- tam amblem ---
	var tam := zemin.duplicate() as Image
	tam.blend_rect(tel, Rect2i(0, 0, N, N), Vector2i.ZERO)
	tam.blend_rect(hat, Rect2i(0, 0, N, N), Vector2i.ZERO)
	tam.blend_rect(dustu, Rect2i(0, 0, N, N), Vector2i.ZERO)
	tam.save_png(KAYNAK + "amblem.png")
	zemin.save_png(URETIM + "amblem_zemin.png")
	if hata:
		maske.save_png(HATA_DIR + "ahize_maske.png")
		zemin.save_png(HATA_DIR + "zemin_ahizesiz.png")
	var rapor := []
	for p in [["amblem_tel", tel], ["amblem_hat", hat], ["amblem_dustu", dustu]]:
		var img: Image = p[1]
		var r := img.get_used_rect().grow(2).intersection(Rect2i(0, 0, N, N))
		img.get_region(r).save_png(URETIM + p[0] + ".png")
		rapor.append('"%s": Rect2(%d, %d, %d, %d)' % [p[0].trim_prefix("amblem_"), r.position.x, r.position.y, r.size.x, r.size.y])
	print("[amblem] tamam. acilis.gd KATMAN = {", ", ".join(rapor), "}")
	quit()


# Kelimeyi yaya bük: ust=true -> üst yay (harf tepesi dışta), false -> alt yay (harf tepesi merkeze bakar, soldan
# sağa okunur). Gölge (koyu, dışa doğru) ve turuncu ışıma eklenir. 1024x1024 saydam katman döner.
func _kelime(src: Image, ust: bool, govde: Vector2) -> Image:
	var sw := src.get_width()
	var sh := src.get_height()
	var uc := sw / 2.0
	var vc := (govde.x + govde.y) / 2.0  # gövde ortası bant ortasına gelir
	var R_ORTA := R_UST if ust else R_ALT
	var yaz := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var a_ext := (sw / 2.0 + 4.0) * OLCEK_T / R_ORTA
	var r_min := R_ORTA - (sh - vc + 4.0) * OLCEK_R
	var r_max := R_ORTA + (vc + 4.0) * OLCEK_R
	if not ust:
		r_min = R_ORTA - (vc + 4.0) * OLCEK_R
		r_max = R_ORTA + (sh - vc + 4.0) * OLCEK_R
	var bas := -PI / 2.0 if ust else PI / 2.0
	for y in N:
		for x in N:
			var d := Vector2(x + 0.5, y + 0.5) - MERKEZ
			var r := d.length()
			if r < r_min or r > r_max:
				continue
			var th := wrapf(atan2(d.y, d.x) - bas, -PI, PI)
			if absf(th) > a_ext:
				continue
			var u: float
			var v: float
			if ust:
				u = uc + th * R_ORTA / OLCEK_T
				v = vc + (R_ORTA - r) / OLCEK_R
			else:
				u = uc - th * R_ORTA / OLCEK_T
				v = vc + (r - R_ORTA) / OLCEK_R
			var c := _ornek(src, u - 0.5, v - 0.5)
			if c.a > 0.0:
				yaz.set_pixel(x, y, c)
	# gölge + ışıma (kelimenin kutusunda)
	var kutu := yaz.get_used_rect().grow(28).intersection(Rect2i(0, 0, N, N))
	var alfa := PackedFloat32Array()
	alfa.resize(kutu.size.x * kutu.size.y)
	for y in kutu.size.y:
		for x in kutu.size.x:
			alfa[y * kutu.size.x + x] = yaz.get_pixel(kutu.position.x + x, kutu.position.y + y).a
	var golge := _bulanik(alfa, kutu.size, 5, 2)
	var isik := _bulanik(alfa, kutu.size, 12, 3)
	var out := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var gol_ofs := Vector2i(0, 5)
	for y in kutu.size.y:
		for x in kutu.size.x:
			var px := kutu.position + Vector2i(x, y)
			var i := y * kutu.size.x + x
			# ışıma (turuncu, logonun neon kenarı gibi)
			var c := Color(1.0, 0.42, 0.08, clampf(isik[i] * 0.75, 0.0, 0.6))
			# gölge (kelimenin altına doğru kaydırılmış)
			var gx := x - gol_ofs.x
			var gy := y - gol_ofs.y
			if gx >= 0 and gy >= 0 and gx < kutu.size.x and gy < kutu.size.y:
				c = _ust(c, Color(0.02, 0.01, 0.0, clampf(golge[gy * kutu.size.x + gx] * 1.1, 0.0, 0.85)))
			c = _ust(c, yaz.get_pixelv(px))
			out.set_pixelv(px, c)
	return out


func _ust(alt: Color, ust: Color) -> Color:
	var a := ust.a + alt.a * (1.0 - ust.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var rgb := (Color(ust.r, ust.g, ust.b) * ust.a + Color(alt.r, alt.g, alt.b) * alt.a * (1.0 - ust.a)) / a
	return Color(rgb.r, rgb.g, rgb.b, a)


func _ornek(img: Image, u: float, v: float) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	if u < -1.0 or v < -1.0 or u > w or v > h:
		return Color(0, 0, 0, 0)
	var x0 := floori(u)
	var y0 := floori(v)
	var fx := u - x0
	var fy := v - y0
	var c := Color(0, 0, 0, 0)
	var top_a := 0.0
	var rgb := Color(0, 0, 0, 0)
	for j in 2:
		for i in 2:
			var xx := x0 + i
			var yy := y0 + j
			var wgt := (fx if i == 1 else 1.0 - fx) * (fy if j == 1 else 1.0 - fy)
			if xx < 0 or yy < 0 or xx >= w or yy >= h or wgt <= 0.0:
				continue
			var p := img.get_pixel(xx, yy)
			top_a += p.a * wgt
			rgb += Color(p.r, p.g, p.b) * p.a * wgt  # önçarpımlı (saydam kenarda koyu saçak olmasın)
	if top_a <= 0.0001:
		return c
	return Color(rgb.r / top_a, rgb.g / top_a, rgb.b / top_a, top_a)


# Ayrılabilir kutu bulanıklığı (geçiş sayısı kadar).
func _bulanik(a: PackedFloat32Array, boy: Vector2i, yar: int, gecis: int) -> PackedFloat32Array:
	var w := boy.x
	var h := boy.y
	var cur := a.duplicate()
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	var n := float(2 * yar + 1)
	for _g in gecis:
		for y in h:
			var s := 0.0
			for k in range(-yar, yar + 1):
				s += cur[y * w + clampi(k, 0, w - 1)]
			for x in w:
				tmp[y * w + x] = s / n
				s += cur[y * w + clampi(x + yar + 1, 0, w - 1)] - cur[y * w + clampi(x - yar, 0, w - 1)]
		for x in w:
			var s := 0.0
			for k in range(-yar, yar + 1):
				s += tmp[clampi(k, 0, h - 1) * w + x]
			for y in h:
				cur[y * w + x] = s / n
				s += tmp[clampi(y + yar + 1, 0, h - 1) * w + x] - tmp[clampi(y - yar, 0, h - 1) * w + x]
	return cur


# Ahize maskesi: iç dairede (r < 282) tonu kırmızıya yakın (sarı-turuncu arka plan ve kıvılcımlar değil), doygun
# pikseller; en büyük bileşen, delikleri kapatılır, kenarı 1,5 px yumuşatılır.
func _ahize_maskesi(img: Image) -> Image:
	var ham := PackedByteArray()
	ham.resize(N * N)
	for y in N:
		for x in N:
			if Vector2(x, y).distance_to(MERKEZ) > 282.0:
				continue
			var c := img.get_pixel(x, y)
			var h := c.h * 360.0
			var kirmizi := (h < 11.0 or h > 340.0) and c.s > 0.45 and c.v > 0.22
			var parlak := (h < 14.0 or h > 330.0) and c.s > 0.12 and c.v > 0.75  # parlama (pembe-beyaz)
			if kirmizi or parlak:
				ham[y * N + x] = 1
	# en büyük bileşen
	var etiket := PackedInt32Array()
	etiket.resize(N * N)
	var en_buyuk := 0
	var en_boy := 0
	var no := 0
	for i in N * N:
		if ham[i] == 0 or etiket[i] != 0:
			continue
		no += 1
		var yigin := [i]
		etiket[i] = no
		var say := 0
		while not yigin.is_empty():
			var p: int = yigin.pop_back()
			say += 1
			var px := p % N
			for q in [p - 1, p + 1, p - N, p + N]:
				if q < 0 or q >= N * N or absi(q % N - px) > 1:
					continue
				if ham[q] == 1 and etiket[q] == 0:
					etiket[q] = no
					yigin.append(q)
		if say > en_boy:
			en_boy = say
			en_buyuk = no
	var m := PackedFloat32Array()
	m.resize(N * N)
	for i in N * N:
		m[i] = 1.0 if etiket[i] == en_buyuk else 0.0
	# kapatma: genişlet 3 + daralt 3 (parlama/çizgi delikleri dolsun)
	m = _morf(m, 3, true)
	m = _morf(m, 3, false)
	# delik doldurma: dışarıdan ulaşılamayan boşluklar maskeye katılır
	var dis := PackedByteArray()
	dis.resize(N * N)
	var yig := [0]
	dis[0] = 1
	while not yig.is_empty():
		var p: int = yig.pop_back()
		var px := p % N
		for q in [p - 1, p + 1, p - N, p + N]:
			if q < 0 or q >= N * N or absi(q % N - px) > 1:
				continue
			if dis[q] == 0 and m[q] < 0.5:
				dis[q] = 1
				yig.append(q)
	for i in N * N:
		if dis[i] == 0:
			m[i] = 1.0
	# 1 px dışa taşır (kenar halesi tabanda kalmasın), sonra yumuşat
	m = _morf(m, 1, true)
	m = _bulanik(m, Vector2i(N, N), 1, 2)
	var out := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var v := m[y * N + x]
			if v > 0.0:
				out.set_pixel(x, y, Color(v, v, v, 1.0))
	return out


# Ayrılabilir genişletme / daraltma (yalnız iç daire kutusunda).
func _morf(m: PackedFloat32Array, yar: int, genislet: bool) -> PackedFloat32Array:
	var x0 := int(MERKEZ.x) - 290
	var x1 := int(MERKEZ.x) + 290
	var y0 := int(MERKEZ.y) - 290
	var y1 := int(MERKEZ.y) + 290
	var tmp := m.duplicate()
	for y in range(y0, y1):
		for x in range(x0, x1):
			var v := m[y * N + x]
			for k in range(-yar, yar + 1):
				var q := m[y * N + x + k]
				v = maxf(v, q) if genislet else minf(v, q)
			tmp[y * N + x] = v
	var out := tmp.duplicate()
	for y in range(y0, y1):
		for x in range(x0, x1):
			var v := tmp[y * N + x]
			for k in range(-yar, yar + 1):
				var q := tmp[(y + k) * N + x]
				v = maxf(v, q) if genislet else minf(v, q)
			out[y * N + x] = v
	return out


# Maskelenen (ahize) bölgeyi çevresindeki tabandan doldurur: halka halka içeri doğru komşu ortalaması, sonra
# hafif bulanıklık (ahize küçük açıyla titrediğinde altından "hayalet" ahize görünmesin).
func _doldur(img: Image, maske: Image) -> void:
	var r := maske.get_used_rect().grow(4)
	var w := r.size.x
	var h := r.size.y
	var bilinen := PackedByteArray()
	bilinen.resize(w * h)
	var renk: Array[Color] = []
	renk.resize(w * h)
	for y in h:
		for x in w:
			var p := r.position + Vector2i(x, y)
			var m := maske.get_pixelv(p).r
			renk[y * w + x] = img.get_pixelv(p)
			bilinen[y * w + x] = 1 if m < 0.02 else 0
	var degisti := true
	while degisti:
		degisti = false
		var yeni: Array[int] = []
		var yeni_renk: Array[Color] = []
		for y in h:
			for x in w:
				var i := y * w + x
				if bilinen[i] == 1:
					continue
				var top := Color(0, 0, 0, 0)
				var say := 0
				for j in range(-1, 2):
					for k in range(-1, 2):
						var xx := x + k
						var yy := y + j
						if xx < 0 or yy < 0 or xx >= w or yy >= h:
							continue
						if bilinen[yy * w + xx] == 1:
							top += renk[yy * w + xx]
							say += 1
				if say > 0:
					yeni.append(i)
					yeni_renk.append(top / say)
		for n in yeni.size():
			bilinen[yeni[n]] = 1
			renk[yeni[n]] = yeni_renk[n]
			degisti = true
	# doldurulan bölgede bulanıklık + kararma (ahizenin gölgesi gibi)
	for y in h:
		for x in w:
			var p := r.position + Vector2i(x, y)
			var m := maske.get_pixelv(p).r
			if m <= 0.0:
				continue
			var top := Color(0, 0, 0, 0)
			var say := 0
			for j in range(-6, 7, 2):
				for k in range(-6, 7, 2):
					var xx := clampi(x + k, 0, w - 1)
					var yy := clampi(y + j, 0, h - 1)
					top += renk[yy * w + xx]
					say += 1
			var c: Color = top / say
			c = c.darkened(0.35)
			c.a = 1.0
			img.set_pixelv(p, img.get_pixelv(p).lerp(c, m))
