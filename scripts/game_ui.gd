# Oyun ekranları (Kara Tahta): rol kartı, üstte görev bandı, tahtaya tebeşirle yazma paneli,
# kişisel tur sonucu (puanlar gizli) ve oyun sonu puan tablosu. Kurallar sunucuda; burası gösterir ve yollar.
extends CanvasLayer

signal decided(value)
signal board_written(text: String)
signal leave_game
signal devre_fx(kind: String)  # kesinti, tamir, yanlis, bitti: ışıklar ve kutu için

const UI := preload("res://scripts/ui.gd")
const OI := preload("res://scripts/oyun_ici.gd")  # oyun içi ortak parçalar (kart, bant, tahta, bildirim)
const Fx := preload("res://scripts/store_fx.gd")
const CHALK_FONT := preload("res://assets/fonts/CabinSketch-Bold.ttf")
const CHALK := Color(0.95, 0.96, 0.9)
const DevreBox := preload("res://scripts/devre_box.gd")
const DevreSema := preload("res://scripts/devre_sema.gd")
# yeni oyunların ekranları (her biri modlar/ altında kendi dosyasında)
const MODS := {
	"kimkim": preload("res://scripts/modlar/kimkim_ui.gd"),
	"yalanci": preload("res://scripts/modlar/yalanci_ui.gd"),
	"rulet": preload("res://scripts/modlar/rulet_ui.gd"),
	"c4": preload("res://scripts/modlar/c4_ui.gd"),
	"ortalama": preload("res://scripts/modlar/ortalama_ui.gd"),
}

var net: Node
var world: Node3D  # main.gd (yeni oyunların 3D etkileri için)
var mod: Node  # şu anki yeni oyunun ekranı (yoksa null)
var _board_task := ""  # tahtadaki yazının ait olduğu oyun
var my_id := 0
var state := {}  # son "oyun" mesajı
var secret := {}  # son "gizli" mesajı (rolün)
var my_score := 0
var written := ""  # bu tur tahtana yazdığın
var _last_result := {}
var _box: Control  # açık sigorta paneli
var _box_state := {"plugged": {}, "adim": 0, "status": "acik", "hak": 3}
var _devre_counts := {}

var _root: Control
var _banner: PanelContainer
var _banner_title: Label
var _banner_info: Label
var _card: Control
var _write_btn: Button
var _panel: Control
var _overlay: Control
var _round_label: Label
var _score_label: Label
var _pill: PanelContainer


func _ready() -> void:
	layer = 12
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# sol üst: oyunun rozeti ve adı (puan YOK: puanlar maç sonuna kadar gizli)
	_pill = OI.hap()
	_round_label = _pill.get_meta("label")
	_pill.position = Vector2(108, 14)
	_root.add_child(_pill)
	_score_label = UI.title("", 22, UI.ELMAS)  # eski kod için; ekrana hiç eklenmez
	_score_label.visible = false
	_root.add_child(_score_label)
	# sayacın altında tek satırlık görev bandı; dokununca rol kartı yeniden açılır
	_banner = OI.bant()
	_banner_title = _banner.get_meta("tag")
	_banner_info = _banner.get_meta("info")
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_left = 0
	_banner.offset_right = 0
	_banner.offset_top = 80
	_banner.gui_input.connect(func(e: InputEvent) -> void:
		if _pressed(e):
			_show_card())
	_banner.visible = false
	_root.add_child(_banner)
	# alt orta: tek ana eylem (TAHTAYA YAZ, SAYI YAZ, OYLA...)
	_write_btn = UI.button("TAHTAYA YAZ", "ana", UI.BTN_H, 28, "tahta", 340)
	_write_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_write_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_write_btn.offset_left = -170
	_write_btn.offset_right = 170
	_write_btn.offset_top = -UI.BTN_H - 24
	_write_btn.offset_bottom = -24
	_write_btn.pressed.connect(open_board)
	_write_btn.visible = false
	_root.add_child(_write_btn)
	visible = false


