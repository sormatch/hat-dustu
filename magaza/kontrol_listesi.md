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

1. **Gerçek ödeme sistemi** — Claude'a söyle.
   Şu an elmas paketleri TEST MODUNDA: para alınmadan elmas veriliyor. Mağazada bu hâliyle yayınlanırsa Apple kesin reddeder (uygulama içi satın alma Apple/Google ödeme sistemiyle olmalı).
   - Oyuna gerçek mağaza ödemesi (Godot IAP eklentisi) ve sunucuda makbuz doğrulaması eklenmeli.
   - İki yerde test modu kapatılmalı: `server/wrangler.toml` içinde `ODEME_TEST = "1"` → `"0"`, ve `server/src/ekonomi.js` içinde `TEST_ODEME = true` → `false`.
   - Elmas mağazasının altındaki "TEST MODU • gerçek ödeme alınmaz" yazısı kaybolmalı.
   - Alternatif: ödeme hazır olana kadar elmas paketlerini oyundan gizleyip ilk sürümü satın almasız çıkarmak.

2. **Destek e-postası** — Bir e-posta adresi seç (ör. hatdustu.destek@gmail.com) ve Claude'a söyle.
   Gizlilik politikasında şu an `ILETISIM_EPOSTASI` yazıyor (`server/src/gizlilik.js`). Gerçek adresle değiştirilmeli. Aynı adresi iki mağazada "destek e-postası" olarak da gireceksin.

3. **Sunucuyu canlıya yüklemek** — Claude'a "sunucuyu canlıya yükle" de (senin onayın gerekiyor).
   Canlıdaki sunucu eski sürüm. Gizlilik sayfası ancak yükleme sonrası çalışır:
   - Gizlilik politikası adresi: `https://hat-dustu.hatdustu.workers.dev/gizlilik` (İngilizcesi: `/privacy`)
   - Kullanım koşulları: `https://hat-dustu.hatdustu.workers.dev/kosullar` (İngilizcesi: `/terms`)
   - Yükledikten sonra bu adresleri telefonundan açıp kontrol et.

4. **Hesap silme web sayfası (Google Play istiyor)** — Claude'a söyle.
   Oyunun içinde "Ayarlar → Hesabı sil" var (Apple için yeterli). Google ayrıca bir **web adresi** istiyor: oyunu silmiş biri de hesabının silinmesini isteyebilmeli. En kolayı: `/hesap-sil` diye kısa bir sayfa (adımlar + destek e-postası). Bu adresi Play Console → Veri güvenliği bölümüne yazacaksın.

5. **Sürüm numarası** — Claude'a söyle.
   Dışa aktarma ayarlarında sürüm `0.1`, hata raporunda `0.9.0` yazıyor. İlk yayın için hepsini `1.0.0` yap (sürüm kodu 1 kalabilir).

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

11. **Android (Google Play)** — Claude'a söyle.
   - Google Play artık **.apk değil .aab** dosyası istiyor. Godot dışa aktarmada "Gradle ile derleme" açılmalı (şu an kapalı) ve Android derleme şablonu kurulmalı.
   - Hedef Android sürümü: Play Console'un o an istediği en güncel seviye (2026 için Android 16 / API 36). Godot'un varsayılanı yetmiyorsa elle yükseltilmeli.
   - **Yükleme anahtarı (keystore)** oluştur. Dosyayı ve şifresini en az iki yerde yedekle (kaybedersen güncelleme yükleyemezsin). Play Console'da "Play Uygulama İmzalama"yı aç.

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
   - **Uygunsuz kullanıcı adlarını süzme**: Claude'a "kullanıcı adlarına küfür süzgeci var mı, yoksa ekle" de.
   - Gelen şikayetlere bakacak biri: şikayetler sunucuda kaydediliyor; bunları okuyup gerekirse hesabı kapatabileceğin basit bir yol için Claude'a danış.

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
