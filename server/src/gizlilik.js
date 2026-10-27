// Mağazaların istediği gizlilik politikası ve kullanım koşulları (Türkçe + İngilizce).
// Sunucuda /gizlilik ve /kosullar adreslerinde yayınlanır. İletişim e-postası ILETISIM sabitinde.

export const ILETISIM = "destek@hatdustu.app"; // destek e-postası (Cloudflare e-posta yönlendirmesiyle Gmail'e gider)
export const GUNCELLEME = "27 Ekim 2026";

export const page = (title, body) => `<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${title} — Hat Düştü</title>
<style>body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:760px;margin:0 auto;padding:24px 18px 64px;
background:#111317;color:#e9e6df;line-height:1.6}h1{color:#ffb020;font-size:28px}h2{color:#ffcf8a;font-size:20px;margin-top:28px}
a{color:#7fe3ff}hr{border:0;border-top:1px solid #333;margin:40px 0}small{color:#999}</style></head><body>${body}</body></html>`;

export function privacyHtml() {
  return page("Gizlilik Politikası", `
<h1>Hat Düştü — Gizlilik Politikası</h1><small>Son güncelleme: ${GUNCELLEME}</small>
<p>Hat Düştü (“oyun”), arkadaşlarınla sesli oynanan çok oyunculu bir parti oyunudur. Bu metin hangi verileri neden işlediğimizi anlatır.</p>
<h2>Topladığımız veriler</h2>
<ul>
<li><b>Hesap bilgileri:</b> seçtiğin kullanıcı adı (oyunda adın olarak görünür), e-posta adresin ve şifren (şifre geri döndürülemez biçimde, tuzlanmış özet olarak saklanır). Oynamak için hesap gerekir; cihazında hesabına bağlı rastgele bir oturum anahtarı saklanır.</li>
<li><b>E-posta adresi:</b> yalnızca hesap kurtarma (şifre sıfırlama kodu), e-posta doğrulama, güvenlik bildirimleri (şifren değiştiğinde, hesabın silindiğinde) ve bir kez hoş geldin e-postası için kullanılır. E-posta adresin başka oyunculara, liderlik tablosuna ya da oda mesajlarına hiçbir zaman gösterilmez; pazarlama için kullanılmaz ve satılmaz. Doğrulama ve sıfırlama kodları sunucuda yalnızca geri döndürülemez özet olarak, en fazla 30 dakika saklanır. Şifre e-postalarında isteğin yaklaşık konumu (şehir, ülke) ve cihaz adı gösterilir; bunlar saklanmaz.</li>
<li><b>Oyun verileri:</b> karakter görünüşün, elmas bakiyen, sahip olduğun eşyalar, seviye/deneyim puanın, görev ve başarım ilerlemen, maç istatistiklerin, haftalık liderlik puanın.</li>
<li><b>Arkadaşlık verileri:</b> arkadaş listen, gönderdiğin/aldığın istekler, engellediğin oyuncular.</li>
<li><b>Ses:</b> oyunda telefonla konuşurken sesin, gerçek zamanlı olarak yalnızca konuştuğun oyuncuya iletilir. Ses <b>kaydedilmez ve saklanmaz</b>.</li>
<li><b>Şikayetler:</b> bir oyuncuyu şikayet ettiğinde şikayet nedeni, oda kodu ve isteğe bağlı notun moderasyon için saklanır.</li>
<li><b>Teknik veriler:</b> oyunun düzgün çalışması için bağlantı bilgileri ve hata/çökme raporları (cihaz modeli, işletim sistemi sürümü, hata kaydı) toplanabilir.</li>
</ul>
<h2>Verileri neden kullanıyoruz</h2>
<p>Oyunu oynatmak, hesabını ve ilerlemeni korumak, arkadaşlarınla eşleştirmek, satın aldıklarını sana teslim etmek, hile ve kötüye kullanımı önlemek, hataları düzeltmek için.</p>
<h2>Uygulama içi satın almalar ve reklamlar</h2>
<p>Satın almalar Apple App Store ya da Google Play üzerinden yapılır; ödeme bilgilerini biz görmeyiz. Ödüllü reklam izlemeyi seçersen reklam sağlayıcısı (Google AdMob) cihazının reklam kimliğini kendi gizlilik politikasına göre işleyebilir.</p>
<h2>Paylaşım</h2>
<p>Verilerini satmayız. Sunucularımız ve e-posta gönderimimiz Cloudflare altyapısında çalışır. Yasal zorunluluk dışında üçüncü kişilerle paylaşmayız.</p>
<h2>Saklama ve silme</h2>
<p>Hesabını oyunun <b>Ayarlar → Hesap → Hesabı sil</b> bölümünden ya da oyun yüklü değilse <a href="/hesap-sil">hesap silme sayfasından</a> istediğin an silebilirsin; kullanıcı adın, e-posta adresin, şifren, profilin, elmasların, eşyaların, arkadaşlıkların ve ilerlemen hemen ve kalıcı olarak silinir (silindiğini bildiren son bir e-posta gönderilir). Hesabından koparılarak bir süre saklananlar: satın alma kayıtları 5 yıl (iade ve yasal yükümlülükler), şikayet kayıtları 1 yıl (kötüye kullanımı önleme), hata raporları 30 gün. Sesli konuşmalar hiç saklanmaz.</p>
<h2>Çocuklar</h2>
<p>Oyun 13 yaşın altındaki çocuklara yönelik değildir ve bilerek bu yaştakilerden veri toplamayız.</p>
<h2>Haklarınız (KVKK / GDPR)</h2>
<p>Verilerine erişme, düzeltme, silme ve işlenmesine itiraz etme hakkın vardır. Bunun için bize yazabilirsin: <a href="mailto:${ILETISIM}">${ILETISIM}</a></p>
<hr>
<h1 id="en">Hat Düştü — Privacy Policy</h1><small>Last updated: ${GUNCELLEME}</small>
<p>Hat Düştü is a multiplayer voice party game. We collect: account data (username, which is also your in-game name; email address; salted password hash; a random session key stored on your device — an account is required to play), game data (appearance, gems, items, level/XP, missions, achievements, match stats, weekly leaderboard score), friends and blocks, and reports you submit. In-game voice is relayed in real time only to the player you are talking to and is <b>never recorded or stored</b>. Your email address is used only for account recovery (password reset codes), email verification, security notices (password changed, account deleted) and a one-time welcome email. It is never shown to other players, on leaderboards or in room messages, never used for marketing and never sold. Verification and reset codes are stored only as one-way hashes for at most 30 minutes. Password emails show the approximate location (city, country) and device name of the request; these are not stored. Emails are sent through Cloudflare. Crash/diagnostic data may be collected to fix bugs. Purchases are processed by Apple/Google; we never see payment details. If you choose to watch rewarded ads, Google AdMob may process your advertising ID. We do not sell your data. You can delete your account at any time in <b>Settings → Account → Delete account</b>, or on our <a href="/hesap-sil#en">account deletion page</a> even if the game is no longer installed. Your username, email address, profile, progress, gems, items and friends are deleted immediately (we send one last email confirming the deletion); purchase records (5 years), reports (1 year) and error reports (30 days) are kept unlinked from your account for that time, then deleted. The game is not directed to children under 13. Contact: <a href="mailto:${ILETISIM}">${ILETISIM}</a></p>`);
}

