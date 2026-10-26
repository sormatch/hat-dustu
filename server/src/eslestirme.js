// HIZLI OYUN eşleştirmesi: tek bir "Eslestirme" nesnesi açık (herkese açık) odaları tutar.
// Oyuncu /hizli ister → dolmamış ve başlamamış bir açık oda varsa onun kodu, yoksa yeni bir kod verilir.
// Odalar kişi sayısını ve başladığını buraya bildirir (/durum). Eski kayıtlar kendiliğinden silinir.

const CODE_CHARS = "ABCDEFGHJKLMNPRSTUVYZ23456789";
export const PUBLIC_MAX = 6; // açık odada en fazla bu kadar gerçek oyuncu beklenir

export class Eslestirme {
  constructor(state) {
    this.state = state;
    this.rooms = null; // kod -> { n, started, ts }
  }

  async load() {
    if (!this.rooms) this.rooms = (await this.state.storage.get("odalar")) || {};
    // 3 dakikadır haber gelmeyen ya da başlamış odaları unut
    const now = Date.now();
    for (const [k, r] of Object.entries(this.rooms)) if (r.started || now - r.ts > 180000) delete this.rooms[k];
  }

  async save() {
    await this.state.storage.put("odalar", this.rooms);
  }

  async fetch(req) {
    const url = new URL(req.url);
    await this.load();
    if (url.pathname === "/hizli") {
      // en kalabalık (ama dolmamış) açık oda: oyun daha çabuk başlasın
      let best = "";
      for (const [k, r] of Object.entries(this.rooms)) {
        if (r.n < PUBLIC_MAX && (!best || r.n > this.rooms[best].n)) best = k;
      }
      if (!best) {
        do {
          best = "";
          for (let i = 0; i < 4; i++) best += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
        } while (this.rooms[best]);
        this.rooms[best] = { n: 0, started: false, ts: Date.now() };
      }
      this.rooms[best].n += 1; // yer ayır (oda gerçek sayıyı birazdan bildirir)
      this.rooms[best].ts = Date.now();
      await this.save();
      return Response.json({ kod: best });
    }
    if (url.pathname === "/durum" && req.method === "POST") {
      const d = await req.json();
      const k = String(d.kod || "");
      if (d.started || d.n <= 0) delete this.rooms[k];
      else this.rooms[k] = { n: Number(d.n) || 0, started: false, ts: Date.now() };
      await this.save();
      return new Response("ok");
    }
    return new Response("?", { status: 404 });
  }
}
