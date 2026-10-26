#!/usr/bin/env bash
# Rus Ruleti sesleri: gerçek altıpatar kayıtlarından katmanlı karışım.
# Kullanım: tools/rulet_ses_uret.sh <kaynak_klasoru> <cikti_klasoru>
#   kaynak_klasoru (hepsi CC0, ayrıntı assets/ses/LISANS.txt):
#     "Prepared SFX Library/Smith & Wesson 642/V_27P.wav" (yakın), V_22P.wav (orta mesafe)
#       — The Free Firearm Sound Library, opengameart.org/content/the-free-firearm-sound-library
#     gun_reload_lock_or_click_sound.mp3 — pauliuw, opengameart.org/content/gun-reload-lock-or-click-sound
#     equipment_clicks3.wav — LFA, opengameart.org/content/equipment-clicks-iii
#     eski/horoz.ogg, eski/bos_tetik.ogg — önceki sürümler ("100 CC0 SFX", rubberduck)
# Çıktı: tabanca.ogg (yakın: patlama + horoz düşüşü + gövde + kısa oda yankısı + çok hafif çınlama),
#        tabanca_uzak.ogg (uzak/izleyen: boğuk, yankılı), bos_tetik.ogg, horoz.ogg, tambur.ogg.
# Hepsinin tepesi -1 dBFS (kırpılma yok).
set -e
K="$1"; O="$2"
SW="$K/Prepared SFX Library/Smith & Wesson 642"
TMP="$(mktemp -d)"
SR=48000

# tepe -1 dBFS ve ogg
bitir() {
	local in="$1" out="$2"
	local peak; peak=$(ffmpeg -v info -i "$in" -af astats=measure_perchannel=none -f null - 2>&1 | grep -oE "Peak level dB: [-0-9.]+" | tail -1 | grep -oE "[-0-9.]+$")
	local g; g=$(awk "BEGIN{print -1.4 - ($peak)}")
	ffmpeg -v error -y -i "$in" -af "volume=${g}dB,alimiter=limit=0.85:level=false:attack=0.5:release=20" -ar $SR -c:a libvorbis -q:a 6 "$O/$out"
	local son; son=$(ffmpeg -v info -i "$O/$out" -af volumedetect -f null - 2>&1 | grep -oE "max_volume: [-0-9.]+ dB")
	echo "$out  (ham tepe $peak dB, kazanç $g dB, son $son)"
}

ST="aformat=sample_fmts=fltp:sample_rates=$SR:channel_layouts=stereo"

# 1) YAKIN ATIŞ (2,2 sn): 25 ms önce horozun düşüş tıkı, sonra .38 patlaması; altında orta mesafe kaydının
#    doğal kuyruğu, alçak geçiren "gövde" (göğse vuran basınç), hücre/masa odası ilk yansımaları
#    (17-83 ms) ve kulak çınlaması hissi için iki yakın sinüs (vuruşlu), çok kısık.
ffmpeg -v error -y \
	-i "$SW/V_27P.wav" -i "$SW/V_22P.wav" -i "$K/eski/bos_tetik.ogg" \
	-filter_complex "
	[0:a]atrim=0.79:1.9,asetpts=PTS-STARTPTS,$ST,highpass=f=45,asplit=4[n1][n2][n3][n4];
	[n1]adelay=25:all=1[blast];
	[n2]lowpass=f=170,volume=7dB,afade=t=out:st=0.05:d=0.3,adelay=25:all=1[body];
	[n3]aecho=0.85:0.75:17|29|43|61|83:0.42|0.33|0.26|0.19|0.13,lowpass=f=5200,volume=-5dB,adelay=25:all=1[room];
	[n4]highpass=f=1200,aecho=0.8:0.5:11|19:0.3|0.2,volume=-12dB,afade=t=out:st=0.1:d=0.25,adelay=27:all=1[crack];
	[1:a]atrim=0.66:2.6,asetpts=PTS-STARTPTS,$ST,lowpass=f=4500,highpass=f=70,volume=-17dB,adelay=32:all=1[tail];
	[2:a]$ST,highpass=f=900,volume=-13dB[hammer];
	aevalsrc='0.012*sin(2*PI*3710*t)*exp(-1.7*t)|0.012*sin(2*PI*3737*t)*exp(-1.7*t)':s=$SR:d=2.1,afade=t=in:d=0.08,adelay=60:all=1[ring];
	[blast][body][room][crack][tail][hammer][ring]amix=inputs=7:normalize=0:duration=longest,alimiter=limit=0.2:attack=0.1:release=40:level=false,atrim=0:2.2,afade=t=out:st=1.7:d=0.5[m]" \
	-map "[m]" -c:a pcm_f32le "$TMP/tabanca.wav"
bitir "$TMP/tabanca.wav" tabanca.ogg

