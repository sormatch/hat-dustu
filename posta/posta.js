// Hat Düştü bildirim postası: yalnızca doğrulanmış tek adrese (wrangler.toml) gönderir.
// Kullanım: POST /gonder  (Authorization: Bearer <.gizli/posta.txt içindeki anahtar>)  gövde: {konu, metin, html?}
import { EmailMessage } from "cloudflare:email";

const KIMDEN = "destek@hatdustu.app";
const KIME = "eminabayli66@gmail.com";

function b64(s) {
  const bytes = new TextEncoder().encode(s);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

function mime(konu, metin, html) {
  const sinir = "hd" + crypto.randomUUID().replace(/-/g, "");
  const satirlar = [
    `From: Hat Düştü <${KIMDEN}>`,
    `To: <${KIME}>`,
    `Subject: =?UTF-8?B?${b64(konu)}?=`,
    `Message-ID: <${crypto.randomUUID()}@hatdustu.app>`,
    `Date: ${new Date().toUTCString()}`,
    "MIME-Version: 1.0",
    `Content-Type: multipart/alternative; boundary="${sinir}"`,
    "",
    `--${sinir}`,
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    b64(metin).replace(/.{76}/g, "$&\r\n"),
  ];
  if (html) {
    satirlar.push(`--${sinir}`, "Content-Type: text/html; charset=UTF-8", "Content-Transfer-Encoding: base64", "", b64(html).replace(/.{76}/g, "$&\r\n"));
  }
  satirlar.push(`--${sinir}--`, "");
  return satirlar.join("\r\n");
}

// Anahtarın kendisi yalnız yerelde (.gizli/posta.txt); burada sadece SHA-256 özeti var.
const ANAHTAR_OZETI = "a3ecb3d530b6949745fed62181dce49201b6d1416c2fa0a41090b3eadf0758dc";
async function dogru(k) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(k)));
  const hex = [...d].map((b) => b.toString(16).padStart(2, "0")).join("");
  let f = hex.length ^ ANAHTAR_OZETI.length;
  for (let i = 0; i < Math.min(hex.length, ANAHTAR_OZETI.length); i++) f |= hex.charCodeAt(i) ^ ANAHTAR_OZETI.charCodeAt(i);
  return f === 0;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (req.method !== "POST" || url.pathname !== "/gonder") return new Response("Hat Düştü", { status: 404 });
    const gelen = (req.headers.get("Authorization") || "").replace(/^Bearer /, "");
    if (!(await dogru(gelen))) return new Response("yetkisiz", { status: 401 });
    const { konu, metin, html } = await req.json();
    if (!konu || !metin) return new Response("eksik", { status: 400 });
    await env.POSTA.send(new EmailMessage(KIMDEN, KIME, mime(String(konu).slice(0, 200), String(metin).slice(0, 20000), html ? String(html).slice(0, 50000) : "")));
    return new Response("gönderildi");
  },
};
