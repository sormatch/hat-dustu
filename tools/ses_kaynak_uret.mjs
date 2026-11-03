// Ses testi için temiz konuşma kayıtları (OpenAI TTS, farklı sesler). Yalnız test; oyuna girmez.
// Kullanım (D:/HatDustu): node tools/ses_kaynak_uret.mjs   -> build/ses/kaynak/<ad>.wav (16 kHz mono) + _ham.wav
// Anahtar .gizli/openai.txt (yazdırılmaz). Var olan dosya atlanır.
import fs from "node:fs";
import { execFileSync } from "node:child_process";

const KOK = "D:/HatDustu";
const CIKTI = `${KOK}/build/ses/kaynak`;
const FF = "C:/ffmpeg/bin/ffmpeg.exe";
const anahtar = fs.readFileSync(`${KOK}/.gizli/openai.txt`, "utf8").trim();
fs.mkdirSync(CIKTI, { recursive: true });

const KAYITLAR = [
  { ad: "erkek", ses: "onyx", metin: "Alo, beni duyuyor musun? Ben üç numaralı hücredeyim. Bence yalancı Kerem, çünkü az önce şapkası hakkında yalan söyledi. Sen ne düşünüyorsun? Tamam, o zaman oylamada onu seçelim. Hadi görüşürüz." },
  { ad: "kadin", ses: "nova", metin: "Evet, seni çok net duyuyorum. Bekle bir saniye, kapının önünden biri geçiyor. Tamam, gitti. Bence de Kerem şüpheli ama emin değilim, belki Zeynep'tir. Bombayı kimse almasın, ben koridora çıkıyorum." },
  { ad: "genc", ses: "echo", metin: "Ha ha, inanamıyorum! Bomba bende kaldı, birisi alsın şunu! Koş koş koş, dört numara açık mı? Tamam verdim, kurtuldum. Şimdi tünelden kaçıyorum, kaşığı bulan var mı?" },
  { ad: "ince", ses: "shimmer", metin: "Merhaba, sesim geliyor mu? Ben biraz kısık konuşuyorum çünkü yanımda annem uyuyor. Kim kim oyununda ikinci hat bence Mustafa. Sen tahtaya ne yazdın? Ben fil yazdım." },
];

for (const k of KAYITLAR) {
  const hedef = `${CIKTI}/${k.ad}.wav`;
  if (fs.existsSync(hedef)) { console.log("var", k.ad); continue; }
  const r = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: { Authorization: `Bearer ${anahtar}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: "gpt-4o-mini-tts", voice: k.ses, input: k.metin, response_format: "wav",
      instructions: "Doğal, günlük Türkçe konuşma; arkadaşla telefonda sohbet eder gibi, cümle aralarında kısa doğal duraklamalar." }),
  });
  if (!r.ok) {
    const t = await r.text();
    console.log("HATA", k.ad, r.status, t.slice(0, 200));
    if (r.status === 429 || /quota|billing/i.test(t)) process.exit(2);
    continue;
  }
  const ham = `${CIKTI}/${k.ad}_ham.wav`;
  fs.writeFileSync(ham, Buffer.from(await r.arrayBuffer()));
  // 16 kHz mono referans (ölçüm) + 44.1 kHz mono (oyuna mikrofon gibi verilir)
  execFileSync(FF, ["-y", "-loglevel", "error", "-i", ham, "-ac", "1", "-ar", "16000", hedef]);
  execFileSync(FF, ["-y", "-loglevel", "error", "-i", ham, "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", `${CIKTI}/${k.ad}_44k.wav`]);
  console.log("yazildi", k.ad);
}
// ortam gürültüsü kaynağı: oyunun kendi rüzgar/uğultu döngüsü (gerçek mikrofona giren fan / sokak sesi yerine)
const gur = `${CIKTI}/gurultu_44k.wav`;
if (!fs.existsSync(gur)) {
  execFileSync(FF, ["-y", "-loglevel", "error", "-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.25:duration=40:seed=7", "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", gur]);
  console.log("yazildi gurultu");
}
