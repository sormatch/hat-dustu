# Gövde tipinin duruşu: animasyon uygulandıktan sonra omurgaya hafif öne eğilme (kamburluk) ekler, boyun ve
# kafa geri döndürülür (bakış yine önde; boyun-göğüs açısı değişmez, yaka aralığı açılmaz). İskeletin ilk düzenleyicisi olarak eklenir: el IK'sı (aim_mod) ve
# diğer düzenleyiciler bunun üstüne çalışır. Bütün iskeletler aynı insansı profile yeniden hedeflendiğinden
# kemik eksenleri aynıdır (+x ekseni etrafında artı açı = öne eğilme, hareketler.gd ile aynı).
extends SkeletonModifier3D

var kambur := 1.0
# [kemik, derece]
const BEND := [["Spine", 5.0], ["Spine1", 7.0], ["Head", -11.0],
	["LeftShoulder", -2.0], ["RightShoulder", -2.0]]
var _ids := []


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or kambur <= 0.0:
		return
	if _ids.is_empty():
		for b in BEND:
			_ids.append(sk.find_bone("mixamorig_" + b[0]))
	for i in BEND.size():
		var bi: int = _ids[i]
		if bi < 0:
			continue
		var q := sk.get_bone_pose_rotation(bi)
		sk.set_bone_pose_rotation(bi, q * Quaternion(Vector3.RIGHT, deg_to_rad(BEND[i][1] * kambur)))
