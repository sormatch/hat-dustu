# GÖREVLER / BAŞARIMLAR ekranı (iki sekme).
# Görevler: günlük giriş serisi (7 gün) + 3 günlük görev (ilerleme çubuğu, tamamlananı AL).
# Başarımlar: kalıcı hedefler (ilerleme, AL). Veri: account.eco (sunucunun "ekonomi" mesajı).
# AL -> account.send({"t":"gorev_al","i":i}) / {"t":"basarim_al","k":k}; sonuç ekonomi güncellemesiyle gelir.
extends CanvasLayer

signal closed

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")

var account: Node
var profile: Node
var tab := 0  # 0 görevler, 1 başarımlar

var _kok: Control
var _govde: Control
var _tabs: HBoxContainer
var _icerik: VBoxContainer
var _sayac: Label
var _gem_label: Label
var _baslik: Label
var _t := 0.0


func _ready() -> void:
	layer = 16
	var s := E.screen("GÖREVLER", "gorev")
	_kok = s.kok
	_baslik = s.baslik
	_govde = s.govde
	add_child(_kok)
	(s.geri as Button).pressed.connect(_close)
	var gem := UI.counter("elmas", "0", 40)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gem_label = gem.get_meta("label")
	_gem_label.add_theme_color_override("font_color", UI.ELMAS)
	(s.bar_sag as HBoxContainer).add_child(gem)
	# sekmeler
	_tabs = HBoxContainer.new()
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("separation", UI.B_S)
	UI.place(_tabs, Control.PRESET_CENTER_TOP, Vector2(-300, 0), Vector2(600, UI.DOKUNMA))
	_govde.add_child(_tabs)
	# içerik paneli
	var p := UI.panel(Vector2.ZERO, 32)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_top = UI.DOKUNMA - 4
	p.offset_bottom = -12
	_govde.add_child(p)
	# geniş ekranda panel aşırı uzamasın: en çok 1100 px, ortada
	var ortala := func() -> void:
		var w := _govde.size.x
		var pw := minf(w - 32.0, 1100.0)
		p.offset_left = (w - pw) / 2.0
		p.offset_right = -(w - pw) / 2.0
	_govde.resized.connect(ortala)
	ortala.call()
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(sc)
	p.add_child(sc)
	_icerik = VBoxContainer.new()
	_icerik.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icerik.add_theme_constant_override("separation", UI.B_S)
	sc.add_child(_icerik)
	account.economy_changed.connect(_build)
	_build()
	E.intro(_kok, null)
	E.stagger(_icerik, 0.06)


func _process(delta: float) -> void:
	_t += delta
	if _t >= 1.0 and _sayac and is_instance_valid(_sayac):
		_t = 0.0
		_sayac.text = _kalan()


# Türkiye saatiyle gece yarısına kalan süre (görevler ve günlük ödül o an yenilenir)
func _kalan() -> String:
	var now := int(Time.get_unix_time_from_system()) + 3 * 3600
	var left := 86400 - (now % 86400)
	return "%02d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]


func _build() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	for i in 2:
		var t := UI.tab("GÖREVLER" if i == 0 else "BAŞARIMLAR", i == tab, "gorev" if i == 0 else "basarim")
		t.custom_minimum_size.x = 280
		var n := _alinabilir(i)
		if n > 0:
			UI.badge_on(t, n, 28)
		t.pressed.connect(func() -> void:
			if tab != i:
				tab = i
				_build()
				E.stagger(_icerik, 0.05))
		_tabs.add_child(t)
	for c in _icerik.get_children():
		_icerik.remove_child(c)
		c.queue_free()
	_gem_label.text = E.sayi(int(account.eco.get("elmas", profile.gems)))
	_baslik.text = "GÖREVLER" if tab == 0 else "BAŞARIMLAR"
	_sayac = null
	if tab == 0:
		_build_gorevler()
	else:
		_build_basarimlar()


func _alinabilir(i: int) -> int:
	var n := 0
	for m in account.eco.get("gorevler" if i == 0 else "basarimlar", []):
		if not bool(m.get("alindi", false)) and int(m.get("ilerleme", 0)) >= int(m.get("hedef", 1)):
			n += 1
	return n


