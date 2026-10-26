# Çalışırken GDScript ile piksel piksel üretilen dokuları PAKETE pişirir (telefonda saniyelerce donma yapıyorlardı):
#   saç teli (hair.gd strand_texture, masaüstünde ~0,5 sn), dövme mürekkepleri (model_body.gd ink_texture, her biri ~40 ms),
#   yanık izi (props.gd scorch_texture). Çıktı: assets/pisir/*.png (içe aktarma: VRAM sıkıştırmalı + mipmap).
# Kullanım: Godot --path . --headless --script res://tools/doku_pisir.gd  sonra  Godot --headless --path . --import
extends SceneTree

const OUT := "res://assets/pisir/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var Hair: GDScript = load("res://scripts/hair.gd")
	var Body: GDScript = load("res://scripts/model_body.gd")
	var Props: GDScript = load("res://scripts/modlar/props.gd")
	_save(Hair.strand_uret(), "sac_tel")
	for id in Body.TATTOO_PLACE.keys():
		var img: Image = Body.ink_uret(str(id))
		if img:
			_save(img, "murekkep_" + str(id))
	_save(Props.scorch_uret(), "yanik")
	quit()


func _save(img: Image, name: String) -> void:
	img.clear_mipmaps()
	var err := img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("[pisir] %s %dx%d -> %d" % [name, img.get_width(), img.get_height(), err])