export function termsHtml() {
  return page("Kullanım Koşulları", `
<h1>Hat Düştü — Kullanım Koşulları</h1><small>Son güncelleme: ${GUNCELLEME}</small>
<p>Oyunu kullanarak bu koşulları kabul edersin.</p>
<h2>Davranış</h2><p>Küfür, taciz, nefret söylemi, hile ve başka oyuncuların deneyimini bozan davranışlar yasaktır. Bu tür davranışlar hesabının kısıtlanmasına ya da kapatılmasına yol açabilir. Rahatsız olduğun oyuncuyu oyun içinden şikayet edebilir ve engelleyebilirsin.</p>
<h2>Sanal eşyalar</h2><p>Elmaslar ve eşyalar yalnızca oyun içinde kullanılabilir, gerçek paraya çevrilemez ve devredilemez. Satın almalarda iade, Apple/Google'ın iade kuralları çerçevesinde yapılır.</p>
<h2>Hizmet</h2><p>Oyunu geliştirmek için içeriği değiştirebilir, bakım için hizmete ara verebiliriz.</p>
<h2>İletişim</h2><p><a href="mailto:${ILETISIM}">${ILETISIM}</a></p>
<hr><h1 id="en">Terms of Use</h1><p>By playing you agree to behave respectfully (no abuse, harassment, hate speech or cheating), that virtual items have no cash value and are non-transferable, that refunds follow Apple/Google policies, and that we may change or pause the service. Contact: <a href="mailto:${ILETISIM}">${ILETISIM}</a></p>`);
}
