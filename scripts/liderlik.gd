# LİDERLİK ekranı (haftalık, her pazartesi sıfırlanır).
# Solda ilk üç için kürsü, sağda sıralama listesi, en altta sabit "SEN" satırı.
# İstek: account.send({"t":"liderlik"}) -> cevap account.leaderboard(d): {liste:[{sira,ad,handle,puan,seviye}], benim_sira, benim_puan}
extends CanvasLayer

signal closed

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")

var account: Node
var profile: Node

var _kok: Control
var _kursu: HBoxContainer
var _liste: VBoxContainer
var _ben: PanelContainer
var _sayac: Label
var _t := 0.0
var _yuklendi := false


func _ready() -> void:
	layer = 16
	var s := E.screen("LİDERLİK", "liderlik")
	_kok = s.kok
	add_child(_kok)
	(s.geri as Button).pressed.connect(_close)
	var sag: HBoxContainer = s.bar_sag
	var hp := E.pill("HAFTALIK", UI.AMBER, 18)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sag.add_child(hp)
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sv.add_theme_constant_override("separation", -4)
	sv.add_child(UI.label("Sıfırlanmasına", UI.FS_KUCUK, UI.METIN_SOLUK))
	_sayac = UI.title(_kalan(), UI.FS_METIN, UI.METIN)
	sv.add_child(_sayac)
	sag.add_child(sv)
	var govde: Control = s.govde
	# iki sütun: kürsü | liste
	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 16
	cols.offset_right = -16
	cols.offset_bottom = -12
	cols.add_theme_constant_override("separation", UI.B_M)
	govde.add_child(cols)
	var sol := UI.panel(Vector2(470, 0), 28)
	cols.add_child(sol)
	var sv2 := VBoxContainer.new()
	sv2.add_theme_constant_override("separation", UI.B_S)
	sol.add_child(sv2)
	sv2.add_child(UI.header("İLK ÜÇ", UI.FS_ORTA))
	_kursu = HBoxContainer.new()
	_kursu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_kursu.alignment = BoxContainer.ALIGNMENT_CENTER
	_kursu.add_theme_constant_override("separation", UI.B_S)
	sv2.add_child(_kursu)
	var sagp := UI.panel(Vector2.ZERO, 28)
	sagp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(sagp)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", UI.B_S)
	sagp.add_child(rv)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(sc)
	rv.add_child(sc)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", UI.B_XS)
	sc.add_child(_liste)
	_ben = E.row_box(UI.AMBER, Vector4(12, 8, 16, 8))
	rv.add_child(_ben)
	account.leaderboard.connect(_doldur)
	if not account.lider.is_empty():
		_doldur(account.lider)
	else:
		_yukleniyor()
	account.send({"t": "liderlik"})
	E.intro(_kok, govde)


func _process(delta: float) -> void:
	_t += delta
	if _t >= 1.0:
		_t = 0.0
		_sayac.text = _kalan()


# Türkiye saatiyle pazartesi 00:00'a kalan süre
func _kalan() -> String:
	var now := int(Time.get_unix_time_from_system()) + 3 * 3600
	var gun := int(now / 86400.0)
	var hafta_gunu := (gun + 3) % 7  # 1970-01-01 perşembe -> 0 = pazartesi
	var left := (7 - hafta_gunu) * 86400 - (now % 86400)
	var g := left / 86400
	var sa := (left / 3600) % 24
	if g > 0:
		return "%dg %02ds" % [g, sa]
	return "%02d:%02d" % [sa, (left / 60) % 60]


func _yukleniyor() -> void:
	for c in _liste.get_children():
		c.queue_free()
	var l := UI.title("Yükleniyor…", UI.FS_ORTA, UI.METIN_SOLUK, true)
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_liste.add_child(l)
	_kursu_doldur([])
	_ben_doldur(0, 0)


func _doldur(d: Dictionary) -> void:
	var list: Array = d.get("liste", [])
	for c in _liste.get_children():
		_liste.remove_child(c)
		c.queue_free()
	_kursu_doldur(list)
	if list.size() <= 3:
		_liste.add_child(_bos(list.is_empty()))
	else:
		for i in range(3, list.size()):
			_liste.add_child(_satir(list[i]))
	_ben_doldur(int(d.get("benim_sira", 0)), int(d.get("benim_puan", 0)))
	if not _yukleniyor_bitti():
		E.stagger(_liste, 0.035)
		E.stagger(_kursu, 0.12)


func _yukleniyor_bitti() -> bool:
	var once := _yuklendi
	_yuklendi = true
	return once


# Kürsü: 2. solda, 1. ortada (yüksek, taçlı), 3. sağda
func _kursu_doldur(list: Array) -> void:
	for c in _kursu.get_children():
		_kursu.remove_child(c)
		c.queue_free()
	for sira in [2, 1, 3]:
		var p: Dictionary = list[sira - 1] if list.size() >= sira else {}
		_kursu.add_child(_kursu_yeri(sira, p))


