# Bir kerelik araç: büyük PNG dokuları küçültüp yazar (paket boyutu). Kullanım:
# Godot --headless --path . --script res://tools/doku_kucult.gd -- boyut=1024 <kaynak.png> <hedef.png> [<kaynak> <hedef> ...]
extends SceneTree


func _init() -> void:
	var size := 1024
	var files := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("boyut="):
			size = int(a.substr(6))
		else:
			files.append(a)
	for i in range(0, files.size() - 1, 2):
		var img := Image.load_from_file(files[i])
		if img == null:
			print("okunamadi ", files[i])
			continue
		if img.get_width() > size:
			img.resize(size, size * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
		print(files[i + 1], " ", img.get_size(), " -> ", img.save_png(files[i + 1]))
	quit()
