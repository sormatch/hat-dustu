// E-posta gönderici: Cloudflare Email Service (Workers ücretli plan, wrangler.toml'daki [[send_email]] EMAIL bağlaması).
// Şablonlar eposta.js'te (eposta(tur, dil, veri) → { konu, html, metin }).
// KURAL: gönderim hiçbir zaman kayıt / şifre sıfırlama / hesap silme akışını bozmaz: hata fırlatmaz, her zaman
// { ok, neden } döner. Bağlama yoksa (servis henüz açılmadı, yerel test) göndermez, yalnızca loglar.
// E-posta adresi ve kodlar hiçbir zaman loglanmaz.

import { eposta } from "./eposta.js";

export const GONDEREN = "destek@hatdustu.app";
export const GONDEREN_AD = "Hat Düştü";

// Basit e-posta biçimi denetimi (istemcideki Account.eposta_hatasi ile aynı kural). Uygunsa küçük harfli adres, değilse "".
export function epostaTemiz(s) {
  const e = String(s || "").trim().toLowerCase();
  if (e.length < 6 || e.length > 120) return "";
  if (!/^[a-z0-9._%+\-]+@[a-z0-9\-]+(\.[a-z0-9\-]+)*\.[a-z]{2,}$/.test(e)) return "";
  if (e.includes("..") || e.startsWith(".") || e.split("@")[0].endsWith(".")) return "";
  return e;
}

// Sahibine gösterilen gizli biçim: "al***@g***.com" (başka hiçbir oyuncuya gönderilmez)
export function epostaMaske(e) {
  const [ad, alan] = String(e || "").split("@");
  if (!ad || !alan) return "";
  const nokta = alan.lastIndexOf(".");
  const ana = nokta > 0 ? alan.slice(0, nokta) : alan;
  const son = nokta > 0 ? alan.slice(nokta) : "";
  return ad.slice(0, Math.min(2, ad.length)) + "***@" + ana.slice(0, 1) + "***" + son;
}

// Gönder: { ok: true } ya da { ok: false, neden: "baglanti_yok" | "hata" | "tur" }
export async function postaGonder(env, tur, dil, alici, veri = {}) {
  try {
    if (!alici) return { ok: false, neden: "alici_yok" };
    const p = eposta(tur, dil === "en" ? "en" : "tr", veri);
    if (!env || !env.EMAIL || typeof env.EMAIL.send !== "function") {
      console.log(`posta: bağlantı yok, gönderilmedi (${tur})`);
      return { ok: false, neden: "baglanti_yok" };
    }
    try {
      await env.EMAIL.send({ to: alici, from: `${GONDEREN_AD} <${GONDEREN}>`, subject: p.konu, html: p.html, text: p.metin });
    } catch (e) {
      // "Ad <adres>" biçimi desteklenmiyorsa yalnız adresle bir kez daha denenir
      if (e && /from|sender|name/i.test(String(e.message || ""))) {
        await env.EMAIL.send({ to: alici, from: GONDEREN, subject: p.konu, html: p.html, text: p.metin });
      } else throw e;
    }
    return { ok: true };
  } catch (e) {
    console.log("posta: gönderilemedi", tur, String((e && e.message) || e).replace(/[^\s@<>"']+@[^\s@<>"']+/g, "<adres>").slice(0, 200));
    return { ok: false, neden: "hata" };
  }
}
