# Yeni mini oyunların ekranları için ortak taban. Her oyun (Kim Kim?, Yalancı, Rus Ruleti, C4, Ortalama)
# bundan türer; game_ui.gd sunucudan geleni buraya iletir, main.gd 3D etkileşimleri (hedefler, kapılar) sorar.
extends Node

const UI := preload("res://scripts/ui.gd")
const OI := preload("res://scripts/oyun_ici.gd")
const Dil := preload("res://scripts/dil.gd")
const CHALK_FONT := preload("res://assets/fonts/CabinSketch-Bold.ttf")
const CHALK := Color(0.95, 0.96, 0.9)
const GREEN := Color("#5be37d")
const RED := Color("#ff5a5a")
const GOLD := Color("#ffcf8a")

var g: CanvasLayer  # game_ui.gd
var w: Node3D  # main.gd
var task := ""
var state := {}
var secret := {}
var panel: Control  # açık tahta / pencere
var card: Control  # rol kartı


# ---------- türeyenlerin dolduracağı ----------

func on_state(_d: Dictionary, _entered: bool) -> void:
	pass


func on_secret(_d: Dictionary) -> void:
	pass


func on_event(_d: Dictionary) -> void:
	pass


func on_result(d: Dictionary) -> void:
	result_modal("SÜRE BİTTİ", GOLD, [], d)


func open_board() -> void:
	pass


# Hücredeki tahta şu an bu oyunda işe yarıyor mu (open_board bir şey açar mı)? Yaramıyorsa eylem düğmesi
# tahtaya bakınca "TAHTAYA YAZ" göstermez. Tahtası olan oyun bunu ezer.
func tahta_var() -> bool:
	return false


# Tahtaya bakınca eylem düğmesinin yazısı
func tahta_yazisi() -> String:
	return "Tahtaya yaz"


func banner() -> Array:
	return [str(state.get("title", "")), ""]


func help_rows() -> Array:
	return []


func show_card() -> void:
	pass


# HUD hedef işareti: gidilecek yer [ad, yazı, ikon, renk, sürekli?] ya da [] (game_ui.hedef açıklaması)
func hedef(_aradi: bool) -> Array:
	return []


# main.gd etkileşim hedefleri: [ad, dünya konumu, en uzak mesafe, düğme yazısı]
func targets(_cell: int) -> Array:
	return []


func do_action(_name: String) -> void:
	pass


func doors_open() -> bool:
	return false


# true: oyuncu oturduğu yerden kalkamaz (rulette masa)
func locks_seat() -> bool:
	return false


# Oyuna özel rehber ([{id, name}]; boşsa normal oyuncu listesi)
func contacts() -> Array:
	return []


# Rehberde ve aramada görünen ad ("" ise gerçek ad)
func contact_name(_id: int) -> String:
	return ""


func process(_delta: float) -> void:
	pass


# uzak oyuncunun gövdesi (yeniden) kuruldu (geç gelen / geri bağlanan): modun gizleme vb. ayarları ona da uygulanır
func on_remote_added(_id: int) -> void:
	pass


# oyun bitti ya da sıradakine geçildi: 3D eklentileri, sesleri temizle
func cleanup() -> void:
	pass


# ---------- yardımcılar ----------

func me() -> int:
	return int(g.my_id)


func phase() -> String:
	return str(state.get("phase", ""))


func pname(id) -> String:
	return g.net.player_name(int(id)) if g.net else tr("Oyuncu %d") % int(id)


func play(n: String, vol := 0.0) -> void:
	g._play(n, vol)


func flash(title: String, sub: String, col: Color, t := 1.6) -> void:
	g._flash(title, sub, col, t)


func root() -> Control:
	return g._root


func close_panel() -> void:
	if is_instance_valid(panel):
		panel.queue_free()
	panel = null


func close_card() -> void:
	if is_instance_valid(card):
		card.queue_free()
	card = null


func chalk(text: String, size: int, col := CHALK) -> Label:
	return OI.chalk_label(text, size, col)


func chalk_button(text: String, icon_kind: String, filled: bool, wd: float, h := 76.0, col := CHALK) -> Button:
	return OI.chalk_button(text, icon_kind, filled, wd, h, col)


# Rol kartı: oyunun rozeti, büyük başlık, (isteğe bağlı görsel), TEK cümle. Kendiliğinden kapanır, dokununca kapanır.
# _points: eski imza için duruyor; ekranda gösterilmez (puanlar maç sonuna kadar gizli, yazı az olsun).
func role_card(title: String, col: Color, body: String, _points := "", extra: Control = null) -> void:
	close_card()
	card = g.rol_karti(task, title, col, body, extra)


# Ahşap çerçeveli kara tahta penceresi (scripts/oyun_ici.gd). Dönen: [katman, içerik kutusu, tahta]
func chalk_modal(title: String, sub := "", bw := 1000.0) -> Array:
	close_panel()
	var m: Array = OI.chalk_board(root(), title, sub, bw)
	(m[2] as Button).pressed.connect(close_panel)
	panel = m[0]
	return [m[0], m[1], m[3]]


