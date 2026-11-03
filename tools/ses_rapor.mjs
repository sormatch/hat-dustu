// tools/ses_senaryo.gd kayıtlarını ölçer. Kullanım: node tools/ses_rapor.mjs <cikti.wav> <refA|-> [refB] [--gecikme_a=0.3 --gecikme_b=0.3]
// Ölçüler (16 kHz'e indirilmiş çıkışta, 10 ms'lik pencerelerle):
//  kirpma   : tavana (|x| >= 0.97) çarpan örnek sayısı (cızırtı / çatlama)
//  sekme    : konuşma sürerken çıkışın sustuğu 30 ms ve üstü boşluk sayısı / toplam ms (ses kesilmesi)
//  gurultu  : konuşma yokken çıkıştaki hışırtı seviyesi (dBFS; -60 altı duyulmaz)
//  netlik   : konuşmanın kaynakla benzerliği (300-3400 Hz, bölüm SNR, dB; 15 üstü iyi, 20 üstü çok iyi)
//  gecikme  : kaynak ile çıkış arasındaki süre (ms)
import fs from "node:fs";
import { execFileSync } from "node:child_process";
const FF = "C:/ffmpeg/bin/ffmpeg.exe";
const KAYNAK = "D:/HatDustu/build/ses/kaynak/";

function oku(yol) {
  const b = fs.readFileSync(yol);
  let i = 12, kanal = 1, veri = null;
  while (i + 8 <= b.length) {
    const ad = b.toString("latin1", i, i + 4), boy = b.readUInt32LE(i + 4);
    if (ad === "fmt ") kanal = b.readUInt16LE(i + 10);
    if (ad === "data") veri = b.subarray(i + 8, Math.min(i + 8 + boy, b.length));
    i += 8 + boy + (boy & 1);
  }
  const n = Math.floor(veri.length / 2 / kanal), x = new Float64Array(n);
  for (let k = 0; k < n; k++) { let t = 0; for (let c = 0; c < kanal; c++) t += veri.readInt16LE((k * kanal + c) * 2) / 32768; x[k] = t / kanal; }
  return x;
}
function ref(ad, gecikme) {
  if (!ad || ad === "-") return null;
  const r = oku(`${KAYNAK}${ad}.wav`), off = Math.round(gecikme * 16000), x = new Float64Array(r.length + off);
  x.set(r, off);
  return x;
}
// basit ikinci derece bant geçiren (biquad, 300-3400 Hz)
function bant(x) {
  const yap = (f0, q, tur) => {
    const w = (2 * Math.PI * f0) / 16000, a = Math.sin(w) / (2 * q), c = Math.cos(w);
    let b0, b1, b2;
    if (tur === "hp") { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2; } else { b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2; }
    const a0 = 1 + a, a1 = -2 * c, a2 = 1 - a;
    return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0];
  };
  const uygula = (x, k) => { const y = new Float64Array(x.length); let x1 = 0, x2 = 0, y1 = 0, y2 = 0; for (let i = 0; i < x.length; i++) { const v = k[0] * x[i] + k[1] * x1 + k[2] * x2 - k[3] * y1 - k[4] * y2; x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v; } return y; };
  return uygula(uygula(x, yap(300, 0.707, "hp")), yap(3400, 0.707, "lp"));
}
const P = 160; // 10 ms
const zarf = (x) => { const n = Math.floor(x.length / P), e = new Float64Array(n); for (let i = 0; i < n; i++) { let s = 0; for (let k = 0; k < P; k++) s += x[i * P + k] ** 2; e[i] = Math.sqrt(s / P); } return e; };
const db = (v) => (20 * Math.log10(Math.max(v, 1e-9))).toFixed(1);