# Aynı anda tek bant: üstte bir bildirim (hud toast'u, aynı yerde çıkar) varken görev bandı yumuşakça gizlenir.
func _process(delta: float) -> void:
	if _banner == null or not _banner.visible:
		return
	var toast_var = null
	var hud_n = world.get("hud") if is_instance_valid(world) else null
	if is_instance_valid(hud_n):
		toast_var = hud_n.get("_toast")
	var hedef := 0.0 if is_instance_valid(toast_var) else 1.0
	_banner.modulate.a = move_toward(_banner.modulate.a, hedef, delta * 8.0)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE if hedef < 0.5 else Control.MOUSE_FILTER_STOP


static func _pressed(e: InputEvent) -> bool:
	return (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)


func _play(n: String, vol := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _clear(c) -> void:
	if is_instance_valid(c):
		c.queue_free()


func _is_writer() -> bool:
	return bool(secret.get("yazan", false))


# Karartılmış katman + ortada metal panel. Dönen: [katman, içerik kutusu]
func _modal(min_w: float, dim := 0.6) -> Array:
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = Color(0.01, 0.01, 0.03, dim)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(d)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var p := UI.panel(Vector2(min_w, 0), 30)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	_root.add_child(ov)
	p.pivot_offset = Vector2(min_w / 2, 120)
	p.scale = Vector2.ONE * 0.85
	p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return [ov, v]


# ---------- sunucudan gelenler ----------

func on_state(d: Dictionary) -> void:
	visible = true
	_pill.visible = true
	if str(d.phase) == "sonuc":
		if mod:
			mod.state["phase"] = "sonuc"
		_show_next(str(d.get("sonraki", "")))
		return
	var entered := str(state.get("phase", "")) != str(d.phase) or str(state.get("task", "")) != str(d.get("task", ""))
	state = d
	var phase := str(d.phase)
	OI.hap_ayarla(_pill, str(d.get("title", "")))
	_score_label.visible = false  # puanlar maç sonuna kadar kimseye görünmez (kendi puanın dahil)
	if str(d.get("task", "")) != _board_task:
		_board_task = str(d.get("task", ""))
		board_written.emit("")  # önceki oyunun tahta yazısı (ör. "B4 KUTUSU") silinsin
		_oyun_degisti()
	_ensure_mod(str(d.get("task", "")))
	if mod:
		if entered:
			_clear(_overlay)
		mod.on_state(d, entered)
		_update_banner()
		return
	if _task() == "devre":
		_on_devre_state(phase)
		_update_banner()
		return
	match phase:
		"anons":
			written = ""
			board_written.emit("")
			_clear(_panel)
			_clear(_overlay)
			_play("anons")
		"telefon":
			_clear(_card)
			_play("sec", -6.0)
			if _is_writer() and written == "":
				open_board()
	_update_banner()


func on_secret(d: Dictionary) -> void:
	if not secret.is_empty() and secret.get("task") == d.get("task") and int(secret.get("round", -1)) == int(d.get("round", -2)):
		secret = d
		if mod:
			mod.secret = d
		return
	secret = d
	if str(d.get("task", "")) != "" and str(d.get("task", "")) != _board_task:
		# gizli bilgi oyun durumundan önce geldiyse temizlik burada (yeni kartı sonradan silmesin)
		_board_task = str(d.get("task", ""))
		board_written.emit("")
		_oyun_degisti()
	_ensure_mod(str(d.get("task", "")))
	if mod:
		my_score = int(d.get("puan", my_score))
		_score_label.text = "PUANIN %d" % my_score
		mod.on_secret(d)
		_update_banner()
		return
	if d.get("task") == "devre":
		my_score = int(d.get("puan", my_score))
		_score_label.text = "PUANIN %d" % my_score
		_box_state = {"plugged": {}, "adim": 0, "status": "acik", "hak": int(d.get("hak", 3))}
		board_written.emit(str(d.get("tahta", "")))
		_update_banner()
		# kart, dramatik açılıştan sonra gelir (oyun bu arada değiştiyse gelmez)
		var rnd := int(d.get("round", 0))
		get_tree().create_timer(3.4).timeout.connect(func() -> void:
			if _task() == "devre" and int(secret.get("round", -1)) == rnd and str(state.get("phase", "")) in ["anons", "calisma"]:
				_show_card())
		return
	_update_banner()
	_show_card()


# Yeni oyun başladı: önceki oyundan kalan HER ŞEY kesin kapanır (rol kartı, tahta/pencere, sigorta paneli,
# tur sonu ekranı, yardım, büyük bildirimler, alttaki ana düğme). Kullanıcı TAMAM'a basmasa da kalmaz.
func _oyun_degisti() -> void:
	clear_flashes()
	for n in [_card, _panel, _box, _overlay]:
		_clear(n)
	_card = null
	_panel = null
	_box = null
	_overlay = null
	if mod:
		mod.close_card()
		mod.close_panel()
	_write_btn.visible = false
	_banner.modulate.a = 1.0


# Görev değişti: eski oyunun ekranını temizle, yenisininkini kur.
func _ensure_mod(task: String) -> void:
	if task == "":
		return
	if mod and str(mod.task) == task:
		return
	if mod:
		mod.cleanup()
		mod.queue_free()
		mod = null
	if MODS.has(task):
		mod = MODS[task].new()
		mod.g = self
		mod.w = world
		mod.task = task
		add_child(mod)


func on_event(d: Dictionary) -> void:
	if mod and str(mod.task) == str(d.get("task", "")):
		mod.on_event(d)


func on_written(kind: String) -> void:
	_play("sec")
	if kind == "kelime":
		_banner_info.text = "%s · şimdi telefonla söyle" % written


# Kişisel tur sonucu: kelime herkese açık, puanın sadece sana.
func on_result(d: Dictionary) -> void:
	_last_result = d
	if d.get("task") == "devre":
		_clear(_box)
		devre_fx.emit("bitti")
	if mod and str(mod.task) == str(d.get("task", "")):
		if int(d.round) >= int(d.get("rounds", 1)):
			mod.cleanup()  # son oyun: sonucu bitiş ekranı gösterir
		else:
			_banner.visible = false
			mod.on_result(d)
		return
	if int(d.round) >= int(d.get("rounds", 1)):
		return  # son oyun: sonucu bitiş ekranı gösterir
	if d.get("task") == "devre":
		_devre_result(d)
		return
	_clear(_card)
	_clear(_panel)
	_write_btn.visible = false
	_banner.visible = false
	_clear(_overlay)
	# Kara Tahta: puanlar gizli, tur sonu ekranı sadece kendi sonucunu gösterir
	var ben = d.get("ben")
	var word := str(d.get("word", ""))
	var lines := []
	if word != "":
		lines.append("%s tahtaya yazmıştı" % str(d.get("writer_name", "?")))
	if typeof(ben) == TYPE_DICTIONARY and ben.has("guess"):
		lines.append("Senin tahminin: %s" % str(ben.guess))
	var ts = load("res://scripts/tur_sonu.gd").new()
	ts.setup(d, my_id, word if word != "" else "SÜRE BİTTİ", CHALK if word != "" else Color("#ffcf8a"), lines)
	_root.add_child(ts)
	_overlay = ts


# Ekrandaki büyük bildirimleri kaldırır (sonuç penceresinin üstüne binmesin).
func clear_flashes() -> void:
	for c in get_children():
		if c.has_meta("flash"):
			c.queue_free()


func on_over(d: Dictionary) -> void:
	clear_flashes()
	if mod:
		mod.cleanup()
		mod.queue_free()
		mod = null
	_clear(_card)
	_clear(_panel)
	_clear(_overlay)
	_clear(_box)
	_write_btn.visible = false
	_banner.visible = false
	# maç sonu ekranı: puan tablosu sondan başa açılır, en son kazanan taçla sahneye çıkar
	var ms = load("res://scripts/mac_sonu.gd").new()
	ms.setup(d, my_id, net.players if net else [])
	ms.back.connect(func() -> void: leave_game.emit())
	_root.add_child(ms)
	_overlay = ms


# ---------- rol kartı ve bant ----------

func _role_text() -> String:
	if _is_writer():
		return "Gizli bir kelime yaz. Tam %d kişi bilsin." % int(secret.get("hedef", 1))
	return "Yazan gizli. Kelimeyi telefonla öğren, tahtana yaz."


func _task() -> String:
	return str(state.get("task", secret.get("task", "")))


func _update_banner() -> void:
	var phase := str(state.get("phase", ""))
	(_banner.get_meta("icon") as Control).visible = false
	if mod:
		var b: Array = mod.banner()
		_banner.visible = phase != "sonuc" and phase != "bitti" and str(b[0]) + str(b[1]) != ""
		_banner_title.text = str(b[0])
		_banner_info.text = str(b[1])
		return
	if _task() == "devre":
		var live := phase in ["anons", "calisma"] and not secret.is_empty()
		_banner.visible = live
		var pn: String = {"anons": "IŞIKLAR KESİLDİ", "calisma": "KUTUNU ONAR"}.get(phase, "")
		_banner_title.text = pn
		var c := _devre_counts if not _devre_counts.is_empty() else state
		_banner_info.text = "Şeman %s için · %d/%d onarıldı" % [str(secret.get("yardim_ad", "?")), int(c.get("onarilan", 0)), int(c.get("toplam", 0))]
		_write_btn.visible = false
		return
	var live := phase in ["anons", "telefon"] and not secret.is_empty()
	_banner.visible = live
	# bantta sadece ne yapacağın: kısa etiket + kısa bilgi (oyunun adı sol üstte)
	if _is_writer():
		_banner_title.text = "GİZLİ KELİMEN"
		_banner_info.text = ("%s · tam %d kişi bilsin" % [written, int(secret.get("hedef", 1))]) if written != "" else "Tahtana yaz"
	else:
		_banner_title.text = "KELİMEYİ BUL"
		_banner_info.text = ("Tahtanda: " + written) if written != "" else "Telefonla öğren"
	var can_write := phase == "telefon" or (_is_writer() and phase == "anons")
	_write_btn.visible = false  # tahtaya yaklaşınca panel kendiliğinden açılır
	UI.set_button_text(_write_btn, "TAHTAYA YAZ" if written == "" else "DEĞİŞTİR")


func _show_card() -> void:
	if mod:
		mod.show_card()
		return
	if secret.is_empty():
		return
	if secret.get("task") == "devre":
		_show_devre_card()
		return
	_clear(_card)
	var writer := _is_writer()
	var extra: Control = null
	if writer:
		# hedef: kaç kişi bilmeli (tebeşir değil, büyük sayı)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", UI.B_S)
		h.add_child(UI.icon("arkadas", 56))
		h.add_child(UI.title("× %d" % int(secret.get("hedef", 1)), 52, UI.AMBER))
		extra = h
	_card = rol_karti("tahta", "SEN YAZIYORSUN" if writer else "KELİMEYİ BUL", UI.AMBER if writer else UI.MAVI, _role_text(), extra)


# Oyunun rozetli rol kartı (kendiliğinden kapanır). Dönen: katman.
func rol_karti(task: String, title: String, col: Color, line: String, extra: Control = null, sure := 4.5) -> Control:
	return OI.rol_karti(_root, task, title, col, line, extra, sure)


# Sade pencere: perde + takımın çelik paneli, yumuşak açılış. Dönen: [katman, içerik kutusu]
func _clean_modal(min_w: float) -> Array:
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = UI.PERDE
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(d)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var p := UI.panel(Vector2(min_w, 0), UI.B_XL)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_M)
	p.add_child(v)
	_root.add_child(ov)
	p.pivot_offset = Vector2(min_w / 2, 120)
	p.scale = Vector2.ONE * 0.88
	d.modulate.a = 0.0
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(d, "modulate:a", 1.0, 0.18)
	return [ov, v]


