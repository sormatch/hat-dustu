# Test: oyun içi 2D ekranları tek tek gösterir (sunucusuz).  main.gd: pose=oyunici ekran=... oyun=...
#   ekran: kart | yardim | flash | tahta | sonraki | kimkim | secici | yalanci_esya | yalanci_oy | ortalama |
#          ortalama_sonuc | rulet | rulet_bar | rulet_gerilim | rulet_olu | rulet_hedef (hedef=<id>|kendi|0) | c4
#   bir oyun kendi ekranlarını kendi dosyasındaki test_ekran() ile çizebilir
extends RefCounted

const OI := preload("res://scripts/oyun_ici.gd")

const TITLES := {"tahta": "KARA TAHTA", "devre": "KISA DEVRE", "kimkim": "KİM KİM?", "yalanci": "YALANCI",
	"rulet": "RUS RULETİ", "c4": "C4", "ortalama": "ORTALAMA SAYI"}


static func run(m: Node, args: Dictionary) -> void:
	var g = m.game_ui
	var ek := str(args.get("ekran", "kart"))
	var task := str(args.get("oyun", "tahta"))
	m.net.players = [{"id": 1, "name": "Sen", "cell": 0}, {"id": 2, "name": "Kara Ali", "cell": 1},
		{"id": 3, "name": "Sinsi Necmi", "cell": 2}, {"id": 4, "name": "Deli Rıza", "cell": 3}]
	m.net.my_id = 1
	g.my_id = 1
	g.visible = true
	var ph := str(args.get("faz", "telefon"))
	var st := {"task": task, "phase": ph, "title": TITLES.get(task, ""), "players": [1, 2, 3, 4]}
	var sec := {"task": task, "round": 1}
	match task:
		"tahta":
			sec["yazan"] = args.get("yazan", "0") == "1"
			sec["hedef"] = 2
		"kimkim":
			sec.merge({"hat": 3, "toplam": 4, "adaylar": [{"id": 2, "ad": "Kara Ali"}, {"id": 3, "ad": "Sinsi Necmi"}, {"id": 4, "ad": "Deli Rıza"}]})
		"yalanci":
			sec.merge({"yalanci": args.get("yalanci", "0") == "1", "esya": "ponpon", "esya_ad": "KIRMIZI PONPONLU BERE"})
	g.state = st
	g.secret = sec
	g._ensure_mod(task if g.MODS.has(task) else "")
	var mod = g.mod
	if mod:
		mod.state = st
		mod.secret = sec
	OI.hap_ayarla(g._pill, str(st.title))
	g._pill.visible = true
	g._update_banner()
	if mod and mod.has_method("test_ekran") and ek != "yardim" and ek != "flash" and ek != "sonraki":
		mod.test_ekran(ek, args)
		return
	match ek:
		"kart":
			if mod:
				if task == "c4":
					mod.holder = int(args.get("bomba", "1"))
				mod.show_card()
			else:
				g._show_card()
		"yardim":
			g.show_help()
		"flash":
			g._flash(str(args.get("yazi", "BOMBA SENDE!")), str(args.get("alt", TranslationServer.translate("%s verdi!") % "Deli Rıza")), Color("#e0322a"), 3.0)
		"tahta":
			g.open_board()
			if args.has("yazi"):
				(g._panel.find_children("*", "LineEdit", true, false)[0] as LineEdit).text = args.yazi
		"sonraki":
			g._show_next("YALANCI")
		"kimkim":
			mod.picks = {1: 2, 2: 4}
			mod.open_board()
		"secici":
			mod.picks = {1: 2}
			mod.open_board()
			await m.get_tree().process_frame
			mod._open_chooser(2, {})
		"yalanci_esya":
			mod._item_card()
		"yalanci_oy":
			st.phase = "oylama"
			mod.voted = int(args.get("oy", "0"))
			mod.open_board()
			g._update_banner()
		"ortalama":
			st.phase = "yaz1"
			mod.number = "26"
			mod.saved = 26
			mod.open_board()
			g._update_banner()
		"ortalama_sonuc":
			mod._reveal({"sayilar": [{"id": 1, "ad": "Sen", "sayi": 26}, {"id": 2, "ad": "Kara Ali", "sayi": 9}, {"id": 3, "ad": "Sinsi Necmi", "sayi": 7}, {"id": 4, "ad": "Deli Rıza", "sayi": 17}],
				"ortalama": 15, "hedef": 8, "kazananlar": [2, 3]})
		"rulet", "rulet_bar", "rulet_gerilim", "rulet_olu":
			st.phase = "oyun"
			mod.holder = 1 if ek == "rulet_bar" else 2
			mod.stage = 1
			mod.alive = [1, 2, 3, 4] if ek != "rulet_olu" else [2, 3, 4]
			mod.dead = [] if ek != "rulet_olu" else [1]
			mod.turn_left = 4.0 if ek == "rulet_bar" else 11.0
			mod._hud.visible = true
			mod._refresh()
			if ek == "rulet_gerilim":
				mod._sus = mod._suspense(true)
		"rulet_hedef":
			# masada 3 bot, silah sende; hedef=<id>|kendi|0 bakışı ayarlar, asama=3 (%100), olu=<id>, ipucu=1
			await mod.test_hedef(args)
		"c4":
			st.phase = "bomba"
			mod._set_holder(int(args.get("bomba", "1")))
			g._update_banner()
