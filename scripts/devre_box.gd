# Kısa Devre: hapishane sigorta kutusunun içi (tam ekran yakın çekim).
# Paslı kapak açılır; solda kablo kanalından rakorlarla çıkan 4 kalın kablo (fiziksel, sarkan, parmağı izleyen),
# sağda sembol + numara plakalı 4 priz, üstte 3 cam sigorta (hak), sağda ana şalter.
# Kabloyu tut -> prize yaklaştır (mıknatıs gibi çekilir) -> bırak. Doğruysa "klik" + yeşil ışık;
# yanlışsa elektrik çarpar: flaş, sarsıntı, kıvılcım, bir cam sigorta patlar, kablo geri fırlar.
# 4 kablo takılınca şalteri yukarı sürükle: güç gelir. Sonuç sunucudan gelir (set_result).
# Her şey tek bir Control'de 1200x680'lik tasarım düzleminde çizilir, ekrana ölçeklenir.
extends Control

signal action(v: Dictionary)
signal closed

const UI := preload("res://scripts/ui.gd")
const COLORS := {
	"KIRMIZI": "#d8262a", "MAVİ": "#1f6fe0", "SARI": "#f2c514", "YEŞİL": "#23a63c", "MOR": "#8a3fc4", "TURUNCU": "#f07a0a",
}
const DIR := "res://assets/ui/devre/"
const SES := "res://assets/ses/devre/"

# ---- tasarım düzlemi ----
const W := 1200.0
const H := 680.0
const FRAME := 24.0
const ROWS := [196.0, 320.0, 444.0, 568.0]
const GLAND := Vector2(150, 0)  # rakor merkezi (y satırdan)
const CABLE_X := 206.0  # kablonun rakordan çıktığı yer
const SOCK_X := 690.0
const PLATE_X := 830.0  # plaka merkezi
const LEVER_X := 1062.0
const LEVER_TOP := 352.0  # şalter kolunun üst / alt konumu
const LEVER_BOT := 540.0
const LAMP := Vector2(1062, 132)
const FUSE_Y := 98.0
const FUSE_X := [118.0, 262.0, 406.0]
const PLUG_LEN := 118.0
const N := 18  # kablo noktası
const REST_DIR := Vector2(0.985, 0.17)  # boştaki fişin yatış yönü

var code := "K7"
var wires: Array = []  # renkler (yukarıdan aşağı)
var symbols: Array = []  # priz sembolleri (yukarıdan aşağı; numarası = sırası + 1)
var steps := 4
var done_steps := 0
var status := "acik"  # acik, tamir, kilit
var connected := {}  # renk -> sembol (sunucunun onayladığı)
var lives := 3

var _tex := {}
var _ropes := {}  # renk -> {pts, old, end, vel, dir}
var _drag := ""  # tutulan kablo
var _picked := ""  # dokun-dokun: seçili kablo
var _press_pos := Vector2.ZERO
var _finger := Vector2.ZERO
var _pending: Array = []  # [renk, sembol]
var _hover := -1  # mıknatısın çektiği priz
var _lever := 0.0  # 0 aşağı, 1 yukarı
var _lever_drag := false
var _lever_grab := 0.0
var _lever_sent := 0.0  # gönderildiği an (0: gönderilmedi)
var _t := 0.0
var _shake := 0.0
var _flash := 0.0
var _flash_col := Color.WHITE
var _sparks: Array = []  # {p, v, life, max, col, w}
var _smoke: Array = []  # {p, v, life, max, r}
var _sock_on := {}  # priz no -> yandığı an
var _fuse_blow := {}  # sigorta no -> patladığı an
var _power_t := -1.0  # güç geldi gösterisi
var _end_t := -1.0  # sonuç yazısı (ONARDIN / YANDI)
var _door := 0.0  # kapak açılışı 0..1
var _idle := 0.0
var _xf := Transform2D.IDENTITY
var _font: Font
# Sabit arka plan (kasa, kanal, montaj levhası, vidalar) bir kez dokuya çizilir: her karede ~yüz çizim çağrısı
# yerine tek doku. Karartma perdesi ve doku, kutunun kendi çiziminin arkasında (show_behind_parent) durur.
var _c: CanvasItem = self  # _draw_box'ın çizdiği tuval (önbellek kurulurken dokunun tuvali)
var _ov: ColorRect
var _bg_vp: SubViewport
var _bg_canvas: Control
var _bg_rect: TextureRect
var _bg_xf := Transform2D.IDENTITY
var _bg_key := []


static func color_of(n: String) -> Color:
	return Color(COLORS.get(n, "#888888"))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = UI.TITLE_FONT
	_ov = ColorRect.new()
	_ov.color = Color(0, 0, 0, 0.82)
	_ov.show_behind_parent = true
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ov)
	_bg_vp = SubViewport.new()
	_bg_vp.transparent_bg = true
	_bg_vp.disable_3d = true
	_bg_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_bg_vp)
	_bg_canvas = Control.new()
	_bg_canvas.draw.connect(_paint_bg)
	_bg_vp.add_child(_bg_canvas)
	_bg_rect = TextureRect.new()
	_bg_rect.texture = _bg_vp.get_texture()
	_bg_rect.show_behind_parent = true
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA  # dokudaki saydam katmanlar doğrudan çizilmiş gibi karışsın
	_bg_rect.material = pm
	add_child(_bg_rect)
	for n in ["zemin", "kapak", "priz", "fis", "plaka", "sigorta", "sigorta_yanik", "salter_govde", "salter_kol", "rakor"]:
		_tex[n] = load(DIR + n + ".png")
	for i in 3:
		if i >= lives:
			_fuse_blow[i] = -10.0
	for i in wires.size():
		var w: String = wires[i]
		var a := _anchor(i)
		var e := _rest(i)
		if connected.has(w):
			e = _sock(symbols.find(connected[w]))
			_sock_on[symbols.find(connected[w])] = -10.0
		var pts := PackedVector2Array()
		for k in N:
			pts.append(a.lerp(e, float(k) / (N - 1)))
		_ropes[w] = {"pts": pts, "old": pts.duplicate(), "end": e, "vel": Vector2.ZERO, "dir": Vector2(1, 0.15).normalized()}
	if status == "tamir":
		_lever = 1.0
		_power_t = 10.0
	elif status == "kilit":
		for i in 3:
			_fuse_blow[i] = -10.0
	_play("kapak", -4.0)


