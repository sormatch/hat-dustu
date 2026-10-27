#!/bin/bash
# Projektör Avı efektleri: köpek, siren, copla parmaklığa vurma, düdük, kapı, jop, gece ortamı, projektör açılışı.
# Kullanım: bash tools/projektor_ses_uret.sh [kaynak=/d/ses_indir3]
# Kaynaklar hepsi Freesound CC0 (liste: $SRC/liste.txt — id, kullanıcı, ad, adres; ayrıntı assets/ses/LISANS.txt
# "Projektör Avı" bölümü) + /d/ses_indir2/fs (önceki tur CC0 kayıtları). Mono 44.1 kHz Ogg, tepe ≤ -1 dBTP.
set -e
SRC="${1:-/d/ses_indir3}"
FS="$SRC/fs"
FS2="/d/ses_indir2/fs"
KOK="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$KOK/assets/ses/projektor"
WORK="$KOK/build/ses_projektor"
mkdir -p "$OUT" "$WORK"
FF="ffmpeg -y -hide_banner -loglevel error"

lufs() { ffmpeg -hide_banner -nostats -i "$1" -af "apad=pad_dur=0.5,ebur128" -f null - 2>&1 | grep -A1 "Integrated loudness" | grep " I:" | awk '{print $2}'; }

# norm <giriş> <çıkış ad> <hedef LUFS>
norm() {
  local i g lim="aresample=176400,alimiter=limit=0.85:attack=0.5:release=50:level=0:latency=1,aresample=44100"
  i=$(lufs "$1")
  g=$(awk -v t="$3" -v i="$i" 'BEGIN{printf "%.2f", t - i}')
  $FF -i "$1" -af "aformat=channel_layouts=mono,volume=${g}dB,$lim" -c:a libvorbis -q:a 4 -ar 44100 "$OUT/$2.ogg"
  echo "$2: $(lufs "$OUT/$2.ogg") LUFS"
}

# kes <kaynak> <bas> <son> <çıkış.wav> [ek süzgeç]: kısa giriş/çıkış yumuşatması
kes() {
  local d
  d=$(awk -v a="$2" -v b="$3" 'BEGIN{print b - a}')
  $FF -ss "$2" -t "$d" -i "$1" -af "aformat=channel_layouts=mono,afade=t=in:d=0.01,afade=t=out:st=$(awk -v d="$d" 'BEGIN{print d - 0.12}'):d=0.12${5:+,$5}" -ar 44100 "$4"
}

# --- köpekler ---
kes "$FS/kopek_iki.mp3" 0.0 1.6 "$WORK/k1.wav"
norm "$WORK/k1.wav" kopek_1 -16
kes "$FS/kopek_iki.mp3" 9.75 13.0 "$WORK/k2.wav"
norm "$WORK/k2.wav" kopek_2 -16
kes "$FS/kopek_saldirgan.mp3" 6.4 8.9 "$WORK/k3.wav"
norm "$WORK/k3.wav" kopek_3 -16
$FF -i "$FS/kopek_uzak.mp3" -af "aformat=channel_layouts=mono,lowpass=f=2500,aecho=0.6:0.5:80:0.3" -ar 44100 "$WORK/ku.wav"
norm "$WORK/ku.wav" kopek_uzak -26

# --- siren: uzun hava sireni (yükselen uluma), kısa acil siren (yakalanınca) ---
kes "$FS/siren_hava.mp3" 2.0 10.0 "$WORK/s1.wav" "afade=t=in:d=0.8"
norm "$WORK/s1.wav" siren -20
kes "$FS/siren_acil.mp3" 0.0 3.2 "$WORK/s2.wav"
norm "$WORK/s2.wav" siren_kisa -19

# --- gardiyan copla parmaklıklara / kapılara vurur ---
kes "$FS/parmaklik_vur.mp3" 1.0 3.2 "$WORK/p1.wav"
norm "$WORK/p1.wav" parmaklik_1 -15
kes "$FS/parmaklik_vur.mp3" 100.3 102.2 "$WORK/p2.wav"
norm "$WORK/p2.wav" parmaklik_2 -15
kes "$FS/parmaklik_vur.mp3" 112.4 114.4 "$WORK/p3.wav"
norm "$WORK/p3.wav" parmaklik_3 -15
$FF -i "$FS/demir_vur.mp3" -af "aformat=channel_layouts=mono" -ar 44100 "$WORK/p4.wav"
norm "$WORK/p4.wav" demir_vur -16

