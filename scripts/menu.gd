# Ana menü. Üstte seviye/XP, elmas (+ elmas mağazası) ve ayarlar; solda giydirilmiş karakterin (envanter kartı),
# sağda arkadaşların, ortada logo, büyük OYNA ve MAĞAZA / GÖREVLER / BAŞARIMLAR / LİDERLİK kutucukları.
# OYNA -> "Oyuna başla" alt ekranı: HIZLI OYUN / ARKADAŞLARINLA ODA KUR / KOD İLE KATIL / TEK BAŞINA DENE.
extends CanvasLayer

signal solo
signal open_character
signal open_settings
signal open_friends
signal open_inventory

const UI := preload("res://scripts/ui.gd")
const E := preload("res://scripts/ekran.gd")
const ModelScript := preload("res://scripts/model_body.gd")
const Catalog := preload("res://scripts/catalog.gd")
const GorevlerScript := preload("res://scripts/gorevler.gd")
const LiderlikScript := preload("res://scripts/liderlik.gd")
const SeviyeYoluScript := preload("res://scripts/seviye_yolu.gd")
const ThumbsScript := preload("res://scripts/thumbs.gd")
const Fx := preload("res://scripts/store_fx.gd")
const Dil := preload("res://scripts/dil.gd")
const Giris := preload("res://scripts/giris.gd")  # topluluk kuralları onayı
const OdalarScript := preload("res://scripts/odalar.gd")  # ODALAR ekranı + ODA KUR penceresi

const BAR_H := 80        # üst çubuk (içindeki düğmeler 64 px dokunma alanı)
const ORTA_W := 560.0    # orta sütun genişliği
const SOL_W := 290.0     # envanter kartı
const SAG_W := 312.0     # arkadaşlar paneli
const KENAR := 16.0
const LOGO_H := 200.0    # logonun yüksekliği (uzun ekranda büyür)
const TILE_H := 112.0    # MAĞAZA / GÖREVLER / BAŞARIMLAR / LİDERLİK kutucukları
const MESGUL_SURE := 20.0  # "bağlanılıyor…" bu kadar sürerse düğmeler yeniden açılır

var net: Node
var profile: Node
var account: Node

var root: Control
var col: VBoxContainer
var logo: TextureRect
var main_box: VBoxContainer
var play_box: Control  # ODA KUR + KODLA KATIL satırı (test pozu "oyna": kod penceresini açar)
var code_edit: LineEdit
var status: Label
var quick_btn: Button
var _create_btn: Button
var _join_btn: Button
var _rooms_btn: Button  # ODALAR (herkese açık odalar listesi)
var _odalar: CanvasLayer
var _solo_btn: Button
var _durum_kutu: PanelContainer
var _durum_don: Control
var _durum_ikon: Control
var _kod_modal: Control
var _son_kod := ""  # son kodla katılma denemesi (hata olursa kod penceresi yeniden açılır)
var _cikis_modal: Control
var _mesgul := 0.0  # > 0: bağlanılıyor (düğmeler kapalı), saniye
var _gunluk_hale: Control
var _ortam_t := 0.0
var _bg_resim: Control
var _isiklar: Array = []  # [TextureRect, görseldeki konum (1920x1080), temel parlaklık]
var _floresan: TextureRect
var _bg_golge: ColorRect
var gorev_tile: Button
var basarim_tile: Button
var _gorev_rozet: PanelContainer
var _basarim_rozet: PanelContainer
var _yol_rozet: PanelContainer  # seviye yolunda alınabilir ödül sayısı (seviye plakası)
var _magaza_rozet: PanelContainer  # istek listesindeki eşya bugün vitrinde
# üst çubuk
var gems_label: Label
var _lvl_shield: Control
var _lvl_label: Label
var _xp_bar: Control
# envanter kartı
var _name_label: Label
var _handle_label: Label
var _rarity_pill: PanelContainer
var _preview: Node3D
var _turn: Node3D
# arkadaşlar
var friends_list: VBoxContainer
var _online_label: Label
var _req_box: Control
var _req_badge: PanelContainer
var _toast: Control
var _box_now: Control
var _sol_kart: Control
var _sag_kart: Control


func _ready() -> void:
	layer = 10
	# arka plan: sisli koridor görseli; çok yavaş yaklaşıp kayar (paralaks), floresan titrer, lambalar
	# nefes alır, yerde sis akar, havada toz. Hepsi 2D ve ucuz (menüde 3D çizim kapalı).
	_ortam_kur()
	# arka plan opak: menü açıkken arkadaki 3D dünyayı çizme (telefonda pil ve ısı)
	visibility_changed.connect(_dunya_ciz)
	_dunya_ciz.call_deferred()
	# menü gizlenince (odaya girildi) bekleme yazısı silinir, düğmeler yeniden açılır
	visibility_changed.connect(func() -> void:
		if not visible and status:
			_set_status(""))

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_center()
	_build_char_card()
	_build_friends_card()
	_build_top_bar()
	# Android geri tuşu oyunu doğrudan kapatmasın (Godot varsayılanı); her ekran kendi geri tuşunu dinler
	# (UI.geri_tusu). Ana menüde: "Oyundan çıkılsın mı?" onayı.
	get_tree().quit_on_go_back = false
	UI.geri_tusu(self, _cikis_onayi)
	root.resized.connect(_yerlesim)
	_yerlesim()

	account.list_changed.connect(_refresh_friends)
	account.me_changed.connect(refresh_profile)
	account.economy_changed.connect(refresh_profile)
	account.invited.connect(_on_invited)
	account.reward.connect(_on_reward)
	if account.has_signal("gift_received"):
		account.gift_received.connect(_on_gift)
	net.welcomed.connect(func() -> void: account.set_room(net.room_code, net.in_game))
	# maç başladı: arkadaşlar "MAÇTA" görsün (davet gelmez, KATIL yerine İZLE)
	net.started.connect(func() -> void: account.set_room(net.room_code, true))
	# maç bitti (maç sonu ekranı): oda yeniden bekleme salonuna döner (TEKRAR OYNA), arkadaşlar ODADA görür
	# ve katılabilir; ÇIKIŞ odadan çıkarır (main.gd leave_game: durum "çevrimiçi").
	net.game_over.connect(func(_d: Dictionary) -> void: account.set_room(net.room_code, false))
	# odaya bağlanılamadı ya da bağlantı koptu: arkadaşlar artık "odada" görmesin
	net.failed.connect(func(_m: String) -> void:
		if not net.connected:
			account.set_room(""))
	profile.changed.connect(refresh_profile)
	refresh_profile()
	_refresh_friends()
	_intro()
	for a in OS.get_cmdline_user_args():
		if a == "kurallar=1":
			get_tree().create_timer(1.0).timeout.connect(func() -> void: Giris.kurallar_onayi(self, profile))  # test pozu
		elif a == "odalar=1":
			get_tree().create_timer(1.0).timeout.connect(_open_odalar)  # test pozu: ODALAR (odalar_demo=dolu|bos)
		elif a == "oda_kur=1":
			get_tree().create_timer(1.0).timeout.connect(_oda_kur_penceresi)  # test pozu: ODA KUR (oda_kur_gor=herkes)


