#!/bin/bash
# Godot Movie Maker ile tek çekim (TikTok reklamları).
# kullanım: tools/fragman2.sh <yatay|dikey> <ad> <sure_sn> sahne=<ad> [kalite=2]  -> build/fragman2/cek/<yon>/<ad>.avi
# Çıktı: build/fragman2/cek/$yon/<ad>.avi (+ .png son kare, .log). Başka Godot açıksa bitmesini bekler.
cd /d/HatDustu
yon=$1; ad=$2; sure=$3; shift 3
if [ "$yon" = "dikey" ]; then W=1080; H=1920; else W=1920; H=1080; fi
mkdir -p build/fragman2/cek/$yon
while tasklist | grep -qi godot; do echo "baska godot acik, bekleniyor"; sleep 15; done
kare=$(awk "BEGIN{print int($sure*30)}")
printf '[display]\n\nwindow/size/window_width_override=%d\nwindow/size/window_height_override=%d\n\n[editor]\n\nmovie_writer/mjpeg_quality=0.95\n' $W $H > override.cfg
TMP=D:/tmp_gh TEMP=D:/tmp_gh timeout 900 /d/Godot/Godot_v4.7.2-stable_win64_console.exe --path . --resolution ${W}x${H} --write-movie build/fragman2/cek/$yon/$ad.avi --fixed-fps 30 --quit-after $kare -- shot=build/fragman2/cek/$yon/$ad.png pose=fragman wait=100 profil=fragman2 yon=$yon "$@" > build/fragman2/cek/$yon/$ad.log 2>&1
rm -f override.cfg
grep -E "SCRIPT ERROR|Parse Error|ERROR|frames at" build/fragman2/cek/$yon/$ad.log | head -8
ls -la build/fragman2/cek/$yon/$ad.avi 2>/dev/null | awk '{print $5, $9}'
