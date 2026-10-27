# Hat Düştü — Devir teslim (otomatik devam için)

Son güncelleme: 26 Ekim 2026, akşam (son tur: hata avı ve cila). Bu belge, kullanıcı uyurken otomatik başlayan oturumun kaldığı yerden devam etmesi içindir.

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
- Botlu otomatik maç (ekran görüntüsü alır): `/d/Godot/Godot_v4.7.2-stable_win64_console.exe --path . -- server=ws://127.0.0.1:8794 auto=oyun code=<4 HARF> n=4 botlar=3 hiz=0.2 oyunlar=tahta,devre,kimkim,yalanci,rulet,c4,ortalama klasor=<klasör>` (oyunlar= verilmezse "Tüm oyunlar" kuralı: 6 oyun)
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
- BİTTİ (sonradan): oyun geçişinde kalan pencereler/bantlar, maç sonu tam; yeşil ışık (cell.gd glow cull_mask); hesap akışı (çıkış onayı, misafir uyarısı, MAÇTA/İZLE); İngilizce (878+ çeviri, tools/ceviri_*.mjs); yayın engelleri (/hesap-sil, küfür süzgeci server/src/suzgec*.js, topluluk kuralları, sürüm 1.0.0, Play AAB ön ayarı + .github/workflows/android_play.yml, ödeme kapalıyken "Yakında"); moderasyon (maçta şikayet/engelleme, /yonetim, YONETICI_ANAHTARI sırrı); hareket (emote) birinci şahısta: kamera göz hizasında, büyük hareketlerde kendi gövde gizli (pose=hareket1p hareket=a,b govde=erkek,kadin,iri yer=hucre,koridor,ayna an=0.5 uzak=1 yuru=1); 2D QA (güvenli alan UI.guvenli, Android geri tuşu UI.geri_tusu); yaka bandı, maç sonu ışığı; ses atmosferi (bus düzeni Master/Muzik/Efekt/Ortam/Ses, ortam döngüsü, ayak sesleri, ducking); performans (çizim ~yarıya, VRAM ~%40 az, sızıntılar) ve paket ~137 MB APK.
- KALAN (kullanıcı gerekir): destek e-postası (ILETISIM_EPOSTASI), canlıya yükleme onayı (önce wrangler.toml ODEME_TEST="0" ve `wrangler secret put YONETICI_ANAHTARI`), gerçek ödeme (kod HAZIR 27 Ekim; kullanıcı: mağazalarda ürünler, Google lisans anahtarı, Apple Paid Apps sözleşmesi), Play keystore ve GitHub sırları, seslerin kulakla dinlenmesi, gerçek telefonda fps/çentik/klavye denemesi.
- KALAN (küçük): 1k model normal haritaları 512'ye inebilir (~20 MB); yasaklı kişi hesabını silip yeniden açabilir.

