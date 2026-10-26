# Bir kerelik araç: Quaternius Universal Animation Library (CC0) dosyalarından seçilen animasyonları
# ayrı .res dosyalarına çıkarır (assets/karakter/anim_ual/). Kaynak .glb dosyaları projede tutulmaz
# (büyük); yeniden üretmek için D:/HatDustu_indir/ual1|ual2 içindeki glb'leri assets/karakter/ual_kaynak/
# klasörüne kopyalayıp içe aktar (kemik haritası: ue_harita.tres, düğüm yolu Armature/Skeleton3D), sonra bu
# aracı çalıştır. Var olan .res dosyalarına dokunmaz (yeni eklenenleri çıkarır); hepsi=1 hepsini yeniden yazar.
# Çalıştırma: Godot --headless --path . --script res://tools/ual_cikar.gd [-- hepsi=1]
extends SceneTree

const SRC := ["res://assets/karakter/ual_kaynak/ual1.glb", "res://assets/karakter/ual_kaynak/ual2.glb"]
const OUT := "res://assets/karakter/anim_ual/"
const WANT := [
	"Dance", "Idle_Talking", "Crouch_Idle", "Crouch_Fwd", "Death01", "Punch_Cross", "Spell_Simple_Shoot", "Roll",
	"Yes", "Idle_No", "Idle_FoldArms", "Idle_TalkingPhone", "Consume", "Zombie_Idle", "Idle_Rail_Call", "OverhandThrow",
	# 2. parti (yeni hareketler)
	"Melee_Hook", "Punch_Jab", "TreeChopping", "Farm_Watering", "Zombie_Scratch", "Fixing_Kneeling",
	"Push", "Chest_Open", "NinjaJump_Start", "LayToIdle",
]


func _init() -> void:
	var all := "hepsi=1" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for path in SRC:
		if not ResourceLoader.exists(path):
			continue
		var sc: Node = load(path).instantiate()
		var ap: AnimationPlayer = sc.find_children("*", "AnimationPlayer", true, false)[0]
		for n in ap.get_animation_list():
			if not (n in WANT):
				continue
			if not all and FileAccess.file_exists(OUT + n + ".res"):
				continue
			var a: Animation = ap.get_animation(n).duplicate(true)
			a.resource_name = n
			var err := ResourceSaver.save(a, OUT + n + ".res", ResourceSaver.FLAG_COMPRESS)
			print(n, " -> ", err, " loop=", a.loop_mode, " len=", a.length, " izler=", a.get_track_count())
		sc.free()
	quit()
