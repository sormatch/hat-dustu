# MakeHuman saç dokularını (assets/sac/*.webp, 2048 kayıpsız) oyunda kullanılan gri tonlu hale bir kez çevirir:
# assets/sac/gri/<ad>.png (1024, VRAM sıkıştırmalı + mipmap olarak içe aktarılır). hair.gd önce bunları kullanır;
# eskiden her saç ilk kullanıldığında telefonda 4 milyon pikselik döngüyle çevriliyor (saniyeler süren takılma)
# ve sıkıştırmasız 2048 doku olarak ~21 MB video belleği tutuyordu (şimdi ~1,4 MB).
# Parlaklık her dokuda aynı ortalamaya çekilir (hair.gd gri_veri, GRI_HEDEF): aynı saç rengi her stilde aynı ton.
# Kullanım: Godot --headless --path . --script res://tools/sac_gri.gd
extends SceneTree

const Hair := preload("res://scripts/hair.gd")
const BOY := 1024


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/sac/gri"))
	for file in Hair.REAL_STYLES.values():
		var src := ProjectSettings.globalize_path("res://assets/sac/%s.webp" % file)
		var img := Image.load_from_file(src)
		if img == null:
			push_error("okunamadı: " + src)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var data := Hair.gri_veri(img.get_data())
		img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		if w > BOY:
			img.resize(BOY, BOY * h / w, Image.INTERPOLATE_LANCZOS)
		var out := ProjectSettings.globalize_path("res://assets/sac/gri/%s.png" % file)
		img.save_png(out)
		print("[sac_gri] ", file, " -> ", out)
	quit()