# Tebeşir çizimi (kutu, kisi, onay, daire, yildiz, ok, tac, ahize, tebesir, silgi, cizgi...).
func chalk_draw(kind: String, sz: Vector2, col := CHALK) -> Control:
	return OI.chalk_draw(kind, sz, col)


# Rol kartı eki: küçük etiket + kocaman değer (ör. "HATTIN" 3), solda isteğe bağlı ikon.
func big_value(small: String, value: String, col: Color, icon := "") -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UI.B_S)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	if icon != "":
		var ic := UI.icon(icon, 64)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -8)
	v.add_child(UI.title(small, UI.FS_KUCUK + 2, UI.METIN_SOLUK))
	v.add_child(UI.title(value, 60, col))
	h.add_child(v)
	return h


func chalk_sfx() -> void:
	play("tebesir_%d" % (randi() % 3 + 1), -6.0)


# Tur sonu ekranı (scripts/tur_sonu.gd): büyük sonuç başlığı, 1-2 satır ayrıntı, isteğe bağlı kısa liste
# ([{a, b, c, col, me}]) ve "SEN" kartında kendi sonucun (ben.msg). Puan yazmaz: puanlar maç sonuna kadar gizli.
# mood: kendi sonucun 1 iyi, -1 kötü, 0 belirsiz (kartın rengi ve sesi). Dönen: ekranın kendisi.
func result_modal(head: String, col: Color, lines: Array, d: Dictionary, items: Array = [], mood := 0) -> Control:
	g.clear_flashes()
	close_panel()
	close_card()
	g._clear(g._overlay)
	var ts = load("res://scripts/tur_sonu.gd").new()
	ts.setup(d, me(), head, col, lines, items, mood)
	root().add_child(ts)
	g._overlay = ts
	return ts


func label(text: String, size := 22, col := Color.WHITE) -> Label:
	var l := UI.label(text, size, col, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 620
	return l


# Ekranı bir an bir renge boyar (patlama, vuruş).
func screen_flash(col: Color, peak: float, t_in: float, t_out: float) -> ColorRect:
	var f := ColorRect.new()
	f.color = Color(col, 0.0)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root().add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "color:a", peak, t_in)
	tw.tween_property(f, "color:a", 0.0, t_out)
	tw.tween_callback(f.queue_free)
	return f


# Alt ortadaki büyük düğme (TAHTA, SAYI YAZ...): game_ui'nin düğmesi kullanılır.
func show_main_button(text: String, on: bool) -> void:
	g._write_btn.visible = on
	if on:
		UI.set_button_text(g._write_btn, text)


# Büyük harf (Türkçede i → İ, ı → I).
static func up(s: String) -> String:
	return Dil.buyuk(s)


# Türkçe ekler (ünlü uyumu): Ali'ye, Bora'da, Cem'in, Fatih'ten...
static func _last_vowel(s: String) -> String:
	var low := s.replace("I", "ı").replace("İ", "i").to_lower()
	for i in range(low.length() - 1, -1, -1):
		if low[i] in "aeıioöuü":
			return low[i]
	return "e"


static func _ends_vowel(s: String) -> bool:
	return s != "" and s.replace("I", "ı").replace("İ", "i").to_lower()[s.length() - 1] in "aeıioöuü"


static func _hard(s: String) -> bool:
	return s != "" and s.to_lower()[s.length() - 1] in "fstkçşhp"


# İngilizcede ek yok: ad olduğu gibi döner (şablon "Run from %s!" gibi çevrilir).
static func dat(s: String) -> String:  # yönelme: Ali'ye
	if not Dil.tr_mi():
		return s
	var v := "a" if _last_vowel(s) in "aıou" else "e"
	return s + "'" + ("y" if _ends_vowel(s) else "") + v


static func loc(s: String) -> String:  # bulunma: Ali'de
	if not Dil.tr_mi():
		return s
	var v := "a" if _last_vowel(s) in "aıou" else "e"
	return s + "'" + ("t" if _hard(s) else "d") + v


static func abl(s: String) -> String:  # ayrılma: Ali'den
	if not Dil.tr_mi():
		return s
	return loc(s) + "n"


static func gen(s: String) -> String:  # ilgi: Ali'nin
	if not Dil.tr_mi():
		return s
	var lv := _last_vowel(s)
	var v: String = {"a": "ı", "ı": "ı", "o": "u", "u": "u", "e": "i", "i": "i", "ö": "ü", "ü": "ü"}.get(lv, "i")
	return s + "'" + ("n" if _ends_vowel(s) else "") + v + "n"


func _auto_close_card(card_id: int) -> void:
	if is_instance_valid(card) and card.get_instance_id() == card_id:
		close_card()
