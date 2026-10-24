# Hat Düştü — devir notu (otomatik oturumlar için)

Kullanıcı uyuyor. Soru sorma, kendin karar ver. Her iş bitince bu dosyadaki listeyi güncelle (yapılanı [x] yap).
Proje belleği: C:\Users\MUSTAFA\.claude\projects\C--dev-mivo\memory\hat-dustu-project.md

## Nasıl çalışılır
- Godot: D:\Godot\Godot_v4.7.2-stable_win64_console.exe
- İçe aktarma: `--headless --import` (D:\HatDustu içinde). Yeni font eklerken project.godot'daki custom_font önce yoksa çöker.
- Ekran görüntüsü testi: `--path D:/HatDustu --resolution 1600x900 -- shot=<png> pose=menu|cell|corridor|karakter cat=<kat>|ayarlar|arkadas|emote` (main.gd `_handle_cmdline`).
- Karakter kadrosu resmi: `--path . --resolution 1800x700 --script res://tools/kadro.gd -- cikti=<png>`
- Çok düzenlemeli yamalar: Node.js betikleri (Python yok).
- GDScript'te `:=` ile Variant çıkarımı hatası sık çıkar → açık tip yaz.
- Sunucu: server/ (Cloudflare Worker, `npx wrangler deploy`), wss://hat-dustu.hatdustu.workers.dev
- iPhone: `git push` (main) → GitHub Actions "iPhone surumu" ~2-3 dk → `gh run download <id> -D D:/HatDustu/build/yeni` → HatDustu.ipa
- Her anlamlı adımda yerel commit at (Türkçe mesaj, sonuna `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

## Yarım kalan iş (öncelik sırası)
- [ ] Kıyafetler: shader ile yapılan 6 kıyafet (atlet, tisort, esofman, gardiyan, revir, askeri) KÖTÜ bulundu → catalog.gd + model_body.gd'den kaldır.
      Yerine hazır Mixamo karakterleri indirildi: assets/karakterler/{mahkum_b, remy, james, brian, big_vegas, kate, megan, sophie, jennifer, claire}.fbx (aynı mixamorig iskeleti, animasyonlar uyar).
      Yapılacak: mağazaya "Karakter/Beden" kategorisi (kadın karakterler + farklı vücut tipleri). model_body.gd'de MODEL'i look.model'e göre seç;
      orijinal mahkum.fbx'te shader boyamaları kalsın, diğerlerinde kendi malzemeleri (StandardMaterial) kullanılsın, ten rengi albedo ile hafifçe çarpılabilir.
      Kendi saçı olan karakterlerde bizim saç modelini takma (ya da seçeneğe bağla). Hair.fit_head'in _rmap'i statik → modele göre yeniden ölçülmeli.
      Dokular 50 MB'a kadar, telefon için *.png.import içinde `process/size_limit=1024` yap.
      Kadın karakterlerde Hair.MH_HEAD ölçüleri farklı; saç oturmasını kadro resmiyle kontrol et.
      Kullanışsız/çirkin olanı (ör. remy çok büyük ölçekliyse ölçekle) eleyebilirsin.
      İLK BULGULAR (kadro.gd resmi, 06:40): hepsi içe aktarıldı (kemik: mahkum_b 47, çoğu 65, big_vegas 86, claire 87).
        * durma animasyonu bu modellere UYGULANMADI (hepsi T-pozda kaldı) → anim izlerinin yolu (Skeleton3D:mixamorig_X) ile
          modellerin AnimationPlayer root_node / iskelet yolu ya da kemik adları eşleşmiyor olabilir; tools/iz.gd ile incele
          (o betik takıldı, --headless yerine pencereli çalıştırmayı dene). Gerekirse izlerin yolunu modele göre yeniden yaz.
        * remy ~2 kat büyük (ölçek 0.5 ver). claire ve big_vegas çizgi film tarzı → claire'i çıkar, big_vegas "iri beden" olarak kalabilir.
        * Kadın: kate, megan, sophie, jennifer. Erkek: mahkum_b (çizgili mahkum), james, brian, remy.
- [ ] Sakal: sadece "keçi" iyi; diğer sakal/bıyıklar bozuk → düzelt + daha çok çeşit.
- [ ] Aksesuar: en az 20 çeşit, yüze oturan (şapkalar, bereler, gözlükler, yara izi, dövme, bandana, kulaklık, zincir...). Yeni kategoriler: Şapka, Dövme/Yara.
- [ ] Yazılı sohbet (oda içi, sunucuda "sohbet" mesajı) + kopunca yeniden bağlanma (reconnect).
- [ ] Telefon kaplamaları (hücredeki telefonun rengi/kaplaması) ve hücre süsleri mağazadan alınır, diğer oyunculara senkron.
- [ ] Hücrede gerçek yansımalı ayna (SubViewport/ReflectionProbe; mobilde ucuz olsun).
- [ ] Odalara daha gerçekçi eşya (Poly Haven CC0 modelleri).

## Sonra: Scam Line mini oyunları
Scam Line (Steam) içindeki mini oyunları/etkinlikleri web'de araştır, benzerlerini KENDİ isim ve tasarımımızla yap
(kopya değil). Oyunu akıcı, cilalı hale getir (FPS, geçişler, sesler, dokunmatik kontroller).

## Teslim
Saat 12:00–13:00 arası (Türkiye saati) iPhone .ipa dosyası hazır olsun ve kullanıcıya gönderilsin.

## Not: assets/karakterler/ git'e girmiyor (.gitignore)
Dosyalar ~400 MB, GitHub gönderimi koptu. Karakterler oyuna bağlanınca: kullanılacakları seç, dokuları 1024px'e küçültüp
(PNG'leri yeniden kaydet) ayrı küçük bir klasöre (ör. assets/karakter2/) koy ve onu commit'le; export_presets.cfg'deki
exclude_filter'dan "assets/karakterler/*" çıkarılmasın, yeni klasör dahil olsun. Tek dosya 50 MB'ı geçmesin.
