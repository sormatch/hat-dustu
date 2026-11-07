// Yönetim sayfası (/yonetim): şikayetleri okuma, hesap arama, uyarı / yasak / ad sıfırlama / şikayet kapatma.
// Accounts nesnesinin içinde çalışır (accounts.js fetch -> yonetim(acc, req)); veriler aynı SQLite'ta.
//
// Güvenlik:
//   - Giriş anahtarı Worker gizli değişkeni env.YONETICI_ANAHTARI (canlıda: npx wrangler secret put YONETICI_ANAHTARI,
//     yerelde: server/.dev.vars). Tanımlı değilse ya da 16 karakterden kısaysa sayfa kapalıdır.
//   - Anahtar yalnızca POST gövdesinde (giriş formu) ya da "Authorization: Bearer ..." başlığında gelir; adres
//     çubuğunda asla. Girişten sonra tarayıcıya HttpOnly + SameSite=Strict oturum çerezi verilir (anahtar değil).
//   - Karşılaştırma sabit zamanlı (iki tarafın SHA-256 özeti bayt bayt XOR ile).
//   - Yanlış anahtar sınırı: aynı IP'den (IPv6'da aynı /64 ağından) 15 dakikada 5 yanlış -> o IP 15 dakika kilitli.
//     (eskiden toplam 30 yanlışta herkes kilitleniyordu: başkası yanlış deneyerek yöneticiyi dışarıda bırakabiliyordu)
//   - Çerezle gelen her POST'ta aynı köken kontrolü (Origin / Sec-Fetch-Site / Referer) — CSRF'e karşı.

import { KALICI, UYARI_METNI, tarihTR, Accounts } from "./accounts.js";
import { tx } from "./metin.js";

const OTURUM_SURE = 2 * 3600000;
const PENCERE = 15 * 60000;
const IP_MAX = 5;
const HATA_KAYIT_MAX = 5000; // sayaç tablosu sınırı (dolunca en eski kayıt atılır)
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
  "referrer-policy": "same-origin", // no-referrer olursa tarayıcı form POST unda Origin: null yollar, ayniKoken girişi reddeder
  "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
};