# ---------- konumlar ----------

func _anchor(i: int) -> Vector2:
	return Vector2(CABLE_X, ROWS[i])


func _rest(i: int) -> Vector2:
	return Vector2(CABLE_X + 150, ROWS[i] + 22)


func _sock(j: int) -> Vector2:
	return Vector2(SOCK_X, ROWS[clampi(j, 0, 3)])


func _lever_y() -> float:
	return lerpf(LEVER_BOT, LEVER_TOP, _lever)


func _ready_lever() -> bool:
	return status == "acik" and done_steps >= steps


func _to_local(p: Vector2) -> Vector2:
	return _xf.affine_inverse() * p


# ---------- giriş ----------

func _gui_input(e: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = _to_local(e.position)
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventMouseMotion:
		pos = _to_local(e.position)
		_finger = pos
		if _lever_drag:
			_drag_lever(pos)
		accept_event()
		return
	else:
		return
	accept_event()
	_finger = pos
	_idle = 0.0
	if pressed:
		if pos.distance_to(Vector2(W - 6, 6)) < 46.0:
			closed.emit()
			return
		if _door < 0.9:
			return
		# şalter kolu
		if Rect2(LEVER_X - 80, _lever_y() - 80, 160, 130).has_point(pos):
			_lever_drag = true
			_lever_grab = pos.y - _lever_y()
			return
		if status != "acik" or not _pending.is_empty():
			return
		var w := _plug_at(pos)
		if w != "":
			_drag = w
			_press_pos = pos
			_play("tut", -10.0)
			_vibrate(15)
			return
		if _picked != "":
			var j := _socket_at(pos, 90.0)
			if j >= 0:
				_drop(_picked, j)
			_picked = ""
	elif released:
		if _lever_drag:
			_lever_drag = false
			_release_lever()
			return
		if _drag != "":
			var w2 := _drag
			_drag = ""
			if pos.distance_to(_press_pos) < 12.0:
				_picked = w2  # dokunup bıraktı: şimdi prize dokunsun
				return
			if _hover >= 0:
				_drop(w2, _hover)
			else:
				_play("klik", -14.0)
			_hover = -1


func _plug_at(p: Vector2) -> String:
	var best := ""
	var bd := 72.0
	for w in _ropes:
		if connected.has(w) or (_pending.size() == 2 and _pending[0] == w):
			continue
		var r: Dictionary = _ropes[w]
		var grip: Vector2 = r.end + (r.dir as Vector2) * PLUG_LEN * 0.4
		var d := minf(p.distance_to(grip), p.distance_to(r.end))
		if d < bd:
			bd = d
			best = w
	return best


func _socket_at(p: Vector2, rad: float) -> int:
	for j in symbols.size():
		if p.distance_to(_sock(j)) < rad and not _sock_busy(j):
			return j
	return -1


func _sock_busy(j: int) -> bool:
	var s: String = symbols[j]
	return s in connected.values() or (_pending.size() == 2 and _pending[1] == s)


func _drop(w: String, j: int) -> void:
	if status != "acik" or connected.has(w) or _sock_busy(j):
		return
	_try_connect(w, symbols[j])


# Kablo prize takıldı: sunucuya sor; cevap gelene kadar fiş prizde bekler.
func _try_connect(renk: String, sembol: String) -> void:
	if status != "acik" or connected.has(renk) or sembol in connected.values() or not _ropes.has(renk):
		return
	_pending = [renk, sembol]
	_picked = ""
	_play("klik", -2.0)
	_vibrate(25)
	_burst(_sock(symbols.find(sembol)), 10, Color(1, 0.85, 0.5), 260.0)
	action.emit({"islem": "bagla", "renk": renk, "sembol": sembol})


func _drag_lever(p: Vector2) -> void:
	var y := clampf(p.y - _lever_grab, LEVER_TOP, LEVER_BOT)
	var k := inverse_lerp(LEVER_BOT, LEVER_TOP, y)
	if not _ready_lever():
		k = minf(k, 0.08)  # kablolar bitmeden kol kalkmaz: biraz oynar, geri düşer
	_lever = k


func _release_lever() -> void:
	if _ready_lever() and _lever > 0.75 and _lever_sent == 0.0:
		pull_lever()
	elif not _ready_lever() and status == "acik":
		_play("vizilti", -12.0)


# Şalter yukarı: sunucuya bildir (otomatik test de bunu çağırır).
func pull_lever() -> void:
	if not _ready_lever() or _lever_sent > 0.0:
		return
	_lever = 1.0
	_lever_sent = _t
	_play("salter", 0.0)
	_shake = maxf(_shake, 0.25)
	_vibrate(60)
	_burst(Vector2(LEVER_X, LEVER_TOP - 20), 26, Color(1, 0.9, 0.55), 420.0)
	action.emit({"islem": "salter"})


# ---------- sunucunun cevabı ----------

# olay: adim (doğru), tamir (şalter kalktı), yanlis / kilit (kısa devre).
func set_result(olay: String, adim: int, renk := "", sembol := "", hak := -1) -> void:
	done_steps = adim
	if renk == "" and _pending.size() == 2:
		renk = _pending[0]
		sembol = _pending[1]
	var blown := hak >= 0 and hak < lives
	if hak >= 0:
		lives = hak
	match olay:
		"adim":
			if renk != "" and _ropes.has(renk):
				connected[renk] = sembol
				var j := symbols.find(sembol)
				_sock_on[j] = _t
				_ropes[renk].end = _sock(j)
				_burst(_sock(j), 18, Color(0.55, 1.0, 0.6), 300.0)
				_play("klik", 0.0)
				_play("bip", -14.0)
				_vibrate(35)
			if _ready_lever():
				_play("salter", -14.0)
		"tamir":
			if renk != "" and _ropes.has(renk) and not connected.has(renk):
				connected[renk] = sembol
			status = "tamir"
			_lever = 1.0
			_power_t = 0.0
			_play("guc", 0.0)
		"yanlis", "kilit":
			if renk != "" and _ropes.has(renk) and not connected.has(renk):
				_shock(renk, sembol)
			elif blown:
				_blow_fuse()
			if olay == "kilit":
				for i in 3:
					if not _fuse_blow.has(i):
						_fuse_blow[i] = _t + 0.25
				status = "kilit"
				_end_t = 0.0
				_play("vizilti", -4.0)
	_pending = []
	queue_redraw()


# Elektrik çarpması: flaş, sarsıntı, kıvılcım, sigorta patlar, kablo geri fırlar.
func _shock(renk: String, sembol: String) -> void:
	var j := symbols.find(sembol)
	var p := _sock(j)
	_flash = 1.0
	_flash_col = Color(0.85, 0.92, 1.0)
	_shake = 0.55
	_burst(p, 70, Color(1, 0.92, 0.6), 900.0)
	_burst(p, 30, Color(0.6, 0.85, 1.0), 600.0)
	for k in 6:
		_smoke.append({"p": p + Vector2(randf_range(-20, 20), randf_range(-10, 10)), "v": Vector2(randf_range(-30, 30), randf_range(-90, -50)), "life": 0.0, "max": randf_range(0.9, 1.5), "r": randf_range(18, 34)})
	var r: Dictionary = _ropes[renk]
	r.vel = Vector2(randf_range(-1400, -1000), randf_range(-700, -300))
	_blow_fuse()
	_play("carpma", 2.0)
	_vibrate(400)


func _blow_fuse() -> void:
	var i := clampi(lives, 0, 2)
	if _fuse_blow.has(i):
		return
	_fuse_blow[i] = _t
	var p := Vector2(FUSE_X[i], FUSE_Y)
	_burst(p, 40, Color(1, 0.75, 0.35), 520.0)
	for k in 14:  # cam kırıkları
		_sparks.append({"p": p, "v": Vector2(randf_range(-260, 260), randf_range(-380, -60)), "life": 0.0, "max": randf_range(0.5, 0.9), "col": Color(0.85, 0.95, 1.0, 0.9), "w": 5.0, "cam": true})
	for k in 5:
		_smoke.append({"p": p, "v": Vector2(randf_range(-25, 25), randf_range(-70, -40)), "life": 0.0, "max": randf_range(1.2, 2.0), "r": randf_range(14, 26)})
	get_tree().create_timer(0.12).timeout.connect(func() -> void: _play("sigorta", 0.0))


func _burst(p: Vector2, n: int, col: Color, speed: float) -> void:
	for k in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(0.25, 1.0) * speed
		_sparks.append({"p": p, "v": v, "life": 0.0, "max": randf_range(0.25, 0.6), "col": col, "w": randf_range(2.0, 4.0)})


# ---------- yardımcılar ----------

func _play(n: String, vol := 0.0) -> void:
	var path := SES + n + ".ogg"
	if not ResourceLoader.exists(path):
		path = "res://assets/ses/%s.ogg" % n
		if not ResourceLoader.exists(path):
			return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _vibrate(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ---------- fizik ----------

func _process(delta: float) -> void:
	# zamanlayıcılar gerçek süreyle, fizik (kablo, kıvılcım) sabit adımla ilerler
	var rt := minf(delta, 0.25)
	var dt := minf(delta, 1.0 / 30.0)
	_t += rt
	_idle += rt
	_door = minf(1.0, _door + rt / 0.5)
	_shake = maxf(0.0, _shake - rt)
	_flash = maxf(0.0, _flash - rt * 3.5)
	if _power_t >= 0.0:
		_power_t += rt
		if _power_t > 0.9 and _end_t < 0.0:
			_end_t = 0.0
			_flash = 0.45
			_flash_col = Color(1.0, 0.95, 0.7)
	if _end_t >= 0.0:
		_end_t += rt
	# şalter: kalkmadıysa geri düşer; gönderildi ama cevap yoksa (bağlantı) 3 sn sonra yine düşer
	if not _lever_drag and status != "tamir":
		if _lever_sent > 0.0 and _t - _lever_sent > 3.0:
			_lever_sent = 0.0
		if _lever_sent == 0.0:
			_lever = move_toward(_lever, 0.0, dt * 5.0)
	# mıknatıs: tutulan fiş boş bir prize yaklaşınca
	_hover = -1
	if _drag != "":
		_hover = _socket_at(_finger, 95.0)
	for i in wires.size():
		_step_rope(i, dt)
	# kıvılcımlar ve duman
	for s in _sparks:
		s.life += dt
		s.v.y += 1500.0 * dt
		s.v *= 0.985
		s.p += s.v * dt
	_sparks = _sparks.filter(func(s: Dictionary) -> bool: return s.life < s.max)
	for s in _smoke:
		s.life += dt
		s.p += s.v * dt
	_smoke = _smoke.filter(func(s: Dictionary) -> bool: return s.life < s.max)
	if status == "kilit" and randf() < dt * 3.0:  # yanık kutu ara ara çıtırdar
		_burst(_sock(randi() % 4), 6, Color(1, 0.7, 0.3), 240.0)
	# ekrana sığdır (sarsıntı dahil)
	var sc := minf(size.x / (W + 90.0), size.y / (H + 76.0))
	var off := (size - Vector2(W, H) * sc) / 2.0
	var base := Transform2D(0.0, Vector2(sc, sc), 0.0, off)
	if _shake > 0.0:
		off += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 22.0 * _shake
	_xf = Transform2D(0.0, Vector2(sc, sc), 0.0, off)
	var key := [size, base]
	if key != _bg_key:
		# boyut değişince arka plan dokusu yeniden çizilir (ekran ölçeğinde, piksel piksel)
		_bg_key = key
		_bg_xf = base
		_bg_vp.size = Vector2i(ceili(size.x), ceili(size.y))
		_bg_canvas.size = Vector2(_bg_vp.size)
		_bg_rect.size = Vector2(_bg_vp.size)
		_bg_canvas.queue_redraw()
		_bg_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_bg_rect.position = off - base.origin  # sarsıntı
	queue_redraw()


func _step_rope(i: int, dt: float) -> void:
	var w: String = wires[i]
	var r: Dictionary = _ropes[w]
	var a := _anchor(i)
	var end: Vector2 = r.end
	if connected.has(w):
		end = end.lerp(_sock(symbols.find(connected[w])), 1.0 - exp(-dt * 30.0))
		r.vel = Vector2.ZERO
	elif _pending.size() == 2 and _pending[0] == w:
		end = end.lerp(_sock(symbols.find(_pending[1])), 1.0 - exp(-dt * 30.0))
		r.vel = Vector2.ZERO
	elif _drag == w:
		var target := _finger - (r.dir as Vector2) * PLUG_LEN * 0.45
		if _hover >= 0:
			target = _sock(_hover)  # mıknatıs: prize çekilir
		end = end.lerp(target, 1.0 - exp(-dt * (34.0 if _hover >= 0 else 24.0)))
		r.vel = Vector2.ZERO
	else:
		# serbest: yay gibi dinlenme yerine döner (yanlışta önce geri fırlar)
		var v: Vector2 = r.vel
		v += (_rest(i) - end) * 90.0 * dt
		v *= exp(-dt * 7.0)
		end += v * dt
		r.vel = v
	end.x = clampf(end.x, FRAME + 10, W - FRAME - 10)
	end.y = clampf(end.y, FRAME + 10, H - FRAME - 10)
	r.end = end
	# verlet: uzunluk uçlar arası mesafeye göre (kablo rakordan uzar/çekilir), hafif sarkma
	var pts: PackedVector2Array = r.pts
	var old: PackedVector2Array = r.old
	var length := maxf(a.distance_to(end) * 1.045 + 14.0, 60.0)
	var seg := length / (N - 1)
	var g := Vector2(0, 1800.0) * dt * dt
	var free: bool = not connected.has(w) and _drag != w and not (_pending.size() == 2 and _pending[0] == w) and (r.vel as Vector2).length() < 60.0
	for k in range(1, N - 1):
		var cur := pts[k]
		pts[k] = cur + (cur - old[k]) * 0.94 + g
		old[k] = cur
	for it in 14:
		pts[0] = a
		pts[N - 1] = end
		# rakordan çıkış yönü: ilk parça hep sağa bakar
		pts[1] = pts[1].lerp(a + Vector2(seg, 0), 0.5)
		if free:
			pts[N - 2] = pts[N - 2].lerp(end - REST_DIR * seg, 0.5)  # fiş kılıfı sert: yerde yatık durur
		for k in N - 1:
			var d := pts[k + 1] - pts[k]
			var l := d.length()
			if l < 0.001:
				continue
			var diff := (l - seg) / l * 0.5
			if k > 0:
				pts[k] += d * diff
			if k + 1 < N - 1:
				pts[k + 1] -= d * diff
	pts[0] = a
	pts[N - 1] = end
	r.pts = pts
	r.old = old
	var dd := end - pts[N - 3]
	if dd.length() > 1.0:
		r.dir = (r.dir as Vector2).lerp(dd.normalized(), 0.35).normalized()


# ---------- çizim ----------

func _draw() -> void:
	draw_set_transform_matrix(_xf)
	_draw_fuses()
	_draw_lamp()
	_draw_sockets()
	_draw_lever()
	_draw_hint()
	# kablolar: takılı olanlar altta, tutulan en üstte
	var order: Array = []
	for w in wires:
		if connected.has(w):
			order.append(w)
	for w in wires:
		if not connected.has(w) and w != _drag:
			order.append(w)
	if _drag != "":
		order.append(_drag)
	for w in order:
		_draw_cable(w)
	if status == "kilit":
		# yanık kutu: is ve karartı
		draw_rect(Rect2(Vector2(FRAME, FRAME), Vector2(W - FRAME * 2, H - FRAME * 2)), Color(0.04, 0.02, 0.0, 0.38))
	_draw_fx()
	_draw_door()
	_draw_close()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_col, _flash * 0.55))
	draw_set_transform_matrix(_xf)
	_draw_end()


