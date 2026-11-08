#!/bin/bash
# Tanıtım videoları için bütün sahneler, sinema modunda (tools/tanitim_cek.sh). Sırayla çekilir.
cd /d/HatDustu
cek() { echo "== $1"; bash tools/tanitim_cek.sh "$@"; }
cek koridor 8.7 sahne=koridor
cek hucre 6.7 sahne=hucre
cek telefon 6.2 sahne=telefon
cek ahize 6.6 sahne=ahize
cek c4 5.2 sahne=c4
cek patlama 5.0 sahne=patlama
cek silah 5.2 sahne=silah
cek karakter 7.2 sahne=karakter
cek tahta 6.2 sahne=tahta kelime=TÜNEL
cek kadro 7.0 sahne=kadro
cek f2_c4ver 11.8 sahne=f2_c4ver
cek f2_vida 6.8 sahne=f2_vida
cek f2_klozet 6.0 sahne=f2_klozet
cek f2_kazi 6.4 sahne=f2_kazi
cek f2_kukla 7.8 sahne=f2_kukla
cek f2_cikis 10.0 sahne=f2_cikis
cek f2_tunel 7.2 sahne=f2_tunel
cek c4kovala 13.0 sahne=c4kovala
cek rulet_masa 9.3 sahne=rulet_masa
cek rulet_don 19.9 sahne=rulet_don
for k in 1 2 3 4; do cek supheli_$k 6.5 sahne=supheli kim=$k; done
cek dolap_ponpon 5.6 sahne=dolap2 esya=ponpon
cek dolap_bandana 5.6 sahne=dolap2 esya=bandana
echo HEPSI_BITTI
