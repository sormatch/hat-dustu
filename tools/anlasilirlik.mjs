// Konuşma anlaşılırlığı ölçümü (STOI benzeri, kaba): temiz kayıt ile işlenmiş kaydın 300-3400 Hz arası
// 12 banttaki enerji zarflarının (25 ms pencere, 10 ms adım) zaman içindeki benzerliği. 1.0 = aynı, ~0 = anlaşılmaz.
// Kullanım: node tools/anlasilirlik.mjs temiz.wav islenmis.wav
import { spawnSync } from 'child_process';

const FF = 'C:/ffmpeg/bin/ffmpeg.exe';
const ORAN = 16000;
function oku(f) {
  const r = spawnSync(FF, ['-v', 'error', '-i', f, '-ac', '1', '-ar', String(ORAN), '-f', 'f32le', '-'], { maxBuffer: 1 << 28 });
  const b = r.stdout;
  return new Float32Array(b.buffer, b.byteOffset, b.length / 4);
}
function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const a = (-2 * Math.PI) / len;
    for (let i = 0; i < n; i += len) for (let k = 0; k < len / 2; k++) {
      const c = Math.cos(a * k), s = Math.sin(a * k);
      const xr = re[i + k + len / 2] * c - im[i + k + len / 2] * s, xi = re[i + k + len / 2] * s + im[i + k + len / 2] * c;
      re[i + k + len / 2] = re[i + k] - xr; im[i + k + len / 2] = im[i + k] - xi;
      re[i + k] += xr; im[i + k] += xi;
    }
  }
}
const N = 512, ADIM = 160, PEN = 400;
const sinirlar = [];
for (let k = 0; k <= 12; k++) sinirlar.push(300 * Math.pow(3400 / 300, k / 12));
function zarf(x) {
  const out = [];
  for (let p = 0; p + PEN <= x.length; p += ADIM) {
    const re = new Float64Array(N), im = new Float64Array(N);
    for (let i = 0; i < PEN; i++) re[i] = x[p + i] * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / PEN));
    fft(re, im);
    const bant = [];
    for (let b = 0; b < 12; b++) {
      let e = 1e-9;
      const lo = Math.floor((sinirlar[b] * N) / ORAN), hi = Math.ceil((sinirlar[b + 1] * N) / ORAN);
      for (let k = lo; k < hi; k++) e += re[k] * re[k] + im[k] * im[k];
      bant.push(Math.log10(e));
    }
    out.push(bant);
  }
  return out;
}
function kor(a, b) {
  const n = a.length;
  const ma = a.reduce((s, v) => s + v, 0) / n, mb = b.reduce((s, v) => s + v, 0) / n;
  let sab = 0, saa = 0, sbb = 0;
  for (let i = 0; i < n; i++) { sab += (a[i] - ma) * (b[i] - mb); saa += (a[i] - ma) ** 2; sbb += (b[i] - mb) ** 2; }
  return sab / Math.sqrt(saa * sbb + 1e-12);
}
const A = zarf(oku(process.argv[2]));
const B = zarf(oku(process.argv[3]));
// gecikme farkını bul (±300 ms) ve en iyi hizada ölç
let en = -1, enG = 0;
for (let g = -30; g <= 30; g++) {
  const a = [], b = [];
  for (let i = 0; i < A.length; i++) if (i + g >= 0 && i + g < B.length) { a.push(A[i][5]); b.push(B[i + g][5]); }
  const k = kor(a, b);
  if (k > en) { en = k; enG = g; }
}
let top = 0;
for (let bnt = 0; bnt < 12; bnt++) {
  const a = [], b = [];
  for (let i = 0; i < A.length; i++) if (i + enG >= 0 && i + enG < B.length && A[i][bnt] > Math.max(...A.map((r) => r[bnt])) - 4) { a.push(A[i][bnt]); b.push(B[i + enG][bnt]); }
  top += kor(a, b);
}
console.log(`anlasilirlik=${(top / 12).toFixed(3)} gecikme=${enG * 10}ms`);
