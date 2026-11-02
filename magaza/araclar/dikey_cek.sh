#!/bin/bash
# Dikey mağaza görseli plakası (yazısız 3D çekim).
# Kullanım (Git Bash): bash magaza/araclar/dikey_cek.sh <iphone|ipad|play> <d_sahne> [ek=parametre ...]
# Çıktı: build/dikey/plaka/<oran>/<sahne>[_<EK>].png
# Ortam: EK=deneme adı, BOL=2 (yarı çözünürlük deneme), SS=1.5 (aşırı örnekleme), YONTEM=--rendering-method mobile
cd /d/HatDustu || exit 1
oran=$1; sahne=$2; shift 2
case "$oran" in
  iphone) W=1290; H=2796 ;;
  ipad)   W=2048; H=2732 ;;
  play)   W=1080; H=1920 ;;
  *) echo "oran?"; exit 1 ;;
esac
KLAS=D:/HatDustu/build/dikey/plaka/$oran
mkdir -p "$KLAS"
while tasklist | grep -qi godot; do echo "baska godot acik, bekleniyor"; sleep 10; done
AD=$sahne${EK:+_$EK}
TMP=D:/tmp_gh TEMP=D:/tmp_gh timeout 150 /d/Godot/Godot_v4.7.2-stable_win64_console.exe --path . ${YONTEM:---rendering-method forward_plus} --resolution 270x480 -- \
  server=ws://127.0.0.1:8794 shot="$KLAS/$AD.png" pose=fragman wait=100 profil=dikey isi=0 yon=dikey sahne="$sahne" oran="$oran" gen=$((W/${BOL:-1})) yuk=$((H/${BOL:-1})) ss=${SS:-1.5} "$@" > "$KLAS/$AD.log" 2>&1
grep -E "SCRIPT ERROR|Parse Error|^ERROR|^yazildi|^bilgi" "$KLAS/$AD.log" | grep -vE "Unreferenced|PagedAllocator|leaked" | head -12
ls -la "$KLAS/$AD.png" 2>/dev/null | awk '{print $5, $9}'
