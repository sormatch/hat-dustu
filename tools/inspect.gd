# Bir kerelik araç: 3D dosyanın içindeki parçaları, iskeleti ve animasyonları listeler.
# Çalıştırma: Godot --headless --path . --script res://tools/inspect.gd -- dosya=res://...
extends SceneTree

func _init() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("dosya="):
			path = a.substr(6)
	var scene: PackedScene = load(path)
	var root := scene.instantiate()
	_walk(root, 0)
	quit()

func _walk(n: Node, depth: int) -> void:
	if depth > 6:
		return
	var extra := ""
	if n is MeshInstance3D:
		var aabb: AABB = n.get_aabb()
		extra = " mesh boyut=%s yüzey=%d" % [aabb.size, n.mesh.get_surface_count() if n.mesh else 0]
	if n is Skeleton3D:
		extra = " kemik=%d" % n.get_bone_count()
	if n is AnimationPlayer:
		extra = " animasyonlar=%s" % [n.get_animation_list()]
	print("  ".repeat(depth), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_walk(c, depth + 1)