# ---------------------------------------------------------------------
# ÜST ÇUBUK: seviye + XP (solda), elmas + "+" (elmas mağazası) + ayarlar (sağda)
# ---------------------------------------------------------------------
func _build_top_bar() -> void:
	var bar := UI.top_bar(BAR_H)
	root.add_child(bar)
	var row: HBoxContainer = bar.get_meta("row")
	# seviye plakası (dokununca başarımlar)
	var lvl := Button.new()
	lvl.focus_mode = Control.FOCUS_NONE
	lvl.custom_minimum_size = Vector2(300, UI.DOKUNMA)
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bos := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus"]:
		lvl.add_theme_stylebox_override(k, bos)
	var lh := HBoxContainer.new()
	lh.set_anchors_preset(Control.PRESET_FULL_RECT)
	lh.add_theme_constant_override("separation", 10)
	lh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lvl_shield = E.level_shield(1, 64)
	_lvl_shield.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lh.add_child(_lvl_shield)
	var lv := VBoxContainer.new()
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_theme_constant_override("separation", 2)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lvl_label = UI.title("SEVİYE 1", 20, UI.METIN)
	lv.add_child(_lvl_label)
	_xp_bar = UI.progress(0.0, 214, 26, "0/100")
	lv.add_child(_xp_bar)
	lh.add_child(lv)
	lvl.add_child(lh)
	lvl.pressed.connect(_open_yol)  # seviye yolu (her seviyede ödül)
	_yol_rozet = UI.badge_on(_lvl_shield, 0, 28)
	UI._basma_hissi(lvl, null)
	row.add_child(lvl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	# elmas sayacı + yanında yeşil "+" (elmas mağazası); sayaca dokunmak da mağazayı açar
	var gem_row := HBoxContainer.new()
	gem_row.add_theme_constant_override("separation", -10)
	gem_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gem_row)
	var gem_btn := Button.new()
	gem_btn.focus_mode = Control.FOCUS_NONE
	gem_btn.custom_minimum_size = Vector2(180, UI.DOKUNMA)
	for k in ["normal", "hover", "pressed", "focus"]:
		gem_btn.add_theme_stylebox_override(k, bos)
	var gem := UI.counter("elmas", "0", 46)
	gem.set_anchors_preset(Control.PRESET_FULL_RECT)
	gem.offset_top = 6
	gem.offset_bottom = -6
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(gem.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 22
	gems_label = gem.get_meta("label")
	gems_label.add_theme_color_override("font_color", UI.ELMAS)
	gems_label.add_theme_font_size_override("font_size", 26)
	gems_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gems_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gem_btn.add_child(gem)
	gem_btn.pressed.connect(_open_gem_store)
	UI._basma_hissi(gem_btn, null)
	gem_row.add_child(gem_btn)
	var plus := UI.button("+", "yesil", UI.DOKUNMA, 40, "", UI.DOKUNMA)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(plus.get_meta("row") as Control).offset_left = 0
	(plus.get_meta("row") as Control).offset_right = 0
	plus.pressed.connect(_open_gem_store)
	gem_row.add_child(plus)
	var gear := UI.icon_button("ayarlar", "ikincil", UI.DOKUNMA)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.pressed.connect(func() -> void: open_settings.emit())
	row.add_child(gear)


func _open_gem_store() -> void:
	var m = get_tree().current_scene
	if m and m.has_method("open_gem_store"):
		m.open_gem_store()
	else:
		open_character.emit()


# ---------------------------------------------------------------------
# ORTA SÜTUN: logo, OYNA, kutucuklar, günlük ödül  |  oyuna başla alt ekranı
# ---------------------------------------------------------------------
func _build_center() -> void:
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", UI.B_S)
	root.add_child(col)
	UI.place(col, Control.PRESET_CENTER_TOP, Vector2(-ORTA_W / 2.0, BAR_H - 2), Vector2(ORTA_W, 0))
	logo = TextureRect.new()
	logo.texture = UI.texture("logo", 460)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(ORTA_W, LOGO_H)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(logo)

	# --- ana kutu: OYNA (hızlı oyun) / ODA KUR + KODLA KATIL / kutucuklar ---
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", UI.B_S)
	col.add_child(main_box)
	var oyna_kap := Control.new()
	oyna_kap.custom_minimum_size = Vector2(ORTA_W, 100)
	main_box.add_child(oyna_kap)
	var hale := E.glow(UI.AMBER, 0.42)
	hale.set_anchors_preset(Control.PRESET_FULL_RECT)
	hale.offset_left = -60
	hale.offset_right = 60
	hale.offset_top = -40
	hale.offset_bottom = 40
	oyna_kap.add_child(hale)
	var ht := hale.create_tween().set_loops()
	ht.tween_property(hale, "modulate:a", 0.45, 1.1).set_trans(Tween.TRANS_SINE)
	ht.tween_property(hale, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	# OYNA = hızlı oyun: oyuncular aranır, 25 sn içinde dolmazsa botlarla tamamlanır
	quick_btn = UI.button("OYNA", "ana", 100, 48, "oyna", ORTA_W)
	_alt_yazi(quick_btn, "Hızlı oyun · hemen eşleş", 17)
	quick_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	quick_btn.pressed.connect(_on_quick)
	oyna_kap.add_child(quick_btn)

	# odalar: açık odalar listesi / oda kur (Arkadaşlarım ya da Herkes) / koda katıl
	var mod := HBoxContainer.new()
	mod.add_theme_constant_override("separation", UI.B_S)
	main_box.add_child(mod)
	play_box = mod
	_rooms_btn = _dugme3("ODALAR", "kapi")
	_rooms_btn.pressed.connect(_open_odalar)
	mod.add_child(_rooms_btn)
	_create_btn = _dugme3("ODA KUR", "arkadas")
	_create_btn.pressed.connect(_on_create)
	mod.add_child(_create_btn)
	_join_btn = _dugme3("KODLA KATIL", "davet")
	_join_btn.pressed.connect(func() -> void: _kod_penceresi())
	mod.add_child(_join_btn)

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", UI.B_S)
	main_box.add_child(tiles)
	var tw := (ORTA_W - UI.B_S * 3) / 4.0
	var shop := E.tile("MAĞAZA", "magaza", tw, TILE_H)
	shop.pressed.connect(func() -> void: open_character.emit())
	tiles.add_child(shop)
	_magaza_rozet = UI.badge_on(shop, 0, 30)
	gorev_tile = E.tile("GÖREVLER", "gorev", tw, TILE_H)
	gorev_tile.pressed.connect(func() -> void: _open_gorevler(0))
	tiles.add_child(gorev_tile)
	_gorev_rozet = UI.badge_on(gorev_tile, 0, 30)
	# günlük ödül hazırken GÖREVLER kutucuğunun arkasında yanıp sönen amber hale (ödül orada alınır)
	_gunluk_hale = E.halo(gorev_tile, UI.AMBER)
	_gunluk_hale.visible = false
	basarim_tile = E.tile("BAŞARIMLAR", "basarim", tw, TILE_H)
	basarim_tile.pressed.connect(func() -> void: _open_gorevler(1))
	tiles.add_child(basarim_tile)
	_basarim_rozet = UI.badge_on(basarim_tile, 0, 30)
	var lb := E.tile("LİDERLİK", "liderlik", tw, TILE_H)
	lb.pressed.connect(_open_liderlik)
	tiles.add_child(lb)

	# en altta: ya "tek başına dene" bağlantısı ya da durum satırı (bağlanılıyor… / hata)
	var alt := Control.new()
	alt.custom_minimum_size = Vector2(ORTA_W, UI.DOKUNMA)
	alt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_box.add_child(alt)
	_solo_btn = Button.new()
	_solo_btn.focus_mode = Control.FOCUS_NONE
	var bos := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus"]:
		_solo_btn.add_theme_stylebox_override(k, bos)
	UI.place(_solo_btn, Control.PRESET_CENTER, Vector2(-170, -UI.DOKUNMA / 2.0), Vector2(340, UI.DOKUNMA))
	var sh := HBoxContainer.new()
	sh.set_anchors_preset(Control.PRESET_FULL_RECT)
	sh.alignment = BoxContainer.ALIGNMENT_CENTER
	sh.add_theme_constant_override("separation", 8)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var si := UI.icon("telefon", 30)
	si.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(si)
	var sl := UI.title("TEK BAŞINA DENE", UI.FS_METIN - 2, UI.METIN_SOLUK)
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.sigdir(sl, 290.0)
	sh.add_child(sl)
	_solo_btn.add_child(sh)
	_solo_btn.pressed.connect(func() -> void: solo.emit())
	UI._basma_hissi(_solo_btn, sh)
	alt.add_child(_solo_btn)

	# durum satırı: dönen gösterge + "Oyuncu aranıyor…" ya da uyarı ikonu + hata
	var dc := CenterContainer.new()
	dc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alt.add_child(dc)
	_durum_kutu = PanelContainer.new()
	var dst := UI.flat(Color(0.03, 0.035, 0.035, 0.94), Color(UI.AMBER, 0.7), UI.R_BUYUK)
	dst.set_border_width_all(2)
	dst.content_margin_left = 14
	dst.content_margin_right = 20
	dst.content_margin_top = 6
	dst.content_margin_bottom = 6
	_durum_kutu.add_theme_stylebox_override("panel", dst)
	_durum_kutu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_durum_kutu.custom_minimum_size = Vector2(0, 52)
	dc.add_child(_durum_kutu)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 10)
	dh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_durum_kutu.add_child(dh)
	_durum_don = E.spinner(30)
	dh.add_child(_durum_don)
	_durum_ikon = UI.icon("sikayet", 30)
	_durum_ikon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dh.add_child(_durum_ikon)
	status = UI.title("", UI.FS_METIN, UI.METIN)
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_constant_override("outline_size", 5)
	dh.add_child(status)
	_durum_kutu.visible = false
	_box_now = main_box


# OYNA'nın altındaki üçlü (ODALAR / ODA KUR / KODLA KATIL): üstte ikon, altta yazı (dar düğmede yazı büyük kalsın)
func _dugme3(metin: String, ikon: String) -> Button:
	var w := (ORTA_W - UI.B_S * 2.0) / 3.0
	var b := UI.button("", "ikincil", UI.BTN_H + 8, UI.FS_METIN, "", w)
	var row: HBoxContainer = b.get_meta("row")
	row.offset_left = 10
	row.offset_right = -10
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UI.icon(ikon, 44)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UI.title(metin, UI.FS_METIN + 1, Color.WHITE, true)
	l.add_theme_constant_override("outline_size", 5)
	UI.sigdir(l, w - 34.0)
	v.add_child(l)
	row.add_child(v)
	b.set_meta("label", l)
	return b


# Düğmeye ikinci satır: büyük başlığın altında küçük açıklama ("Hızlı oyun · hemen eşleş")
func _alt_yazi(b: Button, metin: String, fs: int) -> void:
	var l: Label = b.get_meta("label")
	var row: HBoxContainer = b.get_meta("row")
	var i := l.get_index()
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = l.size_flags_horizontal
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.remove_child(l)
	v.add_child(l)
	var s := UI.title(metin, fs, Color(1, 1, 1, 0.84), true)
	s.add_theme_constant_override("outline_size", 4)
	v.add_child(s)
	if l.has_meta("max_w"):
		UI.sigdir(s, float(l.get_meta("max_w")))
	row.add_child(v)
	row.move_child(v, i)
	b.set_meta("alt", s)


# Koda katıl penceresi: büyük 4 harflik kod alanı + KATIL. Yanlış kodda pencere sallanır, altında neden yazar.
func _kod_penceresi(hata := "", kod := "") -> Control:
	if is_instance_valid(_kod_modal):
		return _kod_modal
	var m := UI.modal("KODLA KATIL", 560)
	_kod_modal = m
	var ip := UI.label("Arkadaşının söylediği 4 harfli kodu yaz", UI.FS_METIN, UI.METIN_SOLUK, true)
	ip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.body.add_child(ip)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ABCD"
	code_edit.max_length = 4
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.custom_minimum_size = Vector2(0, 96)
	UI.style_edit(code_edit, 56)
	code_edit.add_theme_font_override("font", UI.TITLE_FONT)
	code_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.16))
	code_edit.add_theme_constant_override("minimum_character_width", 4)
	m.body.add_child(code_edit)
	var red := UI.label(hata, UI.FS_METIN, UI.KIRMIZI.lightened(0.35), true)
	red.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	red.visible = hata != ""
	m.body.add_child(red)
	var ok := UI.button("KATIL", "ana", UI.BTN_H, UI.FS_BUYUK - 4, "oyna")
	code_edit.text = kod
	code_edit.caret_column = kod.length()
	ok.disabled = kod.length() != 4
	m.body.add_child(ok)
	code_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			code_edit.text = up
			code_edit.caret_column = up.length()
		red.visible = false
		ok.disabled = up.strip_edges().length() != 4)
	var katil := func() -> void:
		var yazilan := code_edit.text.strip_edges().to_upper()
		if yazilan.length() != 4:
			red.text = tr("Oda kodu 4 harf olmalı.")
			red.visible = true
			_salla(m.box)
			return
		m.close()
		_on_join(yazilan)
	ok.pressed.connect(katil)
	code_edit.text_submitted.connect(func(_t: String) -> void: katil.call())
	add_child(m)
	code_edit.grab_focus.call_deferred()
	_klavye_kaydir(m, code_edit, ok)
	return m


