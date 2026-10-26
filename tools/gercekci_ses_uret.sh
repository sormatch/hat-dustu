#!/bin/bash
# Hat Düştü — gerçekçi ses tasarımı (2. tur): C4, Kısa Devre, telefon hattı, yüzeye göre ayak sesleri,
# kumaş, ortam katmanları (rüzgâr, boru suyu, telsiz, zincir, yemekhane), arayüz sesleri.
# Kullanım: bash tools/gercekci_ses_uret.sh [kaynak_klasörü=/d/ses_indir2] [bölüm...]
#   bölümler: c4 devre telefon adim ortam arayuz (verilmezse hepsi)
# Kaynaklar (hepsi CC0; ayrıntı assets/ses/LISANS.txt "Gerçekçi ses 2. tur" bölümü):
#   $SRC/fs/*.mp3            Freesound CC0 kayıtları (liste: $SRC/fs/liste.txt — id, kullanıcı, ad, adres)
#   $SRC/kenney_*/Audio      Kenney Interface/UI/Impact/RPG/Sci-fi (CC0, kenney.nl)
# Hedef: efekt ≈ -16..-18 LUFS, ayak ≈ -19, uzak olaylar ≈ -24..-26, ortam döngüleri ≈ -30..-34, arayüz ≈ -20..-16.
# Hepsi mono 44.1 kHz Ogg Vorbis, gerçek tepe ≤ -1 dBTP. Geçici dosyalar D: üstünde (C: dolu).
set -e
SRC="${1:-/d/ses_indir2}"
shift || true
BOLUM="${*:-c4 devre telefon adim ortam arayuz}"
KOK="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$KOK/assets/ses"
WORK="$KOK/build/ses2/tmp"
mkdir -p "$WORK"
FS="$SRC/fs"
FF="ffmpeg -y -hide_banner -loglevel error"
var() { [[ " $BOLUM " == *" $1 "* ]]; }

lufs() { ffmpeg -hide_banner -nostats -i "$1" -af "apad=pad_dur=0.5,ebur128" -f null - 2>&1 | grep -A1 "Integrated loudness" | grep " I:" | awk '{print $2}'; }

# norm <giriş> <çıkış.ogg> <hedef LUFS>: kazanç + tepe sınırlayıcı (-1 dBFS, 4x örnekleme) + Vorbis (mono 44.1k)
norm() {
  local i g lim="aresample=176400,alimiter=limit=0.8:attack=0.5:release=50:level=0:latency=1,aresample=44100"
  i=$(lufs "$1")
  g=$(awk -v t="$3" -v i="$i" 'BEGIN{printf "%.2f", t - i}')
  $FF -i "$1" -af "aformat=channel_layouts=mono,volume=${g}dB,$lim" -c:a pcm_f32le "$WORK/_n1.wav"
  i=$(lufs "$WORK/_n1.wav")
  g=$(awk -v t="$3" -v i="$i" 'BEGIN{printf "%.2f", t - i}')
  $FF -i "$WORK/_n1.wav" -af "volume=${g}dB,$lim,aformat=sample_fmts=fltp:channel_layouts=mono" -ar 44100 -c:a libvorbis -q:a 5 "$2"
  echo "  $(basename "$2"): $(lufs "$2") LUFS"
}

# kes <kaynak> <başla> <süre> <çıkış.wav> [ek süzgeç]: mono 44.1k parça, 5 ms açılış, 30 ms kapanış
kes() {
  local f="aformat=channel_layouts=mono,aresample=44100,afade=t=in:d=0.005,areverse,afade=t=in:d=0.03,areverse"
  $FF -ss "$2" -t "$3" -i "$1" -af "$f${5:+,$5}" -c:a pcm_f32le "$4"
}

# dongu <giriş.wav> <çıkış.wav> <süre> <geçiş>: dikişsiz döngü (kuyruk başa çapraz geçişle bindirilir)
dongu() {
  local d="$3" x="$4"
  $FF -i "$1" -filter_complex "[0:a]asplit=3[a][b][c];\
[a]atrim=start=$d:end=$(awk -v d=$d -v x=$x 'BEGIN{print d+x}'),asetpts=PTS-STARTPTS,afade=t=out:d=$x:curve=qsin[k];\
[b]atrim=start=0:end=$x,asetpts=PTS-STARTPTS,afade=t=in:d=$x:curve=qsin[h];\
[c]atrim=start=$x:end=$d,asetpts=PTS-STARTPTS[g];\
[k][h]amix=inputs=2:normalize=0[bas];[bas][g]concat=n=2:v=0:a=1" -c:a pcm_f32le "$2"
}

