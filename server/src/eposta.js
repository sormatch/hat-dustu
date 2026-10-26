// Hat Düştü e-posta şablonları (TR / EN). Saf fonksiyonlar: eposta(tur, dil, veri) → { konu, html, metin }.
// Görseller hatdustu.app/img/eposta/ altından gelir (site/img/eposta). Tasarım: koyu hapishane teması,
// tablo tabanlı ve satır içi stilli (Gmail, Outlook, Apple Mail, iOS ve Android posta uygulamalarıyla uyumlu).
// Önizleme ve test gönderimi: node tools/eposta_test.mjs

const SITE = "https://hatdustu.app";
const IMG = SITE + "/img/eposta/";
const DESTEK = "destek@hatdustu.app";
// büyük harfler JS'te dile göre çevrilir: Gmail lang özniteliğini attığı için CSS uppercase "i"yi "I" yapar
let DIL = "tr";
const BUYUK = (s) => String(s).toLocaleUpperCase(DIL === "en" ? "en" : "tr");

const R = {
  zemin: "#0d0b09",
  kart: "#17130f",
  kutu: "#1f1a14",
  cizgi: "#3a2f22",
  amber: "#f2a93b",
  amber2: "#ffcf6b",
  kirmizi: "#e0442e",
  yesil: "#6fcf6b",
  metin: "#efe6d8",
  govde: "#d6cbb9",
  soluk: "#9c8f7a",
};
const BASLIK_FONT = "'Russo One','Arial Black',Arial,Helvetica,sans-serif";
const GOVDE_FONT = "Rubik,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

