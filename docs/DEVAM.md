# Hat Düştü — Devir teslim (otomatik devam için)

Son güncelleme: 26 Ekim 2026, 03:45. Bu belge, kullanıcı uyurken otomatik başlayan oturumun kaldığı yerden devam etmesi içindir.

## Kullanıcı (Türk, kod bilmiyor) ne istiyor
Mağazaya çıkacak PROFESYONEL bir mobil oyun. Tam yetki verdi: "baştan aşağı düzenle, ajanlarla iş bölümü yap, görseller üret, CC0 paket indir". Öncelikler:
1. Hiçbir sorun olmadan çalışan oyun sistemi (derleme temiz, 7 oyun botlarla baştan sona hatasız).
2. Kayıt / giriş / arkadaş ekleme / davet sorunsuz.
3. Karakter özelleştirme: kadın + erkek, farklı saç, sakal/bıyık, TEN RENGİ, kafaya takılanlar (şapka, gözlük, kulaklık...), aksesuar, hareketler (emote).
4. Yeni özellikler; yanlış/hatalı her şeyi düzelt; kendi "böyle daha iyi" dediğin iyileştirmeler.
5. MOBİL: ekranı çok kaplayan şeyler olmasın, dokunma alanları ≥64 px, az yazı.
6. Karakterde ya da herhangi bir şeyde bozukluk olmasın: her detayı ekran görüntüsüyle kontrol et.
Kurallar: iPhone/Android derlemesi YAPMA (kullanıcı isteyince). Puanlar maç sonuna kadar gizli. Oyunlara ait eşyalar oyun gelene kadar sürprizi bozmasın. Sadece CC0 varlık (lisans sorunu olmasın; her kaynak LISANS.txt'ye). OpenAI görsel bakiyesi biterse kullanıcıya hemen haber ver. Commit'lerin sonuna: "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>".

## Ortam
- Proje: D:\HatDustu (Godot 4.7.2, GDScript, Türkçe yorum). Godot: D:\Godot\Godot_v4.7.2-stable_win64_console.exe
- Derleme kontrolü: `cd /d/HatDustu && timeout 300 /d/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|at: "` (boş olmalı). GDScript'te `var x := dict.get()` tip çıkarım hatası verir, açık tip yaz.
- Sunucu: server/ (Cloudflare Worker + Durable Objects). Yerel test: `cd /d/HatDustu/server && npx wrangler dev --port 8794` (arka planda). Sözdizimi: `npx esbuild src/index.js --bundle --format=esm --outfile=<tmp>.js`. CANLIYA YÜKLEME (wrangler deploy) yapılmadı; kullanıcı onay vermeden yapma (canlıda eski sürüm var, yerel sürüm çok ileride).
- Botlu otomatik maç (ekran görüntüsü alır): `/d/Godot/Godot_v4.7.2-stable_win64_console.exe --path . -- server=ws://127.0.0.1:8794 auto=oyun code=<4 HARF> n=4 botlar=3 hiz=0.2 oyunlar=tahta,devre,kimkim,yalanci,rulet,c4,ortalama klasor=<klasör>`
- Tekil ekran: `-- server=ws://127.0.0.1:8794 shot=<png> pose=<poz> wait=3` (pozlar scripts/main.gd _handle_cmdline: menu, oyna, ayarlar, menu_ayarlar, giris, gorevler, basarimlar, liderlik, elmas, karakter cat=.., envanter, arkadas demo=1, lobi, arama, oyunhud, panel, sema, pano, cell, corridor, kit...). Montaj: `tools/montaj.gd` (dosyalar=a,b hucre=760 sutun=2 cikti=..).
- Görsel üretim: tools/gorsel_uret.mjs, tools/arayuz_uret.mjs (OpenAI anahtarı .gizli/openai.txt — ASLA yazdırma; saydam → gpt-image-1.5). Tasarım dili: docs/TASARIM.md + scripts/ui.gd.
- Kullanıcının test kısayolu: "Botlarla Test (yerel sunucu).bat" (8794). Oyunu kullanıcıya göstermek için: önce wrangler 8794 açık olsun, sonra bu .bat.

## Bitenler (bu oturumda)
Ekonomi sunucuda (elmas/kasa/satın alma/görev/başarım/seviye/haftalık liderlik/günlük ödül, ekonomi.js + accounts.js), geri bağlanma (45 sn), Hızlı Oyun (eşleştirme + 25 sn sonra botla dolum), maç ödülü (XP+elmas), sunucu botları (lobide +BOT), müzik + gardiyan anonsları (scripts/muzik.gd), hata raporu (scripts/telemetri.gd → /telemetri), gizlilik/koşullar (/gizlilik, /kosullar; e-posta ILETISIM_EPOSTASI yer tutucu — kullanıcıya sorulacak), şikayet/engelleme/hesap silme, Kim Kim? takma kimlik, C4 yakınlık kontrolü, yakınlık sesi (sunucu: audible()), elmas paketleri (TEST_ODEME açık — yayından önce kapat + gerçek ödeme), tasarım takımı (ui.gd + assets/ui/kit), maç sonu (mac_sonu.gd, taçlı) + tur sonu (tur_sonu.gd, puansız), menü/ayarlar/giriş/görevler/liderlik (menu.gd, settings.gd, giris.gd, gorevler.gd, liderlik.gd, ekran.gd), oyun içi HUD/lobi/arama/arkadaşlar/şikayet (hud.gd, friends.gd, oyuncu_ui.gd), elmas mağazası (elmas_magaza.gd), Kısa Devre baştan (devre_box.gd, devre_sema.gd, devre.js), uygulama ikonu + açılış ekranı.

## 26 Ekim sabah oturumu (07:00 sonrası) — durum
Commit cc1b72f: tüm büyük iş tek kayıtta (GitHub'a gönderilmedi; canlı sunucu ESKİ).
- BİTTİ: Gerçek eller (aim_mod IK, FP ışığı FP_LAYER), CC0 altıpatar (assets/models/altipatar, OpenGameArt loafbrr_1), C4 elde, kadranlı telefon + spiral kablo (scripts/telefon.gd), yakınlık sesi (voice.gd set_spatial). Test: `pose=el el=silah|sakak|hedef|ahize|telefon|kablo|kapat|c4|itme`.
- BİTTİ: 3D dünya (dunya.gd, cell.gd, lobby3d.gd yemekhane, koridor), doku sıkıştırma, occlusion, kalite Pil dostu/Yüksek/Ultra; menüdeyken 3D çizim kapalı (menu.gd _dunya_ciz).
- BİTTİ: Karakterler Quaternius CC0 (assets/govde), look.govde erkek/kadin, ten/göz rengi, 21 saç, sakallar, 14 yeni aksesuar, 10 kıyafet, 20 hareket (Quaternius UAL + koddan). ESKİ mahkum.fbx/PowerPlantA SİLİNDİ. Botlar %40 kadın. Test pozları: `pose=kadro [hareket=]`, `pose=ayna [govde=kadin]`, `pose=macsonu`.
- BİTTİ: Hesap/giriş/arkadaş/davet uçtan uca (11 hata düzeltildi). Test betikleri scratchpad\hesap\.
- BİTTİ: Oyun içi ekranlar (oyun_ici.gd), mağaza/kasa/envanter, gereksiz yazılar kaldırıldı.
- SÜRÜYOR (ajanlar): (1) Kısa Devre "KUTUNU ONAR" modalı sonraki oyunlarda ekranda kalıyor + yalancıda üst üste iki band + maç sonu kontrolü + Tween uyarısı (oyun ekranları ajanı); (2) ten gölgelendiricide yeşil leke boyun/omuz + aynada yeşil yüz (karakter ajanı); (3) çıkış onayı, misafir ilerleme uyarısı/taşıma, menü ad penceresi klavye, arkadaş listesinde MAÇTA durumu (hesap ajanı).
- KALAN BÜYÜK İŞLER: gerçek ödeme (godot-iap) + ödüllü reklam, İngilizce dil, gizlilik iletişim e-postası (kullanıcıya sor), ODEME_TEST kapatma, mağaza materyalleri/ekran görüntüleri, canlıya yükleme (kullanıcı onayı), emote sırasında 3. şahıs kamera, kıyafet hâlâ biraz köylü tuniği tarzı (Quaternius ücretsiz pakette tulum yok).

## Nasıl devam et
1. `git status` ve derleme kontrolü; derleme hatalarını düzelt (yarım dosyaları tamamla). Yerel sunucuyu 8794'te başlat.
2. Yarım kalan her alanı bir alt ajana ver (dosya sahipliği çakışmasın; her ajana "başkasının dosyasına dokunma, ekran görüntüsüyle doğrula, commit atma" de). Biten ajanların ekran görüntülerini Read ile kendin incele.
3. Her şey temiz derlenince tam botlu maç + tüm ekran pozlarıyla denetim yap; sorunları düzelttir. Mobil uygunluk (2400x1080 ve 1280x720), karakter bozuklukları, yazı fazlalığı.
4. Kararlı noktalarda commit at (kısa Türkçe mesaj + Co-Authored-By satırı). Canlıya yükleme ve telefon derlemesi YOK.
5. Bu belgeyi güncelle (bitenler/kalanlar), memory dosyasına önemli kararları yaz.
