// Hücre duvarı posterleri (yazısız, her dilde aynı): OpenAI görsel üretimi -> assets/poster/poster_<ad>.png
// Kullanım: node tools/poster_uret.mjs [ad ...] [--force] [--quality=medium]
// Çıkan 1024x1536 resim Godot aracıyla 512 genişliğe küçültülür (tools/doku_kucult.gd), hücreler cell.gd POSTERS listesinden seçer.
// Anahtar: .gizli/openai.txt (asla yazdırılmaz).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const KOK = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CIKTI = path.join(KOK, "assets", "poster");
const ORTAK =
  "Vintage printed wall poster, slightly worn paper with soft folds and faded colors, full-bleed artwork filling the whole frame, " +
  "no border, no frame, no wall, no tape. Absolutely no text, no letters, no numbers, no logo, no watermark.";
const POSTERLER = {
  dag: "Retro travel-style illustration of a calm alpine lake with snowy mountains and pine trees at golden hour, soft gradient sky.",
  konser: "Retro rock concert illustration: silhouette of a guitarist on stage under bright colorful spotlights and haze, crowd hands raised.",
  futbol: "Retro illustration of a packed football stadium at night under floodlights, a single football in the foreground on green grass.",
  motor: "Retro illustration of a classic black motorcycle parked on an empty desert highway at sunset, long road to the horizon.",
};

const temizle = (s) => String(s).replace(/sk-[A-Za-z0-9_\-*.]+/g, "sk-***");

async function main() {
  const args = process.argv.slice(2);
  const force = args.includes("--force");
  const quality = (args.find((a) => a.startsWith("--quality=")) || "=medium").split("=")[1];
  const adlar = args.filter((a) => !a.startsWith("--"));
  const key = fs.readFileSync(path.join(KOK, ".gizli", "openai.txt"), "utf8").trim();
  for (const [ad, konu] of Object.entries(POSTERLER)) {
    if (adlar.length && !adlar.includes(ad)) continue;
    const dosya = path.join(CIKTI, `poster_${ad}.png`);
    if (fs.existsSync(dosya) && !force) { console.log(`atla ${ad}`); continue; }
    process.stdout.write(`üret ${ad} ... `);
    for (const model of ["gpt-image-1.5", "gpt-image-1"]) {
      const r = await fetch("https://api.openai.com/v1/images/generations", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model, prompt: `${konu} ${ORTAK}`, size: "1024x1536", quality, n: 1, output_format: "png", background: "opaque" }),
      });
      const metin = await r.text();
      if (!r.ok) {
        console.log(`${model} HATA ${r.status}: ${temizle(metin.slice(0, 200))}`);
        if (r.status === 400 || r.status === 404) continue;
        process.exit(2);
      }
      const j = JSON.parse(metin);
      fs.writeFileSync(dosya, Buffer.from(j.data[0].b64_json, "base64"));
      console.log(`tamam (${model})`);
      break;
    }
  }
}
main().catch((e) => { console.error("Hata:", temizle(e.message)); process.exit(1); });
