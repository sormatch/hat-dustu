// E-postadaki bağlantıların web sayfaları: e-posta doğrulama ve şifre sıfırlama (kod bağlantıda dolu gelir).
// GET  /eposta-dogrula?h=<kullanıcı adı>&k=<kod>  -> onay düğmesi (posta tarayıcıları bağlantıyı açınca kendiliğinden doğrulanmasın)
// POST /eposta-dogrula                             -> sonuç
// GET  /sifre-sifirla?h=<kullanıcı adı>&k=<kod>  -> yeni şifre formu;  POST -> sonuç
// İşi Accounts.webKod yapar (accounts.js). Dil: ?dil=en ya da tarayıcının dili.

import { page, ILETISIM } from "./gizlilik.js";

const STIL = `<style>
form{background:#1a1d23;border:1px solid #333;border-radius:12px;padding:18px;margin:18px 0}
label{display:block;margin:10px 0 4px;color:#ffcf8a}
input[type=password]{width:100%;box-sizing:border-box;padding:12px;font-size:17px;border-radius:8px;border:1px solid #555;background:#0c0e11;color:#e9e6df}
button{background:#f2a93b;color:#1a1206;border:0;border-radius:10px;padding:14px 22px;font-size:17px;font-weight:700;cursor:pointer;width:100%;margin-top:14px}
.kutu{border-radius:12px;padding:16px 18px;margin:18px 0}.iyi{background:#12301c;border:1px solid #2e7d4a}.kotu{background:#3a1512;border:1px solid #a84432}
.kod{font-size:28px;letter-spacing:8px;color:#ffcf6b;font-weight:700}
</style>`;

const M = {
  tr: {
    d_baslik: "E-posta adresini doğrula",
    d_giris: "<b>@{h}</b> hesabının e-posta adresini doğrulamak için düğmeye dokun.",
    d_dugme: "E-POSTAMI DOĞRULA",
    s_baslik: "Yeni şifre belirle",
    s_giris: "<b>@{h}</b> hesabı için yeni şifreni yaz. Şifren değişince diğer cihazlardaki oturumların kapanır.",
    sifre: "Yeni şifre (en az 6 karakter)",
    sifre2: "Yeni şifre tekrar",
    s_dugme: "ŞİFREMİ DEĞİŞTİR",
    kod: "Kod",
    oyun: "Kodu oyunun içine de yazabilirsin.",
    sonuc: {
      d_tamam: ["iyi", "E-postan doğrulandı.", "Oyuna dönebilirsin. Şifreni unutursan hesabını bu adresle kurtarabilirsin."],
      s_tamam: ["iyi", "Şifren değişti.", "Oyunu açıp kullanıcı adın ve yeni şifrenle giriş yap."],
      zaten: ["iyi", "E-postan zaten doğrulanmış.", ""],
      yanlis: ["kotu", "Kod yanlış.", "E-postadaki bağlantıyı yeniden aç ya da kodu oyunun içine yaz."],
      suresi: ["kotu", "Kodun süresi doldu.", "Oyunun içinden yeni kod iste."],
      iptal: ["kotu", "Kod iptal edildi.", "Çok fazla yanlış deneme yapıldı. Oyunun içinden yeni kod iste."],
      yok: ["kotu", "Geçerli bir kod yok.", "Oyunun içinden yeni kod iste."],
      kisa: ["kotu", "Şifre en az 6 karakter olmalı.", ""],
      uzun: ["kotu", "Şifre en fazla 64 karakter olabilir.", ""],
      ayni_degil: ["kotu", "Şifreler aynı değil.", ""],
      cok_deneme: ["kotu", "Çok fazla deneme.", "Güvenliğin için 15 dakika bekle, sonra tekrar dene."],
      eksik: ["kotu", "Bağlantı eksik.", "E-postadaki bağlantıyı yeniden aç."],
      hata: ["kotu", "Bir sorun oldu.", "Lütfen biraz sonra tekrar dene."],
    },
    sorun: "Sorun olursa bize yaz:",
  },
  en: {
    d_baslik: "Verify your email",
    d_giris: "Tap the button to verify the email address of the <b>@{h}</b> account.",
    d_dugme: "VERIFY MY EMAIL",
    s_baslik: "Set a new password",
    s_giris: "Enter a new password for <b>@{h}</b>. Once it changes, sessions on your other devices are signed out.",
    sifre: "New password (at least 6 characters)",
    sifre2: "New password again",
    s_dugme: "CHANGE MY PASSWORD",
    kod: "Code",
    oyun: "You can also type the code in the game.",
    sonuc: {
      d_tamam: ["iyi", "Your email is verified.", "You can go back to the game. If you forget your password, you can recover your account with this address."],
      s_tamam: ["iyi", "Your password was changed.", "Open the game and sign in with your username and new password."],
      zaten: ["iyi", "Your email is already verified.", ""],
      yanlis: ["kotu", "Wrong code.", "Open the link in the email again or type the code in the game."],
      suresi: ["kotu", "The code has expired.", "Request a new code in the game."],
      iptal: ["kotu", "The code was cancelled.", "Too many wrong attempts. Request a new code in the game."],
      yok: ["kotu", "There is no valid code.", "Request a new code in the game."],
      kisa: ["kotu", "Password must be at least 6 characters.", ""],
      uzun: ["kotu", "Password can be at most 64 characters.", ""],
      ayni_degil: ["kotu", "Passwords don't match.", ""],
      cok_deneme: ["kotu", "Too many attempts.", "For your security, wait 15 minutes and try again."],
      eksik: ["kotu", "The link is incomplete.", "Open the link in the email again."],
      hata: ["kotu", "Something went wrong.", "Please try again later."],
    },
    sorun: "Need help? Contact us:",
  },
};

