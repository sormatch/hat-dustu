#!/bin/bash
# Çok oyunculu eşzamanlı konuşma testi (yerel sunucu 8794 açık olmalı: cd server && npx wrangler dev --port 8794).
# 4 oyuncu aynı odada, hepsi aynı anda konuşur (erkek, kadin, ince, genc kayıtları). Her dinleyici her konuşan için
# gelen paketi, sekmeyi (hoparlör tamponu konuşurken boşaldı) ve tampon gecikmesini yazar.
# kullanım: bash tools/ses_coklu.sh [sure_sn] [oda_kodu]
cd /d/HatDustu || exit 1
G=/d/Godot/Godot_v4.7.2-stable_win64_console.exe
SURE=${1:-20}
KOD=${2:-S$((RANDOM % 900 + 100))}
mkdir -p build/ses/coklu
i=0
for k in erkek kadin ince genc; do
  i=$((i+1))
  kur=0; [ $i = 1 ] && kur=1
  timeout $((SURE + 90)) $G --headless --path . -- server=ws://127.0.0.1:8794 auto=coklu n=4 kurucu=$kur kaynak=$k sure=$SURE profil=coklu$i code=$KOD > build/ses/coklu/$k.log 2>&1 &
done
wait
grep -h '\[coklu\]\|SCRIPT ERROR' build/ses/coklu/*.log
