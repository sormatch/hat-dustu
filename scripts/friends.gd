# Arkadaşlarım ekranı: @kullanıcıadı ile istek gönder, gelen istekleri kabul et, arkadaşlarını ara,
# çevrimiçi / odada durumlarını gör, lobiye davet et; oyuncuyu ŞİKAYET ET / ENGELLE.
# Tasarım takımı: scripts/ui.gd (docs/TASARIM.md) · avatar ve şikayet pencereleri: scripts/oyuncu_ui.gd
extends CanvasLayer

const UI := preload("res://scripts/ui.gd")
const OU := preload("res://scripts/oyuncu_ui.gd")
const Account := preload("res://scripts/account.gd")

var account: Node
var profile: Node
var net: Node

var _kok: Control
var _govde: Control
var _ara: LineEdit
var _liste: VBoxContainer
var _baslik_sayi: Label
var _kapaniyor := false


func _ready() -> void:
	layer = 16
	_kok = Control.new()
	_kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_kok)
	_kok.add_child(UI.background("bg_lobby", 0.62))

	# üst şerit: geri · başlık · çevrimiçi sayısı · senin adın
	var bar := UI.top_bar()
	_kok.add_child(bar)
	var br: HBoxContainer = bar.get_meta("row")
	var geri := UI.icon_button("geri", "ikincil", UI.DOKUNMA)
	geri.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	geri.pressed.connect(_kapat)
	br.add_child(geri)
	var t := UI.title("ARKADAŞLARIM", UI.FS_BUYUK, UI.METIN)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	br.add_child(t)
	_baslik_sayi = UI.title("", UI.FS_ORTA, UI.YESIL)
	_baslik_sayi.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_baslik_sayi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(_baslik_sayi)
	# senin @adın (dokununca kopyalanır)
	var ben := HBoxContainer.new()
	ben.name = "Ben"
	ben.custom_minimum_size = Vector2(0, UI.DOKUNMA)
	ben.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ben.mouse_filter = Control.MOUSE_FILTER_STOP
	ben.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and account.handle != "":
			DisplayServer.clipboard_set("@" + account.handle)
			UI.tik()
			UI.toast(tr("Kullanıcı adın kopyalandı: @%s") % account.handle, _kok, 2.0, "basari"))
	br.add_child(ben)

	_govde = Control.new()
	_govde.set_anchors_preset(Control.PRESET_FULL_RECT)
	_govde.offset_top = UI.UST_BAR_H + UI.B_S
	_govde.offset_left = UI.B_L
	_govde.offset_right = -UI.B_L
	_govde.offset_bottom = -UI.B_M
	_kok.add_child(_govde)
	UI.guvenli(_govde, UI.KENAR_PAYI - UI.B_L)  # çentik / yuvarlak köşe payı
	UI.geri_tusu(_kok, _kapat)  # Android geri tuşu / Esc

	account.list_changed.connect(_refresh)
	account.me_changed.connect(_refresh)
	# sunucunun cevabı: hata kırmızı, bilgi yeşil
	account.message.connect(func(m: String) -> void:
		UI.toast(m, _kok, 2.6, "hata" if bool(account.get("son_hata")) else "basari"))
	if account.has_signal("blocks_changed"):
		account.connect("blocks_changed", _refresh)
	account.send({"t": "liste"})
	account.send({"t": "engeller"})
	_refresh()
	_kok.modulate.a = 0.0
	_kok.create_tween().tween_property(_kok, "modulate:a", 1.0, 0.2)


func _kapat() -> void:
	if _kapaniyor:
		return
	_kapaniyor = true
	var tw := _kok.create_tween()
	tw.tween_property(_kok, "modulate:a", 0.0, 0.16)
	tw.tween_callback(queue_free)


func _engeller() -> Array:
	var e = account.get("engeller")
	return e if e is Array else []


# ---------------------------------------------------------------- parçalar