# karistir <çıkış.wav> <giriş:gecikme_ms:kazanç_dB> ...: katmanları gecikmeli toplar
karistir() {
  local out="$1"; shift
  local ins="" fc="" n=0 l
  for l in "$@"; do
    IFS=: read -r f dl g <<< "$l"
    ins="$ins -i $f"
    fc="$fc[$n:a]aformat=channel_layouts=mono,aresample=44100,adelay=${dl}:all=1,volume=${g}dB[s$n];"
    n=$((n + 1))
  done
  local m=""
  for ((k = 0; k < n; k++)); do m="$m[s$k]"; done
  $FF $ins -filter_complex "${fc}${m}amix=inputs=$n:normalize=0:duration=longest" -c:a pcm_f32le "$out"
}

# sentez <çıkış.wav> <süre> <ifade>: aevalsrc ile mono sentez
sentez() { $FF -f lavfi -i "aevalsrc='$3':s=44100:d=$2" -c:a pcm_f32le "$1"; }

W="$WORK"

# =====================================================================
if var c4; then
echo "== C4"
# yakın patlama: keskin patlama + gövde (alçak geçiren ikinci patlama) + alt bas + enkaz yağmuru + küçük oda yansıması
kes "$FS/grenade_meaty.mp3" 0 3.4 $W/c4_a.wav
kes "$FS/medium_blast.mp3" 0.30 4.0 $W/c4_b.wav "lowpass=f=900,lowpass=f=900"
sentez $W/c4_sub.wav 2.6 "0.9*sin(2*PI*(36*t+(22/5)*(1-exp(-5*t))))*exp(-2.6*t)*min(1,t*400)"
kes "$FS/debris_short.mp3" 0 2.8 $W/c4_d.wav "highpass=f=250"
kes "$FS/long_crash.mp3" 0.4 4.6 $W/c4_e.wav "highpass=f=300,afade=t=out:st=2.6:d=2.0"
karistir $W/c4_y.wav $W/c4_a.wav:0:0 $W/c4_b.wav:10:-3 $W/c4_sub.wav:0:-4 $W/c4_d.wav:420:-9 $W/c4_e.wav:900:-17
$FF -i $W/c4_y.wav -af "aecho=0.85:0.55:19|37|53:0.32|0.2|0.12" -c:a pcm_f32le $W/c4_y2.wav
norm $W/c4_y2.wav "$OUT/c4_patlama.ogg" -15
# uzak patlama (koridorun öbür ucu, duvar arkası): boğuk gövde + uzak gürleme + uzun koridor yankısı + hafif enkaz
$FF -i $W/c4_y.wav -af "lowpass=f=420,lowpass=f=420" -c:a pcm_f32le $W/c4_u1.wav
kes "$FS/distant_expl.mp3" 0 6 $W/c4_u2.wav "lowpass=f=1200"
karistir $W/c4_u.wav $W/c4_u1.wav:60:0 $W/c4_u2.wav:0:2 $W/c4_e.wav:700:-24
$FF -i $W/c4_u.wav -af "aecho=0.8:0.6:140|290|470|690:0.45|0.32|0.22|0.14,lowpass=f=1400,afade=t=out:st=4.2:d=1.6" -t 6 -c:a pcm_f32le $W/c4_u3.wav
norm $W/c4_u3.wav "$OUT/c4_uzak.ogg" -20
# kulak çınlaması: 3.9 kHz ve hafif vuruşlu ikinci ton, yavaş söner (sentez, oyuna ait)
sentez $W/cin.wav 4.5 "(0.5*sin(2*PI*3900*t)+0.25*sin(2*PI*3913*t)+0.08*sin(2*PI*7800*t))*min(1,t*3)*exp(-0.55*t)"
norm $W/cin.wav "$OUT/cinlama.ogg" -24
# C4 bip: piezo hoparlör (3.1 kHz kare dalga harmonikleri) + plastik kasa tınısı + tık; 95 ms
sentez $W/bip.wav 0.16 "(sin(2*PI*3150*t)+0.33*sin(2*PI*9450*t)+0.12*sin(2*PI*15750*t))*min(1,t/0.002)*if(lt(t,0.095),1,exp(-(t-0.095)*180))+0.3*sin(2*PI*1250*t)*exp(-t*60)*min(1,t/0.001)"
$FF -i $W/bip.wav -af "equalizer=f=2600:t=q:w=2:g=4,aecho=0.8:0.25:7|13:0.25|0.15" -c:a pcm_f32le $W/bip2.wav
norm $W/bip2.wav "$OUT/c4_bip.ogg" -18
fi

