# Hat Düştü — Mağazaya göndermeden önce kontrol listesi

Bu liste kod bilmeyen biri için yazıldı. Her maddeyi sırayla yap, bitince yanına ✔ koy.
"Claude'a söyle" yazan maddeler kodla ilgili; bunları kendin yapmana gerek yok, Claude'dan iste.

Hazır dosyalar bu klasörde:
- `metinler_tr.md` / `metinler_en.md` — mağaza yazıları, yaş anketi ve gizlilik formu cevapları
- `ekranlar/tr/...` ve `ekranlar/en/...` — ekran görüntüleri (Play: 8 adet 1920x1080; App Store iPhone: 9 adet 2796x1290; App Store iPad: 9 adet 2732x2048)
- `play/one_cikan_gorsel_tr_1024x500.png` (ve `_en_`) — Play öne çıkan görsel
- `ikonlar/play_ikon_512.png` — Play mağaza ikonu
- `ikonlar/appstore_ikon_1024.png` — App Store ikonu (saydamlık yok)

---

## A. Önce bitmesi gereken engeller (bunlar olmadan mağaza reddeder)

1. **Ödeme test modunu kapat** — sunucuyu canlıya yüklemeden önce Claude'a söyle.
   Şu an `server/wrangler.toml` içinde `ODEME_TEST = "1"`: bu açıkken elmas paketleri PARA ALINMADAN veriliyor ve mağazada "TEST MODU" yazıyor. Canlıya yüklemeden önce bu satır `"0"` olmalı. (`server/src/ekonomi.js` içindeki `TEST_ODEME` artık `false`; test modu yalnızca bu ayarla açılır.)
   - `"0"` iken oyun hazır: elmas paketleri **"YAKINDA"** görünür, dokununca "Elmas paketleri çok yakında satışta!" penceresi açılır, hiçbir koşulda bedava elmas verilmez (yerelde denendi). İlk sürüm böylece satın almasız çıkabilir.
   - Gerçek satın alma için sonra: oyuna mağaza ödemesi (Godot IAP eklentisi) + sunucuda makbuz doğrulaması — Claude'a söyle. O zamana kadar uygulama içi ürünleri (bölüm C) sürüme eklemene gerek yok.

2. **Destek e-postası** — Bir e-posta adresi seç (ör. hatdustu.destek@gmail.com) ve Claude'a söyle.
   Gizlilik politikasındaki destek e-postası: `destek@hatdustu.app` (yazıldı). Aynı adresi iki mağazada "destek e-postası" olarak gir. Web sitesi: https://hatdustu.app

3. **Sunucuyu canlıya yüklemek** — Claude'a "sunucuyu canlıya yükle" de (senin onayın gerekiyor).
   Canlıdaki sunucu eski sürüm. Gizlilik sayfası ancak yükleme sonrası çalışır:
   - Gizlilik politikası adresi: `https://hat-dustu.hatdustu.workers.dev/gizlilik` (İngilizcesi: `/privacy`)
   - Kullanım koşulları: `https://hat-dustu.hatdustu.workers.dev/kosullar` (İngilizcesi: `/terms`)
   - Yükledikten sonra bu adresleri telefonundan açıp kontrol et.

4. **Hesap silme web sayfası (Google Play istiyor)** — HAZIR ✔ (sunucu canlıya yüklenince çalışır).
   Adres: **`https://hat-dustu.hatdustu.workers.dev/hesap-sil`** (İngilizcesi aynı sayfanın altında; `/delete-account` de açılır).
   - Kullanıcı adı + şifre + "kalıcı silmeyi anlıyorum" kutusuyla hesap silinir. Deneme sınırı var: aynı kullanıcı adına 8 yanlış şifre ya da aynı yerden 10 deneme → 15 dakika kilit.
   - Sayfa silinenleri ve saklananları süreleriyle yazar: satın alma kayıtları 5 yıl, şikayetler 1 yıl, hata raporları 30 gün (hesaptan koparılarak).
   - Gizlilik sayfasından ve oyunda **Ayarlar → Hesap → Hesap silme sayfası**ndan bağlantı var.
   - Bu adresi Play Console → **Veri güvenliği → Veri silme** bölümüne yaz. Yükledikten sonra telefondan açıp bir deneme hesabıyla dene.
   - Sayfada destek e-postası `destek@hatdustu.app` olarak yazıyor.

