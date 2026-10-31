# Otomatik kalite denetleyicisi sınaması (benzetilmiş yavaş kareler). Kullanım:
#   Godot --path . --resolution 1280x720 --script res://tools/isi_test.gd
extends SceneTree

const Dunya := preload("res://scripts/dunya.gd")
const IsiScript := preload("res://scripts/isi.gd")


func _init() -> void:
	_run.call_deferred()


func _isi_bul(main: Node) -> Node:
	for c in main.get_children():
		if c.get_script() == IsiScript:
			return c
	return null


func _golgeli(main: Node) -> int:
	var n := 0
	for l in main.find_children("*", "Light3D", true, false):
		if (l as Light3D).shadow_enabled and (l as Light3D).is_visible_in_tree():
			n += 1
	return n


func _run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if not main.hazir_mi:
		await main.hazir
	main._start_solo()
	main.solo_ring_wait = 9999.0
	main.profile.settings.kalite = 1
	main.profile.settings.kalite_oto = true
	main.apply_settings()
	for i in 10:
		await process_frame
	var isi := _isi_bul(main)
	var vp := main.get_viewport()
	print("[test] baslangic: oto=%s olcek=%.2f golgeli_isik=%d kademe=%d" % [str(isi._oto_acik()), vp.scaling_3d_scale, _golgeli(main), isi.kademe])
	Engine.max_fps = 60
	isi._bekle = 0.0
	# 1) hedefi tutan kareler (60 fps): kademe değişmemeli
	for k in 400:
		isi.ornekle(1.0 / 60.0)
	print("[test] 60 fps tutarken 6,7 sn: kademe=%d (0 beklenir)" % isi.kademe)
	# 2) 30 fps'e düşen kareler: her 2 pencerede (10 sn) bir kademe
	for adim in 5:
		isi._bekle = 0.0
		for k in int(IsiScript.PENCERE * 30.0 * 2.0) + 2:
			isi.ornekle(1.0 / 30.0)
		for k in 120:
			await process_frame  # ölçek yumuşatma işlesin
		print("[test] yavas kareler adim %d: kademe=%d carpan=%.2f olcek=%.2f golge_kapali=%s golgeli_isik=%d" % [adim + 1, isi.kademe, Dunya.oto_carpan, vp.scaling_3d_scale, str(Dunya.golge_kapali), _golgeli(main)])
	# 3) ayar değişince sıfırlanır; Ultra elle seçilince otomatik kapalı
	main.profile.settings.kalite_oto = false
	main.profile.settings.kalite = 2
	await create_timer(0.8).timeout
	print("[test] Ultra elle: oto=%s kademe=%d carpan=%.2f olcek=%.2f golge_kapali=%s golgeli_isik=%d" % [str(isi._oto_acik()), isi.kademe, Dunya.oto_carpan, vp.scaling_3d_scale, str(Dunya.golge_kapali), _golgeli(main)])
	# 4) ölçek bir karede zıplamaz: adım 0,05
	main.profile.settings.kalite = 1
	main.profile.settings.kalite_oto = true
	await create_timer(0.8).timeout
	isi._bekle = 0.0
	var onceki := vp.scaling_3d_scale
	isi.asagi()
	var en_buyuk := 0.0
	var prev := vp.scaling_3d_scale
	for k in 90:
		await process_frame
		en_buyuk = maxf(en_buyuk, absf(vp.scaling_3d_scale - prev))
		prev = vp.scaling_3d_scale
	print("[test] ölçek %.2f -> %.2f, tek adımda en büyük değişim %.3f" % [onceki, vp.scaling_3d_scale, en_buyuk])
	# 5) sinir_sec
	for y in [60.0, 90.0, 120.0, 144.0, 75.0]:
		print("[test] yenileme %.0f Hz: aktif sınır %d, sakin sınır %d" % [y, IsiScript.sinir_sec(60.0, y), IsiScript.sinir_sec(30.0, y)])
	quit()
