# Hapishane koridoru, hücreler, oyuncu, ekran, menü ve çok oyunculu bağlantı.
extends Node3D

const Sfx := preload("res://scripts/sfx.gd")
const UI := preload("res://scripts/ui.gd")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")
const MenuScript := preload("res://scripts/menu.gd")
const CellScript := preload("res://scripts/cell.gd")
const BodyScript := preload("res://scripts/model_body.gd")
const NetScript := preload("res://scripts/net.gd")
const AccountScript := preload("res://scripts/account.gd")
const GirisScript := preload("res://scripts/giris.gd")
const GameUIScript := preload("res://scripts/game_ui.gd")
const FriendsScript := preload("res://scripts/friends.gd")
const LobbyScript := preload("res://scripts/lobby3d.gd")
const LOBBY_POS := Vector3(-40, 0, 0)
const VoiceScript := preload("res://scripts/voice.gd")
const AimModScript := preload("res://scripts/modlar/aim_mod.gd")
const TelefonScript := preload("res://scripts/telefon.gd")
const ProfileScript := preload("res://scripts/profile.gd")
const CharacterScript := preload("res://scripts/character.gd")
const EnvanterScript := preload("res://scripts/envanter.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const Catalog := preload("res://scripts/catalog.gd")
const MuzikScript := preload("res://scripts/muzik.gd")
const TelemetriScript := preload("res://scripts/telemetri.gd")
const Dil := preload("res://scripts/dil.gd")
const AcilisScript := preload("res://scripts/acilis.gd")  # açılış perdesi + kademeli kurulum + gölgelendirici ısıtma

signal hazir  # sahne kuruldu (kademeli kurulumda _ready birkaç kare sürer; araçlar: if not main.hazir_mi: await main.hazir)
var hazir_mi := false

const H := 3.2
const CELL_COUNT := 8
const CELL_SPACING := 6.6
const CORRIDOR_X0 := 2.2
const CORRIDOR_X1 := 5.6
const CORRIDOR_HALF := 28
const ROUND_TIME := 90.0
const WALK_ENDS := [-25.0, 25.0]
const WALK_SPEED := 1.1
const DIAL_TIMEOUT := 30.0
const CALL_REWARD := 10

# tek başına modda arayan hayali oyuncu
const CALL_LINES := [
	[0.6, "Alo? Duyuyor musun beni?"],
	[3.5, "Bu tur ortağız. Ben paylaşacağım, söz veriyorum."],
	[8.0, "Ama Elif'e güvenme. Koridorda duydum, seni satacakmış."],
	[13.0, "Karar senin. Süre dolmadan bir daha ararım."],
]

enum Phone { IDLE, RINGING, DIALING, CALL }

var player: CharacterBody3D
var hud: CanvasLayer
var menu: CanvasLayer
var net: Node
var voice: Node
var profile: Node
var account: Node
var menu_cam: Camera3D
var lobby: Node3D
var in_lobby := false
var _menu_t := 0.0
var env: Environment
var probe: ReflectionProbe
var mats := {}
var ring_stream: AudioStreamWAV
var door_open_stream: AudioStreamWAV
var door_close_stream: AudioStreamWAV
var snd_latch: AudioStream
var snd_slam: AudioStream
var snd_click: AudioStream
var snd_creak: AudioStream
var ambient: AudioStreamPlayer
var glow_window: StandardMaterial3D
var click_player: AudioStreamPlayer

var cells: Array = []
var my_cell := 0
var online := false
var game_ui: CanvasLayer
var game_on := false  # sunucuda tur oyunu sürüyor
var game_left := 0.0
var game_alive: Array = []
var _near_board := false
var _stall_t := 0.0
var muzik: Node  # fon müziği ve gardiyan anonsları
var telemetri: Node  # hata raporu ve analitik
var _music_task := ""
var _game_end_tick := 0  # sürenin bittiği an (bu cihazın saatiyle): herkes aynı süreyi görsün
var call_bar: CanvasLayer  # panellerin de üstünde: "● Hatta: Ali  0:23  [KAPAT]"
var _call_label: Label
var playing := false

var phone_state := Phone.IDLE
var phone_peer := 0  # arayan / aranan / konuşulan oyuncu
var phone_t := 0.0
var solo_ring_wait := 5.0
const MESGUL_SURE := 2.2  # aranan meşgulse kırmızı "MEŞGUL" yazısı + meşgul tonu bu kadar sürer
var _mesgul_kalan := 0.0

var remotes := {}  # id -> {root, body, label, target, yaw, seated}
var _send_t := 0.0
var _last_sent := ""

var walker: AnimatableBody3D
var walker_body: Node3D
var walker_leg := 1
var walker_wait := 0.0

var round_left := ROUND_TIME
var current_target := ""
var current_cell := -1
var test_move := Vector2.ZERO
var _auto := ""
var _drip_t := 3.0
var _drip: AudioStreamPlayer3D


func _ready() -> void:
	# ses düzeni: bus seçmemiş her ses çalar Efekt bus'ına gider (ayarlardaki oyun sesiyle kısılsın)
	if not get_tree().node_added.is_connected(Sfx.yonlendir):
		get_tree().node_added.connect(Sfx.yonlendir)
	# tebeşir yazı tipinde İ, Ş, Ğ yok: eksik harfler el yazısı tarzı Patrick Hand ile yazılsın
	var chalk: FontFile = load("res://assets/fonts/CabinSketch-Bold.ttf")
	chalk.fallbacks = [load("res://assets/fonts/PatrickHand-Regular.ttf")]
	randomize()
	profile = ProfileScript.new()
	add_child(profile)
	Dil.baslat(profile)  # oyunun dili: ayar > cihaz dili (Türkçe değilse İngilizce)
	# açılış perdesi ilk karede görünür; ağır kurulum adımları arasında bir kare çizilir (donma yerine animasyon).
	# Kurulum bitene kadar bu düğümün _process / girişi kapalı (oyuncu, arayüz henüz yok).
	var perde: CanvasLayer = AcilisScript.new()
	add_child(perde)
	set_process(false)
	set_process_unhandled_input(false)
	get_viewport().disable_3d = true  # kurulurken yarım dünya çizilmesin (gölgelendiriciler perdenin ısıtmasında derlenir)
	muzik = MuzikScript.new()
	add_child(muzik)
	_setup_input()
	_make_materials()
	_build_environment()
	await perde.adim(0.08)
	await _build_corridor(perde)
	await perde.adim(0.3)
	lobby = LobbyScript.new()
	lobby.w = self
	lobby.position = LOBBY_POS
	add_child(lobby)
	lobby.build()
	await perde.adim(0.36)
	for k in CELL_COUNT:
		var c: Node3D = CellScript.new()
		c.w = self
		c.index = k
		c.number = 11 + k
		c.position = Vector3(0, 0, (k - (CELL_COUNT - 1) / 2.0) * CELL_SPACING)
		add_child(c)
		c.build()
		cells.append(c)
		await perde.adim(0.36 + 0.05 * (k + 1))

	player = PlayerScript.new()
	add_child(player)
	player.cord_snapped.connect(_on_cord_snapped)
	player.global_position = cells[0].spawn_world()
	player.set_physics_process(false)  # menüdeyken yürümesin
	await perde.adim(0.8)

	click_player = AudioStreamPlayer.new()
	click_player.stream = Sfx.click()
	add_child(click_player)

	net = NetScript.new()
	add_child(net)
	telemetri = TelemetriScript.new()
	telemetri.server_url = net.server_url
	add_child(telemetri)
	account = AccountScript.new()
	add_child(account)
	account.start(net.server_url, profile.token)
	account.set_process(false)  # kurulum bitene kadar sunucu iletisi işlenmez (menü henüz yok); sonda açılır
	net.account_token = profile.token
	account.token_changed.connect(func(t: String) -> void:
		profile.token = t
		net.account_token = t
		profile.save())
	account.me_changed.connect(_on_account)
	account.economy_changed.connect(func() -> void:
		profile.apply_economy(account.eco)
		hud.refresh_gems(profile.gems))
	account.reward.connect(_on_reward)
	account.moderation.connect(_on_moderation)
	account.name_reset.connect(func(ad: String) -> void:
		# yönetici görünen adı sıfırladı: telefondaki ad da değişir (odalara yeni ad gider)
		if ad != "":
			profile.player_name = ad
			profile.save()
			if menu and menu.has_method("refresh_profile"):
				menu.refresh_profile())
	profile.daily_requested.connect(func() -> void: account.send({"t": "gunluk_al"}))
	voice = VoiceScript.new()
	add_child(voice)
	voice.packet_ready.connect(net.send_voice)
	net.voice.connect(voice.receive)
	net.started.connect(_on_started)
	net.players_changed.connect(_on_players_changed)
	net.remote_state.connect(_on_remote_state)
	net.player_left.connect(_remove_remote)
	net.door.connect(func(cell: int, open: bool) -> void: cells[cell].set_door(open))
	net.ringing.connect(_on_ringing)
	net.ring_cell.connect(func(cell: int, on: bool) -> void: cells[cell].set_ringing(on))
	net.call_connected.connect(_on_call_connected)
	net.call_ended.connect(_on_call_ended)
	net.busy.connect(_on_busy)
	net.lines_changed.connect(func() -> void: hud.mark_busy(net.busy_ids))
	net.failed.connect(_on_net_failed)
	net.reconnecting.connect(_on_reconnecting)
	net.public_countdown.connect(func(sec: int) -> void: hud.set_public_countdown(sec))
	net.rejoined.connect(_on_rejoined)

	net.welcomed.connect(_send_profile)
	net.welcomed.connect(func() -> void: voice.start())
	net.welcomed.connect(_enter_lobby)
	net.emote.connect(_on_remote_emote)

	hud = HudScript.new()
	add_child(hud)
	hud.player = player
	hud.action_pressed.connect(_do_action)
	hud.contact_chosen.connect(_dial)
	hud.settings_pressed.connect(open_settings)
	hud.emote_chosen.connect(_do_emote)
	hud.crouch_pressed.connect(player.toggle_crouch)
	player.emote_stopped.connect(func() -> void:
		if online:
			net.send({"t": "emote", "e": "dur"}))
	hud.ptt_changed.connect(func(down: bool) -> void: voice.ptt_down = down)
	hud.lobby_ready.connect(func(on: bool) -> void: net.send({"t": "hazir", "on": on}))
	hud.lobby_start.connect(func() -> void:
		var pick: String = hud.GAME_CHOICES[hud.game_pick][0]
		var liste: Array = [pick] if pick != "" else []
		# test kısayolu: komut satırında oyunlar=devre,rulet,... verilmişse "Tüm oyunlar" bu listeyle başlar
		if pick == "":
			for a in OS.get_cmdline_user_args():
				if a.begins_with("oyunlar="):
					liste = Array(a.trim_prefix("oyunlar=").split(",", false))
		net.send({"t": "basla", "oyunlar": liste}))
	hud.lobby_bot.connect(func(add: bool) -> void: net.send({"t": "bot_ekle" if add else "bot_cikar"}))
	hud.lobby_invite.connect(open_friends)
	hud.lobby_leave.connect(func() -> void:
		net.leave()
		get_tree().reload_current_scene())
	hud.visible = false
	await perde.adim(0.86)

	game_ui = GameUIScript.new()
	game_ui.net = net
	game_ui.world = self
	add_child(game_ui)
	game_ui.decided.connect(func(v) -> void: net.send({"t": "karar", "v": v}))
	game_ui.board_written.connect(func(t: String) -> void: cells[my_cell].set_board_text(t))
	net.written.connect(func(kind: String) -> void: game_ui.on_written(kind))
	net.devre_event.connect(func(d: Dictionary) -> void: game_ui.on_devre(d))
	net.devre_status.connect(func(d: Dictionary) -> void: game_ui.on_devre_status(d))
	net.mode_event.connect(func(d: Dictionary) -> void: game_ui.on_event(d))
	game_ui.devre_fx.connect(_on_devre_fx)
	game_ui.leave_game.connect(func() -> void:
		# maç sonu ekranında ÇIKIŞ (ya da Android geri tuşu): odadan çıkıp ana menüye
		account.set_room("")
		net.leave()
		get_tree().reload_current_scene())
	game_ui.play_again.connect(_tekrar_oyna)
	net.lobby_back.connect(_on_lobby_back)
	net.welcomed.connect(func() -> void: game_ui.my_id = net.my_id)
	net.info.connect(func(m: String) -> void: hud.show_toast(m))
	# oyuncu bildirimleri: bağlantı koptu / geri bağlandı / ayrıldı / katıldı / çıktı / oda sahibi (ikonlu, sıralı)
	net.notice.connect(func(tur: String, _id: int, m: String) -> void:
		if playing:
			hud.bildirim(tur, m))
	# arkadaşlık isteği: maç sürmüyorsa (salonda) kısa bildirim
	account.request_received.connect(func(handle: String) -> void:
		if playing and online and not game_on:
			hud.bildirim("istek", tr("@%s arkadaşlık isteği gönderdi") % handle))
	net.game_state.connect(func(d: Dictionary) -> void:
		_on_game_music(d)
		game_on = true
		game_left = float(d.get("kalan_ms", float(d.kalan) * 1000.0)) / 1000.0
		_game_end_tick = Time.get_ticks_msec() + int(game_left * 1000.0)
		game_alive = d.players
		hud.round_pill.visible = false
		game_ui.on_state(d))
	net.game_secret.connect(func(d: Dictionary) -> void: game_ui.on_secret(d))
	net.game_result.connect(func(d: Dictionary) -> void:
		# süre bitti: zil çalar, hücrenin ışığı bir an söner
		var bell := AudioStreamPlayer.new()
		bell.stream = Sfx.bell()
		bell.volume_db = -4.0
		add_child(bell)
		bell.play()
		bell.finished.connect(bell.queue_free)
		cells[my_cell].flicker()
		game_ui.on_result(d))
	net.game_over.connect(func(d: Dictionary) -> void:
		telemetri.event("mac_bitti", {"oyun": int(d.get("rounds", 0))})
		muzik.play("zafer", 0.5)
		muzik.announce("mac_bitti")
		muzik.ortam_izin(false)  # maç sonu ekranında ortam sesi susar
		game_on = false
		game_ui.on_over(d)
		game_ui.mac_sonu_oyuncular(net.players))

	await perde.adim(0.9)
	get_viewport().disable_3d = false  # menü kendi görünürlüğüne göre yeniden kapatır (menu.gd _dunya_ciz)
	menu = MenuScript.new()
	menu.net = net
	menu.account = account
	menu.profile = profile
	add_child(menu)
	menu.solo.connect(_start_solo)
	menu.open_character.connect(open_character)
	menu.open_inventory.connect(open_inventory)
	menu.open_settings.connect(open_settings)
	menu.open_friends.connect(open_friends)
	_build_menu_scene()

	player.set_look(profile.look)
	profile.changed.connect(_on_profile_changed)
	_on_profile_changed()
	apply_settings()
	muzik.play("menu", 2.5)
	set_process(true)
	set_process_unhandled_input(true)
	account.set_process(true)
	hazir_mi = true
	hazir.emit()
	perde.bitir()  # ilk açılışta gölgelendirici ısıtma, sonra perde kalkar (beklenmez)
	_handle_cmdline()


var _cloud_token := ""  # bu anahtarın sunucu kaydı bir kez yüklendi mi
var _asked_login := false
var _push_t := -1.0


# Hesap bilgisi geldi: sunucuda kayıt varsa onu yükle, yoksa (yeni hesap) telefondakini gönder.
func _on_account() -> void:
	if account.has_account and _cloud_token != account.token:
		_cloud_token = account.token
		if typeof(account.remote_profile) == TYPE_DICTIONARY:
			profile.from_cloud(account.remote_profile)
			player.set_look(profile.look)
			_send_profile()
		else:
			account.push_profile(profile.to_cloud())
	# ilk açılışta hesap sorulur (misafir devam edebilir)
	if not account.has_account and not _asked_login and not bool(profile.settings.giris_soruldu) and not playing and menu.visible 			and OS.get_cmdline_user_args().is_empty():
		_asked_login = true
		var g := open_login()
		g.closed.connect(_kurallar_ilk)  # hesap ekranı kapanınca topluluk kuralları
	elif not _asked_login:
		_kurallar_ilk()


# Yönetici işlemi: hesap askıya alındı ("yasak") ya da uyarı ("uyari"). Kısa bir pencere gösterilir.
func _on_moderation(kind: String, text: String) -> void:
	var m := UI.modal("HESAP ASKIDA" if kind == "yasak" else "UYARI", 600)
	var ic := UI.icon("kilit" if kind == "yasak" else "sikayet", 72)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.body.add_child(ic)
	var l := UI.label(text, UI.FS_ORTA, UI.METIN, true)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # sunucu metni zaten çevrildi (Dil.sunucu)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.body.add_child(l)
	var ok := UI.button("TAMAM", "ana", UI.BTN_H, UI.FS_ORTA)
	ok.pressed.connect(m.close)
	m.body.add_child(ok)
	var katman := CanvasLayer.new()
	katman.layer = 115
	add_child(katman)
	katman.add_child(m)
	m.closed.connect(katman.queue_free)


# Topluluk kuralları: ilk açılışta bir kez (kabul edilene kadar her açılışta bir kez) gösterilir.
# Kabul edilmeden çevrimiçi oynanmaz (menu.gd / friends.gd -> giris.gd kurallar_sonra).
var _kurallar_soruldu := false


func _kurallar_ilk() -> void:
	if _kurallar_soruldu or GirisScript.kurallar_kabul(profile) or playing or not menu.visible or not OS.get_cmdline_user_args().is_empty():
		return
	_kurallar_soruldu = true
	GirisScript.kurallar_onayi(menu, profile)


# Sunucudan gelen ödül: günlük ödül, görev/başarım ödülü ya da maç sonu XP ve elması.
func _on_reward(d: Dictionary) -> void:
	if d.get("t") == "mac_odul":
		var txt := tr("+%d XP   +%d elmas") % [int(d.get("xp", 0)), int(d.get("elmas", 0))]
		if int(d.get("seviye_atladi", 0)) > 0:
			txt = tr("SEVİYE %d!   ") % int(d.seviye_atladi) + txt
		Sfx.arayuz("seviye" if int(d.get("seviye_atladi", 0)) > 0 else "odul")  # ses (D)
		hud.show_toast(txt)
	else:
		hud.show_toast(tr("+%d elmas · %s") % [int(d.get("elmas", 0)), Dil.sunucu(d, "neden")])


func open_login() -> CanvasLayer:
	var g: CanvasLayer = GirisScript.new()
	g.account = account
	g.profile = profile
	add_child(g)
	return g


# Kısa Devre: ışıklar, sigorta kutusu ve sarsıntı. Oyun dışında kutu kapalı ve sakindir;
# kesintide kapak aralanır, uyarı ışığı ve kıvılcım başlar; oyun bitince yeniden kapanır.
func _on_devre_fx(kind: String) -> void:
	var c: Node3D = cells[my_cell]
	match kind:
		"kesinti":
			c.set_power(false)
			c.set_fuse("bozuk")
			_shake(0.6, 0.06)
		"tamir":
			c.power_on_sequence()  # şalter kalktı: ışıklar cızırdayıp tek tek yanar
		"yanlis":
			_shake(0.25, 0.03)
		"kilit":
			c.set_fuse("kilit")
			_shake(0.4, 0.05)
		"bitti":
			c.set_power(true)
			if c.fuse_state == "bozuk":
				c.set_fuse("kilit")
			# biraz sonra kutu sıradan haline döner (kapak kapanır, uyarılar söner)
			get_tree().create_timer(3.5).timeout.connect(func() -> void:
				if is_instance_valid(c) and c.fuse_state != "bozuk":
					c.set_fuse("normal"))


# Her mini oyunun kendi müziği; oyunun başında gardiyan anonsu, oyunlar arasında "sıradaki oyun".
func _on_game_music(d: Dictionary) -> void:
	var task := str(d.get("task", ""))
	var phase := str(d.get("phase", ""))
	if phase == "sonuc":
		if str(d.get("sonraki", "")) != "":
			muzik.announce("siradaki")
		return
	if task != _music_task:
		_music_task = task
		muzik.play_game(task)
		if phase == "anons":
			get_tree().create_timer(0.6).timeout.connect(func() -> void: muzik.announce(task))


# Kamera sarsıntısı (eski çağrılar için): asıl iş player.sars'ta (tek yer); telefon da titrer (ayara bağlı).
func _shake(t: float, amp: float) -> void:
	player.sars(amp, t, true)


func _on_profile_changed() -> void:
	if account and account.has_account:
		_push_t = 1.5  # değişiklikleri biriktirip 1,5 sn sonra hesaba yaz
	hud.refresh_gems(profile.gems)
	var em := []
	for it in Catalog.ITEMS.hareket:
		if profile.owns("hareket", it[0]):
			em.append(it[0])
	hud.set_emotes(em)


func _send_profile() -> void:
	net.send({"t": "profil", "ad": profile.player_name, "g": profile.look})


# Ayarları oyuna uygular: hassasiyet, ses, joystick, grafik kalitesi.
func apply_settings() -> void:
	var s: Dictionary = profile.settings
	player.sensitivity = float(s.get("hassasiyet", 1.0))
	if muzik:
		muzik.set_efekt(float(s.oyun_ses))  # Efekt bus'ı (müzik ve konuşma ayrı)
		muzik.set_volume(float(s.get("muzik_ses", 0.7)))
	voice.set_volume(float(s.konusma_ses))
	hud.floating_joy = bool(s.yuzen_joy)
	var high := int(s.kalite) >= 1
	# 0 pil dostu / 1 yüksek / 2 ultra: gölge, parlama, huzme, leke, yansıma, 3D çözünürlük (scripts/dunya.gd)
	preload("res://scripts/dunya.gd").apply_quality(self, int(s.kalite))
	if playing:
		cells[my_cell].set_detailed(high)
	player.camera.fov = float(s.get("fov", 72.0))
	player.head_bob = bool(s.get("bob", true))
	hud.set_fps_visible(bool(s.get("fps", false)))
	voice.ptt_enabled = bool(s.get("bas_konus", false))
	ring_stream = Sfx.ring(int(s.get("zil", 0)))
	for c in cells:
		c.ring_player.stream = ring_stream


func open_settings() -> CanvasLayer:
	var st: CanvasLayer = SettingsScript.new()
	st.profile = profile
	st.account = account
	st.voice = voice
	st.closed.connect(func() -> void:
		apply_settings()
		_send_profile()
		if menu and is_instance_valid(menu) and menu.has_method("refresh_profile"):
			menu.refresh_profile())  # dil değiştiyse biçimli yazılar yeni dilde yeniden yazılsın
	st.open_character.connect(func() -> void:
		st.queue_free()
		apply_settings()
		open_character())
	st.leave_room.connect(func() -> void:
		net.leave()
		get_tree().reload_current_scene())
	add_child(st)
	return st


# Ortam sesi (damla, havalandırma, uzak sesler) artık muzik.gd'de: menüde ve maç sonunda susar.
func _update_drip(_delta: float) -> void:
	pass


func _update_drip_old(delta: float) -> void:
	_drip_t -= delta
	if _drip_t > 0.0:
		return
	_drip_t = randf_range(3.0, 9.0)
	if not _drip:
		_drip = AudioStreamPlayer3D.new()
		_drip.stream = Sfx.drip()
		_drip.unit_size = 3.0
		add_child(_drip)
	var a := randf() * TAU
	_drip.global_position = player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 4.0) + Vector3(0, H - 0.2, 0)
	_drip.pitch_scale = randf_range(0.8, 1.25)
	_drip.play()


