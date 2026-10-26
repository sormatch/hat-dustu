# Mağaza küçük resimlerini PAKETE pişirir (telefonda karakter çekilmesin: donma ve bellek yükü olmasın).
# Her eşya erkek ve kadın temel görünüşüyle (scripts/thumbs.gd temel_gorunus) çekilir:
#   assets/kucuk/erkek/<kategori>_<kimlik>.webp, assets/kucuk/kadin/..., gövdeler assets/kucuk/govde_<kimlik>.webp
#   Saç ve sakal her saç rengi için ayrı: <kategori>_<kimlik>_<renk>.webp (Thumbs.RENKLI; saç rengi kartları da bunları
#   kullanır). Bunlar kayıplı (kalite 0.92) yazılır: ~500 dosya, pakette yine kayıplı içe aktarılıyor.
# Kullanım (görüntü gerekir, --headless değil):
#   Godot --path . --resolution 640x360 --script res://tools/kucuk_resim_pisir.gd -- [yalniz_eksik=1] [kat=sapka]
# Sonra: Godot --headless --path . --import  (yeni .webp dosyaları içe aktarılır; .import ayarı: kayıplı 0.8)
# Yeni eşya eklenince bu araç yeniden çalıştırılmalı (yoksa telefon eksik resmi kendisi çeker, user://thumbs/).
extends SceneTree

const Thumbs := preload("res://scripts/thumbs.gd")
const Catalog := preload("res://scripts/catalog.gd")
const CATS := ["sac", "sakal", "kiyafet", "aksesuar", "sapka", "hareket"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var only_missing: bool = args.get("yalniz_eksik", "0") == "1"
	var only_cat := str(args.get("kat", ""))
	var th: Node = Thumbs.new()
	root.add_child(th)
	var jobs: Array = []  # [görünüş, kategori, kimlik, yol]
	for v in ["erkek", "kadin"]:
		var look := Thumbs.temel_gorunus(v)
		for cat in CATS:
			if only_cat != "" and cat != only_cat:
				continue
			for it in Catalog.ITEMS[cat]:
				if cat in Thumbs.RENKLI:
					for c in Catalog.HAIR_COLORS.size():
						var lc := look.duplicate()
						lc.sac_renk = c
						jobs.append([lc, cat, str(it[0]), Thumbs.paket_yolu(lc, cat, str(it[0]))])
				else:
					jobs.append([look, cat, str(it[0]), Thumbs.paket_yolu(look, cat, str(it[0]))])
	if only_cat == "" or only_cat == "govde":
		for it in Catalog.ITEMS.govde:
			var look := Thumbs.temel_gorunus("kadin" if str(it[0]).begins_with("kadin") else "erkek")
			look.govde = str(it[0])
			jobs.append([look, "govde", str(it[0]), Thumbs.paket_yolu(look, "govde", str(it[0]))])
	var n := 0
	for j in jobs:
		var path: String = j[3]
		var abs_path := ProjectSettings.globalize_path(path)
		if only_missing and FileAccess.file_exists(abs_path):
			continue
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		var tex: Texture2D = await th._render(j[0], j[1], j[2])
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var err := img.save_webp(abs_path, true, 0.92) if j[1] in Thumbs.RENKLI else img.save_webp(abs_path, false)
		n += 1
		if err != OK:
			print("[pisir] HATA %s -> %d" % [path, err])
	print("[pisir] %d resim yazildi (%d is)" % [n, jobs.size()])
	quit()