const arg = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const opt = Object.fromEntries(process.argv.slice(2).filter((a) => a.startsWith("--")).map((a) => a.slice(2).split("=")));
const [cikti, aAd, bAd] = arg;
const gecici = cikti.replace(/\.wav$/, "_16k.wav");
execFileSync(FF, ["-y", "-loglevel", "error", "-i", cikti, "-ac", "1", "-ar", "16000", gecici]);
const y = oku(gecici);
const ys = oku(cikti);
let kirp = 0;
for (const v of ys) if (Math.abs(v) >= 0.97) kirp++;
const ra = ref(aAd, Number(opt.gecikme_a ?? 0.3)), rb = ref(bAd, Number(opt.gecikme_b ?? 0.3));
const n = y.length;
let r = new Float64Array(n);
for (const q of [ra, rb]) if (q) for (let i = 0; i < Math.min(n, q.length); i++) r[i] += q[i];
const ey = zarf(y);
// kaynak ile çıkış arasındaki gecikme: örnek düzeyinde ilişki (0-1000 ms, 4 örnek adım), sonra 10 ms pencereye yuvarlanır
const er0 = zarf(r);
let gec = 0, gecOrnek = 0;
{ let best = -1; const bas = Math.min(32000, Math.floor(n / 4)), son = Math.min(n, bas + 96000);
  for (let d = 0; d <= 16000; d += 4) { let sxy = 0, sxx = 0, syy = 0; for (let i = bas; i < son; i += 3) { const j = i - d; if (j < 0 || j >= r.length) continue; sxy += y[i] * r[j]; sxx += r[j] * r[j]; syy += y[i] * y[i]; } const c = sxy / Math.sqrt(sxx * syy + 1e-12); if (c > best) { best = c; gecOrnek = d; } }
  gec = Math.round(gecOrnek / P); }
// konuşma araları (ses kapısı) zamanlamayı kaydırır: her 1 sn'lik pencere için gecikme ayrı bulunur (önceki ±150 ms)
const yb = bant(y), rbn = bant(r);
const W = 4000, gecler = [];
let merkez = gecOrnek;
const kor = (s0, d) => { let sxy = 0, sxx = 0, syy = 0; for (let i = s0; i < Math.min(n, s0 + W); i += 2) { const j = i - d; if (j < 0 || j >= rbn.length) continue; sxy += yb[i] * rbn[j]; sxx += rbn[j] * rbn[j]; syy += yb[i] * yb[i]; } return sxx > 1e-6 ? sxy / Math.sqrt(sxx * syy + 1e-12) : -1; };
for (let s0 = 0; s0 < n; s0 += W) {
  // önce yakın (±100 ms), zayıfsa geniş (±300 ms) arama; geniş sonuç ancak belirgin daha iyiyse kabul (sesli harflerin tekrarı yanıltmasın)
  let best = -1, L = merkez;
  for (let d = merkez - 1600; d <= merkez + 1600; d += 2) { const c = kor(s0, d); if (c > best) { best = c; L = d; } }
  if (best < 0.5) { let b2 = -1, L2 = L; for (let d = Math.max(0, merkez - 4800); d <= merkez + 4800; d += 4) { const c = kor(s0, d); if (c > b2) { b2 = c; L2 = d; } } if (b2 > best + 0.15 && b2 > 0.4) { best = b2; L = L2; } }
  if (best > 0.3) merkez = L;
  gecler.push(merkez);
}
const lagAt = (i) => gecler[Math.min(gecler.length - 1, Math.floor(i / W))];
const eyb = zarf(yb);
const er = new Float64Array(ey.length);
for (let f = 0; f < ey.length; f++) { const j0 = f * P - lagAt(f * P); let e = 0; for (let k = 0; k < P; k++) { const j = j0 + k; const v = j >= 0 && j < rbn.length ? rbn[j] : 0; e += v * v; } er[f] = Math.sqrt(e / P); }
const tepe = Math.max(...er);
const aktif = (i) => er[i] > tepe * 0.06;
const aktifCikis = [];
for (let i = 0; i < ey.length; i++) if (aktif(i)) aktifCikis.push(eyb[i]);
aktifCikis.sort((a, b) => a - b);
const medyan = aktifCikis.length ? aktifCikis[Math.floor(aktifCikis.length / 2)] : 0;
let sekme = 0, sekmeMs = 0, kos = 0;
for (let i = 0; i < ey.length; i++) {
  const bos = aktif(i) && eyb[i] < medyan * 0.08;
  if (bos) kos++;
  if (!bos || i === ey.length - 1) { if (kos >= 3) { sekme++; sekmeMs += kos * 10; if (opt.yer) console.log("  sekme", ((i - kos) / 100).toFixed(2), "sn", kos * 10, "ms"); } kos = 0; }
}
const sessiz = [];
let sonAktif = -999;
for (let i = 0; i < ey.length; i++) { if (er[i] > tepe * 0.01) sonAktif = i; else if (i - sonAktif > 60 && i > 150) sessiz.push(ey[i]); }
sessiz.sort((a, b) => a - b);
const gurultu = sessiz.length ? sessiz[Math.floor(sessiz.length * 0.5)] : 0;
// netlik: log-spektral uzaklık (300-3400 Hz, 512 örnek, dB): 2 altı mükemmel, 2-4 iyi, 4-6 orta, 6 üstü bozuk
function fftGuc(x) { const N = x.length, re = Float64Array.from(x), im = new Float64Array(N);
  for (let i = 1, j = 0; i < N; i++) { let bit = N >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { [re[i], re[j]] = [re[j], re[i]]; } }
  for (let len = 2; len <= N; len <<= 1) { const ang = (-2 * Math.PI) / len; for (let i = 0; i < N; i += len) for (let k = 0; k < len / 2; k++) { const wr = Math.cos(ang * k), wi = Math.sin(ang * k); const ur = re[i + k], ui = im[i + k]; const vr = re[i + k + len / 2] * wr - im[i + k + len / 2] * wi, vi = re[i + k + len / 2] * wi + im[i + k + len / 2] * wr; re[i + k] = ur + vr; im[i + k] = ui + vi; re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi; } }
  const g = new Float64Array(N / 2); for (let k = 0; k < N / 2; k++) g[k] = re[k] * re[k] + im[k] * im[k]; return g; }
