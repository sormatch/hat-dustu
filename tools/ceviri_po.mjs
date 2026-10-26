// İngilizce çeviri dosyasını üretir: tools/ceviri_en.json (Türkçe -> İngilizce, elle düzenlenen kaynak)
// -> translations/en.po (Godot bunu yükler; project.godot internationalization/locale/translations).
// Kullanım (proje kökünden): node tools/ceviri_po.mjs
// Yeni metin eklediysen: önce node tools/ceviri_tara.mjs ile eksikleri gör, ceviri_en.json'a ekle, bunu çalıştır.
import fs from "node:fs";

const src = JSON.parse(fs.readFileSync("tools/ceviri_en.json", "utf8"));
const esc = (s) => s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\t/g, "\\t");
let out = 'msgid ""\nmsgstr ""\n"Language: en\\n"\n"MIME-Version: 1.0\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n';
out += "# Bu dosya tools/ceviri_po.mjs ile tools/ceviri_en.json'dan üretilir; elle düzenleme.\n\n";
let n = 0;
for (const [tr, en] of Object.entries(src)) {
  if (!tr || !en || tr === en) continue;
  out += `msgid "${esc(tr)}"\nmsgstr "${esc(en)}"\n\n`;
  n++;
}
fs.mkdirSync("translations", { recursive: true });
fs.writeFileSync("translations/en.po", out);
console.log(n + " çeviri yazıldı -> translations/en.po");
