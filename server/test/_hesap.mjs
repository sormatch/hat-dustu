// Uçtan uca testler için hesap yardımcısı: misafir artık odaya / Hızlı Oyun'a giremez, testler gerçek hesap açar.
//   const h = await hesapAc(URL0, "ali");   // { token, handle, eposta }
//   await hesapSil(URL0, h.token);           // test sonunda (isteğe bağlı)
import crypto from "node:crypto";

export const rastgeleAnahtar = () => crypto.randomBytes(16).toString("hex");

function bagla(URL0, token) {
  return new Promise((res, rej) => {
    const ws = new WebSocket(`${URL0}/hesap?token=${token}`);
    const msgs = [];
    const bekleyen = [];
    ws.onmessage = (e) => {
      if (typeof e.data !== "string" || e.data === "pong") return;
      const d = JSON.parse(e.data);
      msgs.push(d);
      for (const w of [...bekleyen]) if (w.f(d)) (bekleyen.splice(bekleyen.indexOf(w), 1), w.r(d));
    };
    ws.onerror = rej;
    ws.onopen = () =>
      res({
        ws, msgs,
        bekle(f, ms = 8000) {
          const hazir = msgs.find(f);
          if (hazir) return Promise.resolve(hazir);
          return new Promise((r) => {
            const w = { f, r };
            bekleyen.push(w);
            setTimeout(() => (bekleyen.includes(w) ? (bekleyen.splice(bekleyen.indexOf(w), 1), r(null)) : 0), ms);
          });
        },
        gonder(o) {
          ws.send(JSON.stringify(o));
        },
      });
  });
}

// Yeni hesap açar (kullanıcı adı en fazla 16 harf). Başarısızsa hata fırlatır.
export async function hesapAc(URL0, onek = "t", token = rastgeleAnahtar()) {
  const handle = (String(onek).toLowerCase().replace(/[^a-z0-9_.]/g, "").slice(0, 8) || "t") + crypto.randomBytes(3).toString("hex");
  const eposta = `${handle}@test.hatdustu.app`;
  const c = await bagla(URL0, token);
  await c.bekle((d) => d.t === "ben");
  c.gonder({ t: "uye_ol", handle, eposta, sifre: "Test-12345", dil: "tr" });
  const r = await c.bekle((d) => d.t === "hata" || (d.t === "ben" && d.hesap));
  c.ws.close();
  if (!r || r.t !== "ben") throw new Error("hesap açılamadı: " + JSON.stringify(r));
  return { token, handle, eposta };
}

export async function hesapSil(URL0, token) {
  try {
    const c = await bagla(URL0, token);
    await c.bekle((d) => d.t === "ben", 3000);
    c.gonder({ t: "hesap_sil" });
    await c.bekle((d) => d.t === "hesap_silindi", 3000);
    c.ws.close();
  } catch {}
}

export { bagla };
