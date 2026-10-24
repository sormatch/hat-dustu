# Bir kerelik test: gerçek sunucuda kayıt → profil yaz → çıkış → giriş → profil geri gelir mi.
extends SceneTree

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _init() -> void:
	var acc: Node = load("res://scripts/account.gd").new()
	root.add_child(acc)
	var tok := Crypto.new().generate_random_bytes(16).hex_encode()
	acc.start("wss://hat-dustu.hatdustu.workers.dev", tok)
	await _wait(3.0)
	var h := "dene%d" % (randi() % 90000 + 10000)
	acc.sign_up(h, "sifre123", "Deneme")
	await _wait(3.0)
	print("kayit: handle=", acc.handle, " hesap=", acc.has_account)
	acc.push_profile({"ad": "Deneme", "elmas": 12345, "sahip": ["sac:uzun"], "gorunum": {}})
	await _wait(1.5)
	acc.sign_out()
	await _wait(3.0)
	print("cikis: handle='", acc.handle, "' hesap=", acc.has_account)
	acc.sign_in(h, "yanlis1")
	await _wait(2.0)
	acc.sign_in(h, "sifre123")
	await _wait(4.0)
	print("giris: handle=", acc.handle, " hesap=", acc.has_account, " ayni_anahtar=", acc.token == tok, " profil=", acc.remote_profile)
	quit()
