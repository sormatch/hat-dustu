#!/bin/bash
# Hat Düştü — ortam, ayak ve etkileşim seslerini CC0 kaynaklardan karıştırır (ffmpeg).
# Kullanım: bash tools/ortam_ses_uret.sh <indirilen_kaynaklar_klasoru>
# Kaynak klasörün içinde beklenenler (hepsi CC0, ayrıntı assets/ses/LISANS.txt):
#   kenney_impact-sounds/Audio, kenney_rpg-audio/Audio      (kenney.nl)
#   fantozzi/Fantozzi-footsteps/flac                         (OpenGameArt "Fantozzi's Footsteps")
#   mw/  (OpenGameArt "100 CC0 metal and wood SFX"), mech/ ("Mechanical Sounds"), elev/ ("old elevator door")
#   cough/ ("Old Man Cough"), sick/ ("Sick Noises"), crowd/ ("Crowd Shouting/Speaking Ambience")
# Hedef seviyeler: efekt ≈ -16..-18 LUFS, ayak ≈ -18 LUFS, uzak ortam olayları ≈ -24 LUFS, ortam döngüsü ≈ -30 LUFS.
# Tüm çıktılar mono 44.1 kHz Ogg Vorbis, gerçek tepe ≤ -1 dBTP.
set -e
SRC="${1:?kaynak klasörü ver}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/assets/ses"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
K="$SRC/kenney_impact-sounds/Audio"
R="$SRC/kenney_rpg-audio/Audio"
F="$SRC/fantozzi/Fantozzi-footsteps/flac"
FF="ffmpeg -y -hide_banner -loglevel error"

# bütünleşik ses yüksekliği (kısa sesler için sona sessizlik eklenerek ölçülür)
lufs() { ffmpeg -hide_banner -nostats -i "$1" -af "apad=pad_dur=0.5,ebur128" -f null - 2>&1 | grep -A1 "Integrated loudness" | grep " I:" | awk '{print $2}'; }

# norm <giriş> <çıkış.ogg> <hedef LUFS>: kazanç + tepe sınırlayıcı (-1 dBFS) + Vorbis
norm() {
  local i g lim="alimiter=limit=0.84:attack=1:release=60:level=0:latency=1"
  i=$(lufs "$1")
  g=$(awk -v t="$3" -v i="$i" 'BEGIN{printf "%.2f", t - i}')
  $FF -i "$1" -af "volume=${g}dB,$lim" -c:a pcm_f32le "$WORK/_n1.wav"
  # sınırlayıcı tepeleri kırpınca ses yüksekliği düşer: ikinci geçişte farkı kapat
  i=$(lufs "$WORK/_n1.wav")
  g=$(awk -v t="$3" -v i="$i" 'BEGIN{printf "%.2f", t - i}')
  $FF -i "$WORK/_n1.wav" -af "volume=${g}dB,$lim,aformat=sample_fmts=fltp:channel_layouts=mono" -ar 44100 -c:a libvorbis -q:a 5 "$2"
}

# mono 44.1 kHz ara dosya
mono() { $FF -i "$1" -ac 1 -ar 44100 ${2:+-af "$2"} "$3"; }

# sondaki sessizliği kırp, 30 ms yumuşak bitir
KIRP="areverse,silenceremove=start_periods=1:start_threshold=-62dB,afade=t=in:d=0.03,areverse"
# uzak koridor: alçak/yüksek geçiren + seyrek erken yansımalar + uzun kuyruk (sabit; çalışma anında yankı yok)
UZAK="highpass=f=150,lowpass=f=2300,apad=pad_dur=2.5,aecho=0.85:0.8:47|89|143|211|307|433|601|823|1090:0.55|0.46|0.38|0.31|0.24|0.17|0.11|0.07|0.045,lowpass=f=3200,$KIRP"