func _tex_rect(n: String, center: Vector2, h: float, mod := Color.WHITE) -> void:
	var t: Texture2D = _tex.get(n)
	if not t:
		return
	var w := h * t.get_width() / float(t.get_height())
	_c.draw_texture_rect(t, Rect2(center - Vector2(w, h) / 2.0, Vector2(w, h)), false, mod)


func _paint_bg() -> void:
	_c = _bg_canvas
	_bg_canvas.draw_set_transform_matrix(_bg_xf)
	_draw_box()
	_draw_static_parts()
	_c = self


func _draw_box() -> void:
	# dış çerçeve: kalın, boyalı, köşeleri yuvarlatılmış çelik kasa
	var outer := Rect2(Vector2.ZERO, Vector2(W, H))
	_rrect(outer.grow(6), Color(0, 0, 0, 0.6), 26)
	_rrect(outer, Color("#2c3329"), 22)
	_rrect(outer.grow(-4), Color("#3b4536"), 20)
	_rrect(outer.grow(-FRAME + 6), Color("#1b201a"), 10)
	var inner := outer.grow(-FRAME)
	var zt: Texture2D = _tex.get("zemin")
	if zt:
		_c.draw_texture_rect(zt, inner, false, Color(0.92, 0.95, 0.9))
	# iç gölge: kapağın kenarından içeri düşen karanlık
	for k in 10:
		var a := 0.32 * (1.0 - k / 10.0)
		_c.draw_rect(Rect2(inner.position + Vector2(0, k * 3), Vector2(inner.size.x, 3)), Color(0, 0, 0, a))
		_c.draw_rect(Rect2(inner.position + Vector2(k * 3, 0), Vector2(3, inner.size.y)), Color(0, 0, 0, a * 0.8))
		_c.draw_rect(Rect2(Vector2(inner.end.x - (k + 1) * 3, inner.position.y), Vector2(3, inner.size.y)), Color(0, 0, 0, a * 0.5))
	# çerçeve vidaları
	for p in [Vector2(12, 12), Vector2(W - 12, H - 12), Vector2(12, H - 12), Vector2(W * 0.5, 12), Vector2(W * 0.5, H - 12)]:
		_bolt(p, 6.0)
	# sol: gri kablo kanalı (oluklu)
	var duct := Rect2(FRAME + 14, 150, 66, H - FRAME - 150 - 14)
	_rrect(duct.grow(3), Color(0, 0, 0, 0.35), 6)
	_rrect(duct, Color("#8d918c"), 5)
	_rrect(Rect2(duct.position + Vector2(8, 6), duct.size - Vector2(16, 12)), Color("#5c615c"), 4)
	for k in range(int(duct.position.y) + 14, int(duct.end.y) - 8, 18):
		_c.draw_rect(Rect2(duct.position.x, k, 8, 9), Color("#3f433f"))
		_c.draw_rect(Rect2(duct.end.x - 8, k, 8, 9), Color("#3f433f"))
	_c.draw_line(duct.position + Vector2(10, 0), Vector2(duct.position.x + 10, duct.end.y), Color(1, 1, 1, 0.12), 2)
	# sağ: şalter ve lamba için koyu montaj levhası
	var mp := Rect2(LEVER_X - 104, 74, 208, H - FRAME - 74 - 18)
	_rrect(mp.grow(4), Color(0, 0, 0, 0.4), 10)
	_rrect(mp, Color("#2a2f2b"), 8)
	_rrect(mp.grow(-3), Color("#353c36"), 7)
	for p in [mp.position + Vector2(14, 14), Vector2(mp.end.x - 14, mp.position.y + 14), mp.end - Vector2(14, 14), Vector2(mp.position.x + 14, mp.end.y - 14)]:
		_bolt(p, 6.0)
	# sarı-siyah tehlike şeridi (montaj levhasının altında)
	var hz := Rect2(mp.position.x + 30, mp.end.y - 38, mp.size.x - 60, 16)
	_c.draw_rect(hz, Color("#e2b41b"))
	var x := hz.position.x + 4.0
	while x + 12.0 < hz.end.x:
		_c.draw_line(Vector2(x, hz.end.y), Vector2(x + 12, hz.position.y), Color("#151515"), 6.0)
		x += 18.0