func _salla(c: Control) -> void:
	UI.tik()
	var x0 := c.position.x
	var tw := c.create_tween()
	for k in [12.0, -10.0, 6.0, -3.0, 0.0]:
		tw.tween_property(c, "position:x", x0 + k, 0.05)


# ---------------------------------------------------------------------
# SOL: envanter kartı — isim plakası, büyük ışıklı dönen karakter, nadirlik rozeti, ENVANTER düğmesi
# ---------------------------------------------------------------------
func _build_char_card() -> void:
	var card := UI.panel(Vector2(SOL_W, 0), 22)
	_sol_kart = card
	root.add_child(card)
	card.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	card.offset_left = KENAR
	card.offset_right = KENAR + SOL_W
	card.offset_top = BAR_H + 10
	card.offset_bottom = -KENAR
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	card.add_child(v)
	# isim plakası: ad + @kullanıcı adı; dokununca ad değiştirilir
	var plate := Button.new()
	plate.focus_mode = Control.FOCUS_NONE
	plate.custom_minimum_size = Vector2(0, 66)
	var pst := StyleBoxFlat.new()
	pst.bg_color = Color(0.02, 0.025, 0.025, 0.82)
	pst.border_color = Color(UI.AMBER, 0.55)
	pst.set_border_width_all(2)
	pst.border_width_bottom = 4
	pst.set_corner_radius_all(UI.R_ORTA)
	for k in ["normal", "hover", "pressed", "focus"]:
		plate.add_theme_stylebox_override(k, pst)
	var ph := HBoxContainer.new()
	ph.set_anchors_preset(Control.PRESET_FULL_RECT)
	ph.offset_left = 14
	ph.offset_right = -10
	ph.add_theme_constant_override("separation", 8)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_theme_constant_override("separation", -2)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = UI.title("", UI.FS_ORTA, UI.METIN)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pv.add_child(_name_label)
	_handle_label = UI.label("", UI.FS_KUCUK, UI.METIN_SOLUK)
	_handle_label.clip_text = true
	pv.add_child(_handle_label)
	ph.add_child(pv)
	plate.add_child(ph)
	plate.pressed.connect(_hesap_ekrani)  # ad değiştirilmez (kullanıcı adı); hesap ekranı açılır
	UI._basma_hissi(plate, null)
	v.add_child(plate)

	# sahne: arkada amber hale, dönen karakter, sağ üstte nadirlik
	var stage := Button.new()
	stage.focus_mode = Control.FOCUS_NONE
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var empty := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus"]:
		stage.add_theme_stylebox_override(k, empty)
	stage.button_down.connect(func() -> void: UI.tik())
	stage.pressed.connect(func() -> void: open_inventory.emit())
	v.add_child(stage)
	var hale := E.glow(UI.AMBER, 0.55)
	hale.set_anchors_preset(Control.PRESET_FULL_RECT)
	hale.offset_left = -40
	hale.offset_right = 40
	stage.add_child(hale)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(svc)
	_build_preview(svc)
	_rarity_pill = E.pill("", UI.AMBER, 15)
	_rarity_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_rarity_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_rarity_pill.offset_top = 4
	_rarity_pill.offset_right = -2
	stage.add_child(_rarity_pill)

	var inv := UI.button("ENVANTER", "ikincil", UI.BTN_H_KUCUK + 4, UI.FS_ORTA, "envanter")
	inv.pressed.connect(func() -> void: open_inventory.emit())
	v.add_child(inv)


