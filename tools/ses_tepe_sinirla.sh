#!/bin/bash
# Gerçek tepesi 0 dBTP'yi aşan (kırpılma riski olan) ses dosyalarının yalnızca tepelerini -1 dBFS'e sınırlar;
# ses yüksekliğine dokunmaz. Kullanım: bash tools/ses_tepe_sinirla.sh dosya.ogg ...
for f in "$@"; do
  t="${f%.ogg}.tmp.ogg"
  ch=$(ffprobe -v error -show_entries stream=channels -of csv=p=0 "$f")
  sr=$(ffprobe -v error -show_entries stream=sample_rate -of csv=p=0 "$f")
  ffmpeg -y -hide_banner -loglevel error -i "$f" -af "aresample=176400,alimiter=limit=0.84:attack=0.5:release=40:level=0:latency=1,aresample=$sr" -ac "$ch" -c:a libvorbis -q:a 6 "$t" && mv "$t" "$f"
done
