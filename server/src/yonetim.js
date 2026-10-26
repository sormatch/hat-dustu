// Yönetim sayfası (/yonetim): şikayetleri okuma, hesap arama, uyarı / yasak / ad sıfırlama / şikayet kapatma.
// Accounts nesnesinin içinde çalışır (accounts.js fetch -> yonetim(acc, req)); veriler aynı SQLite'ta.
//
// Güvenlik:
//   - Giriş anahtarı Worker gizli değişkeni env.YONETICI_ANAHTARI (canlıda: npx wrangler secret put YONETICI_ANAHTARI,
//     yerelde: server/.dev.vars). Tanımlı değilse ya da 16 karakterden kısaysa sayfa kapalıdır.
//   - Anahtar yalnızca POST gövdesinde (giriş formu) ya da "Authorization: Bearer ..." başlığında gelir; adres
//     çubuğunda asla. Girişten sonra tarayıcıya HttpOnly + SameSite=Strict oturum çerezi verilir (anahtar değil).
//   - Karşılaştırma sabit zamanlı (iki tarafın SHA-256 özeti bayt bayt XOR ile).
//   - Yanlış anahtar sınırı: aynı IP'den 15 dakikada 5, toplamda 30 yanlış -> 15 dakika kilit.
//   - Çerezle gelen her POST'ta aynı köken kontrolü (Origin / Sec-Fetch-Site / Referer) — CSRF'e karşı.

import { KALICI, UYARI_METNI, tarihTR, Accounts } from "./accounts.js";
import { tx } from "./metin.js";

const OTURUM_SURE = 2 * 3600000;
const PENCERE = 15 * 60000;
const IP_MAX = 5;
const TOPLAM_MAX = 30;
const SEBEP = { kufur: "Küfür", taciz: "Taciz", hile: "Hile", uygunsuz_ad: "Uygunsuz ad", diger: "Diğer" };
const ISLEMLER = {
  uyar: "Uyarıldı",
  yasak24: "24 saat yasak",
  yasak7: "7 gün yasak",
  yasakKalici: "Kalıcı yasak",
  yasakKaldir: "Yasak kaldırıldı",
  adSifirla: "Ad sıfırlandı",
  kapat: "Şikayet kapatıldı",
};

const kac = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const BASLIK = {
  "content-type": "text/html; charset=utf-8",
  "cache-control": "no-store",
  "x-frame-options": "DENY",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
};

function sayfa(govde, durum = 200, ek = {}) {
  const html = `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Yönetim — Hat Düştü</title><style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:0 auto;max-width:1280px;padding:18px 16px 60px;background:#111317;color:#e9e6df;line-height:1.45}
h1{color:#ffb020;font-size:24px;margin:0}h2{color:#ffcf8a;font-size:18px;margin:26px 0 8px}
.ust{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap}
table{border-collapse:collapse;width:100%;font-size:14px}th,td{border-top:1px solid #2c2f36;padding:7px 6px;text-align:left;vertical-align:top}th{color:#ffcf8a;font-weight:600}
.k{color:#9aa0a6;font-size:12px}.yasak{color:#ff7b6b;font-weight:600}.ok{background:#12301c;border:1px solid #2e7d4a;padding:10px 14px;border-radius:8px;margin:12px 0}
.hata{background:#3a1512;border:1px solid #a84432;padding:10px 14px;border-radius:8px;margin:12px 0}
form.i{display:inline}button{background:#2a2e36;color:#e9e6df;border:1px solid #444;border-radius:6px;padding:5px 8px;margin:2px 1px;font-size:12px;cursor:pointer}
button.t{border-color:#a84432;color:#ffb3a8}button.a{background:#ffb020;color:#1a1200;border:0;font-weight:700;padding:9px 14px;font-size:14px}
input[type=text],input[type=password],input[type=search]{padding:9px;border-radius:6px;border:1px solid #555;background:#0c0e11;color:#e9e6df;font-size:15px;min-width:260px}
.kutu{background:#1a1d23;border:1px solid #333;border-radius:10px;padding:18px;max-width:420px;margin:60px auto}
.bos{color:#9aa0a6;padding:10px 0}</style></head><body>${govde}</body></html>`;
  return new Response(html, { status: durum, headers: { ...BASLIK, ...ek } });
}

