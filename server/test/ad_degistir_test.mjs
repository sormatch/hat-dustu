// Kullanıcı adı değiştirme, uçtan uca (yerel sunucu): cd server && SRV=ws://127.0.0.1:8794 node test/ad_degistir_test.mjs
import { hesapAc } from "./_hesap.mjs";
const URL0 = process.env.SRV || "ws://127.0.0.1:8794";
let hata = 0;
const bak = (ad, kosul) => { console.log((kosul ? "  OK   " : "  HATA ") + ad); if (!kosul) hata++; };
const bagla = (token) => new Promise((res) => {
  const ws = new WebSocket(`${URL0}/hesap?token=${token}`);
  const msgs = [];
  ws.onmessage = (e) => { if (typeof e.data === "string" && e.data !== "pong") msgs.push(JSON.parse(e.data)); };
  ws.onopen = () => res({ ws, msgs, yolla: (o) => ws.send(JSON.stringify(o)) });
});
const bekle = async (b, f, ms = 5000) => {
  const bas = Date.now();
  for (;;) {
    const i = b.msgs.findIndex(f);
    if (i >= 0) return b.msgs.splice(i, 1)[0];
    if (Date.now() - bas > ms) return null;
    await new Promise((r) => setTimeout(r, 40));
  }
};
const ek = Math.random().toString(36).slice(2, 7);
const a = await hesapAc(URL0, "ada" + ek);
const b = await hesapAc(URL0, "adb" + ek);
const ca = await bagla(a.token);
const cb = await bagla(b.token);
await bekle(ca, (d) => d.t === "ben");
await bekle(cb, (d) => d.t === "ben");
// arkadaş olsunlar
ca.yolla({ t: "istek", handle: b.handle });
await bekle(cb, (d) => d.t === "istek" || d.t === "liste", 2000);
cb.yolla({ t: "istek", handle: a.handle });
await new Promise((r) => setTimeout(r, 500));

ca.yolla({ t: "ad_degistir", handle: "A B" });
bak("boşluklu ad reddedildi", !!(await bekle(ca, (d) => d.t === "hata")));
ca.yolla({ t: "ad_degistir", handle: b.handle });
bak("alınmış ad reddedildi", !!(await bekle(ca, (d) => d.t === "hata")));
const yeni = "yn" + ek;
ca.msgs.length = 0;
cb.msgs.length = 0;
ca.yolla({ t: "ad_degistir", handle: yeni });
const ben = await bekle(ca, (d) => d.t === "ben");
bak("yeni ad kabul edildi", ben && ben.handle === yeni);
bak("bilgi mesajı", !!(await bekle(ca, (d) => d.t === "bilgi")));
const liste = await bekle(cb, (d) => JSON.stringify(d).includes(yeni));
bak("arkadaşı yeni adı görüyor", !!liste);
ca.yolla({ t: "ad_degistir", handle: "ik" + ek });
bak("7 gün dolmadan reddedildi", !!(await bekle(ca, (d) => d.t === "hata")));
ca.ws.close();
cb.ws.close();
console.log(hata ? `${hata} HATA` : "ad_degistir_test: tamam");
process.exit(hata ? 1 : 0);