func _rrect(r: Rect2, col: Color, rad: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	_c.draw_style_box(sb, r)


func _bolt(p: Vector2, r: float) -> void:
	_c.draw_circle(p + Vector2(1, 2), r + 1.5, Color(0, 0, 0, 0.45))
	_c.draw_circle(p, r, Color("#7c827a"))
	_c.draw_circle(p - Vector2(r * 0.25, r * 0.25), r * 0.6, Color("#a3a99f"))
	_c.draw_line(p - Vector2(r * 0.7, -r * 0.2), p + Vector2(r * 0.7, -r * 0.2), Color("#3d423b"), 1.6)


# Sabit parçalar (önbellek dokusunda): porselen sigorta yuvası ve pirinç klipsler, lambanın gövdesi,
# rakorlar ve kanaldan çıkan kısa kablolar, şalter gövdesi. Hiçbiri sonradan çizilen hareketli parçaların
# üstüne binmez; çizim sırası korunur.
func _draw_static_parts() -> void:
	var base := Rect2(FRAME + 22, FUSE_Y - 44, 432, 88)
	_rrect(base.grow(4), Color(0, 0, 0, 0.4), 12)
	_rrect(base, Color("#d9d2c3"), 10)
	_rrect(base.grow(-4), Color("#c6bead"), 8)
	_c.draw_rect(Rect2(base.position + Vector2(10, base.size.y - 12), Vector2(base.size.x - 20, 4)), Color(0, 0, 0, 0.12))
	for i in 3:
		var c := Vector2(FUSE_X[i], FUSE_Y)
		for sx in [-1.0, 1.0]:
			var cp := c + Vector2(sx * 54, 0)
			_rrect(Rect2(cp - Vector2(9, 22), Vector2(18, 44)), Color("#8a6a2c"), 4)
			_rrect(Rect2(cp - Vector2(6, 19), Vector2(12, 38)), Color("#c9a04a"), 3)
	var p := LAMP
	_bolt(p + Vector2(-50, 0), 5.0)
	_bolt(p + Vector2(50, 0), 5.0)
	_c.draw_circle(p + Vector2(2, 4), 40, Color(0, 0, 0, 0.5))
	_c.draw_circle(p, 38, Color("#9aa09a"))
	_c.draw_circle(p, 33, Color("#55594f"))
	_draw_glands()
	_tex_rect("salter_govde", Vector2(LEVER_X, (LEVER_TOP + LEVER_BOT) / 2.0 + 10.0), 300.0)


func _draw_fuses() -> void:
	for i in 3:
		var c := Vector2(FUSE_X[i], FUSE_Y)
		var bt: float = _fuse_blow.get(i, -1.0)
		var blown := _fuse_blow.has(i) and _t >= bt
		var t: Texture2D = _tex.get("sigorta_yanik" if blown else "sigorta")
		if t:
			# dikey görsel yatay çizilir; iki görsel aynı kalınlıkta görünsün
			var thick := 38.0
			var ln := thick * t.get_height() / float(t.get_width())
			if not blown:
				ln = 140.0
				thick = ln * t.get_width() / float(t.get_height())
			draw_set_transform_matrix(_xf * Transform2D(PI / 2, c))
			draw_texture_rect(t, Rect2(Vector2(-thick / 2, -ln / 2), Vector2(thick, ln)), false)
			draw_set_transform_matrix(_xf)
			if not blown and status != "kilit":
				var gl := 0.18 + 0.08 * sin(_t * 3.0 + i)  # sağlam sigortanın teli hafifçe parlar
				draw_circle(c, 22, Color(1.0, 0.55, 0.15, gl * 0.5))
		if blown and _t - bt < 0.35:
			draw_circle(c, 60 * (1.0 - (_t - bt) / 0.35), Color(1, 0.9, 0.6, 0.7))


func _draw_lamp() -> void:
	# büyük pilot lamba: arızada kırmızı nabız, güç gelince yeşil
	var p := LAMP  # gövde önbellekte (_draw_static_parts)
	var col := Color("#ff2d1f")
	var lit := 0.5 + 0.5 * sin(_t * 6.0)
	if status == "tamir" and _power_t > 0.1:
		col = Color("#38ff6a")
		lit = 1.0
	elif status == "kilit":
		lit = 0.15 if randf() < 0.9 else 0.7
	var glass := col.darkened(0.6).lerp(col, lit)
	for k in 6:
		draw_circle(p, 30 + (6 - k) * 9.0 * lit, Color(col, 0.05 * lit))
	draw_circle(p, 28, glass)
	draw_circle(p, 18, glass.lightened(0.35 * lit))
	draw_circle(p + Vector2(-9, -10), 7, Color(1, 1, 1, 0.55))


func _draw_glands() -> void:
	for i in wires.size():
		var y: float = ROWS[i]
		# kanaldan rakora kısa kablo
		var col := color_of(wires[i])
		_c.draw_line(Vector2(FRAME + 50, y), Vector2(GLAND.x, y), col.darkened(0.6), 22)
		_c.draw_line(Vector2(FRAME + 50, y), Vector2(GLAND.x, y), col.darkened(0.15), 16)
		_c.draw_line(Vector2(FRAME + 50, y - 4), Vector2(GLAND.x, y - 4), col.lightened(0.35), 3)
		_tex_rect("rakor", Vector2(GLAND.x + 8, y), 52.0)


func _draw_sockets() -> void:
	for j in symbols.size():
		var c := _sock(j)
		var busy := _sock_busy(j)
		var on := _sock_on.has(j) and _t >= float(_sock_on[j])
		var powered := status == "tamir" and _power_t > 0.25 + j * 0.14
		# mıknatıs çekimi: prizin etrafı parlar
		if j == _hover:
			for k in 5:
				draw_circle(c, 58 + k * 6, Color(1.0, 0.85, 0.35, 0.07))
			draw_arc(c, 60, 0, TAU, 48, Color(1.0, 0.85, 0.35, 0.8), 3.0, true)
		_tex_rect("priz", c, 112.0)
		# yeşil halka: kablo doğru takılı
		if on or powered:
			var a := 0.75 if not powered else 0.9 + 0.1 * sin(_t * 10.0)
			var since := _t - float(_sock_on.get(j, -10.0))
			if since < 0.5:
				draw_arc(c, 56 + since * 80.0, 0, TAU, 48, Color(0.4, 1.0, 0.5, 1.0 - since * 2.0), 6.0, true)
			draw_arc(c, 53, 0, TAU, 48, Color(0.35, 1.0, 0.45, a), 4.0, true)
		# LED (prizin sağ üstünde)
		var led := c + Vector2(46, -46)
		draw_circle(led, 9, Color("#202320"))
		var lc := Color("#1d3a22")
		if on or powered:
			lc = Color("#4dff6e")
			draw_circle(led, 18, Color(0.3, 1.0, 0.45, 0.22))
		elif busy:
			lc = Color("#ffb020") if fmod(_t * 6.0, 1.0) < 0.5 else Color("#5a3c08")
		elif status == "kilit":
			lc = Color("#3a1210")
		draw_circle(led, 6, lc)
		draw_circle(led + Vector2(-2, -2), 2, Color(1, 1, 1, 0.5))
		# emaye plaka: sembol + numara
		var pc := Vector2(PLATE_X, c.y)
		_tex_rect("plaka", pc, 76.0)
		var ink := Color("#1b1a17")
		_symbol(pc + Vector2(-36, 0), str(symbols[j]), 22.0, ink)
		draw_line(pc + Vector2(-2, -22), pc + Vector2(-2, 22), Color(0.1, 0.1, 0.1, 0.35), 2)
		draw_string(_font, pc + Vector2(14, 17), str(j + 1), HORIZONTAL_ALIGNMENT_CENTER, 44, 46, Color("#b3261e"))


func _symbol(c: Vector2, kind: String, r: float, col: Color) -> void:
	match kind:
		"YILDIZ":
			var pts := PackedVector2Array()
			for k in 10:
				var ang := -PI / 2 + k * PI / 5
				pts.append(c + Vector2(cos(ang), sin(ang)) * (r * 1.12 if k % 2 == 0 else r * 0.48))
			draw_colored_polygon(pts, col)
		"ÜÇGEN":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 1.0, r * 0.78), c + Vector2(-r * 1.0, r * 0.78)]), col)
		"DAİRE":
			draw_circle(c, r * 0.9, col)
		"KARE":
			draw_rect(Rect2(c - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), col)