async function ozet(s) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(String(s))));
}

// Sabit zamanlı karşılaştırma: iki tarafın özeti (her zaman 32 bayt) bayt bayt XOR'lanır
async function anahtarDogru(dogru, gelen) {
  const a = await ozet(dogru);
  const b = await ozet(gelen);
  let fark = 0;
  for (let i = 0; i < a.length; i++) fark |= a[i] ^ b[i];
  return fark === 0;
}

function ipOf(req) {
  return (req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") || "?").split(",")[0].trim().slice(0, 64);
}

// Yanlış anahtar sınırı. Dönen: true = kilitli
function kilitli(acc, ip) {
  const now = Date.now();
  for (const k of [ip, "*"]) {
    const f = acc.yonetimHata.get(k);
    if (f && now - f.ts > PENCERE) acc.yonetimHata.delete(k);
  }
  const fi = acc.yonetimHata.get(ip);
  const ft = acc.yonetimHata.get("*");
  return (fi && fi.n >= IP_MAX) || (ft && ft.n >= TOPLAM_MAX);
}

function hataSay(acc, ip) {
  const now = Date.now();
  for (const k of [ip, "*"]) {
    const f = acc.yonetimHata.get(k) || { n: 0, ts: now };
    f.n += 1;
    acc.yonetimHata.set(k, f);
  }
  if (acc.yonetimHata.size > 5000) acc.yonetimHata.clear();
}

// Anahtar kontrolü (deneme sınırıyla). Dönen: "ok" | "yanlis" | "kilit"
async function anahtarKontrol(acc, req, gelen) {
  const ip = ipOf(req);
  if (kilitli(acc, ip)) return "kilit";
  if (gelen && (await anahtarDogru(acc.env.YONETICI_ANAHTARI, gelen))) return "ok";
  hataSay(acc, ip);
  return kilitli(acc, ip) ? "kilit" : "yanlis";
}

function cerez(req, ad) {
  for (const p of (req.headers.get("cookie") || "").split(";")) {
    const [k, ...v] = p.trim().split("=");
    if (k === ad) return v.join("=");
  }
  return "";
}

function oturumGecerli(acc, sid) {
  if (!sid) return false;
  const bitis = acc.yonetimOturum.get(sid);
  if (!bitis) return false;
  if (bitis < Date.now()) {
    acc.yonetimOturum.delete(sid);
    return false;
  }
  return true;
}

// CSRF: çerezle gelen POST aynı kökenden mi
function ayniKoken(req, url) {
  const o = req.headers.get("origin");
  if (o) return o === url.origin;
  const s = req.headers.get("sec-fetch-site");
  if (s) return s === "same-origin";
  const r = req.headers.get("referer");
  if (r) {
    try {
      return new URL(r).origin === url.origin;
    } catch {}
  }
  return false;
}

// Kim olduğu: "@kullanici (ad)" ya da "misafir #12"
function kimlik(acc, token) {
  if (!token) return { metin: "—", yasak: null, id: 0 };
  const u = acc.rows(`SELECT rowid AS id, handle, name FROM users WHERE token = ?`, token)[0];
  if (!u) return { metin: "(silinmiş hesap)", yasak: null, id: 0 };
  const metin = u.handle ? `@${u.handle}${u.name && u.name !== u.handle ? " (" + u.name + ")" : ""}` : `misafir #${u.id}${u.name ? " (" + u.name + ")" : ""}`;
  return { metin, yasak: acc.yasak(token), id: u.id };
}

function yasakYazi(y) {
  if (!y) return "";
  return y.kalici ? "KALICI YASAK" : `yasaklı: ${tarihTR(y.bitis)}'e kadar`;
}

function islemDugmeleri(gizli, raporlu, sadeceKapat = false) {
  const b = (islem, yazi, tehlike) => `<form class="i" method="post" action="/yonetim/islem">${gizli}<input type="hidden" name="islem" value="${islem}"><button${tehlike ? ' class="t"' : ""}>${yazi}</button></form>`;
  if (sadeceKapat) return b("kapat", "Şikayeti kapat") + '<br><span class="k">hesap bilinmiyor</span>';
  return [
    b("uyar", "Uyar"),
    b("yasak24", "24 saat yasak", 1),
    b("yasak7", "7 gün yasak", 1),
    b("yasakKalici", "Kalıcı yasak", 1),
    b("yasakKaldir", "Yasağı kaldır"),
    b("adSifirla", "Adı sıfırla"),
    raporlu ? b("kapat", "Şikayeti kapat") : "",
  ].join("");
}

function panel(acc, url, mesaj) {
  const ara = (url.searchParams.get("ara") || "").trim().slice(0, 40);
  const geri = `<input type="hidden" name="ara" value="${kac(ara)}">`;
  const raporlar = acc.rows(`SELECT id, from_token, target_token, target, target_ad, room, reason, note, ts FROM reports WHERE COALESCE(durum, 'acik') = 'acik' ORDER BY ts DESC LIMIT 200`);
  const sayac = (t) => (t ? acc.rows(`SELECT COUNT(*) AS n FROM reports WHERE target_token = ?`, t)[0].n : 0);
  let govde = `<div class="ust"><h1>Hat Düştü — Yönetim</h1><form class="i" method="post" action="/yonetim/cikis"><button>Çıkış</button></form></div>`;
  if (mesaj) govde += `<div class="${mesaj.hata ? "hata" : "ok"}">${kac(mesaj.metin)}</div>`;
  govde += `<h2>Bekleyen şikayetler (${raporlar.length})</h2>`;
  if (!raporlar.length) govde += `<div class="bos">Bekleyen şikayet yok.</div>`;
  else {
    govde += `<table><tr><th>Tarih</th><th>Şikayet eden</th><th>Şikayet edilen</th><th>Sebep</th><th>Oda</th><th>Maçtaki ad</th><th>Toplam şikayet</th><th>İşlem</th></tr>`;
    for (const r of raporlar) {
      const eden = kimlik(acc, r.from_token);
      const edilen = kimlik(acc, r.target_token);
      const gizli = `<input type="hidden" name="rapor" value="${r.id}">${geri}`;
      govde += `<tr><td>${kac(tarihTR(r.ts))}</td><td>${kac(eden.metin)}</td><td>${kac(edilen.metin)}${edilen.yasak ? `<br><span class="yasak">${kac(yasakYazi(edilen.yasak))}</span>` : ""}</td>`
        + `<td>${kac(SEBEP[r.reason] || r.reason)}${r.note ? `<br><span class="k">${kac(r.note)}</span>` : ""}</td><td>${kac(r.room || "—")}</td><td>${kac(r.target_ad || r.target || "—")}</td>`
        + `<td>${sayac(r.target_token)}</td><td>${islemDugmeleri(gizli, true, !r.target_token)}</td></tr>`;
    }
    govde += `</table>`;
  }
  govde += `<h2>Hesap ara</h2><form method="get" action="/yonetim"><input type="search" name="ara" value="${kac(ara)}" placeholder="kullanıcı adı ya da ad" maxlength="40"> <button class="a">Ara</button></form>`;
  if (ara) {
    const q = "%" + ara.replace(/^@/, "").replace(/[!%_]/g, (c) => "!" + c) + "%"; // LIKE özel karakterleri ! ile kaçışlı
    const bulunan = acc.rows(`SELECT rowid AS id, token, handle, name FROM users WHERE handle LIKE ? ESCAPE '!' OR name LIKE ? ESCAPE '!' ORDER BY handle IS NULL, handle LIMIT 50`, q, q);
    if (!bulunan.length) govde += `<div class="bos">Sonuç yok.</div>`;
    else {
      govde += `<table><tr><th>#</th><th>Kullanıcı adı</th><th>Ad</th><th>Durum</th><th>Toplam şikayet</th><th>İşlem</th></tr>`;
      for (const u of bulunan) {
        const y = acc.yasak(u.token);
        const gizli = `<input type="hidden" name="hesap" value="${u.id}">${geri}`;
        govde += `<tr><td>${u.id}</td><td>${u.handle ? "@" + kac(u.handle) : "misafir"}</td><td>${kac(u.name || "")}</td><td>${y ? `<span class="yasak">${kac(yasakYazi(y))}</span>` : "aktif"}</td><td>${sayac(u.token)}</td><td>${islemDugmeleri(gizli, false)}</td></tr>`;
      }
      govde += `</table>`;
    }
  }
  return sayfa(govde);
}

function girisSayfasi(hata, durum = 200) {
  return sayfa(`<div class="kutu"><h1>Yönetim girişi</h1>${hata ? `<div class="hata">${kac(hata)}</div>` : ""}
<form method="post" action="/yonetim/giris" autocomplete="off"><p><input type="password" name="anahtar" placeholder="Yönetici anahtarı" required autofocus></p><button class="a">Giriş</button></form></div>`, durum);
}

// Hesaba işlem uygular. Dönen: sonuç metni
function uygula(acc, islem, token, raporId) {
  const now = Date.now();
  const online = acc.state.getWebSockets().filter((w) => acc.info(w).token === token);
  switch (islem) {
    case "uyar":
      if (online.length) for (const w of online) acc.send(w, { t: "uyari", ...tx(UYARI_METNI) });
      else acc.sql.exec(`UPDATE users SET uyari = 1 WHERE token = ?`, token);
      break;
    case "yasak24":
    case "yasak7":
    case "yasakKalici": {
      const bitis = islem === "yasakKalici" ? KALICI : now + (islem === "yasak24" ? 24 : 7 * 24) * 3600000;
      acc.sql.exec(`UPDATE users SET yasak_bitis = ?, yasak_neden = ? WHERE token = ?`, bitis, raporId ? "sikayet #" + raporId : "yonetim", token);
      const y = acc.yasak(token);
      for (const w of online) {
        acc.send(w, { t: "yasak", bitis: y.kalici ? 0 : y.bitis, kalici: y.kalici, ...Accounts.yasakMetni(y) });
        try {
          w.close(4003, "yasak");
        } catch {}
      }
      break;
    }
    case "yasakKaldir":
      acc.sql.exec(`UPDATE users SET yasak_bitis = 0, yasak_neden = NULL WHERE token = ?`, token);
      break;
    case "adSifirla": {
      const ad = "Oyuncu" + String(1000 + Math.floor(Math.random() * 9000));
      const u = acc.rows(`SELECT handle, profil FROM users WHERE token = ?`, token)[0] || {};
      let profil = null;
      try {
        profil = u.profil ? JSON.parse(u.profil) : null;
      } catch {}
      if (profil && typeof profil === "object") profil.ad = ad;
      acc.sql.exec(`UPDATE users SET name = ?, profil = COALESCE(?, profil) WHERE token = ?`, ad, profil ? JSON.stringify(profil) : null, token);
      for (const w of online) {
        acc.send(w, { t: "ad_sifirlandi", ad });
        acc.send(w, acc.me(token));
      }
      if (u.handle) acc.refreshFriendsOf(u.handle);
      break;
    }
  }
  return ISLEMLER[islem];
}

export async function yonetim(acc, req) {
  const url = new URL(req.url);
  const yol = url.pathname;
  if (!acc.env.YONETICI_ANAHTARI || String(acc.env.YONETICI_ANAHTARI).length < 16) {
    return sayfa(`<div class="kutu"><h1>Yönetim kapalı</h1><p>YONETICI_ANAHTARI tanımlı değil (en az 16 karakter).</p></div>`, 503);
  }
  // kimlik: Authorization: Bearer <anahtar> (araçlar için) ya da oturum çerezi (tarayıcı)
  const auth = req.headers.get("authorization") || "";
  let girisli = false;
  if (auth.startsWith("Bearer ")) {
    const k = await anahtarKontrol(acc, req, auth.slice(7).trim());
    if (k === "kilit") return sayfa(`<div class="kutu"><div class="hata">Çok fazla yanlış deneme. 15 dakika sonra tekrar dene.</div></div>`, 429);
    if (k !== "ok") return sayfa(`<div class="kutu"><div class="hata">Anahtar yanlış.</div></div>`, 401);
    girisli = true;
  } else if (oturumGecerli(acc, cerez(req, "yonetim"))) {
    girisli = true;
  }
  // çerezle (tarayıcıdan) gelen her POST aynı kökenden olmalı
  if (req.method === "POST" && !auth.startsWith("Bearer ") && !ayniKoken(req, url)) {
    return sayfa(`<div class="kutu"><div class="hata">İstek reddedildi (farklı köken).</div></div>`, 403);
  }

  if (yol === "/yonetim/giris" && req.method === "POST") {
    let form;
    try {
      form = await req.formData();
    } catch {
      return girisSayfasi("Anahtarı yaz.", 400);
    }
    const k = await anahtarKontrol(acc, req, String(form.get("anahtar") || ""));
    if (k === "kilit") return girisSayfasi("Çok fazla yanlış deneme. 15 dakika sonra tekrar dene.", 429);
    if (k !== "ok") return girisSayfasi("Anahtar yanlış.", 401);
    const sid = Accounts.hex(crypto.getRandomValues(new Uint8Array(32)));
    acc.yonetimOturum.set(sid, Date.now() + OTURUM_SURE);
    if (acc.yonetimOturum.size > 200) for (const [s, b] of acc.yonetimOturum) if (b < Date.now()) acc.yonetimOturum.delete(s);
    const guvenli = url.protocol === "https:" ? "; Secure" : "";
    return new Response(null, { status: 303, headers: { location: "/yonetim", "set-cookie": `yonetim=${sid}; HttpOnly; SameSite=Strict; Path=/yonetim; Max-Age=${OTURUM_SURE / 1000}${guvenli}`, "cache-control": "no-store" } });
  }
  if (yol === "/yonetim/cikis" && req.method === "POST") {
    acc.yonetimOturum.delete(cerez(req, "yonetim"));
    return new Response(null, { status: 303, headers: { location: "/yonetim", "set-cookie": "yonetim=; HttpOnly; SameSite=Strict; Path=/yonetim; Max-Age=0", "cache-control": "no-store" } });
  }
  if (!girisli) return girisSayfasi("", yol === "/yonetim" && req.method === "GET" ? 200 : 401);

  if (yol === "/yonetim/islem" && req.method === "POST") {
    const form = await req.formData();
    const islem = String(form.get("islem") || "");
    const ara = String(form.get("ara") || "").slice(0, 40);
    const geri = (metin, hata) => {
      const q = new URLSearchParams();
      if (ara) q.set("ara", ara);
      q.set(hata ? "hata" : "ok", metin);
      return new Response(null, { status: 303, headers: { location: "/yonetim?" + q.toString(), "cache-control": "no-store" } });
    };
    if (!ISLEMLER[islem]) return geri("Bilinmeyen işlem.", 1);
    const raporId = Number(form.get("rapor")) || 0;
    const hesapId = Number(form.get("hesap")) || 0;
    let token = "";
    if (raporId) token = (acc.rows(`SELECT target_token FROM reports WHERE id = ?`, raporId)[0] || {}).target_token || "";
    else if (hesapId) token = (acc.rows(`SELECT token FROM users WHERE rowid = ?`, hesapId)[0] || {}).token || "";
    let sonuc = "";
    if (islem !== "kapat") {
      if (!token) return geri("Bu şikayette hesap bilinmiyor; yalnızca kapatılabilir.", 1);
      sonuc = uygula(acc, islem, token, raporId);
    } else sonuc = ISLEMLER.kapat;
    if (raporId) acc.sql.exec(`UPDATE reports SET durum = 'kapali', islem = ? WHERE id = ?`, islem, raporId);
    const kim = kimlik(acc, token);
    return geri(`${sonuc}${token ? ": " + kim.metin : ""}`, 0);
  }
  if (yol === "/yonetim" && req.method === "GET") {
    const ok = url.searchParams.get("ok");
    const hata = url.searchParams.get("hata");
    return panel(acc, url, ok ? { metin: ok } : hata ? { metin: hata, hata: true } : null);
  }
  return sayfa(`<div class="kutu">Bulunamadı.</div>`, 404);
}
