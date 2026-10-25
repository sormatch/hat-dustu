# Bir kerelik araç: assets/kes içindeki 2x2 ızgara resimlerini 4'e böler, boş/şeffaf kenarı kırpar, adlandırıp yerine koyar.
# Çalıştırma: Godot --headless --path . --script res://tools/kes.gd
extends SceneTree

# ızgara: [hedef klasör, sol üst, sağ üst, sol alt, sağ alt, en büyük kenar]
const PLAN := {
	"sheet_sandik": ["ui", "chest_wood", "chest_wood_open", "chest_gold", "chest_gold_open", 512],
	"sheet_ikon1": ["ui", "icon_beard", "icon_chest", "icon_deal", "icon_room", 256],
	"sheet_ikon2": ["ui", "icon_tattoo", "icon_hat", "icon_chat", "icon_gift", 256],
	"sheet_ikon3": ["ui", "icon_lock", "icon_trophy", "icon_gem", "icon_coin", 256],
	"sheet_rozet": ["ui", "rozet_caylak", "rozet_kidemli", "rozet_patron", "rozet_efsane", 256],
	"sheet_elmas": ["ui", "gem_pack_1", "gem_pack_2", "gem_pack_3", "gem_pack_4", 384],
	"sheet_dovme1": ["dovme", "dovme_kafatasi", "dovme_gul", "dovme_kartal", "dovme_ejderha", 512],
	"sheet_dovme2": ["dovme", "dovme_orumcek_agi", "dovme_gozyasi", "dovme_kalp", "dovme_kaplan", 512],
	"sheet_yara": ["dovme", "yara_uzun", "yara_dikis", "yara_kisa", "yara_pence", 512],
	"sheet_sigorta": ["ui", "salter_kapali", "salter_acik", "soket", "tus", 256],
	"sheet_poster1": ["poster", "poster_sahil", "poster_araba", "poster_boks", "poster_aranan", 768],
	"sheet_poster2": ["poster", "poster_takvim", "poster_harita", "poster_uzay", "poster_kedi", 768],
}


func _init() -> void:
	for sheet in PLAN:
		var path := "res://assets/kes/%s.png" % sheet
		if not FileAccess.file_exists(path):
			print("yok: ", sheet)
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		img.convert(Image.FORMAT_RGBA8)
		var plan: Array = PLAN[sheet]
		var dir := "res://assets/" + str(plan[0])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var hw := img.get_width() / 2
		var hh := img.get_height() / 2
		var alpha := _has_alpha(img)
		for i in 4:
			var part := img.get_region(Rect2i((i % 2) * hw, (i / 2) * hh, hw, hh))
			if alpha:
				_keep_main(part)
			var r := part.get_used_rect() if alpha else _content_rect(part)
			if r.size.x < 8 or r.size.y < 8:
				r = Rect2i(0, 0, hw, hh)
			var pad := 6
			r = r.grow(pad).intersection(Rect2i(0, 0, hw, hh))
			part = part.get_region(r)
			var big: int = plan[5]
			var s := float(big) / maxf(part.get_width(), part.get_height())
			if s < 1.0:
				part.resize(int(part.get_width() * s), int(part.get_height() * s), Image.INTERPOLATE_LANCZOS)
			var out := "%s/%s.png" % [dir, plan[i + 1]]
			part.save_png(ProjectSettings.globalize_path(out))
			print(sheet, " -> ", out, " ", part.get_size(), " seffaf=", alpha)
	quit()


func _has_alpha(img: Image) -> bool:
	var n := 0
	for y in range(0, img.get_height(), 16):
		for x in range(0, img.get_width(), 16):
			if img.get_pixel(x, y).a < 0.5:
				n += 1
	return n > 50


# Şeffaflığı olmayan resimde (poster) kenardaki koyu/boş şeridi atlayıp içeriği bulur.
func _content_rect(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var bg := img.get_pixel(1, 1)
	var x0 := 0
	var x1 := w - 1
	var y0 := 0
	var y1 := h - 1
	var differs := func(c: Color) -> bool: return absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.25
	while x0 < w / 3 and not differs.call(img.get_pixel(x0, h / 2)):
		x0 += 1
	while x1 > w * 2 / 3 and not differs.call(img.get_pixel(x1, h / 2)):
		x1 -= 1
	while y0 < h / 3 and not differs.call(img.get_pixel(w / 2, y0)):
		y0 += 1
	while y1 > h * 2 / 3 and not differs.call(img.get_pixel(w / 2, y1)):
		y1 -= 1
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


# Şeffaf resimde asıl nesneyi bulur: satır/sütun doluluk profilinde en dolu kesintisiz bölge
# (komşu karedeki taşmalar ve tek tük lekeler dışarıda kalır).
func _blob_rect(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var rows := PackedInt32Array()
	rows.resize(h)
	var cols := PackedInt32Array()
	cols.resize(w)
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.35:
				rows[y] += 1
				cols[x] += 1
	var ry := _best_run(rows, 3, 10)
	var rx := _best_run(cols, 3, 10)
	return Rect2i(rx.x, ry.x, rx.y - rx.x + 1, ry.y - ry.x + 1)


func _best_run(prof: PackedInt32Array, min_fill: int, gap: int) -> Vector2i:
	var best := Vector2i(0, prof.size() - 1)
	var best_sum := -1
	var start := -1
	var last := -1
	var total := 0
	for i in prof.size() + gap + 1:
		var on := i < prof.size() and prof[i] >= min_fill
		if on:
			if start < 0:
				start = i
				total = 0
			last = i
			total += prof[i]
		elif start >= 0 and i - last > gap:
			if total > best_sum:
				best_sum = total
				best = Vector2i(start, last)
			start = -1
	return best


# Ana nesneye bağlı olmayan parçaları (komşu karenin taşan parıltısı, lekeler) siler.
# En büyük bağlı bölge ve kenara değmeyen diğer parçalar (çizgiler, kıvılcımlar) kalır.
func _keep_main(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var label := PackedInt32Array()
	label.resize(w * h)
	var sizes := [0]
	var boxes := [Rect2i()]
	var stack := PackedInt32Array()
	for start in w * h:
		if label[start] != 0 or img.get_pixel(start % w, start / w).a <= 0.08:
			continue
		var id := sizes.size()
		var n := 0
		var box := Rect2i(start % w, start / w, 1, 1)
		label[start] = id
		stack.append(start)
		while stack.size() > 0:
			var q := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			n += 1
			var qx := q % w
			var qy := q / w
			box = box.expand(Vector2i(qx, qy))
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = qx + d.x
				var ny: int = qy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := ny * w + nx
				if label[ni] == 0 and img.get_pixel(nx, ny).a > 0.08:
					label[ni] = id
					stack.append(ni)
		sizes.append(n)
		boxes.append(box)
	var main := 1
	for i in range(1, sizes.size()):
		if sizes[i] > sizes[main]:
			main = i
	# kenara değen (komşu kareden taşan) ve çok küçük parçalar silinir, gerisi kalır
	var inner := Rect2i(2, 2, w - 4, h - 4)
	var keep := {}
	for i in range(1, sizes.size()):
		var bx: Rect2i = boxes[i]
		if i == main or (inner.encloses(bx) and sizes[i] >= 12):
			keep[i] = true
	for y in h:
		for x in w:
			var l := label[y * w + x]
			if l == 0 or not keep.has(l):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
