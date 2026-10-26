# Fon müziği ve gardiyan anonsları. Müzikler iki çalar arasında yumuşakça geçer (crossfade);
# telefonda konuşurken ya da anons sırasında müzik kısılır. Ses düzeyi ayarlardan (muzik_ses).
extends Node

const TRACKS := {
	"menu": "res://assets/muzik/menu.ogg", "gerilim": "res://assets/muzik/gerilim.ogg", "nabiz": "res://assets/muzik/nabiz.ogg",
	"ortam": "res://assets/muzik/ortam.ogg", "korku": "res://assets/muzik/korku.ogg", "hava": "res://assets/muzik/hava.ogg",
	"zafer": "res://assets/muzik/zafer.ogg",
}
# her mini oyunun müziği
const GAME_TRACK := {
	"tahta": "ortam", "devre": "nabiz", "kimkim": "korku", "yalanci": "hava", "rulet": "gerilim", "c4": "nabiz", "ortalama": "ortam",
}
const BASE_DB := -9.0  # müzik konuşmanın ve efektlerin altında kalsın

var volume := 0.7  # ayarlardaki müzik sesi (0-1)
var _players: Array[AudioStreamPlayer] = []
var _cur := 0
var _track := ""
var _duck := 1.0  # anons/telefon sırasında kısma
var _duck_target := 1.0
var _announcer: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_announcer = AudioStreamPlayer.new()
	_announcer.volume_db = 2.0
	add_child(_announcer)
	_announcer.finished.connect(func() -> void: _duck_target = 1.0)


# Müziği değiştir ("" durdurur). Aynı parça çalıyorsa dokunmaz.
func play(track: String, fade := 1.5) -> void:
	if track == _track:
		return
	_track = track
	var old := _players[_cur]
	_cur = 1 - _cur
	var nu := _players[_cur]
	if old.playing:
		var to := old.create_tween()
		to.tween_property(old, "volume_db", -80.0, fade)
		to.tween_callback(old.stop)
	if track == "" or not TRACKS.has(track):
		return
	var st: AudioStream = load(TRACKS[track])
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = track != "zafer"
	nu.stream = st
	nu.volume_db = -80.0
	nu.play()
	nu.create_tween().tween_property(nu, "volume_db", _target_db(), fade)


func play_game(task: String) -> void:
	play(GAME_TRACK.get(task, "ortam"))


func _target_db() -> float:
	return BASE_DB + linear_to_db(maxf(volume * _duck, 0.0005))


# Gardiyan anonsu (assets/ses/anons/<ad>.ogg; İngilizcede anons_en/); çalarken müzik kısılır.
func announce(line: String) -> void:
	var path := "res://assets/ses/anons/%s.ogg" % line
	if not preload("res://scripts/dil.gd").tr_mi():
		var en := "res://assets/ses/anons_en/%s.ogg" % line
		if ResourceLoader.exists(en):
			path = en
	if not ResourceLoader.exists(path):
		return
	_announcer.stream = load(path)
	_announcer.play()
	_duck_target = 0.35


# Telefonda konuşurken müzik kısılsın.
func set_call(on: bool) -> void:
	_duck_target = 0.25 if on else 1.0


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	_duck = move_toward(_duck, _duck_target, delta * 1.5)
	var p := _players[_cur]
	if p.playing and not _is_fading(p):
		p.volume_db = _target_db()


func _is_fading(p: AudioStreamPlayer) -> bool:
	return p.volume_db < _target_db() - 6.0 and p.get_playback_position() < 2.0
