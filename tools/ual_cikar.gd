# Bir kerelik araç: Quaternius Universal Animation Library (CC0) dosyalarından seçilen animasyonları
# ayrı .res dosyalarına çıkarır (assets/karakter/anim_ual/). Kaynak .glb dosyaları projede tutulmaz
# (büyük); yeniden üretmek için D:/HatDustu_indir/ual1|ual2 içindeki glb'leri assets/karakter/ual_kaynak/
# klasörüne kopyalayıp içe aktar (kemik haritası: ue_harita.tres), sonra bu aracı çalıştır.
# Çalıştırma: Godot --headless --path . --script res://tools/ual_cikar.gd
extends SceneTree

const SRC := ["res://assets/karakter/ual_kaynak/ual1.glb", "res://assets/karakter/ual_kaynak/ual2.glb"]
const OUT := "res://assets/karakter/anim_ual/"
const WANT := [
	"Dance", "Idle_Talking", "Crouch_Idle", "Crouch_Fwd", "Death01", "Punch_Cross", "Spell_Simple_Shoot", "Roll",
	"Yes", "Idle_No", "Idle_FoldArms", "Idle_TalkingPhone", "Consume", "Zombie_Idle", "Idle_Rail_Call", "OverhandThrow",
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for path in SRC:
		if not ResourceLoader.exists(path):
			continue
		var sc: Node = load(path).instantiate()
		var ap: AnimationPlayer = sc.find_children("*", "AnimationPlayer", true, false)[0]
		for n in ap.get_animation_list():
			if not (n in WANT):
				continue
			var a: Animation = ap.get_animation(n).duplicate(true)
			a.resource_name = n
			var err := ResourceSaver.save(a, OUT + n + ".res", ResourceSaver.FLAG_COMPRESS)
			print(n, " -> ", err, " loop=", a.loop_mode, " len=", a.length)
		sc.free()
	quit()