## Oyunlar, maç süresi, market, yeni içerik — 26 Ekim akşam
- 7 mini oyun (server/src/modes/): kimkim, tahta, devre, yalanci, rulet, c4, ortalama. Kullanıcı KESİN KURAL: yeni mini oyun EKLEME (Mahkum İkilemi ve Kumarbaz eklenmiş, beğenilmeyip silindi).
- **Maç süresi kuralı** (server/src/game.js `macListesi`): lobide "TÜM OYUNLAR" seçiliyse maç `MAC_OYUN` = 6 oyun (~20 dk). Kim Kim? oynanabiliyorsa hep ilk; kalan 5 oyun oynanabilenlerden rastgele; sıra karışık ama aynı tür (`TUR`: telefon/olum/secim/beceri/blof) arka arkaya gelmez. Oda sahibi tek oyun seçtiyse (ya da test listesi `oyunlar=...`) yalnız o liste, verilen sırayla. Oyuncu azalınca en az kişisi tutmayan oyunlar atlanır (`siradaki`, `checkEnd`); maç sonu tablosu oynanan oyun kadar sütun. Test: `cd server && node test/mac_test.mjs`.
- **Market** server/src/market.js (+ ekonomi.js): günün fırsatları (vitrin), haftanın seti (+%10), 11 tematik set (`SETLER`; yeniler Gardiyan, Kovboy, Firar), kasa şans güvencesi (`GUVENCE`) ve olasılıklar, istek listesi, arkadaşa hediye, seviye yolu (scripts/seviye_yolu.gd). Test: `cd server && node test/market_test.mjs` (8794 açıkken uçtan uca kısmı da koşar).
- **Yeni içerik**: 4 gövde tipi (model_body.gd `TYPES`: iri, yasli, kadin_iri, ince), 8 kıyafet, 8 şapka, 6 aksesuar, 9 hareket, hücre eşyaları (kitaplık, radyo, saksı, saat, lavabo, ağırlık, poster). Yaka bandı (model_body.gd `_collar_band`): iç kenar ağırlıkları boyundan kopyalanır, üst kısmı deri malzemesiyle çizilir.
- **Test pozları**: `pose=dizi govde=erkek,iri,yasli kiyafet=.. sapka=.. yakin=kafa|govde|boy yon=on|arka|yan|ceyrek hareket=<id> t=<sn> isik=1` (karakter dizisi; yaka için `yakin=kafa hareket=hayir`), `pose=dizi hucre=<n> aci=1|2|3|raf|lavabo|saat` (hücre içi), `pose=yol demo=1 kaydir=<sıra>` (seviye yolu), `pose=karakter cat=vitrin|setler|sandik|govde|sapka demo=1 set=<k> asagi=<px> olasilik=1 hediye=1 item=<id>` (mağaza).
- **DİKKAT**: main.tscn'i açan test betikleri (scratchpad hesap/mac_sonu_test.gd, macta_oyun_test.gd, tasima_oyun_test.gd) MUTLAKA `-- server=ws://127.0.0.1:8794 profil=<ad>` ile çalıştırılmalı. Yoksa canlı sunucuya bağlanır ve varsayılan profili (user://profil.cfg) değiştirir, tasima testi siler.

## Dil desteği (Türkçe / English) — 26 Ekim
- Kaynak dil Türkçe; çeviri anahtarı Türkçe metnin kendisi. Kaynak: `tools/ceviri_en.json` (Türkçe -> İngilizce, elle düzenlenir) -> `node tools/ceviri_po.mjs` -> `translations/en.po` (project.godot internationalization, fallback tr). Eksik tarama: `node tools/ceviri_tara.mjs` (eksik çeviri + tr() ile sarılmamış biçimli dizeler; bilinçli yoksayılanlar `tools/ceviri_yoksay.txt`).
- Kurallar: Label/Button metni kendiliğinden çevrilir. Biçimli metinde çeviri biçimden ÖNCE: `tr("%d/%d yazdı") % [a, b]`; statik fonksiyonda `Dil.t(...)`. Elle çizilen yazı (draw_string) ve Label3D'ye biçimli metin verirken tr() şart. Büyük harf: `Dil.buyuk()` (Türkçede i -> İ). Sayı: `E.sayi()` dile göre ayraç (10.025 / 10,025). Sabit genişlikli düğme/kutucukta uzun yazı `UI.sigdir` ile küçülür.
- `scripts/dil.gd`: açılışta dil = test parametresi `dil=en` > ayarlardaki seçim (profile.settings.dil) > cihaz dili (Türkçe değilse İngilizce). Ayarlar > PROFİL > "Dil / Language" anında uygular.
- Sunucu: metinler Türkçe gider, telefon çevirir. Değişkenli metinlerde sunucu ayrıca `<alan>_k` = [[şablon, [değerler]]] yollar (server/src/metin.js `tx()`/`metin()`), istemci `Dil.sunucu(d, "m")`. Oda dili = kurucunun dili (`&dil=` ws parametresi): Kara Tahta bot kelimeleri ve büyük harf kuralı buna göre.
- Gardiyan anonsları: İngilizcesi `assets/ses/anons_en/` (`node tools/ses_uret.mjs en`), muzik.gd dile göre seçer. Gizlilik/koşullar: İngilizcede sayfanın `#en` bölümü açılır.
- Test: tüm pozlar `dil=en` ile İngilizce çekilir; `pose=ayarlar dil_sec=en` ayarlar açıkken dili anında değiştirir (kayda yazmaz).

