# Tur sonu ekranı: her mini oyunun sonunda açılan tek, ortak sonuç ekranı.
# Puanlar maç sonuna kadar GİZLİ: burada kimsenin puanı (kendininki dahil) yazmaz, sadece ne olduğu anlatılır.
# Üstte oyunun adı ve büyük sonuç başlığı (ör. "YALANCI DENİZ YAKALANDI!"), altında 1-2 satır ayrıntı,
# ortada isteğe bağlı kısa bir liste (hatlar, eller, oylar...), "SEN" kartında kendi sonucun (cümleyle),
# altta sıradaki oyun, geri sayım ve TAMAM.
# Kullanım: var t = load("res://scripts/tur_sonu.gd").new(); t.setup(d, my_id, baslik, renk, satirlar, liste, duygu)
#   liste: [{a, b, c, col, me}] (a: altın etiket, b: beyaz, c: renkli sonuç), duygu: 1 iyi, -1 kötü, 0 nötr
extends Control

signal closed

const UI := preload("res://scripts/ui.gd")
const Dil := preload("res://scripts/dil.gd")
const GREEN := Color("#5be37d")
const RED := Color("#ff5a5a")
const GOLD := Color("#ffcf8a")
const TEAL := Color("#5ff0ff")
const MUTED := Color(0.78, 0.8, 0.88)

var data: Dictionary = {}
var my_id := 0
var head := ""
var head_col := GOLD
var lines: Array = []
var items: Array = []
var mood := 0

var _sz := Vector2(1280, 720)
var _item_nodes: Array = []
var _me_card: Control
var _count_label: Label
var _left := 0.0
var _closing := false