5. **Sürüm numarası** — HAZIR ✔ `1.0.0` (Android sürüm kodu 1, iOS derleme 1).
   Oyun içindeki sürüm tek yerden okunur: `project.godot` → `application/config/version` (Ayarlar ekranı ve hata raporu buradan alır). Yeni sürümde bunu, `export_presets.cfg` içindeki sürüm adlarını ve sürüm kodlarını (Android `version/code`, iOS `application/version`) birlikte artır; her mağaza yüklemesinde kod bir öncekinden büyük olmalı. Claude'a "sürümü 1.0.1 yap" demen yeter.

6. **İngilizce arayüz** — Karar ver.
   Oyunun içi şimdilik yalnızca Türkçe. İngilizce mağaza sayfasını, oyun İngilizceye çevrilene kadar yayınlama (ya da açıklamaya "Şimdilik yalnızca Türkçe" yaz). İlk sürümde mağaza dili olarak yalnızca **Türkçe** seçmen en güvenlisi.

---

## B. Hesaplar

7. **Google Play Console hesabı** — play.google.com/console, tek seferlik 25 dolar.
   - Kimlik doğrulaması birkaç gün sürebilir.
   - **Önemli:** Yeni bireysel hesaplarda Google, yayından önce **en az 12 test kullanıcısıyla 14 gün kapalı test** istiyor. Arkadaşlarından 12 Gmail adresi topla, önce "Kapalı test" yayınla, 14 gün oynasınlar, sonra "Üretim" için başvur. (Şirket hesabında bu şart yok.)

8. **Apple Developer Program** — developer.apple.com, yıllık 99 dolar.
   - Ekip kimliği (Team ID) zaten ayarlı: `TW6N7YSG4D`. Hesabın bu ekipte olduğunu kontrol et.
   - App Store Connect'te yeni uygulama aç: Paket kimliği (Bundle ID) **`com.sormatch.hatdustu`**, ana dil **Türkçe**, SKU: `hatdustu001`.

9. **Ödeme ve vergi bilgileri** — İki konsolda da "Ödeme profili / Agreements, Tax, and Banking" bölümünü doldur. Uygulama içi satış yapmak için bu zorunlu (banka hesabı ve vergi formu).

---

## C. Uygulama içi ürünler (ürün kimlikleri)

10. İki mağazada da aşağıdaki ürünleri **aynı kimliklerle** oluştur. Tür: **Tüketilebilir (Consumable)** — Google'da "Uygulama içi ürün / Tek seferlik ürün".

| Ürün kimliği | Ad | Elmas | Fiyat (TL) |
|---|---|---|---|
| `baslangic` | Başlangıç Paketi (+1 nadir kasa, hesap başına bir kez) | 300 | 49,99 |
| `elmas_100` | 100 Elmas | 100 | 29,99 |
| `elmas_550` | 550 Elmas (+50 hediye) | 550 | 149,99 |
| `elmas_1200` | 1.200 Elmas | 1.200 | 299,99 |
| `elmas_2500` | 2.500 Elmas | 2.500 | 599,99 |
| `elmas_6500` | 6.500 Elmas | 6.500 | 1.499,99 |

- Mağazaların fiyat basamakları tam bu rakamları vermeyebilir; en yakın basamağı seç ve oyundaki fiyatı Claude'a güncellet (oyun ile mağaza aynı fiyatı göstermeli).
- Apple her ürün için bir ekran görüntüsü ister: `ekranlar/tr/appstore_iphone_6.9/` dışında oyunun elmas mağazası ekranını kullanabilirsin (test modu yazısı kalktıktan sonra çek).

---

## D. Derleme ve imzalama