echo "== ayak sesleri (beton): 6 yürüme + 6 koşma"
n=0
for s in StoneL1 StoneR1 StoneL2 StoneR2 StoneL3 StoneR3; do
  mono "$F/Fantozzi-$s.flac" "highpass=f=70,$KIRP" "$WORK/y$n.wav"
  norm "$WORK/y$n.wav" "$OUT/adim_$n.ogg" -18
  # koşma: aynı adım + Kenney beton topuk vuruşu, biraz tiz ve kısa
  kc=$(printf "%03d" $((n % 5)))
  $FF -i "$WORK/y$n.wav" -i "$K/footstep_concrete_$kc.ogg" -filter_complex \
    "[1:a]aformat=channel_layouts=mono,aresample=44100,volume=-3dB[k];[0:a]asetrate=44100*1.06,aresample=44100[a];[a][k]amix=inputs=2:normalize=0,afade=t=out:st=0.22:d=0.08,$KIRP" "$WORK/k$n.wav"
  norm "$WORK/k$n.wav" "$OUT/kos_$n.ogg" -16
  n=$((n + 1))
done

echo "== hücre kapısı (paslı çelik)"
# kilit: anahtar dönüşü + Kenney sürgü, biraz kalın
$FF -i "$SRC/mw/lock_open_01.ogg" -i "$R/metalLatch.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.8,aresample=44100,adelay=380,volume=-4dB[b];[a][b]amix=inputs=2:normalize=0,highpass=f=60,$KIRP" "$WORK/kilit.wav"
norm "$WORK/kilit.wav" "$OUT/kapi_kilit.ogg" -17
# paslı menteşe gıcırtısı: Kenney creak kalınlaştırılır (yavaş + alçak), ikinci katman hafif kaydırılır
for v in 1 2; do
  p1=$([ $v = 1 ] && echo 0.72 || echo 0.66); p2=$([ $v = 1 ] && echo 0.81 || echo 0.76); c2=$([ $v = 1 ] && echo creak2 || echo creak3)
  $FF -i "$R/creak1.ogg" -i "$R/$c2.ogg" -filter_complex \
    "[0:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*$p1,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*$p2,aresample=44100,adelay=120,volume=-5dB[b];[a][b]amix=inputs=2:normalize=0,highpass=f=90,lowpass=f=5200,aecho=0.8:0.4:23|41:0.3|0.2,$KIRP" "$WORK/gic$v.wav"
  norm "$WORK/gic$v.wav" "$OUT/kapi_gicirti_$v.ogg" -19
done
# kapanış: menteşe sürtünmesi (kapı dönerken) + 0.72 sn'de ağır çelik çarpma + alçak gümbürtü + kısa koridor yankısı
$FF -i "$R/creak3.ogg" -i "$SRC/mw/metal_slam_01.ogg" -i "$K/impactMetal_heavy_000.ogg" -i "$K/impactPlate_heavy_002.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.7,aresample=44100,atrim=0:0.75,afade=t=out:st=0.5:d=0.25,volume=-9dB[c];\
[1:a]aformat=channel_layouts=mono,aresample=44100,adelay=720[s];\
[2:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.75,aresample=44100,adelay=725,volume=-3dB[m];\
[3:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.55,aresample=44100,lowpass=f=400,adelay=720,volume=-2dB[t];\
[c][s][m][t]amix=inputs=4:normalize=0,highpass=f=45,apad=pad_dur=0.6,aecho=0.9:0.5:61|113|177:0.3|0.22|0.14,$KIRP" "$WORK/carp.wav"
norm "$WORK/carp.wav" "$OUT/kapi_carp.ogg" -16

echo "== koltuk (oturma / kalkma)"
$FF -i "$R/cloth2.ogg" -i "$SRC/mech/squeakyclick1.wav" -i "$K/impactSoft_medium_001.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.85,aresample=44100,adelay=420,volume=-3dB[b];[2:a]aformat=channel_layouts=mono,aresample=44100,adelay=400,volume=-2dB[c];[a][b][c]amix=inputs=3:normalize=0,highpass=f=70,$KIRP" "$WORK/otur.wav"
norm "$WORK/otur.wav" "$OUT/koltuk_otur.ogg" -20
$FF -i "$SRC/mech/squeakyclick2.wav" -i "$R/cloth4.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.9,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,adelay=150,volume=-2dB[b];[a][b]amix=inputs=2:normalize=0,highpass=f=70,$KIRP" "$WORK/kalk.wav"
norm "$WORK/kalk.wav" "$OUT/koltuk_kalk.ogg" -21

