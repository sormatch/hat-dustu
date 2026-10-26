# Sistem açılış ekranı görseli (project.godot boot_splash + iOS LaunchScreen): koyu düz zemin ortasında yuvarlak
# "HAT DÜŞTÜ" amblemi (assets/ui/uretim/kaynak/amblem.png; tools/amblem_uret.gd) ve arkasında yumuşak kırmızı ışıma.
# Kenarlar tam zemin rengi (UI.ZEMIN): "Keep" / "Scale to Fit" ile her en-boy oranında (16:9, 19.5:9, 20:9, 4:3)
# kesilmeden, uzamadan ortalanır; kalan pay aynı renkle dolar, dikiş görünmez.
# Motor açılınca scripts/acilis.gd aynı amblemi (katmanlarıyla) aynı yerde gösterip animasyona geçer.
# Kullanım: Godot --path . --headless --script res://tools/acilis_splash_uret.gd
extends SceneTree

const W := 1920
const H := 1080
const AMBLEM := 820  # amblem tuvalinin (1024'lük) splash'taki boyu (px); acilis.gd AMBLEM_ORAN ile aynı (820/1080)
const ISIK_R := 0.5  # ışıma yarıçapı / H (kenara değmez: Keep ile kalan pay dikişsiz); acilis.gd ile aynı
const ISIK_GUC := 0.42
const ISIK_US := 2.0


func _init() -> void:
	var zemin := Color("#0b0e0f")
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(zemin)
	# ışıma: merkezden kenara yumuşak, ISIK_R yarıçapta tamamen zemin
	var glow := Color(0.55, 0.06, 0.04)
	var c := Vector2(W / 2.0, H / 2.0)
	var r := H * ISIK_R
	for y in H:
		for x in range(int(c.x - r), int(c.x + r) + 1):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			if d >= 1.0:
				continue
			img.set_pixel(x, y, zemin.lerp(glow, pow(1.0 - d, ISIK_US) * ISIK_GUC))
	var amb := Image.load_from_file(ProjectSettings.globalize_path("res://assets/ui/uretim/kaynak/amblem.png"))
	amb.convert(Image.FORMAT_RGBA8)
	amb.resize(AMBLEM, AMBLEM, Image.INTERPOLATE_LANCZOS)
	img.blend_rect(amb, Rect2i(0, 0, AMBLEM, AMBLEM), Vector2i(W / 2 - AMBLEM / 2, H / 2 - AMBLEM / 2))
	img.convert(Image.FORMAT_RGB8)
	var out := "res://assets/ui/uretim/acilis_splash.png"
	print("[splash] ", out, " -> ", img.save_png(ProjectSettings.globalize_path(out)))
	quit()
