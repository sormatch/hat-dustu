#!/bin/bash
# Mağaza ekran görüntüsü adaylarını oyundan çeker (yerel sunucu 8794 açık olmalı).
# Kullanım (Git Bash):  bash magaza/araclar/cek.sh [ad ...]   (ad verilmezse hepsi)
# Çıktı: magaza/ham/<ad>.png  (1920x886 = iPhone 6,7"/6,9" en-boy oranı). iPad için: BOYUT=1400x1050 EK=_ipad bash ...
cd /d/HatDustu || exit 1
GODOT=/d/Godot/Godot_v4.7.2-stable_win64_console.exe
BOYUT=${BOYUT:-1920x886}
CIKTI=D:/HatDustu/magaza/ham

declare -A P
P[menu]="pose=menu demo=1 wait=4"
P[karakter]="pose=karakter cat=sac wait=4"
P[kasa_efsane]="pose=karakter cat=sapka ac=1 kazan=tac wait=9"
P[kasa_efsane2]="pose=karakter cat=sapka ac=1 kazan=tac wait=11"
P[kadro]="pose=kadro wait=5"
P[tahta]="pose=oyunici ekran=tahta oyun=tahta yazi=MUZ wait=4"
P[tahtapanel]="pose=tahtapanel yazi=MUZ wait=4"
P[rulet_sakak]="pose=el el=sakak wait=4"
P[rulet_hedef]="pose=el el=hedef bot=1 wait=4"
P[rulet_gerilim]="pose=oyunici ekran=rulet_gerilim oyun=rulet wait=4"
P[c4]="pose=el el=c4 wait=4"
P[c4_ekran]="pose=oyunici ekran=c4 oyun=c4 wait=4"
P[macsonu]="pose=macsonu wait=14"
P[macsonu2]="pose=macsonu wait=20"
P[elmas]="pose=elmas wait=4"
P[envanter]="pose=envanter wait=4"
P[arama]="pose=arama durum=konusma wait=4"
P[ahize]="pose=el el=ahize wait=4"
P[lobi]="pose=lobi wait=4"
P[sema]="pose=sema wait=4"
P[cell]="pose=cell wait=4"
P[corridor]="pose=corridor wait=4"
P[kart]="pose=oyunici ekran=kart oyun=rulet wait=4"
P[yalanci]="pose=oyunici ekran=yalanci_esya oyun=yalanci yalanci=1 wait=4"
P[kimkim]="pose=oyunici ekran=kimkim oyun=kimkim wait=4"
P[ortalama]="pose=oyunici ekran=ortalama_sonuc oyun=ortalama wait=4"
P[arkadas]="pose=arkadas demo=1 wait=4"
P[liderlik]="pose=liderlik demo=1 wait=4"
P[rehber]="pose=contacts wait=4"
P[ariyor]="pose=arama durum=ariyor wait=4"
P[caliyor]="pose=arama durum=caliyor wait=4"
P[altyazi]="pose=arama durum=altyazi wait=4"
P[tel1]="pose=el el=telefon wait=4"
P[tel2]="pose=el el=ahize dis=1 wait=4"
P[tel3]="pose=el el=ahize dis=1 aci=35 wait=4"
P[tel4]="pose=el el=ahize pitch=-10 wait=4"
P[karakter_kiyafet]="pose=karakter cat=kiyafet item=leopar wait=4"
P[karakter_sapka]="pose=karakter cat=sapka item=tac wait=4"

ADLAR=("$@")
[ ${#ADLAR[@]} -eq 0 ] && ADLAR=("${!P[@]}")
for ad in "${ADLAR[@]}"; do
  echo "çek $ad"
  timeout 90 "$GODOT" --path . --resolution "$BOYUT" -- server=ws://127.0.0.1:8794 shot="$CIKTI/$ad${EK:-}.png" ${P[$ad]} >/dev/null 2>&1
done