// Sayfa iskeleti ve görünüm. Koyu tema; kartlar "kalınlığı" olan 3D levhalar, grafik sütunları üst ve yan yüzlü 3D kutular.
// yenile: saniye (Canlı sekmesi kendini yeniler; betik yasak olduğundan meta refresh)
const STIL = `
:root{--zemin:#0c0e13;--yuzey:#161a23;--yuzey2:#1c212c;--cizgi:#262c39;--metin:#ece8df;--ikinci:#a7adb8;--sonuk:#6f7684;
--amber:#ffb020;--amber2:#ffcf8a;--s1:#d95926;--s2:#3987e5;--yesil:#3ccf7a;--kirmizi:#ff6b5b;--kalin:#07080c}
*{box-sizing:border-box}
body{font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;margin:0 auto;max-width:1320px;padding:20px 16px 70px;color:var(--metin);line-height:1.45;
background:radial-gradient(1200px 600px at 85% -10%,rgba(255,176,32,.10),transparent 60%),radial-gradient(900px 500px at -10% 20%,rgba(57,135,229,.10),transparent 60%),var(--zemin);background-attachment:fixed;min-height:100vh}
a{color:inherit}h2{color:var(--amber2);font-size:15px;letter-spacing:.04em;text-transform:uppercase;margin:0 0 14px}
.ust{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:18px}
.logo{display:flex;flex-direction:column}
.l1{font-size:30px;font-weight:900;letter-spacing:.06em;color:var(--amber);transform:perspective(500px) rotateX(18deg);transform-origin:bottom;
text-shadow:0 1px 0 #d48b00,0 2px 0 #b97700,0 3px 0 #9d6400,0 4px 0 #815200,0 5px 0 #664000,0 12px 18px rgba(0,0,0,.7)}
.l2{color:var(--ikinci);font-size:13px;margin-top:6px;letter-spacing:.08em}
.sekmeler{display:flex;gap:6px;flex-wrap:wrap;padding:6px;background:linear-gradient(180deg,#151922,#10131a);border:1px solid var(--cizgi);border-radius:16px;
box-shadow:0 5px 0 var(--kalin),0 18px 30px -12px rgba(0,0,0,.7);margin-bottom:22px}
.sekmeler a{text-decoration:none;color:var(--ikinci);padding:10px 16px;border-radius:11px;font-weight:600;font-size:14px;display:flex;align-items:center;gap:8px;transition:transform .15s,background .15s}
.sekmeler a:hover{color:var(--metin);background:#1d2230;transform:translateY(-1px)}
.sekmeler a.secili{color:#1a1200;background:linear-gradient(180deg,#ffc55a,#ffa800);box-shadow:0 4px 0 #a86a00,0 10px 18px -6px rgba(255,176,32,.55);transform:translateY(-2px)}
.sekmeler a i{font-style:normal;font-size:11px;font-weight:800;padding:1px 7px;border-radius:99px;background:#2a3040;color:var(--metin)}
.sekmeler a i.yesil{background:var(--yesil);color:#05210f}.sekmeler a i.kirmizi{background:var(--kirmizi);color:#2a0400}
.sekmeler a.secili i{background:#1a1200;color:var(--amber)}
.pano{background:linear-gradient(165deg,var(--yuzey2),var(--yuzey));border:1px solid var(--cizgi);border-radius:18px;padding:18px 18px 20px;margin-bottom:22px;
box-shadow:inset 0 1px 0 rgba(255,255,255,.05),0 7px 0 var(--kalin),0 26px 40px -20px rgba(0,0,0,.85)}
.pano-b{display:flex;justify-content:space-between;align-items:baseline;gap:12px;flex-wrap:wrap}
.kpiler{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:16px;margin-bottom:24px;perspective:900px}
.kpi{position:relative;padding:16px 16px 14px;border-radius:16px;background:linear-gradient(160deg,#1f2531,#151922);border:1px solid var(--cizgi);
box-shadow:inset 0 1px 0 rgba(255,255,255,.06),0 8px 0 var(--kalin),0 22px 30px -14px rgba(0,0,0,.8);transform:rotateX(7deg);transform-origin:bottom;transition:transform .2s,box-shadow .2s}
.kpi:hover{transform:rotateX(0) translateY(-4px);box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 12px 0 var(--kalin),0 30px 40px -16px rgba(0,0,0,.85)}
.kpi::before{content:"";position:absolute;left:14px;right:14px;top:0;height:3px;border-radius:0 0 4px 4px;background:var(--amber);opacity:.8}
.kpi.canli::before{background:var(--yesil)}.kpi.vurgu::before{background:var(--s1)}
.kpi-b{color:var(--ikinci);font-size:12.5px;font-weight:600}.kpi-d{font-size:38px;font-weight:800;line-height:1.1;margin:6px 0 4px;letter-spacing:-.01em}
.kpi-a{color:var(--sonuk);font-size:12px}
.kpi.canli .kpi-d::after{content:"";display:inline-block;width:10px;height:10px;border-radius:50%;background:var(--yesil);margin-left:10px;vertical-align:middle;box-shadow:0 0 0 4px rgba(60,207,122,.18)}
.lejant{display:flex;gap:16px;color:var(--ikinci);font-size:13px;flex-wrap:wrap}.lejant span{display:flex;align-items:center;gap:7px}
.k1,.k2{display:inline-block;width:12px;height:12px;border-radius:3px;background:var(--s1)}.k2{background:var(--s2)}
.sahne{perspective:1100px;padding:18px 6px 4px 34px;overflow:hidden}
.zemin{position:relative;transform:rotateX(14deg);transform-origin:bottom;margin-bottom:34px;
background:linear-gradient(180deg,transparent,rgba(255,176,32,.035));border-bottom:2px solid #39404f}
.cizgi{position:absolute;left:0;right:0;border-top:1px dashed #262c39;height:0}
.cizgi span{position:absolute;left:-32px;top:-9px;font-size:11px;color:var(--sonuk);width:26px;text-align:right}
.sutunlar{position:absolute;inset:0;display:grid;grid-template-columns:repeat(14,1fr);align-items:end;gap:4px}
.hucre{position:relative;height:100%;display:flex;flex-direction:column;justify-content:flex-end;align-items:center;cursor:default}
.hucre:hover{background:linear-gradient(180deg,transparent,rgba(255,255,255,.04))}
.sutun{position:relative;width:min(26px,62%);display:flex;flex-direction:column-reverse;gap:2px;margin-right:8px}
.dilim{position:relative;display:block;width:100%}
.dilim.s1{background:linear-gradient(90deg,#e8692f,var(--s1))}.dilim.s2{background:linear-gradient(90deg,#4b97f0,var(--s2))}
.dilim::after{content:"";position:absolute;left:100%;top:0;width:8px;height:100%;transform:skewY(-45deg);transform-origin:0 100%;background:inherit;filter:brightness(.55)}
.dilim:last-of-type::before{content:"";position:absolute;left:0;bottom:100%;width:100%;height:8px;transform:skewX(-45deg);transform-origin:0 100%;background:inherit;filter:brightness(1.35)}
.sifir{display:block;width:100%;height:2px;background:#39404f}
.deger{position:absolute;bottom:calc(100% + 12px);left:50%;transform:translateX(-35%);font-size:13px;color:var(--metin)}
.gun{position:absolute;top:calc(100% + 8px);font-size:11px;color:var(--sonuk);white-space:nowrap}
.hucre.bugun .gun{color:var(--amber2);font-weight:700}
.ipucu{position:absolute;bottom:calc(100% + 6px);left:50%;transform:translate(-50%,6px);opacity:0;pointer-events:none;transition:.15s;z-index:5;white-space:nowrap;
background:#0e1117;border:1px solid #333b4b;border-radius:10px;padding:8px 11px;font-size:12.5px;box-shadow:0 10px 24px rgba(0,0,0,.6);display:flex;flex-direction:column;gap:3px}
.ipucu span{display:flex;align-items:center;gap:6px;color:var(--ikinci)}.ipucu span b{color:var(--metin);margin-left:auto;padding-left:10px}
.hucre:hover .ipucu{opacity:1;transform:translate(-50%,0)}
.hucre:first-child .ipucu,.hucre:nth-child(2) .ipucu{left:0;transform:translate(0,6px)}.hucre:first-child:hover .ipucu,.hucre:nth-child(2):hover .ipucu{transform:translate(0,0)}
.hucre:last-child .ipucu,.hucre:nth-last-child(2) .ipucu{left:auto;right:0;transform:translate(0,6px)}.hucre:last-child:hover .ipucu,.hucre:nth-last-child(2):hover .ipucu{transform:translate(0,0)}
.iki{display:grid;grid-template-columns:1.3fr 1fr;gap:22px}.iki>.pano{margin-bottom:0}
.cubuk{display:grid;grid-template-columns:minmax(90px,170px) 1fr 74px;gap:10px;align-items:center;padding:6px 0;font-size:14px}
.cubuk .ad{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.cubuk .sn{text-align:right;color:var(--ikinci);font-variant-numeric:tabular-nums}
.iz{height:12px;background:#11141b;border-radius:3px;position:relative}
.iz i{display:block;height:100%;border-radius:0 4px 4px 0;background:linear-gradient(90deg,#a85a00,var(--amber));box-shadow:0 3px 0 #6b3b00}
.mini{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.mini div{background:#12151d;border:1px solid var(--cizgi);border-radius:12px;padding:12px;box-shadow:0 4px 0 var(--kalin)}
.mini b{display:block;font-size:26px}.mini span{color:var(--ikinci);font-size:12.5px}
.odalar{display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:16px;perspective:1000px}
.oda{background:linear-gradient(160deg,#212839,#171b25);border:1px solid #2d3445;border-radius:16px;padding:14px;transform:rotateX(5deg);transform-origin:bottom;
box-shadow:inset 0 1px 0 rgba(255,255,255,.06),0 7px 0 var(--kalin),0 20px 26px -14px rgba(0,0,0,.8);transition:transform .2s}
.oda:hover{transform:rotateX(0) translateY(-3px)}
.oda-u{display:flex;justify-content:space-between;gap:10px;align-items:flex-start}.oda-ad{font-weight:700;font-size:16px;margin-bottom:6px}.oda-ad b{color:var(--amber)}
.oda-kisi{text-align:center;background:#0f1218;border-radius:12px;padding:6px 12px;box-shadow:inset 0 2px 6px rgba(0,0,0,.6)}.oda-kisi b{display:block;font-size:24px;line-height:1}.oda-kisi span{font-size:11px;color:var(--sonuk)}
.oda-a{display:flex;flex-wrap:wrap;gap:6px 14px;color:var(--ikinci);font-size:12.5px;margin-top:12px;border-top:1px solid #2a3141;padding-top:10px}
.rozet{display:inline-block;font-size:12px;font-weight:700;padding:3px 9px;border-radius:99px}
.rozet.oyunda{background:rgba(60,207,122,.15);color:var(--yesil)}.rozet.lobi{background:rgba(255,176,32,.14);color:var(--amber2)}.rozet.bitti{background:#2a3040;color:var(--ikinci)}
.cipler{display:flex;flex-wrap:wrap;gap:6px;margin-top:12px}
.cip{display:inline-flex;align-items:center;gap:6px;background:#11151d;border:1px solid #2b3242;border-radius:99px;padding:3px 10px 3px 3px;font-size:13px;margin:2px 3px 2px 0;white-space:nowrap}
.cip.kucuk{padding:2px 9px;font-size:12px}.cip.sonuk{color:var(--ikinci)}
.av{font-style:normal;width:22px;height:22px;border-radius:50%;display:inline-grid;place-items:center;font-size:11px;font-weight:800;color:#1a1200;background:linear-gradient(160deg,#ffd27a,#ff9d00);box-shadow:0 2px 0 #9a5d00}
.cip.sonuk .av{background:linear-gradient(160deg,#5b6474,#3a414f);color:#e9e6df;box-shadow:0 2px 0 #222}
.nokta{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--yesil);box-shadow:0 0 0 3px rgba(60,207,122,.2)}
.maclar{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:16px}
.mac{background:linear-gradient(160deg,#1f2533,#161a23);border:1px solid #2b3242;border-radius:16px;padding:14px;box-shadow:0 6px 0 var(--kalin),0 18px 24px -14px rgba(0,0,0,.8)}
.mac-u{display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap;align-items:center}
.etk1,.etk2{font-size:12px;font-weight:700;padding:3px 9px;border-radius:99px;background:rgba(217,89,38,.16);color:#ff9a6c}.etk2{background:rgba(57,135,229,.16);color:#8fbcf5}
.kazanan{display:flex;gap:12px;align-items:center;margin:12px 0 8px;padding:10px 12px;border-radius:12px;background:linear-gradient(90deg,rgba(255,176,32,.16),transparent)}
.kazanan b{display:block;font-size:18px}.tac{font-style:normal;font-size:26px;color:var(--amber);text-shadow:0 2px 0 #8a5600,0 6px 12px rgba(255,176,32,.35)}
.siralama{list-style:none;margin:0;padding:0;font-size:13.5px}.siralama li{display:flex;gap:6px;padding:3px 0;border-bottom:1px solid #222836}
.siralama .s{color:var(--sonuk);width:22px}.siralama .puan{margin-left:auto;color:var(--ikinci);font-variant-numeric:tabular-nums}
.mini.dort{grid-template-columns:repeat(4,1fr)}.cokme .aciklama{color:var(--ikinci);font-size:13px;margin:10px 0}
.etk{font-size:12px;font-weight:700;padding:3px 9px;border-radius:99px}.etk.bellek{background:rgba(255,107,91,.16);color:#ff9a8f}.etk.ani{background:rgba(255,176,32,.15);color:var(--amber2)}.etk.acilis{background:rgba(57,135,229,.16);color:#8fbcf5}
.bilgi{display:grid;grid-template-columns:1fr 1fr;gap:8px 12px}.bilgi div{display:flex;flex-direction:column}.bilgi b{font-size:13.5px;font-weight:600}
.son-hata{margin-top:10px;display:flex;flex-direction:column;gap:4px}code{font-family:ui-monospace,Consolas,monospace;font-size:12px;background:#0d1016;border:1px solid #232937;border-radius:6px;padding:3px 6px;color:#ffd9a0;word-break:break-all}
.mac-a{display:flex;gap:14px;flex-wrap:wrap;color:var(--ikinci);font-size:12.5px;margin-top:10px}
.tablo{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:14px}
th,td{border-top:1px solid var(--cizgi);padding:9px 8px;text-align:left;vertical-align:top}th{color:var(--amber2);font-weight:600;font-size:12.5px;white-space:nowrap}
tr:hover td{background:rgba(255,255,255,.02)}
.k{color:var(--sonuk);font-size:12.5px}.yenile{text-align:right;margin:-8px 0 12px}.yesil{color:var(--yesil)}.kirmizi{color:var(--kirmizi)}
.yasak{color:var(--kirmizi);font-weight:600}
.ok{background:#12301c;border:1px solid #2e7d4a;padding:10px 14px;border-radius:10px;margin:0 0 18px}
.hata{background:#3a1512;border:1px solid #a84432;padding:10px 14px;border-radius:10px;margin:0 0 18px}
form.i{display:inline}form.ara{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:8px}
button{background:#232936;color:var(--metin);border:1px solid #3a4253;border-radius:8px;padding:6px 10px;margin:2px 1px;font-size:12.5px;cursor:pointer;box-shadow:0 3px 0 var(--kalin)}
button:active{transform:translateY(2px);box-shadow:0 1px 0 var(--kalin)}
button.t{border-color:#a84432;color:#ffb3a8}button.a{background:linear-gradient(180deg,#ffc55a,#ffa800);color:#1a1200;border:0;font-weight:800;padding:10px 16px;font-size:14px;box-shadow:0 4px 0 #a86a00}
input[type=text],input[type=password],input[type=search]{padding:10px 12px;border-radius:10px;border:1px solid #3a4253;background:#0b0d12;color:var(--metin);font-size:15px;min-width:260px;max-width:100%}
.kutu{background:linear-gradient(165deg,var(--yuzey2),var(--yuzey));border:1px solid var(--cizgi);border-radius:18px;padding:22px;max-width:420px;margin:70px auto;box-shadow:0 8px 0 var(--kalin),0 30px 50px -20px rgba(0,0,0,.9)}
.kutu h1{color:var(--amber);font-size:22px;margin:0 0 12px}
.bos{color:var(--sonuk);padding:10px 0}
@media (max-width:760px){.iki{grid-template-columns:1fr}.mini.dort{grid-template-columns:1fr 1fr}.l1{font-size:24px}.kpiler{grid-template-columns:1fr 1fr;gap:12px}.kpi{padding:13px 12px 11px}.kpi-d{font-size:28px}.sekmeler a{padding:8px 11px;font-size:13px}
.sutunlar{gap:1px}.sutun{margin-right:5px}.dilim::after{width:5px}.dilim:last-of-type::before{height:5px}.hucre:nth-child(even) .gun{visibility:hidden}.sahne{padding-left:28px}
input[type=search]{min-width:0;flex:1}}
@media (prefers-reduced-motion:reduce){*{transition:none!important}.kpi,.oda,.zemin{transform:none}}`;

