# Oyuncu arayüz parçaları (bekleme salonu, telefon ve Arkadaşlarım ekranları ortak kullanır):
# avatar (baş harf), bağlam menüsü (kart menüsü), uzun basma, ŞİKAYET ET ve ENGELLE pencereleri.
# Kullanım: const OU := preload("res://scripts/oyuncu_ui.gd")
extends RefCounted

const UI := preload("res://scripts/ui.gd")
const Dil := preload("res://scripts/dil.gd")

# sunucunun bildiği nedenler (server/src/accounts.js "sikayet")
const NEDENLER := [["kufur", "KÜFÜR"], ["taciz", "TACİZ"], ["hile", "HİLE"], ["uygunsuz_ad", "UYGUNSUZ AD"], ["diger", "DİĞER"]]
# avatar zemin renkleri: sanat yönüne uygun toprak tonları (ada göre sabit seçilir)
const AVATAR_RENK := ["#c8892b", "#6f8f3a", "#3f7fa8", "#a3473b", "#7a5aa6", "#2f8f7f", "#b0673a", "#8a8f2f"]


static func renk(ad: String) -> Color:
	var h := 0
	for c in ad.to_lower():
		h = (h * 31 + c.unicode_at(0)) % 9973
	return Color(AVATAR_RENK[h % AVATAR_RENK.size()])


static func bas_harf(ad: String) -> String:
	var s := ad.strip_edges().trim_prefix("@")
	return s.substr(0, 1).to_upper() if s != "" else "?"