function k(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ---------- yapı taşları ----------
const p = (html, ek = "") =>
  `<p style="margin:0 0 16px;font-family:${GOVDE_FONT};font-size:16px;line-height:1.65;color:${R.govde};${ek}">${html}</p>`;

const ust_yazi = (s, renk = R.amber) =>
  `<div style="font-family:${GOVDE_FONT};font-size:12px;font-weight:700;letter-spacing:2.5px;color:${renk};margin:0 0 10px">${k(BUYUK(s))}</div>`;

const baslik = (s) =>
  `<h1 style="margin:0 0 18px;font-family:${BASLIK_FONT};font-weight:400;font-size:30px;line-height:1.2;color:${R.metin};letter-spacing:0.3px">${s}</h1>`;

function ikon(ad, alt = "") {
  return `<img src="${IMG}${ad}" width="76" height="76" alt="${k(alt)}" style="display:block;margin:0 auto 18px;width:76px;height:76px;border:0">`;
}

function dugme(metin, url, renk = "amber") {
  const bg = renk === "kirmizi" ? R.kirmizi : R.amber;
  const grad = renk === "kirmizi" ? "linear-gradient(180deg,#f0604a,#c9351f)" : "linear-gradient(180deg,#ffc35a,#e8962a)";
  const yazi = renk === "kirmizi" ? "#ffffff" : "#1a1206";
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" align="center" style="margin:8px auto 22px">
<tr><td align="center" bgcolor="${bg}" style="border-radius:12px;background:${bg};background-image:${grad};box-shadow:0 6px 18px rgba(0,0,0,0.45)">
<a href="${k(url)}" target="_blank" style="display:inline-block;padding:16px 34px;font-family:${BASLIK_FONT};font-size:16px;letter-spacing:1px;color:${yazi};text-decoration:none;border-radius:12px">${k(BUYUK(metin))}</a>
</td></tr></table>`;
}

function kod_kutusu(kod, alt) {
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:6px 0 20px">
<tr><td align="center" bgcolor="${R.zemin}" style="background:${R.zemin};border:1px dashed ${R.amber};border-radius:14px;padding:20px 12px">
<div style="font-family:${BASLIK_FONT};font-size:38px;line-height:1;letter-spacing:12px;color:${R.amber2};padding-left:12px">${k(kod)}</div>
<div style="font-family:${GOVDE_FONT};font-size:13px;color:${R.soluk};margin-top:10px">${k(alt)}</div>
</td></tr></table>`;
}

// anahtar/değer tablosu: [[etiket, değer], ...]
function bilgi(satirlar) {
  const tr = satirlar
    .map(
      ([a, b], i) => `<tr>
<td style="padding:12px 16px;${i ? `border-top:1px solid ${R.cizgi};` : ""}font-family:${GOVDE_FONT};font-size:14px;color:${R.soluk};white-space:nowrap">${k(a)}</td>
<td align="right" style="padding:12px 16px;${i ? `border-top:1px solid ${R.cizgi};` : ""}font-family:${GOVDE_FONT};font-size:14px;font-weight:600;color:${R.metin}">${b}</td>
</tr>`,
    )
    .join("");
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${R.kutu}" style="background:${R.kutu};border:1px solid ${R.cizgi};border-radius:12px;margin:4px 0 22px;border-collapse:separate">${tr}</table>`;
}

// uyarı / not kutusu (sol şerit)
function not(html, renk = R.kirmizi) {
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:4px 0 22px">
<tr><td bgcolor="${R.kutu}" style="background:${R.kutu};border-left:4px solid ${renk};border-radius:8px;padding:14px 16px;font-family:${GOVDE_FONT};font-size:14px;line-height:1.6;color:${R.govde}">${html}</td></tr></table>`;
}

function yedek_baglanti(t, url) {
  return `<p style="margin:0 0 6px;font-family:${GOVDE_FONT};font-size:12px;line-height:1.6;color:${R.soluk}">${k(t.yedek)}</p>
<p style="margin:0 0 4px;font-family:${GOVDE_FONT};font-size:12px;line-height:1.5;word-break:break-all"><a href="${k(url)}" style="color:${R.amber2};text-decoration:underline">${k(url)}</a></p>`;
}

const imza = (t) =>
  `<p style="margin:22px 0 0;font-family:${GOVDE_FONT};font-size:15px;line-height:1.6;color:${R.govde}">${t.imza1}<br><span style="font-family:${BASLIK_FONT};color:${R.amber}">${t.imza2}</span></p>`;

const ayrac = `<div style="height:1px;line-height:1px;background:${R.cizgi};margin:6px 0 22px">&nbsp;</div>`;

// ---------- iskelet ----------
function iskelet({ dil, t, konu, on_yazi, ust_gorsel, govde, alt_not }) {
  const gizli_on = `<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:${R.zemin};opacity:0">${k(on_yazi)}${"&#8199;&#65279;&#847; ".repeat(40)}</div>`;
  const ust = ust_gorsel
    ? `<tr><td style="padding:0;line-height:0;font-size:0"><img src="${IMG}${ust_gorsel}" width="600" alt="" style="display:block;width:100%;max-width:600px;height:auto;border:0;border-radius:18px 18px 0 0"></td></tr>`
    : `<tr><td height="5" style="height:5px;line-height:5px;font-size:0;background:${R.amber};background-image:linear-gradient(90deg,${R.kirmizi},${R.amber},${R.amber2});border-radius:18px 18px 0 0">&nbsp;</td></tr>`;
  return `<!doctype html>
<html lang="${dil}" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="x-apple-disable-message-reformatting">
<meta name="color-scheme" content="dark">
<meta name="supported-color-schemes" content="dark">
<title>${k(konu)}</title>
<link href="https://fonts.googleapis.com/css2?family=Russo+One&family=Rubik:wght@400;600;700&display=swap" rel="stylesheet">
<style>
:root { color-scheme: dark; supported-color-schemes: dark; }
body { margin:0 !important; padding:0 !important; background:${R.zemin}; }
a { color:${R.amber2}; }
@media (max-width:620px) {
  .dis { padding:12px 8px !important; }
  .ic { padding:26px 20px 28px !important; }
  h1 { font-size:25px !important; }
  .oyun td { padding:6px 2px !important; }
}
</style>
</head>
<body style="margin:0;padding:0;background:${R.zemin}" bgcolor="${R.zemin}">
${gizli_on}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${R.zemin}" style="background:${R.zemin}">
<tr><td align="center" class="dis" style="padding:28px 16px 36px">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px">
<tr><td align="center" style="padding:4px 0 24px"><a href="${SITE}${dil === "en" ? "/en/" : "/"}" target="_blank"><img src="${IMG}logo.png" width="220" alt="Hat Düştü" style="display:block;width:220px;height:auto;border:0"></a></td></tr>
<tr><td>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${R.kart}" style="background:${R.kart};border:1px solid ${R.cizgi};border-radius:18px;border-collapse:separate">
${ust}
<tr><td class="ic" style="padding:36px 40px 38px">
${govde}
</td></tr>
</table>
</td></tr>
<tr><td align="center" style="padding:26px 12px 0;font-family:${GOVDE_FONT};font-size:12px;line-height:1.7;color:${R.soluk}">
<a href="${SITE}${dil === "en" ? "/en/support.html" : "/destek.html"}" style="color:${R.soluk};text-decoration:underline">${k(t.f_destek)}</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="${SITE}/gizlilik${dil === "en" ? "#en" : ""}" style="color:${R.soluk};text-decoration:underline">${k(t.f_gizlilik)}</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a href="${SITE}/kosullar${dil === "en" ? "#en" : ""}" style="color:${R.soluk};text-decoration:underline">${k(t.f_kosullar)}</a>
<div style="margin-top:10px">${alt_not || k(t.f_neden)}</div>
<div style="margin-top:10px;color:#6f6455">© 2026 Hat Düştü · <a href="${SITE}" style="color:#6f6455;text-decoration:none">hatdustu.app</a></div>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>`;
}

// ---------- metinler ----------
const T = {
  tr: {
    f_destek: "Destek",
    f_gizlilik: "Gizlilik",
    f_kosullar: "Koşullar",
    f_neden: "Bu e-postayı Hat Düştü hesabınla ilgili önemli bir bilgilendirme olduğu için aldın.",
    f_tanitim: "Bu e-postayı Hat Düştü'de hesap açtığın için aldın.",
    yedek: "Düğme çalışmıyorsa bu bağlantıyı tarayıcına yapıştır:",
    imza1: "Görüşmek üzere,",
    imza2: "Hat Düştü Ekibi",
    sen_degilsen: "Bu isteği sen yapmadıysan bu e-postayı yok sayabilirsin; hesabında hiçbir şey değişmez.",
    asla: "Hat Düştü ekibi senden asla şifreni ya da doğrulama kodunu istemez.",
    cihaz: "Cihaz",
    konum: "Konum (yaklaşık)",
    zaman: "Zaman",
    hesap: "Hesap",
    hosgeldin: {
      konu: "Hücren hazır, {ad}! 📞",
      on: "Duvardaki kırmızı telefon çalıyor. İlk maçına hazır mısın?",
      ust: "Hoş geldin",
      bas: "Hücren hazır, {ad}!",
      g1: "Hat Düştü'ye katıldığın için teşekkürler. Burada kural basit: <b style=\"color:#efe6d8\">kimse kimseyi göremez, sadece sesini duyar.</b> Duvardaki kırmızı telefonu kap, arkadaşlarını ara; iş birliği yap, ikna et ya da düpedüz kandır.",
      adimlar: [
        ["Hücrene gir", "4 ila 8 oyuncu, herkes ayrı bir hücrede. Hızlı Oyun ile hemen başla ya da arkadaşlarınla oda kur."],
        ["Telefonu kap", "Birini ara, gizli bilgileri paylaş, pazarlık yap… ya da yalan söyle."],
        ["Tacı kap", "Puanlar sona kadar gizli. 6 oyunun sonunda sıralama sondan başa açılır."],
      ],
      oyunlar_bas: "Seni bekleyen oyunlar",
      oyunlar: [
        ["kimkim", "Kim Kim?"],
        ["tahta", "Kara Tahta"],
        ["devre", "Kısa Devre"],
        ["yalanci", "Yalancı"],
        ["rulet", "Rus Ruleti"],
        ["c4", "C4"],
        ["ortalama", "Ortalama"],
      ],
      kullanici: "Kullanıcı adın",
      dugme: "Hemen oyna",
      ipucu: "<b style=\"color:#efe6d8\">İpucu:</b> Arkadaşlarınla oynamak için menüden <b style=\"color:#ffcf6b\">ODA KUR</b>'a dokun ve oda kodunu paylaş. Hepsi hazır dediğinde maç başlar.",
      kapanis: "Telefon çalıyor. Açmayacak mısın?",
    },
    dogrula: {
      konu: "E-posta adresini doğrula: {kod}",
      on: "Doğrulama kodun: {kod}. 30 dakika geçerli.",
      ust: "Hesap güvenliği",
      bas: "E-posta adresini doğrula",
      g1: "Merhaba <b style=\"color:#efe6d8\">{ad}</b>, Hat Düştü hesabına bu e-posta adresini eklemek istedin. Aşağıdaki kodu oyuna gir ya da düğmeye dokun.",
      kod_alt: "Kod 30 dakika geçerli",
      dugme: "E-postamı doğrula",
      fayda: "Doğrulanmış e-posta ile şifreni unutsan bile hesabını, elmaslarını ve eşyalarını kurtarabilirsin.",
    },
    sifirla: {
      konu: "Hat Düştü şifreni sıfırla",
      on: "Şifre sıfırlama isteği aldık. Bağlantı 15 dakika geçerli.",
      ust: "Hesap güvenliği",
      bas: "Şifreni sıfırla",
      g1: "<b style=\"color:#efe6d8\">@{kullanici}</b> hesabın için şifre sıfırlama isteği aldık. Yeni şifreni belirlemek için düğmeye dokun ya da kodu oyuna gir.",
      dugme: "Yeni şifre belirle",
      kod_alt: "Bağlantı ve kod 15 dakika geçerli",
      istek: "İstek",
    },
    degisti: {
      konu: "Şifren değiştirildi",
      on: "Hat Düştü hesabının şifresi az önce değiştirildi.",
      ust: "Hesap güvenliği",
      bas: "Şifren değiştirildi",
      g1: "<b style=\"color:#efe6d8\">@{kullanici}</b> hesabının şifresi başarıyla değiştirildi. Diğer cihazlardaki oturumların güvenliğin için kapatıldı.",
      uyari: "<b style=\"color:#ff8a76\">Bunu sen yapmadıysan</b> hemen şifreni sıfırla ve bize yaz. Hesabını birlikte güvene alalım.",
      dugme: "Bu ben değildim",
    },
    giris: {
      konu: "Hesabına yeni bir cihazdan giriş yapıldı",
      on: "{cihaz} · {konum}. Sen değilsen hemen şifreni değiştir.",
      ust: "Güvenlik uyarısı",
      bas: "Yeni cihazdan giriş",
      g1: "<b style=\"color:#efe6d8\">@{kullanici}</b> hesabına daha önce görmediğimiz bir cihazdan giriş yapıldı.",
      sen_mi: "Sen miydin? Öyleyse bir şey yapmana gerek yok.",
      uyari: "<b style=\"color:#ff8a76\">Sen değilsen:</b> şifreni hemen sıfırla. Sıfırladığında tüm cihazlardaki oturumlar kapanır.",
      dugme: "Şifremi sıfırla",
    },
    makbuz: {
      konu: "Satın alman tamamlandı: {paket}",
      on: "{elmas} elmas hesabına eklendi. Teşekkürler!",
      ust: "Satın alma onayı",
      bas: "Elmasların hesabında!",
      g1: "Teşekkürler <b style=\"color:#efe6d8\">{ad}</b>! Satın alman tamamlandı ve elmasların <b style=\"color:#efe6d8\">@{kullanici}</b> hesabına eklendi.",
      siparis: "Sipariş no",
      tarih: "Tarih",
      platform: "Mağaza",
      tutar: "Toplam (KDV dahil)",
      dugme: "Mağazaya git",
      not: "Ödemen {magaza} tarafından alındı; resmi faturan ayrıca {magaza} tarafından gönderilir. Ödeme bilgilerini biz görmeyiz. İade talepleri {magaza} iade kurallarına göre yapılır.",
    },
    silindi: {
      konu: "Hat Düştü hesabın silindi",
      on: "Hesabın ve ona bağlı veriler kalıcı olarak silindi.",
      ust: "Hesap",
      bas: "Hesabın silindi",
      g1: "<b style=\"color:#efe6d8\">@{kullanici}</b> hesabın, isteğin üzerine silindi. Profilin, ilerlemen, elmasların, eşyaların ve arkadaş listen kalıcı olarak kaldırıldı. Bu işlem geri alınamaz.",
      saklanan: "Yasal yükümlülükler gereği satın alma kayıtları 5 yıl, şikayet kayıtları 1 yıl hesabından koparılarak saklanır, sonra silinir.",
      veda: "Seni özleyeceğiz. Hücren her zaman burada; istediğin zaman yeni bir hesapla geri dönebilirsin.",
      uyari: "<b style=\"color:#ff8a76\">Bu isteği sen yapmadıysan</b> hemen bize yaz.",
      dugme: "Destek ekibine yaz",
    },
    destek: {
      konu: "Mesajını aldık [#{no}]",
      on: "Destek talebin oluşturuldu. Genellikle 24 saat içinde dönüyoruz.",
      ust: "Destek",
      bas: "Mesajını aldık",
      g1: "Merhaba <b style=\"color:#efe6d8\">{ad}</b>, bize yazdığın için teşekkürler. Talebin ekibimize ulaştı; <b style=\"color:#efe6d8\">genellikle 24 saat içinde</b> bu adrese yanıt veriyoruz.",
      no: "Talep no",
      konu_e: "Konu",
      mesajin: "Mesajın",
      ek: "Eklemek istediğin bir şey olursa bu e-postayı yanıtlaman yeterli; talep numaran konu satırında kalsın.",
    },
  },
  en: {
    f_destek: "Support",
    f_gizlilik: "Privacy",
    f_kosullar: "Terms",
    f_neden: "You received this email because it contains important information about your Hat Düştü account.",
    f_tanitim: "You received this email because you created a Hat Düştü account.",
    yedek: "If the button doesn't work, paste this link into your browser:",
    imza1: "See you on the line,",
    imza2: "The Hat Düştü Team",
    sen_degilsen: "If you didn't request this, you can ignore this email; nothing on your account will change.",
    asla: "The Hat Düştü team will never ask for your password or verification code.",
    cihaz: "Device",
    konum: "Location (approx.)",
    zaman: "Time",
    hesap: "Account",
    hosgeldin: {
      konu: "Your cell is ready, {ad}! 📞",
      on: "The red phone on the wall is ringing. Ready for your first match?",
      ust: "Welcome",
      bas: "Your cell is ready, {ad}!",
      g1: "Thanks for joining Hat Düştü. The rule is simple: <b style=\"color:#efe6d8\">nobody can see anyone, you can only hear them.</b> Grab the red phone on the wall, call your friends; team up, persuade, or flat out deceive.",
      adimlar: [
        ["Enter your cell", "4 to 8 players, each in their own cell. Jump in with Quick Play or create a room with friends."],
        ["Grab the phone", "Call someone, share secrets, bargain… or lie."],
        ["Take the crown", "Scores stay hidden until the end. After 6 games the ranking is revealed from last to first."],
      ],
      oyunlar_bas: "Games waiting for you",
      oyunlar: [
        ["kimkim", "Who's Who?"],
        ["tahta", "Blackboard"],
        ["devre", "Short Circuit"],
        ["yalanci", "Liar"],
        ["rulet", "Roulette"],
        ["c4", "C4"],
        ["ortalama", "Average"],
      ],
      kullanici: "Your username",
      dugme: "Play now",
      ipucu: "<b style=\"color:#efe6d8\">Tip:</b> To play with friends, tap <b style=\"color:#ffcf6b\">CREATE ROOM</b> in the menu and share the room code. The match starts when everyone is ready.",
      kapanis: "The phone is ringing. Aren't you going to pick up?",
    },
    dogrula: {
      konu: "Verify your email: {kod}",
      on: "Your verification code: {kod}. Valid for 30 minutes.",
      ust: "Account security",
      bas: "Verify your email",
      g1: "Hi <b style=\"color:#efe6d8\">{ad}</b>, you asked to add this email address to your Hat Düştü account. Enter the code below in the game or tap the button.",
      kod_alt: "Code valid for 30 minutes",
      dugme: "Verify my email",
      fayda: "With a verified email you can recover your account, gems and items even if you forget your password.",
    },
    sifirla: {
      konu: "Reset your Hat Düştü password",
      on: "We received a password reset request. The link is valid for 15 minutes.",
      ust: "Account security",
      bas: "Reset your password",
      g1: "We received a password reset request for <b style=\"color:#efe6d8\">@{kullanici}</b>. Tap the button to choose a new password, or enter the code in the game.",
      dugme: "Set a new password",
      kod_alt: "Link and code valid for 15 minutes",
      istek: "Request",
    },
    degisti: {
      konu: "Your password was changed",
      on: "The password for your Hat Düştü account was just changed.",
      ust: "Account security",
      bas: "Your password was changed",
      g1: "The password for <b style=\"color:#efe6d8\">@{kullanici}</b> was changed successfully. For your safety, sessions on other devices were signed out.",
      uyari: "<b style=\"color:#ff8a76\">If this wasn't you</b>, reset your password right away and write to us. We'll secure your account together.",
      dugme: "This wasn't me",
    },
    giris: {
      konu: "New sign-in to your account",
      on: "{cihaz} · {konum}. If this wasn't you, change your password now.",
      ust: "Security alert",
      bas: "New device sign-in",
      g1: "Someone signed in to <b style=\"color:#efe6d8\">@{kullanici}</b> from a device we haven't seen before.",
      sen_mi: "Was this you? Then there's nothing you need to do.",
      uyari: "<b style=\"color:#ff8a76\">If this wasn't you:</b> reset your password now. Resetting signs out every device.",
      dugme: "Reset my password",
    },
    makbuz: {
      konu: "Purchase complete: {paket}",
      on: "{elmas} gems added to your account. Thank you!",
      ust: "Purchase confirmation",
      bas: "Your gems are in!",
      g1: "Thanks <b style=\"color:#efe6d8\">{ad}</b>! Your purchase is complete and the gems were added to <b style=\"color:#efe6d8\">@{kullanici}</b>.",
      siparis: "Order no.",
      tarih: "Date",
      platform: "Store",
      tutar: "Total (tax incl.)",
      dugme: "Go to store",
      not: "Your payment was processed by {magaza}; your official invoice is sent separately by {magaza}. We never see your payment details. Refunds follow {magaza}'s refund policy.",
    },
    silindi: {
      konu: "Your Hat Düştü account was deleted",
      on: "Your account and its data have been permanently deleted.",
      ust: "Account",
      bas: "Your account was deleted",
      g1: "Your account <b style=\"color:#efe6d8\">@{kullanici}</b> was deleted at your request. Your profile, progress, gems, items and friends list have been permanently removed. This can't be undone.",
      saklanan: "For legal obligations, purchase records (5 years) and reports (1 year) are kept unlinked from your account, then deleted.",
      veda: "We'll miss you. Your cell is always here; you can come back with a new account anytime.",
      uyari: "<b style=\"color:#ff8a76\">If you didn't request this</b>, write to us right away.",
      dugme: "Contact support",
    },
    destek: {
      konu: "We got your message [#{no}]",
      on: "Your support request was created. We usually reply within 24 hours.",
      ust: "Support",
      bas: "We got your message",
      g1: "Hi <b style=\"color:#efe6d8\">{ad}</b>, thanks for writing to us. Your request reached our team; we <b style=\"color:#efe6d8\">usually reply within 24 hours</b> to this address.",
      no: "Request no.",
      konu_e: "Subject",
      mesajin: "Your message",
      ek: "To add anything, just reply to this email; keep the request number in the subject line.",
    },
  },
};

function doldur(s, v) {
  return String(s).replace(/\{(\w+)\}/g, (_, a) => (v[a] !== undefined ? v[a] : `{${a}}`));
}
// metin içine kullanıcı verisi: önce kaçır, sonra yerleştir
function doldur_k(s, v) {
  const kv = Object.fromEntries(Object.entries(v).map(([a, b]) => [a, k(b)]));
  return doldur(s, kv);
}

// ---------- e-posta türleri ----------
const TURLER = {
  hosgeldin(t, v, dil) {
    const m = t.hosgeldin;
    const adimlar = m.adimlar
      .map(
        ([a, b], i) => `<tr><td width="46" valign="top" style="padding:0 14px 16px 0">
<div style="width:40px;height:40px;line-height:40px;border-radius:20px;background:${R.amber};background-image:linear-gradient(180deg,#ffc35a,#e8962a);text-align:center;font-family:${BASLIK_FONT};font-size:18px;color:#1a1206">${i + 1}</div></td>
<td valign="top" style="padding:0 0 16px"><div style="font-family:${BASLIK_FONT};font-size:17px;color:${R.metin};margin:2px 0 4px">${k(a)}</div>
<div style="font-family:${GOVDE_FONT};font-size:14px;line-height:1.55;color:${R.govde}">${k(b)}</div></td></tr>`,
      )
      .join("");
    const hucre = ([id, ad]) =>
      `<td align="center" valign="top" width="25%" style="padding:8px 4px"><img src="${IMG}oyun_${id}.png" width="64" height="64" alt="" style="display:block;margin:0 auto 6px;width:64px;height:64px;border:0;border-radius:14px"><div style="font-family:${GOVDE_FONT};font-size:12px;font-weight:600;color:${R.govde}">${k(ad)}</div></td>`;
    const o = m.oyunlar;
    const oyunlar = `<table role="presentation" class="oyun" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 18px"><tr>${o.slice(0, 4).map(hucre).join("")}</tr></table>
<table role="presentation" class="oyun" width="75%" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto 22px"><tr>${o.slice(4).map((x) => hucre(x).replace('width="25%"', 'width="33%"')).join("")}</tr></table>`;
    return {
      konu: doldur(m.konu, v),
      on_yazi: m.on,
      ust_gorsel: "kapak.jpg",
      alt_not: k(t.f_tanitim),
      govde: `${ust_yazi(m.ust)}${baslik(doldur_k(m.bas, v))}${p(m.g1)}
${bilgi([[m.kullanici, `<span style="color:${R.amber2}">@${k(v.kullanici)}</span>`]])}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:4px 0 10px">${adimlar}</table>
${ayrac}
<div style="font-family:${BASLIK_FONT};font-size:18px;color:${R.metin};text-align:center;margin:0 0 12px">${k(m.oyunlar_bas)}</div>
${oyunlar}
${dugme(m.dugme, v.url || SITE + (dil === "en" ? "/en/" : "/"))}
${not(m.ipucu, R.amber)}
<p style="margin:18px 0 0;font-family:${BASLIK_FONT};font-size:17px;color:${R.amber};text-align:center">${k(m.kapanis)}</p>`,
    };
  },

  dogrula(t, v) {
    const m = t.dogrula;
    return {
      konu: doldur(m.konu, v),
      on_yazi: doldur(m.on, v),
      govde: `<div style="text-align:center">${ikon("ik_posta.png")}${ust_yazi(m.ust)}${baslik(k(m.bas))}</div>
${p(doldur_k(m.g1, v))}
${kod_kutusu(v.kod, m.kod_alt)}
${dugme(m.dugme, v.url)}
${p(k(m.fayda), `font-size:14px;color:${R.soluk}`)}
${not(`${k(t.sen_degilsen)} ${k(t.asla)}`, R.cizgi)}
${yedek_baglanti(t, v.url)}
${imza(t)}`,
    };
  },

  sifirla(t, v) {
    const m = t.sifirla;
    return {
      konu: doldur(m.konu, v),
      on_yazi: m.on,
      govde: `<div style="text-align:center">${ikon("ik_kilit.png")}${ust_yazi(m.ust)}${baslik(k(m.bas))}</div>
${p(doldur_k(m.g1, v))}
${dugme(m.dugme, v.url)}
${kod_kutusu(v.kod, m.kod_alt)}
${bilgi([
  [m.istek, k(v.zaman)],
  [t.cihaz, k(v.cihaz)],
  [t.konum, k(v.konum)],
])}
${not(`${k(t.sen_degilsen)} <b style="color:${R.metin}">${k(t.asla)}</b>`)}
${yedek_baglanti(t, v.url)}
${imza(t)}`,
    };
  },

  degisti(t, v) {
    const m = t.degisti;
    return {
      konu: m.konu,
      on_yazi: m.on,
      govde: `<div style="text-align:center">${ikon("ik_onay.png")}${ust_yazi(m.ust, R.yesil)}${baslik(k(m.bas))}</div>
${p(doldur_k(m.g1, v))}
${bilgi([
  [t.hesap, `@${k(v.kullanici)}`],
  [t.zaman, k(v.zaman)],
  [t.cihaz, k(v.cihaz)],
  [t.konum, k(v.konum)],
])}
${not(m.uyari)}
${dugme(m.dugme, v.url, "kirmizi")}
${imza(t)}`,
    };
  },

  giris(t, v) {
    const m = t.giris;
    return {
      konu: m.konu,
      on_yazi: doldur(m.on, v),
      govde: `<div style="text-align:center">${ikon("ik_uyari.png")}${ust_yazi(m.ust, R.kirmizi)}${baslik(k(m.bas))}</div>
${p(doldur_k(m.g1, v))}
${bilgi([
  [t.cihaz, k(v.cihaz)],
  [t.konum, k(v.konum)],
  [t.zaman, k(v.zaman)],
])}
${p(k(m.sen_mi))}
${not(m.uyari)}
${dugme(m.dugme, v.url, "kirmizi")}
${p(k(t.asla), `font-size:13px;color:${R.soluk};text-align:center`)}
${imza(t)}`,
    };
  },

  makbuz(t, v) {
    const m = t.makbuz;
    const urun = `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${R.kart}" style="background:${R.kart};border:1px solid ${R.amber};border-radius:14px;margin:4px 0 16px;border-collapse:separate">
<tr><td width="104" style="padding:14px 0 14px 14px"><img src="${IMG}paket.jpg" width="92" height="92" alt="" style="display:block;width:92px;height:92px;border:0;border-radius:12px"></td>
<td style="padding:14px 16px">
<div style="font-family:${GOVDE_FONT};font-size:11px;font-weight:700;letter-spacing:2px;color:${R.amber}">${k(BUYUK(v.etiket || ""))}</div>
<div style="font-family:${BASLIK_FONT};font-size:20px;color:${R.metin};margin:4px 0 6px">${k(v.paket)}</div>
<div style="font-family:${GOVDE_FONT};font-size:14px;color:${R.govde}"><img src="${IMG}ik_elmas.png" width="18" height="18" alt="" style="vertical-align:-3px;border:0"> <b style="color:#7fe3ff">${k(v.elmas)}</b>${v.ek ? ` &nbsp;+&nbsp; ${k(v.ek)}` : ""}</div>
</td></tr></table>`;
    return {
      konu: doldur(m.konu, v),
      on_yazi: doldur(m.on, v),
      govde: `<div style="text-align:center">${ust_yazi(m.ust, R.yesil)}${baslik(k(m.bas))}</div>
${p(doldur_k(m.g1, v))}
${urun}
${bilgi([
  [m.siparis, k(v.siparis)],
  [m.tarih, k(v.zaman)],
  [m.platform, k(v.magaza)],
  [m.tutar, `<span style="font-family:${BASLIK_FONT};font-size:18px;color:${R.amber2}">${k(v.tutar)}</span>`],
])}
${dugme(m.dugme, v.url)}
${p(doldur_k(m.not, v), `font-size:13px;color:${R.soluk}`)}
${imza(t)}`,
    };
  },

  silindi(t, v) {
    const m = t.silindi;
    return {
      konu: m.konu,
      on_yazi: m.on,
      govde: `<div style="text-align:center">${ikon("ik_kapi.png")}${ust_yazi(m.ust, R.soluk)}${baslik(k(m.bas))}</div>
${p(doldur_k(m.g1, v))}
${bilgi([
  [t.hesap, `@${k(v.kullanici)}`],
  [t.zaman, k(v.zaman)],
])}
${p(k(m.saklanan), `font-size:13px;color:${R.soluk}`)}
${p(k(m.veda))}
${not(m.uyari)}
${dugme(m.dugme, `mailto:${DESTEK}?subject=${encodeURIComponent("Hesap silme: @" + (v.kullanici || ""))}`)}
${imza(t)}`,
    };
  },

  destek(t, v) {
    const m = t.destek;
    const mesaj = k(v.mesaj).replace(/\n/g, "<br>");
    return {
      konu: doldur(m.konu, v),
      on_yazi: m.on,
      govde: `<div style="text-align:center">${ikon("ik_telefon.png")}${ust_yazi(m.ust)}${baslik(k(m.bas))}</div>
${p(doldur_k(m.g1, v))}
${bilgi([
  [m.no, `<span style="color:${R.amber2}">#${k(v.no)}</span>`],
  [m.konu_e, k(v.baslik)],
  [t.zaman, k(v.zaman)],
])}
<div style="font-family:${GOVDE_FONT};font-size:12px;font-weight:700;letter-spacing:2px;color:${R.soluk};margin:0 0 8px">${k(BUYUK(m.mesajin))}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 22px"><tr><td style="border-left:3px solid ${R.cizgi};padding:4px 0 4px 16px;font-family:${GOVDE_FONT};font-size:14px;line-height:1.65;color:${R.govde};font-style:italic">${mesaj}</td></tr></table>
${p(k(m.ek), `font-size:14px;color:${R.soluk}`)}
${imza(t)}`,
    };
  },
};

export const EPOSTA_TURLERI = Object.keys(TURLER);

// düz metin sürümü (HTML göremeyen istemciler ve spam süzgeçleri için)
function duz(html) {
  return html
    .replace(/<div style="display:none[\s\S]*?<\/div>/, "")
    .replace(/<(style|title|head)[\s\S]*?<\/\1>/gi, "")
    .replace(/<a [^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi, (_, u, s) => (u.startsWith("http") && s.replace(/<[^>]+>/g, "").trim() !== u ? `${s} (${u})` : s))
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|h1|tr|table)>/gi, "\n")
    .replace(/<\/td>/gi, "  ")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#\d+;/g, "")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function eposta(tur, dil, veri = {}) {
  const t = T[dil] || T.tr;
  DIL = dil === "en" ? "en" : "tr";
  const f = TURLER[tur];
  if (!f) throw new Error("bilinmeyen e-posta türü: " + tur);
  const parca = f(t, veri, dil === "en" ? "en" : "tr");
  const html = iskelet({ dil: dil === "en" ? "en" : "tr", t, konu: parca.konu, on_yazi: parca.on_yazi, ust_gorsel: parca.ust_gorsel, govde: parca.govde, alt_not: parca.alt_not });
  return { konu: parca.konu, html, metin: duz(html) };
}