function sayfa(govde, durum = 200, ek = {}, yenile = 0) {
  const html = `<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">${yenile ? `<meta http-equiv="refresh" content="${yenile}">` : ""}<title>Yönetim — Hat Düştü</title><style>${STIL}</style></head><body>${govde}</body></html>`;
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

// Sayaç anahtarı: IPv4 olduğu gibi, IPv6 ilk 4 grup (/64: tek bağlantının adres havuzu)
function ipAnahtar(ip) {
  return ip.includes(":") ? ip.toLowerCase().split(":").slice(0, 4).join(":") : ip;
}

// Yanlış anahtar sınırı (yalnız IP başına). Dönen: true = kilitli
function kilitli(acc, ip) {
  const k = ipAnahtar(ip);
  const f = acc.yonetimHata.get(k);
  if (f && Date.now() - f.ts > PENCERE) acc.yonetimHata.delete(k);
  const fi = acc.yonetimHata.get(k);
  return !!(fi && fi.n >= IP_MAX);
}

function hataSay(acc, ip) {
  const k = ipAnahtar(ip);
  const f = acc.yonetimHata.get(k) || { n: 0, ts: Date.now() };
  f.n += 1;
  acc.yonetimHata.delete(k);
  acc.yonetimHata.set(k, f);
  while (acc.yonetimHata.size > HATA_KAYIT_MAX) acc.yonetimHata.delete(acc.yonetimHata.keys().next().value);
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

// ---------------- Panel: sekmeli analiz sayfası (Genel bakış · Canlı · Oyuncular · Maçlar · Şikayetler · Hatalar) ----------------
// Betik yok (CSP: script yasak): sekmeler ?sekme= bağlantısı, 3D görünüm yalnız CSS, ipuçları :hover ile.
const GUN_MS = 24 * 3600000;
const TR_OFSET = 3 * 3600000; // Türkiye saati (UTC+3)
const gunBasi = (ts) => Math.floor((ts + TR_OFSET) / GUN_MS) * GUN_MS - TR_OFSET;
const AYLAR = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"];
const SEKMELER = [
  ["ozet", "Genel bakış"],
  ["canli", "Canlı"],
  ["oyuncular", "Oyuncular"],
  ["maclar", "Maçlar"],
  ["sikayet", "Şikayetler"],
  ["hatalar", "Hatalar"],
];
const CANLI_SURE = 90000; // bu kadar süredir sinyal gelmeyen oda kapanmış sayılır (oda 30 sn'de bir bildirir)

function once(ts, now = Date.now()) {
  if (!ts) return "—";
  const s = Math.max(0, Math.round((now - ts) / 1000));
  if (s < 45) return "şimdi";
  const dk = Math.round(s / 60);
  if (dk < 60) return `${dk} dk önce`;
  const sa = Math.round(dk / 60);
  if (sa < 24) return `${sa} sa önce`;
  return `${Math.round(sa / 24)} gün önce`;
}

function sureYaz(sn) {
  sn = Math.max(0, Math.round(sn || 0));
  if (sn < 60) return `${sn} sn`;
  const dk = Math.floor(sn / 60);
  if (dk < 60) return `${dk} dk`;
  return `${Math.floor(dk / 60)} sa ${dk % 60} dk`;
}

function saatYaz(ts) {
  const d = new Date(ts + TR_OFSET);
  return `${d.getUTCDate()} ${AYLAR[d.getUTCMonth()]} ${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")}`;
}

const jsonOku = (s, v) => {
  try {
    return s ? JSON.parse(s) ?? v : v;
  } catch {
    return v;
  }
};
const sayi = (acc, q, ...p) => Number(acc.rows(q, ...p)[0]?.n || 0);
const harf = (ad) => kac((String(ad || "?").replace(/^@/, "")[0] || "?").toUpperCase());

// Şu an bağlı hesaplar (uygulama açık): hesap başına bir kez, en eski bağlantı zamanıyla
function cevrimici(acc) {
  const m = new Map();
  let wss = [];
  try {
    wss = acc.state.getWebSockets();
  } catch {}
  for (const ws of wss) {
    const i = acc.info(ws);
    if (!i.token) continue;
    const o = m.get(i.token);
    if (!o || (i.bas && i.bas < o.bas)) m.set(i.token, { token: i.token, handle: i.handle || "", bas: i.bas || Date.now() });
  }
  return [...m.values()];
}

function canliOdalar(acc, now) {
  return acc.rows(`SELECT * FROM oda_canli WHERE son > ? AND durum != 'kapandi' ORDER BY acilis DESC LIMIT 100`, now - CANLI_SURE);
}

function kart(baslik, deger, alt, tur = "") {
  return `<div class="kpi ${tur}"><div class="kpi-b">${baslik}</div><div class="kpi-d">${deger}</div><div class="kpi-a">${alt}</div></div>`;
}

// Son 14 günün biten maçları: 3D sütunlar (özel oda + hızlı maç üst üste), üzerine gelince gün ayrıntısı
function grafik(acc, now) {
  const bas = gunBasi(now) - 13 * GUN_MS;
  const rows = acc.rows(`SELECT CAST((ts + ?) / ? AS INTEGER) AS g, SUM(hizli = 0) AS oda, SUM(hizli = 1) AS hizli FROM mac_kayit WHERE ts >= ? GROUP BY g`, TR_OFSET, GUN_MS, bas);
  const by = new Map(rows.map((r) => [Number(r.g), r]));
  const gunler = [];
  for (let i = 0; i < 14; i++) {
    const t = bas + i * GUN_MS;
    const r = by.get(Math.floor((t + TR_OFSET) / GUN_MS)) || {};
    gunler.push({ t, oda: Number(r.oda) || 0, hizli: Number(r.hizli) || 0 });
  }
  const enCok = Math.max(1, ...gunler.map((g) => g.oda + g.hizli));
  const adim = enCok <= 4 ? 1 : enCok <= 10 ? 2 : enCok <= 25 ? 5 : enCok <= 50 ? 10 : Math.ceil(enCok / 5 / 10) * 10;
  const tavan = Math.ceil(enCok / adim) * adim;
  const H = 190;
  let izgara = "";
  for (let v = 0; v <= tavan; v += adim) izgara += `<div class="cizgi" style="bottom:${(v / tavan) * H}px"><span>${v}</span></div>`;
  const tepe = gunler.reduce((a, g, i) => (g.oda + g.hizli > gunler[a].oda + gunler[a].hizli ? i : a), 0);
  let sut = "";
  gunler.forEach((g, i) => {
    const top = g.oda + g.hizli;
    const d = new Date(g.t + TR_OFSET);
    const etiket = i === 0 || d.getUTCDate() === 1 ? `${d.getUTCDate()} ${AYLAR[d.getUTCMonth()]}` : String(d.getUTCDate());
    const h1 = (g.oda / tavan) * H;
    const h2 = (g.hizli / tavan) * H;
    const dilim = (h, c) => (h > 0 ? `<i class="dilim ${c}" style="height:${Math.max(3, h - 2).toFixed(1)}px"></i>` : "");
    const yazi = top > 0 && (i === tepe || i === 13) ? `<b class="deger">${top}</b>` : "";
    sut += `<div class="hucre${i === 13 ? " bugun" : ""}"><div class="sutun">${yazi}${dilim(h1, "s1")}${dilim(h2, "s2")}${top ? "" : `<i class="sifir"></i>`}</div>`
      + `<div class="gun">${etiket}</div><div class="ipucu"><b>${d.getUTCDate()} ${AYLAR[d.getUTCMonth()]}${i === 13 ? " (bugün)" : ""}</b>`
      + `<span><i class="k1"></i>Özel oda <b>${g.oda}</b></span><span><i class="k2"></i>Hızlı maç <b>${g.hizli}</b></span></div></div>`;
  });
  return `<section class="pano"><div class="pano-b"><h2>Biten maçlar · son 14 gün</h2><div class="lejant"><span><i class="k1"></i>Özel oda (arkadaşlarla)</span><span><i class="k2"></i>Hızlı maç</span></div></div>`
    + `<div class="sahne"><div class="zemin" style="height:${H}px">${izgara}<div class="sutunlar">${sut}</div></div></div></section>`;
}

function sekmeOzet(acc, now) {
  const online = cevrimici(acc);
  const odalar = canliOdalar(acc, now);
  const bugun = gunBasi(now);
  const kayitli = sayi(acc, `SELECT COUNT(*) AS n FROM users WHERE pass IS NOT NULL AND pass != ''`);
  const misafir = sayi(acc, `SELECT COUNT(*) AS n FROM users WHERE pass IS NULL OR pass = ''`);
  const mac = (k) => sayi(acc, `SELECT COUNT(*) AS n FROM users WHERE CAST(COALESCE(json_extract(stats, '$.mac'), 0) AS INTEGER) >= ?`, k);
  const aktif = (t) => sayi(acc, `SELECT COUNT(*) AS n FROM users WHERE son_aktif >= ?`, t);
  const bugunMac = acc.rows(`SELECT COUNT(*) AS n, SUM(hizli = 0) AS oda FROM mac_kayit WHERE ts >= ?`, bugun)[0] || {};
  const ay = now - 30 * GUN_MS;
  const ev = (k) => sayi(acc, `SELECT COUNT(*) AS n FROM events WHERE ts > ? AND kind = ?`, ay, k);
  let h = `<div class="kpiler">`;
  h += kart("Şu an çevrim içi", online.length, "uygulamayı açık tutan", "canli");
  h += kart("Canlı oda", odalar.length, `${odalar.filter((o) => o.durum === "oyunda").length} odada maç sürüyor`);
  h += kart("Bugün aktif", aktif(bugun), `son 7 gün: ${aktif(now - 7 * GUN_MS)}`);
  h += kart("Bugün biten maç", Number(bugunMac.n) || 0, `özel oda: ${Number(bugunMac.oda) || 0}`);
  h += kart("Kayıtlı hesap", kayitli, `misafir: ${misafir}`);
  h += kart("Arkadaşlarıyla oynayan", mac(1), `5+ maç: ${mac(5)} · 20+ maç: ${mac(20)}`, "vurgu");
  h += `</div>`;
  h += grafik(acc, now);
  // en çok vakit geçirenler (uygulama açık kalma süresi; çevrim içiyse şu anki oturum da eklenir)
  const acik = new Map(online.map((o) => [o.token, now - o.bas]));
  const enler = acc.rows(`SELECT token, handle, name, COALESCE(sure, 0) AS sure FROM users WHERE COALESCE(sure, 0) > 0 OR son_aktif > ? ORDER BY sure DESC LIMIT 40`, now - GUN_MS)
    .map((u) => ({ ...u, top: u.sure + (acik.get(u.token) || 0) / 1000 }))
    .sort((a, b) => b.top - a.top)
    .slice(0, 8);
  h += `<div class="iki"><section class="pano"><h2>En çok oynayanlar</h2>`;
  if (!enler.length) h += `<div class="bos">Henüz süre kaydı yok — oyuncular uygulamayı kapattıkça dolar.</div>`;
  else {
    const m = Math.max(...enler.map((e) => e.top), 1);
    for (const e of enler) {
      h += `<div class="cubuk"><span class="ad">${e.handle ? "@" + kac(e.handle) : kac(e.name || "misafir")}${acik.has(e.token) ? ` <i class="nokta"></i>` : ""}</span>`
        + `<span class="iz"><i style="width:${Math.max(2, (e.top / m) * 100).toFixed(1)}%"></i></span><span class="sn">${sureYaz(e.top)}</span></div>`;
    }
  }
  h += `</section><section class="pano"><h2>Son 30 gün</h2><div class="mini">`
    + `<div><b>${ev("oturum")}</b><span>uygulama açılışı</span></div>`
    + `<div><b>${ev("mac_basla")}</b><span>maça başlama</span></div>`
    + `<div><b>${ev("mac_bitti")}</b><span>maçı bitirme</span></div>`
    + `<div><b>${ev("tekrar_oyna")}</b><span>"tekrar oyna"</span></div>`
    + `</div><p class="k">Sayılar oyuncu başınadır: 4 kişilik bir maç 4 "maça başlama" yazar.</p></section></div>`;
  return h;
}

function oyuncuCip(o, cevrim) {
  const ad = o.ad || "?";
  return `<span class="cip${o.hesap ? "" : " sonuk"}"><i class="av">${harf(ad)}</i>${kac(ad)}${cevrim ? ` <i class="nokta"></i>` : ""}</span>`;
}

function sekmeCanli(acc, now) {
  const online = cevrimici(acc).sort((a, b) => a.bas - b.bas);
  const odalar = canliOdalar(acc, now);
  const odaAdi = new Map(); // oyuncu adı -> oda
  for (const o of odalar) for (const p of jsonOku(o.oyuncular, [])) if (p.ad) odaAdi.set(p.ad, o);
  const onlineAd = new Set(online.map((o) => o.handle).filter(Boolean));
  let h = `<p class="k yenile">Bu sekme 20 saniyede bir kendini yeniler · ${saatYaz(now)}</p>`;
  h += `<section class="pano"><h2>Canlı odalar (${odalar.length})</h2>`;
  if (!odalar.length) h += `<div class="bos">Şu an açık oda yok.</div>`;
  else {
    h += `<div class="odalar">`;
    for (const o of odalar) {
      const oy = jsonOku(o.oyuncular, []);
      const durum = o.durum === "oyunda" ? `<span class="rozet oyunda">Maç sürüyor${o.oyun ? " · " + kac(o.oyun) : ""}${o.turlar ? ` · ${o.tur}/${o.turlar}` : ""}</span>`
        : o.durum === "bitti" ? `<span class="rozet bitti">Maç bitti</span>` : `<span class="rozet lobi">Lobide bekliyor</span>`;
      h += `<div class="oda"><div class="oda-u"><div><div class="oda-ad">${o.hizli ? "Hızlı maç" : `Özel oda <b>${kac(o.kod || "")}</b>`}</div>${durum}</div>`
        + `<div class="oda-kisi"><b>${oy.length + (o.bot || 0)}</b><span>kişi</span></div></div>`
        + `<div class="cipler">${oy.map((p) => oyuncuCip(p, false)).join("")}${o.bot ? `<span class="cip sonuk"><i class="av">🤖</i>${o.bot} bot</span>` : ""}</div>`
        + `<div class="oda-a"><span>Açık: <b>${sureYaz((now - o.acilis) / 1000)}</b></span><span>En kalabalık: <b>${o.en_cok}</b> gerçek</span><span>Son sinyal: ${once(o.son, now)}</span></div></div>`;
    }
    h += `</div>`;
  }
  h += `</section><section class="pano"><h2>Şu an çevrim içi (${online.length})</h2>`;
  if (!online.length) h += `<div class="bos">Şu an uygulamayı açık tutan yok.</div>`;
  else {
    h += `<div class="tablo"><table><tr><th>Oyuncu</th><th>Ne kadardır açık</th><th>Nerede</th></tr>`;
    for (const o of online) {
      const oda = o.handle ? odaAdi.get(o.handle) : null;
      const yer = oda ? (oda.hizli ? "Hızlı maç" : `Özel oda ${kac(oda.kod || "")}`) + (oda.durum === "oyunda" ? " · maçta" : " · lobide") : "Ana menü";
      h += `<tr><td><span class="cip"><i class="av">${harf(o.handle || "m")}</i>${o.handle ? "@" + kac(o.handle) : "misafir"} <i class="nokta"></i></span></td><td>${sureYaz((now - o.bas) / 1000)}</td><td>${yer}</td></tr>`;
    }
    h += `</table></div>`;
  }
  const kapanan = acc.rows(`SELECT * FROM oda_canli WHERE (son <= ? OR durum = 'kapandi') AND son > ? ORDER BY son DESC LIMIT 60`, now - CANLI_SURE, now - GUN_MS);
  h += `</section><section class="pano"><h2>Son 24 saatte kapanan odalar (${kapanan.length})</h2>`;
  if (!kapanan.length) h += `<div class="bos">Kayıt yok (oda takibi yeni başladı).</div>`;
  else {
    h += `<div class="tablo"><table><tr><th>Oda</th><th>Açıldı</th><th>Ne kadar açık kaldı</th><th>En kalabalık</th><th>Odaya girenler</th><th>Kapandı</th></tr>`;
    for (const o of kapanan) {
      const goren = jsonOku(o.goren, []);
      h += `<tr><td>${o.hizli ? "Hızlı maç" : `Özel oda <b>${kac(o.kod || "")}</b>`}</td><td>${saatYaz(o.acilis)}</td><td><b>${sureYaz((o.son - o.acilis) / 1000)}</b></td><td>${o.en_cok}</td>`
        + `<td>${goren.map((a) => `<span class="cip kucuk">${kac(a)}${onlineAd.has(a) ? ` <i class="nokta"></i>` : ""}</span>`).join("")}</td><td>${once(o.son, now)}</td></tr>`;
    }
    h += `</table></div>`;
  }
  return h + `</section>`;
}

function sekmeOyuncular(acc, url, now, geri) {
  const ara = (url.searchParams.get("ara") || "").trim().slice(0, 40);
  const sayac = (t) => (t ? acc.rows(`SELECT COUNT(*) AS n FROM reports WHERE target_token = ?`, t)[0].n : 0);
  let h = `<section class="pano"><h2>Hesap ara</h2><form method="get" action="/yonetim" class="ara"><input type="hidden" name="sekme" value="oyuncular"><input type="search" name="ara" value="${kac(ara)}" placeholder="kullanıcı adı ya da ad" maxlength="40"> <button class="a">Ara</button></form>`;
  if (ara) {
    const q = "%" + ara.replace(/^@/, "").replace(/[!%_]/g, (c) => "!" + c) + "%"; // LIKE özel karakterleri ! ile kaçışlı
    const bulunan = acc.rows(`SELECT rowid AS id, token, handle, name FROM users WHERE handle LIKE ? ESCAPE '!' OR name LIKE ? ESCAPE '!' ORDER BY handle IS NULL, handle LIMIT 50`, q, q);
    if (!bulunan.length) h += `<div class="bos">Sonuç yok.</div>`;
    else {
      h += `<div class="tablo"><table><tr><th>#</th><th>Kullanıcı adı</th><th>Ad</th><th>Durum</th><th>Toplam şikayet</th><th>İşlem</th></tr>`;
      for (const u of bulunan) {
        const y = acc.yasak(u.token);
        const gizli = `<input type="hidden" name="hesap" value="${u.id}">${geri}`;
        h += `<tr><td>${u.id}</td><td>${u.handle ? "@" + kac(u.handle) : "misafir"}</td><td>${kac(u.name || "")}</td><td>${y ? `<span class="yasak">${kac(yasakYazi(y))}</span>` : "aktif"}</td><td>${sayac(u.token)}</td><td>${islemDugmeleri(gizli, false)}</td></tr>`;
      }
      h += `</table></div>`;
    }
  }
  h += `</section>`;
  const online = new Map(cevrimici(acc).map((o) => [o.token, o]));
  const liste = acc.rows(
    `SELECT token, handle, name, COALESCE(son_aktif, 0) AS son, COALESCE(sure, 0) AS sure, COALESCE(oturum, 0) AS oturum, COALESCE(ilk, 0) AS ilk,
       CAST(COALESCE(json_extract(stats, '$.mac'), 0) AS INTEGER) AS mac, CAST(COALESCE(json_extract(stats, '$.oda_mac'), 0) AS INTEGER) AS oda_mac,
       CAST(COALESCE(json_extract(stats, '$.galibiyet'), 0) AS INTEGER) AS gal
     FROM users WHERE handle IS NOT NULL AND handle != '' ORDER BY son DESC, mac DESC LIMIT 300`,
  );
  h += `<section class="pano"><h2>Oyuncular (son aktif olan üstte)</h2><p class="k">"Son aktif" ve "uygulamada" sayaçları yeni başladı; eski oyuncularda ilk girişlerine kadar "—" görünür. Maç sayıları baştan beri tutuluyor.</p>`;
  h += `<div class="tablo"><table><tr><th>Oyuncu</th><th>Son aktif</th><th>Uygulamada toplam</th><th>Giriş</th><th>Maç</th><th>Özel oda maçı</th><th>Galibiyet</th><th>İlk görülme</th></tr>`;
  for (const u of liste) {
    const o = online.get(u.token);
    const top = u.sure + (o ? (now - o.bas) / 1000 : 0);
    h += `<tr><td><span class="cip"><i class="av">${harf(u.handle)}</i>@${kac(u.handle)}${o ? ` <i class="nokta"></i>` : ""}</span></td>`
      + `<td>${o ? `<b class="yesil">şu an çevrim içi</b>` : once(u.son, now)}</td><td>${top ? sureYaz(top) : "—"}</td><td>${u.oturum || "—"}</td>`
      + `<td><b>${u.mac}</b></td><td>${u.oda_mac}</td><td>${u.gal}</td><td>${u.ilk ? saatYaz(u.ilk) : "—"}</td></tr>`;
  }
  return h + `</table></div></section>`;
}

function sekmeMaclar(acc, now) {
  const rows = acc.rows(`SELECT ts, hizli, insan, toplam, kod, oyun, tablo, COALESCE(sure, 0) AS sure FROM mac_kayit WHERE tablo IS NOT NULL ORDER BY ts DESC LIMIT 100`);
  let h = `<section class="pano"><h2>Son maçlar (${rows.length})</h2>`;
  if (!rows.length) return h + `<div class="bos">Adlı maç listesi yeni başladı; ilk biten maçla dolar. Önceki maçlar aşağıda.</div></section>` + eskiMaclarHtml(acc, now);
  h += `<div class="maclar">`;
  for (const r of rows) {
    const t = jsonOku(r.tablo, []);
    const ad = (o) => kac(o.ad || "?") + (o.hesap ? "" : ` <span class="k">(bot/misafir)</span>`);
    const kazanan = t.find((o) => o.sira === 1);
    h += `<div class="mac"><div class="mac-u"><span class="${r.hizli ? "etk2" : "etk1"}">${r.hizli ? "Hızlı maç" : `Özel oda ${kac(r.kod || "")}`}</span><span class="k">${saatYaz(r.ts)} · ${once(r.ts, now)}</span></div>`
      + `<div class="kazanan"><i class="tac">♛</i><div><span class="k">Kazanan</span><b>${kazanan ? ad(kazanan) : "-"}</b></div></div>`
      + `<ol class="siralama">${t.map((o) => `<li><span class="s">${o.sira}.</span> ${ad(o)} <span class="puan">${o.puan}</span></li>`).join("")}</ol>`
      + `<div class="mac-a"><span><b>${r.toplam}</b> kişi (${r.insan} gerçek)</span><span><b>${r.oyun || 0}</b> oyun</span><span>${r.sure ? `<b>${sureYaz(r.sure)}</b>` : "süre yok"}</span></div></div>`;
  }
  return h + `</div></section>` + eskiMaclarHtml(acc, now);
}

function sekmeSikayet(acc, geri) {
  const raporlar = acc.rows(`SELECT id, from_token, target_token, target, target_ad, room, reason, note, ts FROM reports WHERE COALESCE(durum, 'acik') = 'acik' ORDER BY ts DESC LIMIT 200`);
  const sayac = (t) => (t ? acc.rows(`SELECT COUNT(*) AS n FROM reports WHERE target_token = ?`, t)[0].n : 0);
  let h = `<section class="pano"><h2>Bekleyen şikayetler (${raporlar.length})</h2>`;
  if (!raporlar.length) return h + `<div class="bos">Bekleyen şikayet yok.</div></section>`;
  h += `<div class="tablo"><table><tr><th>Tarih</th><th>Şikayet eden</th><th>Şikayet edilen</th><th>Sebep</th><th>Oda</th><th>Maçtaki ad</th><th>Toplam şikayet</th><th>İşlem</th></tr>`;
  for (const r of raporlar) {
    const eden = kimlik(acc, r.from_token);
    const edilen = kimlik(acc, r.target_token);
    const gizli = `<input type="hidden" name="rapor" value="${r.id}">${geri}`;
    h += `<tr><td>${kac(tarihTR(r.ts))}</td><td>${kac(eden.metin)}</td><td>${kac(edilen.metin)}${edilen.yasak ? `<br><span class="yasak">${kac(yasakYazi(edilen.yasak))}</span>` : ""}</td>`
      + `<td>${kac(SEBEP[r.reason] || r.reason)}${r.note ? `<br><span class="k">${kac(r.note)}</span>` : ""}</td><td>${kac(r.room || "—")}</td><td>${kac(r.target_ad || r.target || "—")}</td>`
      + `<td>${sayac(r.target_token)}</td><td>${islemDugmeleri(gizli, true, !r.target_token)}</td></tr>`;
  }
  return h + `</table></div></section>`;
}

// Eski maçlar (maç listesi tutulmaya başlamadan önceki 30 gün): telefonların yolladığı "mac_basla" / "mac_bitti" kayıtlarından
// tahmin. Aynı maçtaki her telefon birkaç saniye arayla aynı oyuncu sayısıyla "mac_basla" yollar: bunlar tek maç sayılır.
// Kayıt sayısı = maçtaki gerçek oyuncu (telefon) sayısı. Adlar bu kayıtlarda yok.
function eskiMaclar(acc, now) {
  const bas = now - 30 * GUN_MS;
  const kume = (kind, anahtar) => {
    const rows = acc.rows(`SELECT ts, platform, data FROM events WHERE kind = ? AND ts > ? ORDER BY ts`, kind, bas);
    const out = [];
    for (const r of rows) {
      const v = Number(jsonOku(r.data, {})[anahtar]) || 0;
      const son = out[out.length - 1];
      if (son && r.ts - son.ts <= 25000 && son.v === v) {
        son.n++;
        son.p[r.platform] = (son.p[r.platform] || 0) + 1;
      } else out.push({ ts: r.ts, v, n: 1, p: { [r.platform]: 1 } });
    }
    return out;
  };
  const baslar = kume("mac_basla", "oyuncu");
  const bitisler = kume("mac_bitti", "oyun");
  const kullanildi = new Set();
  for (const m of baslar) {
    const i = bitisler.findIndex((b, j) => !kullanildi.has(j) && b.ts > m.ts && b.ts - m.ts < 60 * 60000 && b.n <= m.n);
    if (i >= 0) {
      kullanildi.add(i);
      m.bitis = bitisler[i];
    }
  }
  return baslar.reverse();
}

function eskiMaclarHtml(acc, now) {
  const liste = eskiMaclar(acc, now);
  const ark = liste.filter((m) => m.n >= 2);
  let h = `<section class="pano"><div class="pano-b"><h2>Eski maçlar · son 30 gün (${liste.length})</h2></div>`
    + `<p class="k">Telefonların maç başında ve sonunda yolladığı kayıtlardan çıkarıldı (tahmini). Oyuncu adları bu kayıtlarda yok; yeni maçlar yukarıda adlarıyla görünür.</p>`;
  if (!liste.length) return h + `<div class="bos">Son 30 günde kayıt yok.</div></section>`;
  const bitti = liste.filter((m) => m.bitis).length;
  h += `<div class="mini dort"><div><b>${liste.length}</b><span>başlayan maç</span></div><div><b>${ark.length}</b><span>2+ gerçek oyunculu (arkadaşlarla)</span></div>`
    + `<div><b>${bitti}</b><span>sonuna kadar oynanan</span></div><div><b>${liste.reduce((a, m) => a + m.n, 0)}</b><span>toplam katılım</span></div></div>`;
  h += `<div class="tablo" style="margin-top:14px"><table><tr><th>Başladı</th><th>Maçtaki kişi</th><th>Gerçek oyuncu</th><th>Cihazlar</th><th>Sonuç</th></tr>`;
  for (const m of liste.slice(0, 300)) {
    const cihaz = Object.entries(m.p).map(([p, n]) => `${kac(p)} ${n}`).join(" · ");
    const sonuc = m.bitis ? `<span class="yesil">Bitti</span> · ${sureYaz((m.bitis.ts - m.ts) / 1000)}${m.bitis.v ? ` · ${m.bitis.v} oyun` : ""}` : `<span class="k">Yarıda kaldı / kayıt yok</span>`;
    h += `<tr><td>${saatYaz(m.ts)} <span class="k">· ${once(m.ts, now)}</span></td><td>${m.v || "?"}</td><td><b>${m.n}</b>${m.n >= 2 ? ` <span class="etk1">arkadaşlarla</span>` : ""}</td><td>${cihaz}</td><td>${sonuc}</td></tr>`;
  }
  return h + `</table></div></section>`;
}

// ---- Hatalar: çökmeler okunur hâlde (neden, nerede, hangi cihaz) + betik hataları ----
const EKRANLAR = { menu: "Ana menü", magaza: "Mağaza", kasa: "Kasa", kasa_acilis: "Kasa açılışı", envanter: "Envanter", mac: "Maç", "": "Bilinmiyor" };
const OLAYLAR = { oturum: "Uygulama açıldı", mac_basla: "Maç başladı", mac_bitti: "Maç bitti", tekrar_oyna: "Tekrar oyna", arama_ses: "Telefonla konuşma", mik_sorun: "Mikrofon sorunu", bellek_uyarisi: "Bellek uyarısı", "": "—" };

function cokmeNedeni(d) {
  const tepe = Math.max(Number(d.tepe_bellek) || 0, Number(d.bellek) || 0);
  const vram = Math.max(Number(d.tepe_vram) || 0, Number(d.vram) || 0);
  if (Number(d.uyari) > 0) return ["bellek", "Telefonun belleği doldu", `Telefon kapanmadan önce ${d.uyari} kez "bellek az" uyarısı verdi, sonra sistem oyunu kapattı.`];
  if (tepe + vram > 1800) return ["bellek", "Bellek çok yüksekti", `Oyun ${Math.round(tepe + vram)} MB kullanıyordu; zayıf telefonlarda sistem bu düzeyde uygulamayı kapatır.`];
  if ((Number(d.sure_sn) || 0) < 20) return ["acilis", "Açılırken kapandı", "Oyun açıldıktan birkaç saniye içinde kapandı (yükleme sırasında)."];
  return ["ani", "Aniden kapandı", "Bellek uyarısı yoktu: büyük olasılıkla grafik/motor hatası ya da telefonun kendisi kapattı (ısınma, düşük pil)."];
}

function sekmeHatalar(acc) {
  const now = Date.now();
  const bas = now - 14 * GUN_MS;
  const acilis = sayi(acc, `SELECT COUNT(*) AS n FROM events WHERE ts > ? AND kind = 'oturum'`, bas);
  const cokmeler = acc.rows(`SELECT ts, surum, platform, data FROM events WHERE ts > ? AND kind = 'onceki_cokme' ORDER BY ts DESC LIMIT 200`, bas);
  // aynı paketle gelen "oturum" olayı: cihaz modeli ve RAM (çökme bir sonraki açılışta, oturumla birlikte yollanır)
  const cihaz = (c) => {
    const o = acc.rows(`SELECT data FROM events WHERE kind = 'oturum' AND ts = ? AND platform = ? LIMIT 1`, c.ts, c.platform)[0];
    return o ? jsonOku(o.data, {}) : {};
  };
  const oran = acilis ? Math.max(0, 100 - (cokmeler.length / acilis) * 100) : 100;
  const gruplar = {};
  const kartlar = cokmeler.map((c) => {
    const d = jsonOku(c.data, {});
    const [tur, baslik, aciklama] = cokmeNedeni(d);
    gruplar[baslik] = (gruplar[baslik] || 0) + 1;
    return { c, d, tur, baslik, aciklama, cihaz: cihaz(c) };
  });
  let h = `<div class="kpiler">`;
  h += kart("Açılış (14 gün)", acilis, "uygulamanın açılma sayısı");
  h += kart("Çökme (14 gün)", cokmeler.length, cokmeler.length ? Object.entries(gruplar).map(([k, n]) => `${k}: ${n}`).join(" · ") : "çökme yok", cokmeler.length ? "vurgu" : "canli");
  h += kart("Çökmesiz açılış", `%${oran.toFixed(1)}`, "100 açılışta çökmeden geçen");
  h += `</div>`;
  h += `<section class="pano"><h2>Çökmeler · son 14 gün (${cokmeler.length})</h2>`;
  if (!kartlar.length) h += `<div class="bos">Son 14 günde çökme yok.</div>`;
  else {
    h += `<div class="maclar">`;
    for (const k of kartlar) {
      const d = k.d;
      const model = k.cihaz.model ? kac(k.cihaz.model) : "";
      const ram = k.cihaz.ram > 0 ? ` · ${(k.cihaz.ram / 1024).toFixed(1)} GB RAM` : "";
      const son = Array.isArray(d.son_hatalar) && d.son_hatalar.length ? `<div class="son-hata"><span class="k">Kapanmadan önceki son hatalar</span>${d.son_hatalar.map((m) => `<code>${kac(m)}</code>`).join("")}</div>` : "";
      h += `<div class="mac cokme ${k.tur}"><div class="mac-u"><span class="etk ${k.tur}">${k.baslik}</span><span class="k">${saatYaz(k.c.ts)} · ${once(k.c.ts, now)}</span></div>`
        + `<p class="aciklama">${kac(k.aciklama)}</p>`
        + `<div class="bilgi"><div><span class="k">Cihaz</span><b>${kac(k.c.platform)}${model ? " · " + model : ""}${ram}</b></div><div><span class="k">Sürüm</span><b>${kac(d.surum || k.c.surum)}</b></div>`
        + `<div><span class="k">Nerede</span><b>${kac(EKRANLAR[d.son_ekran] || d.son_ekran)}</b></div><div><span class="k">Son olay</span><b>${kac(OLAYLAR[d.son_olay] || d.son_olay)}</b></div>`
        + `<div><span class="k">Ne kadar açıktı</span><b>${d.sure_sn ? sureYaz(d.sure_sn) : "—"}</b></div><div><span class="k">Bellek (en yüksek)</span><b>${Number(d.tepe_bellek) || Number(d.tepe_vram) ? `${Math.round(Number(d.tepe_bellek) || 0)} MB + ${Math.round(Number(d.tepe_vram) || 0)} MB görüntü` : "—"}</b></div></div>${son}</div>`;
    }
    h += `</div>`;
  }
  h += `</section>`;
  // betik hataları: aynı hata tek satırda, kaç kez
  const hatalar = acc.rows(`SELECT surum, platform, data, COUNT(*) AS n, MAX(ts) AS son FROM events WHERE ts > ? AND kind = 'hata' GROUP BY surum, platform, data ORDER BY n DESC, son DESC LIMIT 150`, bas);
  h += `<section class="pano"><h2>Oyun içi hata mesajları · son 14 gün (${hatalar.length})</h2><p class="k">Oyunu kapatmayan ama kodda bir şeyin ters gittiğini gösteren hatalar. Dosya:satır ve mesaj, kaç kez görüldüğüyle.</p>`;
  if (!hatalar.length) h += `<div class="bos">Hata yok.</div>`;
  else {
    h += `<div class="tablo"><table id="hatalar"><tr><th>Kaç kez</th><th>Hata</th><th>Sürüm</th><th>Cihaz</th><th>En son</th></tr>`;
    for (const r of hatalar) {
      const m = String(jsonOku(r.data, {}).m || r.data || "");
      h += `<tr><td><b>${r.n}</b></td><td style="word-break:break-all"><code>${kac(m)}</code></td><td>${kac(r.surum)}</td><td>${kac(r.platform)}</td><td>${once(r.son, now)}</td></tr>`;
    }
    h += `</table></div>`;
  }
  const surumler = acc.rows(`SELECT surum, platform, SUM(kind = 'oturum') AS acilis, SUM(kind = 'onceki_cokme') AS cokme FROM events WHERE ts > ? AND kind IN ('oturum', 'onceki_cokme') GROUP BY surum, platform ORDER BY acilis DESC LIMIT 40`, bas);
  h += `</section><section class="pano"><h2>Sürüm ve cihaz başına</h2>`;
  if (!surumler.length) return h + `<div class="bos">Kayıt yok.</div></section>`;
  h += `<div class="tablo"><table><tr><th>Sürüm</th><th>Cihaz</th><th>Açılış</th><th>Çökme</th><th>Çökme oranı</th></tr>`;
  for (const o of surumler) h += `<tr><td>${kac(o.surum)}</td><td>${kac(o.platform)}</td><td>${o.acilis}</td><td>${o.cokme ? `<b class="kirmizi">${o.cokme}</b>` : 0}</td><td>${o.acilis ? "%" + Math.min(100, (o.cokme / o.acilis) * 100).toFixed(1) : "—"}</td></tr>`;
  return h + `</table></div></section>`;
}

function panel(acc, url, mesaj) {
  const now = Date.now();
  const sekme = SEKMELER.some(([k]) => k === url.searchParams.get("sekme")) ? url.searchParams.get("sekme") : "ozet";
  const ara = (url.searchParams.get("ara") || "").trim().slice(0, 40);
  const geri = `<input type="hidden" name="ara" value="${kac(ara)}"><input type="hidden" name="sekme" value="${sekme}">`;
  const rozet = {
    canli: canliOdalar(acc, now).length,
    sikayet: sayi(acc, `SELECT COUNT(*) AS n FROM reports WHERE COALESCE(durum, 'acik') = 'acik'`),
  };
  let govde = `<header class="ust"><div class="logo"><span class="l1">HAT DÜŞTÜ</span><span class="l2">Yönetim · Analiz</span></div>`
    + `<form class="i" method="post" action="/yonetim/cikis"><button>Çıkış</button></form></header>`;
  govde += `<nav class="sekmeler">${SEKMELER.map(([k, ad]) => `<a href="/yonetim?sekme=${k}" class="${k === sekme ? "secili" : ""}">${ad}${rozet[k] ? `<i class="${k === "sikayet" ? "kirmizi" : "yesil"}">${rozet[k]}</i>` : ""}</a>`).join("")}</nav>`;
  if (mesaj) govde += `<div class="${mesaj.hata ? "hata" : "ok"}">${kac(mesaj.metin)}</div>`;
  if (sekme === "ozet") govde += sekmeOzet(acc, now);
  else if (sekme === "canli") govde += sekmeCanli(acc, now);
  else if (sekme === "oyuncular") govde += sekmeOyuncular(acc, url, now, geri);
  else if (sekme === "maclar") govde += sekmeMaclar(acc, now);
  else if (sekme === "sikayet") govde += sekmeSikayet(acc, geri);
  else govde += sekmeHatalar(acc);
  return sayfa(govde, 200, {}, sekme === "canli" ? 20 : 0);
}

function girisSayfasi(hata, durum = 200) {
  return sayfa(`<div class="kutu"><h1>Yönetim girişi</h1>${hata ? `<div class="hata">${kac(hata)}</div>` : ""}
<form method="post" action="/yonetim/giris" autocomplete="off"><p><input type="password" name="anahtar" placeholder="Yönetici anahtarı" required autofocus></p><button class="a">Giriş</button></form></div>`, durum);
}

// Hesaba işlem uygular. Dönen: sonuç metni
function uygula(acc, islem, token, raporId) {
  const now = Date.now();
  const online = acc.socketsOfToken(token);
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
      const sk = String(form.get("sekme") || "").replace(/[^a-z]/g, "").slice(0, 12);
      if (sk) q.set("sekme", sk);
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