echo "== dolap kapağı kapanış, sigorta kutusu kapağı"
$FF -i "$SRC/mw/metal_sheet_02.ogg" -i "$K/impactMetal_light_002.ogg" -i "$R/metalClick.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,volume=-4dB[b];[2:a]aformat=channel_layouts=mono,aresample=44100,adelay=90,volume=-6dB[c];[a][b][c]amix=inputs=3:normalize=0,highpass=f=80,$KIRP" "$WORK/dk.wav"
norm "$WORK/dk.wav" "$OUT/dolap_kapa.ogg" -17
$FF -i "$SRC/mw/metal_spring_01.ogg" -i "$K/impactPlate_light_000.ogg" -i "$R/metalLatch.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100,adelay=40[a];[1:a]aformat=channel_layouts=mono,aresample=44100,volume=-3dB[b];[2:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*1.15,aresample=44100,volume=-6dB[c];[a][b][c]amix=inputs=3:normalize=0,highpass=f=90,$KIRP" "$WORK/sa.wav"
norm "$WORK/sa.wav" "$OUT/sigorta_ac.ogg" -18
$FF -i "$K/impactMetal_light_001.ogg" -i "$R/metalClick.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,adelay=70,volume=-3dB[b];[a][b]amix=inputs=2:normalize=0,highpass=f=90,$KIRP" "$WORK/sk.wav"
norm "$WORK/sk.wav" "$OUT/sigorta_kapa.ogg" -19

echo "== uzak ortam olayları (3B, koridor ucundan)"
mono "$SRC/mw/metal_slam_01.ogg" "$UZAK" "$WORK/u1.wav"; norm "$WORK/u1.wav" "$OUT/uzak_kapi_1.ogg" -24
$FF -i "$SRC/mw/metal_close_01.ogg" -i "$K/impactMetal_heavy_002.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.7,aresample=44100,volume=-3dB[b];[a][b]amix=inputs=2:normalize=0,$UZAK" "$WORK/u2.wav"
norm "$WORK/u2.wav" "$OUT/uzak_kapi_2.ogg" -24
$FF -i "$K/impactPlate_heavy_001.ogg" -i "$K/impactMetal_heavy_004.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.7,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.62,aresample=44100,adelay=15[b];[a][b]amix=inputs=2:normalize=0,$UZAK" "$WORK/u3.wav"
norm "$WORK/u3.wav" "$OUT/uzak_kapi_3.ogg" -24
mono "$SRC/elev/old_elevator_door.mp3" "$UZAK" "$WORK/u4.wav"; norm "$WORK/u4.wav" "$OUT/uzak_parmaklik.ogg" -25
mono "$SRC/cough/old-man-cough.flac" "atrim=0:2.35,afade=t=out:st=2.15:d=0.2,$UZAK" "$WORK/o1.wav"; norm "$WORK/o1.wav" "$OUT/uzak_oksuruk_1.ogg" -26
mono "$SRC/cough/old-man-cough.flac" "atrim=2.45:3.5,asetpts=PTS-STARTPTS,afade=t=out:st=0.85:d=0.2,$UZAK" "$WORK/o2.wav"; norm "$WORK/o2.wav" "$OUT/uzak_oksuruk_2.ogg" -26
mono "$SRC/sick/sickness.wav" "atrim=0:3.2,afade=t=out:st=2.9:d=0.3,$UZAK" "$WORK/o3.wav"; norm "$WORK/o3.wav" "$OUT/uzak_oksuruk_3.ogg" -27
$FF -i "$SRC/mw/keys_02.ogg" -i "$SRC/mw/keys_03.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,adelay=520[b];[a][b]amix=inputs=2:normalize=0,$UZAK" "$WORK/u5.wav"
norm "$WORK/u5.wav" "$OUT/uzak_anahtar.ogg" -27
$FF -i "$SRC/mw/metal_hit_03.ogg" -i "$SRC/mw/metal_hit_05.ogg" -filter_complex \
  "[0:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.6,aresample=44100[a];[1:a]aformat=channel_layouts=mono,aresample=44100,asetrate=44100*0.55,aresample=44100,adelay=380,volume=-3dB[b];[a][b]amix=inputs=2:normalize=0,$UZAK" "$WORK/u6.wav"
