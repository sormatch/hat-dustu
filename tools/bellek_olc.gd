# Bellek + takılma ölçümü (iPhone çökme / donma avı): gerçek kullanıcı akışı adım adım yürütülür, her adımdan
# sonra statik bellek, video belleği, doku belleği, nesne sayısı ve o adımdaki en uzun kare yazılır.
# Senaryo: açılış -> menü -> mağaza (bütün sekmeler + kaydırma) -> envanter -> kasa x3 -> menü -> maç -> menü (yeniden yükleme)
# Kullanım (görüntü gerekir, --headless değil):
#   Godot --path . --resolution 1280x720 --script res://tools/bellek_olc.gd -- server=ws://127.0.0.1:8794 profil=bellektest kalite=1 [kasa=3] [magaza_tur=1] [cikti=build/mobil/olcum/x.txt]
extends SceneTree

const Catalog := preload("res://scripts/catalog.gd")


class Kare extends Node:
	var last := 0
	var worst := 0.0
	var over := 0  # 33 ms'yi aşan kare
	var frames := 0
	var log_spikes := false
	var tag := ""

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -1000
		last = Time.get_ticks_usec()

	func _process(_d: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		frames += 1
		worst = maxf(worst, ms)
		if ms > 33.0:
			over += 1
			if log_spikes:
				print("[kare] %s: %.1f ms" % [tag, ms])

	func reset(t: String) -> void:
		worst = 0.0
		over = 0
		frames = 0
		tag = t
		last = Time.get_ticks_usec()


var args := {}
var main: Node
var kare: Kare
var rows: Array = []
var t_start := 0


func _init() -> void:
	t_start = Time.get_ticks_msec()
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	kare = Kare.new()
	root.add_child(kare)
	kare.log_spikes = args.get("ani", "0") == "1"
	await process_frame
	# 1) açılış: sahne kurulumu + ilk kareler (menü görünene kadar)
	kare.reset("acilis")
	var t0 := Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var t_ready := Time.get_ticks_msec() - t0
	if not main.hazir_mi:
		await main.hazir
	var t_kurulum := Time.get_ticks_msec() - t0
	main.profile.settings.kalite = int(args.get("kalite", "1"))
	main.apply_settings()
	# menü "hazır": açılış perdesi varsa kalkana kadar bekle
	var t_menu := -1
	for i in 1200:
		await process_frame
		if _menu_hazir():
			t_menu = Time.get_ticks_msec() - t0
			break
	await _wait_s(2.0)
	_row("acilis (ilk kare %d ms, kurulum %d ms, menu %d ms, motor->betik %d ms)" % [t_ready, t_kurulum, t_menu, t0])
	kare.reset("menu")
	await _wait_s(2.0)
	_row("menu")
	for tur in int(args.get("magaza_tur", "1")):
		await _magaza(tur)
	await _envanter()
	var kasa_n := int(args.get("kasa", "3"))
	if kasa_n > 0:
		await _kasa(kasa_n)
	kare.reset("menu2")
	await _wait_s(2.0)
	_row("menu (kasadan sonra)")
	if args.get("mac", "1") == "1":
		kare.reset("mac")
		main._start_solo()
		main.solo_ring_wait = 9999.0
		main.test_move = Vector2(0, 1)
		await _wait_s(3.0)
		main.test_move = Vector2.ZERO
		main.cells[0].set_door(true, true)
		main.player.global_position = Vector3(3.9, 0, main.cells[0].position.z + 3.0)
		await _wait_s(3.0)
		_row("mac (solo, hucre + koridor)")
		# menüye dönüş: sahne baştan yüklenir (main.gd reload_current_scene ile aynı)
		kare.reset("menu3")
		main.queue_free()
		await process_frame
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
		current_scene = main
		if not main.hazir_mi:
			await main.hazir
		main.profile.settings.kalite = int(args.get("kalite", "1"))
		main.apply_settings()
		for i in 1200:
			await process_frame
			if _menu_hazir():
				break
		await _wait_s(3.0)
		_row("menu (macdan donus)")
	_print()
	quit()


func _menu_hazir() -> bool:
	if not bool(main.get("hazir_mi")):
		return false
	for c in main.get_children():
		if c.get_script() == preload("res://scripts/acilis.gd"):
			return false
	return true


func _magaza(tur: int) -> void:
	kare.reset("magaza")
	var ch: CanvasLayer = main.open_character()
	await _wait_s(1.5)
	_row("magaza acildi (tur %d)" % (tur + 1))
	kare.reset("magaza_sekme")
	for c in ch.CATS:
		ch._select_cat(c)
		await _wait_s(0.6)
		# kaydırma: aşağı ve geri
		for k in 8:
			ch._scroll.scroll_vertical += 120
			await _wait_s(0.08)
		# bir karta dokun (önizleme)
		if c in ["sac", "sapka", "kiyafet", "aksesuar", "sakal"]:
			var it: Array = Catalog.ITEMS[c][mini(5, Catalog.ITEMS[c].size() - 1)]
			ch._pick(str(it[0]))
			await _wait_s(0.3)
		ch._scroll.scroll_vertical = 0
	_row("magaza tum sekmeler (tur %d)" % (tur + 1))
	kare.reset("magaza_bekle")
	# küçük resim sırası bitene kadar (en çok 40 sn)
	var tb: Node = ch._thumbs
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 40000 and tb and tb.mesgul():
		await process_frame
	_row("magaza resimler bitti (%.1f sn)" % ((Time.get_ticks_msec() - w0) / 1000.0))
	ch._close(false)
	await _wait_s(1.0)
	_row("magaza kapandi")


func _envanter() -> void:
	kare.reset("envanter")
	var inv: CanvasLayer = main.open_inventory()
	await _wait_s(1.0)
	for c in inv.TABS:
		inv._select_tab(c)
		await _wait_s(0.5)
	_row("envanter")
	inv._close()
	await _wait_s(1.0)
	_row("envanter kapandi")


func _kasa(n: int) -> void:
	kare.reset("kasa_sekme")
	var ch: CanvasLayer = main.open_character()
	await _wait_s(0.5)
	ch._select_cat("sandik")
	await _wait_s(1.0)
	_row("kasa sekmesi")
	var all := Catalog.shop_items()
	for i in n:
		kare.reset("kasa%d" % (i + 1))
		var won: Array = all[(i * 37) % all.size()]
		ch.spin(ch.CHESTS[i % 2], won)
		await _wait_s(13.0)
		# TAMAM: gösteri penceresi kapanır
		for c in ch.get_children():
			if c is Control and c != ch._kok:
				c.queue_free()
		ch._opening = false
		ch._sahne_ciz(true)
		await _wait_s(0.5)
		_row("kasa %d" % (i + 1))
	ch._close(false)
	await _wait_s(1.0)
	_row("kasalar kapandi")


func _wait_s(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await process_frame


func _row(name: String) -> void:
	var r := [name,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		kare.worst, kare.over, kare.frames]
	rows.append(r)
	print("[bellek] %-48s | bellek %6.1f MB | vram %6.1f MB | doku %6.1f MB | nesne %6d | dugum %5d | en uzun kare %6.1f ms | >33ms %3d / %d" % r)


func _print() -> void:
	var out := PackedStringArray()
	out.append("kalite=%s" % args.get("kalite", "1"))
	out.append("adim | bellek MB | vram MB | doku MB | nesne | dugum | en uzun kare ms | >33ms kare")
	for r in rows:
		out.append("%s | %.1f | %.1f | %.1f | %d | %d | %.1f | %d/%d" % r)
	var txt := "\n".join(out)
	print(txt)
	var path := str(args.get("cikti", ""))
	if path != "":
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(txt + "\n")
