// tools/ses_test.gd kayıtlarını ölçer. Kullanım: node tools/ses_olc.mjs <hz> a.wav b.wav ...
// Ton kayıtlarında: seviye, temiz sinyal oranı (SNR), kopma sayısı/toplamı; hz=0: yalnız seviye ve kopma.
import fs from "node:fs";

function oku(yol) {
  const b = fs.readFileSync(yol);
  let i = 12, kanal = 2, oran = 44100, bit = 16, veri = null;
  while (i + 8 <= b.length) {
    const ad = b.toString("latin1", i, i + 4);
    const boy = b.readUInt32LE(i + 4);
    if (ad === "fmt ") { kanal = b.readUInt16LE(i + 10); oran = b.readUInt32LE(i + 12); bit = b.readUInt16LE(i + 22); }
    if (ad === "data") veri = b.subarray(i + 8, Math.min(i + 8 + boy, b.length));
    i += 8 + boy + (boy & 1);
  }
  const n = Math.floor(veri.length / (bit / 8) / kanal);
  const x = new Float64Array(n);
  for (let k = 0; k < n; k++) {
    let t = 0;
    for (let c = 0; c < kanal; c++) t += veri.readInt16LE((k * kanal + c) * 2) / 32768;
    x[k] = t / kanal;
  }
  return { x, oran };
}

const hz = Number(process.argv[2]);
for (const yol of process.argv.slice(3)) {
  const { x, oran } = oku(yol);
  const bas = Math.floor(oran * 1.2);
  const son = x.length;
  const pencere = Math.floor(oran * 0.01);
  // kopmalar: 10 ms'lik pencere sessiz (ilk sesten sonra)
  let kopma = 0, kopmaMs = 0, icinde = false, ust = 0;
  for (let i = bas; i + pencere < son; i += pencere) {
    let e = 0;
    for (let k = 0; k < pencere; k++) e += x[i + k] * x[i + k];
    e = Math.sqrt(e / pencere);
    if (e > ust) ust = e;
    const s = e < 0.002;
    if (s) { kopmaMs += 10; if (!icinde) kopma++; }
    icinde = s;
  }
  let toplam = 0;
  for (let i = bas; i < son; i++) toplam += x[i] * x[i];
  const rms = Math.sqrt(toplam / Math.max(1, son - bas));
  let kirp=0,sert=0;for(let i=bas;i<son;i++){const a=Math.abs(x[i]);if(a>0.97)kirp++;if(i>bas&&Math.abs(x[i]-x[i-1])>0.5)sert++;}
  let satir = `kirpma=${kirp} sicrama=${sert} ${yol.split(/[\\/]/).pop().padEnd(26)} rms=${rms.toFixed(4)} kopma=${String(kopma).padStart(3)} (${kopmaMs} ms)`;
  if (hz > 0) {
    // 100 ms'lik sessiz olmayan pencerelerde en iyi uyan sinüs çıkarılır: kalan = gürültü + bozulma
    const bl = Math.floor(oran * 0.1);
    let sinyal = 0, kalan = 0;
    for (let i = bas; i + bl < son; i += bl) {
      let sa = 0, ca = 0, e = 0;
      for (let k = 0; k < bl; k++) {
        const w = (2 * Math.PI * hz * k) / oran;
        sa += x[i + k] * Math.sin(w);
        ca += x[i + k] * Math.cos(w);
        e += x[i + k] * x[i + k];
      }
      if (Math.sqrt(e / bl) < 0.01) continue;
      const a = (2 * sa) / bl, c = (2 * ca) / bl;
      const p = (a * a + c * c) / 2;
      sinyal += p * bl;
      kalan += Math.max(0, e - p * bl);
    }
    satir += ` SNR=${(10 * Math.log10(sinyal / Math.max(kalan, 1e-12))).toFixed(1)} dB`;
  }
  console.log(satir);
}
