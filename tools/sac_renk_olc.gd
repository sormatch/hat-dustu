# Saç rengi denetimi: her saç stili x her saç rengi mağaza kartıyla aynı ışıkta (scripts/thumbs.gd _render) çekilir,
# kafadaki saç/sakal parçaları gizlenerek ikinci kez çekilir; fark eden pikseller saçtır. Saçın ortalama rengi
# katalogdaki renkle (mağazadaki renk kartı) karşılaştırılır. Her hücrenin altında: sol yarı katalog rengi,
# sağ yarı ölçülen ortalama. Konsola ton (derece) ve parlaklık farkı yazılır.
# Kullanım (görüntü gerekir, --headless değil):
#   Godot --path . --resolution 640x360 --script res://tools/sac_renk_olc.gd -- cikti=build/sac_renk/x.png
#     [satirlar=erkek:kisa,kadin:uzun_duz,erkek:kel:sakal]  (gövde:saç[:sakal])
extends SceneTree

const Thumbs := preload("res://scripts/thumbs.gd")
const Catalog := preload("res://scripts/catalog.gd")
const VARSAYILAN := "erkek:kisa,kadin:uzun_duz,erkek:mohawk,kadin:ikiz_orgu,erkek:rasta,kadin:kivircik,erkek:ayrik,erkek:kel:dolgun"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var rows: PackedStringArray = str(args.get("satirlar", VARSAYILAN)).split(",", false)
	var th: Node = Thumbs.new()
	root.add_child(th)
	var n := Catalog.HAIR_COLORS.size()
	var cell := 200
	var strip := 34
	var out := Image.create(n * cell, rows.size() * (cell + strip), false, Image.FORMAT_RGBA8)
	out.fill(Color("#2a2d36"))
	var toplam := 0.0
	for r in rows.size():
		var p: PackedStringArray = rows[r].split(":")
		var line := "%-22s" % rows[r]
		for c in n:
			var look := Thumbs.temel_gorunus("kadin" if p[0].begins_with("kadin") else "erkek")
			look.govde = p[0]
			look.sac = p[1]
			look.sakal = p[2] if p.size() > 2 else "yok"
			look.sac_renk = c
			var cat := "sac"
			var full: Image = await _shot(th, look, cat, false)
			var bare: Image = await _shot(th, look, cat, true)
			var sum := Vector3.ZERO
			var cnt := 0
			for y in full.get_height():
				for x in full.get_width():
					var a := full.get_pixel(x, y)
					var b := bare.get_pixel(x, y)
					if a.a > 0.9 and (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)) > 0.12:
						sum += Vector3(a.r, a.g, a.b)
						cnt += 1
			var mean := Color(sum.x / maxi(cnt, 1), sum.y / maxi(cnt, 1), sum.z / maxi(cnt, 1))
			var want := Color(Catalog.HAIR_COLORS[c])
			var dh := 0.0
			if want.s > 0.15 and mean.s > 0.05:
				dh = fposmod(mean.h - want.h + 0.5, 1.0) - 0.5
			var dl := mean.get_luminance() - want.get_luminance()
			toplam += absf(dl) + absf(dh) * 2.0
			line += "  %s:h%+4d l%+.2f s%+.2f" % [c, int(dh * 360), dl, mean.s - want.s]
			full.resize(cell, cell)
			out.blend_rect(full, Rect2i(0, 0, cell, cell), Vector2i(c * cell, r * (cell + strip)))
			out.fill_rect(Rect2i(c * cell, r * (cell + strip) + cell, cell / 2, strip - 4), want)
			out.fill_rect(Rect2i(c * cell + cell / 2, r * (cell + strip) + cell, cell / 2, strip - 4), mean)
		print("[sac_renk] ", line)
	print("[sac_renk] toplam sapma: %.2f" % toplam)
	var path := ProjectSettings.globalize_path(str(args.get("cikti", "res://build/sac_renk/olcum.png")))
	print("[sac_renk] kayit ", path, " -> ", out.save_png(path))
	quit()


# Kartla aynı çekim; gizle: kafadaki saç/sakal parçaları gizlenir (maske için).
func _shot(th: Node, look: Dictionary, cat: String, gizle: bool) -> Image:
	if gizle:
		_gizle_bekle(th)
	var tex: Texture2D = await th._render(look, cat, str(look.sac))
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


# _render karakteri ekler, 3 kare bekler, çeker: kafa parçaları takılınca (1 kare sonra) gizlenir.
func _gizle_bekle(th: Node) -> void:
	var cb := func(n: Node) -> void:
		if n.get_script() == Thumbs.BodyScript:
			_gizle_sonra.call_deferred(n)
	th.child_entered_tree.connect(func(sv: Node) -> void: sv.child_entered_tree.connect(cb), CONNECT_ONE_SHOT)


func _gizle_sonra(body: Node) -> void:
	for i in 2:
		await process_frame
		if not is_instance_valid(body):
			return
		var h: Node3D = body.get("_head")
		if h:
			for ch in h.get_children():
				if ch is MeshInstance3D:
					(ch as MeshInstance3D).visible = false