func _build_preview(svc: SubViewportContainer) -> void:
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)
	var w := Node3D.new()
	sv.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	w.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.55, 2.7, 0)
	key.light_energy = 1.3
	key.light_color = Color("#fff1d8")
	w.add_child(key)
	# sıcak tepe ışığı (lamba altında duruyormuş gibi)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 3.2, -0.6)
	spot.rotation = Vector3(-PI / 2 + 0.2, 0, 0)
	spot.light_color = Color("#ffb64a")
	spot.light_energy = 3.0
	spot.spot_range = 5.0
	spot.spot_angle = 38.0
	w.add_child(spot)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.9, 1.9, 1.2)
	rim.light_color = Color("#7fa8ff")
	rim.light_energy = 1.6
	rim.omni_range = 4.5
	w.add_child(rim)
	# ayak altı: koyu gölge diski + ince amber halka
	var sh := MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 0.5
	disk.bottom_radius = 0.5
	disk.height = 0.01
	sh.mesh = disk
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.albedo_color = Color(0, 0, 0, 0.35)
	sh.material_override = shm
	w.add_child(sh)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.44
	ring.outer_radius = 0.47
	var rg := MeshInstance3D.new()
	rg.mesh = ring
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color("#ffb020")
	rg.material_override = rm
	rg.scale = Vector3(1, 0.3, 1)
	w.add_child(rg)
	_turn = Node3D.new()
	w.add_child(_turn)
	_preview = ModelScript.new()
	_preview.look = profile.look.duplicate()
	_turn.add_child(_preview)
	var cam := Camera3D.new()
	cam.fov = 26
	w.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.1, -4.1), Vector3(0, 0.9, 0))


# ---------------------------------------------------------------------
# SAĞ: arkadaşlar paneli
# ---------------------------------------------------------------------
func _build_friends_card() -> void:
	var card := UI.panel(Vector2(SAG_W, 0), 20)
	_sag_kart = card
	root.add_child(card)
	card.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	card.offset_left = -KENAR - SAG_W
	card.offset_right = -KENAR
	card.offset_top = BAR_H + 10
	card.offset_bottom = -KENAR
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UI.B_S)
	card.add_child(v)
	# başlık: ikon + ARKADAŞLAR + çevrimiçi sayısı
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var hi := UI.icon("arkadas", 40)
	hi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hi)
	var ht := UI.title("ARKADAŞLAR", 22, UI.METIN)
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ht.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(ht)
	var on := PanelContainer.new()
	var ost := StyleBoxFlat.new()
	ost.bg_color = Color(0, 0, 0, 0.5)
	ost.border_color = Color(UI.YESIL, 0.6)
	ost.set_border_width_all(2)
	ost.set_corner_radius_all(20)
	ost.content_margin_left = 10
	ost.content_margin_right = 12
	on.add_theme_stylebox_override("panel", ost)
	on.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var oh := HBoxContainer.new()
	oh.add_theme_constant_override("separation", 6)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dst := StyleBoxFlat.new()
	dst.bg_color = UI.YESIL
	dst.set_corner_radius_all(6)
	dst.shadow_color = Color(UI.YESIL, 0.6)
	dst.shadow_size = 4
	dot.add_theme_stylebox_override("panel", dst)
	oh.add_child(dot)
	_online_label = UI.title("0", 20, UI.YESIL)
	oh.add_child(_online_label)
	on.add_child(oh)
	head.add_child(on)
	v.add_child(head)
	# gelen istek bildirimi
	var req := Button.new()
	req.focus_mode = Control.FOCUS_NONE
	req.custom_minimum_size = Vector2(0, UI.DOKUNMA)
	var rst := StyleBoxFlat.new()
	rst.bg_color = Color(UI.AMBER, 0.14)
	rst.border_color = Color(UI.AMBER, 0.8)
	rst.set_border_width_all(2)
	rst.border_width_left = 6
	rst.set_corner_radius_all(UI.R_ORTA)
	for k in ["normal", "hover", "pressed", "focus"]:
		req.add_theme_stylebox_override(k, rst)
	var rh := HBoxContainer.new()
	rh.set_anchors_preset(Control.PRESET_FULL_RECT)
	rh.offset_left = 12
	rh.offset_right = -12
	rh.add_theme_constant_override("separation", 10)
	rh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ri := UI.icon("davet", 38)
	ri.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(ri)
	var rl := UI.title("YENİ İSTEK", 19, UI.AMBER)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rh.add_child(rl)
	_req_badge = UI.badge(1, 30)
	_req_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(_req_badge)
	req.add_child(rh)
	req.pressed.connect(func() -> void: open_friends.emit())
	UI._basma_hissi(req, rh)
	_req_box = req
	v.add_child(req)
	# liste
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UI.touch_scroll(sc)
	v.add_child(sc)
	friends_list = VBoxContainer.new()
	friends_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	friends_list.add_theme_constant_override("separation", UI.B_XS)
	sc.add_child(friends_list)
	var add := UI.button("ARKADAŞ EKLE", "ikincil", UI.BTN_H_KUCUK + 4, 22, "davet")
	add.pressed.connect(func() -> void: open_friends.emit())
	v.add_child(add)


