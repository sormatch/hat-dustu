# Açılış animasyonunu (tools/acilis_canli.gd) önceden çizilmiş kare dizisine PİŞİRİR.
# Çıktılar: assets/ui/uretim/acilis_kareler.res (kayıplı WebP kareleri, tek dosya), assets/ui/uretim/acilis_ses.ogg
# (zil + vuruş sesleri zamanlı tek dosya), build/acilis/acilis_onizleme.gif (yalnız önizleme, pakete girmez).
# Kullanım (pencereli, sabit kare hızıyla):
#   Godot --path . --fixed-fps 30 --resolution 1280x720 --script res://tools/acilis_gif_pisir.gd -- kalite=0.82
# Sonra: Godot --headless --path . --import  (acilis_ses.ogg içe aktarılır). .res için içe aktarma gerekmez.
extends SceneTree

const Canli := preload("res://tools/acilis_canli.gd")
const FPS := 30
const SURE := 2.3  # sn (kıvılcımlar 2,25'te biter)
const TUVAL := Vector2i(2400, 1080)  # tasarım tuvali (acilis.gd ile aynı)
const CIKTI := Vector2i(1440, 648)
const KENAR := 24  # çıktı px: kenarlar zemin rengine solar (başka ekran oranlarında dikiş görünmesin)
const FFMPEG := "C:/ffmpeg/bin/ffmpeg.exe"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var kalite := float(args.get("kalite", "0.82"))
	var gecici := ProjectSettings.globalize_path("res://build/acilis_gif")
	var kare_klasor := gecici.path_join("kare")
	DirAccess.make_dir_recursive_absolute(kare_klasor)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/acilis"))
	seed(7)
	var sv := SubViewport.new()
	sv.size = TUVAL
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var canli: CanvasLayer = Canli.new()
	sv.add_child(canli)
	canli._bar_kutu.visible = false  # çubuk ve yazı canlı çizilir, karelere pişmez
	# kenar solması: zemin renginde, kenarda opak, içeride saydam
	var ov := Image.create(CIKTI.x, CIKTI.y, false, Image.FORMAT_RGBA8)
	for y in CIKTI.y:
		for x in CIKTI.x:
			var d := float(mini(mini(x, CIKTI.x - 1 - x), mini(y, CIKTI.y - 1 - y)))
			var a := clampf(1.0 - d / float(KENAR), 0.0, 1.0)
			ov.set_pixel(x, y, Color(Canli.ZEMIN, a * a))
	for i in 3:
		await process_frame
	var n := int(round(SURE * FPS))
	var kareler: Array = []
	var toplam := 0
	for k in n:
		if k > 0:
			canli.adim(1.0 / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(CIKTI.x, CIKTI.y, Image.INTERPOLATE_LANCZOS)
		img.blend_rect(ov, Rect2i(0, 0, CIKTI.x, CIKTI.y), Vector2i.ZERO)
		img.convert(Image.FORMAT_RGB8)
		var buf := img.save_webp_to_buffer(true, kalite)
		kareler.append(buf)
		toplam += buf.size()
		var dec := Image.new()
		dec.load_webp_from_buffer(buf)
		dec.save_png(kare_klasor.path_join("k_%03d.png" % k))
	print("[pisir] %d kare, WebP toplam %.2f MB (kare ort. %.1f KB)" % [n, toplam / 1048576.0, toplam / 1024.0 / n])
	var r := Resource.new()
	r.set_meta("kareler", kareler)
	r.set_meta("fps", FPS)
	r.set_meta("boyut", CIKTI)
	print("[pisir] kare paketi: ", ResourceSaver.save(r, "res://assets/ui/uretim/acilis_kareler.res", ResourceSaver.FLAG_COMPRESS))
	_ses(canli, gecici)
	# önizleme GIF'i (yalnız gösterim için)
	var gif := ProjectSettings.globalize_path("res://build/acilis/acilis_onizleme.gif")
	var cikis := []
	OS.execute(FFMPEG, ["-y", "-v", "error", "-framerate", str(FPS), "-i", kare_klasor.path_join("k_%03d.png"), "-vf",
			"fps=20,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=5",
			"-loop", "0", gif], cikis, true)
	print("[pisir] gif: ", gif, " ", FileAccess.get_file_as_bytes(gif).size() / 1024, " KB ", cikis)
	quit()


func _ses(canli: Node, gecici: String) -> void:
	var zil: AudioStreamWAV = Canli._zil()
	zil.save_to_wav(gecici.path_join("zil.wav"))
	var girdi: Array = []
	var filtre := ""
	var etiket := ""
	var i := 0
	for o in canli.ses_olaylari:
		var yol := gecici.path_join("zil.wav") if str(o[1]) == "" else ProjectSettings.globalize_path(str(o[1]))
		girdi.append_array(["-i", yol])
		var ms := int(float(o[0]) * 1000.0)
		filtre += "[%d:a]aformat=channel_layouts=stereo,aresample=44100,asetrate=%d,aresample=44100,volume=%fdB,adelay=%d|%d[s%d];" % [i, int(44100.0 * float(o[3])), float(o[2]), ms, ms, i]
		etiket += "[s%d]" % i
		i += 1
	filtre += "%samix=inputs=%d:normalize=0,atrim=0:%f[o]" % [etiket, i, SURE]
	var arg: Array = ["-y", "-v", "error"]
	arg.append_array(girdi)
	arg.append_array(["-filter_complex", filtre, "-map", "[o]", "-c:a", "libvorbis", "-q:a", "4", ProjectSettings.globalize_path("res://assets/ui/uretim/acilis_ses.ogg")])
	var cikis := []
	print("[pisir] ses: ", i, " olay, ffmpeg=", OS.execute(FFMPEG, arg, cikis, true), " ", cikis)