const pen = Float64Array.from({ length: 512 }, (_, i) => 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / 511));
const k1 = Math.round((300 / 8000) * 256), k2 = Math.round((3400 / 8000) * 256);
let lsdTop = 0, lsdN = 0;
for (let f = 0; f + 512 <= n; f += 320) {
  const L = lagAt(f); const a = new Float64Array(512), b2 = new Float64Array(512); let e = 0;
  for (let i = 0; i < 512; i++) { const j = f + i - L; const v = j >= 0 && j < r.length ? r[j] : 0; a[i] = v * pen[i]; b2[i] = y[f + i] * pen[i]; e += v * v; }
  if (Math.sqrt(e / 512) < tepe * 0.15) continue;
  const ga = fftGuc(a), gb = fftGuc(b2); const d = [];
  for (let k = k1; k <= k2; k++) d.push(10 * Math.log10(gb[k] + 1e-10) - 10 * Math.log10(ga[k] + 1e-10));
  const m = d.reduce((x, z) => x + z, 0) / d.length;
  lsdTop += Math.sqrt(d.reduce((x, z) => x + (z - m) ** 2, 0) / d.length); lsdN++; }
const netlik = lsdN ? (lsdTop / lsdN).toFixed(2) : '-';
console.log(`${cikti.split(/[\\/]/).pop().padEnd(22)} kirpma=${String(kirp).padStart(5)}  sekme=${String(sekme).padStart(3)} (${String(sekmeMs).padStart(4)} ms)  gurultu=${db(gurultu)} dBFS  bozulma=${netlik} dB  gecikme=${Math.round(gecOrnek / 16)} ms`);
fs.unlinkSync(gecici);
