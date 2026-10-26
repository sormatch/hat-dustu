# Seviye yolu (ücretsiz ödül şeridi, Brawl Stars "Trophy Road" gibi): her seviyede bir ödül — elmas, kasa ya da eşya.
# Seviye maç oynayarak (XP) yükselir; açılan ödül "AL" ile alınır. Ödüller sunucuda verilir (server/src/market.js yol_al).
# Kasa ödülü mağazadaki Kasa sekmesinde "ÜCRETSİZ" olarak açılır.
extends CanvasLayer

signal closed

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const Catalog := preload("res://scripts/catalog.gd")
const ThumbsScript := preload("res://scripts/thumbs.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const Fx := preload("res://scripts/store_fx.gd")
const Magaza := preload("res://scripts/character.gd")

const NODE_W := 172.0
const CARD_H := 208.0

var account: Node
var profile: Node
var _kok: Control
var _scroll: ScrollContainer
var _row: HBoxContainer
var _thumbs: Node
var _lvl_shield: Control
var _lvl_label: Label
var _xp_bar: Control
var _hak_btn: Button
var _sag: HBoxContainer
var _gem_label: Label
var _ilk := true
var _bekle := false  # ödül alınırken yeniden kurma


func _ready() -> void:
	layer = 21
	_thumbs = ThumbsScript.new()
	add_child(_thumbs)
	var s := E.screen("SEVİYE YOLU", "xp", "bg_menu", 0.72)
	_kok = s.kok
	add_child(_kok)
	(s.geri as Button).pressed.connect(_close)
	_sag = s.bar_sag
	var gw := Magaza.gem_widget(func() -> void: Magaza.open_gem_store(self))
	_gem_label = gw.get_meta("label")
	_sag.add_child(gw)
	var govde: Control = s.govde
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + k, UI.B_L)
	mc.add_theme_constant_override("margin_top", UI.B_S)
	mc.add_theme_constant_override("margin_bottom", UI.B_L)
	govde.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_M)
	mc.add_child(v)
	# üst: seviye kalkanı, XP çubuğu, açıklama
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", UI.B_M)
	v.add_child(top)
	_lvl_shield = E.level_shield(1, 76)
	_lvl_shield.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_lvl_shield)
	var lv := VBoxContainer.new()
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_theme_constant_override("separation", 4)
	top.add_child(lv)
	_lvl_label = UI.title("SEVİYE 1", UI.FS_ORTA, UI.METIN)
	lv.add_child(_lvl_label)
	_xp_bar = UI.progress(0.0, 360, 30, "")
	lv.add_child(_xp_bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var ipucu := UI.label("Maç oynadıkça seviye atla, her seviyede ödül al", UI.FS_KUCUK, UI.METIN_SOLUK)
	ipucu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ipucu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ipucu.custom_minimum_size.x = 300
	ipucu.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(ipucu)
	# yol: yana kaydırılan ödül şeridi
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	UI.touch_scroll(_scroll)
	v.add_child(_scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 0)
	_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_row)
	if account and account.has_signal("economy_changed"):
		account.economy_changed.connect(_on_eco)
	_build()
	E.intro(_kok, govde)


func _process(_delta: float) -> void:
	if _gem_label and profile:
		_gem_label.text = E.sayi(int(profile.gems))


func _on_eco() -> void:
	if not _bekle:
		_build()


func _eco() -> Dictionary:
	return account.eco if account else {}


func _build() -> void:
	var eco := _eco()
	var sv := int(eco.get("seviye", 1))
	var ic := int(eco.get("xp_ic", 0))
	var ger := maxi(1, int(eco.get("xp_gerek", 100)))
	_lvl_label.text = tr("SEVİYE %d") % sv
	(_lvl_shield.get_meta("label") as Label).text = str(sv)
	_xp_bar.value = float(ic) / float(ger)
	_xp_bar.text = tr("%d / %d XP") % [ic, ger]
	# ücretsiz kasa hakkı varsa: üstte mağazanın Kasa sekmesine götüren düğme
	var hak: Dictionary = eco.get("kasa_hak", {})
	var hn := int(hak.get("tahta", 0)) + int(hak.get("altin", 0))
	if is_instance_valid(_hak_btn):
		_hak_btn.queue_free()
	if hn > 0:
		_hak_btn = UI.button(tr("KASA ×%d") % hn, "yesil", UI.DOKUNMA, UI.FS_METIN, "kasa", 190)
		_hak_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_hak_btn.pressed.connect(_kasaya_git)
		E.pulse(_hak_btn, 1.04, 0.6)
		_sag.add_child(_hak_btn)
		_sag.move_child(_hak_btn, 0)
	var sx := _scroll.scroll_horizontal
	for c in _row.get_children():
		c.queue_free()
	var yol: Array = eco.get("yol", [])
	if yol.is_empty():
		# ödüller sunucudan gelir: gelene kadar dönen gösterge (bağlantı yoksa nedeni de yazar)
		var bagli := bool(account.get("connected"))
		var v := E.durum("xp", "Seviye yolu yükleniyor…", "" if bagli else "İnternete bağlanınca ödüllerin görünür.", true)
		v.custom_minimum_size = Vector2(maxf(_scroll.size.x, 900.0), 320)
		_row.add_child(v)
		return
	var hedef := 0
	for i in yol.size():
		var o: Dictionary = yol[i]
		_row.add_child(_node(o, sv))
		if int(o.s) <= sv and not bool(o.alindi) and hedef == 0:
			hedef = i
		if int(o.s) == sv + 1 and hedef == 0:
			hedef = i
	if _ilk:
		_ilk = false
		_kaydir.call_deferred(hedef)
	else:
		_geri_kaydir.call_deferred(sx)


