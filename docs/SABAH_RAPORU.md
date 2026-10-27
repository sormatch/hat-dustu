# Sabah raporu — 27 Ekim 2026

## Gece biten işler
- **Canlı sunucu:** Yeni sürüm yayında: zorunlu hesap, e-posta gönderimi, gerçek satın alma doğrulaması. Testlerin hepsi geçti.
- **iPhone:** GitHub'da yeni derleme başarılı, ödeme (StoreKit) eklentisi içinde.
  - Arkadaşlar için yeni dosya: `D:\HatDustu_IPA\yeni_27ekim\HatDustu.ipa`. Eski sürüm artık sunucuya bağlanamaz; herkes bunu Sideloadly ile kurmalı.
- **Android (Google Play):**
  - İmzalı paket (AAB) bu bilgisayarda üretildi ve Play Console'a **Dahili test** olarak yüklendi (sürüm 1.0.0).
  - 6 elmas paketi Play'de oluşturuldu ve etkin; Türkiye fiyatları App Store ile aynı: 59,99 / 39,99 / 179,99 / 349,99 / 699,99 / 1.749,99 TL.
  - Play lisans anahtarı koda eklendi; sunucuya yüklenince Android satın alımları doğrulanır.
- **Mağaza görselleri:** App Store (iPhone, iPad, IAP inceleme görselleri) ve Play (ikon, öne çıkan görsel, ekran görüntüleri) yüklü.
- **TikTok videoları:** 5 video, Türkçe ve İngilizce, toplam 10 adet: `D:\HatDustu_Reklam\TikTok\`
  1. C4 kovalamaca (15 sn)
  2. Rus Ruleti (17 sn)
  3. Kim Kim robot ses (21 sn)
  4. Yalancı (25 sn)
  5. Derleme (15 sn)

## Senin yapman gerekenler (güvenlik kuralları gereği ben yapamıyorum)
1. ~~**Sunucu güncellemesi**~~ — 27 Ekim sabah canlıya yüklendi (sürüm 23cad949). Android ödeme doğrulaması açık.
2. ~~**App Store**~~ — 27 Ekim 11:57 incelemeye gönderildi (sürüm 1.0.0 derleme 4 + 6 elmas paketi). Sonuç 48 saat içinde e-postayla gelir.
   - `ASC_KEY_ID` = `YX3N5NT5P6`
   - `ASC_ISSUER_ID` = `49c3e1a1-15f9-4233-9b84-e372f3927308`
   - `ASC_KEY_P8` = İndirilenler'deki `AuthKey_YX3N5NT5P6.p8` dosyasının tüm içeriği (Not Defteri ile aç, kopyala)

   Sonra bana yaz; derleyip App Store'a yükler ve incelemeye gönderirim.
3. ~~**İnceleme hesabı**~~ — apple_inceleme oluşturuldu, App Store Connect ve Play Console a girildi.
   - App Store Connect → App Review Information
   - Play Console → Uygulama içeriği → Uygulama erişimi
4. **Play test kullanıcıları:** Dahili teste en fazla 100 kişi eklenebilir (Play Console → Test → Dahili test → Test kullanıcıları). Herkese açık yayın için kapalı testte 12 kişinin 14 gün test yapması şart.
5. **Yedek:** `D:\HatDustu\.gizli\play_upload.keystore` ve aynı klasördeki şifre dosyasını bir yere yedekle. Kaybolursa Play'e güncelleme yüklemek zorlaşır.

## Notlar
- Rulet TikTok videosunda vurulan karakter yığılınca başı görünmüyor (12–13. saniye). İstersen düzeltirim.
- TikTok seslendirmeleri kulakla dinlenmedi; bir kez dinle.
- Android derlemesi için `D:\jdk17` (Java 17) ve `D:\gradle_home` kuruldu; Godot'un Java ayarı bu klasöre çevrildi (eski ayar `D:\tmp_gh\editor_settings-4.7.tres.yedek`).
- C: diski dolu (~0,6 GB boş). Bellek yetmezliği hatalarının sebebi bu (Windows takas dosyası C:'de). Temizlik iyi olur.
