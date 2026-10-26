extends SceneTree
func _init() -> void:
	for id in ["wooden_bookshelf_worn", "boombox", "potted_plant_04", "wall_clock"]:
		var sc: Node3D = load("res://assets/models/%s/%s.gltf" % [id, id]).instantiate()
		var tris := 0
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			for s in m.get_surface_count():
				tris += m.surface_get_array_index_len(s) / 3
			print(id, " ", mi.name, " surf=", m.get_surface_count(), " aabb=", (mi as MeshInstance3D).get_aabb(), " mat=", m.surface_get_material(0).resource_name if m.surface_get_material(0) else "")
		print(id, " ucgen=", tris)
		sc.free()
	quit()