# ---------- KISA DEVRE ----------

func _on_devre_state(phase: String) -> void:
	match phase:
		"anons":
			_clear(_panel)
			_clear(_overlay)
			_clear(_box)
			_devre_counts = {}
			_blackout_intro()
		"calisma":
			_clear(_card)
			_play("sec", -6.0)


# Dramatik açılış: çift şimşek parlaması, gök gürültüsü, çığlık, ışıklar söner, titreyen kırmızı yazı.
func _blackout_intro() -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(flash)
	_play("simsek", 2.0)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.95, 0.04)
	tw.tween_property(flash, "color:a", 0.0, 0.12)
	tw.tween_interval(0.08)
	tw.tween_property(flash, "color:a", 0.8, 0.03)
	tw.tween_callback(func() -> void: devre_fx.emit("kesinti"))
	tw.tween_property(flash, "color", Color(0, 0, 0, 0.85), 0.25)
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void: _play("ciglik", -2.0))
	tw.tween_property(flash, "color:a", 0.45, 1.2)
	tw.tween_interval(1.6)
	tw.tween_property(flash, "color:a", 0.0, 0.6)
	tw.tween_callback(flash.queue_free)
	# arızalı neon gibi titreyen, renk kaymalı, elektrik arklı yazı
	var title: Control = load("res://scripts/glitch_title.gd").new()
	title.sub = "Sigorta kutunu bul ve onar!"
	title.life = 3.4
	get_tree().create_timer(0.3).timeout.connect(func() -> void: _root.add_child(title))


