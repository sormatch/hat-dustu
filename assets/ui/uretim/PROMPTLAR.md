# Hat Düştü — üretilen görseller ve promptları

Üretici betik: `tools/gorsel_uret.mjs` (liste betiğin içindeki `GORSELLER` dizisi; var olan dosyayı atlar, `--force` ile yeniden üretir).
Ayrıntılı kayıt (model, kalite, token kullanımı, tarih): `_kayit.json`.

## Modeller
- **gpt-image-2** (high): saydam OLMAYANLAR — `uygulama_ikonu.png`, `acilis.png`. (Bu model `background: "transparent"` desteklemiyor.)
- **gpt-image-1.5** (high): saydam olanların hepsi. (`gpt-image-1` bu hesapta yok; betik saydamlık reddedilirse 2 → 1.5 → 1 sırasıyla düşer.)

## Sonradan yapılan işlemler (ffmpeg)
- `logo.png`: içerik kutusuna göre kırpıldı (+40 px saydam pay) → 1236x362.
- Rozetler (`oyun_*`), `kasa_*`, `tac`: nesne kırpılıp 900x900 içine sığdırıldı, 1024x1024 saydam tuvalde ortalandı (hepsi aynı görünür boyutta).
- Kartlar (`kart_*`): 990x1480 içine sığdırılıp 1024x1536 tuvalde ortalandı.

## Notlar
- `oyun_c4`: ilk prompt (askeri C4) güvenlik filtresine takıldı (violence); "parti oyunu sahne eşyası" diliyle yeniden yazıldı.
- `oyun_rulet`: ilk sürümde lamba kablosu üst kenardan kesiliyordu; lambasız yeniden üretildi.
- `logo`: 1. deneme "DÜŞÜ" yazdı (T eksik); 2. denemede harf harf tarif edilerek "HAT DÜŞTÜ" doğru çıktı (Ü noktaları ve Ş çengeli doğru).

## Açılış amblemi
- `kaynak/amblem_taban.png` (gpt-image-1.5, saydam, 1024): yazısız yuvarlak amblem (paslı perçinli halka, neon, ortada kırmızı ahize + spiral kablo). Yazılar modelden DEĞİL: `tools/amblem_uret.gd` logo.png deki "HAT" ve "DÜŞTÜ" yü üst/alt yay boyunca büker (Ü noktaları, Ş çengeli logodakiyle aynı). Prompt: gorsel_uret.mjs `amblem_taban`.

## Promptlar

### uygulama_ikonu.png
- Boyut: 1024x1024 · opak · Model: gpt-image-2 (high)

