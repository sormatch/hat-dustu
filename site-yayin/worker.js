// hatdustu.app: www adresi tek adrese (hatdustu.app) kalıcı yönlenir (Google aynı sayfayı iki kez görmesin);
// geri kalan her istek ../site klasöründeki durağan dosyalardan sunulur.
// Videolarda "Range" isteği (iPhone Safari oynatmak için ister) 206 kısmi yanıtla karşılanır; durağan dosya
// sunucusu bunu kendisi yapmıyordu (hep dosyanın tamamı 200 ile gidiyordu).
export default {
  async fetch(req, env) {
    const u = new URL(req.url);
    if (u.hostname === "www.hatdustu.app") {
      u.hostname = "hatdustu.app";
      return Response.redirect(u.toString(), 301);
    }
    const range = req.headers.get("Range");
    if (!range || !u.pathname.startsWith("/video/")) return env.ASSETS.fetch(req);
    const tam = await env.ASSETS.fetch(new Request(req.url, { method: "GET" }));
    if (tam.status !== 200) return tam;
    const govde = await tam.arrayBuffer();
    const boy = govde.byteLength;
    const m = /bytes=(\d*)-(\d*)/.exec(range);
    let bas = m && m[1] !== "" ? Number(m[1]) : NaN;
    let son = m && m[2] !== "" ? Number(m[2]) : NaN;
    if (Number.isNaN(bas)) {
      // "bytes=-500": son 500 bayt
      bas = Number.isNaN(son) ? 0 : Math.max(0, boy - son);
      son = boy - 1;
    } else if (Number.isNaN(son) || son >= boy) {
      son = boy - 1;
    }
    if (bas >= boy || bas > son) {
      return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${boy}` } });
    }
    const h = new Headers(tam.headers);
    h.set("Content-Range", `bytes ${bas}-${son}/${boy}`);
    h.set("Content-Length", String(son - bas + 1));
    h.set("Accept-Ranges", "bytes");
    return new Response(req.method === "HEAD" ? null : govde.slice(bas, son + 1), { status: 206, headers: h });
  },
};
