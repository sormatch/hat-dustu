// Hat Düştü — ELMAS MAĞAZASI paket görselleri (6 adet, küçükten büyüğe elmas yığını)
// Kullanım (Git Bash, D:/HatDustu içinde):
//   node tools/elmas_paket_uret.mjs                    -> eksik ham görselleri üretir (var olanı atlar)
//   node tools/elmas_paket_uret.mjs elmas_paket_3      -> yalnızca adı verilenler
//   node tools/elmas_paket_uret.mjs --force elmas_paket_6
//   node tools/elmas_paket_uret.mjs --isle             -> ham görselleri kırpıp assets/ui/kit/elmas_paket_N.png yazar (ffmpeg)
//   --quality=medium  --list
// Anahtar: .gizli/openai.txt (asla yazdırılmaz / loglanmaz).
// Ham çıktı: assets/ui/kit/_ham/elmas_paket_N.png (Godot görmez), son hâli: assets/ui/kit/elmas_paket_N.png (640x640 saydam)
// Model: gpt-image-1.5 (saydam arka plan), kalite high. Sanat yönü arayuz_uret.mjs ikonlarıyla aynı.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const KOK = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const HAM = path.join(KOK, "assets", "ui", "kit", "_ham");
const KAYIT = path.join(HAM, "_kayit.json");
const KIT = path.join(KOK, "assets", "ui", "kit");
const FFMPEG = fs.existsSync("C:/ffmpeg/bin/ffmpeg.exe") ? "C:/ffmpeg/bin/ffmpeg.exe" : "ffmpeg";
const MODEL = "gpt-image-1.5";

// arayuz_uret.mjs ikon stiliyle aynı (kit ikonları ve ikon_elmas ile yan yana durabilsin)
const STIL =
  "Premium mobile game shop item illustration (Clash Royale / Brawl Stars gem shop production quality), realistic-stylized painted 3D look, chunky simplified readable shapes, a thin dark outline around the whole silhouette, consistent lighting: warm amber key light from the upper left, soft rim light. Industrial prison theme: worn olive-green painted steel, rust on the edges, small round rivets, brass, yellow-black hazard stripes. The gems are brilliant-cut sparkling diamonds glowing bright cyan blue (#5ff0ff) with white star sparkles, exactly like a premium game's gem currency icon.";
const SAYDAM = "Three-quarter front view, object centered and filling about 85% of the canvas, fully transparent background, no floor, no backdrop, no shadow plate, no circle behind it, no frame, nothing cropped.";
const YAZISIZ = "Absolutely no text, no letters, no numbers, no price tags, no watermark, no logo.";

const paket = (n, konu) => ({ ad: `elmas_paket_${n}`, size: "1024x1024", prompt: `${STIL} The subject: ${konu}. ${SAYDAM} ${YAZISIZ}` });

export const PAKETLER = [
  paket(1, "a small worn olive-green canvas prison pouch tied with a frayed rope, slightly open, with three or four glowing cyan diamond gems peeking out and one gem lying in front of it. Small modest amount"),
  paket(2, "a small heap of about fifteen glowing cyan diamond gems piled up on a battered steel prison food tray with rivets. Modest amount, clearly more than a pouch"),
  paket(3, "a dented olive-green steel ammo box with a hinged lid flipped open and a brass latch, filled to the brim with glowing cyan diamond gems, a few gems spilling over the front edge. Medium amount"),
  paket(4, "a sturdy riveted olive-green steel crate with yellow-black hazard stripes along its edge, lid open, heaped high with a mound of glowing cyan diamond gems, gems spilling onto the ground around it. Large amount, bright cyan glow rising from it"),
  paket(5, "a heavy open steel prison vault safe with a thick round door swung open and a brass combination dial, packed and overflowing with a huge pile of glowing cyan diamond gems pouring out in front. Very large amount, strong cyan glow and sparkles"),
  paket(6, "a big luxurious royal treasure chest made of gleaming polished GOLD with dark riveted steel bands and a large gold crown emblem on the front, the heavy lid wide open, a towering mountain of glowing cyan diamond gems overflowing and cascading down all sides into a big pile around its base, golden light rays bursting from inside the chest, intense cyan glow and white sparkles. Clearly the most expensive jackpot, the chest itself is large and clearly visible, mostly gold"),
];

