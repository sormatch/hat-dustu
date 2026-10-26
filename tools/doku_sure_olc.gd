# Çalışırken üretilen dokuların süresi (ana iş parçacığını ne kadar donduruyorlar?).
# Kullanım: Godot --path . --headless --script res://tools/doku_sure_olc.gd
extends SceneTree


func _init() -> void:
	var Hair: GDScript = load("res://scripts/hair.gd")
	var Body: GDScript = load("res://scripts/model_body.gd")
	var Props: GDScript = load("res://scripts/modlar/props.gd")
	_t("sac tel dokusu", func() -> void: Hair.strand_texture())
	_t("sac tutam dokusu", func() -> void: Hair.lock_texture())
	for id in Body.TATTOO_PLACE.keys():
		_t("dovme " + str(id), func() -> void: Body.ink_texture(str(id)))
	_t("yanik izi", func() -> void: Props.scorch_texture())
	quit()


func _t(n: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	f.call()
	print("[doku] %-24s %7.1f ms" % [n, (Time.get_ticks_usec() - t0) / 1000.0])