# ---------------------------------------------------------------------
# GÖREVLER
# ---------------------------------------------------------------------
func _build_gorevler() -> void:
	_icerik.add_child(_streak())
	# başlık + yenilenme sayacı
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	var t := UI.title("GÜNLÜK GÖREVLER", UI.FS_ORTA, UI.AMBER)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(UI.label("Yenilenmesine", UI.FS_KUCUK, UI.METIN_SOLUK))
	_sayac = UI.title(_kalan(), UI.FS_METIN, UI.METIN)
	h.add_child(_sayac)
	_icerik.add_child(h)
	var list: Array = account.eco.get("gorevler", [])
	if list.is_empty():
		_icerik.add_child(_bos("gorev", "Görevler yükleniyor…", "İnternete bağlanınca bugünün görevleri gelir."))
		return
	for i in list.size():
		var m: Dictionary = list[i]
		_icerik.add_child(_hedef_satiri("gorev", str(m.get("ad", "")), "", int(m.get("ilerleme", 0)), int(m.get("hedef", 1)),
			int(m.get("odul", 0)), bool(m.get("alindi", false)), func() -> void: account.send({"t": "gorev_al", "i": i})))


# 7 günlük giriş serisi: geçmiş günler işaretli, bugün parlıyor; ödül 30 + gün*10
func _streak() -> Control:
	var box := E.row_box(UI.YESIL if profile.daily_available() else Color(0, 0, 0, 0), Vector4(16, 12, 16, 12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_M)
	box.add_child(h)
	var ic := UI.icon("gift", 76)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.custom_minimum_size.x = 170
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UI.title("GÜNLÜK ÖDÜL", 22, UI.METIN))
	var hazir: bool = profile.daily_available()
	var seri := int(account.eco.get("seri", 0))
	var bugun := mini(7, seri + 1) if hazir else seri  # bugün alınacak (ya da alınmış) gün
	tv.add_child(UI.label(tr("Seri: %d gün") % seri if seri > 0 else "Her gün gir, ödül büyüsün", UI.FS_KUCUK, UI.METIN_SOLUK))
	h.add_child(tv)
	var gunler := HBoxContainer.new()
	gunler.add_theme_constant_override("separation", 6)
	gunler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gunler.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(gunler)
	for d in range(1, 8):
		var alindi := d < bugun or (d == bugun and not hazir)
		var simdi := d == bugun and hazir
		var g := PanelContainer.new()
		g.custom_minimum_size = Vector2(70, 76)
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(UI.R_KUCUK + 2)
		st.set_border_width_all(2)
		if simdi:
			st.bg_color = Color(UI.AMBER, 0.22)
			st.border_color = UI.AMBER
			st.shadow_color = Color(UI.AMBER, 0.45)
			st.shadow_size = 8
		elif alindi:
			st.bg_color = Color(UI.YESIL, 0.16)
			st.border_color = Color(UI.YESIL, 0.6)
		else:
			st.bg_color = Color(0, 0, 0, 0.4)
			st.border_color = UI.CIZGI
		g.add_theme_stylebox_override("panel", st)
		var gv := VBoxContainer.new()
		gv.alignment = BoxContainer.ALIGNMENT_CENTER
		gv.add_theme_constant_override("separation", 0)
		g.add_child(gv)
		gv.add_child(UI.title(tr("%d. GÜN") % d, UI.FS_KUCUK, UI.AMBER if simdi else (UI.YESIL if alindi else UI.METIN_SOLUK), true))
		if alindi:
			gv.add_child(UI.title("✓", 30, UI.YESIL, true))
		else:
			var r := E.reward(30 + d * 10, 24)
			r.alignment = BoxContainer.ALIGNMENT_CENTER
			gv.add_child(r)
		gunler.add_child(g)
		if simdi:
			E.pulse(g, 1.06, 0.6)
	if hazir:
		var al := UI.button("AL", "yesil", UI.DOKUNMA, UI.FS_ORTA, "", 120)
		al.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		al.pressed.connect(func() -> void:
			al.disabled = true
			profile.claim_daily())
		h.add_child(al)
	return box