# =====================================================================
if var devre; then
echo "== Kısa Devre"
# elektrik kesilir: şalter "kılık" + trafo vızıltısının (50 Hz ve harmonikleri) düşerek sönmesi + kısa ark + floresan tıkı
kes "$FS/big_breaker.mp3" 1.55 1.2 $W/e_k.wav
sentez $W/e_hum.wav 2.4 "(0.5*sin(2*PI*50*(1-exp(-1.1*t))/1.1)+0.35*sin(2*PI*100*(1-exp(-1.1*t))/1.1)+0.2*sin(2*PI*150*(1-exp(-1.1*t))/1.1)+0.1*sin(2*PI*300*(1-exp(-1.1*t))/1.1))*exp(-1.6*t)"
kes "$FS/spark_bed.mp3" 1.0 0.35 $W/e_ark.wav "afade=t=out:st=0.1:d=0.25"
kes "$FS/fluo_flicker.mp3" 0.0 0.12 $W/e_tik.wav
karistir $W/e.wav $W/e_k.wav:0:0 $W/e_hum.wav:20:-6 $W/e_ark.wav:0:-8 $W/e_tik.wav:160:-10
norm $W/e.wav "$OUT/elektrik_kes.ogg" -17
# ışık geri gelir: floresan starter tıkları (cell.gd power_on_sequence ile aynı zamanlama) + tüpün yanıp vızıldaması
kes "$FS/fluo_flicker.mp3" 0.68 0.14 $W/f1.wav
kes "$FS/fluo_flicker.mp3" 1.18 0.06 $W/f2.wav
kes "$FS/fluo_on_off.mp3" 1.55 2.2 $W/f3.wav "afade=t=out:st=0.8:d=1.4"
kes "$FS/big_breaker.mp3" 0.2 0.6 $W/f0.wav
karistir $W/f.wav $W/f0.wav:0:-8 $W/f1.wav:240:0 $W/f2.wav:420:-2 $W/f1.wav:560:-4 $W/f3.wav:620:0
norm $W/f.wav "$OUT/floresan_yan.ogg" -21.8
# sigorta kutusundaki ark çıtırtısı (döngü, 3B): gerçek elektrik arkı kaydı, dikişsiz 6 sn
kes "$FS/spark_bed.mp3" 0.5 7.0 $W/c.wav "highpass=f=120"
dongu $W/c.wav $W/c2.wav 6.0 0.8
norm $W/c2.wav "$OUT/ark_dongu.ogg" -24
# sigorta yerine oturur: gerçek sigorta kutusu tıkı + Kenney metal mandal, kısa metal kutu tınısı
kes "$FS/fusebox_klick.mp3" 0 0.5 $W/s1.wav
kes "$SRC/kenney_rpg-audio/Audio/metalLatch.ogg" 0 0.4 $W/s2.wav
karistir $W/s.wav $W/s1.wav:0:0 $W/s2.wav:8:-8
$FF -i $W/s.wav -af "aecho=0.8:0.3:11|23:0.2|0.1" -c:a pcm_f32le $W/s3.wav
norm $W/s3.wav "$OUT/devre/klik.ogg" -18
# şalter kolu: büyük şalterin kalkması (gerçek kayıt) + mevcut şalter katmanı
kes "$FS/big_breaker.mp3" 0.15 1.3 $W/sl1.wav
karistir $W/sl.wav $W/sl1.wav:0:0 "$KOK/build/ses2/eski/devre_salter.ogg":0:-10
norm $W/sl.wav "$OUT/devre/salter.ogg" -17
fi