func _do_emote(id: String) -> void:
	if phone_state == Phone.CALL or phone_state == Phone.DIALING:
		hud.show_toast("Telefondayken hareket yapamazsın.")
		return
	if player.seated:
		hud.show_toast("Önce koltuktan kalk.")
		return
	if player.hands_full():
		hud.show_toast("Elin doluyken hareket yapamazsın.")
		return
	# oyun bir eylem bekliyor (açık panel, tahta, sigorta kutusu) ya da oyuncu bir işte (oturuyor, kalkıyor)
	if player.busy or (is_instance_valid(game_ui._box) and game_ui._box.is_visible_in_tree()) \
			or (is_instance_valid(game_ui._panel) and game_ui._panel.is_visible_in_tree()):
		hud.show_toast("Şu an hareket yapamazsın.")
		return
	player.play_emote(id)
	if online:
		net.send({"t": "emote", "e": id})


func _on_remote_emote(id: int, e: String) -> void:
	if e == "dur" and remotes.has(id):
		remotes[id].body.stop_emote()
		return
	if _auto != "":
		print("[test] hareket geldi: ", e, " oyuncu ", id)
	if not remotes.has(id) or not Catalog.EMOTE_TEXT.has(e):
		return
	var r: Dictionary = remotes[id]
	r.body.play_emote(e)
	var bubble := Label3D.new()
	bubble.text = Catalog.EMOTE_TEXT[e]
	bubble.font_size = 56
	bubble.pixel_size = 0.004
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.outline_size = 10
	bubble.modulate = Color("#F5C542")
	bubble.position.y = 2.3
	r.root.add_child(bubble)
	var tw := bubble.create_tween()
	tw.tween_property(bubble, "position:y", 2.6, 2.4)
	tw.parallel().tween_property(bubble, "modulate:a", 0.0, 2.4).set_delay(1.2)
	tw.tween_callback(bubble.queue_free)


func _setup_input() -> void:
	var keys := {"ileri": KEY_W, "geri": KEY_S, "sol": KEY_A, "sag": KEY_D, "etkilesim": KEY_E, "kos": KEY_SHIFT, "egil": KEY_C}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)


# ---------- malzemeler ve yardımcılar ----------

# Poly Haven'dan indirilen gerçek doku (renk + yüzey kabartısı + pürüzlülük).
func _pbr(id: String, scale: float, rough := 1.0, tint := Color.WHITE, diff := "diff.jpg", metal := 0.0) -> StandardMaterial3D:
	var dir := "res://assets/textures/%s/" % id
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + diff)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "nor.jpg")
	m.roughness_texture = load(dir + "rough.jpg")
	m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _noise_tex(c1: Color, c2: Color, freq: float, sd: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = sd
	n.frequency = freq
	n.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2)
	tex.color_ramp = g
	return tex


