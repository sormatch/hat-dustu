# Bir kerelik araç: pembe soyulmuş boya dokusunu hapishane yeşiline çevirir.
# Çalıştırma: Godot --headless --path . --script res://tools/recolor.gd
extends SceneTree

func _init() -> void:
	var img := Image.load_from_file("res://assets/textures/peeling_painted_wall/diff.jpg")
	img.convert(Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.s > 0.12:
				c.h = 0.3
				c.s = c.s * 0.75
				c.v = c.v * 0.62
			img.set_pixel(x, y, c)
	img.save_jpg("res://assets/textures/peeling_painted_wall/diff_green.jpg", 0.92)
	print("bitti")
	quit()
