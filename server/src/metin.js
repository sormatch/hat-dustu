// Kullanıcıya giden metinler. Sunucu metni Türkçe yazar; telefon kendi diline çevirir (msgid = Türkçe,
// istemcide translations/en.po). Sabit metinler olduğu gibi gider. Değişkenli metinlerde ayrıca
// "<alan>_k" gönderilir: [[şablon, [değerler]], ...] — istemci şablonu çevirir, {0} {1}... yerine değerleri koyar,
// parçaları boşlukla birleştirir. Türkçe dolu metin (<alan>) eski istemciler için yine gider.

export function fmt(k, a = []) {
  return String(k).replace(/\{(\d+)\}/g, (_, i) => String(a[Number(i)] ?? ""));
}

// metin("msg", "Sabit cümle.", ["{0} kişi bildi.", [3]]) -> { msg: "Sabit cümle. 3 kişi bildi.", msg_k: [...] }
export function metin(alan, ...parts) {
  const p = parts.filter(Boolean).map((x) => (typeof x === "string" ? [x, []] : [x[0], x[1] || []]));
  return { [alan]: p.map(([k, a]) => fmt(k, a)).join(" "), [alan + "_k"]: p };
}

// En sık kullanım: bilgi/hata mesajının "m" alanı. tx("{0} geri döndü.", ad)
export function tx(k, ...a) {
  return metin("m", [k, a]);
}

// Odanın dili (kurucunun dili): oyun içi kelime havuzları ve büyük harf kuralı için.
export function odaDili(d) {
  return d === "en" ? "en" : "tr";
}

export function buyuk(s, dil) {
  const t = String(s || "");
  return dil === "en" ? t.toUpperCase() : t.replace(/i/g, "İ").replace(/ı/g, "I").toLocaleUpperCase("tr-TR");
}
