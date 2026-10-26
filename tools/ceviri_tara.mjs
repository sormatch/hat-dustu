// Çeviri tarayıcısı: scripts/*.gd ve server/src/**/*.js içindeki kullanıcıya görünebilecek Türkçe dizeleri bulur,
// translations/en.po ile karşılaştırır. Kullanım (proje kökünden):
//   node tools/ceviri_tara.mjs            -> eksik çevirileri ve tr() ile sarılmamış biçimli dizeleri listeler
//   node tools/ceviri_tara.mjs --json f   -> tüm adayları JSON olarak f dosyasına yazar
// Sadece okur; hiçbir dosyayı değiştirmez.
import fs from "node:fs";
import path from "node:path";

const KOK = process.cwd();
const TR_HARF = /[çğıöşüÇĞİÖŞÜ]/;

function dosyalar(dir, uzanti) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...dosyalar(p, uzanti));
    else if (uzanti.some((u) => e.name.endsWith(u))) out.push(p);
  }
  return out;
}

// Bir satırdaki dize sabitlerini (başlangıç sütunu, bitiş sütunu, içerik) bulur; # / // yorumundan sonrası atlanır.
function dizeler(satir, js) {
  const out = [];
  let i = 0;
  while (i < satir.length) {
    const c = satir[i];
    if (!js && c === "#") break;
    if (js && c === "/" && satir[i + 1] === "/") break;
    if (c === '"' || c === "'" || (js && c === "`")) {
      let j = i + 1;
      let s = "";
      while (j < satir.length && satir[j] !== c) {
        if (satir[j] === "\\") {
          s += satir[j] + (satir[j + 1] || "");
          j += 2;
          continue;
        }
        s += satir[j];
        j++;
      }
      out.push({ bas: i, son: j, s, tirnak: c });
      i = j + 1;
      continue;
    }
    i++;
  }
  return out;
}

export function metinMi(s) {
  if (!/[A-Za-zÇĞİÖŞÜçğıöşü]/.test(s)) return false;
  if (/^(res|user|http|https|wss?):\/\//.test(s)) return false;
  if (/^#[0-9a-fA-F]{3,8}$/.test(s)) return false;
  if (/^[a-z0-9_:\/.\-]+$/.test(s) && !TR_HARF.test(s)) return false; // anahtar / yol / kimlik
  if (/^[A-Z][a-zA-Z0-9]+$/.test(s) && !TR_HARF.test(s) && /[a-z]/.test(s) && /[A-Z].*[A-Z]/.test(s)) return false; // CamelCase sınıf adı
  return true;
}

function ac(s) {
  // GDScript kaçışlarını çöz (\n, \t, \", \\)
  return s.replace(/\\(.)/g, (_, k) => ({ n: "\n", t: "\t", '"': '"', "'": "'", "\\": "\\" })[k] ?? "\\" + k);
}

export function tara() {
  const adaylar = [];
  const gd = dosyalar(path.join(KOK, "scripts"), [".gd"]);
  const js = dosyalar(path.join(KOK, "server", "src"), [".js"]);
  for (const f of [...gd, ...js]) {
    const isJs = f.endsWith(".js");
    const rel = path.relative(KOK, f).replace(/\\/g, "/");
    const satirlar = fs.readFileSync(f, "utf8").split(/\r?\n/);
    satirlar.forEach((satir, n) => {
      for (const d of dizeler(satir, isJs)) {
        if (!metinMi(d.s)) continue;
        const once = satir.slice(0, d.bas).trimEnd();
        const sonra = satir.slice(d.son + 1).trimStart();
        const sarili = /\b(tr|atr|translate|_t|T)\($/.test(once);
        let tur = "duz";
        if (sonra.startsWith("%") && !sonra.startsWith("%=")) tur = "bicim";
        else if (sonra.startsWith("+") || once.endsWith("+")) tur = "ekleme";
        else if (sonra.startsWith(".format(")) tur = "bicim";
        adaylar.push({ dosya: rel, satir: n + 1, s: isJs ? d.s : ac(d.s), tur, sarili, kod: satir.trim().slice(0, 200) });
      }
    });
  }
  return adaylar;
}

export function poOku(p) {
  const map = new Map();
  if (!fs.existsSync(p)) return map;
  const txt = fs.readFileSync(p, "utf8");
  const re = /msgid ((?:"(?:[^"\\]|\\.)*"\s*)+)msgstr ((?:"(?:[^"\\]|\\.)*"\s*)+)/g;
  const birles = (blok) => [...blok.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => ac(m[1])).join("");
  let m;
  while ((m = re.exec(txt))) {
    const id = birles(m[1]);
    if (id) map.set(id, birles(m[2]));
  }
  return map;
}

if (process.argv[1] && process.argv[1].endsWith("ceviri_tara.mjs")) {
  const ad = tara();
  const ji = process.argv.indexOf("--json");
  if (ji > 0) {
    fs.writeFileSync(process.argv[ji + 1], JSON.stringify(ad, null, 1));
    console.log(ad.length + " aday yazıldı");
  } else {
    const po = poOku(path.join(KOK, "translations", "en.po"));
    // eksik: Türkçe harfli ya da boşluklu (cümle) olup po'da olmayanlar; teknik dosyalar ve bilinen yoksayılanlar hariç
    const TEKNIK = /el_test|hareketler\.gd|model_body|hair\.gd|aim_mod|telemetri|thumbs|aksesuar\.gd|body\.gd|props\.gd|gizlilik\.js|hesap_sil\.js|suzgec|oyunici_test|ui\.gd/;
    const YOKSAY = new Set(fs.existsSync("tools/ceviri_yoksay.txt") ? fs.readFileSync("tools/ceviri_yoksay.txt", "utf8").split(/\r?\n/).filter(Boolean) : []);
    const eksik = new Map();
    for (const a of ad) {
      if (po.has(a.s) || YOKSAY.has(a.s) || TEKNIK.test(a.dosya)) continue;
      if (/^(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER)\b|^\[(test|el|ses)\]|^\$\{|[?&=]|^%s\//.test(a.s)) continue;
      if (TR_HARF.test(a.s) || /\S\s+\S/.test(a.s)) eksik.set(a.s, a);
    }
    console.log("Aday: " + ad.length + "  po: " + po.size + "  eksik: " + eksik.size);
    for (const [s, a] of eksik) console.log(`${a.dosya}:${a.satir}  ${JSON.stringify(s)}`);
    const sarilmamis = ad.filter((a) => a.dosya.endsWith(".gd") && a.tur !== "duz" && !a.sarili);
    console.log("\ntr() ile sarılmamış biçimli/eklemeli: " + sarilmamis.length);
    for (const a of sarilmamis) console.log(`${a.dosya}:${a.satir}  [${a.tur}] ${a.kod}`);
  }
}
