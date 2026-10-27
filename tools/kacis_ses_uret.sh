#!/bin/bash
# Büyük Kaçış efektleri: kürek / kaşık kazısı, toprak dökülmesi, kayaya ve tuğlaya vuruş, tornavida, klozetin
# betonda sürüklenmesi, yorgun nefes, sayım zili, yeraltı uğultusu. Kaynaklar Freesound CC0 (liste:
# tools/projektor_ses_kaynak.txt, "kacis" satırları; ayrıntı assets/ses/LISANS.txt "Büyük Kaçış" bölümü).
# Kullanım: bash tools/kacis_ses_uret.sh [kaynak=/d/ses_indir3]   -> assets/ses/kacis/
# Kesim noktaları kayıtlardaki en güçlü bölümlerden seçildi (/d/ses_indir3/tepeler.cjs).
set -e
SRC="${1:-/d/ses_indir3}"
FS="$SRC/fs"
KOK="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$KOK/assets/ses/kacis"
WORK="$KOK/build/ses_kacis"
mkdir -p "$OUT" "$WORK"
FF="ffmpeg -y -hide_banner -loglevel error"
lufs() { ffmpeg -hide_banner -nostats -i "$1" -af "apad=pad_dur=0.5,ebur128" -f null - 2>&1 | grep -A1 "Integrated loudness" | grep " I:" | awk '{print $2}'; }
norm() {
  local i g lim="aresample=176400,alimiter=limit=0.85:attack=0.5:release=50:level=0:latency=1,aresample=44100"
  i=$(lufs "$1")
  g=$(awk -v t="$3" -v i="$i" 'BEGIN{printf "%.2f", t - i}')
  $FF -i "$1" -af "aformat=channel_layouts=mono,volume=${g}dB,$lim" -c:a libvorbis -q:a 4 -ar 44100 "$OUT/$2.ogg"
  echo "$2: $(lufs "$OUT/$2.ogg") LUFS"
}
kes() {
  local d
  d=$(awk -v a="$2" -v b="$3" 'BEGIN{print b - a}')
  $FF -ss "$2" -t "$d" -i "$1" -af "aformat=channel_layouts=mono,highpass=f=60,afade=t=in:d=0.01,afade=t=out:st=$(awk -v d="$d" 'BEGIN{print d - 0.1}'):d=0.1${5:+,$5}" -ar 44100 "$4"
}
# yer altında: hafif boğuk, dar tünel yankısı
TUNEL="lowpass=f=6000,aecho=0.7:0.45:28|55:0.25|0.12"

# kürek darbeleri (4 çeşit) ve kaşık kazıması (daha ince, hızlı: perde yukarı, kısa)
i=1; for t in 145.65 180.15 206.80 258.60; do kes "$FS/kazi_kurek.mp3" $t $(awk -v t=$t 'BEGIN{print t+0.95}') "$WORK/kk$i.wav" "$TUNEL"; norm "$WORK/kk$i.wav" kurek_$i -16; i=$((i+1)); done
i=1; for t in 7.45 17.70 25.75; do kes "$FS/kazi_cesit.mp3" $t $(awk -v t=$t 'BEGIN{print t+0.7}') "$WORK/ks$i.wav" "asetrate=44100*1.35,aresample=44100,$TUNEL"; norm "$WORK/ks$i.wav" kasik_$i -19; i=$((i+1)); done
# toprak dökülmesi (kazı bitince) ve yukarıya kazarken taş-toprak yağmuru
kes "$FS/toprak_dokul.mp3" 0.0 2.4 "$WORK/td.wav" "$TUNEL"; norm "$WORK/td.wav" toprak_dokul -19
kes "$FS/tas_toprak.mp3" 0.75 3.4 "$WORK/tt.wav"; norm "$WORK/tt.wav" tas_toprak -17
# sert yüzeyler: kaya / beton (kürek çarpar, tınlar) ve tuğla dökülmesi
i=1; for t in 21.35 28.85; do kes "$FS/kurek_kaya.mp3" $t $(awk -v t=$t 'BEGIN{print t+0.85}') "$WORK/kr$i.wav" "$TUNEL"; norm "$WORK/kr$i.wav" kaya_$i -15; i=$((i+1)); done
kes "$FS/tugla_dus.mp3" 0.0 2.1 "$WORK/tg.wav" "$TUNEL"; norm "$WORK/tg.wav" tugla -16
# tornavida (vida sökme) ve vida yere düşme
kes "$FS/tornavida.mp3" 5.10 6.40 "$WORK/tv.wav"; norm "$WORK/tv.wav" vida -18
$FF -f lavfi -i "sine=f=3100:d=0.05,afade=t=out:st=0.01:d=0.04" -f lavfi -i "anullsrc=r=44100:cl=mono:d=0.08" -f lavfi -i "sine=f=2600:d=0.04,afade=t=out:st=0.01:d=0.03" -filter_complex "[0][1][2]concat=n=3:v=0:a=1,aformat=channel_layouts=mono,aecho=0.6:0.4:20:0.3" -ar 44100 "$WORK/vd.wav"
norm "$WORK/vd.wav" vida_dus -22
# klozet betonda sürüklenir
kes "$FS/tas_surukle.mp3" 8.00 10.30 "$WORK/ts.wav"; norm "$WORK/ts.wav" klozet_cek -15
# yorgun nefes (kazarken yorulunca) ve hızlı soluma
kes "$FS/nefes_agir.mp3" 1.30 5.40 "$WORK/na.wav"; norm "$WORK/na.wav" nefes -21
kes "$FS/nefes_hizli.mp3" 8.90 12.80 "$WORK/nh.wav"; norm "$WORK/nh.wav" nefes_hizli -21
# sayım zili (eski okul zili, koridorda yankılı)
kes "$FS/zil.mp3" 1.00 5.40 "$WORK/zl.wav" "aecho=0.8:0.5:90|180:0.3|0.15"; norm "$WORK/zl.wav" sayim_zili -15
# yer altı uğultusu (döngü): pembe gürültü + derin uğultu + uzaktan damla, 20 sn
$FF -f lavfi -i "anoisesrc=d=20:c=brown:r=44100:a=0.25" -f lavfi -i "sine=f=48:d=20" -filter_complex "[0]lowpass=f=420,volume=0.7[a];[1]volume=0.08[b];[a][b]amix=inputs=2:normalize=0,afade=t=in:d=1,afade=t=out:st=19:d=1" -ar 44100 "$WORK/ug.wav"
norm "$WORK/ug.wav" tunel_ortam -32
echo "tamam: $OUT"