func _draw_lever() -> void:
	var ready := _ready_lever()
	var y := _lever_y()
	# hazır: kol nabız gibi parlar, yukarı oklar
	if ready and _lever < 0.9:
		var a := 0.5 + 0.5 * sin(_t * 7.0)
		for k in 3:
			var cy := LEVER_TOP - 40 + 50 - k * 26.0 - fmod(_t * 40.0, 26.0)
			var al := clampf(1.0 - absf(cy - (LEVER_TOP - 10)) / 70.0, 0.0, 1.0)
			draw_polyline(PackedVector2Array([Vector2(LEVER_X - 22, cy + 10), Vector2(LEVER_X, cy - 6), Vector2(LEVER_X + 22, cy + 10)]), Color(1.0, 0.78, 0.2, al), 6.0, true)
		for k in 4:
			draw_circle(Vector2(LEVER_X, y - 30), 54 + k * 8, Color(1.0, 0.7, 0.15, 0.06 * a))
	# kolun gölgesi ve kendisi (sap aşağıda yuvaya girer)
	var hc := Vector2(LEVER_X, y - 32)
	var mod := Color.WHITE if ready or status == "tamir" else Color(0.72, 0.72, 0.72)
	var t: Texture2D = _tex.get("salter_kol")
	if t:
		var hh := 92.0
		var ww := hh * t.get_width() / float(t.get_height())
		draw_texture_rect(t, Rect2(hc - Vector2(ww, hh) / 2.0 + Vector2(6, 10), Vector2(ww, hh)), false, Color(0, 0, 0, 0.45))
		draw_texture_rect(t, Rect2(hc - Vector2(ww, hh) / 2.0, Vector2(ww, hh)), false, mod)