func _kaydir(i: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_horizontal = int(maxf(0.0, i * NODE_W - (_scroll.size.x - NODE_W) / 2.0))


func _geri_kaydir(sx: int) -> void:
	await get_tree().process_frame
	_scroll.scroll_horizontal = sx


# Tek bir seviye: üstte iz çizgisi + seviye kalkanı, ortada ödül kartı, altta AL / ALINDI / kilit.
func _node(o: Dictionary, sv: int) -> Control:
	var s := int(o.s)
	var acik := s <= sv
	var alindi := bool(o.alindi)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = NODE_W
	v.add_theme_constant_override("separation", UI.B_S)
	# iz: geçilen seviyeler amber, ilerisi koyu; şimdiki seviyede ışık
	var track := Control.new()
	track.custom_minimum_size.y = 78
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(track)
	var line := ColorRect.new()
	line.color = UI.AMBER if acik else UI.CIZGI
	if s == sv + 1:
		line.color = UI.AMBER.lerp(UI.CIZGI, 0.6)
	line.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	line.anchor_right = 1.0
	line.offset_top = -5
	line.offset_bottom = 5
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(line)
	if s == sv:
		var gl := E.glow(UI.AMBER, 0.55)
		gl.set_anchors_preset(Control.PRESET_CENTER)
		gl.offset_left = -70
		gl.offset_right = 70
		gl.offset_top = -60
		gl.offset_bottom = 60
		track.add_child(gl)
	var sh := E.level_shield(s, 66)
	sh.set_anchors_preset(Control.PRESET_CENTER)
	sh.offset_left = -33
	sh.offset_right = 33
	sh.offset_top = -33
	sh.offset_bottom = 33
	if not acik:
		sh.modulate = Color(0.6, 0.6, 0.62)
	track.add_child(sh)
	# ödül kartı
	var cc := CenterContainer.new()
	v.add_child(cc)
	var card := _reward_card(o)
	cc.add_child(card)
	if not acik:
		card.modulate = Color(0.62, 0.62, 0.66)
	elif alindi:
		card.modulate = Color(0.75, 0.75, 0.75)
	# alt: AL / ALINDI / kilit
	var alt := CenterContainer.new()
	alt.custom_minimum_size.y = UI.DOKUNMA
	v.add_child(alt)
	if alindi:
		var p := E.pill("ALINDI", UI.YESIL, UI.FS_KUCUK + 2)
		alt.add_child(p)
	elif acik:
		var b := UI.button("AL", "yesil", UI.DOKUNMA, UI.FS_ORTA, "", 140)
		b.pressed.connect(_al.bind(s, b, card))
		E.pulse(b, 1.05, 0.55)
		alt.add_child(b)
	else:
		var k := UI.icon("kilit", 36)
		k.modulate = Color(1, 1, 1, 0.7)
		alt.add_child(k)
	return v


# Ödül kartı: elmas yığını / kasa / eşya resmi ve altında miktar ya da ad.
func _reward_card(o: Dictionary) -> Control:
	var tur := str(o.get("tur", ""))
	var rk := ""
	if tur == "kasa":
		rk = "efsane" if str(o.kasa) == "altin" else "siradan"
	elif tur == "esya":
		rk = UI.rarity_key(str(Catalog.rarity(Catalog.price(str(o.kat), str(o.id)))[1]))
	else:
		rk = "nadir"
	var fr := UI.card_frame(rk, Vector2(NODE_W - 16, CARD_H))
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.add_child(v)
	var pic := Control.new()
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.clip_contents = true
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var gl := E.glow(UI.rarity_color(rk), 0.3)
	gl.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.add_child(gl)
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.offset_left = 8
	t.offset_right = -8
	t.offset_top = 6
	t.offset_bottom = -2
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.add_child(t)
	var yazi := ""
	var renk := UI.METIN
	match tur:
		"elmas":
			t.texture = UI.texture("gem_pile", 256)
			yazi = "+" + E.sayi(int(o.n))
			renk = UI.ELMAS
		"kasa":
			var gold := str(o.kasa) == "altin"
			t.texture = UI.texture(Magaza.CHEST_ART[1 if gold else 0][0], 256)
			yazi = tr("ALTIN KASA") if gold else tr("TAHTA KASA")
			renk = UI.NADIRLIK.efsane if gold else UI.METIN
		"esya":
			var cat := str(o.kat)
			var id := str(o.id)
			if cat == "dovme":
				t.texture = BodyScript.ink_texture(id)
			else:
				t.material = Magaza._fade_material()
				_thumbs.request(profile.look, cat, id, t)
			if cat == "hareket":
				var em := UI.icon("emote", 26)
				em.position = Vector2(6, 6)
				pic.add_child(em)
			yazi = Catalog.item_name(cat, id)
			renk = UI.rarity_color(rk).lightened(0.3)
	var l := UI.title(yazi, {"elmas": UI.FS_ORTA, "kasa": UI.FS_KUCUK + 1}.get(tur, UI.FS_METIN), renk, true)
	# uzun ad (WOODEN CRATE, eşya adları) kesilmesin: iki satıra iner, yine sığmazsa küçülür
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size = Vector2(NODE_W - 16 - 46, 34)
	l.add_theme_constant_override("line_spacing", -4)
	var en_uzun := ""
	for k in yazi.split(" "):
		if k.length() > en_uzun.length():
			en_uzun = k
	var olc := UI.title(en_uzun, l.get_theme_font_size("font_size"))
	UI.sigdir(olc, NODE_W - 16 - 46)  # tek kelime bile sığmıyorsa hepsi küçülür
	var fs_son := olc.get_theme_font_size("font_size")
	l.add_theme_font_size_override("font_size", fs_son)
	olc.free()
	if UI.TITLE_FONT.get_string_size(yazi, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_son).x > NODE_W - 16 - 50:
		l.custom_minimum_size.y = fs_son * 2 + 6  # iki satır
	v.add_child(l)
	return fr


func _al(s: int, b: Button, card: Control) -> void:
	b.disabled = true
	UI.set_button_text(b, "...")
	_bekle = true
	var res: Array = await Magaza.islem_bekle(self, account, {"t": "yol_al", "s": s}, "yol_alindi")
	_bekle = false
	if not is_instance_valid(b):
		return
	if not bool(res[0]):
		_ses("hata", -4.0)
		UI.toast(str((res[1] as Dictionary).get("m", "")), null, 2.4, "hata")
		_build()
		return
	var o: Dictionary = (res[1] as Dictionary).get("odul", {})
	_ses("odul", -3.0)
	_ses("kasa/elmas", -6.0)
	var at := card.get_global_rect().get_center()
	Fx.confetti(_kok, at, [UI.AMBER, UI.ELMAS, "#5be37d", "#ffffff"])
	match str(o.get("tur", "")):
		"elmas":
			UI.toast(tr("+%d elmas") % int(o.n), null, 2.0, "basari")
		"kasa":
			UI.toast("Ücretsiz kasa! Mağaza > Kasa'dan aç", null, 2.6, "basari")
		"esya":
			if bool(o.get("kopya", false)):
				UI.toast(tr("Zaten sendeydi: +%d elmas") % int(o.get("n", 0)), null, 2.4, "basari")
			else:
				var pic := TextureRect.new()
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				var cat := str(o.kat)
				var id := str(o.id)
				if cat == "dovme":
					pic.texture = BodyScript.ink_texture(id)
				else:
					_thumbs.request(profile.look, cat, id, pic)
				var tier: Array = Catalog.rarity(Catalog.price(cat, id))
				Fx.reward_popup(self, "YENİ EŞYA!", Catalog.item_name(cat, id), str(tier[1]), UI.rarity_color(UI.rarity_key(str(tier[1]))), pic)
	_build()


func _ses(n: String, vol := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://assets/ses/%s.ogg" % n)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# Ücretsiz kasa: mağazanın Kasa sekmesi açılır (bu ekran kapanır).
func _kasaya_git() -> void:
	var m = get_tree().current_scene
	_close()
	if m and m.has_method("open_character"):
		var ch: CanvasLayer = m.open_character()
		ch.set("_cat", "sandik")
		ch.call_deferred("_refresh")


func _close() -> void:
	E.outro(_kok, func() -> void:
		closed.emit()
		queue_free())