# 2) UZAK ATIŞ (2,6 sn): orta mesafe kaydı; boğuk (alçak geçiren), daha uzun koridor yankısı. Oyunda yakın
#    sesle birlikte 3B çalınır: yakındaysan yakın baskın, uzaklaştıkça yalnız bu kalır.
ffmpeg -v error -y -i "$SW/V_22P.wav" \
	-filter_complex "
	[0:a]atrim=0.62:3.0,asetpts=PTS-STARTPTS,$ST,highpass=f=70,lowpass=f=2400,asplit=2[d][r];
	[r]aecho=0.8:0.8:60|115|180|260:0.4|0.3|0.22|0.14,lowpass=f=1800,volume=-4dB[rv];
	[d][rv]amix=inputs=2:normalize=0:duration=longest,acompressor=threshold=-24dB:ratio=3:attack=3:release=200:makeup=1,atrim=0:2.6,afade=t=out:st=1.9:d=0.7[m]" \
	-map "[m]" -c:a pcm_f32le "$TMP/uzak.wav"
bitir "$TMP/uzak.wav" tabanca_uzak.ogg

# 3) BOŞ TETİK: eski tık + gerçek kilit/tetik tıkı (keskin) + küçük metal gövde ve dar oda yansıması
ffmpeg -v error -y -i "$K/eski/bos_tetik.ogg" -i "$K/gun_reload_lock_or_click_sound.mp3" \
	-filter_complex "
	[0:a]$ST,volume=-3dB[a];
	[1:a]atrim=0:0.14,asetpts=PTS-STARTPTS,$ST,highpass=f=500,volume=-4dB,asplit=2[b][c];
	[c]lowpass=f=600,volume=2dB,afade=t=out:st=0.02:d=0.08[thunk];
	[a][b][thunk]amix=inputs=3:normalize=0:duration=longest,aecho=0.8:0.55:9|17|31:0.32|0.22|0.12,atrim=0:0.45,afade=t=out:st=0.3:d=0.15[m]" \
	-map "[m]" -c:a pcm_f32le "$TMP/bos.wav"
bitir "$TMP/bos.wav" bos_tetik.ogg

# 4) HOROZ (tetiğin geriye çekilmesi): eski horoz + gerçek mekanizma tıkı (sürgü kurma kaydının ilk
#    tıkı) + kısa oda yansıması
ffmpeg -v error -y -i "$K/eski/horoz.ogg" -i "$K/equipment_clicks3.wav" \
	-filter_complex "
	[0:a]$ST[a];
	[1:a]atrim=0.17:0.47,asetpts=PTS-STARTPTS,$ST,highpass=f=300,volume=-9dB,adelay=40:all=1[b];
	[a][b]amix=inputs=2:normalize=0:duration=longest,aecho=0.8:0.5:13|27:0.25|0.15,atrim=0:0.6,afade=t=out:st=0.45:d=0.15[m]" \
	-map "[m]" -c:a pcm_f32le "$TMP/horoz.wav"
bitir "$TMP/horoz.wav" horoz.ogg

# 5) TAMBUR ÇEVİRME (1,4 sn): mandal tıkları gittikçe seyrelir (tambur yavaşlar), altında hafif metal
#    vınlama; sonda tamburun yerine oturduğu daha dolgun bir "klak".
args=(); filt=""; labels=""; i=0
t=0.0; iv=0.026
while awk "BEGIN{exit !($t < 1.18)}"; do
	d=$(awk "BEGIN{printf \"%d\", $t*1000}")
	v=$(awk -v s=$i "BEGIN{srand(s*7+3); printf \"%.1f\", -1 - $t*5 + (rand()*3-1.5)}")
	p=$(awk -v s=$i "BEGIN{srand(s*13+1); printf \"%.3f\", 1.25 + rand()*0.18}")
	args+=(-i "$K/gun_reload_lock_or_click_sound.mp3")
	filt+="[$i:a]atrim=0:0.035,asetpts=PTS-STARTPTS,$ST,asetrate=$SR*$p,aresample=$SR,highpass=f=700,volume=${v}dB,adelay=$d:all=1[t$i];"
	labels+="[t$i]"
	i=$((i + 1))
	t=$(awk "BEGIN{print $t + $iv}"); iv=$(awk "BEGIN{print $iv * 1.14}")
done
args+=(-i "$K/eski/bos_tetik.ogg")
filt+="[$i:a]$ST,volume=-4dB,adelay=$(awk "BEGIN{printf \"%d\", $t*1000}"):all=1[t$i];"
labels+="[t$i]"; i=$((i + 1))
filt+="anoisesrc=d=1.3:c=pink:a=0.05:r=$SR,bandpass=f=2600:width_type=q:w=2,afade=t=in:d=0.05,afade=t=out:st=0.1:d=1.1,aformat=channel_layouts=stereo[w];"
labels+="[w]"; i=$((i + 1))
filt+="${labels}amix=inputs=$i:normalize=0:duration=longest,aecho=0.8:0.4:15|29:0.2|0.12,atrim=0:1.55,afade=t=out:st=1.4:d=0.15[m]"
ffmpeg -v error -y "${args[@]}" -filter_complex "$filt" -map "[m]" -c:a pcm_f32le "$TMP/tambur.wav"
bitir "$TMP/tambur.wav" tambur.ogg

rm -rf "$TMP"
