#!/bin/bash
# Ses dosyalarının seviyesini ölçer: süre, bütünleşik ses yüksekliği (LUFS), gerçek tepe (dBTP), kırpılmış örnek.
# Kullanım: bash tools/ses_olc.sh dosya1.ogg dosya2.ogg ...
for f in "$@"; do
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  o=$(ffmpeg -hide_banner -nostats -i "$f" -af "apad=pad_dur=0.5,ebur128=peak=true" -f null - 2>&1)
  i=$(echo "$o" | grep -A1 "Integrated loudness" | grep " I:" | awk '{print $2}')
  p=$(echo "$o" | grep -A1 "True peak" | grep "Peak:" | awk '{print $2}')
  printf "%-40s %6.2fs  I=%6s LUFS  TP=%6s dBTP\n" "$(basename "$f")" "$d" "$i" "$p"
done