# Yuvarlak avatar: renkli zemin + baş harf. halka: kenar rengi (hazır = yeşil, sen = amber...).
static func avatar(ad: String, px := 64.0, halka := Color(0, 0, 0, 0)) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(px, px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	var c := renk(ad)
	st.bg_color = c
	st.set_corner_radius_all(int(px / 2.0))
	st.border_color = halka if halka.a > 0.0 else c.darkened(0.45)
	st.set_border_width_all(maxi(3, int(px * 0.06)))
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 4
	st.shadow_offset = Vector2(0, 2)
	st.anti_aliasing = true
	p.add_theme_stylebox_override("panel", st)
	# üstten ışık: yarım saydam parlama
	var parla := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(1, 1, 1, 0.13)
	ps.set_corner_radius_all(int(px / 2.0))
	parla.add_theme_stylebox_override("panel", ps)
	parla.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parla.set_anchors_preset(Control.PRESET_TOP_WIDE)
	parla.offset_left = px * 0.14
	parla.offset_right = -px * 0.14
	parla.offset_top = px * 0.07
	parla.offset_bottom = px * 0.46
	p.add_child(parla)
	var l := UI.title(bas_harf(ad), int(px * 0.5), Color.WHITE, true)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.set_meta("style", st)
	return p


# Avatar halkasının rengini sonradan değiştirir.
static func avatar_halka(p: Panel, c: Color) -> void:
	var st: StyleBoxFlat = p.get_meta("style")
	st.border_color = c


# Uzun basma (0.45 sn): cb çağrılır; kısa dokunuş düğmenin normal "pressed" sinyali olarak kalır.
# Uzun basmadan sonra gelen "pressed" yutulsun diye düğmeye "uzun" meta'sı yazılır (pressed içinde bakılır).
static func uzun_bas(b: BaseButton, cb: Callable) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 0.45
	b.add_child(t)
	b.button_down.connect(func() -> void:
		b.set_meta("uzun", false)
		t.start())
	b.button_up.connect(func() -> void: t.stop())
	t.timeout.connect(func() -> void:
		b.set_meta("uzun", true)
		Input.vibrate_handheld(40)
		cb.call())


# Küçük bağlam menüsü: hedef öğenin altında (sığmazsa üstünde) açılır, dışarı dokununca kapanır.
# items: [[yazı, ikon, tür, Callable], ...]
static func menu(host: Node, hedef: Control, items: Array, w := 280.0) -> Control:
	var kok := Control.new()
	kok.set_anchors_preset(Control.PRESET_FULL_RECT)
	kok.mouse_filter = Control.MOUSE_FILTER_STOP
	var kapat := func() -> void:
		if not is_instance_valid(kok) or kok.has_meta("kapaniyor"):
			return
		kok.set_meta("kapaniyor", true)
		var tw := kok.create_tween()
		tw.tween_property(kok, "modulate:a", 0.0, 0.12)
		tw.tween_callback(kok.queue_free)
	kok.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			kapat.call())
	var p := PanelContainer.new()
	var st := UI.flat(Color(UI.YUZEY, 0.97), UI.CIZGI, UI.R_ORTA)
	st.set_border_width_all(2)
	st.border_color = Color(UI.AMBER, 0.55)
	st.content_margin_left = UI.B_S
	st.content_margin_right = UI.B_S
	st.content_margin_top = UI.B_S
	st.content_margin_bottom = UI.B_S
	st.shadow_size = 18
	st.shadow_color = Color(0, 0, 0, 0.6)
	p.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_XS)
	p.add_child(v)
	for it in items:
		var b := UI.button(str(it[0]), str(it[2]), UI.BTN_H_KUCUK, UI.FS_METIN, str(it[1]), w - UI.B_S * 2)
		var cb: Callable = it[3]
		b.pressed.connect(func() -> void:
			kapat.call()
			cb.call())
		v.add_child(b)
	kok.add_child(p)
	host.add_child(kok)
	# konum: hedefin altı, ekrana sığdır
	var r := hedef.get_global_rect()
	var vs := kok.get_viewport_rect().size
	var h := items.size() * (UI.BTN_H_KUCUK + UI.B_XS) + UI.B_S * 2
	var pos := Vector2(r.get_center().x - w / 2.0, r.end.y + 6)
	if pos.y + h > vs.y - 8:
		pos.y = r.position.y - h - 6
	pos.x = clampf(pos.x, 8, vs.x - w - 8)
	pos.y = clampf(pos.y, 8, vs.y - h - 8)
	p.position = pos
	p.custom_minimum_size.x = w
	p.pivot_offset = Vector2(w / 2.0, 0)
	p.scale = Vector2(0.9, 0.9)
	kok.modulate.a = 0.0
	var tw := kok.create_tween().set_parallel(true)
	tw.tween_property(kok, "modulate:a", 1.0, 0.12)
	tw.tween_property(p, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return kok


static func _kisi_satiri(ad: String, handle: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", UI.B_M)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_child(avatar(ad, 64))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(UI.title(ad, UI.FS_ORTA + 2, UI.METIN))
	if handle != "":
		tv.add_child(UI.label("@" + handle, UI.FS_KUCUK, UI.METIN_SOLUK))
	r.add_child(tv)
	return r


# ŞİKAYET ET penceresi: neden seç (KÜFÜR / TACİZ / HİLE / UYGUNSUZ AD / DİĞER), istersen engelle, gönder.
# hedef: oyundaki ad; handle: @kullanıcıadı (bilinmiyorsa ""); oda: oda kodu.
# oda_gonder: maçtaki oyuncu için oda bağlantısına gönderir (sunucu oda içi numarayı hesaba çevirir):
#   oda_gonder.call({"t": "sikayet", "neden": ..}) ve "AYRICA ENGELLE" için oda_gonder.call({"t": "engelle"})
static func sikayet(host: Node, account: Node, hedef: String, handle := "", oda := "", oda_gonder := Callable()) -> Control:
	var m := UI.modal("ŞİKAYET ET", 660)
	var sec := {"neden": "", "engel": false}
	m.body.add_child(_kisi_satiri(hedef, handle))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", UI.B_S)
	g.add_theme_constant_override("v_separation", UI.B_S)
	m.body.add_child(g)
	var gonder := UI.button("GÖNDER", "tehlike", UI.BTN_H, UI.FS_ORTA, "sikayet", 230)
	gonder.disabled = true
	var dugmeler: Array[Button] = []
	for n in NEDENLER:
		var b := UI.button(str(n[1]), "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN, "", 192)
		var key: String = n[0]
		b.pressed.connect(func() -> void:
			sec.neden = key
			for d in dugmeler:
				UI.set_button_kind(d, "ana" if d == b else "ikincil")
			gonder.disabled = false)
		dugmeler.append(b)
		g.add_child(b)
	if handle != "" or oda_gonder.is_valid():
		var eb := UI.button("AYRICA ENGELLE", "ikincil", UI.BTN_H_KUCUK, UI.FS_METIN, "engelle")
		eb.pressed.connect(func() -> void:
			sec.engel = not sec.engel
			UI.set_button_kind(eb, "tehlike" if sec.engel else "ikincil")
			UI.set_button_text(eb, "ENGELLENECEK" if sec.engel else "AYRICA ENGELLE"))
		m.body.add_child(eb)
	var alt := HBoxContainer.new()
	alt.alignment = BoxContainer.ALIGNMENT_CENTER
	alt.add_theme_constant_override("separation", UI.B_M)
	var vaz := UI.button("VAZGEÇ", "ikincil", UI.BTN_H, UI.FS_ORTA, "", 200)
	vaz.pressed.connect(m.close)
	alt.add_child(vaz)
	alt.add_child(gonder)
	m.body.add_child(alt)
	gonder.pressed.connect(func() -> void:
		if oda_gonder.is_valid():
			# maçtaki oyuncu: oda sunucusu cevabı (bilgi/hata) oyunun bildirim alanında görünür
			oda_gonder.call({"t": "sikayet", "neden": sec.neden})
			if sec.engel:
				oda_gonder.call({"t": "engelle"})
			UI.toast("Şikayetin iletildi. Teşekkürler.", null, 2.4, "basari")
			m.close()
			return
		if account == null or not bool(account.get("connected")):
			UI.toast("Sunucuya bağlı değilsin, sonra tekrar dene.", null, 2.4, "hata")
			return
		account.send({"t": "sikayet", "hedef": handle if handle != "" else hedef, "oda": oda, "neden": sec.neden})
		if sec.engel and handle != "":
			account.send({"t": "engelle", "handle": handle})
		UI.toast("Şikayetin iletildi. Teşekkürler.", null, 2.4, "basari")
		m.close())
	host.add_child(m)
	return m


# ENGELLE onayı: engellenenin sesi duyulmaz, daveti gelmez. bitti: onaylanınca çağrılır.
# oda_gonder: maçtaki oyuncu (kullanıcı adı bilinmez): oda_gonder.call({"t": "engelle"}) ile oda sunucusuna gider.
static func engelle(host: Node, account: Node, ad: String, handle: String, bitti := Callable(), oda_gonder := Callable()) -> Control:
	var m := UI.modal("ENGELLE", 600)
	m.body.add_child(_kisi_satiri(ad, handle))
	m.body.add_child(UI.label("Sesini duymazsın, sana istek ve davet gönderemez.", UI.FS_METIN, UI.METIN_SOLUK, true))
	var alt := HBoxContainer.new()
	alt.alignment = BoxContainer.ALIGNMENT_CENTER
	alt.add_theme_constant_override("separation", UI.B_M)
	var vaz := UI.button("VAZGEÇ", "ikincil", UI.BTN_H, UI.FS_ORTA, "", 200)
	vaz.pressed.connect(m.close)
	alt.add_child(vaz)
	var ok := UI.button("ENGELLE", "tehlike", UI.BTN_H, UI.FS_ORTA, "engelle", 230)
	ok.pressed.connect(func() -> void:
		if oda_gonder.is_valid():
			oda_gonder.call({"t": "engelle"})  # sunucunun "X engellendi" bilgisi bildirim olarak gelir
			if bitti.is_valid():
				bitti.call()
			m.close()
			return
		if account == null or not bool(account.get("connected")):
			UI.toast("Sunucuya bağlı değilsin, sonra tekrar dene.", null, 2.4, "hata")
			return
		account.send({"t": "engelle", "handle": handle})
		UI.toast(Dil.t("@%s engellendi.") % handle, null, 2.2, "basari")
		if bitti.is_valid():
			bitti.call()
		m.close())
	alt.add_child(ok)
	m.body.add_child(alt)
	host.add_child(m)
	return m