func _draw_hint() -> void:
	# tek satır, yalnızca ne yapılacağı (ilk bağlantıya kadar, sonra şalter zamanı)
	var txt := ""
	if status == "acik" and _door >= 1.0:
		if done_steps == 0 and _pending.is_empty() and _drag == "":
			txt = tr("KABLOYU DOĞRU PRİZE TAK")
		elif _ready_lever() and _lever < 0.5:
			txt = tr("ŞALTERİ KALDIR")
	if txt == "":
		return
	var fs := 26
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := Vector2(735, FUSE_Y)
	var r := Rect2(c - Vector2(w / 2 + 22, 24), Vector2(w + 44, 48))
	var a := 0.75 + 0.25 * sin(_t * 4.0)
	_rrect(r.grow(2), Color(0, 0, 0, 0.5), 10)
	_rrect(r, Color(0.06, 0.07, 0.06, 0.92), 9)
	draw_string(_font, Vector2(r.position.x + 22, c.y + 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.8, 0.3, a))
	# boş fişlerin etrafında hafif nabız: tutulacak yer burası
	if done_steps == 0 and _pending.is_empty() and _drag == "" and _idle > 1.0:
		for w2 in _ropes:
			var rp: Dictionary = _ropes[w2]
			var g: Vector2 = rp.end + (rp.dir as Vector2) * PLUG_LEN * 0.45
			var k := fmod(_t * 1.2, 1.0)
			draw_arc(g, 30 + k * 30, 0, TAU, 40, Color(1, 0.85, 0.4, 0.6 * (1.0 - k)), 3.0, true)