function anahtar() {
  const k = fs.readFileSync(path.join(KOK, ".gizli", "openai.txt"), "utf8").trim();
  if (!k) throw new Error("Anahtar dosyası boş");
  return k;
}
const temizle = (s) => String(s).replace(/sk-[A-Za-z0-9_\-*.]+/g, "sk-***");
function kayitOku() {
  try { return JSON.parse(fs.readFileSync(KAYIT, "utf8")); } catch { return {}; }
}

async function uret(key, g, quality, dosya) {
  const govde = { model: MODEL, prompt: g.prompt, size: g.size, quality, n: 1, output_format: "png", background: "transparent" };
  const r = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(govde),
  });
  const metin = await r.text();
  let j = null;
  try { j = JSON.parse(metin); } catch {}
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${temizle(j?.error?.message || metin.slice(0, 300))}`);
  const b64 = j?.data?.[0]?.b64_json;
  if (!b64) throw new Error("Yanıtta b64_json yok");
  fs.writeFileSync(dosya, Buffer.from(b64, "base64"));
  return j.usage || null;
}

// --isle: saydam olmayan kutuyu bulur, kırpar, 600x600 içine sığdırır, 640x640 saydam tuvalde ortalar
function kutu(dosya) {
  let err = "";
  try { execFileSync(FFMPEG, ["-hide_banner", "-i", dosya], { stdio: ["ignore", "ignore", "pipe"] }); }
  catch (e) { err = String(e.stderr); }
  const m = err.match(/, (\d{2,5})x(\d{2,5})/);
  if (!m) throw new Error("boyut okunamadı: " + dosya);
  const w = +m[1], h = +m[2];
  const b = execFileSync(FFMPEG, ["-v", "error", "-i", dosya, "-f", "rawvideo", "-pix_fmt", "rgba", "-"], { maxBuffer: 64 << 20 });
  let x0 = w, y0 = h, x1 = 0, y1 = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (b[(y * w + x) * 4 + 3] > 24) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
  }
  return [x0, y0, x1 + 1, y1 + 1];
}
function isle(adlar) {
  for (const g of PAKETLER) {
    const giris = path.join(HAM, g.ad + ".png");
    if (!fs.existsSync(giris) || (adlar.length && !adlar.includes(g.ad))) continue;
    const [x0, y0, x1, y1] = kutu(giris);
    const vf = `crop=${x1 - x0}:${y1 - y0}:${x0}:${y0},scale=600:600:force_original_aspect_ratio=decrease:flags=lanczos,format=rgba,pad=640:640:(ow-iw)/2:(oh-ih)/2:color=0x00000000`;
    execFileSync(FFMPEG, ["-v", "error", "-y", "-i", giris, "-vf", vf, "-frames:v", "1", path.join(KIT, g.ad + ".png")]);
    console.log("yaz ", g.ad, vf);
  }
}

async function main() {
  const args = process.argv.slice(2);
  const bayrak = (n) => args.includes(`--${n}`);
  const deger = (n, v) => (args.find((a) => a.startsWith(`--${n}=`)) || `=${v}`).split("=")[1];
  const adlar = args.filter((a) => !a.startsWith("--"));
  const quality = deger("quality", "high");
  fs.mkdirSync(HAM, { recursive: true });
  if (bayrak("list")) { for (const g of PAKETLER) console.log(`${g.ad}\t${g.size}`); return; }
  if (bayrak("isle")) { isle(adlar); return; }
  const key = anahtar();
  const liste = PAKETLER.filter((g) => !adlar.length || adlar.includes(g.ad))
    .filter((g) => bayrak("force") || !fs.existsSync(path.join(HAM, `${g.ad}.png`)));
  await Promise.all(liste.map(async (g) => {
    const dosya = path.join(HAM, `${g.ad}.png`);
    const t0 = Date.now();
    try {
      const usage = await uret(key, g, quality, dosya);
      console.log(`tamam ${g.ad} ${((Date.now() - t0) / 1000).toFixed(0)} sn usage=${JSON.stringify(usage)}`);
      const k = kayitOku();
      k[g.ad] = { model: MODEL, quality, size: g.size, prompt: g.prompt, usage, tarih: new Date().toISOString() };
      fs.writeFileSync(KAYIT, JSON.stringify(k, null, 2));
    } catch (e) {
      console.log(`HATA ${g.ad}: ${e.message}`);
    }
  }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main().catch((e) => { console.error("Hata:", temizle(e.message)); process.exit(1); });
