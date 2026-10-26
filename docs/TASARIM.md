# Hat Düştü — Tasarım Rehberi (arayüz takımı)

Tek kaynak: `scripts/ui.gd` (belirteçler dosyanın başında). Görseller: `assets/ui/kit/`.
Takımın hepsini tek ekranda görmek için:

```
cd /d/HatDustu && /d/Godot/Godot_v4.7.2-stable_win64_console.exe --path . -- shot=pano.png pose=kit wait=1.5
```

## Sanat yönü
Paslı / yıpranmış **zeytin yeşili çelik**, perçinler, **sarı-siyah tehlike şeridi**, sıcak **amber lamba ışığı**, koyu sinematik zemin.
Arayüz parçaları bu dünyadan gelir ama **sade, düz önden, okunaklıdır**: süs kenarlarda, ortası düz. Yazılar görselin içinde değil, kodda.

## Renkler (`UI.<AD>`)
| Belirteç | Renk | Ne için |
|---|---|---|
| `ZEMIN` | `#0b0e0f` | ekran zemini |
| `YUZEY` / `YUZEY_2` | `#161b19` / `#212826` | panel içi / panel içindeki satır, kart |
| `CIZGI` | `#3a4240` | ayraç, pasif kenar |
| `ZEYTIN` | `#4b5a3c` | marka metal rengi |
| `AMBER` | `#ffb020` | **tek ana vurgu**: birincil düğme, seçili sekme, ilerleme, odak |
| `TEHLIKE_SARI` | `#f5c518` | şerit sarısı (az kullan) |
| `KIRMIZI` | `#e0322a` | tehlike, sil, çık, rozet |
| `YESIL` | `#4cc23a` | onay, satın al, hazır |
| `MAVI` | `#3fa8ff` | bilgi |
| `ELMAS` | `#5ff0ff` | elmas para birimi sayısı |
| `METIN` / `METIN_SOLUK` | `#f3ead8` / gri | ana yazı / ikincil yazı |
| `PERDE` | siyah %72 | modal arkası |
| `NADIRLIK` | sıradan `#9aa3ab`, nadir `#3fa8ff`, epik `#b05cff`, efsane `#ffc23a` | kart, eşya adı |

Kural: bir ekranda **tek bir amber birincil eylem** olur. Her şey amber olursa hiçbir şey öne çıkmaz.

## Yazı tipleri
- **Başlık / düğme / sayı:** RussoOne (`UI.title`, `UI.TITLE_FONT`) — koyu dış çizgi + alta gölge otomatik.
- **Metin:** Rubik 500 (`UI.label`, proje teması varsayılanı). İkisi de Türkçe karakterleri (ç ğ ı İ ö ş ü) destekler.

## Ölçekler
- **Yazı boyutu:** `FS_KUCUK 16` (dipnot) · `FS_METIN 20` (gövde) · `FS_ORTA 24` (alt başlık, küçük düğme) · `FS_BUYUK 32` (panel başlığı, ana düğme) · `FS_DEV 44` (ekran başlığı, sonuç).
- **Boşluk:** `B_XS 8` · `B_S 12` · `B_M 16` · `B_L 24` · `B_XL 32`. Öğe arası 12–16, bölüm arası 24–32, panel iç payı 24–32.
- **Köşe (kodla çizilen kutular):** `R_KUCUK 8` · `R_ORTA 14` · `R_BUYUK 22`.
- **Dokunma alanı:** en az **64 px** (`DOKUNMA`). Düğme yükseklikleri: `BTN_H_KUCUK 64` · `BTN_H 76` · `BTN_H_BUYUK 92`.
- **İkon:** `IKON_KUCUK 24` (yazı içi) · `IKON_ORTA 40` (düğme/sekme) · `IKON_BUYUK 64` (menü kutucuğu) · `IKON_DEV 120` (boş durum, ödül). Düğme içindeki ikon otomatik `h*0.58`.
- Taban çözünürlük 1280x720 (`canvas_items`, `expand`); ölçüler bu tabana göredir.

## Düğme türleri — ne zaman hangisi
| Tür | Görünüm | Kullanım | Eski ad |
|---|---|---|---|
| `"ana"` | amber | ekrandaki **tek** ana eylem: OYNA, DEVAM, seçili seçenek | `primary`, `orange` |
| `"ikincil"` | koyu çelik | geri, vazgeç, seçili olmayan seçenek, diğer eylemler | `normal` |
| `"tehlike"` | kırmızı | geri alınamayan: çık, sil, odadan at | `red` |
| `"yesil"` | yeşil | onay / satın al / hazırım | `green` |

