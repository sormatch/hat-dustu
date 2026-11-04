// hatdustu.app: www adresi tek adrese (hatdustu.app) kalıcı yönlenir (Google aynı sayfayı iki kez görmesin);
// geri kalan her istek ../site klasöründeki durağan dosyalardan sunulur.
// Videolarda "Range" isteği (iPhone Safari oynatmak için ister) 206 kısmi yanıtla karşılanır; durağan dosya
// sunucusu bunu kendisi yapmıyordu (hep dosyanın tamamı 200 ile gidiyordu).
const YASAL = new Set(["/gizlilik", "/privacy", "/kosullar", "/terms", "/hesap-sil", "/delete-account"]);

// İndirilen dosyalar (R2 hatdustu-indir): adres -> [R2 anahtarı, tür]. Yarıda kalan indirme Range ile sürer.
const INDIRMELER = {
  "/indir/hatdustu.apk": ["HatDustu.apk", "application/vnd.android.package-archive"], // Android
  "/indir/hatdustu-pc.zip": ["HatDustu_PC.zip", "application/zip"], // Windows (HatDustu.exe + HatDustu.pck)
};

async function dosyaIndir(req, env, [ad, tur]) {
  if (req.method !== "GET" && req.method !== "HEAD") return new Response(null, { status: 405 });
  const nesne = await env.INDIR.head(ad);
  if (!nesne) return new Response("Dosya bulunamadı", { status: 404 });
  const h = new Headers({
    "Content-Type": tur,
    "Content-Disposition": `attachment; filename="${ad}"`,
    "Accept-Ranges": "bytes",
    "Cache-Control": "public, max-age=300",
    ETag: nesne.httpEtag,
    "X-Content-Type-Options": "nosniff",
  });
  const boy = nesne.size;
  const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.get("Range") || "");
  if (!m || (m[1] === "" && m[2] === "")) {
    h.set("Content-Length", String(boy));
    if (req.method === "HEAD") return new Response(null, { headers: h });
    return new Response((await env.INDIR.get(ad)).body, { headers: h });
  }
  let bas = m[1] === "" ? Math.max(0, boy - Number(m[2])) : Number(m[1]);
  let son = m[1] === "" || m[2] === "" ? boy - 1 : Math.min(Number(m[2]), boy - 1);
  if (bas >= boy || bas > son) return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${boy}` } });
  h.set("Content-Range", `bytes ${bas}-${son}/${boy}`);
  h.set("Content-Length", String(son - bas + 1));
  if (req.method === "HEAD") return new Response(null, { status: 206, headers: h });
  const parca = await env.INDIR.get(ad, { range: { offset: bas, length: son - bas + 1 } });
  return new Response(parca.body, { status: 206, headers: h });
}

export default {
  async fetch(req, env) {
    const u = new URL(req.url);
    if (u.hostname === "www.hatdustu.app") {
      u.hostname = "hatdustu.app";
      return Response.redirect(u.toString(), 301);
    }
    // Google Search Console sahiplik dosyası: tam bu adreste 200 dönmeli (durağan sunucu .html'i uzantısız adrese yönlendiriyor)
    if (u.pathname === "/google903b9d2bc7bf56e5.html") {
      return new Response("google-site-verification: google903b9d2bc7bf56e5.html", { headers: { "Content-Type": "text/html; charset=utf-8" } });
    }
    // Yasal sayfalar ve hesap silme oyun sunucusunda üretilir; adres çubuğunda hatdustu.app kalsın diye içeriden istenir
    if (YASAL.has(u.pathname)) return env.OYUN.fetch(req);
    if (INDIRMELER[u.pathname]) return dosyaIndir(req, env, INDIRMELER[u.pathname]);
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
