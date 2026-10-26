# Mağaza önizleme davranışı: satın alınmamış eşyaya dokun -> başka sekme -> karakter kayıtlı görünüşe döner.
# Kullanım: Godot --path . --resolution 1280x720 --script res://tools/onizleme_test.gd -- server=ws://127.0.0.1:8794 profil=onizlemetest klasor=build/mobil/onizleme
extends SceneTree

var dir := ""
var hata := 0


func _init() -> void:
	_run.call_deferred()


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(dir.path_join(n + ".png"))


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	dir = str(args.get("klasor", "build/mobil/onizleme"))
	DirAccess.make_dir_recursive_absolute(dir)
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 60:
		await process_frame
	var saved: Dictionary = main.profile.look.duplicate()
	var ch: CanvasLayer = main.open_character()
	for i in 30:
		await process_frame
	ch._select_cat("sapka")
	for i in 20:
		await process_frame
	# sahip olunmayan bir şapka
	var unowned := ""
	for it in ch.Catalog.ITEMS.sapka:
		if not main.profile.owns("sapka", it[0]):
			unowned = it[0]
	print("[onizleme] kayitli sapka=%s, denenen=%s" % [saved.sapka, unowned])
	ch._pick(unowned)
	for i in 30:
		await process_frame
	await _shot("1_sapka_onizleme")
	_bak(ch._look.sapka == unowned, "dokununca giyildi")
	# başka sekme: önizleme geri alınmalı
	ch._select_cat("kiyafet")
	for i in 30:
		await process_frame
	await _shot("2_baska_sekme")
	_bak(ch._look.sapka == saved.sapka, "sekme degisince eski haline dondu")
	_bak(str(ch._body.look.sapka) == str(saved.sapka), "karakter modeli eski sapkada")
	# başka karta dokun: önceki önizleme gider
	ch._select_cat("sapka")
	for i in 10:
		await process_frame
	ch._pick(unowned)
	ch._select_cat("aksesuar")
	var acc := ""
	for it in ch.Catalog.ITEMS.aksesuar:
		if not main.profile.owns("aksesuar", it[0]):
			acc = it[0]
	ch._pick(acc)
	for i in 30:
		await process_frame
	await _shot("3_baska_kart")
	_bak(ch._look.sapka == saved.sapka and ch._look.aksesuar == acc, "baska karta dokununca onceki onizleme cikti")
	# sahip olunmayan önizleme varken çıkış: "kaydedilmemiş değişiklik" sorulmamalı
	_bak(not ch._dirty(), "satin alinmamis onizlemede kaydet sorusu yok")
	# sahip olunan bir değişiklik: soru çıkmalı ve sekme değişince kalmalı
	var owned_hat := ""
	for it in ch.Catalog.ITEMS.kiyafet:
		if main.profile.owns("kiyafet", it[0]) and it[0] != saved.kiyafet:
			owned_hat = it[0]
	if owned_hat != "":
		ch._select_cat("kiyafet")
		ch._pick(owned_hat)
		ch._select_cat("sac")
		for i in 20:
			await process_frame
		await _shot("4_sahip_olunan_kalir")
		_bak(ch._look.kiyafet == owned_hat, "sahip olunan esya sekme degisince kaldi")
		_bak(ch._dirty(), "sahip olunan degisiklikte kaydet sorusu var")
	print("[onizleme] %s" % ("TAMAM" if hata == 0 else "%d HATA" % hata))
	quit()


func _bak(ok: bool, n: String) -> void:
	print("[onizleme] %s: %s" % ["ok" if ok else "HATA", n])
	if not ok:
		hata += 1
