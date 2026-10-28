#!/bin/bash
# Sinematik fragman kurgusu (yazısız, anlatıcısız): çekimleri keser, renk/tane verir, oyun sesleri + gerilim müziği,
# sonda logo. Kullanım: bash tools/fragman2_kurgu.sh [dikey|yatay]  -> build/fragman2/hat_dustu_fragman_<yon>.mp4
# Çekimler: tools/fragman2.sh (f2_*) ve build/tiktok/cek (rulet_masa, rulet_don).
set -e
cd /d/HatDustu
YON=${1:-dikey}
if [ "$YON" = "dikey" ]; then W=1080; H=1920; else W=1920; H=1080; fi
C=build/fragman2/cek/$YON
T=build/tiktok/cek
if [ "$YON" = "yatay" ]; then T=build/fragman2/cek/yatay; fi  # yatay rulet çekimleri de fragman2.sh ile
O=build/fragman2/kurgu_$YON
mkdir -p $O
FF="ffmpeg -y -hide_banner -loglevel error"
# sinematik görünüm: biraz kontrast, sıcak-soğuk ayrımı, kenar kararması, ince film tanesi
GORUN="eq=contrast=1.08:saturation=1.06:gamma=0.97,colorbalance=rs=0.03:bs=-0.02:rh=-0.02:bh=0.03,vignette=PI/5,noise=alls=5:allf=t"

# parca <ad> <kaynak> <başlangıç> <süre> [ek video süzgeci] [ses kazancı dB]
parca() {
  local ad=$1 src=$2 ss=$3 d=$4 ek=${5:-null} db=${6:-0}
  $FF -ss $ss -t $d -i $src -f lavfi -t $d -i anullsrc=r=48000:cl=stereo \
    -filter_complex "[0:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,fps=30,$GORUN,$ek,format=yuv420p[v];[0:a]aresample=48000,aformat=channel_layouts=stereo,volume=${db}dB[a0];[a0][1:a]amix=inputs=2:duration=first:normalize=0[a]" \
    -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 18 -c:a aac -b:a 192k -ar 48000 $O/$ad.mp4
}
# beyaz flaş (patlama / atış anı): t saniyesinde 0.12 sn
flas() { echo "drawbox=x=0:y=0:w=iw:h=ih:color=white@1:t=fill:enable='between(t,$1,$(awk "BEGIN{print $1+0.07}"))',drawbox=x=0:y=0:w=iw:h=ih:color=white@0.5:t=fill:enable='between(t,$(awk "BEGIN{print $1+0.07}"),$(awk "BEGIN{print $1+0.16}"))'"; }

parca 01 $C/f2_c4ver.avi 2.4 2.9 "fade=t=in:st=0:d=0.25"
parca 02 $C/f2_c4ver.avi 5.6 2.4
parca 03 $C/f2_c4ver.avi 8.0 3.3 "$(flas 2.5),fade=t=out:st=3.0:d=0.3"
parca 04 $T/rulet_masa.avi 5.0 2.8 "fade=t=in:st=0:d=0.15"
parca 05 $T/rulet_don.avi 10.0 2.3
parca 06 $T/rulet_don.avi 17.2 2.7 "fade=t=out:st=2.45:d=0.25"
parca 07 $C/f2_vida.avi 2.4 2.8 "fade=t=in:st=0:d=0.15"
parca 08 $C/f2_klozet.avi 2.6 3.0
parca 09 $C/f2_tunel.avi 2.6 2.8
parca 10 $C/f2_kukla.avi 4.0 3.2
parca 11 $C/f2_cikis.avi 3.3 3.9 "fade=t=out:st=3.5:d=0.4"

# son: siyah zemin, logo yavaşça belirir, altında küçük mağaza yazısı; hat düşme sesi (meşgul tonu)
LW=$(( W * 78 / 100 ))
$FF -f lavfi -i color=c=0x0b0e0f:s=${W}x${H}:d=3.4:r=30 -loop 1 -t 3.4 -framerate 30 -i build/fragman2/logo_seffaf.png \
  -f lavfi -i "sine=f=425:d=3.4,volume=0.25" \
  -filter_complex "[1:v]scale=$LW:-1,format=rgba,fade=t=in:st=0.25:d=0.5:alpha=1[l];[0:v][l]overlay=(W-w)/2:(H-h)/2-40,drawtext=fontfile=build/fragman/font/russo.ttf:text='App Store  ·  Google Play':fontsize=$(( W / 26 )):fontcolor=0xd9d6cf:x=(w-tw)/2:y=h/2+$(( W / 8 )):alpha='if(lt(t,1.0),0,min(1,(t-1.0)/0.4))',fade=t=out:st=3.0:d=0.4,format=yuv420p[v];[2:a]volume='if(lt(mod(t,0.6),0.3),1,0)':eval=frame,afade=t=out:st=2.6:d=0.6,aformat=channel_layouts=stereo,aresample=48000[a]" \
  -map "[v]" -map "[a]" -c:v libx264 -preset medium -crf 18 -c:a aac -b:a 192k -ar 48000 -t 3.4 $O/12.mp4

(cd $O && ls [0-9][0-9].mp4 | sed "s/^/file '/; s/\$/'/") > $O/liste.txt  # yollar liste dosyasına göre (ffmpeg /d/ yolunu açamaz)
$FF -f concat -safe 0 -i $O/liste.txt -c copy $O/govde.mp4
SURE=$(ffprobe -v error -show_entries format=duration -of csv=p=0 $O/govde.mp4)
# müzik: gerilim, oyun seslerinin altında; sonda kısılır
$FF -i $O/govde.mp4 -i assets/muzik/gerilim.ogg \
  -filter_complex "[1:a]atrim=0:$SURE,volume=0.32,afade=t=in:d=1.0,afade=t=out:st=$(awk "BEGIN{print $SURE-3.6}"):d=1.2,aformat=channel_layouts=stereo,aresample=48000[m];[0:a][m]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]" \
  -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -movflags +faststart build/fragman2/hat_dustu_fragman_$YON.mp4
echo "tamam: build/fragman2/hat_dustu_fragman_$YON.mp4 ($SURE sn)"
