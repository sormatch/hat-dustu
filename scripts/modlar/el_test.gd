# Ekran görüntüsü testi: gerçek karakter elleriyle tutma pozları (main.gd pose=el).
#   el=silah|sakak|hedef|ahize|c4|itme|bos   otur=1 (oturarak)   pitch=derece
#   dis=1  kendi gövdeni dışarıdan gösteren kamera (aci=derece: etrafında dönüş)
#   bot=1  karşına oturan bir karakter aynı pozu uzaktaki oyuncu gibi yapar (bot hedefi: sen)
extends RefCounted

const Props := preload("res://scripts/modlar/props.gd")
const AimMod := preload("res://scripts/modlar/aim_mod.gd")
const ModelScript := preload("res://scripts/model_body.gd")


static func run(w: Node3D, args: Dictionary) -> void:
	var p: CharacterBody3D = w.player
	var kind := str(args.get("el", "silah"))
	w.solo_ring_wait = 100.0
	p.global_position = w.cells[0].to_global(Vector3(0.0, 0, 0.6))
	p.rotation.y = 0.0
	if args.has("otur"):
		p.seated = true
		p.body.seated = true
		p.head.position.y = p.EYE_SEAT
	await w.get_tree().create_timer(0.3).timeout
	if args.has("bot"):
		var b: Node3D = ModelScript.new()
		w.add_child(b)
		b.global_position = p.global_position + Vector3(float(args.get("bx", "0")), 0, -1.3)
		b.rotation.y = PI + deg_to_rad(float(args.get("byaw", "0")))
		b.seated = args.has("otur")
		await w.get_tree().process_frame
		var sk: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
		var m: Node = AimMod.new()
		sk.add_child(m)
		var item := Node3D.new()
		w.add_child(item)
		if kind == "ahize":
			var h: Node3D = load("res://scripts/telefon.gd").handset(item)
			h.scale = Vector3.ONE * 1.15
			m.mode = "ahize"
			m.aim = 1.0
			m.hold(1, item, AimMod.item_offset("ahize", 1))
		elif kind == "c4":
			Props.c4(item)
			m.mode = "c4"
			m.aim_l = 1.0
			m.hold(0, item, AimMod.item_offset("c4", 0))
		else:
			var inner := Node3D.new()
			item.add_child(inner)
			Props.revolver(inner)
			m.mode = {"sakak": "sakak", "hedef": "hedef"}.get(kind, "silah")
			m.mode_target = p.camera.global_position
			m.aim = 1.0
			m.hold(1, item, AimMod.item_offset("silah", 1))
	else:
		match kind:
			"silah", "sakak", "hedef":
				var gun := Node3D.new()
				Props.revolver(gun)
				p.hold_item(1, gun, AimMod.item_offset("silah", 1))
				if kind == "hedef":
					var fwd := -p.global_transform.basis.z
					p.set_hand_pose(1, {"obj": "silah", "aim_at": p.camera.global_position + fwd * 2.0 + p.global_transform.basis.x * -0.6, "u": Vector3.UP, "e": Vector3(0.5, -1.0, 0.0), "c": [0.6, 0.45, 1.0, 1.0, 1.0], "r": 8.0})
				else:
					p.set_hand_pose(1, kind)
			"ahize", "telefon", "kablo", "kapat":
				# telefonun önünden ahizeyi al; kablo: telefondan uzaklaş (kablo gerilir); kapat: geri koy
				var c: Node3D = w.cells[0]
				p.global_position = c.to_global(Vector3(1.0, 0, -1.8))
				p.rotation.y = -PI / 2
				p.lift_handset(c)
				if kind == "telefon":
					await w.get_tree().create_timer(float(args.get("t", "0.3"))).timeout
				else:
					await w.get_tree().create_timer(1.2).timeout
				if kind == "kablo":
					var to: Vector3 = c.to_global(Vector3(float(args.get("kx", "-0.2")), 0, float(args.get("kz", "-1.0"))))
					p.global_position = to
					var dir: Vector3 = c.phone_world() - to
					p.rotation.y = atan2(-dir.x, -dir.z) + float(args.get("yaw", "0")) * PI / 180.0
					p.head.rotation.x = deg_to_rad(-15.0)
				elif kind == "kapat":
					p.hang_up_handset(args.has("kay"))
					await w.get_tree().create_timer(float(args.get("t", "0.2"))).timeout
			"c4":
				var bomb := Node3D.new()
				Props.c4(bomb)
				p.hold_item(0, bomb, AimMod.item_offset("c4", 0))
				p.set_hand_pose(0, "c4")
			"itme":
				p.set_hand_pose(1, "itme")
			"ses":
				await _ses_testi(w)
			"yumruk":
				p.set_hand_pose(1, {"p": Vector3(0.15, -0.15, -0.4), "f": Vector3(0, 0, -1), "u": Vector3(0, 1, 0), "c": [1.0, 1.0, 1.0, 1.0, 1.0]})
	if args.has("govdesiz"):
		p.body.visible = false
	if args.has("pitch"):
		p.head.rotation.x = deg_to_rad(float(args.pitch))
	if args.has("debug"):
		await w.get_tree().create_timer(1.0).timeout
		debug(w)
	if args.has("dis"):
		await w.get_tree().create_timer(float(args.get("bekle", "1.2"))).timeout
		var cam := Camera3D.new()
		w.add_child(cam)
		var a := deg_to_rad(float(args.get("aci", "35")))
		var c := p.global_position + Vector3(0, p.head.position.y - 0.25, 0)
		var yuk := float(args.get("yuk", "0.25"))
		if args.has("telbak"):
			c = w.cells[0].phone_world() + Vector3(0, -0.15, 0)
		if args.has("yakin"):
			c = p.hand_frame(0 if kind == "c4" else 1).origin
			var l := OmniLight3D.new()
			w.add_child(l)
			l.global_position = c + Vector3(0.3, 0.5, -0.4)
			l.light_energy = 1.5
		cam.global_position = c + Vector3(sin(a), yuk, -cos(a)) * float(args.get("uzak", "1.1"))
		cam.look_at(c, Vector3.UP)
		cam.fov = 50.0
		if args.has("zoom"):
			cam.global_position = p.camera.global_position
			cam.look_at(p.hand_frame(0 if kind == "c4" else 1).origin, Vector3.UP)
			cam.fov = 28.0
		cam.current = true
		w.hud.visible = false
		var sk: Skeleton3D = p.body.get("_skel")
		print("[el] govde yuzu=", sk.global_transform.basis.z, " kamera ileri=", -p.camera.global_transform.basis.z, " dis kamera=", cam.global_position - p.global_position, " avuc=", p.hand_frame(1).origin - p.global_position)