# --- düdük, jop, fener, telsiz ---
kes "$FS/duduk.mp3" 0.0 1.7 "$WORK/d1.wav"
norm "$WORK/d1.wav" duduk -17
$FF -i "$FS/jop_2.mp3" -af "aformat=channel_layouts=mono" -ar 44100 "$WORK/j1.wav"
norm "$WORK/j1.wav" jop -14
$FF -i "$FS/fener.mp3" -af "aformat=channel_layouts=mono" -ar 44100 "$WORK/f1.wav"
norm "$WORK/f1.wav" fener -20
$FF -i "$FS/telsiz_bip.mp3" -af "aformat=channel_layouts=mono" -ar 44100 "$WORK/t1.wav"
norm "$WORK/t1.wav" telsiz -22

# --- kapılar: avlunun paslı demir kapısı ---
kes "$FS/kapi_pas.mp3" 0.3 4.6 "$WORK/g1.wav"
norm "$WORK/g1.wav" avlu_kapi -16

# --- projektör açılır: büyük şalter + soğuk ark vızıltısı ---
$FF -i "$FS2/big_breaker.mp3" -i "$FS2/switch_fuse_hum.mp3" -filter_complex "[0]aformat=channel_layouts=mono,atrim=0:1.6[a];[1]aformat=channel_layouts=mono,atrim=0:1.6,volume=0.35,afade=t=in:d=0.15,afade=t=out:st=1.2:d=0.4[b];[a][b]amix=inputs=2:normalize=0" -ar 44100 "$WORK/pr.wav"
norm "$WORK/pr.wav" projektor_ac -15

# --- gece ortamı (döngü): cırcır böcekleri + uzak köpekler, 30 sn, uçları birbirine yumuşak geçer ---
$FF -ss 5 -t 31 -i "$FS/gece_circir.mp3" -ss 10 -t 31 -i "$FS/gece_kopek.mp3" -filter_complex "[0]aformat=channel_layouts=mono[a];[1]aformat=channel_layouts=mono,lowpass=f=3000,volume=0.5[b];[a][b]amix=inputs=2:normalize=0" -ar 44100 "$WORK/go.wav"
$FF -i "$WORK/go.wav" -filter_complex "[0]atrim=0:30,asetpts=N/SR/TB[a];[0]atrim=30:31,asetpts=N/SR/TB[b];[a][b]acrossfade=d=1:c1=tri:c2=tri" "$WORK/go_dongu.wav" 2>/dev/null || cp "$WORK/go.wav" "$WORK/go_dongu.wav"
norm "$WORK/go_dongu.wav" gece_ortam -30

# --- gardiyanın kahkahası: gerçek insan kaydı (yapay ses kahkahası doğal değildi). koridor: hafif yankı; kuleden: hoparlör ---
kes "$FS/gulus_a.mp3" 0.25 5.85 "$WORK/gl1.wav" "highpass=f=90,aecho=0.85:0.5:55|110:0.2|0.1"
norm "$WORK/gl1.wav" gulus -14
kes "$FS/gulus_d.mp3" 1.0 5.2 "$WORK/gl2.wav" "highpass=f=280,lowpass=f=3600,acompressor=threshold=0.2:ratio=4:attack=5:release=120,aecho=0.8:0.55:70|140:0.28|0.14"
norm "$WORK/gl2.wav" gulus_megafon -15

# --- ışık yaklaşıyor: yükselen kısa uyarı (sentez, bu projeye ait) ---
$FF -f lavfi -i "sine=f=880:d=0.09,afade=t=out:st=0.06:d=0.03" -f lavfi -i "anullsrc=r=44100:cl=mono:d=0.07" -f lavfi -i "sine=f=1175:d=0.12,afade=t=out:st=0.08:d=0.04" -filter_complex "[0][1][2]concat=n=3:v=0:a=1,aformat=channel_layouts=mono" -ar 44100 "$WORK/yk.wav"
norm "$WORK/yk.wav" isik_yaklasiyor -20

echo "tamam: $OUT"