## Mağaza engelleri — 26 Ekim (yayın hazırlığı)
- Hesap silme web sayfası: `/hesap-sil` (+ `/delete-account`), server/src/hesap_sil.js; silme işi accounts.js `deleteAccount` (oyun içi ile ortak), `webDelete` (deneme sınırı), saklama süreleri `KAYIT_SURE`.
- Küfür süzgeci: server/src/suzgec.js + suzgec_liste.js (kaba kelimeler YALNIZ bu dosyada). Test: `cd server && node test/suzgec_test.mjs`. Adlar (hesap + oda) ve Kara Tahta ("***") sunucuda süzülür; istemci `account.ad_dene()` ile sorar.
- Topluluk kuralları onayı: giris.gd `kurallar_onayi / kurallar_sonra` (profile.settings.kurallar). Test pozu: `pose=menu kurallar=1`; ad reddi: `pose=menu ad_dene=<ad>`; uçtan uca şikayet: `pose=sikayet menu=1 gonder=1`.
- Gerçek ödeme yokken (eklenti yok / sunucu o mağazayı doğrulamıyor) ve ODEME_TEST=0 iken elmas paketleri "YAKINDA". ekonomi.js `TEST_ODEME=false`; test modu yalnızca wrangler.toml `ODEME_TEST="1"` (CANLIDA "0").
- Maçta şikayet/engel: istemci oda içi numarayı yollar ({t:"sikayet"|"engelle", id}), Room hesaba çevirir (accounts.js /ic/oda-*). Anahtarla engel tablosu blocks_t; ses yönlendirmesinde Room.engelli (iki yön); Hızlı Oyun eslestirme.js /ic/engelliler (istemci X-Hesap başlığı).
- Yönetim: /yonetim (server/src/yonetim.js, Accounts içinde). Anahtar env.YONETICI_ANAHTARI (yerel server/.dev.vars, canlı wrangler secret put). Yasak users.yasak_bitis, uyarı users.uyari. Test: scratchpad hesap/test_moderasyon.mjs.
- Sürüm tek kaynak: project.godot `application/config/version` (1.0.0). "Android Play" ön ayarı (Gradle + AAB) ve .github/workflows/android_play.yml (çalıştırılmadı).

## Tekrar Oyna + rehberde meşgul — 26 Ekim gece
- **Tekrar Oyna**: maç sonu ekranında (mac_sonu.gd) ana düğme TEKRAR OYNA (köşede kendiliğinden dönüşe kalan saniye), ikincil ÇIKIŞ (ana menü; Android geri tuşu da). Satır köşesinde diğerlerinin durumu: LOBİDE / ÇIKTI.
- Sunucu (index.js Room): maç bitince `macBitti` (herkes `ms`=maç sonu ekranında, ödül `reportMatch` maç başına bir kez, `msBitis` = en geç dönüş: 30 sn × hız, en az 20 sn). İlk `{t:"tekrar"}` (ya da süre dolması, ya da odaya yeni gelen) `lobiyeDon`: oyun silinir, started=false, hazır/telefon/kapı temizlenir, kod ve sahip aynı, özel odada botlar kalır; Hızlı Oyun botları bırakır, eşleştirmeye yeniden açılır, `PUBLIC_WAIT` sonra yine botla dolar. Dönen oyuncuya `{t:"lobi", id, cell, host, code, players}`. Maç sonundaki varken BAŞLAT olmaz ("{0} henüz maç sonu ekranında."); süre dolunca `herkesLobiye`. Lobide/maç sonunda çıkan için `bilgi "{0} odadan çıktı."` (+ sahiplik devri).
- İstemci: main.gd `_tekrar_oyna` / `_lobiye_don` (sahne yeniden yüklenmez): game_ui.reset_after_match, cell.mac_sonrasi (kapı, elektrik, sigorta, tahta, telefon, dolap, kilit), uzak gövdeler yeniden kurulur, player.reset_state, HUD salon düzeni (kartta "MAÇ SONU" etiketi), müzik "menu" + ortam sesi, arkadaş durumu ODADA (yeni maçta MAÇTA). net.gd `lobby_back` sinyali.
- Testler: `cd server && node test/tekrar_test.mjs` (birim + uçtan uca, 43 kontrol). Otomatik maç: `auto=oyun tekrar=1 ... profil=<ad>` maç sonu → TEKRAR → salonda kalıntı denetimi → 2. maç (yardımcı insanlar: build/tekrar/yardimci.mjs KOD ad erken|gec|cik).
- **Rehberde meşgul**: telefondaki kişinin kartı kırmızı + büyük MEŞGUL/BUSY, arama düğmesi gri ve pasif (hud.gd `_kart_mesgul`); rehber açılınca `{t:"hatlar"}` ile güncel liste istenir (Kim Kim? takma numara ve "****" kuralı aynı `hatlar()` içinde). Test: `pose=arama durum=rehber`; üç istemcili gerçek arama build/tekrar/rehber_test.gd + arama_yardimci.mjs.