func _refresh_friends() -> void:
	if not friends_list:
		return
	for ch in friends_list.get_children():
		ch.queue_free()
	_online_label.text = str(account.online_count())
	_req_box.visible = account.incoming.size() > 0
	UI.set_badge(_req_badge, account.incoming.size())
	if account.friends.is_empty():
		friends_list.add_child(_empty_friends())
		return
	var list: Array = account.friends.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := (2 if str(a.get("room", "")) != "" else 0) + (1 if a.get("online", false) else 0)
		var rb := (2 if str(b.get("room", "")) != "" else 0) + (1 if b.get("online", false) else 0)
		if ra != rb:
			return ra > rb
		return str(a.get("name", "")) < str(b.get("name", "")))
	for f in list:
		friends_list.add_child(_friend_row(f))
	E.stagger(friends_list, 0.04)


func _friend_row(f: Dictionary) -> Control:
	var online: bool = f.get("online", false)
	var room := str(f.get("room", ""))
	var box := E.row_box(Color(0, 0, 0, 0), Vector4(10, 8, 8, 8))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	box.add_child(r)
	var nm := str(f.get("name", ""))
	var hd := str(f.get("handle", ""))
	var durum := "kapali"
	if online:
		durum = "oda" if room != "" else "acik"
	var av := E.avatar(nm if nm != "" else hd, hd, 50, durum)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not online:
		av.modulate = Color(0.6, 0.6, 0.6, 0.9)
	r.add_child(av)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	var n := UI.title(nm if nm != "" else hd, 20, UI.METIN if online else UI.METIN_SOLUK)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(n)
	var macta: bool = online and room != "" and bool(f.get("oyun", false))
	var sub := "Çevrimdışı"
	var sub_c := UI.METIN_SOLUK
	if macta:
		sub = "Maçta"
		sub_c = UI.KIRMIZI.lightened(0.3)
	elif online and room != "":
		sub = "Odada"
		sub_c = UI.AMBER
	elif online:
		sub = "Çevrimiçi"
		sub_c = UI.YESIL
	var s := UI.label(sub, UI.FS_KUCUK, sub_c)
	s.clip_text = true
	tv.add_child(s)
	r.add_child(tv)
	if online and room != "":
		# maçtaki arkadaşın odasına izleyici olarak girilir (maç bitince birlikte oynanır)
		var join := UI.button("İZLE" if macta else "KATIL", "ikincil" if macta else "yesil", UI.DOKUNMA, 18, "", 100)
		join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		(join.get_meta("row") as Control).offset_left = 10
		(join.get_meta("row") as Control).offset_right = -10
		UI.sigdir(join.get_meta("label"), 100.0 - 24.0)  # dar kenar payına göre yeniden sığdır
		join.pressed.connect(func() -> void: _on_join(room))
		r.add_child(join)
	else:
		r.add_child(_spacer(0, UI.DOKUNMA))
	return box


func _empty_friends() -> Control:
	return E.durum("arkadas", "BİRLİKTE OYNA", "Arkadaşlarını ekle, birlikte oynayın.", false, "", Callable(), 96.0)


func _spacer(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# Arkadaş daveti: üstten kayan kart (KATIL / kapat), 15 sn sonra kendiliğinden kapanır.
func _on_invited(handle: String, name: String, code: String) -> void:
	if not visible:
		# menü kapalı: maçtaysa rahatsız etme; bekleme salonundaysa kısa bilgi ver
		if net.connected and not net.in_game and code != net.room_code:
			UI.toast(tr("%s seni odasına çağırıyor (%s)") % [name, code], null, 3.0, "bilgi")
		return
	if _toast and is_instance_valid(_toast):
		_toast.queue_free()
	var kok := Control.new()
	kok.set_anchors_preset(Control.PRESET_CENTER_TOP)
	kok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(kok)
	_toast = kok
	var card := E.row_box(UI.AMBER, Vector4(18, 12, 12, 12))
	var cst := card.get_theme_stylebox("panel") as StyleBoxFlat
	cst.bg_color = Color(0.04, 0.05, 0.05, 0.97)
	cst.shadow_size = 18
	cst.shadow_color = Color(0, 0, 0, 0.7)
	card.custom_minimum_size = Vector2(620, 0)
	card.position = Vector2(-310, BAR_H + 10)
	kok.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	card.add_child(h)
	var av := E.avatar(name, handle, 60, "oda")
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(UI.title("ODA DAVETİ", 18, UI.AMBER))
	var l := UI.label(tr("%s seni odasına çağırıyor") % name, UI.FS_METIN, UI.METIN)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(l)
	h.add_child(tv)
	var ok := UI.button("KATIL", "yesil", UI.DOKUNMA, 22, "", 130)
	ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		_close_toast(kok)
		if not net.connected:
			_on_join(code))
	h.add_child(ok)
	var no := UI.icon_button("kapat", "ikincil", UI.DOKUNMA)
	no.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	no.pressed.connect(func() -> void: _close_toast(kok))
	h.add_child(no)
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(card, "position:y", card.position.y, 0.35).from(card.position.y - 40.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var kid := kok.get_instance_id()  # kapatılıp silinmişse lambda silinmiş düğümü yakalamasın
	get_tree().create_timer(15.0).timeout.connect(func() -> void:
		var k := instance_from_id(kid) as Control
		if k:
			_close_toast(k))


func _close_toast(kok: Control) -> void:
	if not is_instance_valid(kok) or kok.has_meta("kapaniyor"):
		return
	kok.set_meta("kapaniyor", true)
	var tw := kok.create_tween()
	tw.tween_property(kok, "modulate:a", 0.0, 0.18)
	tw.tween_callback(kok.queue_free)


func _dunya_ciz() -> void:
	if is_inside_tree():
		get_viewport().disable_3d = visible


func _exit_tree() -> void:
	get_viewport().disable_3d = false


func _process(delta: float) -> void:
	if not visible:
		return
	_ortam_t += delta
	if _turn:
		# karakter hep önü bize dönük kalır: iki yana yavaşça salınır (arkası pek görünmez)
		_turn.rotation.y = sin(_ortam_t * 0.45) * 0.55
	if _mesgul > 0.0:
		_mesgul -= delta
		if _mesgul <= 0.0:
			# cevap gelmedi: düğmeleri geri aç
			_set_status("Cevap gelmedi. İnternetini kontrol edip tekrar dene.")
	_ortam_isle()


# ---------------------------------------------------------------------
# Arka plan ortamı (bg_menu): paralaks, floresan titremesi, lamba nefesi, yer sisi, toz
# ---------------------------------------------------------------------
# görseldeki ışıkların yerleri (1920x1080 görsel üzerinde), hale boyu ve rengi
const ISIKLAR := [
	[Vector2(960, 105), 300.0, Color("#9fd8ff"), 0.5],   # tavandaki floresan (logonun üstünde)
	[Vector2(960, 290), 150.0, Color("#9fd8ff"), 0.35],
	[Vector2(503, 350), 120.0, Color("#ff9a3a"), 0.55],   # koridor lambaları
	[Vector2(1415, 350), 120.0, Color("#ff9a3a"), 0.55],
	[Vector2(617, 425), 80.0, Color("#ff9a3a"), 0.5],
	[Vector2(1300, 425), 80.0, Color("#ff9a3a"), 0.5],
	[Vector2(212, 165), 150.0, Color("#ffa040"), 0.5],
	[Vector2(1705, 165), 150.0, Color("#ffa040"), 0.5],
]
const BG_BOYUT := Vector2(1920, 1080)
var _titreme_sonraki := 2.5


func _ortam_kur() -> void:
	var bg := UI.background("bg_menu", 0.2)
	add_child(bg)
	if bg.get_child_count() > 1:
		_bg_resim = bg.get_child(0)
		_bg_golge = bg.get_child(1) as ColorRect
		_bg_resim.resized.connect(func() -> void: _bg_resim.pivot_offset = _bg_resim.size / 2.0)
		_bg_resim.scale = Vector2.ONE * 1.04
		var zoom := _bg_resim.create_tween().set_loops()
		zoom.tween_property(_bg_resim, "scale", Vector2.ONE * 1.09, 18.0).set_trans(Tween.TRANS_SINE)
		zoom.tween_property(_bg_resim, "scale", Vector2.ONE * 1.04, 18.0).set_trans(Tween.TRANS_SINE)
		# ışık haleleri: toplamalı karışım (görseldeki lambaların üstünde parlar)
		var ekle := CanvasItemMaterial.new()
		ekle.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		for i in ISIKLAR.size():
			var d: Array = ISIKLAR[i]
			var g := E.glow(d[2], 1.0)
			g.material = ekle
			g.modulate.a = float(d[3])
			bg.add_child(g)
			_isiklar.append([g, d[0], float(d[1]), float(d[3]), randf() * TAU])
		_floresan = _isiklar[0][0]
	var kalite := int(profile.settings.get("kalite", 1)) if profile else 1
	if kalite >= 1:
		bg.add_child(_sis())
		bg.add_child(_toz())
	add_child(E.vignette(0.1, 0.88))


# Yerde yavaşça akan sis: tek gürültü dokusu, kayan UV (alt yarıda, üst kenarı yumuşak)
func _sis() -> Control:
	var gur := NoiseTexture2D.new()
	gur.width = 256
	gur.height = 128
	gur.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.012
	fn.fractal_octaves = 3
	gur.noise = fn
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D gurultu : repeat_enable, filter_linear;
uniform vec4 renk : source_color = vec4(0.62, 0.74, 0.85, 0.16);
void fragment() {
	vec2 uv = UV * vec2(2.2, 1.0);
	float a = texture(gurultu, uv + vec2(TIME * 0.006, 0.0)).r;
	float b = texture(gurultu, uv * 1.7 + vec2(-TIME * 0.011, 0.31)).r;
	float m = smoothstep(0.0, 0.55, UV.y) * smoothstep(1.0, 0.8, UV.y);
	COLOR = vec4(renk.rgb, renk.a * smoothstep(0.25, 0.85, a * 0.6 + b * 0.5) * m);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("gurultu", gur)
	var r := ColorRect.new()
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.5
	r.anchor_bottom = 1.0
	return r


# Lamba ışığında süzülen toz zerreleri (az sayıda, CPU parçacığı)
func _toz() -> Node:
	var p := CPUParticles2D.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 16
	gt.height = 16
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	p.texture = gt
	p.amount = 22
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(700, 380)
	p.direction = Vector2(0.3, -1)
	p.spread = 50.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 14.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 0.75, 0.45, 0.0))
	ramp.add_point(0.3, Color(1, 0.78, 0.5, 0.45))
	ramp.add_point(0.7, Color(1, 0.78, 0.5, 0.35))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 0.75, 0.45, 0.0))
	p.color_ramp = ramp
	var kok := Node2D.new()
	kok.add_child(p)
	var yerles := func() -> void:
		var s := get_viewport().get_visible_rect().size
		p.position = s / 2.0
		p.emission_rect_extents = s / 2.0
	get_viewport().size_changed.connect(yerles)
	yerles.call_deferred()
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(kok)
	return c


