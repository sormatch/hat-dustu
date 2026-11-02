// Dikey görsellerin süs dokuları (OpenAI). Karakter, silah, mekân, yazı YOK: yalnız gökyüzü / ateş / duman / kıvılcım.
// Kullanım (Git Bash, D:/HatDustu): node magaza/araclar/dikey_sus_uret.mjs [ad ...]   (var olanı atlar; --force yeniden)
// Çıktı: magaza/araclar/sus/<ad>.png. Anahtar .gizli/openai.txt (yazdırılmaz). Kota hatasında hemen durur.
import fs from "node:fs";

const KOK = "D:/HatDustu";
const CIKTI = `${KOK}/magaza/araclar/sus`;
const YAZISIZ = "Absolutely no text, no letters, no numbers, no watermark, no logo, no people, no objects, no buildings.";
const SUSLER = [
  { ad: "gokyuzu", size: "1024x1536", prompt: `Dramatic moonlit night sky background texture, deep navy and cold blue, a bright full moon in the upper right third with soft halo, thin torn clouds drifting, a few faint stars, cinematic, painterly realistic. Only sky. ${YAZISIZ}` },
  { ad: "ates", size: "1024x1024", prompt: `A single huge billowing fireball explosion, photographic VFX stock element, centered, orange and yellow hot core with dark red edges and curling flames, on a perfectly pure black background so it can be used with additive blending, nothing touching the image edges. ${YAZISIZ}` },
  { ad: "duman", size: "1024x1536", prompt: `Soft drifting grey-white smoke and haze wisps, VFX stock element, on a perfectly pure black background for additive blending, sparse and subtle, more density at the bottom and edges, the middle mostly empty. ${YAZISIZ}` },
  { ad: "kivilcim", size: "1024x1536", prompt: `Scattered glowing orange embers and tiny flying sparks with slight motion streaks, VFX stock element, on a perfectly pure black background for additive blending, sparse, varied size, nothing else. ${YAZISIZ}` },
];

const args = process.argv.slice(2);
const force = args.includes("--force");
const adlar = args.filter((a) => !a.startsWith("--"));
fs.mkdirSync(CIKTI, { recursive: true });
const key = fs.readFileSync(`${KOK}/.gizli/openai.txt`, "utf8").trim();
const temizle = (s) => String(s).replace(/sk-[A-Za-z0-9_\-*.]+/g, "sk-***");

for (const g of SUSLER) {
  if (adlar.length && !adlar.includes(g.ad)) continue;
  const dosya = `${CIKTI}/${g.ad}.png`;
  if (fs.existsSync(dosya) && !force) { console.log("atla", g.ad); continue; }
  const r = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: "gpt-image-1.5", prompt: g.prompt, size: g.size, quality: "medium", n: 1, output_format: "png", background: "opaque" }),
  });
  const metin = await r.text();
  if (!r.ok) {
    console.log(`DUR: ${g.ad} HTTP ${r.status}: ${temizle(metin).slice(0, 300)}`);
    process.exit(2);
  }
  const j = JSON.parse(metin);
  fs.writeFileSync(dosya, Buffer.from(j.data[0].b64_json, "base64"));
  console.log("tamam", g.ad, JSON.stringify(j.usage || {}));
}