const k = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export function webDili(req, url) {
  const q = url.searchParams.get("dil");
  if (q === "en" || q === "tr") return q;
  const a = String(req.headers.get("accept-language") || "").toLowerCase();
  return a.startsWith("tr") || (!a.includes("en") && a.includes("tr")) ? "tr" : a ? "en" : "tr";
}

// Form sayfası (GET). tur: "dogrula" | "sifirla"
export function kodFormHtml(tur, h, kod, dil) {
  const m = M[dil] || M.tr;
  const hh = k(String(h || "").replace(/^@/, "").toLowerCase().slice(0, 32));
  const kk = k(String(kod || "").replace(/\D/g, "").slice(0, 6));
  const yol = tur === "dogrula" ? "/eposta-dogrula" : "/sifre-sifirla";
  const gizli = `<input type="hidden" name="h" value="${hh}"><input type="hidden" name="k" value="${kk}"><input type="hidden" name="dil" value="${dil}">`;
  const govde = tur === "dogrula"
    ? `<h1>${m.d_baslik}</h1><p>${m.d_giris.replace("{h}", hh)}</p><form method="post" action="${yol}">${gizli}<div>${m.kod}: <span class="kod">${kk}</span></div><button type="submit">${m.d_dugme}</button></form>`
    : `<h1>${m.s_baslik}</h1><p>${m.s_giris.replace("{h}", hh)}</p><form method="post" action="${yol}">${gizli}
<label for="s1">${m.sifre}</label><input id="s1" type="password" name="sifre" minlength="6" maxlength="64" autocomplete="new-password" required>
<label for="s2">${m.sifre2}</label><input id="s2" type="password" name="sifre2" minlength="6" maxlength="64" autocomplete="new-password" required>
<button type="submit">${m.s_dugme}</button></form>`;
  return page(tur === "dogrula" ? m.d_baslik : m.s_baslik, `${STIL}${govde}<p><small>${m.oyun}</small></p><p>${m.sorun} <a href="mailto:${ILETISIM}">${ILETISIM}</a></p>`);
}

export function kodSonucHtml(tur, kod, dil) {
  const m = M[dil] || M.tr;
  const anahtar = kod === "tamam" ? (tur === "dogrula" ? "d_tamam" : "s_tamam") : kod;
  const [sinif, bas, alt] = m.sonuc[anahtar] || m.sonuc.hata;
  return page(bas, `${STIL}<div class="kutu ${sinif}"><h1 style="margin-top:0">${k(bas)}</h1>${alt ? `<p>${k(alt)}</p>` : ""}</div><p>${m.sorun} <a href="mailto:${ILETISIM}">${ILETISIM}</a></p>`);
}