```
Mobile app icon, full-bleed square artwork filling every corner (no rounded corners, no border). A glossy red rotary prison wall payphone handset falling and snapping off its coiled cord, frozen mid-air, small sparks where the cord broke, behind it dark rusty iron prison bars against green-painted concrete, one warm yellow lamp light from above, strong bold silhouette, high contrast, readable at very small size, simple composition. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### acilis.png
- Boyut: 1536x1024 · opak · Model: gpt-image-2 (high)

```
Wide horizontal loading screen / splash art for a mobile game. Long dark prison cell block corridor in one-point perspective, rows of rusty steel cell doors with small barred windows on both sides, green-painted concrete walls with peeling paint, a red rotary payphone mounted on the wall, warm yellow caged ceiling lamps creating pools of light, light haze and dust in the air, cinematic moody lighting. The central upper area is calm, darker and empty (negative space reserved for a game logo). Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo. No people.
```

### logo.png
- Boyut: 1536x1024 · saydam · Model: gpt-image-1.5 (high)

```
Video game title logo, horizontal, two words on one line: "HAT DÜŞTÜ". Spelling, letter by letter: first word H, A, T (3 letters); second word D, Ü, Ş, T, Ü (5 letters: D, then U-umlaut, then S-cedilla, then the letter T, then U-umlaut). The second word must contain the letter T between Ş and the final Ü. All capitals, large and highly legible. Heavy bold blocky letters made of scratched rusty riveted steel plates with glowing red neon tube outlines, subtle warm yellow rim light, a few small sparks. Nothing else written. Logo only, centered, generous margin, transparent background, no backdrop, nothing cropped.
```

### oyun_tahta.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
Game mode badge icon: a small green school chalkboard in a worn wooden frame, with abstract chalk scribbles and a chalk-drawn question mark shape, a piece of white chalk on the ledge, chalk dust. Bold silhouette, cinematic warm rim light. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### oyun_devre.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
Game mode badge icon: an open rusty metal electrical fuse box with old ceramic fuses and tangled colorful wires (red, blue, yellow, green), bright electric sparks and a short-circuit flash bursting out. Bold silhouette, cinematic lighting. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### oyun_kimkim.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
Game mode badge icon: a red rotary telephone handset with a glowing anonymous hooded silhouette mask / question shape made of sound waves coming out of the earpiece, robotic voice wave lines, mysterious. Bold silhouette, cinematic lighting. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### oyun_yalanci.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
Game mode badge icon: a dented grey-green metal prison locker with its door half open, a warm light glowing from inside revealing a hidden object, suspicious mood. Bold silhouette, cinematic lighting. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### oyun_rulet.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
Game mode badge icon for a tabletop luck game: an old worn six-shot revolver lying on its side, its cylinder swung open showing six empty chambers, one single brass cartridge standing upright next to it, dramatic warm overhead spotlight (no lamp visible in frame), tense mood. Bold silhouette. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### oyun_c4.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
Stylized game prop icon for a party mini-game called "hot potato bomb": a harmless prop, three beige putty bricks bundled together with grey duct tape, a few red, blue and yellow wires, and a small digital countdown clock strapped on top with a glowing red LED display (only abstract glowing red bars, no readable digits). Video game collectible, cartoon-realistic, non-violent. Bold silhouette, cinematic lighting. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### oyun_ortalama.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
Game mode badge icon: a balance scale made of rusty metal with chalk-dusted weights on both sides and a small piece of chalk, symbolizing averaging numbers, chalk dust in the air. Bold silhouette, cinematic lighting. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### kart_siradan.png
- Boyut: 1024x1536 · saydam · Model: gpt-image-1.5 (high)

```
Vertical collectible loot card frame for a mobile game case-opening screen, front view, perfectly flat and symmetric, filling most of the canvas. Ornate riveted industrial metal border in cool grey / gunmetal silver with subtle grey glowing edges and a soft outer glow, small corner rivets and prison-bar motifs. The inner panel is a plain very dark charcoal empty area with a faint cool grey / gunmetal silver vignette, completely empty (an item picture will be placed on top later). Outside the card: fully transparent background. Absolutely no text, no letters, no numbers, no watermark, no logo. No item, no character inside.
```

### kart_nadir.png
- Boyut: 1024x1536 · saydam · Model: gpt-image-1.5 (high)

```
Vertical collectible loot card frame for a mobile game case-opening screen, front view, perfectly flat and symmetric, filling most of the canvas. Ornate riveted industrial metal border in electric blue with bright blue glowing edges and a soft outer glow, small corner rivets and prison-bar motifs. The inner panel is a plain very dark charcoal empty area with a faint electric blue vignette, completely empty (an item picture will be placed on top later). Outside the card: fully transparent background. Absolutely no text, no letters, no numbers, no watermark, no logo. No item, no character inside.
```

### kart_epik.png
- Boyut: 1024x1536 · saydam · Model: gpt-image-1.5 (high)

```
Vertical collectible loot card frame for a mobile game case-opening screen, front view, perfectly flat and symmetric, filling most of the canvas. Ornate riveted industrial metal border in royal purple / violet with intense purple glowing edges and a soft outer glow, small corner rivets and prison-bar motifs. The inner panel is a plain very dark charcoal empty area with a faint royal purple / violet vignette, completely empty (an item picture will be placed on top later). Outside the card: fully transparent background. Absolutely no text, no letters, no numbers, no watermark, no logo. No item, no character inside.
```

### kart_efsane.png
- Boyut: 1024x1536 · saydam · Model: gpt-image-1.5 (high)

```
Vertical collectible loot card frame for a mobile game case-opening screen, front view, perfectly flat and symmetric, filling most of the canvas. Ornate riveted industrial metal border in rich gold with radiant golden glowing edges and a soft outer glow, small corner rivets and prison-bar motifs. The inner panel is a plain very dark charcoal empty area with a faint rich gold vignette, completely empty (an item picture will be placed on top later). Outside the card: fully transparent background. Absolutely no text, no letters, no numbers, no watermark, no logo. No item, no character inside.
```

### kasa_kapali.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
Game loot crate: a heavy closed prison-themed steel strongbox chest, olive-green painted riveted metal with rust and scratches, yellow-black hazard stripes, a big padlock and chains locking it shut, three-quarter view. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### kasa_acik.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
Game loot crate opened: the same heavy prison-themed steel strongbox chest, olive-green painted riveted metal with rust and yellow-black hazard stripes, lid flung open, broken padlock and loose chains, bright warm golden light rays and sparkles bursting out of the inside, three-quarter view. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Dark cinematic prison atmosphere, realistic-stylized 3D game art, rusty metal, green-painted concrete, warm yellow tungsten lamp light, deep shadows, high detail, crisp edges, mobile game asset quality. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### tac.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high)

```
A shiny golden king's crown with red and purple gemstones, slightly worn, polished metal with warm highlights, front three-quarter view, victory trophy icon for match results screen. Single object centered with generous empty margin on all sides, nothing cropped, fully transparent background, no floor, no backdrop, no shadow plate. Realistic-stylized 3D game art, high detail, crisp edges. Absolutely no text, no letters, no numbers, no watermark, no logo.
```

### kasa_altin_kapali.png / kasa_altin_acik.png
- Boyut: 1024x1024 · saydam · Model: gpt-image-1.5 (high) — prompt: tools/gorsel_uret.mjs (GORSELLER), kayıt: _kayit.json
- İlk denemede model arka plana duvar/zemin çizdi (saydam değildi); "Isolated game asset render ... 100% transparent alpha" eklenip STIL cümlesi çıkarılarak yeniden üretildi.
- Mağazanın Kasa sekmesinde ve altın kasa açılış gösterisinde kullanılır (tahta kasa: kasa_kapali / kasa_acik).