static func debug(w: Node3D) -> void:
	var p: CharacterBody3D = w.player
	var skd: Skeleton3D = p.body.get("_skel")
	var hbi := skd.find_bone("mixamorig_Head")
	print("[el] kafa kemigi (oyuncuya gore)=", p.to_local(skd.global_transform * skd.get_bone_global_pose(hbi).origin), " kamera=", p.to_local(p.camera.global_position), " govde=", p.body.position)
	var m: Node = p.hand_mod()
	if not m:
		print("[el] mod yok")
		return
	for fn in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
		var b1 := skd.find_bone("mixamorig_RightHand" + fn + "1")
		var b2 := skd.find_bone("mixamorig_RightHand" + fn + "2")
		var b3 := skd.find_bone("mixamorig_RightHand" + fn + "3")
		var hb := skd.find_bone("mixamorig_RightHand")
		if b1 < 0 or b2 < 0 or b3 < 0:
			continue
		var ph := skd.get_bone_global_pose(hb).origin
		var p1 := skd.get_bone_global_pose(b1).origin
		var p2 := skd.get_bone_global_pose(b2).origin
		var p3 := skd.get_bone_global_pose(b3).origin
		print("[el] parmak ", fn, " boğum1=", rad_to_deg((p1 - ph).angle_to(p2 - p1)), " boğum2=", rad_to_deg((p2 - p1).angle_to(p3 - p2)))
	for ch in skd.get_children():
		print("[el] iskelet cocugu: ", ch.name, " ", ch.get_class(), " ", ch.get_script().resource_path if ch.get_script() else "")
	var inv: Transform3D = p.camera.global_transform.affine_inverse()
	for side in 2:
		var f: Transform3D = m.frame(side)
		print("[el] taraf ", side, " w=", m.weights[side], " hedef(cam)=", inv * (m.targets[side] as Vector3), " avuc(cam)=", inv * f.origin)
		print("[el]   ileri hedef=", inv.basis * (m.forwards[side] as Vector3), " gercek=", inv.basis * -f.basis.z)
		print("[el]   bas hedef=", inv.basis * (m.ups[side] as Vector3), " gercek=", inv.basis * f.basis.y)


# Mekânsal ses testi: sahte uzak oyuncular yakına, uzağa, koridora (kapı kapalı/açık) konur, kazançlar yazılır.
static func _ses_testi(w: Node3D) -> void:
	var p: CharacterBody3D = w.player
	var c0: Node3D = w.cells[0]
	p.global_position = c0.to_global(Vector3(0, 0, 0))
	p.rotation.y = 0.0
	var yerler := {
		201: ["yanında sağda 1 m", c0.to_global(Vector3(1.0, 0, 0))],
		202: ["aynı hücre solda 2.5 m", c0.to_global(Vector3(-1.5, 0, -2.0))],
		203: ["koridorda (kapı kapalı)", c0.to_global(Vector3(3.9, 0, 0.5))],
		204: ["komşu hücrede", w.cells[1].to_global(Vector3(0, 0, 0))],
		205: ["koridorda uzak 12 m", c0.to_global(Vector3(3.9, 0, 12.0))],
	}
	for id in yerler:
		var root := Node3D.new()
		w.add_child(root)
		root.global_position = yerler[id][1]
		var lab := Label3D.new()
		lab.position.y = 2.05
		root.add_child(lab)
		w.remotes[id] = {"root": root, "body": Node3D.new(), "label": lab, "target": root.position, "yaw": 0.0, "seated": false}
	await w.get_tree().process_frame
	for durum in ["kapı kapalı", "kapı açık"]:
		if durum == "kapı açık":
			c0.door_open = true
		w._update_voice_space(0.016)
		for id in yerler:
			var s: Dictionary = w.voice._space.get(id, {})
			print("[ses] %s | %s: kazanç=%.2f pan=%.2f boğukluk=%.2f" % [durum, yerler[id][0], s.get("g", -1.0), s.get("p", 0.0), s.get("m", 0.0)])
	w.phone_state = 3  # Phone.CALL
	w.phone_peer = 205
	w._update_voice_space(0.016)
	var s5: Dictionary = w.voice._space.get(205, {})
	print("[ses] telefonda 205 (12 m uzakta): kazanç=%.2f telefon=%s" % [s5.get("g", -1.0), str(s5.get("phone", false))])
	for id in yerler:
		w.remotes.erase(id)
	w.phone_state = 0  # Phone.IDLE
