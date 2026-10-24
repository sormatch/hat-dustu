extends SceneTree
func _init() -> void:
	var inst: Node = load("res://assets/karakter/anim/durma.fbx").instantiate()
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var a: Animation = ap.get_animation(ap.get_animation_list()[0])
	print("anim root=", ap.root_node, " track0=", a.track_get_path(0), " n=", a.get_track_count())
	for n in ["mahkum_b", "james", "kate", "remy"]:
		var m: Node = load("res://assets/karakterler/%s.fbx" % n).instantiate()
		var p: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
		var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
		print(n, " aproot=", p.root_node, " skelpath=", p.get_node(p.root_node).get_path_to(sk), " bone0=", sk.get_bone_name(0), " b1=", sk.get_bone_name(1), " scale=", sk.global_transform.basis.get_scale() if sk.is_inside_tree() else sk.transform.basis.get_scale())
	quit()
