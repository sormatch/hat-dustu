// Web'den hesap silme sayfası (Google Play şartı: oyunu silmiş biri de hesabının silinmesini isteyebilmeli).
// GET /hesap-sil (İngilizce bölüm #en; /delete-account aynı sayfa) -> form. POST /hesap-sil -> sonuç sayfası.
// Silme işini Accounts.webDelete / deleteAccount yapar (accounts.js); saklama süreleri KAYIT_SURE ile aynı olmalı.

import { page, ILETISIM } from "./gizlilik.js";

const STIL = `<style>
form{background:#1a1d23;border:1px solid #333;border-radius:12px;padding:18px;margin:18px 0}
label{display:block;margin:10px 0 4px;color:#ffcf8a}
input[type=text],input[type=password]{width:100%;box-sizing:border-box;padding:12px;font-size:17px;border-radius:8px;border:1px solid #555;background:#0c0e11;color:#e9e6df}
.onay{display:flex;gap:10px;align-items:flex-start;margin:14px 0;color:#e9e6df}.onay input{width:22px;height:22px;flex:none;margin-top:2px}
button{background:#c0392b;color:#fff;border:0;border-radius:10px;padding:14px 22px;font-size:17px;font-weight:700;cursor:pointer;width:100%}
.kutu{border-radius:12px;padding:16px 18px;margin:18px 0}.iyi{background:#12301c;border:1px solid #2e7d4a}.kotu{background:#3a1512;border:1px solid #a84432}
td,th{border-top:1px solid #333;padding:8px 6px;text-align:left;vertical-align:top}table{border-collapse:collapse;width:100%}th{color:#ffcf8a}
</style>`;

const METIN = {
  tr: {
    baslik: "Hesabını sil",
    giris: "Hat Düştü hesabını buradan kalıcı olarak silebilirsin. Oyun telefonunda yüklü değilse de çalışır. Oyunun içinden silmek için: <b>Ayarlar → Hesap → Hesabı sil</b>.",
    kullanici: "Kullanıcı adı (@ olmadan)",
    sifre: "Şifre",
    onay: "Hesabımın ve ilerlememin kalıcı olarak silineceğini, bunun geri alınamayacağını anlıyorum.",
    dugme: "HESABIMI KALICI OLARAK SİL",
    silinen: "Hemen ve kalıcı olarak silinenler",
    silinenler: [
      "Kullanıcı adın, görünen adın ve şifren (şifrenin özeti)",
      "Karakter görünüşün, elmasların, eşyaların ve açılmamış kasaların",
      "Seviye/deneyim puanın, görev ve başarım ilerlemen, maç istatistiklerin, haftalık liderlik puanın",
      "Arkadaş listen, gönderdiğin ve aldığın istekler, engellediğin oyuncular",
    ],
    saklanan: "Bir süre saklananlar (hesabınla bağı koparılır)",
    tablo: ["Veri", "Neden", "Süre"],
    saklananlar: [
      ["Satın alma kayıtları (paket, elmas, tutar, platform, tarih, mağaza makbuzu)", "İade, dolandırıcılık incelemesi ve yasal/mali yükümlülükler", "5 yıl, sonra silinir"],
      ["Gönderdiğin ve senin hakkında yapılan şikayetler (neden, oda kodu, not, oyundaki ad)", "Kötüye kullanımı önleme ve moderasyon", "1 yıl, sonra silinir"],
      ["Hata raporları ve oyun olayları (cihaz modeli, sürüm, dil)", "Hataları düzeltmek; zaten hesabına bağlı değildir", "30 gün, sonra silinir"],
    ],
    ses: "Sesli konuşmalar hiçbir zaman kaydedilmez ve saklanmaz.",
    misafir: "Hesap açmadan <b>misafir</b> olarak oynadıysan kullanıcı adın ve şifren olmadığı için bu form kullanılamaz: oyunun içinden <b>Ayarlar → Hesap → Hesabı sil</b> ile silebilirsin. Misafir kaydı hiçbir kimlik bilgisi (ad, e-posta, telefon) içermez.",
    sorun: "Şifreni unuttuysan ya da bir sorun olursa bize yaz:",
    sonuc: {
      silindi: ["iyi", "Hesabın silindi.", "Kullanıcı adın, ilerlemen ve arkadaşlıkların kalıcı olarak silindi. Oyunu yeniden açarsan yeni bir misafir olarak başlarsın."],
      yanlis: ["kotu", "Kullanıcı adı ya da şifre yanlış.", "Bilgilerini kontrol edip tekrar dene."],
      cok_deneme: ["kotu", "Çok fazla deneme.", "Güvenliğin için silme 15 dakika kapalı. Biraz sonra tekrar dene."],
      onay: ["kotu", "Onay kutusunu işaretle.", "Silmeden önce kalıcı silmeyi onaylaman gerekiyor."],
      eksik: ["kotu", "Kullanıcı adını ve şifreni yaz.", ""],
      hata: ["kotu", "Bir sorun oldu.", "Lütfen biraz sonra tekrar dene."],
    },
    geri: "Geri dön",
  },
  en: {
    baslik: "Delete your account",
    giris: "You can permanently delete your Hat Düştü account here, even if the game is no longer installed. To delete it in the game: <b>Settings → Account → Delete account</b>.",
    kullanici: "Username (without @)",
    sifre: "Password",
    onay: "I understand that my account and progress will be permanently deleted and this cannot be undone.",
    dugme: "PERMANENTLY DELETE MY ACCOUNT",
    silinen: "Deleted immediately and permanently",
    silinenler: [
      "Your username, display name and password (password hash)",
      "Your character appearance, gems, items and unopened chests",
      "Your level/XP, mission and achievement progress, match stats, weekly leaderboard score",
      "Your friends list, sent and received requests, players you blocked",
    ],
    saklanan: "Kept for a limited time (no longer linked to your account)",
    tablo: ["Data", "Why", "How long"],
    saklananlar: [
      ["Purchase records (pack, gems, amount, platform, date, store receipt)", "Refunds, fraud checks and legal/financial obligations", "5 years, then deleted"],
      ["Reports you sent or that were made about you (reason, room code, note, in-game name)", "Preventing abuse and moderation", "1 year, then deleted"],
      ["Error reports and game events (device model, version, language)", "Fixing bugs; never linked to your account", "30 days, then deleted"],
    ],
    ses: "Voice chat is never recorded or stored.",
    misafir: "If you played as a <b>guest</b> (no account), you have no username or password, so this form can't be used: delete it in the game under <b>Settings → Account → Delete account</b>. Guest records contain no identity information (name, e-mail, phone).",
    sorun: "If you forgot your password or need help, contact us:",
    sonuc: {
      silindi: ["iyi", "Your account was deleted.", "Your username, progress and friends were permanently deleted. If you open the game again you will start as a new guest."],
      yanlis: ["kotu", "Wrong username or password.", "Check your details and try again."],
      cok_deneme: ["kotu", "Too many attempts.", "For your security, deletion is locked for 15 minutes. Please try again later."],
      onay: ["kotu", "Please tick the confirmation box.", "You need to confirm permanent deletion first."],
      eksik: ["kotu", "Enter your username and password.", ""],
      hata: ["kotu", "Something went wrong.", "Please try again later."],
    },
    geri: "Go back",
  },
};

