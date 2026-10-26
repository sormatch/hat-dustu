# Bir kerelik araç: Godot'nun insansı iskelet profilini (SkeletonProfileHumanoid) Mixamo kemik adlarıyla
# kopyalar (mixamorig_Hips, mixamorig_LeftArm...). Bütün karakter modelleri ve animasyonlar içe aktarılırken
# bu profile göre yeniden hedeflenir (retarget): kemik adları her modelde aynı "mixamorig_*" olur, böylece
# kol/el kodları (aim_mod.gd) ve animasyonlar her gövdede çalışır.
# Çalıştırma: Godot --headless --path . --script res://tools/profil_uret.gd
extends SceneTree

const OUT := "res://assets/karakter/mixamo_profil.tres"

const MAP := {
	"Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "UpperChest": "Spine2", "Neck": "Neck", "Head": "Head",
	"LeftEye": "LeftEye", "RightEye": "RightEye", "Jaw": "Jaw",
	"LeftShoulder": "LeftShoulder", "LeftUpperArm": "LeftArm", "LeftLowerArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightUpperArm": "RightArm", "RightLowerArm": "RightForeArm", "RightHand": "RightHand",
	"LeftUpperLeg": "LeftUpLeg", "LeftLowerLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightUpLeg", "RightLowerLeg": "RightLeg", "RightFoot": "RightFoot", "RightToes": "RightToeBase",
}
const FINGER := {"Thumb": ["Metacarpal", "Proximal", "Distal"], "Index": ["Proximal", "Intermediate", "Distal"],
	"Middle": ["Proximal", "Intermediate", "Distal"], "Ring": ["Proximal", "Intermediate", "Distal"],
	"Little": ["Proximal", "Intermediate", "Distal"]}


static func mixamo_name(n: String) -> String:
	if n == "Root" or n == "":
		return n
	if MAP.has(n):
		return "mixamorig_" + MAP[n]
	for side in ["Left", "Right"]:
		for f in FINGER:
			for i in 3:
				if n == side + f + FINGER[f][i]:
					var mf: String = "Pinky" if f == "Little" else f
					return "mixamorig_%sHand%s%d" % [side, mf, i + 1]
	push_error("eşlenmeyen kemik: " + n)
	return n


func _init() -> void:
	var src := SkeletonProfileHumanoid.new()
	var p := SkeletonProfile.new()
	p.group_size = src.group_size
	for g in src.group_size:
		p.set_group_name(g, src.get_group_name(g))
		p.set_texture(g, src.get_texture(g))
	p.bone_size = src.bone_size
	for i in src.bone_size:
		p.set_bone_name(i, mixamo_name(src.get_bone_name(i)))
		p.set_bone_parent(i, mixamo_name(src.get_bone_parent(i)))
		p.set_tail_direction(i, src.get_tail_direction(i))
		p.set_bone_tail(i, mixamo_name(src.get_bone_tail(i)))
		p.set_reference_pose(i, src.get_reference_pose(i))
		p.set_handle_offset(i, src.get_handle_offset(i))
		p.set_group(i, src.get_group(i))
		p.set_required(i, src.is_required(i))
	p.root_bone = mixamo_name(src.root_bone)
	p.scale_base_bone = mixamo_name(src.scale_base_bone)
	print(ResourceSaver.save(p, OUT), " ", p.bone_size, " kemik")
	for i in p.bone_size:
		print(src.get_bone_name(i), " -> ", p.get_bone_name(i))
	quit()