# Görev / başarım satırı: ikon, ad (+açıklama), ilerleme çubuğu, ödül ve AL
func _hedef_satiri(icon_name: String, ad: String, aciklama: String, ilerleme: int, hedef: int, odul: int, alindi: bool, al: Callable, dar := false) -> Control:
	var bitti := ilerleme >= hedef
	var hazir := bitti and not alindi
	var box := E.row_box(UI.YESIL if hazir else (Color(0, 0, 0, 0)), Vector4(14, 10, 14, 10))
	box.custom_minimum_size.y = 96
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_M)
	box.add_child(h)
	# ikon kutusu
	var ik := PanelContainer.new()
	ik.custom_minimum_size = Vector2(72, 72)
	ik.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color(0, 0, 0, 0.45)
	ist.border_color = Color(UI.AMBER, 0.5) if not alindi else UI.CIZGI
	ist.set_border_width_all(2)
	ist.set_corner_radius_all(UI.R_ORTA)
	ik.add_theme_stylebox_override("panel", ist)
	var icn := UI.icon(icon_name, 56)
	icn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not bitti and icon_name == "basarim":
		icn.modulate = Color(0.55, 0.55, 0.55)
	ik.add_child(icn)
	h.add_child(ik)
	# ad + çubuk
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 4)
	var at := UI.title(ad, 22, UI.METIN if not alindi else UI.METIN_SOLUK)
	at.clip_text = true
	at.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(at)
	if aciklama != "":
		var al2 := UI.label(aciklama, UI.FS_KUCUK, UI.METIN_SOLUK)
		al2.clip_text = true
		tv.add_child(al2)
	var bar := UI.progress(float(mini(ilerleme, hedef)) / float(maxi(1, hedef)), 150 if dar else 300, 30, "%d / %d" % [mini(ilerleme, hedef), hedef])
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(bar)
	h.add_child(tv)
	# sağ: ödül / AL / alındı
	var sag := CenterContainer.new()
	sag.custom_minimum_size = Vector2(150 if dar else 176, UI.DOKUNMA)
	h.add_child(sag)
	if alindi:
		var ok := HBoxContainer.new()
		ok.add_theme_constant_override("separation", 6)
		ok.add_child(UI.title("✓", 30, UI.YESIL))
		var ol := UI.title("ALINDI", UI.FS_METIN, UI.METIN_SOLUK)
		ol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ok.add_child(ol)
		sag.add_child(ok)
		box.modulate = Color(1, 1, 1, 0.75)
	elif hazir:
		var yazi := tr("AL  +%d") % odul
		if dar and TranslationServer.get_locale().substr(0, 2) != "tr":
			yazi = "+%d" % odul  # dar kartta İngilizce "CLAIM +150" sığmıyor: yeşil düğme + elmas ikonu + miktar yeter
		var b := UI.button(yazi, "yesil", UI.DOKUNMA, 20 if dar else 22, "elmas", 150 if dar else 176)
		b.pressed.connect(func() -> void:
			b.disabled = true
			al.call())
		sag.add_child(b)
		E.pulse(b, 1.05, 0.55)
	else:
		var odulk := PanelContainer.new()
		var ost := StyleBoxFlat.new()
		ost.bg_color = Color(0, 0, 0, 0.45)
		ost.border_color = UI.CIZGI
		ost.set_border_width_all(2)
		ost.set_corner_radius_all(30)
		ost.content_margin_left = 14
		ost.content_margin_right = 18
		ost.content_margin_top = 6
		ost.content_margin_bottom = 6
		odulk.add_theme_stylebox_override("panel", ost)
		odulk.add_child(E.reward(odul, 32))
		sag.add_child(odulk)
	return box


# ---------------------------------------------------------------------
# BAŞARIMLAR
# ---------------------------------------------------------------------
func _build_basarimlar() -> void:
	var list: Array = account.eco.get("basarimlar", []).duplicate()
	if list.is_empty():
		_icerik.add_child(_bos("basarim", "Başarımlar yükleniyor…", "İnternete bağlanınca başarımların gelir."))
		return
	# alınabilir olanlar üstte, sonra devam edenler (ilerlemeye göre), en altta alınmışlar
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _sira(a) > _sira(b))
	var acik := 0
	for a in list:
		if bool(a.get("alindi", false)):
			acik += 1
	# toplam ilerleme: kaç başarım alındı
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_M)
	var ti := UI.icon("basarim", 44)
	ti.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ti)
	var top := UI.progress(float(acik) / float(maxi(1, list.size())), 300, 34, tr("%d / %d ALINDI") % [acik, list.size()])
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(top)
	_icerik.add_child(h)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", UI.B_S)
	g.add_theme_constant_override("v_separation", UI.B_S)
	_icerik.add_child(g)
	for a in list:
		var k := str(a.get("k", ""))
		var row := _hedef_satiri("basarim", str(a.get("ad", "")), str(a.get("aciklama", "")), int(a.get("ilerleme", 0)),
			int(a.get("hedef", 1)), int(a.get("odul", 0)), bool(a.get("alindi", false)), func() -> void: account.send({"t": "basarim_al", "k": k}), true)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(row)


func _sira(a: Dictionary) -> float:
	var hedef := maxi(1, int(a.get("hedef", 1)))
	var il := int(a.get("ilerleme", 0))
	if bool(a.get("alindi", false)):
		return -1.0
	if il >= hedef:
		return 2.0
	return float(il) / float(hedef)


# Liste gelene kadar: dönen gösterge ile "yükleniyor"; bağlantı yoksa nedeni yazar (gelince kendiliğinden dolar)
func _bos(icon_name: String, baslik: String, alt: String) -> Control:
	var bagli := bool(account.get("connected"))
	var v := E.durum(icon_name, baslik, "" if bagli else alt, true)
	v.custom_minimum_size.y = 300
	return v


func _close() -> void:
	E.outro(_kok, func() -> void:
		closed.emit()
		queue_free())