# =====================================================================
if var telefon; then
echo "== Telefon"
mkdir -p "$OUT/telefon"
# hat hışırtısı: pembe gürültü, 300-3400 Hz bant (görüşme boyunca çok kısık, voice.gd)
$FF -f lavfi -i "anoisesrc=color=pink:r=44100:a=0.5:d=10" -af "highpass=f=300,highpass=f=300,lowpass=f=3400,lowpass=f=3400" -c:a pcm_f32le $W/h.wav
sentez $W/h50.wav 10 "0.02*sin(2*PI*50*t)+0.01*sin(2*PI*150*t)"
karistir $W/h2.wav $W/h.wav:0:0 $W/h50.wav:0:0
dongu $W/h2.wav $W/h3.wav 8 1
norm $W/h3.wav "$OUT/telefon/hat.ogg" -30
# hat tonları (Türkiye, ITU-T E.180): 450 Hz; çevir sesi sürekli, çalma 2 sn açık 4 sn kapalı, meşgul 0.5/0.5.
# Hattan geçmiş gibi: bant süzgeci + karbon mikrofon doyması + altta kısık hışırtı.
ton() { sentez "$1" "$2" "0.5*sin(2*PI*450*t)*($3)"; $FF -i "$1" -af "highpass=f=300,lowpass=f=3400,asoftclip=type=tanh" -c:a pcm_f32le "$1.b.wav"; karistir "$1.k.wav" "$1.b.wav":0:0 $W/h3.wav:0:-26; $FF -i "$1.k.wav" -t "$2" -c:a pcm_f32le "$1.c.wav"; }
ton $W/tc.wav 2 "1"
norm $W/tc.wav.c.wav "$OUT/telefon/cevir_sesi.ogg" -18
ton $W/tm.wav 3 "if(lt(mod(t,1),0.5),min(1,mod(t,1)/0.01)*min(1,(0.5-mod(t,1))/0.01),0)"
norm $W/tm.wav.c.wav "$OUT/telefon/mesgul.ogg" -18
# çalma: önce gerçek döner kadran (iki rakam çevrilir), santral tıkı, sonra 2/4 sn çalma sesi döngüsü.
# Döngü başı (loop_offset) = KADRAN_SN + 0.45 → telefon.gd CALMA_DONGU
kes "$FS/rotary_dial.mp3" 1.25 2.85 $W/kd.wav "highpass=f=90"
ton $W/tr.wav 6 "if(lt(t,2),min(1,t/0.01)*min(1,(2-t)/0.01),0)"
sentez $W/sant.wav 0.06 "0.4*sin(2*PI*900*t)*exp(-t*90)"
$FF -i $W/kd.wav -af "volume=4dB" -c:a pcm_f32le $W/kd2.wav
$FF -i $W/kd2.wav -i $W/sant.wav -f lavfi -t 0.39 -i "anullsrc=r=44100:cl=mono" -i $W/tr.wav.c.wav -filter_complex "[0:a]aformat=channel_layouts=mono[a];[1:a]aformat=channel_layouts=mono[b];[2:a]aformat=channel_layouts=mono[c];[3:a]aformat=channel_layouts=mono,volume=-6dB[d];[a][b][c][d]concat=n=4:v=0:a=1" -c:a pcm_f32le $W/cal.wav
norm $W/cal.wav "$OUT/telefon/calma_sesi.ogg" -19
# ahize kaldırma (çatal yayı) ve bırakma (bakalit çarpması + zil kabı) — gerçek eski telefon kayıtları, 3 çeşit
kes "$FS/phone_pickup_hangup.mp3" 0.0 0.45 $W/k1.wav
kes "$FS/phone_pickup_hangup.mp3" 0.95 0.5 $W/k2.wav
kes "$FS/heavy_phone_updown.mp3" 0.0 0.55 $W/k3.wav
kes "$FS/phone_pickup_hangup.mp3" 4.35 0.6 $W/b1.wav
kes "$FS/phone_pickup_hangup.mp3" 6.05 0.6 $W/b2.wav
kes "$FS/heavy_phone_updown.mp3" 2.45 0.8 $W/b3.wav
for i in 1 2 3; do norm $W/k$i.wav "$OUT/telefon/kaldir_$i.ogg" -21; norm $W/b$i.wav "$OUT/telefon/birak_$i.ogg" -18; done
fi

# =====================================================================
if var adim; then
echo "== Ayak ve kumaş"
# metal (hücre kapısı eşiğindeki çelik ray/ızgara): gerçek metal zemin adımları
i=0
for t in 0.0 0.69 1.34 2.00 2.66 3.37; do
  kes "$FS/steps_metal_floor.mp3" $t 0.32 $W/m$i.wav "highpass=f=70,acompressor=threshold=0.05:ratio=4:attack=0.5:release=40:makeup=2"
  norm $W/m$i.wav "$OUT/adim_metal_$i.ogg" -19
  i=$((i + 1))
