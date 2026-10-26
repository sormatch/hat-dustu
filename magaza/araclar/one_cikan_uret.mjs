// Play "öne çıkan görsel" için arka plan sanatı üretir (OpenAI gpt-image-2, opak, 1536x1024).
// Kullanım (Git Bash, D:/HatDustu içinde): node magaza/araclar/one_cikan_uret.mjs
// Anahtar .gizli/openai.txt'den okunur, ASLA yazdırılmaz. Çıktı: magaza/ham/one_cikan_ham.png
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const KOK = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const CIKTI = path.join(KOK, "magaza", "ham", "one_cikan_ham.png");
const temizle = (s) => String(s).replace(/sk-[A-Za-z0-9_\-*.]+/g, "sk-***");

const PROMPT =
  "Wide horizontal key art banner for a mobile multiplayer party game set in a prison. " +
  "Composition: the LEFT 45% of the image is calm, dark and mostly empty (deep shadowy green-painted concrete wall, soft haze) reserved for a logo. " +
  "On the RIGHT side, a cutaway view of two neighbouring prison cells separated by a thick concrete wall: " +
  "in the left cell a stylized cartoon-3D male inmate in an orange jumpsuit talks into a red rotary wall payphone with a coiled cord, grinning slyly and crossing his fingers behind his back; " +
  "in the right cell a stylized female inmate in an orange jumpsuit presses a red wall payphone to her ear, eyes narrowed with suspicion. " +
  "Rusty steel cell bars, caged warm yellow ceiling lamps, sarcastic playful mood, stylized 3D game art like a modern mobile party game, rich warm amber light against teal-green shadows, high detail, crisp edges. " +
  "Absolutely no text, no letters, no numbers, no watermark, no logo. No weapons, no blood.";

async function main() {
  const key = fs.readFileSync(path.join(KOK, ".gizli", "openai.txt"), "utf8").trim();
  const r = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: "gpt-image-2", prompt: PROMPT, size: "1536x1024", quality: "high", n: 1, output_format: "png", background: "opaque" }),
  });
  const metin = await r.text();
  let j = null;
  try { j = JSON.parse(metin); } catch {}
  if (!r.ok) {
    console.log(`HATA HTTP ${r.status}: ${temizle(j?.error?.message || metin.slice(0, 300))}`);
    process.exit(1);
  }
  fs.writeFileSync(CIKTI, Buffer.from(j.data[0].b64_json, "base64"));
  console.log("tamam", CIKTI, JSON.stringify(j.usage || {}));
}
main().catch((e) => { console.log("Hata:", temizle(e.message)); process.exit(1); });