norm "$WORK/u6.wav" "$OUT/uzak_boru.ogg" -26
mono "$SRC/crowd/crowd_shouting_0.ogg" "atrim=10:12.6,asetpts=PTS-STARTPTS,afade=t=in:d=0.15,afade=t=out:st=2.2:d=0.4,highpass=f=200,lowpass=f=1500,$UZAK" "$WORK/u7.wav"; norm "$WORK/u7.wav" "$OUT/uzak_bagiris.ogg" -28

echo "== ortam döngüsü (havalandırma + floresan vızıltısı + uzak uğultu + damla), 24 sn, uçlar çapraz geçişli"
L=24; X=3; D=$((L + X))
$FF -f lavfi -i "anoisesrc=d=$D:c=brown:r=44100:a=0.7:seed=11" -af "highpass=f=35,lowpass=f=380,tremolo=f=0.1:d=0.25" "$WORK/b_vent.wav"
$FF -f lavfi -i "anoisesrc=d=$D:c=pink:r=44100:a=0.5:seed=23" -af "highpass=f=500,lowpass=f=2200" "$WORK/b_hava.wav"
$FF -f lavfi -i "aevalsrc=exprs='0.3*sin(2*PI*100*t)+0.14*sin(2*PI*200*t)+0.07*sin(2*PI*300*t)+0.035*sin(2*PI*400*t)':d=$D:s=44100" "$WORK/b_hum.wav"
$FF -f lavfi -i "anoisesrc=d=$D:c=white:r=44100:a=0.5:seed=5" -f lavfi -i "aevalsrc=exprs='pow(abs(sin(PI*100*t)),14)':d=$D:s=44100" -filter_complex "[0:a][1:a]amultiply,highpass=f=1800,lowpass=f=6000" "$WORK/b_buzz.wav"
$FF -i "$SRC/crowd/crowd_shouting_0.ogg" -af "aformat=channel_layouts=mono,aresample=44100,atrim=0:$D,highpass=f=180,lowpass=f=650,apad=pad_dur=1,aecho=0.8:0.85:67|131|223|347:0.5|0.4|0.3|0.2,atrim=0:$D" "$WORK/b_ugul.wav"
$FF -stream_loop 1 -i "$OUT/damla_ortam.mp3" -af "aformat=channel_layouts=mono,aresample=44100,atrim=0:$D" "$WORK/b_damla.wav"
# katmanlar kendi ses yüksekliğine getirilip toplanır
for p in "vent -33" "hava -45" "hum -44" "buzz -50" "ugul -42" "damla -37"; do
  set -- $p
  i=$(lufs "$WORK/b_$1.wav"); g=$(awk -v t="$2" -v i="$i" 'BEGIN{printf "%.2f", t - i}')
  $FF -i "$WORK/b_$1.wav" -af "volume=${g}dB" "$WORK/n_$1.wav"
done
$FF -i "$WORK/n_vent.wav" -i "$WORK/n_hava.wav" -i "$WORK/n_hum.wav" -i "$WORK/n_buzz.wav" -i "$WORK/n_ugul.wav" -i "$WORK/n_damla.wav" \
  -filter_complex "amix=inputs=6:normalize=0" "$WORK/yatak_ham.wav"
# kusursuz döngü: son X saniye, ilk X saniyenin üstüne çapraz geçişle biner
$FF -i "$WORK/yatak_ham.wav" -filter_complex \
  "[0:a]asplit=3[a][b][c];[a]atrim=0:$X,afade=t=in:d=$X[h];[b]atrim=$L:$D,asetpts=PTS-STARTPTS,afade=t=out:d=$X[t];[h][t]amix=inputs=2:normalize=0[x];[c]atrim=$X:$L,asetpts=PTS-STARTPTS[g];[x][g]concat=n=2:v=0:a=1" "$WORK/yatak.wav"
norm "$WORK/yatak.wav" "$OUT/ortam_dongu.ogg" -30
echo "bitti -> $OUT"