done
# ahşap (yemekhane zemini): gerçek ahşap zemin adımları (Nox_Sound), hafif gürültü temizliği
i=0
for t in 0.0 4.25 10.37 12.11 21.15 22.13; do
  kes "$FS/steps_wood.mp3" $t 0.36 $W/t$i.wav "highpass=f=60,afftdn=nr=12:nf=-50,acompressor=threshold=0.08:ratio=3:attack=1:release=50:makeup=1.5"
  norm $W/t$i.wav "$OUT/adim_ahsap_$i.ogg" -19
  $FF -i $W/t$i.wav -af "asetrate=44100*1.05,aresample=44100,equalizer=f=160:t=q:w=1:g=3" -c:a pcm_f32le $W/tk$i.wav
  norm $W/tk$i.wav "$OUT/kos_ahsap_$i.ogg" -17.5
  i=$((i + 1))
done
# kumaş: eğilme/kalkma, oturma (gerçek giysi hışırtısı)
kes "$FS/cloth_ruffle1.mp3" 4.50 0.5 $W/ku1.wav
kes "$FS/cloth_ruffle1.mp3" 5.60 0.5 $W/ku2.wav
kes "$FS/cloth_ruffle2.mp3" 3.28 0.95 $W/ku3.wav
norm $W/ku1.wav "$OUT/kumas_1.ogg" -26
norm $W/ku2.wav "$OUT/kumas_2.ogg" -26
norm $W/ku3.wav "$OUT/kumas_3.ogg" -26
# oturma/kalkma: eski metal sandalye gıcırtısı + giysi hışırtısı
karistir $W/ko.wav "$KOK/build/ses2/eski/koltuk_otur.ogg":0:0 $W/ku3.wav:0:-6
norm $W/ko.wav "$OUT/koltuk_otur.ogg" -20
karistir $W/kk.wav "$KOK/build/ses2/eski/koltuk_kalk.ogg":60:0 $W/ku1.wav:0:-5
norm $W/kk.wav "$OUT/koltuk_kalk.ogg" -20
fi

# =====================================================================
if var ortam; then
echo "== Ortam"
# rüzgâr: binanın kapı aralığından uğuldayan rüzgâr (felix.blume), 20 sn dikişsiz döngü, koridor ucunda
kes "$FS/wind_door.mp3" 30 23 $W/r.wav "highpass=f=170,highpass=f=170,lowpass=f=5000"
dongu $W/r.wav $W/r2.wav 20 3
norm $W/r2.wav "$OUT/ortam_ruzgar.ogg" -30
# borudan akan su (bodrum borusu hışırtı + guruldama), 16 sn döngü, koridor tavanındaki boru
kes "$FS/water_pipe.mp3" 8 19 $W/b.wav "highpass=f=80"
dongu $W/b.wav $W/b2.wav 16 3
norm $W/b2.wav "$OUT/ortam_boru_su.ogg" -32
# yemekhane kalabalık uğultusu (okul yemekhanesi, anlaşılmaz) + tabak/çatal: 24 sn döngü, yan salondan gelir gibi
kes "$FS/school_canteen.mp3" 20 27 $W/y.wav "highpass=f=90,lowpass=f=3500"
kes "$FS/canteen_cutlery.mp3" 2 27 $W/y1.wav "highpass=f=200"
karistir $W/yk.wav $W/y.wav:0:0 $W/y1.wav:0:-8
dongu $W/yk.wav $W/y2.wav 24 3
norm $W/y2.wav "$OUT/lobi_ugultu.ogg" -31
# tek tek tabak / çatal / tepsi (yemekhanede rastgele 3B olaylar)
kes "$FS/tableware_plates.mp3" 1.92 0.7 $W/l1.wav
kes "$FS/tableware_plates.mp3" 4.63 0.5 $W/l2.wav
kes "$FS/tableware_plates.mp3" 7.99 0.95 $W/l3.wav
kes "$FS/platos_cubiertos.mp3" 16.85 1.7 $W/l4.wav
for i in 1 2 3 4; do
  $FF -i $W/l$i.wav -af "aecho=0.8:0.5:60|110:0.25|0.15" -c:a pcm_f32le $W/l${i}b.wav
  norm $W/l${i}b.wav "$OUT/lobi_tabak_$i.ogg" -26
