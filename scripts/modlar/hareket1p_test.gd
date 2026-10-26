# Ekran görüntüsü testi: birinci şahısta hareket (emote) (main.gd pose=hareket1p).
#   hareket=<kimlik>[,<kimlik>...]  govde=erkek|kadin|iri|...[,..]  yer=hucre|koridor|duvar|ayna[,..]
#   t=<sn> (hareket başladıktan sonra çekim)  ya da  an=0.3,0.6 (animasyon süresinin kesirleri; varsayılan 0.5)
#   egim=<derece> (bakış; varsayılan -6)  yon=<derece>  hud=1 (arayüzle)  uzak=1 (karşıda uzaktaki oyuncu gibi
#   bir gövde aynı hareketi yapar: diğerleri hareketi tam görüyor mu)  yuru=1 (çekimden sonra joystick: hareket biter)
# Tek bir çekimde dosya shot= olur; birden çokta shot= klasörüne <yer>_<govde>_<hareket>_<an>.png yazılır.
extends RefCounted

const ModelScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")

const LOOKS := {
	"erkek": {"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "sac_renk": 1, "sapka": "ters_kep", "aksesuar": "gunes", "kiyafet": "cizgili", "ten": 2},
	"kadin": {"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "sapka": "bere", "aksesuar": "kupe", "kiyafet": "turuncu", "ten": 1},
	"iri": {"govde": "iri", "sac": "kisa", "sakal": "sakal", "sac_renk": 2, "kiyafet": "atlet", "aksesuar": "saat", "ten": 3},
}


static func run(w: Node3D, args: Dictionary) -> void:
	var p: CharacterBody3D = w.player
	w.solo_ring_wait = 100.0
	w.hud.visible = args.get("hud", "0") == "1"
	var ids: PackedStringArray = str(args.get("hareket", "alkis")).split(",")
	var bodies: PackedStringArray = str(args.get("govde", "erkek")).split(",")
	var places: PackedStringArray = str(args.get("yer", "hucre")).split(",")
	var fracs: PackedStringArray = str(args.get("an", "0.5")).split(",")
	var single := ids.size() * bodies.size() * places.size() * fracs.size() == 1
	var dir := str(args.get("shot", "user://x.png")).get_base_dir()
	var c0: Node3D = w.cells[0]
	for gv in bodies:
		var look: Dictionary = LOOKS.get(gv, {"govde": gv})
		p.set_look(Catalog.sanitize(look.duplicate()))
		await w.get_tree().create_timer(0.6).timeout
		for yer in places:
			var yaw := 0.0
			match yer:
				"koridor":
					c0.set_door(true, true)
					p.global_position = Vector3(3.9, 0, c0.position.z + 3.0)
				"duvar":
					# yüzü sol duvara dönük, duvara yarım metre
					p.global_position = c0.to_global(Vector3(-1.1, 0, 0.6))
					yaw = c0.global_rotation.y + PI / 2
				"ayna":
					# aynanın karşısında (sol duvar): yansımada hareket görünmeli
					p.global_position = c0.to_global(Vector3(-0.6, 0, 1.05))
					yaw = c0.global_rotation.y + PI / 2
				_:
					p.global_position = c0.to_global(Vector3(0.0, 0, 0.6))
			p.rotation.y = yaw + deg_to_rad(float(args.get("yon", "0")))
			p.head.rotation.x = deg_to_rad(float(args.get("egim", "-6")))
			var other: Node3D = null
			if args.has("uzak"):
				other = ModelScript.new()
				w.add_child(other)
				other.set_look(Catalog.sanitize(look.duplicate()))
				other.global_position = p.global_position - p.global_transform.basis.z * 2.0
				other.rotation.y = p.rotation.y + PI
			await w.get_tree().create_timer(0.5).timeout
			for id in ids:
				p.stop_emote()
				await w.get_tree().create_timer(0.7).timeout
				w._do_emote(id)
				if other:
					other.play_emote(id)
				var length := _length(p.body, id)
				var t0 := Time.get_ticks_msec() / 1000.0
				for f in fracs:
					var at := float(args.t) if args.has("t") else length * float(f)
					while Time.get_ticks_msec() / 1000.0 - t0 < at:
						await w.get_tree().process_frame
					await RenderingServer.frame_post_draw
					_report(p, id, gv, yer, f)
					if not single:
						w.get_viewport().get_texture().get_image().save_png(dir.path_join("%s_%s_%s_%s.png" % [yer, gv, id, f]))
				if args.has("yuru"):
					p.move_input = Vector2(0, -1)
					await w.get_tree().create_timer(0.25).timeout
					print("[1p] yuru: emote=", p.emote_active, " govde_anim=", p.body.get("emote"))
					await RenderingServer.frame_post_draw
					if not single:
						w.get_viewport().get_texture().get_image().save_png(dir.path_join("%s_%s_%s_yuru.png" % [yer, gv, id]))
					p.move_input = Vector2.ZERO
			if other:
				other.queue_free()
	args["wait"] = "0"


# Hareketin süresi: döngülüler EMOTE_LEN kadar, diğerleri animasyon boyu.
static func _length(body: Node, id: String) -> float:
	var lens: Dictionary = ModelScript.EMOTE_LEN
	if lens.has(id):
		return float(lens[id])
	var ap = body.get("_player")
	if ap is AnimationPlayer and (ap as AnimationPlayer).has_animation("hd/" + id):
		return (ap as AnimationPlayer).get_animation("hd/" + id).length
	return 2.0


static func _report(p: CharacterBody3D, id: String, gv: String, yer: String, f: String) -> void:
	var sk = p.body.get("_skel")
	var near := INF
	var head := Vector3.ZERO
	if sk is Skeleton3D:
		var s := sk as Skeleton3D
		var inv: Transform3D = p.camera.global_transform.affine_inverse() * s.global_transform
		for side in ["Left", "Right"]:
			for bn in ["ForeArm", "Hand", "HandMiddle1"]:
				var b := s.find_bone("mixamorig_" + side + bn)
				if b >= 0:
					var q: Vector3 = inv * s.get_bone_global_pose(b).origin
					if q.z < 0.04:
						near = minf(near, q.length())
		var hb := s.find_bone("mixamorig_Head")
		if hb >= 0:
			head = inv * s.get_bone_global_pose(hb).origin
		var zs := ""
		for bn in p.EMOTE_CLEAR:
			var b2 := s.find_bone(bn)
			if b2 >= 0:
				zs += " %s=%.2f" % [bn.trim_prefix("mixamorig_"), (inv * s.get_bone_global_pose(b2).origin).z]
		print("[1p]   z:", zs, " geri=%.2f" % float(p.get("_em_back")))
	print("[1p] %s %s %s an=%s emote=%s gizli=%d kamera_y=%.3f donus=(%.1f,%.1f) en_yakin_el=%.2f bas=(%.2f,%.2f,%.2f)" % [
		yer, gv, id, f, str(p.emote_active), int(p.get("_em_hide")), p.camera.position.y,
		rad_to_deg(p.camera.rotation.x), rad_to_deg(p.camera.rotation.y), near, head.x, head.y, head.z])