func _ortam_isle() -> void:
	if not is_instance_valid(_bg_resim):
		return
	var t := _ortam_t
	# paralaks: görsel çok yavaş iki yana kayar (ölçek 1.04+ olduğundan kenar görünmez)
	_bg_resim.position = Vector2(sin(t * 0.11) * 12.0, cos(t * 0.083) * 5.0)
	var rs := _bg_resim.size
	var s := maxf(rs.x / BG_BOYUT.x, rs.y / BG_BOYUT.y) * _bg_resim.scale.x
	var merkez := _bg_resim.position + rs / 2.0
	for i in _isiklar.size():
		var d: Array = _isiklar[i]
		var g: TextureRect = d[0]
		var yer: Vector2 = merkez + ((d[1] as Vector2) - BG_BOYUT / 2.0) * s
		var r: float = float(d[2]) * s
		g.position = yer - Vector2(r, r)
		g.size = Vector2(r, r) * 2.0
		if i >= 2:
			# lambalar nefes alır
			g.modulate.a = float(d[3]) * (0.8 + 0.2 * sin(t * 1.4 + float(d[4])))
	# floresan: ara sıra kısa titreme (lamba bozuk gibi); o an koridor da hafifçe kararır
	if t >= _titreme_sonraki and is_instance_valid(_floresan):
		_titreme_sonraki = t + randf_range(4.0, 9.0)
		var a0: float = float(_isiklar[0][3])
		var tw := _floresan.create_tween()
		for k in [[0.1, 0.04], [a0, 0.06], [0.2, 0.05], [a0 * 0.8, 0.08], [0.05, 0.04], [a0, 0.12]]:
			tw.tween_property(_floresan, "modulate:a", float(k[0]), float(k[1]))
		if _bg_golge:
			var gt := _bg_golge.create_tween()
			gt.tween_property(_bg_golge, "color:a", 0.34, 0.05)
			gt.tween_property(_bg_golge, "color:a", 0.2, 0.3)


# Geniş telefonlarda (ör. 2400x1080 -> 1600x720) yan paneller biraz genişler, kenarlardan içeri alınır;
# orta sütun hep ortada kalır.
func _yerlesim() -> void:
	var fazla := maxf(0.0, root.size.x - 1280.0)
	var ek := minf(fazla * 0.2, 70.0)
	# kenar payı: çentik / kamera deliği (güvenli alan) ve yuvarlak köşeler için en az UI.KENAR_PAYI
	var g := UI.guvenli_pay()
	var kenar := maxf(KENAR + minf(fazla * 0.12, 40.0), maxf(maxf(g.x, g.z) + 8.0, UI.KENAR_PAYI))
	# yan kartlar orta sütuna değmesin (dar ekranda biraz daralırlar)
	var yer := (root.size.x - ORTA_W) / 2.0 - kenar - UI.B_S
	# iPad gibi uzun ekranda orta sütun üste yapışık kalmasın: logo büyür, sütun biraz iner
	var uzun := maxf(0.0, root.size.y - 720.0)
	logo.custom_minimum_size.y = LOGO_H + minf(uzun * 0.4, 90.0)
	col.offset_top = BAR_H - 2 + uzun * 0.3
	_sol_kart.custom_minimum_size.x = minf(SOL_W, yer)
	_sag_kart.custom_minimum_size.x = minf(SAG_W, yer)
	_sol_kart.offset_left = kenar
	_sol_kart.offset_right = kenar + minf(SOL_W + ek, yer)
	_sag_kart.offset_left = -kenar - minf(SAG_W + ek, yer)
	_sag_kart.offset_right = -kenar