func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	# Catmull-Rom ile pürüzsüz kablo
	var out := PackedVector2Array()
	var n := pts.size()
	for k in n - 1:
		var p0 := pts[maxi(k - 1, 0)]
		var p1 := pts[k]
		var p2 := pts[k + 1]
		var p3 := pts[mini(k + 2, n - 1)]
		for s in 3:
			var t := s / 3.0
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[n - 1])
	return out


func _draw_cable(w: String) -> void:
	var r: Dictionary = _ropes[w]
	var col := color_of(w)
	var pts := _smooth(r.pts)
	var target := str(connected.get(w, ""))
	if target == "" and _pending.size() == 2 and _pending[0] == w:
		target = str(_pending[1])
	var held := _drag == w or _picked == w
	var dir: Vector2 = r.dir
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + Vector2(7, 12) * (1.6 if held else 1.0))
	draw_polyline(shadow, Color(0, 0, 0, 0.35), 20, true)
	if held:
		draw_polyline(pts, Color(col, 0.18), 34, true)
	draw_polyline(pts, col.darkened(0.62), 21, true)
	draw_polyline(pts, col.darkened(0.12), 16, true)
	# üst kenar parlaklığı (normal yönünde)
	var hl := PackedVector2Array()
	var sp := PackedVector2Array()
	for k in pts.size():
		var tg := pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]
		var nrm := Vector2(tg.y, -tg.x).normalized()
		if nrm.y > 0.0:
			nrm = -nrm
		hl.append(pts[k] + nrm * 3.5)
		sp.append(pts[k] + nrm * 4.5)
	draw_polyline(hl, col.lightened(0.3), 5, true)
	draw_polyline(sp, Color(1, 1, 1, 0.45), 1.6, true)
	# güç gelince akım: kablo boyunca kayan ışıklar
	if status == "tamir" and _power_t > 0.0:
		for k in 3:
			var f := fmod(_t * 0.9 + k / 3.0, 1.0)
			var q := pts[int(f * (pts.size() - 1))]
			draw_circle(q, 9, Color(col.lightened(0.6), 0.35))
			draw_circle(q, 4.5, Color(1, 1, 0.9, 0.9))
	var end: Vector2 = r.end
	if target != "" and end.distance_to(_sock(symbols.find(target))) < 14.0:
		# prize oturmuş fişin arkası: kauçuk başlık + renk halkası
		draw_circle(end + Vector2(4, 7), 33, Color(0, 0, 0, 0.45))
		draw_circle(end, 31, Color("#121212"))
		for k in 3:
			draw_arc(end, 26 - k * 5, 0, TAU, 36, Color(1, 1, 1, 0.07), 2.0, true)
		draw_arc(end, 31, 0, TAU, 40, col, 5.0, true)
		draw_circle(end, 11, col.darkened(0.2))
		draw_circle(end + Vector2(-8, -10), 6, Color(1, 1, 1, 0.22))
	else:
		# yandan fiş: kablo yönünde döndürülmüş
		var t: Texture2D = _tex.get("fis")
		if t:
			var hh := PLUG_LEN * t.get_height() / float(t.get_width())
			var ang := dir.angle()
			var lift := 1.12 if held else 1.0
			draw_set_transform_matrix(_xf * Transform2D(ang, Vector2(lift, lift), 0.0, end + Vector2(6, 11) * (1.6 if held else 1.0)))
			draw_texture_rect(t, Rect2(Vector2(-4, -hh / 2), Vector2(PLUG_LEN, hh)), false, Color(0, 0, 0, 0.4))
			draw_set_transform_matrix(_xf * Transform2D(ang, Vector2(lift, lift), 0.0, end))
			draw_texture_rect(t, Rect2(Vector2(-4, -hh / 2), Vector2(PLUG_LEN, hh)), false)
			# kılıfın renkli halkası
			draw_rect(Rect2(Vector2(-2, -hh * 0.42), Vector2(10, hh * 0.84)), col)
			draw_set_transform_matrix(_xf)
		if held and fmod(_t * 14.0, 1.0) < 0.5:
			# tutarken ucunda minik kıvılcım
			var tip := end + dir * PLUG_LEN
			draw_circle(tip, 4, Color(1, 0.95, 0.7, 0.9))


