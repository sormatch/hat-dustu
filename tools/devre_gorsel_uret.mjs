// Kısa Devre sigorta kutusu parçaları — OpenAI görsel üretimi.
// Kullanım (D:/HatDustu içinde): node tools/devre_gorsel_uret.mjs [ad ...] [--force]
// Saydam parçalar gpt-image-1.5, saydam olmayanlar gpt-image-2. Anahtar: .gizli/openai.txt (asla yazdırılmaz).
// Çıktı: assets/ui/devre/<ad>.png

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const KOK = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CIKTI = path.join(KOK, "assets", "ui", "devre");

const GERCEK = "Photorealistic high-detail game asset render, realistic materials, soft even studio light from the top-left, crisp edges.";
const SAYDAM = "Single object only, centered with a small empty margin, nothing cropped, fully transparent background, no floor, no backdrop, no cast shadow.";
const YAZISIZ = "Absolutely no text, no letters, no numbers, no watermark, no logo.";

const GORSELLER = [
  {
    ad: "zemin", size: "1536x1024", transparent: false,
    prompt: `Straight-on orthographic front view, flat texture filling the entire canvas edge to edge: the inside back plate of an old industrial electrical cabinet in a prison. Grimy dark olive-grey painted steel sheet, worn and chipped paint, rust streaks running down, water stains, fine scratches, subtle dents, a few small bolts near the corners, rows of small perforated mounting holes along the top and bottom edges. Slight darker vignette toward the edges. Even soft overhead lighting, no strong highlights. Completely empty: no wires, no components, no switches, no stickers. ${GERCEK} ${YAZISIZ}`,
  },
  {
    ad: "kapak", size: "1536x1024", transparent: true,
    prompt: `Front view, perfectly flat and straight-on: the closed rectangular steel door of a wall-mounted industrial electrical box, landscape orientation, filling most of the canvas. Rusty dark olive-green painted steel with rounded folded edges, chipped paint, rust spots, scratches, two heavy hinges on the left edge, a recessed T-handle latch on the right edge, and in the middle a weathered yellow and black triangular warning sticker showing only a lightning bolt symbol. ${GERCEK} Transparent background outside the door. ${YAZISIZ}`,
  },
  {
    ad: "priz", size: "1024x1024", transparent: true,
    prompt: `Looking straight into it, front view: a single heavy-duty round industrial panel socket. Black bakelite face with one large round hole in the exact center lined with a brass contact sleeve, surrounded by a thick brushed steel bezel ring with four small screws, slightly worn and dusty. Perfectly circular, centered. ${GERCEK} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "fis", size: "1536x1024", transparent: true,
    prompt: `Side view, perfectly horizontal, pointing to the right: a heavy-duty single-pole industrial cable plug. On the left a ribbed matte black rubber grip boot (its left end cut flat where a cable would enter), then a knurled brass collar, then a solid polished copper contact pin sticking out to the right with a rounded tip. No cable attached. ${GERCEK} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "plaka", size: "1536x1024", transparent: true,
    prompt: `Front view, flat: a small blank vintage enamel label plate, landscape rectangle with rounded corners, cream off-white enamel on steel, chipped edges showing dark metal underneath, slightly dirty and scuffed, one brass rivet near the left edge and one near the right edge. The face is completely blank and empty. ${GERCEK} ${SAYDAM} ${YAZISIZ} No symbol.`,
  },
  {
    ad: "sigorta", size: "1024x1536", transparent: true,
    prompt: `Front view, perfectly vertical: a single vintage glass cartridge fuse. Clear glass tube with polished brass end caps at the top and bottom, a thin glowing-hot orange filament wire running straight through the center, a subtle warm glow inside the glass. ${GERCEK} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "sigorta_yanik", size: "1024x1536", transparent: true,
    prompt: `Front view, perfectly vertical: a single BLOWN vintage glass cartridge fuse. Glass tube with brass end caps at the top and bottom; the glass is blackened with soot inside and has a visible crack, the filament wire is broken and melted in the middle, scorch marks on the brass caps, a wisp of smoke. ${GERCEK} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "salter_govde", size: "1024x1536", transparent: true,
    prompt: `Front view, perfectly flat: the base of a large vintage industrial main breaker switch, a vertical rectangular heavy black bakelite plate with rounded corners, brass bolts in the four corners, a long straight vertical slot running down the center (empty, no lever), a small red painted band at the bottom of the slot and a small green painted band at the top of the slot, worn edges. ${GERCEK} ${SAYDAM} ${YAZISIZ} No lever, no handle.`,
  },
  {
    ad: "salter_kol", size: "1536x1024", transparent: true,
    prompt: `Front view: a chunky industrial lever grip handle, a thick horizontal red bakelite bar handle with rounded ends and finger grooves, mounted on a short polished steel shaft that goes straight down from its middle. Centered. ${GERCEK} ${SAYDAM} ${YAZISIZ}`,
  },
  {
    ad: "rakor", size: "1024x1024", transparent: true,
    prompt: `Side view, perfectly horizontal, pointing to the right: a brass cable gland (cable entry fitting): a hexagonal brass nut body on the left and a rounded tapered dome cap on the right with a round opening where a cable exits to the right. No cable. ${GERCEK} ${SAYDAM} ${YAZISIZ}`,
  },
];

function anahtar() {
  const k = fs.readFileSync(path.join(KOK, ".gizli", "openai.txt"), "utf8").trim();
  if (!k) throw new Error("Anahtar dosyası boş");
  return k;
}
const temizle = (s) => String(s).replace(/sk-[A-Za-z0-9_\-*.]+/g, "sk-***");

async function uret(key, g, dosya) {
  const govde = {
    model: g.transparent ? "gpt-image-1.5" : "gpt-image-2",
    prompt: g.prompt, size: g.size, quality: "high", n: 1, output_format: "png",
    background: g.transparent ? "transparent" : "opaque",
  };
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
  return govde.model;
}

async function main() {
  const args = process.argv.slice(2);
  const force = args.includes("--force");
  const adlar = args.filter((a) => !a.startsWith("--"));
  fs.mkdirSync(CIKTI, { recursive: true });
  const key = anahtar();
  const liste = GORSELLER.filter((g) => !adlar.length || adlar.includes(g.ad));
  await Promise.all(liste.map(async (g) => {
    const dosya = path.join(CIKTI, `${g.ad}.png`);
    if (fs.existsSync(dosya) && !force) return console.log(`atla ${g.ad}`);
    const t0 = Date.now();
    try {
      const m = await uret(key, g, dosya);
      console.log(`tamam ${g.ad} (${m}) ${((Date.now() - t0) / 1000).toFixed(0)} sn`);
    } catch (e) {
      console.log(`HATA ${g.ad}: ${e.message}`);
    }
  }));
}

main().catch((e) => { console.error("Hata:", temizle(e.message)); process.exit(1); });