done
# uzak gardiyan telsizi: cızırtı açılışı + anlaşılmaz konuşma (dar bant, bozuk, yankılı) + kapanış cızırtısı
kes "$FS/squelch.mp3" 0 0.3 $W/sq.wav
kes "$FS/walkie_end.mp3" 0 0.4 $W/we.wav
i=1
for t in 1.0 8.5 15.5; do
  kes "$FS/police_radio.mp3" $t 3.2 $W/pr$i.wav "highpass=f=500,lowpass=f=2400,asoftclip=type=hard:param=0.6,lowpass=f=1800,acrusher=bits=8:mix=0.4"
  $FF -i $W/sq.wav -i $W/pr$i.wav -i $W/we.wav -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1,aecho=0.8:0.6:120|260|410:0.4|0.28|0.18,lowpass=f=2600" -c:a pcm_f32le $W/te$i.wav
  norm $W/te$i.wav "$OUT/uzak_telsiz_$i.ogg" -27
  i=$((i + 1))
done
# kapıda kilit zinciri: asma kilit ve zincirin şıngırtısı, koridor yankısıyla
kes "$FS/padlock_chain.mp3" 0.40 1.4 $W/z1.wav
kes "$FS/padlock_chain.mp3" 2.50 2.3 $W/z2.wav
kes "$FS/chain_rattle.mp3" 0 1.5 $W/z3.wav
for i in 1 2 3; do
  $FF -i $W/z$i.wav -af "lowpass=f=4500,aecho=0.8:0.55:90|210|340:0.35|0.24|0.15" -c:a pcm_f32le $W/z${i}b.wav
  norm $W/z${i}b.wav "$OUT/uzak_zincir_$i.ogg" -26
done
fi

# =====================================================================
if var arayuz; then
echo "== Arayüz"
# Hepsi aynı aileden: kısa yumuşak tık + La majör beşli ton (A5=880, C#6=1109, E6=1319, A6=1760), marimba gibi çabuk söner.
nota() { echo "(sin(2*PI*$1*t)+0.25*sin(2*PI*$1*4*t)*exp(-t*40))*exp(-t*$2)*min(1,t/0.003)"; }
# dokunma: kısa keçeli tık + çok kısık tiz ton
kes "$SRC/kenney_ui-audio/Audio/click3.ogg" 0 0.08 $W/u_c.wav
sentez $W/u_t.wav 0.12 "0.3*$(nota 1760 55)"
karistir $W/u.wav $W/u_c.wav:0:-3 $W/u_t.wav:0:-14
norm $W/u.wav "$OUT/tik_ui.ogg" -24
# pencere açılış: yükselen iki nota + hafif hava sesi; kapanış: inen iki nota
$FF -f lavfi -i "anoisesrc=color=pink:r=44100:a=0.3:d=0.25" -af "bandpass=f=2500:w=2000,afade=t=in:d=0.12,afade=t=out:st=0.12:d=0.13" -c:a pcm_f32le $W/u_w.wav
sentez $W/u_a1.wav 0.4 "0.35*$(nota 1109 18)"
sentez $W/u_a2.wav 0.4 "0.35*$(nota 1319 14)"
karistir $W/ua.wav $W/u_w.wav:0:-10 $W/u_a1.wav:20:0 $W/u_a2.wav:85:0
norm $W/ua.wav "$OUT/ui_ac.ogg" -24
karistir $W/uk.wav $W/u_w.wav:0:-12 $W/u_a2.wav:0:-1 $W/u_a1.wav:65:-2
norm $W/uk.wav "$OUT/ui_kapa.ogg" -25
# ödül: üç nota arpej + parıltı (eski odul katmanı altta)
sentez $W/o1.wav 0.9 "0.35*$(nota 880 9)"
sentez $W/o2.wav 0.9 "0.35*$(nota 1109 8)"
sentez $W/o3.wav 1.1 "0.35*$(nota 1319 6)+0.06*sin(2*PI*2638*t)*exp(-t*5)"
karistir $W/o.wav $W/o1.wav:0:0 $W/o2.wav:70:0 $W/o3.wav:140:0 "$KOK/build/ses2/eski/odul.ogg":0:-12
norm $W/o.wav "$OUT/odul.ogg" -17
# seviye atlama: dört nota yükselen arpej + kalan akor + Kenney zafer parıltısı
sentez $W/s4.wav 1.6 "0.3*$(nota 1760 3)+0.12*$(nota 1319 3)+0.1*$(nota 1109 3)"
karistir $W/sv.wav $W/o1.wav:0:-2 $W/o2.wav:90:-2 $W/o3.wav:180:-2 $W/s4.wav:270:0 "$OUT/parilti.ogg":270:-10
norm $W/sv.wav "$OUT/seviye.ogg" -16
fi
rm -f $W/*.wav
echo "bitti"