## Nasıl devam et
1. `git status` ve derleme kontrolü; derleme hatalarını düzelt (yarım dosyaları tamamla). Yerel sunucuyu 8794'te başlat.
2. Yarım kalan her alanı bir alt ajana ver (dosya sahipliği çakışmasın; her ajana "başkasının dosyasına dokunma, ekran görüntüsüyle doğrula, commit atma" de). Biten ajanların ekran görüntülerini Read ile kendin incele.
3. Her şey temiz derlenince tam botlu maç + tüm ekran pozlarıyla denetim yap; sorunları düzelttir. Mobil uygunluk (2400x1080 ve 1280x720), karakter bozuklukları, yazı fazlalığı.
4. Kararlı noktalarda commit at (kısa Türkçe mesaj + Co-Authored-By satırı). Canlıya yükleme ve telefon derlemesi YOK.
5. Bu belgeyi güncelle (bitenler/kalanlar), memory dosyasına önemli kararları yaz.

## Mobil performans / bellek (27 Ekim) — iPhone çökme ve donma işi
- Mağaza küçük resimleri PAKETTE: `assets/kucuk/{erkek,kadin}/<kat>_<id>.webp` + `govde_<id>.webp` (tools/kucuk_resim_pisir.gd). Telefonda karakter çekilmez; resimler iş parçacığında yüklenir, LRU 72. YENİ EŞYA EKLEYİNCE: `Godot --path . --resolution 640x360 --script res://tools/kucuk_resim_pisir.gd -- yalniz_eksik=1` + import (yeni .import'larda compress/mode=1). Eksikse telefon kendisi çeker (user://thumbs/). Saç ve sakal kartları her saç rengi için ayrı (`<kat>_<id>_<renk>.webp`, kayıplı; Thumbs.RENKLI); Saç rengi sekmesi de bunları gösterir (oyuncunun saç stili o renkte). Saç dokusu/malzemesi değişince hepsini yeniden pişir.
- Arayüz görselleri PAKETTE: `assets/ui/hazir/` (UI.texture'ın kırpılmış+ölçeklenmiş hâlleri). Yeni ekran/boy eklenince: oyunu `ui_kayit=1` ile gez (user://ui_anahtar.txt), sonra `--script res://tools/ui_pisir.gd` + import (compress/mode=1). Eksik anahtar eskisi gibi çalışırken üretilir.
- Saç rengi denetimi: `--script res://tools/sac_renk_olc.gd -- cikti=..` (her stil x renk, kart ışığında; saçın ortalama tonu katalog rengiyle karşılaştırılır). MakeHuman gri dokuları `tools/sac_gri.gd` ile aynı ortalama parlaklığa çekilir (hair.gd gri_veri).
- Koddan üretilen dokular PAKETTE: `assets/pisir/` (saç teli, dövme mürekkepleri, yanık izi; tools/doku_pisir.gd).
- Açılış: scripts/acilis.gd (perde + kademeli kurulum + gölgelendirici ısıtma). main.gd _ready artık birkaç kare sürer: araçlar `if not main.hazir_mi: await main.hazir`. `--script` ile çalışan araçlarda kurulum eskisi gibi tek seferde (kademeli=1 verilirse perdeli). Sistem açılış görseli assets/ui/uretim/acilis_splash.png (tools/acilis_splash_uret.gd), boot_splash Keep + aynı zemin rengi. Görsel: yuvarlak "HAT DÜŞTÜ" amblemi. Yazısız taban OpenAI (gorsel_uret.mjs amblem_taban -> assets/ui/uretim/kaynak/, .gdignore), harfler logo.png den yaya bükülür: tools/amblem_uret.gd -> kaynak/amblem.png + animasyon katmanları amblem_zemin/tel/hat/dustu.png (kırpık katman yerleri acilis.gd KATMAN ile aynı olmalı), sonra acilis_splash_uret.gd. Animasyon: ahize iki kez çalar (koddan zil), ışık bandı geçer, HAT (1,05 sn) ve DÜŞTÜ (1,45 sn) metal vuruşla parlar. Kare denetimi: acilis_kare.gd anlar=0.03,0.4,... (çıktılar build/amblem/).
- Ölçüm araçları: tools/bellek_olc.gd (senaryo tablosu), tools/ackapa_olc.gd (ekran aç/kapa sızıntı), tools/doku_dok.gd (doku dökümü), tools/acilis_kare.gd (açılış kareleri), tools/onizleme_test.gd (mağaza önizleme davranışı), fps_olc `sahne=c4ani` (patlama karesi). Çıktılar build/mobil/.
- Telemetri: "onceki_cokme" olayı (user://oturum.cfg bayrağı), her olayda "mb": [bellek, vram], "bellek_uyarisi". export_presets: shader_baker açık; iphone.yml önce --headless'sız (fırınlı) dışa aktarmayı dener.

## Hazır sistemi, mikrofon düğmesi, bağlantı bildirimleri — 27 Ekim
- **Hazır**: maç yalnız bütün insanlar HAZIR iken başlar (botlar hep hazır). Özel oda: kurucunun BAŞLAT'ı kendi hazırı sayılır; HAZIR demeyen varken BAŞLAT gri/pasif (dokununca "Herkes hazır değil: Ad"), sunucu da `basla`yı reddeder (`bilgi` + `hazir_degil:[id]`). Hızlı Oyun (index.js `OTO_HAZIR` 35 sn, `HAZIR_SAYIM` 5 sn): geri sayım yalnız herkes hazırken işler (`acik_oda baslama:-1` = bekleniyor, salonda "Herkes hazır olunca başlar"); HAZIR demeyen salona girdikten 35 sn sonra kendiliğinden hazır sayılır; herkes hazır olunca en az 5 sn sayım, sonra eski kural (PUBLIC_WAIT dolmuşsa botla 4'e doldur). Maç sonu / Tekrar Oyna hazırları sıfırlar. Kartlarda ve salonda baş üstünde HAZIR / HAZIR DEĞİL (main.gd `_remote_etiket`), maçta gizli.
- **Mikrofon**: sol üstte ayarların altında 92 px aç/kapa düğmesi (hud.gd `Mik`, `MIK_OFS`): açık yeşil (konuşurken dalga), kapalı kırmızı çizik. Kapalıyken voice.gd `kapali` hiçbir ses parçası göndermez (yakın + telefon). Durum salon/maç/Tekrar Oyna arasında korunur. Sunucuya `{t:"mik",kapali}`; herkese `{t:"mik",id,kapali}`, listede `mk` → baş üstünde ve kartta çizik mikrofon.
- **Bildirimler**: sunucu `bilgi` mesajlarında `bag` (koptu, geri, ayrildi, katildi, cikti, sahip) + `id`; Kim Kim? sürerken ad yerine "****". İstemci net.gd `notice` → hud.gd `bildirim()`: ikonlu, sıralı, aynı anda en çok 2 (maçta üstte, salonda alt düğmelerin üstünde). Kopan oyuncunun baş üstünde çizik sinyal. Zayıf bağlantıda mikrofonun altında sarı/kırmızı sinyal (net.gd `baglanti_kalitesi`, 4 sn'de bir ping). Salondan maça geçişte ortada 3-2-1. Salonda arkadaşlık isteği bildirimi.
- Test: `cd server && node test/hazir_test.mjs` (birim + uçtan uca, 53 kontrol). Ekran: build/hazir/hazir_test.gd + yardimci.mjs (başlığındaki komut), pozlar `pose=lobi [host=0] [hizli=bekle] [bildirim=1] [ping=1|2] [mik=acik|kapali]`.

## ODALAR (oda kurma + açık odalar listesi) — 27 Ekim
- Menüde OYNA'nın altında üçlü: ODALAR · ODA KUR · KODLA KATIL (menu.gd `_dugme3`). ODA KUR penceresi (scripts/odalar.gd `kur_penceresi`): Arkadaşlarım / Herkes, kişi 4-8 (varsayılan 8), isteğe bağlı oda adı (varsayılan "Ali'nin odası", süzgeçten geçer), Botla doldur. Son seçimler profile.settings.oda_ayar.
- ODALAR ekranı (odalar.gd, CanvasLayer): POST /odalar {ark:[arkadaşların oda kodları]} -> en çok 50 "Herkes" odası; arkadaşlarınki üstte (ARKADAŞIN), 5 sn'de bir yenilenir, maçtakiler gri, dolu odada KATIL kapalı; red olursa bildirim + yenileme. Arkadaşların listede olmayan (Arkadaşlarım) odaları da üstte "X burada" satırı olarak görünür (arkadaş paneli zaten gösteriyordu).
- Sunucu: server/src/odalar.js — `Odalar` Durable Object (wrangler.toml v4) tek liste; Room ayarı `this.ayar` (depo "ayar"), kur=1 adresinde gor/max/oda_ad/botla; kişi sınırı Room'da ("Oda dolu (en fazla {0} kişi)."); `liste=1` ile yalnız lobideki Herkes odasına girilir. Room kurulunca/kişi/durum değişince/kapanınca `odaBildir`, en geç 25 sn'de bir nabız (mesaj + alarm), 60 sn haber gelmeyen kayıt düşer. Lobide sahip {t:"oda_ayar"} ile ayarı değiştirir (oda kartındaki şeride dokununca). Hızlı Oyun (eslestirme.js) ayrı, değişmedi.
- Join hatası artık 400 ms sonra kapanıyor (Godot hemen kapanan bağlantıda mesajı kaybediyordu: "Oda dolu" yerine genel hata çıkıyordu).
- Test: `cd server && node test/odalar_test.mjs` (55 kontrol). Pozlar: `pose=menu odalar=1 odalar_demo=dolu|bos`, `pose=menu oda_kur=1 oda_kur_gor=herkes`, `odalar_katil=<KOD>` (listeden katılır), lobide `pose=lobi oda_demo=herkes:6:1:Ad`. Görüntüler build/odalar/.

## Gerçek uygulama içi satın alma — 27 Ekim
- Ürünler (tüketilebilir, iki mağazada aynı kimlik): baslangic 59,99 · elmas_100 39,99 · elmas_550 179,99 · elmas_1200 349,99 · elmas_2500 699,99 · elmas_6500 1.749,99 TL (ekonomi.js PAKETLER, elmas_magaza.gd YEDEK_PAKETLER).
- İstemci: scripts/odeme.gd (/root/Odeme, sahne yenilense de yaşar; main.gd `baglan(account)`). iOS: GodotApplePlugins StoreKit 2 (GDExtension, MIT; repoda YOK, iphone.yml sabit sürümü SHA-256 ile indirip addons/GodotApplePluginsStoreKit + Runtime'a koyar; en az iOS 17 → export_presets min_ios_version 17.0). Android: addons/GodotGooglePlayBilling 3.3.0 (repoda, project.godot editor_plugins; yalnız Gradle'lı "Android Play" ön ayarında etkin; BILLING izni). Eklenti yoksa platform="" → YAKINDA.
- Akış: ürün sorgusu (kartta mağazanın yerel fiyat metni) → satin_al → makbuz {t:"elmas_paketi", platform, paket, islem, makbuz} → sunucu: "elmas_alindi" (yeni) / "odeme_tamam" (zaten işlenmiş) → ANCAK O ZAMAN finish/consume; "odeme_red" bitirilmez (sonraki açılışta mağaza yarım işlemi yeniden verir). Bekleyenler bağlantı gelince 20 sn'de bir yeniden gider.
- Sunucu: server/src/odeme.js (gizli anahtarsız doğrulama). iOS JWS: x5c[2] = gömülü Apple Root CA - G3 (bayt bayt), ara/yaprak imza zinciri (ECDSA P-384), Apple OID'leri (yaprak 1.2.840.113635.100.6.11.1, ara ...6.2.1), imza anında geçerlilik, ES256 JWS imzası; bundleId, type Consumable, ortam Sandbox|Production, iade yok. Android: originalJson + signature, GOOGLE_LISANS_ANAHTARI (boş → Android kapalı) RSASSA-PKCS1-v1_5/SHA-1, packageName, purchaseState 0. accounts.js odemeIsle: purchases.islem TEKİL dizin ("ios:<transactionId>" / "android:<purchaseToken>"), makbuz sütununda kısa özet; Başlangıç ikinci kez ödenirse elmas verilir, hediye kasa verilmez. Ekonomi özetinde `odeme: {ios, android}`.
- Test: `cd server && node test/odeme_test.mjs` (58 kontrol: gerçek Apple WWDR G6 ⇄ G3 zinciri, test kökü ile JWS kabul/red, Android test RSA, hesap nesnesi tekillik/eşzamanlılık, test modu, 8794 açıksa uçtan uca). Ekran: `pose=elmas odeme_demo=hazir [al=<paket>] profil=odeme_x` (sahte hazır mağaza, mağaza aşamasında bekler). Görüntüler build/odeme/.

## PROJEKTÖR AVI (gece avlusu) — 28 Ekim
- Kurallar: server/src/modes/projektor.js. Aşamalar anons 28 sn (sinematik açılış), sayim 12 sn (ışıklar kapalı, saklan), av 110 sn.
  Avlu dünya koordinatında x 23..57, z -13..13 (koridorun uzağında); GIRIS, SIPERLER (10 siper, yarıçap 1.1), ışık yolları
  (isiklar/tau/isikMerkez/aktifIsik) istemcideki projektor_ui.gd ile AYNI olmalı (değiştirirsen ikisini birlikte değiştir).
  Yakalanma sunucuda: Room "konum" mesajında onKonum (ışıkta ilk görülüş "isikta", 350 ms sonra hâlâ ışıktaysa "yakalandi";
  sunucu yarıçapı 2.1, çizilen 2.4). Arama: 14. sn'den itibaren 14->8 sn arayla 2-3 siper (yarısı dolu olanlardan), 5 sn uyarı.
  Botlar sunucuda siperden sipere koşar ("bot_kos"); yolda ışığa denk gelen yakalanır. Puan: yakalanan -1, süre sonunda hayatta +2, tek kalan +3.
- Sürüm kapısı: istemci odaya `sv=2` (net.gd OYUN_SURUMU) yollar; mod `surum = 2` -> odada sv'si küçük biri varsa oyun seçilmez
  (lobide seçilse bile). Eski App Store/Play sürümleri bu yüzden bozulmaz. Yeni mini oyun eklerken: OYUN_SURUMU'nu ve modun surum'unu artır.
- İstemci: scripts/modlar/projektor_ui.gd. Avlu koddan + Poly Haven CC0 modeller (sandık, varil, bariyer, tank, çöp, lastik, kapı,
  projektör, sokak lambası); 4 kule (koddan), dikenli tel (çoklu örnek), gece ortamı (env değerleri geri alınır), ay.
  Giriş: gardiyan (model_body, gardiyan üniforması + kep + cop) koridorda kapılara vurur (parmaklik_*), "uyanin", kahkaha (gulus + "gul" hareketi),
  12.8 sn kapılar, 14 sn HİZAYA (sarı çizgi + ▼), 20 sn çizgide olmayana cop (jop + "hizaya_dedim" + kırmızı flaş, çizgiye ışınlanır),
  22 sn karartma -> sinematik (avlu kapısı açılır, herkes sırayla yürür; arayüz gizlenir, sonra yalnız gizlenenler açılır).
- Sesler: tools/projektor_ses_uret.sh (Freesound CC0, kaynak listesi tools/projektor_ses_kaynak.txt) -> assets/ses/projektor/;
  gardiyan replikleri tools/gardiyan_ses_uret.mjs (OpenAI TTS "onyx") -> assets/ses/gardiyan/ ve gardiyan_en/.
- Testler: `node test/projektor_test.mjs` (39 birim), `SRV=ws://127.0.0.1:8798 node test/projektor_uctan_test.mjs` (9 uçtan uca).
  Ekran: `pose=oyunici oyun=projektor ekran=giris|sayim|av|arama|yakalandi [t=<av sn>] [yer=<siper>] [ust=1]` (build/projektor/).

## BÜYÜK KAÇIŞ (maçın son oyunu) — 28 Ekim
- Kurallar: server/src/modes/kacis.js (`final: true` -> macListesi onu hep sona koyar; `surum = 3`, istemci OYUN_SURUMU = 3).
  Aşamalar anons 14 sn, kacis 420 sn. Her hücrede 10 gizli yer (YERLER), her insana çakı + kaşık, havuzda tahta/bant/pil/ampul/tel/catal.
  Tarifler: kürek = kaşık+tahta+bant, fener = pil+ampul+tel, maymuncuk = tel+çatal. Klozet: 4 vida (çakı) -> kenara çek -> kuyu.
  Yer altı 1 m'lik ızgara (x, z = floor): KLOZET [1.5, -2.54] hücre yerelinde; TEMEL_X = -9 beton (geçit: 2 eski ızgara -> maymuncuk,
  1 gevşek tuğla -> kürek, z'leri hücre hizasında, ipucu oyuncuya özel); kayalar (~70) kazılmaz; CIT_X = -19 ötesinde 3 kez yukarı kaz = kaçış.
  Sayım: ilk uyarı 45. sn, sonra 55-75 sn arayla; 30 sn uyarı. Hücrende değilsen (kuklan yoksa) ya da klozet açıksa: aletler gider (çakı+kaşık kalır), vidalar
  geri, 12 sn ceza. Puan sırası PUAN [12,9,7,5,4,3,2,2], kaçamayan 0. Botlar %70 olasılıkla 150-390 sn arası "kaçar".
  Sabitler (HUCRE_ARA, KLOZET, TEMEL_X, CIT_X, YUKARI, SURE) istemcideki kacis_ui.gd ile AYNI olmalı.
- İstemci: scripts/modlar/kacis_ui.gd. Tüneller kazılan karelerden SurfaceTool ile tek ağ (malzeme başına yüzey, oyuk gürültü) +
  ConcavePolygon çarpışma; duvar türü komşu kareye göre (toprak/kaya/temel/tuğla/ızgara çubukları); her 3 karede ahşap destek.
  Çakmak (kameraya bağlı turuncu ışık), fener varsa beyaz spot; yorgunluk (kazınca düşer, kenarlar kararır, nefes sesi), BATI pusulası.
  cell.gd: klozet hep KLOZET_POS'ta (klozet_world, klozet_vida(n), klozet_ac(acik, anim)). main.gd: mod.sadece_kendi() yer altında
  koltuk/kapı/telefon hedeflerini kapatır; konumda `h` (yükseklik) gider, uzak oyuncu yer altında görünür.
  Kaçış sahnesi: orman zemini, tel örgü, hapishane duvarı + lambalar + dönen projektör, ağaçlar, ay; mahkûm ormana koşar; sonra izleyici.
- Sesler: tools/kacis_ses_uret.sh (Freesound CC0) -> assets/ses/kacis/; gardiyan: kacis_basla, sayim_geliyor, sayim_tamam,
  sayim_yakaladim, kacak_var. Dokular (Poly Haven CC0): excavated_soil_wall, dirt_floor, rock_wall_08, broken_brick_wall,
  weathered_planks, forest_ground_04 (VRAM sıkıştırmalı). Rozet: assets/ui/uretim/oyun_kacis.png.
  Kukla: kendi hücrende yatağa yatırılır ({kukla:true}); tüneldeyken klozet alttan kapatılırsa (klozet:false, vidalar sökük kalır) sayımda
  gardiyan %75 kanar (KUKLA_FARK 0.25, testte K.sans.r). Fener yapılınca herkese "fener" listesi gider: uzak oyuncunun kafasında lamba.
  İstemci: bulunan eşya yerinden ele uçar, sonra envantere; kazarken kaşık/kürek, vidada çakı elde (önde çizilir); 4 vida tek tek
  döne döne çıkar ve yere düşer (cell.klozet_vida_sok); bildirimler küçük kutu (_bildir), büyük flaş yok.
- Testler: `node test/kacis_test.mjs` (66 birim), `SRV=ws://127.0.0.1:8798 node test/kacis_uctan_test.mjs` (17). Ekran: `pose=oyunici oyun=kacis
  ekran=hucre|defter|klozet|tunel|kaz|kacis|sayim|vida|esya|kukla|kazi_el` (build/kacis/). Nasıl kaçılır videosu: `ekran=gosterim cik=1`
  + `--write-movie build/kacis/gosterim.avi --fixed-fps 25` (sunucusuz, olayları kendisi üretir).