func setup(d: Dictionary, me: int, title: String, col: Color, detail: Array, list: Array = [], feel := 0) -> void:
	data = d
	my_id = me
	head = title
	head_col = col
	lines = detail.filter(func(x) -> bool: return str(x) != "")
	items = list
	mood = feel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sz = get_viewport_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.015, 0.035, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# başlığın arkasında oyunun renginde hafif bir parıltı
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var gr := Gradient.new()
	gr.set_color(0, Color(head_col, 0.22))
	gr.set_color(1, Color(head_col, 0.0))
	gt.gradient = gr
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.position = Vector2(_sz.x / 2.0 - 520.0, -150.0)
	glow.size = Vector2(1040, 420)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	var y := 20.0
	# oyunun adı: küçük, altın renkli bir şerit
	var game := UI.title(_up(str(data.get("title", ""))), 22, GOLD, true)
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(1, 0.75, 0.3, 0.12)
	gs.set_corner_radius_all(14)
	gs.content_margin_left = 18
	gs.content_margin_right = 18
	gs.content_margin_top = 2
	gs.content_margin_bottom = 2
	game.add_theme_stylebox_override("normal", gs)
	add_child(game)
	game.reset_size()
	game.position = Vector2((_sz.x - game.size.x) / 2.0, y)
	y += 44.0
	# büyük sonuç başlığı
	var hs := _fit(head, 60, _sz.x - 80.0)
	var hl := UI.title(head, hs, head_col, true)
	hl.position = Vector2(20, y)
	hl.size = Vector2(_sz.x - 40, hs + 16)
	hl.pivot_offset = hl.size / 2.0
	add_child(hl)
	hl.scale = Vector2.ONE * 1.6
	hl.modulate.a = 0.0
	var htw := hl.create_tween().set_parallel()
	htw.tween_property(hl, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	htw.tween_property(hl, "modulate:a", 1.0, 0.15)
	y += hs + 22.0
	# ayrıntı satırları
	for i in mini(2, lines.size()):
		var ll := UI.label(str(lines[i]), 23, MUTED, true)
		ll.position = Vector2(40, y)
		ll.size = Vector2(_sz.x - 80, 32)
		ll.clip_text = true
		ll.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ll.modulate.a = 0.0
		add_child(ll)
		var ltw := ll.create_tween()
		ltw.tween_interval(0.25 + 0.1 * i)
		ltw.tween_property(ll, "modulate:a", 1.0, 0.25)
		y += 32.0
	y += 18.0
	var bottom := _sz.y - 104.0
	var msg := _my_msg()
	var card_h := 70.0 if msg != "" else 0.0
	if not items.is_empty():
		_build_items(y, bottom - card_h - (16.0 if card_h > 0.0 else 0.0))
		y = bottom - card_h
	else:
		y = maxf(y, (y + bottom) / 2.0 - card_h / 2.0)
	if msg != "":
		_build_me_card(msg, y, card_h)
	_build_bottom()
	_play("anons", -6.0)
	_run()


# Kendi sonucun: sunucunun cümlesi; içinde puan sayısı varsa (ör. "(+1)") ekranda gösterilmez.
func _my_msg() -> String:
	var ben = data.get("ben")
	if typeof(ben) != TYPE_DICTIONARY:
		return ""
	var msg := Dil.sunucu(ben as Dictionary, "msg")  # sunucunun Türkçe cümlesi oyunun diline çevrilir
	var re := RegEx.new()
	re.compile("\\s*\\(?[+\\-−]\\s?\\d+\\s*(puan|PUAN)?\\)?")
	msg = re.sub(msg, "", true).strip_edges()
	return msg


# ---------- orta liste (hatlar, eller, oylar...) ----------

func _build_items(top: float, bottom: float) -> void:
	var n := mini(items.size(), 8)
	var gap := 8.0
	var rh := clampf((bottom - top - gap * (n - 1)) / maxf(1.0, n), 34.0, 52.0)
	var lw := minf(_sz.x - 80.0, 760.0)
	var x0 := (_sz.x - lw) / 2.0
	var total_h := rh * n + gap * (n - 1)
	var y := top + maxf(0.0, (bottom - top - total_h) / 2.0)
	var fs := int(clampf(rh * 0.5, 18, 26))
	for i in n:
		var it: Dictionary = items[i]
		var me := bool(it.get("me", false))
		var row := Panel.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.05, 0.16, 0.19, 0.95) if me else Color(0.09, 0.09, 0.14, 0.92)
		st.border_color = TEAL if me else Color(1, 1, 1, 0.08)
		st.set_border_width_all(2 if me else 1)
		st.set_corner_radius_all(12)
		row.add_theme_stylebox_override("panel", st)
		row.position = Vector2(x0, y)
		row.size = Vector2(lw, rh)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.modulate.a = 0.0
		add_child(row)
		var a := UI.title(str(it.get("a", "")), fs, GOLD)
		a.position = Vector2(20, 0)
		a.size = Vector2(lw * 0.24, rh)
		a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		a.clip_text = true
		row.add_child(a)
		var b := UI.title(str(it.get("b", "")), fs, TEAL if me else Color.WHITE)
		b.position = Vector2(20 + lw * 0.25, 0)
		b.size = Vector2(lw * 0.42, rh)
		b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(b)
		var ccol: Color = it.get("col", Color.WHITE)
		var c := UI.title(str(it.get("c", "")), fs, ccol)
		c.position = Vector2(lw * 0.68, 0)
		c.size = Vector2(lw * 0.32 - 20, rh)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.clip_text = true
		row.add_child(c)
		_item_nodes.append(row)
		y += rh + gap


func _build_me_card(msg: String, y: float, h: float) -> void:
	var w := minf(_sz.x - 80.0, 820.0)
	var col := GREEN if mood > 0 else (RED if mood < 0 else TEAL)
	var card := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(col.r * 0.18, col.g * 0.18, col.b * 0.18, 0.95)
	st.border_color = col
	st.set_border_width_all(2)
	st.set_corner_radius_all(16)
	st.shadow_color = Color(col, 0.3)
	st.shadow_size = 12
	card.add_theme_stylebox_override("panel", st)
	card.position = Vector2((_sz.x - w) / 2.0, y)
	card.size = Vector2(w, h)
	card.pivot_offset = card.size / 2.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.modulate.a = 0.0
	add_child(card)
	var tag := UI.title("SEN", 22, Color(0.05, 0.05, 0.08), true)
	tag.add_theme_constant_override("outline_size", 0)
	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	var ts := StyleBoxFlat.new()
	ts.bg_color = col
	ts.set_corner_radius_all(10)
	tag.add_theme_stylebox_override("normal", ts)
	tag.position = Vector2(14, 14)
	tag.size = Vector2(70, h - 28)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(tag)
	var ml := UI.title(msg, _fit(msg, 26, w - 120.0), Color.WHITE, true)
	ml.position = Vector2(96, 0)
	ml.size = Vector2(w - 112, h)
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ml.clip_text = true
	ml.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(ml)
	_me_card = card