Her düğmede hazır: basınca küçülme (0.94) + içe göçen basılı doku + içerik 2–3 px aşağı kayar + `tik_ui.ogg` sesi; `disabled = true` olunca gri doku ve soluk yazı. Sesi kapatmak: `b.set_meta("sessiz", true)`; tümü: `UI.ses_acik = false`. Seçim değişince türü değiştirmek: `UI.set_button_kind(b, "ana")`.

## API özeti (`const UI := preload("res://scripts/ui.gd")`)
```gdscript
UI.button(text, kind, h, font, icon_name, w)   # Button — imza değişmedi
UI.icon_button("kapat", "ikincil", 64)          # kare ikon düğmesi
UI.set_button_text(b, "YENİ") ; UI.set_button_kind(b, "yesil")
UI.panel(min_size, pad)                          # çelik panel (9 parçalı)
UI.header("BAŞLIK", 30)                          # tehlike şeritli başlık plakası
UI.tab("SAÇ", secili, "envanter")                # sekme
UI.top_bar()                                     # üst şerit; içine: .get_meta("row")
UI.counter("elmas", "10.025")                    # ikon + sayı hapı
UI.card_frame("efsane", Vector2(150, 206))       # nadirlik çerçeveli kart ("" = nötr kart)
UI.progress(0.35, 320, 34, "35/100")             # .value = 0.5 / .animate_to(0.8) / .text
UI.badge(3) ; UI.set_badge(r, n) ; UI.badge_on(hedef, n)   # kırmızı sayı rozeti
var m := UI.modal("SATIN AL", 640)               # perde + panel + başlık + kapat; m.body.add_child(...)
ekran.add_child(m) ; m.closed.connect(...) ; m.close()
UI.toast("Kaydedildi", null, 2.2, "basari")      # bilgi / basari / hata
UI.icon("oyna", 40)                              # Türkçe ya da eski İngilizce ad (play, store...)
UI.title / UI.label / UI.flat / UI.sbox / UI.kit_sbox / UI.background / UI.style_edit
UI.sigdir(label, max_w)                          # yazı sığmazsa küçülür (İngilizce uzun metinler); sabit genişlikli UI.button kendisi yapar
UI.rarity_key("NADİR") -> "nadir" ; UI.rarity_color("epik")
```

## İkonlar (`assets/ui/kit/ikon_*.png`, 512x512, saydam)
oyna · magaza · envanter · arkadas · ayarlar · gorev · liderlik · basarim · elmas · xp · kilit · telefon · kapat · geri · tac · davet · ses · mikrofon · kasa.
Ek (oyun içi / telefon / şikayet): sikayet · engelle · kopyala · bot · onay · ahize (çevirmeli telefon) · el · kapi · sandalye · bilgisayar · tahta · sigorta · egil. Ortak oyuncu parçaları (avatar, kart menüsü, ŞİKAYET ET / ENGELLE pencereleri): `scripts/oyuncu_ui.gd`.
Eski adlar otomatik eşlenir (play→oyna, store→magaza, friends→arkadas, settings→ayarlar, gem→elmas, lock→kilit, phone→telefon, crown→tac, invite→davet, sound→ses, mic→mikrofon, chest→kasa). Kit ikonu olmayan adlar eski `icon_<ad>.png`ye düşer.

## 9 parçalı parçalar
`panel`, `panel_baslik`, `ust_bar`, `btn_<tür>` (+`_basili`), `sekme`, `sekme_secili`, `cubuk_bos`, `cubuk_dolu`, `rozet`, `kart`. Kesim oranları `UI.KESIM` tablosunda. Görsel, kullanıldığı yüksekliğe ölçeklenip yalnızca ortası esner; köşe süsleri hep aynı boyutta kalır. Nadirlik çerçeveleri `assets/ui/uretim/kart_*.png`.

## Yapılmaması gerekenler
- Ekran kodunda yeni renk kodu yazma — `UI.<renk>` kullan. Yeni bir renk gerekiyorsa buraya ve `ui.gd`ye ekle.
- 64 px'ten küçük dokunma alanı yapma; yazıyı 16 px'in altına indirme.
- Görselin içine yazı koyma (çeviri, Türkçe karakter ve keskinlik sorunları).
- Bir ekranda birden fazla amber ana düğme kullanma.

## Görsel üretimi
`node tools/arayuz_uret.mjs` (eksikleri üretir, `--force ad` yeniden üretir) → ham görseller `assets/ui/kit/_ham/` (Godot görmez, `.gdignore`), promptlar ve kullanım `_ham/_kayit.json`.
`node tools/arayuz_uret.mjs --isle` → ffmpeg ile kırpar, düğme sayfasını 4 düğmeye böler, basılı halleri (ters ışık + karartma) üretir, ikonları 512x512'ye oturtur. Model: gpt-image-1.5 (saydam), kalite high.
