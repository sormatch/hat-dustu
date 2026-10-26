# Ses düzeni denetimi: oyunu açar (komut satırı argümanları main.gd'ye aynen gider), belirli aralıklarla
# bus'ları, hangi bus'ta kaç ses çalar olduğunu, ortam sesinin ve uzak oyuncu ayak seslerinin durumunu yazar.
# Kullanım: Godot --path . -s tools/ses_kontrol.gd -- server=ws://127.0.0.1:8794 auto=oyun code=SESK n=4 botlar=3 hiz=0.2 oyunlar=tahta
extends SceneTree

var _t := 0.0
var _next := 3.0
var _main: Node
var _sure := 70.0
var _adim_kare := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("sure="):
			_sure = float(a.substr(5))
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	var s := "[ses] bus'lar:"
	for i in AudioServer.bus_count:
		s += " %d=%s(->%s, %d efekt)" % [i, AudioServer.get_bus_name(i), AudioServer.get_bus_send(i), AudioServer.get_bus_effect_count(i)]
	print(s)


func _process(delta: float) -> bool:
	_t += delta
	# uzak oyuncu ayak sesi çalınıyor mu (kare sayısı)
	var rem: Dictionary = _main.get("remotes")
	for id in rem:
		var p = rem[id].get("_adim")
		if p and p.playing:
			_adim_kare += 1
			break
	# 28-34. saniyeler: ilk uzak oyuncu yürüyormuş gibi (2.4 m/sn) ayak sesi denemesi
	if _t > 28.0 and _t < 34.0 and not rem.is_empty():
		var r0: Dictionary = rem[rem.keys()[0]]
		r0.target += Vector3(0, 0, 2.4 * delta * (1.0 if fmod(_t, 4.0) < 2.0 else -1.0))
	# 20-26. saniyeler: sahte gelen konuşma (ducking denemesi)
	var v: Node = _main.get("voice")
	if _t > 20.0 and _t < 26.0 and v and v.active:
		var d := PackedByteArray()
		d.resize(641)
		d[0] = 7
		for i in 640:
			d[i + 1] = v._enc(sin(i * 0.3) * 0.4)
		v.receive(d)
	if _t >= _next:
		_next += 5.0
		_rapor()
	return _t > _sure


func _rapor() -> void:
	var say := {}
	var calan := {}
	_say(root, say, calan)
	var m: Node = _main.get("muzik")
	var ortam = m.get("_ortam") if m else null
	var adim := 0
	var rem: Dictionary = _main.get("remotes")
	for id in rem:
		if rem[id].has("_adim"):
			adim += 1
	var vols := []
	for i in AudioServer.bus_count:
		vols.append("%s=%.1f" % [AudioServer.get_bus_name(i), AudioServer.get_bus_volume_db(i)])
	print("[ses] t=%.0f playing=%s lobi=%s | çalar/bus %s | çalan %s | ortam=%s %s | uzak adım çaları %d/%d (adım çalan kare %d) | %s" % [_t,
		_main.get("playing"), _main.get("in_lobby"), say, calan,
		"yok" if ortam == null else ("çalıyor" if ortam.playing else "durdu"),
		"" if ortam == null else "%.1f dB" % ortam.volume_db, adim, rem.size(), _adim_kare, " ".join(vols)])


func _say(n: Node, say: Dictionary, calan: Dictionary) -> void:
	if n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D:
		var b := String(n.bus)
		say[b] = int(say.get(b, 0)) + 1
		if n.playing:
			calan[b] = int(calan.get(b, 0)) + 1
	for c in n.get_children():
		_say(c, say, calan)