11. **Android (Google Play)** — ayarlar HAZIR, derleme senin onayınla.
   - Google Play **.apk değil .aab** istiyor. Bunun için yeni bir dışa aktarma ön ayarı eklendi: **"Android Play"** (`export_presets.cfg`: Gradle ile derleme açık `gradle_build/use_gradle_build=true`, AAB çıktısı `gradle_build/export_format=1`, dosya `build/android/HatDustu.aab`). Telefona doğrudan kurduğun eski **"Android"** (APK) ön ayarı aynen duruyor.
   - Gradle ile derleme, Godot'un **Android derleme şablonunu** ister (düzenleyicide "Proje → Android Derleme Şablonunu Yükle"). Bunu bilgisayarında yapmana gerek yok: yeni GitHub iş akışı **"Android Play surumu (AAB)"** (`.github/workflows/android_play.yml`) şablonu her derlemede kendisi kurar ve Gradle belleğini 3 GB ile sınırlar. Henüz hiç çalıştırılmadı.
   - Senin yapacakların:
     1. **Yükleme anahtarı (upload keystore)** oluştur (Claude komutu verir). Dosyayı ve şifresini en az iki yerde yedekle — kaybedersen güncelleme yükleyemezsin.
     2. GitHub → Settings → Secrets and variables → Actions'a üç sır ekle: `PLAY_KEYSTORE_BASE64` (anahtar dosyasının base64 hâli), `PLAY_KEYSTORE_ALIAS`, `PLAY_KEYSTORE_PASSWORD`.
     3. GitHub → Actions → "Android Play surumu (AAB)" → Run workflow. Çıkan `HatDustu-Play-AAB` dosyasını Play Console'a yükle; Play Console'da "Play Uygulama İmzalama"yı aç.
   - Şablonu kendi bilgisayarında kurarsan (`android/` klasörü oluşur, git'e girmez): `android/build/gradle.properties` içindeki `org.gradle.jvmargs` değerini `-Xmx3g` yap (bilgisayarın 8 GB; şablonun varsayılanı daha yüksek).
   - Hedef Android sürümü (target SDK) boş = Godot 4.7.2'nin varsayılanı. Play Console yüklemede "hedef API düzeyi düşük" derse Claude'a söyle: `gradle_build/target_sdk` 36 yapılır.

12. **iPhone (App Store)** — Claude'a söyle.
   - Şu an Sideloadly ile deneme kurulumu yapıyorsun; mağaza için **"App Store dağıtım sertifikası" + "App Store provisioning profile"** gerekiyor. GitHub Actions derlemesi bunlarla imzalayıp App Store Connect'e (TestFlight) yüklemeli.
   - Ayarlarda uygulama **iPhone + iPad** için işaretli. Bu yüzden iPad ekran görüntüleri de hazırlandı (`appstore_ipad_13`). iPad'i istemiyorsan Claude'a "yalnızca iPhone yap" de; o zaman iPad görüntülerini yüklemene gerek kalmaz.
   - İhracat uyumluluğu (Export Compliance) sorusu: oyun yalnızca standart HTTPS/WSS şifrelemesi kullanıyor → **"Muaf (exempt)"**, yani "Standart dışı şifreleme kullanıyor musunuz?" sorusuna **Hayır**.
   - Önce TestFlight'ta kendin ve birkaç arkadaşınla dene.

---

## E. Mağaza sayfasını doldurma

13. **Google Play Console**
   - Uygulama adı, kısa açıklama, uzun açıklama: `metinler_tr.md` bölüm 1, 3, 4.
   - Uygulama simgesi: `ikonlar/play_ikon_512.png`
   - Öne çıkan görsel: `play/one_cikan_gorsel_tr_1024x500.png`
   - Telefon ekran görüntüleri: `ekranlar/tr/play/` içindeki 8 dosya, numara sırasıyla. (Google'ın kuralı: uzun kenar kısa kenarın 2 katını geçemez; bu yüzden Play için 1920x1080 hazırlandı, 2400x1080 kullanılmadı.)
   - Tablet ekran görüntüleri isteğe bağlı; istersen `ekranlar/tr/appstore_ipad_13/` dosyalarını 7 ve 10 inç tablet alanına yükleyebilirsin.
   - Kategori: **Oyun → Parti**. Etiketler: Çok oyunculu, Sosyal.
   - İletişim: destek e-postası (madde 2). Web sitesi isteğe bağlı.
   - Gizlilik politikası: madde 3'teki adres.
   - **Uygulama içeriği** bölümü:
     - Reklam içeriyor mu: **Hayır** (reklam eklenirse değiştir)
     - Uygulama erişimi: "Bazı özellikler giriş gerektirir" → test hesabı bilgisi ver (madde 15) ya da "misafir olarak tüm özellikler açık" de.
     - İçerik derecelendirmesi: `metinler_tr.md` bölüm 8a.
     - Hedef kitle: **13-15, 16-17, 18 ve üzeri**. "Çocuklara hitap ediyor mu" → Hayır. (13 yaş altını seçme; gizlilik politikası 13 yaş altını kapsamıyor.)
     - Veri güvenliği: `metinler_tr.md` bölüm 9a.
     - Haber uygulaması / Sağlık / Finans / Devlet uygulaması: Hayır.
   - Fiyat: **Ücretsiz**. Ülkeler: önce Türkiye (+ istersen Azerbaycan, Kıbrıs, Almanya vb.).

14. **App Store Connect**
   - Ad, alt başlık, açıklama, anahtar kelimeler, yenilikler: `metinler_tr.md` bölüm 1, 2, 4, 5, 6.
   - Destek adresi (Support URL) zorunlu: gizlilik sayfası adresini ya da basit bir destek sayfasını yaz.
   - Ekran görüntüleri: iPhone 6,9" alanına `ekranlar/tr/appstore_iphone_6.9/` (9 dosya), iPad 13" alanına `ekranlar/tr/appstore_ipad_13/` (9 dosya).
   - Uygulama simgesi derlemenin içinden gelir; `ikonlar/appstore_ikon_1024.png` aynısıdır, gerekirse kullan.
   - Kategori: **Oyunlar → Parti**, ikinci kategori **Strateji**.
   - Yaş derecelendirmesi: `metinler_tr.md` bölüm 8b.
   - App Privacy (Uygulama Gizliliği): `metinler_tr.md` bölüm 9b. Gizlilik politikası adresini gir.
   - Fiyat: Ücretsiz. Uygulama içi ürünleri (madde 10) sürüme ekle.

15. **İnceleme ekibi için not (App Review / Uygulama erişimi)** — İnceleyen kişi tek başına oynar, bu yüzden şunu yaz:
   ```
   Hat Düştü çok oyunculu sesli bir parti oyunudur. Tek başına denemek için ana menüde OYNA → HIZLI OYUN'a dokunun; 25 saniye içinde boş yerleri botlar doldurur ve maç başlar.
   Hesap açmadan misafir olarak oynanabilir. Hesap silme: Ayarlar → Hesap → Hesabı sil.
   Sesli sohbet yalnızca oyuncular arasında canlı aktarılır, kaydedilmez. Oyuncular birbirini oyun içinden şikayet edip engelleyebilir.
   Test hesabı: kullanıcı adı ...... / şifre ......
   ```
   Test hesabını oyunda kendin aç (gerçek şifreni kullanma, sadece bu iş için yeni bir şifre) ve kullanıcı adı/şifreyi buraya yaz.

---

## F. Kullanıcı içeriği kuralları (Apple 1.2 / Google UGC)

16. Oyunda canlı sesli sohbet ve kullanıcı adları olduğu için mağazalar şunları arar — hepsinin oyunda çalıştığını kendin dene:
   - Oyuncuyu **şikayet etme** (var) ✔
   - Oyuncuyu **engelleme** (var) ✔
   - Kullanım koşullarında küfür/taciz yasağı (var, `/kosullar`) ✔
   - **Uygunsuz ad ve kelime süzgeci** (var) ✔ — Türkçe + İngilizce küfür süzgeci sunucuda: kullanıcı adı, görünen ad ve Kara Tahta kelimeleri. Uygunsuz ad "Bu ad kullanılamaz" ile reddedilir, tahtaya yazılan uygunsuz kelime diğer oyunculara "***" gider. Kelime listesi `server/src/suzgec_liste.js` (kelime eklemek için Claude'a söyle).
   - **Topluluk kuralları onayı** (var) ✔ — ilk açılışta bir kez çıkar; kabul edilmeden çevrimiçi oynanmaz.
   - **Maçta şikayet ve engelleme** (var) ✔ — oyuncu kartından ŞİKAYET ET / ENGELLE; misafir oyuncu da engellenebilir. Engellenen kişi sana istek ya da davet gönderemez, Hızlı Oyun'da seninle aynı odaya düşmez, maçta sesi sana (seninki de ona) hiç iletilmez. Engeller Ayarlar → Hesap → Engellenen oyuncular bölümünden kaldırılır.
   - **Yönetim sayfası** (var) ✔ — `https://hat-dustu.hatdustu.workers.dev/yonetim`: bekleyen şikayetler (tarih, şikayet eden, şikayet edilen, sebep, oda, maçtaki ad, toplam şikayet sayısı), hesap arama ve işlemler: Uyar, 24 saat / 7 gün / kalıcı yasak, yasağı kaldır, adı sıfırla ("OyuncuNNNN"), şikayeti kapat. Yasaklı hesap giriş yapamaz ve odaya giremez (misafirse cihaz anahtarı yasaklanır); oyunda "Hesabın ... tarihine kadar askıya alındı." yazar.
   - **Yönetim anahtarını kendin koy (canlıya yüklemeden önce, bir kez):** `server` klasöründe komut satırına `npx wrangler secret put YONETICI_ANAHTARI` yaz, sorulunca en az 16 karakterlik uzun, tahmin edilemez bir şifre gir (şifre yöneticisinde sakla, kimseyle paylaşma). Sayfaya bu anahtarla girersin; tanımlı değilse sayfa kapalı kalır. Yerel test anahtarı `server/.dev.vars` dosyasında (git'e girmez), canlıda onu kullanma.
   - **ÖNEMLİ — şikayetlere 24 saat içinde yanıt (senin sorumluluğun):** Apple, kullanıcı içeriği olan uygulamalarda şikayetlere **24 saat içinde** bakılmasını, kötü davranan kullanıcının içeriğinin kaldırılıp hesabının kapatılmasını bekler. Her gün en az bir kez `/yonetim` sayfasını açıp bekleyen şikayetleri işle. İnceleme notuna "Reports are reviewed within 24 hours; abusive users are warned or banned" cümlesini ancak gerçekten bakacaksan yaz.

---

## G. Göndermeden hemen önce son kontrol

17. Telefonda yayın derlemesini (TestFlight / Play kapalı test) aç ve şunları dene:
   - [ ] Misafir olarak oyna, sonra hesap aç, çıkış yap, tekrar giriş yap
   - [ ] Arkadaş ekle, davet et, aynı odada oyna
   - [ ] Hızlı Oyun botlarla başlıyor
   - [ ] Mikrofon izni soruluyor, sesli konuşma çalışıyor
   - [ ] Gerçek (test) satın alma: Google'da "lisans test kullanıcısı", Apple'da "Sandbox hesabı" ile elmas al; elmas geliyor, para çekilmiyor
   - [ ] Hesabı sil çalışıyor
   - [ ] Gizlilik ve koşullar sayfaları oyunun içinden açılıyor
18. Ekran görüntülerinde "TEST MODU" ya da sahte bilgi kalmadığını kontrol et (hazırlanan görüntülerde yok).
19. Her şey tamamsa "İncelemeye gönder". Apple incelemesi genelde 1-3 gün, Google ilk incelemede 1 haftaya kadar sürebilir. Red gelirse gelen mesajı Claude'a göster.