func _kursu_yeri(sira: int, p: Dictionary) -> Control:
	var renk: Color = E.KURSU_RENK[sira - 1]
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	v.custom_minimum_size.x = 128
	v.add_theme_constant_override("separation", 6)
	var bos := p.is_empty()
	var ad := str(p.get("ad", "?"))
	var px := 92.0 if sira == 1 else 74.0
	if sira == 1:
		var tac := UI.icon("tac", 56)
		tac.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(tac)
	var av_kap := Control.new()
	av_kap.custom_minimum_size = Vector2(px, px)
	av_kap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var hale := E.glow(renk, 0.5 if not bos else 0.0)
	UI.place(hale, Control.PRESET_TOP_LEFT, Vector2(-px * 0.5, -px * 0.5), Vector2(px * 2.0, px * 2.0))
	av_kap.add_child(hale)
	var av := E.avatar(ad if not bos else "?", str(p.get("handle", ad)), px)
	if bos:
		av.modulate = Color(0.4, 0.4, 0.4, 0.7)
	av_kap.add_child(av)
	v.add_child(av_kap)
	var n := UI.title(ad if not bos else "—", 20, UI.METIN, true)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.custom_minimum_size.x = 128
	v.add_child(n)
	if not bos:
		var ph := HBoxContainer.new()
		ph.alignment = BoxContainer.ALIGNMENT_CENTER
		ph.add_theme_constant_override("separation", 4)
		ph.add_child(UI.icon("xp", 26))
		ph.add_child(UI.title(E.sayi(int(p.get("puan", 0))), 20, renk))
		v.add_child(ph)
	else:
		v.add_child(UI.label(" ", 20, UI.METIN_SOLUK, true))
	# kürsü bloğu
	var blok := PanelContainer.new()
	blok.custom_minimum_size = Vector2(128, [0, 240, 180, 140][sira])
	var st := StyleBoxFlat.new()
	st.bg_color = renk.darkened(0.62)
	st.border_color = renk
	st.set_border_width_all(2)
	st.border_width_top = 6
	st.corner_radius_top_left = UI.R_ORTA
	st.corner_radius_top_right = UI.R_ORTA
	st.shadow_color = Color(renk, 0.25)
	st.shadow_size = 10
	blok.add_theme_stylebox_override("panel", st)
	var sl := UI.title(str(sira), 54 if sira == 1 else 44, renk.lightened(0.2), true)
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	blok.add_child(sl)
	v.add_child(blok)
	return v


func _satir(p: Dictionary) -> Control:
	var me: bool = account.handle != "" and str(p.get("handle", "")) == account.handle
	var box := E.row_box(UI.AMBER if me else Color(0, 0, 0, 0), Vector4(12, 6, 16, 6))
	box.custom_minimum_size.y = 68
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	box.add_child(h)
	var sl := UI.title(str(int(p.get("sira", 0))), UI.FS_ORTA, UI.METIN_SOLUK, true)
	sl.custom_minimum_size.x = 48
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(sl)
	var ad := str(p.get("ad", ""))
	var av := E.avatar(ad, str(p.get("handle", ad)), 48)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var n := UI.title(ad, 22, UI.METIN)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(n)
	var lv := E.level_shield(int(p.get("seviye", 1)), 50)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lv)
	var ph := HBoxContainer.new()
	ph.custom_minimum_size.x = 130
	ph.alignment = BoxContainer.ALIGNMENT_END
	ph.add_theme_constant_override("separation", 6)
	var pi := UI.icon("xp", 30)
	pi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(pi)
	var pl := UI.title(E.sayi(int(p.get("puan", 0))), UI.FS_ORTA, UI.AMBER)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.add_child(pl)
	h.add_child(ph)
	return box


func _ben_doldur(sira: int, puan: int) -> void:
	for c in _ben.get_children():
		_ben.remove_child(c)
		c.queue_free()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	_ben.add_child(h)
	var sl := UI.title(str(sira) if sira > 0 else "—", UI.FS_ORTA, UI.AMBER, true)
	sl.custom_minimum_size.x = 48
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(sl)
	var ad: String = profile.player_name
	var av := E.avatar(ad, account.handle if account.handle != "" else ad, 52)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", -2)
	tv.add_child(UI.title("SEN", 22, UI.METIN))
	var alt := "Bu hafta sıralamaya girmek için maç oyna" if sira <= 0 else ("Haftanın %d. oyuncususun" % sira)
	tv.add_child(UI.label(alt, UI.FS_KUCUK, UI.METIN_SOLUK))
	h.add_child(tv)
	var lv := E.level_shield(int(account.eco.get("seviye", 1)), 52)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lv)
	var ph := HBoxContainer.new()
	ph.custom_minimum_size.x = 130
	ph.alignment = BoxContainer.ALIGNMENT_END
	ph.add_theme_constant_override("separation", 6)
	var pi := UI.icon("xp", 30)
	pi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(pi)
	var pl := UI.title(E.sayi(puan), UI.FS_ORTA, UI.AMBER)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.add_child(pl)
	h.add_child(ph)


func _bos(hic: bool) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", UI.B_S)
	var ic := UI.icon("liderlik", UI.IKON_DEV)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	v.add_child(UI.title("İLK SIRA BOŞ!" if hic else "SIRALAMA YENİ BAŞLIYOR", UI.FS_ORTA, UI.METIN, true))
	v.add_child(UI.label("Maç oyna, puan topla, kürsüye sen çık." if hic else "Daha çok oyuncu puan aldıkça liste dolacak.", UI.FS_METIN, UI.METIN_SOLUK, true))
	return v


func _close() -> void:
	E.outro(_kok, func() -> void:
		closed.emit()
		queue_free())