func _surface(c: Color, rough: float, scale: float, sd: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(c.darkened(0.22), c.lightened(0.05), 0.02, sd)
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _flat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _make_materials() -> void:
	# sanat yönü: yeşil boyalı paslı beton, sıcak amber ışık, ıslak zemin (Poly Haven CC0 dokular, assets/textures/LISANS.txt)
	mats.wall = _pbr("concrete_wall_008", 0.45, 1.0, Color(0.74, 0.68, 0.58))
	mats.paint = _pbr("painted_concrete", 0.42, 1.0, Color(0.62, 0.74, 0.6))
	mats.paint_b = _pbr("peeling_painted_wall", 0.6, 0.85, Color(0.66, 0.74, 0.64), "diff_green.jpg")
	mats.paint_c = _pbr("painted_concrete", 0.5, 1.0, Color(0.52, 0.66, 0.62))
	mats.floor = _pbr("worn_concrete_floor", 0.5, 0.85, Color(0.4, 0.37, 0.33))
	mats.ceiling = _pbr("dirty_concrete", 0.4, 1.0, Color(0.36, 0.34, 0.31))
	mats.corridor_floor = _pbr("concrete_floor_painted", 0.32, 0.5, Color(0.55, 0.5, 0.44))
	mats.corridor_wall = _pbr("concrete_wall_006", 0.45, 1.0, Color(0.66, 0.6, 0.52))
	for k in ["wall", "paint", "paint_b", "paint_c", "floor", "ceiling", "corridor_floor", "corridor_wall"]:
		(mats[k] as StandardMaterial3D).uv1_world_triplanar = true  # yan yana kutularda doku dikişi olmasın
	mats.door = _pbr("rusty_metal_02", 0.9, 0.9, Color(0.5, 0.47, 0.43), "diff.jpg", 0.6)
	mats.green_metal = _pbr("green_metal_rust", 0.9, 1.0, Color(0.62, 0.72, 0.62), "diff.jpg", 0.35)
	mats.metal_plate = _pbr("metal_plate", 1.2, 0.8, Color(0.55, 0.55, 0.55), "diff.jpg", 0.75)
	mats.pipe = _pbr("rusty_metal_02", 2.5, 0.7, Color(0.42, 0.45, 0.42), "diff.jpg", 0.7)
	mats.stripe = _flat(Color("#1c2a20"), 0.55)
	var line := _flat(Color.WHITE, 0.6)
	line.albedo_texture = _noise_tex(Color("#5e5032"), Color("#d9a81e"), 0.06, 41)
	line.uv1_triplanar = true
	line.uv1_world_triplanar = true
	line.uv1_scale = Vector3.ONE * 0.5
	mats.yellow_line = line
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.12, 0.14, 0.13, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.08
	glass.metallic = 0.4
	mats.glass = glass
	mats.metal = _pbr("rusty_metal_02", 0.9, 1.0, Color(0.8, 0.8, 0.8), "diff.jpg", 0.5)
	mats.metal_dark = _flat(Color("#1d1f22"), 0.5, 0.7)
	var red := _flat(Color("#C4121A"), 0.22)
	red.clearcoat_enabled = true
	red.clearcoat = 0.6
	mats.red = red
	mats.dial = _flat(Color("#B9B5AC"), 0.4, 0.3)
	mats.dial_label = _flat(Color("#e8e2d2"), 0.5)
	mats.phone_dark = _flat(Color("#141414"), 0.6)
	mats.door_window = _flat(Color("#0b0c0d"), 1.0)
	mats.blanket = _surface(Color("#4a5560"), 1.0, 1.5, 10)
	mats.mattress = _flat(Color("#8a8475"), 1.0)
	# gece penceresi: gündüz göğü gibi açık mavi değil, ay ışıklı koyu lacivert (alttan üste hafif açılır)
	glow_window = _glow(Color("#3a5888"), 0.6)
	var gece := GradientTexture2D.new()
	gece.width = 4
	gece.height = 64
	gece.fill_to = Vector2(0, 1)
	gece.gradient = Gradient.new()
	gece.gradient.set_color(0, Color(1.0, 1.0, 1.0))
	gece.gradient.set_color(1, Color(0.45, 0.5, 0.6))
	glow_window.emission_texture = gece
	glow_window.uv1_triplanar = false
	glow_window.albedo_color = Color(0.015, 0.02, 0.03)  # yalnız kendi ışığı görünsün (önündeki ay ışığı camı beyazlatmasın)
	glow_window.roughness = 1.0
	# duvar/zemin/metal: kalite >= 1 iken dünya koordinatlı kir katmanlı kopyaları (scripts/dunya.gd)
	preload("res://scripts/dunya.gd").malzeme_ciftleri(self, int(profile.settings.get("kalite", 1)) if profile else 1)
	ring_stream = Sfx.ring()
	# hücre kapısı (paslı çelik): kilit + menteşe gıcırtısı; kapanırken gıcırtı + 0.72 sn'de çarpma (tools/ortam_ses_uret.sh)
	snd_latch = load("res://assets/ses/kapi_kilit.ogg")
	snd_slam = load("res://assets/ses/kapi_carp.ogg")
	snd_click = load("res://assets/ses/tik.ogg")
	var creaks := AudioStreamRandomizer.new()
	creaks.add_stream(-1, load("res://assets/ses/kapi_gicirti_1.ogg"))
	creaks.add_stream(-1, load("res://assets/ses/kapi_gicirti_2.ogg"))
	creaks.random_pitch = 1.06
	snd_creak = creaks


func box(size: Vector3, pos: Vector3, mat: Material, collide := true, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


# Hazır 3D modeli yükler; tabanı (ya da top_y verilirse tepesi) o yüksekliğe, ortası pos'a gelir.
func model(id: String, pos: Vector3, yaw := 0.0, scale := 1.0, top_y := NAN, parent: Node = null) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	(parent if parent else self).add_child(holder)
	var inst: Node3D = load("res://assets/models/%s/%s.gltf" % [id, id]).instantiate()
	inst.scale = Vector3.ONE * scale
	holder.add_child(inst)
	var bb := _bounds(inst, holder)
	var c := bb.get_center()
	inst.position = Vector3(-c.x, -bb.position.y if is_nan(top_y) else -(bb.end.y), -c.z)
	if not is_nan(top_y):
		holder.position.y = top_y
	return holder


func _bounds(n: Node, rel: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var box_ := (mi as MeshInstance3D).get_aabb()
		var xf := rel.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		box_ = xf * box_
		out = box_ if first else out.merge(box_)
		first = false
	return out


# Görünmez çarpışma kutusu (modellerin içinden geçilmesin diye).
func solid(size: Vector3, pos: Vector3, yaw := 0.0, parent: Node = null) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = yaw
	(parent if parent else self).add_child(sb)


# Yüzü +z'ye bakan ince silindir (kadran, delik, ahize kulaklığı).
func _disc(parent: Node3D, pos: Vector3, radius: float, depth: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = depth
	c.radial_segments = 24
	mi.mesh = c
	mi.material_override = mat
	mi.rotation.x = PI / 2
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------- ortam ----------

func _build_environment() -> void:
	# Sinematik bodrum havası: soğuk koyu gölgeler + sıcak amber lambalar. Telefonda ucuz: SSAO/SSR/hacimsel sis yok;
	# yerine sahte AO şeritleri, yansıma sondası, sis ve sahte ışık huzmeleri (scripts/dunya.gd).
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.006, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# gölgeler soğuk (ay ışığı), biraz daha aydınlık: oynanış karanlıkta kalmasın
	env.ambient_light_color = Color(0.28, 0.34, 0.4)
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.2
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	# uzak sis hafif soğuk: sıcak lambalar onun önünde daha çok öne çıkar (derinlik)
	env.fog_light_color = Color(0.072, 0.07, 0.072)
	env.fog_density = 0.033
	env.fog_sky_affect = 0.0
	# sinematik renk ayarı (kanal başına eğri): koyu tonlar yeşil-mavi, açık tonlar sıcak, hafif S eğrisi
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.0
	var grade := Gradient.new()
	grade.set_color(0, Color(0.0, 0.016, 0.024))
	grade.add_point(0.2, Color(0.186, 0.197, 0.2))
	grade.add_point(0.45, Color(0.45, 0.445, 0.42))
	grade.add_point(0.75, Color(0.785, 0.762, 0.7))
	grade.set_color(grade.get_point_count() - 1, Color(1.0, 0.96, 0.88))
	var lut := GradientTexture1D.new()
	lut.gradient = grade
	lut.width = 256
	env.adjustment_color_correction = lut
	get_viewport().use_occlusion_culling = true  # hücre duvarları arkasındaki hücreler çizilmesin
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_corridor(perde: Node = null) -> void:  # perde: açılışta parça parça kurulur (her parçadan sonra bir kare)
	const Dunya := preload("res://scripts/dunya.gd")
	var x0 := CORRIDOR_X0
	var x1 := CORRIDOR_X1
	var cx := (x0 + x1) / 2.0
	var w := x1 - x0
	var zmin := -CORRIDOR_HALF
	var zmax := CORRIDOR_HALF
	for z in range(zmin, zmax, 4):
		box(Vector3(w, 0.2, 4.0), Vector3(cx, -0.1, z + 2.0), mats.corridor_floor)
		box(Vector3(w, 0.2, 4.0), Vector3(cx, H + 0.1, z + 2.0), mats.ceiling, false)
		box(Vector3(0.2, H, 4.0), Vector3(x1 + 0.1, H / 2, z + 2.0), mats.corridor_wall)
	# hücre duvarlarının arasındaki boşlukları ve uçları kapat
	var first := -(CELL_COUNT - 1) / 2.0 * CELL_SPACING
	var last := -first
	for k in CELL_COUNT - 1:
		box(Vector3(0.2, H, 0.2), Vector3(2.1, H / 2, first + (k + 0.5) * CELL_SPACING), mats.corridor_wall)
	var end_len := zmax - (last + 3.2)
	box(Vector3(0.2, H, end_len), Vector3(2.1, H / 2, zmin + end_len / 2), mats.corridor_wall)
	box(Vector3(0.2, H, end_len), Vector3(2.1, H / 2, zmax - end_len / 2), mats.corridor_wall)
	box(Vector3(w, H, 0.2), Vector3(cx, H / 2, zmin - 0.1), mats.corridor_wall)
	box(Vector3(w, H, 0.2), Vector3(cx, H / 2, zmax + 0.1), mats.corridor_wall)

	# süsler ayrı düğümde (gerekirse topluca gizlenebilir)
	var root := Node3D.new()
	root.name = "KoridorSusleri"
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# hücre tarafı duvar parçaları (kapı boşlukları hariç)
	var segs: Array = []
	var zz := float(zmin)
	for k in CELL_COUNT:
		var cz := (k - (CELL_COUNT - 1) / 2.0) * CELL_SPACING
		segs.append([zz, cz - 0.06])
		zz = cz + 1.06
	segs.append([zz, float(zmax)])
	# duvarların alt yarısı yeşil boyalı, üstünde koyu şerit (afişteki gibi)
	var bh := 1.25
	for s in segs:
		var a: float = s[0]
		var b: float = s[1]
		box(Vector3(0.02, bh, b - a), Vector3(x0 + 0.01, bh / 2, (a + b) / 2), mats.paint, false, root)
		box(Vector3(0.01, 0.06, b - a), Vector3(x0 + 0.02, bh, (a + b) / 2), mats.stripe, false, root)
	box(Vector3(0.02, bh, zmax - zmin), Vector3(x1 - 0.01, bh / 2, 0), mats.paint, false, root)
	box(Vector3(0.01, 0.06, zmax - zmin), Vector3(x1 - 0.02, bh, 0), mats.stripe, false, root)
	for e in [[zmin, 1.0], [zmax, -1.0]]:
		box(Vector3(w, bh, 0.02), Vector3(cx, bh / 2, float(e[0]) + float(e[1]) * 0.01), mats.paint, false, root)
	# zeminde aşınmış sarı kenar çizgileri
	for lx in [x0 + 0.32, x1 - 0.32]:
		box(Vector3(0.07, 0.004, zmax - zmin - 0.6), Vector3(lx, 0.002, 0), mats.yellow_line, false, root)

	# tavanda borular (karşı duvar) ve kablo kanalı (hücre tarafı)
	Dunya.boru(root, Vector3(x1 - 0.15, H - 0.24, zmin), Vector3(x1 - 0.15, H - 0.24, zmax), 0.075, mats.pipe)
	Dunya.boru(root, Vector3(x1 - 0.34, H - 0.13, zmin), Vector3(x1 - 0.34, H - 0.13, zmax), 0.045, mats.pipe)
	var clamp_mesh := BoxMesh.new()
	clamp_mesh.size = Vector3(0.42, 0.04, 0.06)
	var clamps: Array = []
	for z in range(zmin + 1, zmax, 2):
		clamps.append(Transform3D(Basis(), Vector3(x1 - 0.21, H - 0.19, z)))
	Dunya.coklu(root, clamp_mesh, mats.metal_dark, clamps)
	box(Vector3(0.16, 0.07, zmax - zmin), Vector3(x0 + 0.1, H - 0.08, 0), mats.metal_dark, false, root)

	if perde:
		await perde.adim(0.14)
	# kafesli amber duvar lambaları: hücre tarafında (hücreler arası) ışık verir, karşıda sadece parlar
	var lamp_z: Array = [zmin + 1.6]
	for k in CELL_COUNT - 1:
		lamp_z.append(first + (k + 0.5) * CELL_SPACING)
	lamp_z.append(zmax - 1.6)
	var lambalar: Array = []  # titreyebilen lambalar (dunya.gd Canlilik)
	for z in lamp_z:
		lambalar.append(Dunya.duvar_lambasi(self, root, Vector3(x0, 2.5, float(z)), Vector3.RIGHT, true, 2.8, 6.5))
	for z in range(-24, 25, 6):
		Dunya.duvar_lambasi(self, root, Vector3(x1, 2.5, float(z)), Vector3.LEFT, false)

	# karşı duvarda açılmayan hücre kapıları (tek seferde, MultiMesh ile)
	var doors: Array = []
	var k := 0
	for zf in range(zmin + 2, zmax - 1, 3):
		doors.append([x1, float(zf) + 0.5, -1.0, 40 + k, k % 3 == 1])
		k += 1
	Dunya.sahte_kapilar(self, doors, root)

	# uçta demir parmaklıklı kapı, arkasında ışık (koridorun kaçış noktası)
	var gz := float(zmin) + 0.9
	Dunya.parmaklik(root, Vector3(x0 + 0.1, 0, gz), Vector3.RIGHT, int((w - 0.2) / 0.15) + 1, 0.15, H - 0.3, 0.02, mats.door, 3)
	box(Vector3(w, 0.14, 0.14), Vector3(cx, H - 0.25, gz), mats.door, false, root)
	solid(Vector3(w, H, 0.12), Vector3(cx, H / 2, gz), 0.0, root)
	lambalar.append(Dunya.duvar_lambasi(self, root, Vector3(cx, 2.4, float(zmin)), Vector3.BACK, true, 2.6, 3.2, Color("#ffc178")))
	Dunya.levha(root, "B BLOK", Vector3(cx, H - 0.5, gz + 0.09), 0.0, Vector2(1.1, 0.3), mats.stripe, Color("#e9d9b0"), 120)
	var hz := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(w - 0.3, 0.3)
	hz.mesh = hq
	hz.material_override = Dunya.hazard_mat()
	hz.rotation.x = -PI / 2
	hz.position = Vector3(cx, 0.004, gz + 0.4)
	root.add_child(hz)

	# öbür uçta gardiyan kulübesi: metal alt duvar, camlar, içinde masa, monitör ve lamba
	var kul: Dictionary = Dunya.kulube(self, root, x1, zmax)

	if perde:
		await perde.adim(0.2)
	# levhalar, güvenlik kameraları, sigorta dolabı, "ıslak zemin" uyarısı
	var plate: StandardMaterial3D = _flat(Color("#c9a227"), 0.6, 0.2)
	Dunya.levha(root, "KOŞMAK\nYASAKTIR", Vector3(x1 - 0.015, 1.75, 9.0), -PI / 2, Vector2(0.62, 0.42), plate, Color("#141414"), 70)
	Dunya.levha(root, "SESSİZLİK", Vector3(x1 - 0.015, 1.8, -9.0), -PI / 2, Vector2(0.7, 0.24), mats.stripe, Color("#e9d9b0"), 70)
	Dunya.levha(root, "SAYIM\n22:00", Vector3(x1 - 0.015, 1.75, -21.0), -PI / 2, Vector2(0.5, 0.42), plate, Color("#141414"), 70)
	var kameralar: Array = [
		model("security_camera_02", Vector3(x0 + 0.35, H - 0.45, zmax - 3.2), PI, 0.75, NAN, root),
		model("security_camera_02", Vector3(x1 - 0.35, H - 0.45, zmin + 2.4), 0.0, 0.75, NAN, root),
	]
	model("utility_box_01", Vector3(x1 - 0.22, 0, -15.0), -PI / 2, 0.75, NAN, root)
	solid(Vector3(0.45, 1.3, 0.7), Vector3(x1 - 0.22, 0.65, -15.0), 0.0, root)
	model("WetFloorSign_01", Vector3(x1 - 0.55, 0, 6.9), -PI / 2 + 0.4, 1.0, NAN, root)
	solid(Vector3(0.35, 0.65, 0.35), Vector3(x1 - 0.55, 0.32, 6.9), 0.0, root)

	# lekeler: su birikintileri (yansıma sondasıyla ıslak parlar), kir, çatlak, borulardan pas akıntısı
	var birikintiler: Array = []
	for p in [[cx + 0.3, -21.0, 2.2], [cx - 0.4, -12.6, 1.6], [cx + 0.6, -4.2, 1.2], [x1 - 0.9, 6.4, 1.8], [cx - 0.2, 11.4, 2.4], [cx + 0.2, 19.5, 1.5]]:
		Dunya.leke_zemin(root, "su", Vector3(float(p[0]), 0, float(p[1])), Vector2(float(p[2]), float(p[2]) * 0.7), rng.randf() * TAU)
		birikintiler.append(Vector3(float(p[0]), 0, float(p[1])))
	for i in 14:
		var side := x0 + 0.45 if i % 2 == 0 else x1 - 0.45
		Dunya.leke_zemin(root, "kir", Vector3(side, 0, rng.randf_range(zmin + 2, zmax - 3)), Vector2(1.4, 1.0) * rng.randf_range(0.8, 1.5), rng.randf() * TAU, Color(1, 1, 1, 0.8))
	for i in 5:
		Dunya.leke_zemin(root, "catlak", Vector3(cx + rng.randf_range(-0.8, 0.8), 0, rng.randf_range(zmin + 3, zmax - 4)), Vector2(1.3, 1.3), rng.randf() * TAU)
	for z in [-21.0, -9.0, 3.0, 15.0, 21.0]:
		Dunya.leke_duvar(root, "pas", Vector3(x1 - 0.01, 2.2, z + rng.randf_range(-0.3, 0.3)), Vector3.LEFT, Vector2(0.7, 1.9))
	for z in lamp_z:
		Dunya.leke_duvar(root, "catlak", Vector3(x0 + 0.01, rng.randf_range(0.6, 2.0), float(z) + rng.randf_range(-1.6, 1.6)), Vector3.RIGHT, Vector2(0.9, 0.9), Color(1, 1, 1, 0.7))

	if perde:
		await perde.adim(0.25)
	# sahte ortam gölgesi: duvar dipleri ve tavan köşeleri koyulaşır
	var o := 0.024
	var ao: Array = [
		[Vector3(x0 + o, 0.004, zmin), Vector3(x0 + o, 0.004, zmax), Vector3.RIGHT, 0.4],
		[Vector3(x1 - o, 0.004, zmin), Vector3(x1 - o, 0.004, zmax), Vector3.LEFT, 0.4],
		[Vector3(x1 - o, 0.004, zmin), Vector3(x1 - o, 0.004, zmax), Vector3.UP, 0.32],
		[Vector3(x0 + 0.004, H - 0.004, zmin), Vector3(x0 + 0.004, H - 0.004, zmax), Vector3.DOWN, 0.5],
		[Vector3(x1 - 0.004, H - 0.004, zmin), Vector3(x1 - 0.004, H - 0.004, zmax), Vector3.DOWN, 0.5],
		[Vector3(x0 + 0.004, H - 0.004, zmin), Vector3(x0 + 0.004, H - 0.004, zmax), Vector3.RIGHT, 0.45],
		[Vector3(x1 - 0.004, H - 0.004, zmin), Vector3(x1 - 0.004, H - 0.004, zmax), Vector3.LEFT, 0.45],
	]
	for s in segs:
		ao.append([Vector3(x0 + o, 0.004, float(s[0])), Vector3(x0 + o, 0.004, float(s[1])), Vector3.UP, 0.32])
	# eşyaların altında temas gölgesi (sigorta dolabı, ıslak zemin levhası, kulübe)
	Dunya.ao_ag(root, ao, 0.55, [[Vector3(x1 - 0.24, 0, -15.0), 0.36, 0.5, 0.0, 0.25], [Vector3(x1 - 0.55, 0, 6.9), 0.32, 0.3, 0.4, 0.4],
		[Vector3((3.8 + x1) / 2.0, 0, zmax - 1.15), 1.1, 1.35, 0.0, 0.35]])

	# canlılık: tavan pencerelerinden ay ışığı, havalandırma buharı, kamera ışıkları, titreyen lambalar, damlayan su,
	# kopuk kablodan kıvılcım, nefes buharı, toz zerreleri (scripts/dunya.gd koridor_ekleri, scripts/efekt.gd)
	Dunya.koridor_ekleri(self, root, x0, x1, H, lambalar, kul, kameralar, birikintiler)
	preload("res://scripts/efekt.gd").hazirla(self)  # efekt havuzu: ilk kullanımda düğüm/gölgelendirici üretimi olmasın

	# koridorda dolaşan mahkum (NPC) kullanıcı isteğiyle kaldırıldı; koridorda yalnız gerçek oyuncular olur

	# ıslak zemin yansımaları: tek sefer çekilen, kutu izdüşümlü yansıma sondası (telefonda ucuz)
	probe = ReflectionProbe.new()
	probe.size = Vector3(w, H, zmax - zmin)
	probe.position = Vector3(cx, H / 2, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.interior = true
	probe.intensity = 0.9
	add_child(probe)


# Koridor duvarındaki açılmayan hücre kapısı. side: +1 = +x'e bakar, -1 = -x'e bakar.
func _fake_door(x: float, z: float, side: float, number: int, leak: bool) -> void:
	preload("res://scripts/dunya.gd").sahte_kapilar(self, [[x, z, side, number, leak]], self)


# ---------- ana menü arka planı ----------

# Menünün arkasında: sisli koridorda yavaşça ilerleyen kamera ve yerden yükselen buhar.
func _build_menu_scene() -> void:
	# Kamera bir "ray" üstünde: _process kameranın z'sini ve hafif sağa-sola bakışını sürer; ray onu alçak,
	# hücre kapılarına yakın ve çok hafif yatık (sinematik) tutar. Koridorun sonunda parmaklıklı kapı ışıkla parlar.
	var rig := Node3D.new()
	rig.name = "MenuKameraRayi"
	rig.position = Vector3(-0.55, -0.45, 0.0)
	rig.rotation.z = deg_to_rad(-1.2)
	add_child(rig)
	menu_cam = Camera3D.new()
	menu_cam.fov = 58.0
	rig.add_child(menu_cam)
	menu_cam.position = Vector3(3.9, 1.75, 20.0)
	menu_cam.rotation = Vector3(deg_to_rad(1.5), 0, 0)
	menu_cam.current = true
	menu_cam.tree_exiting.connect(rig.queue_free)
	# yerden yükselen sıcak buhar
	var m := StandardMaterial3D.new()
	m.albedo_texture = preload("res://scripts/dunya.gd")._radial_tex()  # yumuşak yuvarlak (halelerle aynı)
	m.albedo_color = Color(0.95, 0.82, 0.62, 0.2)
	m.texture_repeat = false
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.proximity_fade_enabled = true  # zemine/duvara değdiği yerde sert kenar olmasın
	m.proximity_fade_distance = 0.8
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	q.material = m
	for z in [14.0, 6.0, -2.0]:
		var steam := CPUParticles3D.new()
		steam.mesh = q
		steam.amount = 14
		steam.lifetime = 6.0
		steam.preprocess = 6.0
		steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		steam.emission_box_extents = Vector3(1.2, 0.05, 0.6)
		steam.direction = Vector3(0, 1, 0)
		steam.spread = 25.0
		steam.initial_velocity_min = 0.15
		steam.initial_velocity_max = 0.35
		steam.gravity = Vector3.ZERO
		steam.scale_amount_min = 0.8
		steam.scale_amount_max = 1.8
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0))
		fade.add_point(0.3, Color(1, 1, 1, 1))
		fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
		steam.color_ramp = fade
		steam.position = Vector3(3.9 + (0.6 if z < 10.0 else -0.5), 0.05, z)
		add_child(steam)


func open_friends() -> void:
	var f: CanvasLayer = FriendsScript.new()
	f.account = account
	f.profile = profile
	f.net = net
	add_child(f)


# ---------- karakter ve mağaza ----------

func open_character() -> CanvasLayer:
	var ch: CanvasLayer = CharacterScript.new()
	ch.profile = profile
	ch.account = account
	ch.closed.connect(_on_character_closed)
	add_child(ch)
	return ch


# Envanter: giyilen parça hemen kaydedilir; kapanınca oyuncu ve menü güncellenir.
func open_inventory() -> CanvasLayer:
	var inv: CanvasLayer = EnvanterScript.new()
	inv.profile = profile
	inv.closed.connect(_on_character_closed)
	inv.open_store.connect(func() -> void: open_character())
	add_child(inv)
	return inv


# Elmas mağazası (menüdeki ve mağazadaki "+" düğmeleri: get_tree().current_scene.open_gem_store()).
# Kapanınca menü ve oyun içi elmas sayaçları güncellenir.
func open_gem_store() -> CanvasLayer:
	var g: CanvasLayer = preload("res://scripts/elmas_magaza.gd").new()
	g.account = account
	g.profile = profile
	g.closed.connect(func() -> void:
		hud.refresh_gems(profile.gems)
		if menu and menu.has_method("refresh_profile"):
			menu.refresh_profile())
	add_child(g)
	return g


func _on_character_closed(saved: bool) -> void:
	if not saved:
		return
	player.set_look(profile.look)
	menu.refresh_profile()
	hud.refresh_gems(profile.gems)
	if online:
		net.send({"t": "profil", "ad": profile.player_name, "g": profile.look})


# ---------- oyunun başlaması ----------

func _start_solo() -> void:
	online = false
	_begin(0)
	hud.set_players([{"id": 1, "name": "Sen", "cell": 0}, {"id": 2, "name": "Deniz", "cell": 1}], 1)


# Odaya girince: 3D bekleme salonuna ışınlan, salondaki herkesle yakınlık sesiyle konuş.
func _enter_lobby() -> void:
	in_lobby = true
	online = true
	playing = true
	menu.visible = false
	player.camera.current = true
	if menu_cam:
		menu_cam.queue_free()
		menu_cam = null
	player.global_position = lobby.spawn_point(net.my_cell)
	player.rotation.y = 0.0
	player.set_physics_process(true)
	hud.visible = true
	hud.show_lobby(true)
	lobby.set_code(net.room_code)
	_refresh_lobby()


# Maç sonu ekranında TEKRAR OYNA: sunucuya haber ver, sahneyi yeniden yüklemeden aynı odanın salonuna geç.
func _tekrar_oyna() -> void:
	if in_lobby:
		return
	if not net.connected:
		# oda bağlantısı yok (koptu): ana menüye
		account.set_room("")
		net.leave()
		get_tree().reload_current_scene()
		return
	telemetri.event("tekrar_oyna", {})
	net.send({"t": "tekrar"})
	_lobiye_don()


# Sunucu bizi salona aldı (TEKRAR OYNA'nın cevabı ya da maç sonu süresi doldu).
func _on_lobby_back() -> void:
	if not in_lobby:
		_lobiye_don()
	elif playing:
		_refresh_lobby()


# Maçtan bekleme salonuna dönüş: önceki maçtan kalan her şey temizlenir (oyun ekranları, eşyalar,
# cesetler, kapılar, elektrik, telefon hatları), oyuncu hücresinden salona ışınlanır, HUD salon düzenine,
# ses/müzik/ortam salona döner. Arkadaşlar bizi yeniden ODADA görür.
func _lobiye_don() -> void:
	_end_call_local()
	_mesgul_kalan = 0.0
	phone_state = Phone.IDLE
	voice.phone_line = false
	muzik.set_call(false)
	game_ui.reset_after_match()  # maç sonu ekranı, oyun ekranları ve oyunların 3D eşyaları (cleanup)
	game_on = false
	game_left = 0.0
	game_alive = []
	_music_task = ""
	_near_board = false
	_stall_t = 0.0
	current_target = ""
	for c in cells:
		c.mac_sonrasi()
	# uzak oyuncuların gövdeleri (ölü pozu, elindeki eşya, ahize) baştan kurulsun: salonda yeniden belirirler
	for id in remotes.keys():
		_remove_remote(id)
	player.reset_state()
	player.velocity = Vector3.ZERO
	hud.hide_call()
	_set_call_bar("")
	hud.ring_label.visible = false
	hud.contacts.visible = false
	hud.set_action("")
	hud.set_ptt(false)
	hud.set_alive(net.players.map(func(p) -> int: return int(p.id)))
	muzik.ortam_izin(true)  # salonda ortam sesi yeniden
	muzik.play("menu", 1.5)  # salonun müziği (odaya ilk girişteki gibi)
	account.set_room(net.room_code, false)  # arkadaşlar: ODADA (sonraki maç başlayınca MAÇTA)
	_enter_lobby()
	voice.start()
	_on_players_changed()
	place_bots()


func _refresh_lobby() -> void:
	hud.update_lobby(net.room_code, net.players, net.my_id, net.is_host)
	lobby.set_count(net.players.size())


func _on_started() -> void:
	if in_lobby:
		hud.geri_sayim(3)  # salondan maça: ortada 3-2-1 (sonradan izleyici olarak girende yok)
	muzik.ortam_izin(true)
	telemetri.event("mac_basla", {"oyuncu": net.players.size()})
	muzik.play("", 1.0)
	muzik.announce("mac_basliyor")
	in_lobby = false
	hud.show_lobby(false)
	voice.start()  # oyunda da yakındakiler birbirini duyar (ses kapısı sessizlikte paket yollamaz)
	online = true
	_begin(net.my_cell)
	_on_players_changed()
	place_bots()


func _begin(cell: int) -> void:
	my_cell = cell
	player.camera.current = true
	if menu_cam:
		menu_cam.queue_free()
		menu_cam = null
	var used := maxi(cell + 1, 2)
	if online:
		for p in net.players:
			used = maxi(used, int(p.cell) + 1)
	for k in range(used, CELL_COUNT):
		cells[k].lock_empty()
	cells[cell].set_detailed(true)
	player.global_position = cells[cell].spawn_world()
	player.rotation.y = 0.0
	menu.visible = false
	hud.visible = true
	playing = true
	player.set_physics_process(true)


# Oyun sırasında bağlantı koptu: ekranı kapatmadan yeniden bağlanmayı dene.
var _reconnect_ui: CanvasLayer
var _reconnect_label: Label


func _on_reconnecting(left: float) -> void:
	if not _reconnect_ui:
		_reconnect_ui = CanvasLayer.new()
		_reconnect_ui.layer = 40
		add_child(_reconnect_ui)
		var dim := ColorRect.new()
		dim.color = Color(0.0, 0.0, 0.02, 0.72)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_reconnect_ui.add_child(dim)
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 10)
		_reconnect_ui.add_child(v)
		v.add_child(UI.title("BAĞLANTI KOPTU", 46, Color("#ffcf8a"), true))
		_reconnect_label = UI.label("", 22, Color(0.85, 0.87, 0.92), true)
		v.add_child(_reconnect_label)
	_reconnect_ui.visible = true
	_reconnect_label.text = tr("Yeniden bağlanılıyor…  %d") % ceili(left)
	_end_call_local()


func _on_rejoined() -> void:
	if _reconnect_ui:
		_reconnect_ui.visible = false
	hud.show_toast("Oyuna geri döndün!")
	_send_profile()
	net.send({"t": "hatlar"})  # telefonda olanların listesi (koparken kaçmış olabilir)
	net.send({"t": "durum"})


func _on_net_failed(msg: String) -> void:
	if _reconnect_ui:
		_reconnect_ui.visible = false
	if playing and online:
		_end_call_local()
		hud.show_toast(msg)
	else:
		menu.show_error(msg)


# ---------- diğer oyuncular ----------

func _on_players_changed() -> void:
	if not playing:
		return
	game_ui.mac_sonu_oyuncular(net.players)  # maç sonu ekranındaki LOBİDE / ÇIKTI etiketleri
	hud.set_players(net.players, net.my_id)
	if in_lobby:
		_refresh_lobby()
	if not game_on:
		place_bots()
	var ids := {}
	for p in net.players:
		var id := int(p.id)
		ids[id] = true
		if remotes.has(id):
			_apply_remote_profile(id)
	for id in remotes.keys():
		if not ids.has(id):
			_remove_remote(id)


func is_bot(id: int) -> bool:
	return bool(_player_entry(id).get("bot", false))


# Botların bilgisayarı yok, konum yollamazlar: gövdelerini bu istemci kendi hücrelerine (lobide salona) koyar.
func place_bots() -> void:
	if not playing:
		return
	for p in net.players:
		if not bool(p.get("bot", false)):
			continue
		var id := int(p.id)
		var pos: Vector3 = lobby.spawn_point(int(p.cell)) if in_lobby else cells[int(p.cell)].spawn_world() + Vector3(0.3, 0, -0.6)
		var yaw := 0.0 if in_lobby else PI
		if not remotes.has(id):
			_on_remote_state(id, {"p": [pos.x, pos.z], "y": yaw, "o": false})
		var r: Dictionary = remotes[id]
		r.target = pos
		r.root.position = pos
		r.yaw = yaw


func _player_entry(id: int) -> Dictionary:
	for p in net.players:
		if int(p.id) == id:
			return p
	return {}


# Diğer oyuncunun adı ve görünüşü değiştiyse karakterini yeniden giydirir.
func _apply_remote_profile(id: int) -> void:
	var r: Dictionary = remotes[id]
	var p := _player_entry(id)
	var look_json := JSON.stringify(p.get("g", {}))
	if look_json != r.get("look", ""):
		r.look = look_json
		r.body.set_look(p.get("g", {}))
	r.label.text = str(p.get("name", "?"))
	_remote_etiket(r, p)


# Baş üstü etiketler: salonda adın üstünde yeşil HAZIR / kırmızı HAZIR DEĞİL (botlar hep hazır; maç başlayınca
# kalkar), mikrofonunu kapatanın en üstte küçük kırmızı çizik mikrofonu (salonda ve maçta).
func _remote_etiket(r: Dictionary, p: Dictionary) -> void:
	var hz: Label3D = r.get("hazir")
	if hz:
		var on := bool(p.get("r", false)) and not bool(p.get("ms", false))
		hz.visible = in_lobby and not p.is_empty()
		hz.text = tr("HAZIR") if on else tr("HAZIR DEĞİL")
		hz.modulate = UI.YESIL.lightened(0.15) if on else Color("#ff5a4e")
	# bağlantısı kopan (geri dönmesi bekleniyor): çizik sinyal; değilse mikrofonu kapalıysa çizik mikrofon
	var kopuk := bool(p.get("kopuk", false))
	var kapali := bool(p.get("mk", false)) and not kopuk
	var s: Sprite3D = r.get("mik")
	if (kapali or kopuk) and s == null:
		s = Sprite3D.new()
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.pixel_size = 0.0042
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD  # saydam geçişte sise / ışığa karışıp sönük görünmesin
		s.modulate = Color(1.35, 1.35, 1.35)
		(r.root as Node3D).add_child(s)
		r["mik"] = s
	if s:
		s.texture = _kopuk_doku() if kopuk else _mik_kapali_doku()
		s.visible = kapali or kopuk
		s.position.y = _etiket_ust(r)
	(r.label as Label3D).modulate = Color(0.6, 0.6, 0.6) if kopuk else Color.WHITE


# Etiket yığınının en üstü (ad, salonda HAZIR yazısı): konuşma dalgası ya da çizik mikrofon buraya.
func _etiket_ust(r: Dictionary) -> float:
	var lab: Label3D = r.label
	var hz: Label3D = r.get("hazir")
	return lab.position.y + (0.46 if hz and hz.visible else 0.26)


static var _mik_kapali_tex: ImageTexture
static var _kopuk_tex: ImageTexture


# Bağlantı koptu simgesi: koyu daire + gri sinyal çubukları + kırmızı çizik (koddan, bir kez)
static func _kopuk_doku() -> ImageTexture:
	if _kopuk_tex:
		return _kopuk_tex
	var n := 72
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(n / 2.0, n / 2.0)
	var kirmizi := Color("#ff5a4e")
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= 34.5:
				img.set_pixel(x, y, kirmizi if d > 30.0 else Color(0.06, 0.07, 0.07, 0.94))
	for i in 4:
		var h := int(10 + i * 7)
		img.fill_rect(Rect2i(17 + i * 10, 52 - h, 7, h), Color(0.75, 0.77, 0.75))
	for kat in [[4.6, Color(0, 0, 0, 0.85)], [2.8, kirmizi]]:
		var w: float = kat[0]
		var col: Color = kat[1]
		for y in n:
			for x in n:
				var q := Vector2(x + 0.5, y + 0.5) - c
				if absf(q.x - q.y) / 1.4142 <= w and q.length() <= 24.0:
					img.set_pixel(x, y, col)
	_kopuk_tex = ImageTexture.create_from_image(img)
	return _kopuk_tex


# Kırmızı halkalı koyu daire + soluk mikrofon + kırmızı çizik (koddan, bir kez)
static func _mik_kapali_doku() -> ImageTexture:
	if _mik_kapali_tex:
		return _mik_kapali_tex
	var n := 72
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(n / 2.0, n / 2.0)
	var kirmizi := Color("#ff5a4e")
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= 34.5:
				img.set_pixel(x, y, kirmizi if d > 30.0 else Color(0.28, 0.04, 0.03, 0.94))
	# sade beyaz mikrofon (küçük boyda okunsun): kapsül + U tutucu + sap + taban
	var beyaz := Color(0.95, 0.93, 0.88)
	for y in n:
		for x in n:
			var q := Vector2(x + 0.5, y + 0.5)
			var kaps := Geometry2D.get_closest_point_to_segment(q, Vector2(36, 20), Vector2(36, 32)).distance_to(q) <= 8.0
			var u := q.y >= 32.0 and absf(q.distance_to(Vector2(36, 32)) - 13.0) <= 2.0
			var sap := absf(q.x - 36.0) <= 2.0 and q.y >= 45.0 and q.y <= 54.0
			var taban := absf(q.x - 36.0) <= 9.0 and q.y >= 52.0 and q.y <= 56.0
			if kaps or u or sap or taban:
				img.set_pixel(x, y, beyaz)
	# çizik: koyu kenarlı kırmızı çapraz çizgi
	for kat in [[4.6, Color(0, 0, 0, 0.85)], [2.8, kirmizi]]:
		var w: float = kat[0]
		var col: Color = kat[1]
		for y in n:
			for x in n:
				var q := Vector2(x + 0.5, y + 0.5) - c
				if absf(q.x - q.y) / 1.4142 <= w and q.length() <= 24.0:
					img.set_pixel(x, y, col)
	_mik_kapali_tex = ImageTexture.create_from_image(img)
	return _mik_kapali_tex


func _on_remote_state(id: int, d: Dictionary) -> void:
	if not playing or id == net.my_id:
		return
	if not remotes.has(id):
		# diğer oyuncular katı: içinden geçilmez
		var root := AnimatableBody3D.new()
		root.sync_to_physics = false
		var rc := CollisionShape3D.new()
		var rs := CapsuleShape3D.new()
		rs.radius = 0.3
		rs.height = 1.7
		rc.shape = rs
		rc.position.y = 0.85
		root.add_child(rc)
		add_child(root)
		var body: Node3D = BodyScript.new()
		root.add_child(body)
		var label := Label3D.new()
		label.text = net.player_name(id)
		label.font_size = 48
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 2.05
		label.outline_size = 8
		root.add_child(label)
		# salonda adın üstünde HAZIR / HAZIR DEĞİL (maç başlayınca gizlenir; _remote_etiket)
		var hz := Label3D.new()
		hz.font_size = 40
		hz.pixel_size = 0.004
		hz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hz.position.y = label.position.y + 0.2
		hz.outline_size = 10
		hz.outline_modulate = Color(0.04, 0.03, 0.02, 0.95)
		hz.font = UI.TITLE_FONT
		hz.visible = false
		root.add_child(hz)
		var p0: Array = d.p
		root.position = Vector3(p0[0], 0, p0[1])
		remotes[id] = {"root": root, "body": body, "label": label, "hazir": hz, "target": root.position, "yaw": 0.0, "seated": false}
		_apply_remote_profile(id)
	var r: Dictionary = remotes[id]
	var p: Array = d.p
	r.target = Vector3(float(p[0]), 0, float(p[1]))
	r.yaw = float(d.y)
	r.seated = bool(d.o)
	r.body.crouched = bool(d.get("k", false))
	r.label.text = net.player_name(id) + (tr("  (telefonda)") if bool(d.get("c", false)) else "")
	r["call"] = bool(d.get("c", false))


func _remove_remote(id: int) -> void:
	if remotes.has(id):
		var hs = remotes[id].get("ahize")
		if hs and is_instance_valid(hs):
			# telefondayken çıktı: ahizesi çatalına döner
			var ci := int(_player_entry(id).get("cell", -1))
			if ci >= 0 and ci < cells.size():
				cells[ci].set_handset_lifted(false)
			hs.queue_free()
		remotes[id].root.queue_free()
		remotes.erase(id)


func _update_remotes(delta: float) -> void:
	for id in remotes:
		var r: Dictionary = remotes[id]
		var root: Node3D = r.root
		var before := root.position
		root.position = root.position.lerp(r.target, minf(1.0, delta * 10.0))
		root.rotation.y = lerp_angle(root.rotation.y, r.yaw, minf(1.0, delta * 10.0))
		var speed := Vector2(root.position.x - before.x, root.position.z - before.z).length() / maxf(delta, 0.001)
		r.body.walk = clampf(speed / 2.4, 0.0, 1.0)
		r.body.seated = r.seated
		Sfx.uzak_adim(r, root, speed / 2.4, bool(r.body.get("crouched")), bool(r.seated), delta)  # ayak + koltuk sesi
		_remote_phone(id, r, delta)


# Telefonda konuşan uzak oyuncu: gerçek eli kendi hücresindeki ahizeyi kulağına tutar, spiral kablo eline uzanır.
func _remote_phone(id: int, r: Dictionary, delta: float) -> void:
	var on := bool(r.get("call", false)) and not in_lobby
	var hs: Node3D = r.get("ahize")
	if not on and hs == null:
		return
	var mod: Node = AimModScript.of_body(r.body)
	if not mod:
		return
	var cell_i := int(_player_entry(id).get("cell", -1))
	var cell: Node3D = cells[cell_i] if cell_i >= 0 and cell_i < cells.size() else null
	if on and hs == null:
		if mod.mode != "":
			return  # elinde silah/bomba var (oyun pozu öncelikli)
		hs = Node3D.new()
		hs.name = "UzakAhize"
		add_child(hs)
		var h: Node3D = TelefonScript.handset(hs)
		h.scale = Vector3.ONE * TelefonScript.SCALE
		h.get_node("kablo_ucu").reparent(hs)
		r["ahize"] = hs
		r["call_w"] = 0.0
		mod.mode = "ahize"
		mod.hold(1, hs, AimModScript.item_offset("ahize", 1))
		hs.visible = false
		if cell and cell.handset_home:
			# ahize çataldan kalkar (ilk kare elin olduğu yerde belirsin diye bir kare sonra görünür)
			cell.set_handset_lifted(true, hs)
	var w_now: float = r.get("call_w", 0.0)
	w_now = move_toward(w_now, 1.0 if on else 0.0, delta * 2.5)
	r["call_w"] = w_now
	if mod.mode == "ahize":
		mod.aim = smoothstep(0.0, 1.0, w_now)
	if on:
		hs.visible = true
		return
	if w_now <= 0.0:
		# kapattı: ahize çatala döner, el serbest
		if mod.mode == "ahize":
			mod.mode = ""
			mod.aim = 0.0
			mod.hold(1, null)
		if cell:
			cell.slip_handset(hs.global_transform)
		hs.queue_free()
		r.erase("ahize")


func _send_state(delta: float) -> void:
	_send_t += delta
	if _send_t < 0.12:
		return
	_send_t = 0.0
	var gp := player.global_position
	var d := {"t": "konum", "p": [snappedf(gp.x, 0.01), snappedf(gp.z, 0.01)], "y": snappedf(player.rotation.y, 0.01),
		"o": player.seated, "c": phone_state == Phone.CALL, "k": player.crouched}
	var s := JSON.stringify(d)
	if s != _last_sent:
		_last_sent = s
		net.send(d)


# ---------- oyun döngüsü ----------

func _process(delta: float) -> void:
	player.move_input = test_move if test_move != Vector2.ZERO else hud.move
	player.sprint = hud.sprint
	_update_walker(delta)
	if _push_t > 0.0:
		_push_t -= delta
		if _push_t <= 0.0:
			account.push_profile(profile.to_cloud())
	if not playing:
		if menu_cam:
			_menu_t += delta
			menu_cam.position.z = 20.0 - fmod(_menu_t * 0.35, 14.0)
			menu_cam.rotation.y = sin(_menu_t * 0.15) * 0.08
		return
	profile.tick_play(delta)
	_update_drip(delta)
	if in_lobby:
		hud.set_action("")
	else:
		_update_phone(delta)
		_update_target()
	_update_voice_space(delta)
	_update_remotes(delta)
	if online:
		_send_state(delta)
	if game_on:
		if game_ui.mod:
			game_ui.mod.process(delta)
		var before_left := game_left
		game_left = maxf(0.0, (_game_end_tick - Time.get_ticks_msec()) / 1000.0)
		if before_left > 15.0 and game_left <= 15.0 and str(game_ui.state.get("phase", "")) in ["telefon", "calisma", "yaz1", "oylama"]:
			muzik.announce("son_15")
		hud.set_game_timer(game_left)
		# süre bittiği hâlde yeni durum gelmediyse sunucudan iste (kaçan mesaj olursa takılı kalmasın)
		if game_left <= 0.0:
			_stall_t += delta
			if _stall_t > 4.0:
				_stall_t = 0.0
				net.send({"t": "durum"})
		else:
			_stall_t = 0.0
		var bd: float = player.global_position.distance_to(cells[my_cell].board_world() * Vector3(1, 0, 1))
		if bd < 1.25 and not _near_board:
			_near_board = true
			game_ui.open_board()
		elif bd > 2.1:
			_near_board = false
	else:
		round_left -= delta
		if round_left <= 0.0:
			round_left = ROUND_TIME
		hud.set_timer(round_left)


func _unhandled_input(event: InputEvent) -> void:
	if playing and event.is_action_pressed("etkilesim"):
		_do_action()
	if playing and event.is_action_pressed("egil"):
		player.toggle_crouch()


func _nearest_cell() -> int:
	var z := player.global_position.z
	return clampi(roundi(z / CELL_SPACING + (CELL_COUNT - 1) / 2.0), 0, CELL_COUNT - 1)


func _update_target() -> void:
	var cam: Camera3D = player.camera
	var fwd := -cam.global_transform.basis.z
	var best := ""
	var best_score := -INF
	var ci := _nearest_cell()
	var c: Node3D = cells[ci]
	var mine: Node3D = cells[my_cell]
	var targets := [["chair", c.chair_world() + Vector3(0, 0.5, 0), 2.0], ["door", c.door_world(), 2.2]]
	if phone_state == Phone.RINGING or phone_state == Phone.IDLE:
		# telefon sadece kendi hücrende ve ayaktayken, kol boyu uzaklıktan alınır
		if not player.seated and ci == my_cell:
			targets.append(["phone", mine.phone_world(), 1.7])
	if game_on and ci == my_cell:
		if game_ui.tahta_var(): targets.append(["board", mine.board_world(), 2.6])  # tahta bu oyunda işe yarıyorsa (game_ui)
		if str(game_ui.state.get("task", "")) == "devre" and str(game_ui.state.get("phase", "")) == "calisma":
			targets.append(["kutu", mine.fuse_world(), 2.2])
	if ci == my_cell:
		targets.append(["pc", mine.pc_world(), 2.0])
	# yeni oyunların hedefleri (dolap, bombayı ver...): "m:" ile başlar
	var mod_labels := {}
	if game_on and game_ui.mod:
		for t in game_ui.mod.targets(ci):
			targets.append(["m:" + str(t[0]), t[1], t[2]])
			mod_labels["m:" + str(t[0])] = str(t[3])
	for t in targets:
		var to: Vector3 = t[1] - cam.global_position
		var d := to.length()
		if d > t[2]:
			continue
		var facing := fwd.dot(to.normalized())
		if facing < 0.5 and not (t[0] == "phone" and player.seated):
			continue
		var score := facing - d * 0.15 + (2.0 if t[0] == "phone" and phone_state == Phone.RINGING else 0.0)
		if score > best_score:
			best_score = score
			best = t[0]
	if player.seated and best != "phone":
		best = "chair"
	if game_on and game_ui.mod and game_ui.mod.locks_seat():
		best = ""  # rulette masadan kalkılmaz
	# konuşurken tahta/kutu/bilgisayar kullanılabilir; başka yere bakınca düğme telefonu kapatır
	if (phone_state == Phone.CALL or phone_state == Phone.DIALING) and not (best in ["board", "kutu", "pc"] or best.begins_with("m:")):
		best = "hangup"
	if best == "door" and game_on and not _doors_free():
		best = ""  # oyunda kapılar kilitli (C4 hariç)
	current_target = best
	current_cell = ci
	match best:
		"board":
			hud.set_action(game_ui.tahta_yazisi())  # oyuna göre: Tahtaya yaz / Tahtayı oku / Eşleştir / Oy ver / Sayı yaz
		"kutu":
			hud.set_action("Sigorta kutusu")
		"pc":
			hud.set_action("Bilgisayar")
		"chair":
			hud.set_action("Kalk" if player.seated else "Otur")
		"door":
			hud.set_action("Kapıyı kapat" if c.door_open else "Kapıyı aç")
		"phone":
			if phone_state == Phone.RINGING:
				hud.set_action("Cevapla", true)
			else:
				hud.set_action("Ara", true)
		"hangup":
			hud.set_action("Kapat", true)
		_:
			hud.set_action(mod_labels.get(best, ""))


func _do_action() -> void:
	if player.busy or not playing:
		return
	var c: Node3D = cells[current_cell] if current_cell >= 0 else cells[my_cell]
	match current_target:
		"chair":
			if player.seated:
				player.stand(c.to_global(c.CHAIR_POS + Vector3(sin(c.CHAIR_YAW), 0, cos(c.CHAIR_YAW)) * 0.95))
			else:
				player.sit(c.chair_world(), PI + c.CHAIR_YAW)
		"door":
			if game_on and not _doors_free():
				hud.show_toast("Oyun sürerken hücre kapıları kilitli. Telefonu kullan!")
				return
			if c.door_busy or c.locked:
				return
			c.set_door(not c.door_open)
			player.push()
			if online:
				net.send({"t": "kapi", "cell": c.index, "open": c.door_open})
		"phone":
			if phone_state == Phone.RINGING:
				_answer()
			else:
				_open_contacts()
		"hangup":
			_hang_up()
		"board":
			game_ui.open_board()
		"kutu":
			game_ui.open_box()
		"pc":
			game_ui.show_help()
		_:
			if current_target.begins_with("m:") and game_ui.mod:
				game_ui.mod.do_action(current_target.substr(2))


func _doors_free() -> bool:
	return game_ui.mod != null and game_ui.mod.doors_open()


# Telefonda görünen ad: Kim Kim?'de isim yerine "Hat 3".
func _display_name(id: int) -> String:
	if game_on and game_ui.mod:
		var n: String = game_ui.mod.contact_name(id)
		if n != "":
			return n
	return net.player_name(id)


# ---------- telefon ----------

func _open_contacts() -> void:
	var list := []
	if online:
		if game_on and not (net.my_id in game_alive):
			hud.show_toast("Bu oyuna sonradan katıldın, izleyicisin.")
			return
		if game_on and game_ui.mod and not game_ui.mod.contacts().is_empty():
			list = game_ui.mod.contacts()  # ör. Kim Kim?: "Hat 1, Hat 2..."
		for p in ([] if not list.is_empty() else net.players):
			if int(p.id) != net.my_id and (not game_on or int(p.id) in game_alive):
				# oyunda hücre numarası gizli; Kim Kim?'de isim de gizli ("Hat 3")
				list.append({"id": int(p.id), "name": _display_name(int(p.id)) if game_on else "%s  (hücre %d)" % [p.name, 11 + int(p.cell)]})
		list.sort_custom(func(a, b) -> bool: return str(a.name) < str(b.name))
	else:
		list.append({"id": 2, "name": "Deniz  (hücre 12)"})
	if list.is_empty():
		hud.show_toast("Arayacak kimse yok. Arkadaşını odaya davet et!")
		return
	hud.show_contacts(list)
	if online:
		hud.mark_busy(net.busy_ids)  # telefonda olanların kartı kırmızı, "MEŞGUL" (bildiğimiz son liste)
		net.send({"t": "hatlar"})  # güncel listeyi hemen iste (gelir gelmez kartlar güncellenir)


func _dial(id: int) -> void:
	if phone_state != Phone.IDLE:
		return
	phone_state = Phone.DIALING
	phone_peer = id
	phone_t = 0.0
	# gerçek el ahizeyi çataldan alır; kulakta karşı tarafın çalma sesi duyulur
	player.lift_handset(cells[my_cell])
	player.line_tone("calma_sesi")
	hud.show_call(_peer_name(), "Çalıyor…")
	_set_call_bar("● %s aranıyor…" % _peer_name())
	if online:
		net.send({"t": "ara", "to": id})


func _on_ringing(from_id: int) -> void:
	if _mesgul_kalan > 0.0:
		_end_call_local()  # "MEŞGUL" gösterilirken biri aradı: meşgul ekranı kapanır, zil çalar
	preload("res://scripts/titresim.gd").zil()  # iki uzun titreşim (ayarlardan kapalıysa titremez)
	phone_state = Phone.RINGING
	phone_peer = from_id
	phone_t = 0.0
	hud.ring_label.text = tr("Telefon çalıyor: %s") % _display_name(from_id)  # hud ": " sonrasını ad olarak okur
	hud.ring_label.visible = true


func _answer() -> void:
	cells[my_cell].set_ringing(false)
	player.lift_handset(cells[my_cell])
	hud.ring_label.visible = false
	if online:
		hud.show_call(_peer_name(), "Bağlanıyor…")
		net.send({"t": "cevap"})
	else:
		phone_state = Phone.CALL
		phone_t = 0.0


func _on_call_connected(with_id: int) -> void:
	player.line_tone("")
	voice.phone_line = true  # karşı tarafın sesi telefon hattından gelir gibi (bant süzgeci)
	muzik.set_call(true)
	hud.set_ptt(voice.ptt_enabled)
	phone_state = Phone.CALL
	phone_peer = with_id
	phone_t = 0.0
	voice.start()


func _on_call_ended() -> void:
	if phone_state == Phone.DIALING and phone_t < DIAL_TIMEOUT:
		hud.show_toast(tr("%s açmadı.") % _peer_name())
	_end_call_local()


func _on_busy() -> void:
	if phone_state != Phone.DIALING:
		return
	# arama şeridi kırmızıya döner ve büyük "MEŞGUL" yazar; kulakta meşgul tonu çalar.
	# _update_phone ~2 sn sonra hattı kapatır (bu arada KAPAT'a basılırsa hemen kapanır).
	hud.show_busy(_peer_name())
	player.line_tone("mesgul")
	_mesgul_kalan = MESGUL_SURE


func _hang_up(slip := false) -> void:
	if online:
		net.send({"t": "kapat"})
	_end_call_local(slip)


# Kablo sınırı aşıldı ya da hücreden çıkıldı: ahize elden kayıp çatala çarpar, hat kapanır.
func _on_cord_snapped() -> void:
	if phone_state == Phone.CALL or phone_state == Phone.DIALING:
		hud.show_toast("Ahize elinden kaydı, hat kapandı.")
		_hang_up(true)


func _end_call_local(slip := false) -> void:
	_mesgul_kalan = 0.0
	if phone_state == Phone.IDLE:
		return
	muzik.set_call(false)
	voice.phone_line = false
	# 10 saniyeden uzun gerçek konuşma elmas kazandırır
	if phone_state == Phone.CALL and online and phone_t > 10.0:
		pass  # konuşma ödülü kaldırıldı: elmas maç sonunda sunucudan gelir
	phone_state = Phone.IDLE
	solo_ring_wait = 20.0
	if not online:
		voice.stop()  # çevrimiçiyken açık kalır: yakındakiler birbirini duymaya devam eder
	hud.set_ptt(false)
	cells[my_cell].set_ringing(false)
	player.hang_up_handset(slip)  # el ahizeyi çatala koyar (uzaksa ahize kayıp çatala çarpar)
	hud.hide_call()
	_set_call_bar("")
	hud.ring_label.visible = false


# Her zaman en üstte duran arama çubuğu (tahta/kutu paneli açıkken de görünür).
func _set_call_bar(text: String) -> void:
	# Şerit hud.gd'de (sağ üst, katman 30): avatar + ad + durum/süre + şikayet + kapat (tasarım takımı).
	if not call_bar:
		call_bar = CanvasLayer.new()  # tutucu: şeridin kapat düğmesi bir kez bağlanır
		add_child(call_bar)
		hud.hangup_pressed.connect(_hang_up)
	hud.set_call_bar(text)


func _peer_name() -> String:
	return _display_name(phone_peer) if online else "Deniz"


func _update_phone(delta: float) -> void:
	phone_t += delta
	match phone_state:
		Phone.IDLE:
			if not online:
				solo_ring_wait -= delta
				if solo_ring_wait <= 0.0:
					phone_state = Phone.RINGING
					phone_peer = 2
					phone_t = 0.0
					cells[my_cell].set_ringing(true)
					hud.ring_label.text = tr("Telefon çalıyor: %s") % "Deniz"
					hud.ring_label.visible = true
		Phone.RINGING:
			hud.ring_label.modulate.a = 0.6 + 0.4 * sin(phone_t * 6.0)
			if not online and phone_t > 24.0:
				_end_call_local()
		Phone.DIALING:
			if _mesgul_kalan > 0.0:
				# karşı taraf meşgul: kırmızı "MEŞGUL" + meşgul tonu ~2 sn, sonra ahize kapanır
				_mesgul_kalan -= delta
				if _mesgul_kalan <= 0.0:
					_end_call_local()
				return
			_cord_check(delta)
			if not online and phone_t > 2.5:
				phone_state = Phone.CALL
				phone_t = 0.0
				player.line_tone("")
			elif online and phone_t > DIAL_TIMEOUT:
				hud.show_toast(tr("%s açmadı.") % _peer_name())
				_hang_up()
		Phone.CALL:
			_cord_check(delta)
			if online:
				var s := int(phone_t)
				hud.show_call(_peer_name(), "Konuşuyorsunuz  %d:%02d" % [s / 60, s % 60])
				_set_call_bar("● Hatta: %s   %d:%02d" % [_peer_name(), s / 60, s % 60])
			else:
				var line := ""
				for l in CALL_LINES:
					if phone_t >= l[0]:
						line = l[1]
				hud.show_call("Deniz", line if line != "" else "…")
				if phone_t > 22.0:
					_hang_up()


# Konuşurken spiral kablo: gerildikçe lastik gıcırtısı; hücreden çıkmaya kalkınca ahize elden kayar.
var _creak_t := 0.0


func _cord_check(delta: float) -> void:
	_creak_t -= delta
	var c: Node3D = cells[my_cell]
	if player.cord_tension > 0.45 and _creak_t <= 0.0:
		_creak_t = 1.1
		c._phone_snd("gerilme", linear_to_db(0.35 + player.cord_tension * 0.6))
	var loc: Vector3 = c.to_local(player.global_position)
	if loc.x > 1.95 or absf(loc.z) > 3.0:  # kapıdan çıktı
		_on_cord_snapped()


# ---------- mekânsal ses ----------
# Her uzak oyuncunun sesi konumuna göre: yakındaki yakından, uzaktaki uzaktan; kameranın sağına/soluna göre
# stereo; arada kapalı kapı/duvar varsa duyulmaz; telefonda konuşulan kişi mesafeden bağımsız, ortada, hat sesiyle.
static var _wave_tex: ImageTexture


# Konumun bulunduğu bölge: hücre numarası ya da -1 (koridor). Bekleme salonunda herkes aynı bölgede.
func _zone_of(p: Vector3) -> int:
	if in_lobby:
		return 0
	for i in cells.size():
		var l: Vector3 = cells[i].to_local(p)
		if absf(l.x) < 2.0 and absf(l.z) < 3.05:
			return i
	return -1


func _update_voice_space(_delta: float) -> void:
	if online and not voice.active and not voice.testing:
		voice.start()  # bir oyun ya da arama durdurduysa yeniden aç (ses kapısı sessizlikte bir şey yollamaz)
	var cam: Transform3D = player.camera.global_transform
	var right := cam.basis.x
	var me_zone := _zone_of(player.global_position)
	var on_phone := phone_state == Phone.CALL
	for id in remotes:
		var r: Dictionary = remotes[id]
		var pos: Vector3 = (r.root as Node3D).global_position + Vector3(0, 1.55, 0)
		if on_phone and int(id) == phone_peer:
			voice.set_spatial(id, 1.0, 0.0, 0.0, true)
		else:
			var rel := pos - cam.origin
			var d := rel.length()
			# 1 m'de tam, ~12 m'de çok kısık, 16 m'den sonra duyulmaz
			var g := 1.0 / (1.0 + 0.3 * pow(maxf(d - 1.0, 0.0), 1.3))
			if d > 16.0:
				g = 0.0
			var muffle := clampf(d / 20.0, 0.0, 0.5)
			var z := _zone_of(r.root.global_position)
			if z != me_zone:
				# hücre <-> koridor: o hücrenin kapısı açıksa duyulur (biraz boğuk); iki ayrı hücre: iki kapı da açık olmalı
				var open := true
				for c in [me_zone, z]:
					if c >= 0 and not cells[c].door_open:
						open = false
				if not open:
					g = 0.0
				else:
					g *= 0.6 if (me_zone == -1 or z == -1) else 0.3
					muffle = minf(1.0, muffle + (0.35 if (me_zone == -1 or z == -1) else 0.6))
			var pan := 0.0
			if d > 0.05:
				pan = clampf(rel.normalized().dot(right), -1.0, 1.0) * 0.85
			voice.set_spatial(id, g, pan, muffle, false)
		_talk_icon(r, voice.talk_level(int(id)))
		r.body.set("talk", voice.talk_level(int(id)))  # konuşurken çene/baş oynar (canlilik.gd)


# Konuşan uzak oyuncunun adının yanında küçük ses dalgası (konuştukça zıplar).
func _talk_icon(r: Dictionary, lvl: float) -> void:
	var lab: Label3D = r.label
	var s: Sprite3D = r.get("wave")
	if s == null or not is_instance_valid(s):
		if lvl < 0.05:
			return
		if _wave_tex == null:
			var img := Image.create(64, 40, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			var hs := [0.35, 0.7, 1.0, 0.7, 0.35]
			for b in 5:
				var h := int(36.0 * hs[b])
				for y in range(20 - h / 2, 20 + h / 2):
					for x in range(4 + b * 12, 12 + b * 12):
						img.set_pixel(x, y, Color(1, 1, 1, 1))
			_wave_tex = ImageTexture.create_from_image(img)
		s = Sprite3D.new()
		s.texture = _wave_tex
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.pixel_size = 0.0035
		s.modulate = Color("#7CFF9A")
		s.no_depth_test = false
		s.position = lab.position + Vector3(0, 0.22, 0)
		(r.root as Node3D).add_child(s)
		r["wave"] = s
	s.position.y = _etiket_ust(r)  # salonda HAZIR yazısının üstünde
	s.visible = lvl > 0.05 and lab.visible
	s.scale = Vector3(1.0, 0.5 + clampf(lvl, 0.0, 1.0) * 0.8, 1.0)


# Mahkum koridorun iki ucu arasında yürür, uçlarda biraz bekleyip geri döner.
func _update_walker(delta: float) -> void:
	if not walker:
		return
	if walker_wait > 0.0:
		walker_wait -= delta
		walker_body.walk = 0.0
		return
	var target_z: float = WALK_ENDS[walker_leg]
	var dz := target_z - walker.position.z
	var dir := signf(dz)
	var ahead := walker.position + Vector3(0, 0, dir * 0.9)
	var blocked := ahead.distance_to(player.global_position * Vector3(1, 0, 1)) < 0.75
	for id in remotes:
		blocked = blocked or ahead.distance_to(remotes[id].root.position) < 0.75
	walker.rotation.y = lerp_angle(walker.rotation.y, 0.0 if dir < 0.0 else PI, minf(1.0, delta * 5.0))
	if blocked:
		walker_body.walk = 0.0
		return
	var step := dir * WALK_SPEED * delta
	if absf(step) >= absf(dz):
		walker.position.z = target_z
		walker_leg = 1 - walker_leg
		walker_wait = randf_range(1.5, 4.0)
	else:
		walker.position.z += step
	walker_body.walk = WALK_SPEED / 1.4


# ---------- testler ----------
# Ekran görüntüsü:  Godot --path . -- shot=dosya.png pose=cell|corridor|icon|menu
# İki oyunculu test: -- server=ws://127.0.0.1:8787 auto=host|join code=TEST tone=1

func _handle_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if args.has("auto"):
		_run_auto(args)
		return
	if not args.has("shot"):
		return
	var pose: String = args.get("pose", "cell")
	if args.has("kalite"):
		# test: grafik kalitesi (0 pil dostu / 1 yüksek / 2 ultra), kayda yazılmaz
		profile.settings["kalite"] = int(args.kalite)
		apply_settings()
	if pose == "arkadas":
		open_friends()
	elif pose == "oyna":
		menu._show(menu.play_box)
	elif pose == "giris":
		var g := open_login()
		if args.has("tab"):
			g._signup = false
			g._build()
	elif pose == "envanter":
		if args.has("demo"):
			# test: kayıt bozulmasın diye ayrı dosya; birkaç parça bellekte verilir
			profile.path = "user://profil_envanter_test.cfg"
			for k in ["sac:mohawk", "sac:orgu", "sapka:tac", "sapka:ters_kep", "sapka:bere", "kiyafet:altin", "kiyafet:kamuflaj", "aksesuar:gunes", "aksesuar:zincir", "dovme:ejderha", "sakal:sakal", "hareket:dans"]:
				if not profile.owned.has(k):
					profile.owned.append(k)
		var inv: CanvasLayer = open_inventory()
		await get_tree().process_frame
		if args.has("cat"):
			inv._select_tab(args.cat)
		if args.has("item"):
			for it in inv._owned(inv._cat):
				if it[1] == args.item:
					inv._equip(it, inv._grid.get_child(0))
	elif pose == "karakter":
		var ch: CanvasLayer = open_character()
		await get_tree().process_frame
		ch._cat = args.get("cat", "sac")
		ch._refresh()
		if args.has("item"):
			ch._pick(args.item)
		if args.has("asagi"):
			# test: ızgarayı kaydır (asagi=<piksel>)
			await get_tree().create_timer(0.5).timeout
			ch._scroll.scroll_vertical = int(args.asagi)
		if args.has("ac"):
			await get_tree().create_timer(0.5).timeout
			if args.has("kazan"):
				# test: belirli bir eşyayla kasa gösterisi (ekonomiye dokunmaz)
				for it in Catalog.shop_items():
					if it[1] == args.kazan:
						ch.spin(ch.CHESTS[int(args.ac)], it)
			else:
				ch._open_chest(ch.CHESTS[int(args.ac)])
		if args.has("al"):
			ch._pending = [ch._cat, args.al]
			ch._buy()
		# mağaza testleri: demo=1 örnek arkadaş/istek/kasa hakkı; set=<kimlik> seti dener; olasilik=1; hediye=1 (item= ile)
		if args.has("demo") or args.has("set") or args.has("olasilik") or args.has("hediye") or args.has("istek"):
			await get_tree().create_timer(2.0).timeout
		if args.has("demo"):
			_demo_market()
			await get_tree().process_frame
			ch._refresh()
		if args.has("set"):
			for st in ch._sets():
				if str(st.k) == args.set:
					ch._pick_set(st)
		if args.has("item") and args.has("demo"):
			ch._pick(args.item)
		if args.has("set_al"):
			ch._on_buy_pressed()  # set satın alma onay penceresi
		if args.has("istek"):
			ch._toggle_wish()  # yerel sunucuda istek listesine ekler/çıkarır
		if args.has("olasilik"):
			ch._odds_modal()
		if args.has("hediye"):
			ch._gift_open()
	elif not pose in ["menu", "oyna", "kit", "gorevler", "basarimlar", "liderlik", "menu_ayarlar", "elmas", "yol"]:
		_start_solo()
		if args.has("pitch"):
			player.head.rotation.x = deg_to_rad(float(args.pitch))
	if args.has("market_demo"):
		get_tree().create_timer(2.0).timeout.connect(_demo_market)  # test: menüde mağaza rozetleri
	match pose:
		"yol":
			# seviye yolu. demo=1: seviye 12, birkaç ödül alınmış (sunucuya bir şey gitmez)
			if args.has("demo"):
				await get_tree().create_timer(2.0).timeout
				_demo_market()
			var yol: CanvasLayer = menu._open_yol()
			if args.has("kaydir"):
				# test: yolun ilerisini göster (kaydir=<sıra>, 0'dan)
				await get_tree().create_timer(1.0).timeout
				yol._kaydir(int(args.kaydir))
		"elmas":
			# elmas mağazası. sec=<paket id> onay penceresini açar; al=<paket id> satın alır (ODEME_TEST=1 sunucu) ve kutlamayı gösterir
			var gs := open_gem_store()
			if args.has("sec") or args.has("al"):
				await get_tree().create_timer(float(args.get("bekle", "2.5"))).timeout
				gs.call("test_sec", str(args.get("al", args.get("sec", ""))), args.has("al"))
		"kit":
			# tasarım panosu: arayüz takımının bütün parçaları (scripts/ui.gd -> kit_board)
			var kit_katman := CanvasLayer.new()
			kit_katman.layer = 110
			add_child(kit_katman)
			kit_katman.add_child(UI.kit_board())
		"corridor":
			cells[0].set_door(true, true)
			player.global_position = Vector3(3.9, 0, cells[0].position.z + 3.0)
		"kadro":
			# test: koridorda farklı gövde/saç/sakal/aksesuarla karakterler (uzaktaki oyuncularla aynı model);
			# hareket=<kimlik> hepsine o hareketi yaptırır. Örnek: pose=kadro hareket=gul
			cells[0].set_door(true, true)
			hud.visible = false
			player.global_position = Vector3(3.9, 0, cells[0].position.z + 3.0)
			player.head.rotation.x = deg_to_rad(-8)
			var kadro := [
				{"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "sac_renk": 1, "aksesuar": "gunes", "kiyafet": "turuncu"},
				{"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "aksesuar": "kupe", "kiyafet": "pembe", "ten": 0},
				{"govde": "erkek", "sac": "rasta", "sakal": "keci", "ten": 4, "aksesuar": "zincir", "kiyafet": "cizgili"},
				{"govde": "kadin", "sac": "uzun_duz", "sac_renk": 3, "aksesuar": "kalp", "kiyafet": "leopar", "ten": 2},
				{"govde": "erkek", "sac": "mohawk", "sakal": "pala", "sac_renk": 2, "sapka": "yok", "kiyafet": "kot", "ten": 1},
			]
			for i in kadro.size():
				var b: Node3D = BodyScript.new()
				b.look = Catalog.sanitize(kadro[i])
				add_child(b)
				b.global_position = player.global_transform * Vector3((i - 2) * 0.85, 0, -3.2 - absf(i - 2) * 0.25)
				b.rotation.y = player.rotation.y + PI
			if args.has("hareket"):
				await get_tree().process_frame
				await get_tree().process_frame
				for b in get_children():
					if b.get_script() == BodyScript:
						b.play_emote(args.hareket)
		"dolap":
			# test: Yalancı dolabı açık, rafta eşya  esya=bere|ponpon|bandana|kulaklik|...
			hud.visible = false
			solo_ring_wait = 100.0
			player.global_position = cells[0].to_global(Vector3(-0.35, 0, -0.2))
			player.rotation.y = cells[0].global_rotation.y + PI / 2
			player.head.rotation.x = deg_to_rad(-12)
			cells[0].set_locker_item(str(args.get("esya", "ponpon")))
			cells[0].set_locker(true)
		"ayna":
			# test: hücredeki aynada oyuncunun kendi karakteri  govde=kadin|erkek
			hud.visible = false
			player.set_look({"govde": args.get("govde", "kadin"), "sac": "uzun_duz", "sac_renk": 3, "aksesuar": "kupe", "kiyafet": "turuncu"})
			player.global_position = cells[0].to_global(Vector3(-0.85, 0, 1.05))
			player.rotation.y = cells[0].global_rotation.y + PI / 2
			player.head.rotation.x = deg_to_rad(8)
			if args.has("yesil"):
				# karşılaştırma: bilgisayar ekranının yeşil ışığı yalnız dünyayı aydınlatsın (önerilen cell.gd düzeltmesi)
				for l in find_children("*", "OmniLight3D", true, false):
					if (l as Light3D).light_color.is_equal_approx(Color("#3cff7a")):
						(l as Light3D).light_cull_mask = 1
			if args.has("dekal"):
				# karşılaştırma: dünya lekeleri (Decal) kapalı
				for d in find_children("*", "Decal", true, false):
					(d as Decal).visible = false
			if args.has("yan"):
				# karşılaştırma: aynanın yanında, aynı ışıkta doğrudan görünen bir karakter
				var yb: Node3D = BodyScript.new()
				yb.look = Catalog.sanitize({"govde": args.get("govde", "kadin"), "sac": "uzun_duz", "sac_renk": 3})
				add_child(yb)
				yb.global_position = cells[0].to_global(Vector3(-1.75, 0, 0.45))
				yb.rotation.y = cells[0].global_rotation.y - PI / 2
			if args.has("uzak"):
				# karşılaştırma: aynanın olduğu duvar odanın ortasından (ayna apliki ve ışığı)
				player.global_position = cells[0].to_global(Vector3(0.9, 0, 1.25))
				player.head.rotation.x = deg_to_rad(4)
		"macsonu":
			# test: maç sonu ekranı, birinci taçla sahnede (sahte puan tablosu)
			var looks := [
				{"govde": "kadin", "sac": "ikiz_orgu", "sac_renk": 5, "aksesuar": "kalp", "kiyafet": "pembe"},
				{"govde": "erkek", "sac": "ayrik", "sakal": "dolgun", "sac_renk": 1},
				{"govde": "erkek", "sac": "rasta", "ten": 4, "kiyafet": "cizgili"},
			]
			var rows := []
			var players_l := []
			for i in 3:
				rows.append({"id": i + 1, "name": ["Zeynep", "Kerem", "Ali"][i], "score": 30 - i * 10, "p": [10 - i * 3, 12 - i * 4, 8 - i * 3], "g": looks[i]})
				players_l.append({"id": i + 1, "g": looks[i]})
			var oyunlar_t := [{"ad": "Kara Tahta"}, {"ad": "Kısa Devre"}, {"ad": "Rulet"}]
			if str(args.get("tam", "")) == "1":  # test: dokuz oyunlu tam maç tablosu (sütunlar ve adlar sığıyor mu)
				oyunlar_t = []
				for a in ["KİM KİM", "TAHTA", "DEVRE", "YALANCI", "RULET", "C4", "ORTALAMA"]:
					oyunlar_t.append({"ad": a})
				for r in rows:
					r["p"] = [2, -1, 3, 3, 0, -1, 2, 1, -2]
				rows[1]["name"] = "Sinsi Necmi"
			var ms = load("res://scripts/mac_sonu.gd").new()
			ms.setup({"table": rows, "oyunlar": oyunlar_t, "winner": 1}, 1, players_l)
			var katman := CanvasLayer.new()
			katman.layer = 100
			add_child(katman)
			katman.add_child(ms)
		"icon":
			hud.visible = false
			solo_ring_wait = 0.0
			player.global_position = cells[0].to_global(Vector3(0.75, 0, -2.25))
			player.rotation.y = -PI / 2
			player.head.rotation.x = deg_to_rad(-10)
			player.camera.fov = 42.0
		"ayarlar":
			var st_a: CanvasLayer = open_settings()
			if args.has("dil_sec"):
				# test: ayarlar açıkken dili anında değiştir (kayda yazmadan): dil_sec=tr|en
				await get_tree().create_timer(0.6).timeout
				TranslationServer.set_locale(str(args.dil_sec))
				UI.sigdir_hepsi(get_tree().root)
				st_a._dil_degisti()
				menu.refresh_profile()
		"menu_ayarlar":
			# ana menüden açılan ayarlar (oyunda değilken); sekme=ses|goruntu|kontroller|hesap
			var st_ekran: CanvasLayer = open_settings()
			if args.has("sekme"):
				st_ekran.call_deferred("_sec", ["profil", "ses", "goruntu", "kontroller", "hesap"].find(str(args.sekme)))
			if args.has("sil"):
				st_ekran.call_deferred("_confirm_delete")
		"gorevler", "basarimlar":
			if args.has("demo"):
				await get_tree().create_timer(1.2).timeout
				_demo_menu()
			menu._open_gorevler(0 if pose == "gorevler" else 1)
		"liderlik":
			menu._open_liderlik()
			if args.has("demo"):
				await get_tree().create_timer(1.2).timeout
				_demo_menu()
				account.leaderboard.emit({"liste": [
					{"sira": 1, "ad": "Kara Murat", "handle": "karamurat", "puan": 4820, "seviye": 31},
					{"sira": 2, "ad": "Zeynep", "handle": "zey", "puan": 3975, "seviye": 18},
					{"sira": 3, "ad": "Hücre Bekçisi", "handle": "bekci", "puan": 3410, "seviye": 16},
					{"sira": 4, "ad": "Apo", "handle": "apo", "puan": 2900, "seviye": 12},
					{"sira": 5, "ad": "Selin", "handle": "selin", "puan": 2410, "seviye": 9},
					{"sira": 6, "ad": "Tünelci", "handle": "tunel", "puan": 1980, "seviye": 7},
					{"sira": 7, "ad": "Mahkum78", "handle": "m78", "puan": 1500, "seviye": 5},
					{"sira": 8, "ad": "Gardiyan", "handle": "gard", "puan": 990, "seviye": 3}],
					"benim_sira": 12, "benim_puan": 640})
		"menu", "oyna":
			if args.has("demo"):
				await get_tree().create_timer(1.2).timeout
				_demo_menu()
				if args.has("davet"):
					account.invited.emit("zey", "Zeynep", "KAPI")
		"bilgisayar":
			game_ui.show_help()
		"panel", "sema":
			# Kısa Devre kutusu: durum=surukle (varsayılan) | salter | guc | yandi, yanlis=1; pose=sema tahtadaki şema
			game_ui.visible = true
			game_ui.secret = {"task": "devre", "kod": "K7", "kablolar": ["KIRMIZI", "MAVİ", "SARI", "YEŞİL"], "semboller": ["KARE", "YILDIZ", "DAİRE", "ÜÇGEN"], "adim_sayisi": 4, "round": 2,
				"yardim_ad": "Kara Ali", "sema": [["TURUNCU", "S", "YILDIZ"], ["MOR", "N", 3], ["MAVİ", "S", "KARE"], ["SARI", "N", 1]]}
			game_ui.state = {"task": "devre", "phase": "calisma"}
			if args.has("satirlar"):
				# test: satirlar=RENK:S:SEMBOL,RENK:N:3,...  (uzun renk adları, 4-5 satır)  ad=<kimin için>
				var sr := []
				for parca in str(args.satirlar).split(","):
					var q := parca.split(":")
					if q.size() == 3:
						sr.append([q[0], q[1], int(q[2]) if q[1] == "N" else q[2]])
				game_ui.secret.sema = sr
				game_ui.secret.yardim_ad = str(args.get("ad", "Kara Ali")).replace("_", " ")
			if pose == "sema" and args.has("duvar"):
				# test: hücre duvarındaki 3D tahtaya yazılan şema (wait= yazı bitene kadar, ~4 sn)
				cells[0].set_board_text(game_ui._devre_tahta(game_ui.secret))
				player.global_position = cells[0].to_global(Vector3(0.35, 0, -1.0))
				player.rotation.y = cells[0].global_rotation.y
				player.head.rotation.x = deg_to_rad(10)
			elif pose == "sema":
				game_ui._show_devre_board()
			else:
				var durum: String = args.get("durum", "")
				game_ui._box_state.plugged = {"KIRMIZI": "DAİRE"}
				game_ui._box_state.adim = 1
				if durum in ["salter", "guc"]:
					game_ui._box_state.plugged = {"KIRMIZI": "DAİRE", "MAVİ": "KARE", "SARI": "ÜÇGEN", "YEŞİL": "YILDIZ"}
					game_ui._box_state.adim = 4
					game_ui._box_state.hak = 2
				game_ui.open_box()
				var bx: Control = game_ui._box
				if args.get("yanlis", "") == "1":
					get_tree().create_timer(2.42).timeout.connect(func() -> void: bx.set_result("yanlis", 1, "MAVİ", "KARE", 2))
				elif durum == "guc":
					get_tree().create_timer(float(args.get("t", "0.6"))).timeout.connect(func() -> void:
						bx.pull_lever()
						bx.set_result("tamir", 4, "", "", 2))
				elif durum == "yandi":
					get_tree().create_timer(1.0).timeout.connect(func() -> void: bx.set_result("kilit", 1, "SARI", "KARE", 0))
				elif durum == "":
					bx._drag = "SARI"
					var fp := Vector2(float(args.get("fx", "600")), float(args.get("fy", "300")))
					bx._finger = fp
					get_tree().create_timer(2.0).timeout.connect(func() -> void: bx._finger = fp)
		"cagri":
			_set_call_bar("● Hatta: Ali   0:23")
			game_ui.visible = true
			game_ui.secret = {"task": "devre", "kod": "K7", "kablolar": ["KIRMIZI", "MAVİ", "SARI", "YEŞİL"], "semboller": ["KARE", "YILDIZ", "DAİRE", "ÜÇGEN"], "adim_sayisi": 4}
			game_ui.state = {"task": "devre", "phase": "calisma"}
			game_ui.open_box()
		"tahtapanel":
			game_ui.visible = true
			game_ui.secret = {"task": "tahta", "yazan": args.get("yazan", "0") == "1", "hedef": 2, "tahminci": 4, "round": 1}
			game_ui.state = {"task": "tahta", "phase": "telefon", "title": "KARA TAHTA"}
			game_ui.open_board()
			if args.has("yazi"):
				(game_ui._panel.find_children("*", "LineEdit", true, false)[0] as LineEdit).text = args.yazi
		"isik":
			game_ui.visible = true
			game_ui._blackout_intro()
		"pano":
			player.global_position = cells[0].to_global(Vector3(0.3, 0, 1.85))
			player.rotation.y = -PI / 2
			player.head.rotation.x = deg_to_rad(-3)
			if args.get("kutu", "") != "normal":
				cells[0].set_power(false)
				cells[0].set_fuse("bozuk")
		"patlama":
			player.global_position = cells[0].to_global(Vector3(0.0, 0, 2.2))
			player.rotation.y = 0.0
			await get_tree().create_timer(0.5).timeout
			preload("res://scripts/modlar/props.gd").explosion(self, cells[0].to_global(Vector3(0.0, 1.0, -1.0)), 0.0)
		"pc3d":
			player.global_position = cells[0].to_global(Vector3(0.7, 0, 1.3))
			player.rotation.y = PI / 2
			player.head.rotation.x = deg_to_rad(-12)
		"emote":
			await get_tree().create_timer(0.3).timeout
			hud.emote_panel.visible = true
			if args.has("e"):
				hud.emote_panel.visible = false
				player.global_position = cells[0].to_global(Vector3(0.6, 0, 1.2))
				_do_emote(args.e)
		"kontrol":
			await load("res://scripts/modlar/kontrol_test.gd").run(self, args)  # test: dokunmayla joystick/bakış/duvar/kapı (adim=..)
		"hareket1p":
			# test: birinci şahısta hareket (scripts/modlar/hareket1p_test.gd): hareket=<kimlik> t=<sn> govde=.. yer=..
			await preload("res://scripts/modlar/hareket1p_test.gd").run(self, args)
		"dizi":
			# test: yeni içerik dizisi (gövde tipleri, kıyafet, şapka, aksesuar, hareket): tools/yeni_icerik_test.gd
			await load("res://tools/yeni_icerik_test.gd").run(self, args)
		"el_govde":
			# test: birinci şahıs elleri başka gövde tipi/kıyafetle  govde=iri|yasli|kadin_iri|ince  kiyafet=..  aksesuar=..  (+ pose=el seçenekleri)
			player.set_look(Catalog.sanitize({"govde": args.get("govde", "iri"), "kiyafet": args.get("kiyafet", "turuncu"), "aksesuar": args.get("aksesuar", "yok")}))
			await get_tree().process_frame
			await preload("res://scripts/modlar/el_test.gd").run(self, args)
		"el":
			# test: gerçek ellerle tutma pozları  el=silah|sakak|hedef|ahize|c4|itme  dis=1 dışarıdan bak
			await preload("res://scripts/modlar/el_test.gd").run(self, args)
		"fragman":
			# tanıtım fragmanı çekimleri (tools/fragman_cek.gd): sahne=koridor|hucre|telefon|ahize|c4|patlama|silah|karakter
			await load("res://tools/fragman_cek.gd").run(self, args)
		"oyunici":
			# test: oyun içi 2D ekranlar  ekran=kart|yardim|flash|tahta|kimkim|secici|yalanci_esya|yalanci_oy|ortalama|ortalama_sonuc|rulet|rulet_bar|c4  oyun=tahta|kimkim|...
			solo_ring_wait = 100.0
			await preload("res://scripts/modlar/oyunici_test.gd").run(self, args)
		"arkadas":
			if args.has("demo"):
				# test: sahte arkadaş listesi (sunucunun listesi geldikten sonra üstüne yazılır)
				await get_tree().create_timer(2.0).timeout
				account.set_process(false)  # sunucunun listesi sahte veriyi ezmesin
				account.handle = "mustafa"
				account.friends = [{"handle": "kerem", "name": "Kerem", "online": true, "room": "K7QX"}, {"handle": "zeynep", "name": "Zeynep", "online": true, "room": ""}, {"handle": "ali34", "name": "Ali", "online": true, "room": "M4CX", "oyun": true}, {"handle": "deniz", "name": "Deniz", "online": false, "room": ""}]
				account.incoming = [{"handle": "mert_x", "name": "Mert"}]
				account.outgoing = [{"handle": "selin", "name": "Selin"}]
				account.set("engeller", ["kufurbaz34"])
				account.list_changed.emit()
				if args.has("menu"):
					await get_tree().create_timer(0.5).timeout
					var f3: Node = get_children().filter(func(n: Node) -> bool: return n.get_script() == FriendsScript)[-1]
					var dd: Array = f3.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return b.get_meta("label", null) is Label and (b.get_meta("label") as Label).text == "•••")
					if not dd.is_empty():
						(dd[0] as Button).pressed.emit()
		"lobi", "sikayet":
			# bekleme salonu (sahte oyuncular): host=0 misafir görünümü, hizli=1 Hızlı Oyun geri sayımı
			var demo := [
				{"id": 1, "name": "Mustafa", "cell": 0, "host": true, "r": true},
				{"id": 2, "name": "Kerem", "cell": 1, "host": false, "r": false, "mk": true},
				{"id": 3, "name": "Zeynep", "cell": 2, "host": false, "r": true},
				{"id": 4, "name": "Bot Ayşe", "cell": 3, "host": false, "r": true, "bot": true},
				{"id": 5, "name": "Deniz", "cell": 4, "host": false, "r": false},
			]
			hud.show_lobby(true)
			if args.get("hizli", "") == "1":
				hud.set_public_countdown(25)
			elif args.get("hizli", "") == "bekle":
				hud.set_public_countdown(-1)  # Hızlı Oyun: herkes hazır değil, geri sayım durdu
			if args.has("bildirim"):
				# test: sıralı bildirimler (en çok 2 görünür) + bağlantı göstergesi (ping=1|2 ile)
				hud.bildirim("koptu", tr("{0} bağlantısı koptu, bekleniyor…").format(["Kerem"]))
				hud.bildirim("geri", tr("{0} geri bağlandı.").format(["Zeynep"]))
				hud.bildirim("katildi", tr("{0} odaya katıldı.").format(["Deniz"]))
				hud.bildirim("sahip", tr("Oda sahibi artık {0}.").format(["Zeynep"]))
			hud.update_lobby("K7QX", demo, 1 if args.get("host", "1") == "1" else 2, args.get("host", "1") == "1")
			if args.has("ayarlar"): open_settings()  # test: odadaki ayarlar paneli (baglam=lobi ile)
			if pose == "sikayet" and args.get("menu", "") == "1":
				# uçtan uca: Kerem'in kartına dokun -> ŞİKAYET ET -> KÜFÜR -> GÖNDER (sunucuya gerçek şikayet gider)
				await get_tree().create_timer(0.6).timeout
				var bas := func(metin: String, kok: Node) -> bool:
					for b in kok.find_children("*", "Button", true, false):
						var lb: Variant = b.get_meta("label", null)
						var ok_b: bool = (lb is Label and (lb as Label).text == metin)
						if not ok_b:
							for l in b.find_children("*", "Label", true, false):
								ok_b = ok_b or (l as Label).text == metin
						if ok_b and (b as Button).is_visible_in_tree():
							(b as Button).pressed.emit()
							return true
					return false
				print("[test] kart: ", bas.call("Kerem", hud))
				await get_tree().create_timer(0.4).timeout
				print("[test] menü: ", bas.call("ŞİKAYET ET", hud))
				await get_tree().create_timer(0.5).timeout
				print("[test] neden: ", bas.call("KÜFÜR", hud))
				await get_tree().create_timer(0.3).timeout
				if args.get("gonder", "") == "1":
					print("[test] gönder: ", bas.call("GÖNDER", hud))
			elif pose == "sikayet" and hud.has_method("open_report"):
				await get_tree().create_timer(0.4).timeout
				hud.call("open_report", "Kerem", "", "K7QX")
		"arama":
			# telefon: durum=ariyor | baglaniyor | konusma | altyazi | caliyor
			player.global_position = cells[0].to_global(Vector3(1.05, 0, -2.25))
			player.rotation.y = -PI / 2
			solo_ring_wait = 100.0
			match args.get("durum", "konusma"):
				"ariyor":
					hud.show_call("Ali", "Çalıyor…")
					_set_call_bar("● Ali aranıyor…")
				"baglaniyor":
					hud.show_call("Ali", "Bağlanıyor…")
				"altyazi":
					hud.show_call("Deniz", "Alo? Sen de mi buradasın? Tahtaya ne yazdılar, oku bana!")
					_set_call_bar("● Deniz aranıyor…")
				"mesgul":
					# aranan meşgul: kırmızı büyük "MEŞGUL" şeridi (süre uzatılır ki görüntü alınsın)
					_dial(2)
					_on_busy()
					_mesgul_kalan = 60.0
				"mesgul_sonra":
					# meşgul şeridi kapandıktan sonraki arama: şerit eski boyuna dönmeli
					hud.show_busy("Deniz")
					await get_tree().create_timer(0.6).timeout
					hud.hide_call()
					await get_tree().create_timer(0.6).timeout
					hud.show_call("Ali", "Çalıyor…")
				"rehber":
					# rehber: telefonda olan kişinin kartı kırmızı, büyük "MEŞGUL", arama düğmesi gri
					hud.show_contacts([{"id": 2, "name": "Ali"}, {"id": 3, "name": "Zeynep"},
						{"id": 4, "name": "Deniz"}, {"id": 5, "name": "Mert"}])
					hud.mark_busy([3, 5])
				"caliyor":
					# oyun=kimkim: arayan gizli ("****")
					hud.ring_label.text = tr("Telefon çalıyor: %s") % ("****" if args.get("oyun", "") == "kimkim" else "Zeynep")
					hud.ring_label.visible = true
					hud.set_action("Cevapla", true)
				_:
					hud.show_call("Ali", "Konuşuyorsunuz  0:23")
					_set_call_bar("● Hatta: Ali   0:23")
					hud.set_ptt(true)
		"oyunhud":
			# oyun içi göstergeler: eylem düğmesi + son saniyeler + bildirim
			player.global_position = cells[0].to_global(Vector3(1.05, 0, -2.25))
			player.rotation.y = -PI / 2
			solo_ring_wait = 100.0
			hud.set_game_timer(float(args.get("sure", "12")))
			hud.set_action(args.get("eylem", "Tahtaya yaz"), args.get("tel", "") == "1")
		"contacts":
			player.global_position = cells[0].to_global(Vector3(1.05, 0, -2.25))
			player.rotation.y = -PI / 2
			solo_ring_wait = 100.0
			await get_tree().create_timer(0.5).timeout
			_do_action()
	if args.has("geri"):
		# test: Android geri tuşu / Esc (ui_cancel) geri=<n> kez basılır (en üstteki ekran / pencere kapanmalı)
		for i in int(args.geri):
			await get_tree().create_timer(1.5).timeout
			for basili in [true, false]:
				var ev := InputEventAction.new()
				ev.action = "ui_cancel"
				ev.pressed = basili
				Input.parse_input_event(ev)
				await get_tree().process_frame
	await get_tree().create_timer(float(args.get("wait", "2.5"))).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args["shot"])
	get_tree().quit()


# Test: mağaza ekranları için örnek veri (sunucuya bir şey gönderilmez): arkadaşlar, istek listesi, kasa hakları,
# seviye 12 ve seviye yolunda alınmamış ödüller.
func _demo_market() -> void:
	if account.handle == "":
		account.handle = "demo"
	account.friends = [
		{"handle": "zey", "name": "Zeynep", "online": true, "room": ""},
		{"handle": "karamurat", "name": "Kara Murat", "online": true, "room": ""},
		{"handle": "m78", "name": "Mahkum78", "online": false, "room": ""}]
	var e: Dictionary = account.eco.duplicate(true)
	var vit: Array = e.get("firsatlar", [])
	var istek: Array = []
	for i in mini(2, vit.size()):
		istek.append(str(vit[i][0]) + ":" + str(vit[i][1]))
	var yol: Array = e.get("yol", [])
	for o in yol:
		o["alindi"] = int(o.s) <= 8 and int(o.s) != 5
	e.merge({"seviye": 12, "xp_ic": 340, "xp_gerek": 650, "kasa_hak": {"tahta": 2, "altin": 1}, "istek": istek,
		"istek_yeni": istek.size(), "yol": yol, "yol_hazir": 5, "hediye": {"kalan": 2, "sinir": 3, "min_seviye": 5}}, true)
	account.eco = e
	account.economy_changed.emit()
	account.list_changed.emit()


# Test: menü ekranları için örnek arkadaş, istek ve ekonomi verisi (sunucuya bir şey gönderilmez).
func _demo_menu() -> void:
	account.friends = [
		{"handle": "zey", "name": "Zeynep", "online": true, "room": "KAPI"},
		{"handle": "apo", "name": "Apo", "online": true, "room": ""},
		{"handle": "karamurat", "name": "Kara Murat", "online": true, "room": "M4CX", "oyun": true},
		{"handle": "m78", "name": "Mahkum78", "online": false, "room": ""},
		{"handle": "selin", "name": "Selin", "online": false, "room": ""}]
	account.incoming = [{"handle": "tunel", "name": "Tünelci"}, {"handle": "gard", "name": "Gardiyan"}]
	var e: Dictionary = account.eco.duplicate()
	e.merge({"elmas": 10025, "seviye": 7, "xp_ic": 340, "xp_gerek": 700, "gunluk_hazir": true, "seri": 3,
		"gorevler": [
			{"k": "mac", "ad": "3 maç oyna", "hedef": 3, "odul": 40, "ilerleme": 3, "alindi": false},
			{"k": "kazan", "ad": "1 maç kazan", "hedef": 1, "odul": 60, "ilerleme": 0, "alindi": false},
			{"k": "ara", "ad": "Telefonla 5 kez ara", "hedef": 5, "odul": 30, "ilerleme": 5, "alindi": true}],
		"basarimlar": [
			{"k": "mac1", "ad": "İlk gün", "aciklama": "İlk maçını oyna", "hedef": 1, "odul": 50, "ilerleme": 1, "alindi": true},
			{"k": "mac10", "ad": "Koğuşun eskisi", "aciklama": "10 maç oyna", "hedef": 10, "odul": 150, "ilerleme": 10, "alindi": false},
			{"k": "mac50", "ad": "Müebbet", "aciklama": "50 maç oyna", "hedef": 50, "odul": 500, "ilerleme": 12, "alindi": false},
			{"k": "kazan10", "ad": "Koğuş ağası", "aciklama": "10 maç kazan", "hedef": 10, "odul": 200, "ilerleme": 4, "alindi": false},
			{"k": "sv10", "ad": "Kıdemli", "aciklama": "10. seviyeye ulaş", "hedef": 10, "odul": 300, "ilerleme": 7, "alindi": false},
			{"k": "arkadas", "ad": "Kankalar", "aciklama": "3 arkadaş edin", "hedef": 3, "odul": 100, "ilerleme": 1, "alindi": false}]}, true)
	account.eco = e
	account.economy_changed.emit()
	account.list_changed.emit()


func _run_auto(args: Dictionary) -> void:
	_auto = args.auto
	var code: String = args.get("code", "TEST")
	print("[test] ", _auto, " başlıyor")
	net.failed.connect(func(m: String) -> void:
		print("[test] hata: ", m)
		if get_meta("test_bitti", false):
			return  # maç bitti: bitiş ekranının görüntüleri yine de alınsın
		get_tree().quit())
	if _auto == "oyun":
		# tur oyunu testi: oda kur, botları bekle, hızlı oyna, her aşamada ekran görüntüsü al
		var dir: String = args.get("klasor", "user://oyun_test")
		net.join(code, "Sen", true)
		await net.welcomed
		print("[test] oda kuruldu ", net.room_code)
		for i in int(args.get("botlar", "0")):
			net.send({"t": "bot_ekle"})
			await get_tree().create_timer(0.3).timeout
		while net.players.size() < int(args.get("n", "3")):
			await get_tree().process_frame
		var ol: Array = str(args.get("oyunlar", "")).split(",", false)
		net.send({"t": "basla", "hiz": float(args.get("hiz", "0.2")), "oyunlar": ol})
		var shots := {"n": 0}
		var shot := func(name: String) -> void:
			await RenderingServer.frame_post_draw
			shots.n += 1
			get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [dir, shots.n, name])
			if args.has("olc"):
				# performans: o andaki çizim çağrısı, üçgen, video belleği (tools/fps_olc.gd ile aynı ölçüler)
				print("[olc] %-22s | %5d cizim | %7.1fk ucgen | %5.0f MB vram | %5.0f MB bellek | %d dugum" % [name,
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
					Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		net.game_secret.connect(func(d: Dictionary) -> void:
			if game_ui.MODS.has(str(d.task)):
				await get_tree().create_timer(1.6).timeout
				await shot.call("kart_" + str(d.task))
				if game_ui.mod:
					game_ui.mod.close_card()
				return
			if d.task == "devre":
				await get_tree().create_timer(0.45).timeout
				await shot.call("devre_simsek")
				await get_tree().create_timer(0.9).timeout
				await shot.call("devre_yazi")
				return
			await get_tree().create_timer(0.5).timeout
			shot.call("kart_" + ("yazan" if d.get("yazan", false) else "tahminci")))
		net.mode_event.connect(func(d: Dictionary) -> void: _auto_event(d, shot))
		# Kim Kim?: biri ararsa çalan telefon ve konuşma çekilir (arayan "****" görünmeli), sonra kapatılır
		net.ringing.connect(func(from_id: int) -> void:
			if not (game_ui.mod and str(game_ui.mod.task) == "kimkim"):
				return
			await get_tree().create_timer(0.8).timeout
			print("[test] kimkim: çalıyor, no %d, görünen '%s', meşgul %s" % [from_id, _display_name(from_id), str(net.busy_ids)])
			await shot.call("kimkim_caliyor")
			_answer()
			await net.call_connected
			await get_tree().create_timer(0.6).timeout
			var k = game_ui.mod.get("_kimim") if game_ui.mod else null
			print("[test] kimkim: bağlandı, görünen '%s', robot sesi: %s" % [_peer_name(), str(k is AudioStreamPlayer and k.playing)])
			if game_ui.mod:
				game_ui.mod.close_panel()
			await shot.call("kimkim_hatta")
			await get_tree().create_timer(2.0).timeout
			_hang_up())
		net.game_state.connect(func(d: Dictionary) -> void:
			if game_ui.MODS.has(str(d.task)):
				_auto_state(d, shot)
				return
			if d.task == "devre":
				if d.phase == "calisma":
					await get_tree().create_timer(0.3).timeout
					game_ui._clear(game_ui._card)
					# kutuya bak: kıvılcım, acil durum ışığı
					player.global_position = cells[my_cell].to_global(Vector3(0.6, 0, 1.85))
					player.rotation.y = -PI / 2
					player.head.rotation.x = deg_to_rad(-5)
					await get_tree().create_timer(0.5).timeout
					await shot.call("devre_kutu3d")
					player.global_position = cells[my_cell].to_global(Vector3(0.35, 0, -1.6))
					player.rotation.y = 0.0
					player.head.rotation.x = deg_to_rad(10)
					await get_tree().create_timer(2.5).timeout
					await shot.call("devre_tahta3d")
					game_ui.open_box()
					await get_tree().create_timer(0.3).timeout
					await shot.call("devre_panel")
					var wires: Array = game_ui.secret.get("kablolar", [])
					var syms: Array = game_ui.secret.get("semboller", [])
					game_ui._box._try_connect(wires[0], syms[0])
					await get_tree().create_timer(0.35).timeout
					await shot.call("devre_sonuc_aninda")
					await get_tree().create_timer(1.2).timeout
					await shot.call("devre_sonuc_sonra")
					game_ui._clear(game_ui._box)
					game_ui._show_devre_board()
					await get_tree().create_timer(0.3).timeout
					await shot.call("devre_sema")
					game_ui._clear(game_ui._panel)
				elif d.phase == "oylama":
					await get_tree().create_timer(0.4).timeout
					await shot.call("devre_oylama")
				return
			if d.phase != "telefon":
				return
			await get_tree().create_timer(0.8).timeout
			game_ui.open_board()
			await get_tree().create_timer(0.3).timeout
			await shot.call("tahta_panel")
			game_ui._clear(game_ui._panel)
			var word := "elma" if Dil.tr_mi() else "apple"  # test: odanın diline uygun kelime
			game_ui.written = word.to_upper()
			game_ui.board_written.emit(game_ui.written)
			game_ui.decided.emit(word)
			game_ui._update_banner()
			# tahtaya bak
			player.global_position = cells[my_cell].to_global(Vector3(0.35, 0, -1.2))
			player.rotation.y = 0.0
			player.head.rotation.x = deg_to_rad(8)
			await get_tree().create_timer(0.6).timeout
			shot.call("tahta_3d"))
		net.game_result.connect(func(d: Dictionary) -> void:
			# tur sonu ekranı animasyonlu: puanlar sayıldıktan sonra (ekran kapanmadan) çek
			await get_tree().create_timer(clampf(float(d.get("sonuc_sure", 2)) - 0.4, 0.5, 3.2)).timeout
			shot.call("sonuc_" + str(d.get("task", ""))))
		await net.game_over
		set_meta("test_bitti", true)
		if args.get("tekrar", "") == "1":
			# TEKRAR OYNA testi: maç sonu (iki düğme, LOBİDE/ÇIKTI etiketleri) -> salona dönüş -> 2. maç aynı odada
			await _auto_tekrar(args, shot)
			print("[test] oyun bitti, goruntu: ", shots.n)
			get_tree().quit()
			return
		# maç sonu ekranı uzun bir açılış: farklı anlarda görüntü al
		var last_t := 0.0
		for t in [1.2, 3.5, 6.0, 7.2, 8.2, 9.2, 10.4, 13.0]:
			await get_tree().create_timer(t - last_t).timeout
			last_t = t
			await shot.call("bitti_%04.1f" % t)
		print("[test] oyun bitti, goruntu: ", shots.n)
		get_tree().quit()
		return
	if _auto == "host":
		net.join(code, "Kurucu", true)
		await net.welcomed
		print("[test] oda kuruldu, kod ", net.room_code, " hücre ", net.my_cell)
		while net.players.size() < 2:
			await get_tree().process_frame
		print("[test] oyuncular: ", net.players)
		if args.has("lobishot"):
			await get_tree().create_timer(2.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(args.lobishot)
		net.send({"t": "basla"})
		await net.ringing
		print("[test] telefon çalıyor, arayan ", net.player_name(phone_peer))
		await get_tree().create_timer(1.0).timeout
		_answer()
	else:
		await get_tree().create_timer(2.0).timeout
		net.join(code, "Arkadaş", false)
		await net.welcomed
		print("[test] odaya katıldı, hücre ", net.my_cell)
		net.send({"t": "hazir", "on": true})  # kurucu ancak herkes HAZIR iken başlatabilir
		await net.started
		await get_tree().create_timer(1.5).timeout
		print("[test] uzaktaki oyuncular: ", remotes.keys())
		_do_emote("selam")
		await get_tree().create_timer(3.0).timeout
		print("[test] karşıdakinin görünüşü: ", _player_entry(_other_id()).get("g", {}))
		_dial(_other_id())
	await net.call_connected
	print("[test] arama bağlandı")
	await get_tree().create_timer(4.0).timeout
	print("[test] ses: yollanan %d, gelen %d paket" % [voice.sent_packets, voice.received_packets])
	if args.has("shot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.shot)
	if _auto == "join":
		_hang_up()
	else:
		await net.call_ended
		print("[test] karşı taraf kapattı")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


# Otomatik test (auto=oyun tekrar=1): maç bitti -> maç sonu ekranında TEKRAR OYNA'ya basılır -> salonda
# önceki maçtan bir şey kalmamış mı denetlenir -> herkes salona dönünce 2. maç aynı odada başlar ve biter.
func _auto_tekrar(args: Dictionary, shot: Callable) -> void:
	var t0 := 0.0
	for t in [3.5, 7.2, 10.4]:
		await get_tree().create_timer(t - t0).timeout
		t0 = t
		await shot.call("bitti_%04.1f" % t)
	var ms = game_ui.get("_mac_sonu")
	var bek := 0.0
	while is_instance_valid(ms) and not (ms._btns.visible and ms._btns.modulate.a > 0.99) and bek < 8.0:
		await get_tree().create_timer(0.2).timeout
		bek += 0.2
	await shot.call("bitti_dugmeler")
	print("[test] maç sonu: düğmeler %s (%.1f sn sonra), ÇIKIŞ '%s', TEKRAR '%s'" % [str(is_instance_valid(ms) and ms._btns.visible),
		10.4 + bek, tr("ÇIKIŞ"), tr("TEKRAR OYNA")])
	ms._again_btn.pressed.emit()  # TEKRAR OYNA'ya basılmış gibi
	await get_tree().create_timer(1.6).timeout
	await shot.call("lobi_donus")
	# önceki maçtan kalan bir şey var mı?
	var kalan := []
	if not in_lobby:
		kalan.append("salonda değil")
	if game_on or game_ui.visible or game_ui.mod != null or game_ui.mac_sonu_acik():
		kalan.append("oyun ekranı")
	if not (hud.lobby_panel and hud.lobby_panel.visible):
		kalan.append("HUD salon düzeninde değil")
	if phone_state != Phone.IDLE:
		kalan.append("telefon")
	for c in cells:
		if c.door_open or not c.power or c.fuse_state != "normal" or c.ringing or not c.handset_home or c.locker_open \
				or (c.board_label and c.board_label.text != "") or c.locked:
			kalan.append("hücre %d" % c.index)
	if player.seated or player.busy or player.crouched:
		kalan.append("oyuncu durumu")
	if player.global_position.distance_to(lobby.spawn_point(net.my_cell)) > 3.0:
		kalan.append("oyuncu salonda değil")
	print("[test] salona dönüş: kalıntı %s, oyun ekranı çocukları %d, kod %s, kurucu %s, oyuncular %s" % [
		str(kalan), game_ui._root.get_child_count(), net.room_code, str(net.is_host),
		str(net.players.map(func(p) -> String: return "%s%s%s" % [p.name, "*" if bool(p.get("ms", false)) else "", "(bot)" if bool(p.get("bot", false)) else ""]))])
	# maç sonu ekranında kalan varsa (süre dolunca sunucu alır) bekle; sonra herkes salonda
	var bekle := 0.0
	while net.players.any(func(p) -> bool: return bool(p.get("ms", false))) and bekle < 25.0:
		await get_tree().create_timer(0.5).timeout
		bekle += 0.5
	await get_tree().create_timer(0.8).timeout
	await shot.call("lobi_hepsi")
	var ol: Array = str(args.get("oyunlar", "")).split(",", false)
	net.send({"t": "basla", "hiz": float(args.get("hiz", "0.2")), "oyunlar": ol})
	await net.started
	await get_tree().create_timer(2.5).timeout
	await shot.call("mac2_basla")
	print("[test] 2. maç başladı: hücre %d, salonda %s, kilitli hücreler %s" % [my_cell, str(in_lobby),
		str(cells.filter(func(c) -> bool: return c.locked).map(func(c) -> int: return c.index))])
	await net.game_over
	print("[test] 2. maç bitti")
	await get_tree().create_timer(10.4).timeout
	await shot.call("mac2_bitti")


# Otomatik test: yeni oyunlarda her aşamada ne görünüyor (kurucu = "Sen" oynar).
func _auto_state(d: Dictionary, shot: Callable) -> void:
	var t := str(d.task)
	var ph := str(d.phase)
	await get_tree().create_timer(0.4).timeout
	var m = game_ui.mod
	if not m:
		return
	if m.has_method("auto_test"):  # bir oyun kendi test adımlarını kendi dosyasında taşıyabilir
		await m.auto_test(ph, shot)
		return
	match t:
		"kimkim":
			if ph == "telefon":
				m.close_card()
				_open_contacts()
				await get_tree().create_timer(0.4).timeout
				await shot.call("kimkim_rehber")
				hud.contacts.visible = false
				var cands: Array = m.secret.get("adaylar", [])
				# hatlara sırayla aday koy (gerçek eşleşme telefonda bilinmez)
				var k := 0
				for c in m.contacts():
					m.picks[int(c.id) - 100] = int(cands[k % cands.size()].id)
					k += 1
				m.open_board()
				await get_tree().create_timer(0.4).timeout
				await shot.call("kimkim_tahta")
				var other: int = 1 if m.my_line() != 1 else 2
				m._open_chooser(other, {other: Button.new()})
				await get_tree().create_timer(0.3).timeout
				await shot.call("kimkim_secici")
				var out := {}
				for key in m.picks:
					out[str(key)] = int(m.picks[key])
				game_ui.decided.emit({"eslesme": out})
				m.close_panel()
		"yalanci":
			if ph == "telefon":
				m.close_card()
				player.global_position = cells[my_cell].to_global(Vector3(-0.35, 0, -0.2))
				player.rotation.y = PI / 2
				player.head.rotation.x = deg_to_rad(-12)
				await get_tree().create_timer(0.5).timeout
				m.do_action("dolap")
				await get_tree().create_timer(0.9).timeout
				m.close_card()
				await shot.call("yalanci_dolap3d")
				m._item_card()
				await shot.call("yalanci_esya")
				m.close_card()
				m._wear(true)
				player.global_position = cells[my_cell].to_global(Vector3(-0.75, 0, 1.05))
				player.rotation.y = PI / 2
				player.head.rotation.x = deg_to_rad(4)
				await get_tree().create_timer(1.0).timeout
				await shot.call("yalanci_ayna")
			elif ph == "oylama":
				await get_tree().create_timer(0.6).timeout
				await shot.call("yalanci_oylama")
				for id in d.players:
					if int(id) != net.my_id:
						game_ui.decided.emit({"oy": int(id)})
						break
		"rulet":
			if ph == "oyun":
				m.close_card()
				await get_tree().create_timer(0.3).timeout
				await shot.call("rulet_basla")
				_auto_rulet_turn(shot, 0.6)
		"c4":
			if ph == "anons":
				await get_tree().create_timer(0.3).timeout
				await shot.call("c4_alarm")
			elif ph == "bomba":
				m.close_card()
				player.global_position = cells[my_cell].to_global(Vector3(1.0, 0, 0.5))
				player.rotation.y = -PI / 2
				await get_tree().create_timer(1.2).timeout
				await shot.call("c4_kapilar")
				if m.holder == net.my_id:
					await get_tree().create_timer(0.8).timeout
					player.global_position = Vector3(3.9, 0, cells[my_cell].global_position.z)
					game_ui.decided.emit({"ver": _other_id()})
		"ortalama":
			if ph.begins_with("yaz"):
				m.close_card()
				await get_tree().create_timer(0.3).timeout
				m.number = str(10 + randi() % 30)
				m.open_board()
				await get_tree().create_timer(0.3).timeout
				if ph == "yaz1":
					await shot.call("ortalama_tuslar")
				game_ui.decided.emit({"sayi": int(m.number)})
				m.saved = int(m.number)
				cells[my_cell].set_board_text(str(m.saved))  # onay tuşunun yaptığı gibi: sayı 3D tahtada
				m.close_panel()
				if ph == "yaz1":
					# hücredeki 3D tahtaya bak: yazılan sayı orada görünmeli
					player.global_position = cells[my_cell].to_global(Vector3(0.35, 0, -0.9))
					player.rotation.y = cells[my_cell].global_rotation.y
					player.head.rotation.x = deg_to_rad(8)
					await get_tree().create_timer(0.8).timeout
					await shot.call("ortalama_tahta3d")


# Silah bendeyse: sırayla şakağa ya da bakışla birine doğrult, tetiği çek (ekran görüntüsüyle).
func _auto_rulet_turn(shot: Callable, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	var m = game_ui.mod
	if not m or str(m.task) != "rulet" or m.holder != net.my_id or m.busy or not (net.my_id in m.alive):
		return
	await m.auto_sira(shot)  # bakışla hedef + tetik (rulet_ui.gd)


var args_test_ustten_alindi := false  # test: rulette yukarıdan (izleyici) görüntüsü bir kez alınır


func _auto_event(d: Dictionary, shot: Callable) -> void:
	var tur := str(d.get("tur", ""))
	var mm = game_ui.mod
	if mm and str(mm.task) == str(d.get("task", "")) and mm.has_method("auto_event"):
		await mm.auto_event(d, shot)
		return
	match str(d.get("task", "")):
		"rulet":
			if tur == "atis":
				await get_tree().create_timer(0.9).timeout
				await shot.call("rulet_gerilim")
				await get_tree().create_timer(1.0).timeout
				await shot.call("rulet_" + ("bam" if bool(d.patladi) else "tik"))
				if bool(d.patladi) and int(d.olen) != net.my_id:
					await get_tree().create_timer(1.6).timeout
					await shot.call("rulet_ceset")
					if not args_test_ustten_alindi:
						# izleyici görünümü (ölünce kamera masanın üstüne çıkar): bir kez yukarıdan da çek
						args_test_ustten_alindi = true
						var hy: float = player.head.position.y
						var hx: float = player.head.rotation.x
						player.head.position.y = 2.5
						player.head.rotation.x = deg_to_rad(-40)
						await get_tree().create_timer(0.3).timeout
						await shot.call("rulet_ustten")
						player.head.position.y = hy
						player.head.rotation.x = hx
				elif bool(d.patladi):
					# ben öldüm: kamera masanın üstüne çıkar (izleyici görünümü)
					await get_tree().create_timer(5.0).timeout
					await shot.call("rulet_izleyici")
				_auto_rulet_turn(shot, 1.3)
			elif tur == "sira":
				_auto_rulet_turn(shot, 0.8)
		"c4":
			match tur:
				"verdin":
					await get_tree().create_timer(0.15).timeout
					await shot.call("c4_isinlan")
				"verdi":
					if int(d.kime) == net.my_id:
						await get_tree().create_timer(0.5).timeout
						await shot.call("c4_bomba_sende")
						await get_tree().create_timer(1.5).timeout
						if game_ui.mod and game_ui.mod.holder == net.my_id:
							game_ui.decided.emit({"ver": _other_id()})
				"patlama":
					await get_tree().create_timer(0.12).timeout
					await shot.call("c4_patlama_a")
					await get_tree().create_timer(0.45).timeout
					await shot.call("c4_patlama_b")
					await get_tree().create_timer(1.2).timeout
					await shot.call("c4_patlama_c")
		"ortalama":
			if tur == "goster" and int(d.get("el", 0)) == 1:
				await get_tree().create_timer(3.0).timeout
				await shot.call("ortalama_sonuc")


func _other_id() -> int:
	for p in net.players:
		if int(p.id) != net.my_id:
			return int(p.id)
	return 0