# ---------- alt kısım: sıradaki oyun, geri sayım, TAMAM ----------

func _build_bottom() -> void:
	var y := _sz.y - 84.0
	var nx := str(data.get("sonraki", ""))
	var ok := UI.button("TAMAM", "primary", 62, 24, "", 230)
	ok.position = Vector2(_sz.x / 2.0 + 120.0, y + 4)
	ok.pressed.connect(close)
	add_child(ok)
	if nx != "":
		var sl := UI.label("SIRADAKİ OYUN", 16, MUTED)
		sl.position = Vector2(_sz.x / 2.0 - 400.0, y + 4)
		sl.size = Vector2(360, 22)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(sl)
		var nl := UI.title(_up(nx), 30, GOLD)
		nl.position = Vector2(_sz.x / 2.0 - 400.0, y + 24)
		nl.size = Vector2(360, 40)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(nl)
	_left = float(data.get("sonuc_sure", 0))
	if _left > 0.0:
		_count_label = UI.title(str(int(ceil(_left))), 30, Color.WHITE, true)
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(1, 1, 1, 0.08)
		cs.border_color = Color(1, 1, 1, 0.35)
		cs.set_border_width_all(2)
		cs.set_corner_radius_all(100)
		_count_label.add_theme_stylebox_override("normal", cs)
		_count_label.position = Vector2(_sz.x / 2.0 + 20.0, y + 8)
		_count_label.size = Vector2(56, 56)
		_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_count_label)


func _process(delta: float) -> void:
	if _left <= 0.0 or _closing:
		return
	var before := int(ceil(_left))
	_left -= delta
	var now := int(ceil(maxf(0.0, _left)))
	if now != before and is_instance_valid(_count_label):
		_count_label.text = str(now)
		if now <= 3 and now > 0:
			_play("tik", -10.0)
	if _left <= 0.0:
		close()


func close() -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())


# ---------- animasyon ----------

# Güvenli bekleme: ekran bu arada kapandıysa (sahneden çıktıysa) false döner, açılış durur.
func _wait(t: float) -> bool:
	if not is_inside_tree():
		return false
	# ekran kısa süre açık kalacaksa (hızlı oyun) animasyon da hızlanır
	var sure := float(data.get("sonuc_sure", 0))
	var k := clampf(sure / 6.0, 0.4, 1.0) if sure > 0.0 else 1.0
	await get_tree().create_timer(t * k).timeout
	return is_inside_tree()


func _run() -> void:
	if not await _wait(0.45):
		return
	for row in _item_nodes:
		if not is_inside_tree() or not is_instance_valid(row):
			return
		var r: Control = row
		var x0 := r.position.x
		r.position.x = x0 + 50.0
		var tw := r.create_tween().set_parallel()
		tw.tween_property(r, "position:x", x0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(r, "modulate:a", 1.0, 0.2)
		_play("tik_ui", -8.0)
		if not await _wait(0.12):
			return
	if is_instance_valid(_me_card) and is_inside_tree():
		if not await _wait(0.2):
			return
		_me_card.scale = Vector2.ONE * 0.85
		var ctw := _me_card.create_tween().set_parallel()
		ctw.tween_property(_me_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ctw.tween_property(_me_card, "modulate:a", 1.0, 0.2)
		if mood > 0:
			_play("odul", -4.0)
		elif mood < 0:
			_play("hata", -5.0, 0.85)
		else:
			_play("parilti", -6.0)


func _play(n: String, vol := 0.0, pitch := 1.0) -> void:
	var path := "res://assets/ses/%s.ogg" % n
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = vol
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


static func _fit(text: String, size: int, w: float) -> int:
	var s := size
	while s > 18 and UI.TITLE_FONT.get_string_size(TranslationServer.translate(text), HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > w:
		s -= 2
	return s


# Oyunun diline çevir, sonra büyük harf (Türkçede i → İ, ı → I).
static func _up(s: String) -> String:
	return Dil.buyuk(Dil.t(s))
