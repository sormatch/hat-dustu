# Arayüz görsellerinin kırpılmış + ölçeklenmiş hâllerini PAKETE pişirir (scripts/ui.gd texture / _gri).
# Anahtar listesi: oyun "ui_kayit=1" ile çalıştırılınca user://ui_anahtar.txt dosyasına yazılır (pişmişi olmayanlar).
# Kullanım: Godot --path . --headless --script res://tools/ui_pisir.gd  [-- liste=<dosya>]  sonra  Godot --headless --path . --import
# Çıktı: assets/ui/hazir/<ad>@<boy>.png (opak arka planlar kayıplı, diğerleri kayıpsız içe aktarılır; tools/ui_pisir_import.sh değil,
# bu araç .import ayarını da yazar).
extends SceneTree


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var UI: GDScript = load("res://scripts/ui.gd")
	var liste := str(args.get("liste", "user://ui_anahtar.txt"))
	var f := FileAccess.open(liste, FileAccess.READ)
	if f == null:
		print("[uipisir] liste yok: ", liste)
		quit()
		return
	var keys := {}
	while not f.eof_reached():
		var k := f.get_line().strip_edges()
		if k != "":
			keys[k] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UI.HAZIR))
	var n := 0
	var bayt := 0
	for k in keys:
		var gri: bool = k.ends_with("#gri")
		var kk: String = k.trim_suffix("#gri")
		var at := kk.rfind("@")
		var name := kk.substr(0, at)
		var h := int(kk.substr(at + 1))
		var img: Image = UI.gri_isle(name, h) if gri else UI.isle(name, h)
		if img == null:
			print("[uipisir] yok: ", k)
			continue
		var p: String = ProjectSettings.globalize_path(UI.hazir_yolu(k))
		img.save_png(p)
		n += 1
		bayt += FileAccess.get_file_as_bytes(p).size()
	print("[uipisir] %d gorsel (%.1f MB png)" % [n, bayt / 1048576.0])
	quit()