func _bolum(baslik: String, ikon: String, sayi := 0) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_XS)
	var ic := UI.icon(ikon, 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := UI.title(baslik, UI.FS_ORTA, UI.METIN)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	if sayi > 0:
		var b := UI.badge(sayi, 28)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	v.add_child(h)
	return v


func _edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = 17
	e.custom_minimum_size = Vector2(0, UI.DOKUNMA)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.style_edit(e, UI.FS_METIN + 1)
	return e


# Kişi satırı: avatar (çevrimiçiyse yeşil halka + nokta) + ad + @ad · durum + sağda düğmeler.
func _satir(f: Dictionary, durum: String, durum_renk: Color, dugmeler: Array, cevrimici := false) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UI.flat(Color(UI.YUZEY_2, 0.92), UI.CIZGI, UI.R_ORTA)
	st.set_border_width_all(1)
	st.border_width_bottom = 3
	st.shadow_size = 3
	st.content_margin_left = UI.B_S
	st.content_margin_right = UI.B_XS
	st.content_margin_top = UI.B_XS
	st.content_margin_bottom = UI.B_XS
	p.add_theme_stylebox_override("panel", st)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", UI.B_S)
	p.add_child(r)
	var ad := str(f.get("name", f.get("handle", "?")))
	var ak := Control.new()
	ak.custom_minimum_size = Vector2(56, 56)
	ak.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ak)
	ak.add_child(OU.avatar(ad, 56, UI.YESIL if cevrimici else Color(0, 0, 0, 0)))
	if not cevrimici and durum != "":
		ak.modulate = Color(0.7, 0.7, 0.7)
	if cevrimici:
		var nokta := Panel.new()
		var ns := StyleBoxFlat.new()
		ns.bg_color = UI.YESIL
		ns.border_color = UI.YUZEY_2
		ns.set_border_width_all(3)
		ns.set_corner_radius_all(10)
		nokta.add_theme_stylebox_override("panel", ns)
		nokta.position = Vector2(38, 38)
		nokta.size = Vector2(20, 20)
		ak.add_child(nokta)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", -2)
	r.add_child(tv)
	var nm := UI.title(ad, UI.FS_ORTA, UI.METIN)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(nm)
	var alt := HBoxContainer.new()
	alt.add_theme_constant_override("separation", UI.B_XS)
	tv.add_child(alt)
	alt.add_child(UI.label("@" + str(f.get("handle", "")), UI.FS_KUCUK, UI.METIN_SOLUK))
	if durum != "":
		alt.add_child(UI.title(durum, UI.FS_KUCUK, durum_renk))
	for b in dugmeler:
		(b as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(b)
	return p


func _btn(text: String, kind: String, on: Callable, w := 0.0, ikon := "") -> Button:
	var b := UI.button(text, kind, UI.BTN_H_KUCUK, UI.FS_METIN, ikon, w)
	b.pressed.connect(on)
	return b


func _ikon_btn(ikon: String, kind: String, on: Callable) -> Button:
	var b := UI.icon_button(ikon, kind, UI.DOKUNMA)
	b.pressed.connect(on)
	return b


# ---------------------------------------------------------------- ekran

func _refresh() -> void:
	if not is_inside_tree():
		return
	for ch in _govde.get_children():
		_govde.remove_child(ch)
		ch.queue_free()
	var ben: Control = _kok.find_child("Ben", true, false)
	for ch in ben.get_children():
		ben.remove_child(ch)
		ch.queue_free()
	_baslik_sayi.text = ""
	if account.handle == "":
		_hesapsiz()
		return
	# sağ üst: senin adın (dokununca kopyalanır)
	var chip := UI.counter("arkadas", "@" + account.handle, 40)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ben.add_child(chip)
	var n := int(account.online_count())
	_baslik_sayi.text = (tr("   ● %d çevrimiçi") % n) if n > 0 else ""

	var cols := HBoxContainer.new()
	cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.add_theme_constant_override("separation", UI.B_L)
	_govde.add_child(cols)

	# --- sol: arkadaş ekle + istekler
	var sp := UI.panel(Vector2(430, 0), UI.B_L)
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(sp)
	var ssc := ScrollContainer.new()
	ssc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(ssc)
	sp.add_child(ssc)
	var sol := VBoxContainer.new()
	sol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sol.add_theme_constant_override("separation", UI.B_L)
	ssc.add_child(sol)
	var ekle := _bolum("ARKADAŞ EKLE", "davet")
	sol.add_child(ekle)
	var e2 := _edit("Kullanıcı adı (ör. ali_34)")
	ekle.add_child(e2)
	var gonder := func() -> void:
		var h := Account.clean_handle(e2.text)
		if h == "":
			UI.toast("Önce arkadaşının kullanıcı adını yaz.", _kok, 2.2, "hata")
			return
		if h == account.handle:
			UI.toast("Kendine istek gönderemezsin.", _kok, 2.2, "hata")
			return
		var he := Account.handle_error(h)
		if he != "":
			UI.toast(he, _kok, 2.6, "hata")
			return
		account.send({"t": "istek", "handle": h})
		e2.text = ""
		e2.release_focus()
	e2.text_submitted.connect(func(_s: String) -> void: gonder.call())
	ekle.add_child(_btn("İSTEK GÖNDER", "ana", gonder, 0, "davet"))

	if account.incoming.size() > 0:
		var inc := _bolum("GELEN İSTEKLER", "arkadas", account.incoming.size())
		sol.add_child(inc)
		for f in account.incoming:
			var h: String = f.handle
			inc.add_child(_satir(f, "", UI.METIN_SOLUK, [
				_ikon_btn("onay", "yesil", func() -> void: account.send({"t": "kabul", "handle": h})),
				_ikon_btn("kapat", "ikincil", func() -> void: account.send({"t": "reddet", "handle": h})),
			], true))
	if account.outgoing.size() > 0:
		var out := _bolum("GÖNDERİLENLER", "davet")
		sol.add_child(out)
		for f in account.outgoing:
			var h: String = f.handle
			out.add_child(_satir(f, "BEKLİYOR", UI.AMBER, [
				_btn("İPTAL", "ikincil", func() -> void: account.send({"t": "reddet", "handle": h}), 124),
			]))

	# --- sağ: arama + arkadaş listesi + engellenenler
	var rp := UI.panel(Vector2.ZERO, UI.B_L)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(rp)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", UI.B_M)
	rp.add_child(rv)
	var ust := HBoxContainer.new()
	ust.add_theme_constant_override("separation", UI.B_M)
	rv.add_child(ust)
	var fb := _bolum("ARKADAŞLAR", "arkadas")
	fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ust.add_child(fb)
	var eski := _ara.text if is_instance_valid(_ara) else ""
	_ara = _edit("Ara…")
	_ara.text = eski
	_ara.custom_minimum_size.x = 260
	_ara.size_flags_horizontal = Control.SIZE_SHRINK_END
	_ara.text_changed.connect(func(_s: String) -> void: _doldur())
	ust.add_child(_ara)
	var rsc := ScrollContainer.new()
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI.touch_scroll(rsc)
	rv.add_child(rsc)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", UI.B_S)
	rsc.add_child(_liste)
	_doldur()

	# paneller aşağıdan kayarak gelir (yalnız ilk açılışta)
	if not has_meta("acildi"):
		set_meta("acildi", true)
		for i in 2:
			var c: Control = [sp, rp][i]
			c.modulate.a = 0.0
			var tw := c.create_tween()
			tw.tween_interval(0.05 + i * 0.07)
			tw.tween_property(c, "modulate:a", 1.0, 0.25)


func _hesapsiz() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_govde.add_child(cc)
	var p := UI.panel(Vector2(620, 0), UI.B_XL)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_L)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var ic := UI.icon("arkadas", UI.IKON_DEV)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	v.add_child(UI.title("KULLANICI ADINI SEÇ", UI.FS_BUYUK, UI.METIN, true))
	var l := UI.label("Arkadaşların seni kullanıcı adınla bulur. Karakterin ve elmasların da kaybolmaz.", UI.FS_METIN, UI.METIN_SOLUK, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 540
	v.add_child(l)
	var open := UI.button("HESAP AÇ / GİRİŞ YAP", "ana", UI.BTN_H, UI.FS_ORTA, "arkadas")
	open.pressed.connect(func() -> void:
		var g: CanvasLayer = load("res://scripts/giris.gd").new()
		g.account = account
		g.profile = profile
		add_child(g))
	v.add_child(open)
	if not account.connected:
		v.add_child(UI.label("Sunucuya bağlanılıyor…", UI.FS_KUCUK, UI.AMBER, true))


# Arkadaşın odasına katıl: bağlanınca lobiye geçilir (main.gd), hata olursa menüde yazar.
func _katil(kod: String) -> void:
	if net == null:
		return
	var ad: String = str(profile.player_name) if profile and str(profile.player_name) != "" else account.handle
	# önce topluluk kuralları (kabul edilmediyse) — scripts/giris.gd
	preload("res://scripts/giris.gd").kurallar_sonra(_kok, profile, func() -> void:
		net.join(kod, ad, false)
		UI.toast("Odaya bağlanılıyor…", null, 1.6, "bilgi")
		_kapat())


# Arkadaş listesini arama kutusuna göre doldurur (ekranın geri kalanı yeniden kurulmaz; klavye kapanmaz).
func _doldur() -> void:
	if not is_instance_valid(_liste):
		return
	for ch in _liste.get_children():
		_liste.remove_child(ch)
		ch.queue_free()
	var q := _ara.text.strip_edges().trim_prefix("@").to_lower()
	var in_room: bool = net != null and bool(net.get("connected"))
	var oda: String = str(net.get("room_code")) if in_room else ""
	var sayi := 0
	for f in account.friends:
		var h: String = f.handle
		var ad := str(f.get("name", h))
		if q != "" and not (h.to_lower().contains(q) or ad.to_lower().contains(q)):
			continue
		sayi += 1
		var online := bool(f.get("online", false))
		var odada := online and str(f.get("room", "")) != ""
		var macta := odada and bool(f.get("oyun", false))  # odasında maç başlamış
		var durum := "MAÇTA" if macta else ("ODADA" if odada else ("ÇEVRİMİÇİ" if online else "ÇEVRİMDIŞI"))
		var renk := UI.KIRMIZI.lightened(0.3) if macta else (UI.MAVI if odada else (UI.YESIL if online else UI.METIN_SOLUK))
		var btns := []
		if in_room and online and not macta and str(f.get("room", "")) != oda:
			# davet: sonucu sunucu söyler ("davet edildi" / "çevrimdışı"); düğme 5 sn dinlenir
			var db := UI.button("DAVET", "yesil", UI.BTN_H_KUCUK, UI.FS_METIN, "davet", 150)
			db.pressed.connect(func() -> void:
				account.send({"t": "davet", "handle": h, "oda": oda})
				db.disabled = true
				var db_wr: WeakRef = weakref(db)  # ekran 5 sn içinde kapanırsa lambda silinmiş düğümü yakalamasın
				get_tree().create_timer(5.0).timeout.connect(func() -> void:
					var d: Button = db_wr.get_ref()
					if d:
						d.disabled = false))
			btns.append(db)
		elif not in_room and odada:
			# arkadaşın bir odada: koduyla odasına katıl
			var oda_kodu := str(f.get("room", ""))
			# maçtaki arkadaşın odasına izleyici olarak girilir; maç bitince birlikte oynanır
			btns.append(_btn("İZLE" if macta else "KATIL", "ikincil" if macta else "yesil", func() -> void: _katil(oda_kodu), 150, "oyna"))
		var daha := UI.button("•••", "ikincil", UI.BTN_H_KUCUK, UI.FS_ORTA, "", 72)
		daha.pressed.connect(func() -> void:
			OU.menu(_kok, daha, [
				["ŞİKAYET ET", "sikayet", "tehlike", func() -> void: OU.sikayet(_kok, account, ad, h, oda)],
				["ENGELLE", "engelle", "ikincil", func() -> void:
					OU.engelle(_kok, account, ad, h, func() -> void: account.send({"t": "sil", "handle": h}))],
				["ARKADAŞLIKTAN ÇIKAR", "kapat", "ikincil", func() -> void:
					account.send({"t": "sil", "handle": h})
					UI.toast(tr("@%s arkadaş listenden çıkarıldı.") % h, _kok, 2.2, "bilgi")],
			], 400))
		btns.append(daha)
		_liste.add_child(_satir(f, durum, renk, btns, online))
	if account.friends.is_empty():
		var bos := VBoxContainer.new()
		bos.add_theme_constant_override("separation", UI.B_S)
		bos.alignment = BoxContainer.ALIGNMENT_CENTER
		bos.custom_minimum_size.y = 300
		var ic := UI.icon("arkadas", UI.IKON_DEV)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.modulate = Color(1, 1, 1, 0.55)
		bos.add_child(ic)
		bos.add_child(UI.title("HENÜZ ARKADAŞIN YOK", UI.FS_ORTA, UI.METIN, true))
		bos.add_child(UI.label("Soldan kullanıcı adını yazıp istek gönder.", UI.FS_METIN, UI.METIN_SOLUK, true))
		_liste.add_child(bos)
	elif sayi == 0:
		_liste.add_child(UI.label(tr("“%s” bulunamadı.") % _ara.text.strip_edges(), UI.FS_METIN, UI.METIN_SOLUK, true))
	# engellenenler (en altta; kaldırılabilir)
	var eng := _engeller()
	if not eng.is_empty() and q == "":
		var eb := _bolum("ENGELLENENLER", "engelle")
		_liste.add_child(eb)
		for x in eng:
			var h2 := str(x)
			eb.add_child(_satir({"handle": h2, "name": h2}, "ENGELLİ", UI.KIRMIZI, [
				_btn("KALDIR", "ikincil", func() -> void: account.send({"t": "engel_kaldir", "handle": h2}), 130),
			]))