const kac = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

function bolum(dil) {
  const t = METIN[dil];
  const id = dil === "en" ? ' id="en"' : "";
  return `
<h1${id}>Hat Düştü — ${t.baslik}</h1>
<p>${t.giris}</p>
<form method="post" action="/hesap-sil" autocomplete="off">
<input type="hidden" name="dil" value="${dil}">
<label for="k_${dil}">${t.kullanici}</label><input type="text" id="k_${dil}" name="kullanici" maxlength="32" autocapitalize="none" spellcheck="false" required>
<label for="s_${dil}">${t.sifre}</label><input type="password" id="s_${dil}" name="sifre" maxlength="64" required>
<div class="onay"><input type="checkbox" id="o_${dil}" name="onay" value="1" required><label for="o_${dil}" style="margin:0;color:#e9e6df">${t.onay}</label></div>
<button type="submit">${t.dugme}</button>
</form>
<h2>${t.silinen}</h2>
<ul>${t.silinenler.map((x) => `<li>${x}</li>`).join("")}</ul>
<h2>${t.saklanan}</h2>
<table><tr>${t.tablo.map((x) => `<th>${x}</th>`).join("")}</tr>${t.saklananlar.map((r) => `<tr>${r.map((x) => `<td>${x}</td>`).join("")}</tr>`).join("")}</table>
<p>${t.ses}</p>
<p>${t.misafir}</p>
<p>${t.sorun} <a href="mailto:${ILETISIM}">${ILETISIM}</a></p>`;
}

export function hesapSilHtml() {
  return page("Hesabı sil / Delete account", STIL + bolum("tr") + "<hr>" + bolum("en"));
}

// Silme denemesinin sonucu. kod: silindi | yanlis | cok_deneme | onay | eksik | hata
export function hesapSilSonucHtml(kod, dil) {
  const t = METIN[dil === "en" ? "en" : "tr"];
  const [tur, baslik, aciklama] = t.sonuc[kod] || t.sonuc.hata;
  const geri = kod === "silindi" ? "" : `<p><a href="/hesap-sil${dil === "en" ? "#en" : ""}">${t.geri}</a></p>`;
  return page(t.baslik, `${STIL}<h1>Hat Düştü — ${kac(t.baslik)}</h1><div class="kutu ${tur}"><b>${kac(baslik)}</b>${aciklama ? `<br>${kac(aciklama)}` : ""}</div>${geri}`);
}