# ---------------------------------------------------------------------
# Geçişler
# ---------------------------------------------------------------------
func _intro() -> void:
	# yan paneller yandan, orta sütun ve üst çubuk soluklaşarak gelir; logo hafifçe büyüyerek oturur
	var parcalar := root.get_children()
	for c in parcalar:
		(c as Control).modulate.a = 0.0
	await get_tree().process_frame
	for i in parcalar.size():
		var c: Control = parcalar[i]
		var tw := c.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(c, "modulate:a", 1.0, 0.3)
		var dx := 0.0
		if c.anchor_left == 0.0 and c.anchor_right == 0.0:
			dx = -40.0
		elif c.anchor_left == 1.0:
			dx = 40.0
		if dx != 0.0:
			var x0 := c.position.x
			tw.parallel().tween_property(c, "position:x", x0, 0.4).from(x0 + dx).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	logo.pivot_offset = logo.size / 2.0
	logo.scale = Vector2.ONE * 1.12
	logo.create_tween().tween_property(logo, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	E.stagger(main_box, 0.07)


# Eski arayüz: "oyna" alt ekranı yerine kod penceresi açılır (test pozu "oyna" ve geri uyumluluk)
func _show(box: Control) -> void:
	if box == play_box:
		_kod_penceresi()


# Ana menüde geri tuşu: "Oyundan çıkılsın mı?" (yanlışlıkla basınca oyun kapanmasın)
func _cikis_onayi() -> void:
	if is_instance_valid(_cikis_modal) or is_instance_valid(_kod_modal):
		return
	var m := UI.modal("ÇIKIŞ", 520)
	var l := UI.label("Oyundan çıkmak istiyor musun?", UI.FS_METIN + 2, UI.METIN, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.body.add_child(l)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_M)
	var vaz := UI.button("VAZGEÇ", "ikincil", UI.BTN_H, UI.FS_ORTA)
	vaz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vaz.pressed.connect(m.close)
	h.add_child(vaz)
	var cik := UI.button("ÇIK", "tehlike", UI.BTN_H, UI.FS_ORTA, "geri")
	cik.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cik.pressed.connect(func() -> void: get_tree().quit())
	h.add_child(cik)
	m.body.add_child(h)
	add_child(m)
	_cikis_modal = m


# ---------------------------------------------------------------------
# Veri
# ---------------------------------------------------------------------
# Oyundaki ad: hesabın kullanıcı adı (ayrı bir takma ad yok; sunucu da odada adı hesaptan alır).
func _player_name() -> String:
	if account.has_account and account.handle != "":
		return account.handle
	return profile.player_name if profile.player_name != "" else account.handle


# Hesapsız oynanmaz: hesap yoksa (olağan akışta açılış kapısı zaten açıktır) hesap ekranı açılır.
func _hesap_var() -> bool:
	if account.has_account:
		return true
	var g: CanvasLayer = Giris.new()
	g.account = account
	g.profile = profile
	g.zorunlu = true
	get_parent().add_child(g)
	return false


func refresh_profile() -> void:
	if not gems_label:
		return
	var eco: Dictionary = account.eco
	gems_label.text = E.sayi(int(eco.get("elmas", profile.gems)))
	var sv := int(eco.get("seviye", 1))
	var ic := int(eco.get("xp_ic", 0))
	var ger := maxi(1, int(eco.get("xp_gerek", 100)))
	_lvl_label.text = tr("SEVİYE %d") % sv
	(_lvl_shield.get_meta("label") as Label).text = str(sv)
	_xp_bar.value = float(ic) / float(ger)
	_xp_bar.text = tr("%d / %d XP") % [ic, ger]
	# günlük ödül GÖREVLER ekranında alınır: hazırken kutucuk rozetine +1 ve arkasında yanıp sönen hale
	var hazir: bool = bool(eco.get("gunluk_hazir", false)) and profile.daily_available()
	_gunluk_hale.visible = hazir
	# alınabilir görev / başarım sayıları
	var g := 0
	for m in eco.get("gorevler", []):
		if not bool(m.get("alindi", false)) and int(m.get("ilerleme", 0)) >= int(m.get("hedef", 1)):
			g += 1
	var b := 0
	for a in eco.get("basarimlar", []):
		if not bool(a.get("alindi", false)) and int(a.get("ilerleme", 0)) >= int(a.get("hedef", 1)):
			b += 1
	UI.set_badge(_gorev_rozet, g + (1 if hazir else 0))
	UI.set_badge(_basarim_rozet, b)
	UI.set_badge(_yol_rozet, int(eco.get("yol_hazir", 0)))
	UI.set_badge(_magaza_rozet, int(eco.get("istek_yeni", 0)))
	# isim plakası
	_name_label.text = _player_name()
	_handle_label.text = tr("Oyundaki adın") if account.has_account else tr("Giriş yapılmadı")
	# giyili en nadir parça
	var en := -1
	for cat in ["sac", "sakal", "sapka", "dovme", "kiyafet", "aksesuar"]:
		var p := Catalog.price(cat, str(profile.look.get(cat, "")))
		if p > 0:
			en = maxi(en, _rarity_index(p))
	_rarity_pill.visible = en >= 1
	if en >= 1:
		var key: String = ["siradan", "nadir", "epik", "efsane"][en]
		var c := UI.rarity_color(key)
		var lab: Label = _rarity_pill.get_meta("label")
		lab.text = ["", "NADİR", "EPİK", "EFSANE"][en]
		lab.add_theme_color_override("font_color", c.lightened(0.15))
		var st := _rarity_pill.get_theme_stylebox("panel") as StyleBoxFlat
		st.border_color = c
		st.bg_color = Color(c.darkened(0.75), 0.92)
	if _preview:
		_preview.set_look(profile.look)


func _rarity_index(p: int) -> int:
	for i in Catalog.RARITY.size():
		if p <= int(Catalog.RARITY[i][0]):
			return i
	return 0


# Sunucudan ödül geldi (günlük ödül, görev, başarım): menüdeyken üstte yeşil bildirim
func _on_reward(d: Dictionary) -> void:
	if not visible or str(d.get("t", "")) == "mac_odul":
		return
	UI.toast(tr("+%d elmas  ·  %s") % [int(d.get("elmas", 0)), Dil.sunucu(d, "neden")], null, 2.4, "basari", BAR_H + 12.0)


# İsim plakasına dokununca hesap ekranı (sicil kartı): oyundaki ad kullanıcı adıdır, ayrıca değiştirilmez.
func _hesap_ekrani() -> void:
	var g: CanvasLayer = Giris.new()
	g.account = account
	g.profile = profile
	get_parent().add_child(g)


# Telefonda klavye açılınca pencere yukarı kayar: yazı alanı ve KAYDET düğmesi klavyenin üstünde kalır.
# Test: -- klavye=<px> klavye açıkmış gibi davranır.
func _klavye_kaydir(m: Control, e: LineEdit, alt_dugme: Control) -> void:
	var test := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("klavye="):
			test = float(a.substr(7))
	if test > 0.0:
		e.grab_focus.call_deferred()
	var kutu: Control = m.get("box")
	var kaydir := [0.0]
	var adim := func() -> void:
		if not is_instance_valid(m) or not is_instance_valid(kutu) or not m.is_inside_tree():
			return
		var vis := m.get_viewport().get_visible_rect().size
		var kh := test
		if kh <= 0.0 and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			kh = float(DisplayServer.virtual_keyboard_get_height()) * vis.y / maxf(1.0, float(DisplayServer.window_get_size().y))
		var hedef := 0.0
		if kh > 0.0 and e.has_focus():
			var ust: float = e.get_global_rect().position.y + kaydir[0]
			var alt: float = maxf(e.get_global_rect().end.y, alt_dugme.get_global_rect().end.y) + kaydir[0] + UI.B_S
			hedef = clampf(alt - (vis.y - kh), 0.0, maxf(0.0, ust - UI.B_S))
		var yeni := lerpf(kaydir[0], hedef, 0.25) if absf(kaydir[0] - hedef) > 0.5 else hedef
		kaydir[0] = yeni
		# CenterContainer'ın ortaladığı yerden yukarı kaydır
		var orta := ((kutu.get_parent() as Control).size.y - kutu.size.y) / 2.0
		kutu.position.y = orta - yeni
	get_tree().process_frame.connect(adim)
	m.tree_exiting.connect(func() -> void:
		if get_tree().process_frame.is_connected(adim):
			get_tree().process_frame.disconnect(adim))


func _open_gorevler(tab: int) -> void:
	var g: CanvasLayer = GorevlerScript.new()
	g.account = account
	g.profile = profile
	g.tab = tab
	get_parent().add_child(g)


func _open_yol() -> CanvasLayer:
	var y: CanvasLayer = SeviyeYoluScript.new()
	y.account = account
	y.profile = profile
	get_parent().add_child(y)
	return y


# Arkadaştan hediye geldi: ödül penceresi (eşyanın resmi, kimden geldiği)
func _on_gift(d: Dictionary) -> void:
	var cat := str(d.get("kat", ""))
	var id := str(d.get("id", ""))
	var kim := str(d.get("ad", ""))
	if kim == "":
		kim = "@" + str(d.get("handle", ""))
	var katman := CanvasLayer.new()
	katman.layer = 60
	get_parent().add_child(katman)
	var th: Node = ThumbsScript.new()
	katman.add_child(th)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if cat == "dovme":
		pic.texture = ModelScript.ink_texture(id)
	else:
		th.request(profile.look, cat, id, pic)
	var tier: Array = Catalog.rarity(Catalog.price(cat, id))
	var pop := Fx.reward_popup(katman, tr("%s SANA HEDİYE GÖNDERDİ!") % kim, Catalog.item_name(cat, id), str(tier[1]), UI.rarity_color(UI.rarity_key(str(tier[1]))), pic)
	pop.tree_exited.connect(katman.queue_free)


func _open_liderlik() -> void:
	var l: CanvasLayer = LiderlikScript.new()
	l.account = account
	l.profile = profile
	get_parent().add_child(l)


# Durum satırı: hata (kırmızı kenar, uyarı ikonu) ya da bekleme (amber kenar, dönen gösterge).
# Beklerken OYNA / ODA KUR / KODLA KATIL kapalıdır (iki kez basılıp iki odaya girilmesin).
func _set_status(text: String, hata := true) -> void:
	status.text = text
	_mesgul = 0.0 if hata else MESGUL_SURE
	if text == "":
		_mesgul = 0.0
	status.add_theme_color_override("font_color", UI.KIRMIZI.lightened(0.4) if hata else UI.METIN)
	var st := _durum_kutu.get_theme_stylebox("panel") as StyleBoxFlat
	st.border_color = Color(UI.KIRMIZI, 0.85) if hata else Color(UI.AMBER, 0.7)
	_durum_don.visible = not hata
	_durum_ikon.visible = hata
	var acik := text != ""
	if acik and not _durum_kutu.visible:
		_durum_kutu.modulate.a = 0.0
		_durum_kutu.create_tween().tween_property(_durum_kutu, "modulate:a", 1.0, 0.18)
	_durum_kutu.visible = acik
	_solo_btn.visible = not acik
	for b in [quick_btn, _create_btn, _join_btn, _rooms_btn]:
		(b as Button).disabled = _mesgul > 0.0
	if acik and hata:
		# yerleşimden sonra salla (CenterContainer konumu bir kare sonra kurar)
		get_tree().create_timer(0.1).timeout.connect(func() -> void: _salla(_durum_kutu))


func _on_quick() -> void:
	if not _hesap_var():
		return
	Giris.kurallar_sonra(self, profile, func() -> void:
		_son_kod = ""
		_set_status("Oyuncu aranıyor…", false)
		net.quick_match(_player_name()))


func _on_create() -> void:
	_oda_kur_penceresi()


# ODA KUR penceresi (menüde ya da ODALAR ekranının üstünde). Son seçimler hatırlanır (profile.settings.oda_ayar).
func _oda_kur_penceresi() -> void:
	var son: Dictionary = profile.settings.get("oda_ayar", {}) if profile.settings.get("oda_ayar") is Dictionary else {}
	var ayar := son.duplicate()
	ayar.oda_ad = ""  # ad her seferinde boş başlar (varsayılan: "<ad>'nin odası")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("oda_kur_gor="):
			ayar.gor = a.substr(12)  # test pozu
	var m := OdalarScript.kur_penceresi(ayar, false, _player_name(), _oda_kur, account)
	(_odalar if is_instance_valid(_odalar) else self).add_child(m)


func _oda_kur(ayar: Dictionary) -> void:
	profile.settings["oda_ayar"] = {"gor": ayar.gor, "max": ayar.max, "botla": ayar.botla}
	profile.save()
	if not _hesap_var():
		return
	Giris.kurallar_sonra(_odalar if is_instance_valid(_odalar) else self, profile, func() -> void:
		_son_kod = ""
		_set_status("Oda kuruluyor…", false)
		net.join(net.new_code(), _player_name(), true, "", false, ayar))


# ODALAR ekranı: herkese açık odalar (arkadaşlarınki üstte); KATIL listeden bağlanır
func _open_odalar() -> void:
	if is_instance_valid(_odalar):
		return
	var o: CanvasLayer = OdalarScript.new()
	o.net = net
	o.account = account
	for a in OS.get_cmdline_user_args():
		if a.begins_with("odalar_demo="):
			o.demo = a.substr(12)  # test pozu
	o.katil.connect(func(code: String, liste: bool) -> void:
		if not _hesap_var():
			return
		Giris.kurallar_sonra(o, profile, func() -> void:
			_son_kod = ""  # hata ODALAR ekranında bildirilir (kod penceresi açılmaz)
			if is_instance_valid(o):
				o.call("baglaniyor", code)
			_set_status("Bağlanılıyor…", false)
			net.join(code, _player_name(), false, "", false, {}, liste)))
	o.kur_iste.connect(_oda_kur_penceresi)
	_odalar = o
	get_parent().add_child(o)


func _on_join(raw: String) -> void:
	var code := raw.strip_edges().to_upper()
	if code.length() != 4:
		_kod_penceresi(tr("Oda kodu 4 harf olmalı."))
		return
	if not _hesap_var():
		return
	Giris.kurallar_sonra(self, profile, func() -> void:
		_son_kod = code
		_set_status("Bağlanılıyor…", false)
		net.join(code, _player_name(), false))


# main.gd: bağlantı / oda hatası. Kodla katılırken olduysa kod penceresi kodu ve nedeniyle yeniden açılır.
func show_error(msg: String) -> void:
	_set_status(msg)
	if _son_kod != "" and visible:
		var m := _kod_penceresi(msg, _son_kod)
		_son_kod = ""
		# pencere yerleştikten sonra sallanır (yerleşmeden sallanırsa kenara kayar)
		var kutu: Control = m.get("box")
		if kutu:
			get_tree().create_timer(0.3).timeout.connect(func() -> void:
				if is_instance_valid(kutu):
					_salla(kutu))
