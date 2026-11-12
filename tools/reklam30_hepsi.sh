#!/bin/bash
# 30 sn yatay reklam (16:9) için bütün sahneler, sinema modunda (tools/reklam30_cek.sh). Sırayla çekilir.
cd /d/HatDustu
cek() { echo "== $1"; bash tools/reklam30_cek.sh "$@"; }
for k in 1 2 3 4; do cek kam_$k 8.3 sahne=r_kam kim=$k; done
cek c4kos 9.5 sahne=r_c4kos sis=0.45 bulanik=14
cek gardiyan 10.8 sahne=r_gardiyan bulanik=12
cek koridor 8.7 sahne=koridor
cek telefon 6.2 sahne=telefon
cek c4kovala 13.0 sahne=c4kovala
cek patlama 5.0 sahne=patlama
cek rulet_masa 9.3 sahne=rulet_masa
cek rulet_don 19.9 sahne=rulet_don
cek f2_vida 6.8 sahne=f2_vida
cek f2_kazi 6.4 sahne=f2_kazi
cek f2_kukla 7.8 sahne=f2_kukla
cek f2_cikis 10.0 sahne=f2_cikis
cek f2_tunel 7.2 sahne=f2_tunel
cek kadro 7.0 sahne=kadro
echo HEPSI_BITTI
