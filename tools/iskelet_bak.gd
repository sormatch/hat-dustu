# Bir kerelik araç: içe aktarılmış sahnelerin iskeletini ve animasyon izlerini yazar (yeniden hedefleme kontrolü).
# Çalıştırma: Godot --headless --path . --script res://tools/iskelet_bak.gd -- res://a.fbx res://b.gltf
extends SceneTree


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var sc: Node = load(a).instantiate()
		root.add_child(sc)
		for s in sc.find_children("*", "Skeleton3D", true, false):
			var sk := s as Skeleton3D
			print(a, " iskelet=", sc.get_path_to(sk), " kemik=", sk.get_bone_count())
			var names := []
			for i in sk.get_bone_count():
				names.append(sk.get_bone_name(i))
			print("  ", ", ".join(names))
			for b in ["mixamorig_Hips", "mixamorig_Head", "mixamorig_LeftArm", "mixamorig_LeftHand"]:
				var i := sk.find_bone(b)
				if i >= 0:
					print("  ", b, " global_rest=", sk.get_bone_global_rest(i).origin, " rot=", sk.get_bone_global_rest(i).basis.get_euler())
		for ap in sc.find_children("*", "AnimationPlayer", true, false):
			for n in (ap as AnimationPlayer).get_animation_list():
				var an := (ap as AnimationPlayer).get_animation(n)
				print("  anim ", n, " len=", an.length, " izler=", an.get_track_count(), " ilk=", an.track_get_path(0) if an.get_track_count() > 0 else "")
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			print("  mesh ", m.name, " aabb=", m.get_aabb(), " yüzey=", m.mesh.get_surface_count() if m.mesh else 0)
		sc.free()
	quit()
