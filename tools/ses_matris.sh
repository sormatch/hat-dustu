#!/bin/bash
# Ses senaryoları: eski ve yeni ses kodu aynı koşullarda. Kullanım: bash tools/ses_matris.sh [yeni|eski|ikisi]
# Çıktı: build/ses/s/<surum>_<senaryo>.wav + tablo (tools/ses_rapor.mjs)
cd /d/HatDustu || exit 1
G=/d/Godot/Godot_v4.7.2-stable_win64_console.exe
SURUMLER=${1:-ikisi}
[ "$SURUMLER" = ikisi ] && SURUMLER="eski yeni"
# ad | ses_senaryo argümanları | rapor referansları
SENARYOLAR=(
  "01_temiz|a=erkek|erkek"
  "02_kadin|a=kadin|kadin"
  "03_kisik|a=ince a_db=-16|ince"
  "04_bagiran|a=genc a_db=8|genc"
  "05_gurultulu|a=kadin gurultu_db=-32|kadin"
  "06_dalgali_ag|a=erkek ag=dalgali|erkek"
  "07_kotu_ag|a=erkek ag=kotu|erkek"
  "08_yavas_tel|a=kadin ag=dalgali kare=yavas|kadin"
  "09_iki_kisi|a=erkek b=kadin b_bas=0.9|erkek kadin --gecikme_b=0.9"
  "10_telefon|a=erkek telefon=1|erkek"
  "11_yanki|a= b=kadin yanki_db=-16|- kadin"
  "12_yanki_konusma|a=erkek b=kadin b_bas=0.9 yanki_db=-16|erkek kadin --gecikme_b=0.9"
)
for s in $SURUMLER; do
  [ -n "$SADECE" ] && true
  for sat in "${SENARYOLAR[@]}"; do
    IFS="|" read -r ad sa ra <<< "$sat"
    if [ -n "$SADECE" ] && ! echo " $SADECE " | grep -q " $ad "; then continue; fi
    out=build/ses/s/${s}_${ad}.wav
    sonuc=$(timeout 45 $G --headless --path . --script res://tools/ses_senaryo.gd -- surum=$s $sa sure=19 cikti=$out 2>&1 | grep -E "^SONUC|SCRIPT ERROR" | head -2)
    yol=$(echo "$sonuc" | grep -oE "yollanan=[0-9]+")
    rap=$(node tools/ses_rapor.mjs $out $ra 2>&1 | tail -1 | sed -E 's/^[^ ]+ +//')
    printf "%-5s %-18s %s %s\n" "$s" "$ad" "$rap" "$yol"
  done
done
