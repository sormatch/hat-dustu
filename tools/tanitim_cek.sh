#!/bin/bash
# Tanıtım videosu çekimi (sinema modu: geniş kadraj, Forward+, SSAO, hacimsel sis, alan derinliği).
# kullanım: tools/tanitim_cek.sh <ad> <sure_sn> sahne=<ad> [genis=1.35] [bulanik=7] [diğer sahne argümanları]
# Çıktı: build/tanitim/cek/<ad>.avi (+ .png son kare, .log). 1080x1920, 30 fps.
cd /d/HatDustu
ad=$1; sure=$2; shift 2
mkdir -p build/tanitim/cek
kare=$(awk "BEGIN{print int($sure*30)}")
printf '[display]\n\nwindow/size/window_width_override=1080\nwindow/size/window_height_override=1920\n\n[editor]\n\nmovie_writer/mjpeg_quality=0.97\n' > override.cfg
TMP=D:/tmp_gh TEMP=D:/tmp_gh timeout 900 /d/Godot/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method forward_plus --resolution 1080x1920 --write-movie build/tanitim/cek/$ad.avi --fixed-fps 30 --quit-after $kare -- shot=build/tanitim/cek/$ad.png pose=fragman wait=100 profil=tanitim yon=dikey sinema=1 "$@" > build/tanitim/cek/$ad.log 2>&1
rm -f override.cfg
grep -E "SCRIPT ERROR|Parse Error|frames at" build/tanitim/cek/$ad.log | head -5