# Kısa Devre rol kartı: diğer oyunlarınki gibi rozetli, kısa ve 4,5 sn'de kendiliğinden kapanır.
func _show_devre_card() -> void:
	_clear(_card)
	var who := str(secret.get("yardim_ad", "?"))
	# ek: kimi araman gerektiği kocaman (telefon ikonu + ad)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := UI.icon("telefon", 60)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -6)
	hv.add_child(UI.title("TAHTANDAKİ ŞEMA", UI.FS_KUCUK + 2, UI.METIN_SOLUK))
	hv.add_child(UI.title(who.replace("i", "İ").replace("ı", "I").to_upper(), 46, UI.AMBER))
	h.add_child(hv)
	_card = rol_karti("devre", "KUTUNU ONAR", UI.YESIL, "Onu ara, şemasını oku.", h)

# Tahtadaki şema (başkasının kutusu için): tebeşirle çizilmiş renkli kablo -> sembol / numara.
func _show_devre_board() -> void:
	if secret.is_empty() or str(state.get("phase", "")) != "calisma":
		return
	_clear(_panel)
	var sema: Control = DevreSema.new()
	sema.kimin = str(secret.get("yardim_ad", "?"))
	var rows = secret.get("sema", [])
	if typeof(rows) != TYPE_ARRAY or (rows as Array).is_empty():
		# eski sunucu: "RENK >> SEMBOL" satırlarından kur
		rows = []
		var lines: PackedStringArray = str(secret.get("tahta", "")).split("
")
		for i in range(1, lines.size()):
			var parts: PackedStringArray = lines[i].split(" >> ")
			if parts.size() == 2:
				(rows as Array).append([parts[0], "S", parts[1]])
	sema.rows = rows
	sema.closed.connect(func() -> void: _clear(_panel))
	_root.add_child(sema)
	_panel = sema
	_play("sec", -8.0)


func open_box() -> void:
	if secret.is_empty() or _task() != "devre":
		return
	_clear(_box)
	var b: Control = DevreBox.new()
	b.wires = secret.get("kablolar", [])
	b.symbols = secret.get("semboller", [])
	b.steps = int(secret.get("adim_sayisi", 4))
	b.connected = _box_state.plugged  # aynı sözlük: kapatıp açınca bağlantılar kalır
	b.done_steps = int(_box_state.adim)
	b.status = str(_box_state.status)
	b.lives = int(_box_state.get("hak", 3))
	b.action.connect(func(v: Dictionary) -> void: decided.emit(v))
	b.closed.connect(func() -> void: _clear(_box))
	_root.add_child(b)
	_box = b


# Sunucudan anında sonuç: doğru adım, onarıldı (şalter), yanlış, kutu yandı ya da şeman işe yaradı.
# Puanlar maç sonuna kadar gizli: burada hiçbir sayı gösterilmez.
func on_devre(d: Dictionary) -> void:
	var olay := str(d.olay)
	if olay == "yardim":
		_flash("YARDIMIN İŞE YARADI!", "%s kutusunu onardı" % str(d.kim), Color("#5be37d"))
		_play("odul")
		return
	if d.has("adim"):
		_box_state.adim = int(d.adim)
	if d.has("hak"):
		_box_state.hak = int(d.hak)
	var open := is_instance_valid(_box)
	match olay:
		"adim":
			if not open:
				_flash("ŞALTERİ KALDIR" if bool(d.get("hazir", false)) else "DOĞRU!", "", Color("#7dff9f"), 0.9)
				_play("odul", -8.0)
		"tamir":
			if _box_state.status == "tamir":
				return
			_box_state.status = "tamir"
			if not open:
				_flash("ONARDIN!", "", Color("#5be37d"))
				_play("guc_geldi")
			_play("odul", -6.0)
			devre_fx.emit("tamir")
		"yanlis":
			if not open:
				_flash("KISA DEVRE!", "", Color("#ff3b3b"), 0.9)
				_play("kivilcim")
			devre_fx.emit("yanlis")
		"kilit":
			if _box_state.status == "kilit":
				return
			_box_state.status = "kilit"
			if not open:
				_flash("KUTU YANDI", "", Color("#ff3b3b"))
				_play("kivilcim")
				_play("vizilti", -6.0)
			devre_fx.emit("kilit")
	if olay == "adim" and d.has("renk"):
		_box_state.plugged[str(d.renk)] = str(d.sembol)
	if open:
		_box.set_result(olay, int(_box_state.adim), str(d.get("renk", "")), str(d.get("sembol", "")), int(_box_state.get("hak", -1)))


func on_devre_status(d: Dictionary) -> void:
	_devre_counts = d
	_update_banner()


# Ekranın ortasında kısa süreli büyük bildirim.
# Sinematik şerit üstünde büyük yazı; aynı anda tek bildirim (yenisi eskisini kaldırır).
func _flash(title: String, sub: String, col: Color, t := 1.6) -> void:
	clear_flashes()
	OI.flash(self, title, sub, col, t)


func _devre_result(d: Dictionary) -> void:
	_clear(_overlay)
	var all := bool(d.get("hepsi", false))
	var lines := ["Onarılan kutu: %d / %d" % [int(d.get("onarilan", 0)), int(d.get("toplam", 0))]]
	if str(d.get("ilk_ad", "")) != "":
		lines.append("İlk onaran: %s" % str(d.ilk_ad))
	var ts = load("res://scripts/tur_sonu.gd").new()
	ts.setup(d, my_id, "IŞIKLAR GELDİ!" if all else "SÜRE BİTTİ", Color("#5be37d") if all else Color("#ffcf8a"), lines, [], 1 if all else 0)
	_root.add_child(ts)
	_overlay = ts


# Oyunlar arası: tur sonu ekranı sıradaki oyunu zaten gösterir; ekran kapandıysa bantta rozetiyle görünür.
func _show_next(title: String) -> void:
	_write_btn.visible = false
	_banner.visible = true
	_banner_title.text = "SIRADAKİ"
	_banner_info.text = title if title != "" else "hazırlanıyor..."
	var ic: TextureRect = _banner.get_meta("icon")
	ic.texture = OI.rozet_tex(OI.gorev_of(title), 44)
	ic.visible = ic.texture != null


# ---------- bilgisayar: oyunun amacı ----------

func show_help() -> void:
	visible = true
	_pill.visible = not state.is_empty()  # oyun dışında (tek başına) üst yazı görünmesin
	_clear(_overlay)
	var devre := _task() == "devre"
	var task := str(mod.task) if mod else ("devre" if devre else "tahta")
	var title := str(state.get("title", "")) if mod else ("KISA DEVRE" if devre else "KARA TAHTA")
	# üç adım: büyük ikon + birkaç kelime (uzun kural metni yok)
	var rows: Array = mod.help_rows() if mod else [
		["sigorta", "Kutun bozuk: onar"],
		["telefon", "Şemanı bilen başkası: ara"],
		["onay", "Kabloları doğru prize tak"],
	] if devre else [
		["tahta", "Biri gizli kelime yazar"],
		["telefon", "Telefonla öğren, tahtana yaz"],
		["onay", "Tam hedef kadar kişi bilsin"],
	]
	var m := OI.yardim(task, title, rows)
	m.closed.connect(func() -> void:
		if state.is_empty():
			visible = false)
	_root.add_child(m)
	_overlay = m
	_play("sec")


# ---------- tahtaya yazma ----------

func _chalk_label(text: String, size: int) -> Label:
	return OI.chalk_label(text, size)


# Tebeşirle elle çizilmiş simgeler ve kutular (scripts/oyun_ici.gd).
const ChalkDraw := OI.ChalkDraw


# Tebeşirle elle çizilmiş çerçeveli düğme: içinde simge ve tebeşir yazısı.
func _chalk_button(text: String, icon_kind: String, filled: bool, w: float) -> Button:
	return OI.chalk_button(text, icon_kind, filled, w)


# Kara tahta: ahşap çerçeveli gerçek tahta, tebeşirle başlık, ortada kocaman yazı alanı (tebeşir çizgisi),
# altta tebeşir "Yaz" ve silgi; köşede tebeşir çarpı. Yazı az: başlık + gerekirse tek kısa satır.
func open_board() -> void:
	if mod:
		mod.open_board()
		return
	if _task() == "devre":
		_show_devre_board()
		return
	var phase := str(state.get("phase", ""))
	var can_write := phase == "telefon" or (_is_writer() and phase == "anons")
	if not can_write:
		return
	_clear(_panel)
	var info := ("Tam %d kişi bilsin" % int(secret.get("hedef", 1))) if _is_writer() else ""
	var m := OI.chalk_board(_root, "Gizli kelimen" if _is_writer() else "Tahminin", info, 1000.0)
	var ov: Control = m[0]
	var v: VBoxContainer = m[1]
	var close: Button = m[2]
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var e := LineEdit.new()
	e.text = written.to_lower()
	e.max_length = 16
	e.placeholder_text = "kelime..."
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_font_override("font", CHALK_FONT)
	e.add_theme_font_size_override("font_size", 100)
	e.add_theme_color_override("font_color", CHALK)
	e.add_theme_color_override("font_placeholder_color", Color(CHALK, 0.22))
	e.add_theme_color_override("caret_color", CHALK)
	e.add_theme_color_override("selection_color", Color(CHALK, 0.25))
	var empty := StyleBoxEmpty.new()
	for k in ["normal", "focus", "read_only"]:
		e.add_theme_stylebox_override(k, empty)
	e.custom_minimum_size = Vector2(0, 124)
	v.add_child(e)
	var line := ChalkDraw.new()
	line.custom_minimum_size = Vector2(0, 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	# tek satır durum: tahtadaki kelime ya da uyarı (boşsa görünmez)
	var hint := OI.chalk_label("", 28, OI.CHALK_YESIL)
	hint.custom_minimum_size.y = 40
	v.add_child(hint)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp2)
	var refresh := func() -> void:
		hint.add_theme_color_override("font_color", OI.CHALK_YESIL)
		hint.text = ("Tahtanda: " + written) if written != "" else ""
	refresh.call()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UI.B_L)
	var ok := OI.chalk_button("Yaz", "tebesir", true, 320, 80)
	var erase := OI.chalk_button("", "silgi", false, 110, 80)
	row.add_child(ok)
	row.add_child(erase)
	v.add_child(row)
	# yazarken tebeşir sesi
	var chalk := AudioStreamPlayer.new()
	var rnd := AudioStreamRandomizer.new()
	for i in 3:
		rnd.add_stream(-1, load("res://assets/ses/tebesir_%d.ogg" % (i + 1)))
	rnd.random_pitch = 1.15
	chalk.stream = rnd
	chalk.volume_db = -6.0
	ov.add_child(chalk)
	e.text_changed.connect(func(_t: String) -> void:
		chalk.play()
		refresh.call())
	erase.pressed.connect(func() -> void:
		e.text = ""
		chalk.play()
		refresh.call()
		e.grab_focus())
	var submit := func() -> void:
		var t := e.text.strip_edges()
		if t.length() < 2:
			hint.text = "En az 2 harf"
			hint.add_theme_color_override("font_color", OI.CHALK_KIRMIZI)
			_play("hata", -10.0)
			return
		written = t.to_upper()
		board_written.emit(written)
		decided.emit(t)
		hint.text = "Tahtaya yazıldı!"
		_play("sec", -4.0)
		# yazı tebeşirle "basılır": kısa büyüme, sonra pencere kapanır
		e.pivot_offset = e.size / 2.0
		var tw := ov.create_tween()
		tw.tween_property(e, "scale", Vector2.ONE * 1.12, 0.1)
		tw.tween_property(e, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.35)
		tw.tween_callback(func() -> void:
			_clear(_panel)
			_update_banner())
	ok.pressed.connect(submit)
	e.text_submitted.connect(func(_t: String) -> void: submit.call())
	close.pressed.connect(func() -> void: _clear(_panel))
	_panel = ov
	e.grab_focus.call_deferred()
	e.caret_column = e.text.length()
