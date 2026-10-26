# Bir kerelik araç: yeniden hedefleme için iki kemik haritası (BoneMap) üretir ve modellerdeki
# Skeleton3D düğüm yollarını yazar (.import dosyalarındaki "PATH:..." anahtarı için).
#  - mixamo_harita.tres: Mixamo iskeletleri (mahkum, Mixamo animasyonları) -> aynı adlar
#  - ue_harita.tres: Quaternius Universal (Unreal adları: pelvis, spine_01, upperarm_l...) -> mixamorig_*
# Çalıştırma: Godot --headless --path . --script res://tools/kemik_haritasi.gd
extends SceneTree

const PROFILE := "res://assets/karakter/mixamo_profil.tres"

const UE := {
	"Root": "root", "mixamorig_Hips": "pelvis", "mixamorig_Spine": "spine_01", "mixamorig_Spine1": "spine_02",
	"mixamorig_Spine2": "spine_03", "mixamorig_Neck": "neck_01", "mixamorig_Head": "Head",
}


func _ue_name(n: String) -> String:
	if UE.has(n):
		return UE[n]
	var side := ""
	var rest := ""
	if n.begins_with("mixamorig_Left"):
		side = "l"
		rest = n.substr(14)
	elif n.begins_with("mixamorig_Right"):
		side = "r"
		rest = n.substr(15)
	else:
		return ""
	var simple := {"Shoulder": "clavicle", "Arm": "upperarm", "ForeArm": "lowerarm", "Hand": "hand",
		"UpLeg": "thigh", "Leg": "calf", "Foot": "foot", "ToeBase": "ball"}
	if simple.has(rest):
		return "%s_%s" % [simple[rest], side]
	for f in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		for i in 3:
			if rest == "Hand%s%d" % [f, i + 1]:
				return "%s_%02d_%s" % [f.to_lower(), i + 1, side]
	return ""


func _init() -> void:
	var prof: SkeletonProfile = load(PROFILE)
	var mix := BoneMap.new()
	mix.profile = prof
	var ue := BoneMap.new()
	ue.profile = prof
	for i in prof.bone_size:
		var n := prof.get_bone_name(i)
		if n.begins_with("mixamorig_") and not n.ends_with("Eye") and not n.ends_with("Jaw"):
			mix.set_skeleton_bone_name(n, n)
		var u := _ue_name(n)
		if u != "":
			ue.set_skeleton_bone_name(n, u)
		print(n, "  mixamo=", mix.get_skeleton_bone_name(n), "  ue=", u)
	print(ResourceSaver.save(mix, "res://assets/karakter/mixamo_harita.tres"))
	print(ResourceSaver.save(ue, "res://assets/karakter/ue_harita.tres"))
	for a in OS.get_cmdline_user_args():
		var sc: Node = load(a).instantiate()
		for s in sc.find_children("*", "Skeleton3D", true, false):
			print(a, " -> PATH:", sc.get_path_to(s), "  kemik=", (s as Skeleton3D).get_bone_count())
		sc.free()
	quit()