func _draw_fx() -> void:
	for s in _smoke:
		var k: float = s.life / s.max
		draw_circle(s.p, s.r * (0.6 + k), Color(0.15, 0.15, 0.15, 0.35 * (1.0 - k)))
	# kıvılcım başlarındaki beyaz noktalar tek üçgen dizisinde (patlamada yüzlerce ayrı çizim çağrısıydı);
	# kuyruk çizgilerinden sonra, hepsi birden çizilir
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for s in _sparks:
		var k: float = s.life / s.max
		var c: Color = s.col
		var tail: Vector2 = s.v * 0.025
		if s.get("cam", false):
			draw_line(s.p, s.p + tail.normalized() * 7.0, Color(c, 1.0 - k), s.w)
		else:
			draw_line(s.p - tail, s.p, Color(c, 1.0 - k), s.w, true)
			var base := pts.size()
			var r: float = s.w * 0.6
			var wc := Color(1, 1, 1, 1.0 - k)
			pts.append(s.p)
			cols.append(wc)
			for q in 12:
				pts.append(s.p + Vector2(cos(q * TAU / 12.0), sin(q * TAU / 12.0)) * r)
				cols.append(wc)
				idx.append_array([base, base + 1 + q, base + 1 + (q + 1) % 12])
	if not pts.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)


func _draw_door() -> void:
	if _door >= 1.0:
		return
	var t: Texture2D = _tex.get("kapak")
	# menteşe solda: kapak dönerken yatayda daralır ve kararır
	var k := ease(_door, 2.2)
	var wd := W * cos(k * PI * 0.5)
	if t and wd > 2.0:
		draw_texture_rect(t, Rect2(Vector2(0, 0), Vector2(wd, H)), false, Color(1, 1, 1).darkened(k * 0.6))
		draw_rect(Rect2(Vector2(wd - 8, 0), Vector2(8, H)), Color(0, 0, 0, 0.4 * k))


func _draw_close() -> void:
	var p := Vector2(W - 6, 6)
	draw_circle(p + Vector2(2, 4), 34, Color(0, 0, 0, 0.5))
	draw_circle(p, 32, Color("#59605a"))
	draw_circle(p, 27, Color("#2a2f2b"))
	var t := UI.icon_texture("kapat", 36)
	if t:
		draw_texture_rect(t, Rect2(p - Vector2(18, 18), Vector2(36, 36)), false)
	else:
		draw_line(p - Vector2(10, 10), p + Vector2(10, 10), Color.WHITE, 4)
		draw_line(p + Vector2(-10, 10), p + Vector2(10, -10), Color.WHITE, 4)


func _draw_end() -> void:
	if _end_t < 0.0:
		return
	var ok := status == "tamir"
	var txt := tr("ONARDIN!" if ok else "KUTU YANDI!")
	var col := Color("#56ff7a") if ok else Color("#ff4038")
	var k := clampf(_end_t / 0.25, 0.0, 1.0)
	var sc := lerpf(1.6, 1.0, ease(k, 0.4))
	var fs := 92
	var sz := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var c := Vector2(W * 0.45, H * 0.5)
	draw_set_transform_matrix(_xf * Transform2D(0.0, Vector2(sc, sc), 0.0, c))
	var band := Rect2(Vector2(-sz.x / 2 - 60, -sz.y * 0.75), Vector2(sz.x + 120, sz.y * 1.1))
	_rrect(band.grow(4), Color(col, 0.35 * k), 22)
	_rrect(band, Color(0.02, 0.03, 0.02, 0.88 * k), 18)
	var bp := Vector2(-sz.x / 2, sz.y * 0.28)
	draw_string_outline(_font, bp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color(0, 0, 0, k))
	draw_string(_font, bp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, k))
	draw_string(_font, bp + Vector2(0, -3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lightened(0.55), 0.35 * k))
	draw_set_transform_matrix(_xf)
