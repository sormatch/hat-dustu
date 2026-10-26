extends SceneTree
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var b: Node3D = load("res://scripts/model_body.gd").new()
	b.look = {"govde": "kadin_iri", "aksesuar": "anahtar", "sac": "kisa", "kiyafet": "turuncu", "ten": 1, "sac_renk": 0, "goz": 0, "kas": "duz", "sakal": "yok", "sapka": "yok", "dovme": "yok"}
	root.add_child(b)
	for i in 4:
		await process_frame
	for ba in b.find_children("*", "BoneAttachment3D", true, false):
		print(ba.bone_name, " ", (ba as Node3D).global_position)
		for mi in ba.find_children("*", "MeshInstance3D", true, false):
			print("   ", mi.name, " merkez=", (mi as Node3D).global_transform * (mi as MeshInstance3D).get_aabb().get_center(), " aabb=", (mi as MeshInstance3D).get_aabb().size)
	quit()
