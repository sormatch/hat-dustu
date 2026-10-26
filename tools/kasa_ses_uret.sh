#!/usr/bin/env bash
# Kullanım: tools/kasa_ses_uret.sh <kenney_klasoru> <eski_kasa_sesleri> <cikti_klasoru>
#   kenney_klasoru: Casino Audio, Interface Sounds, UI Audio, Impact Sounds zip'lerinin açıldığı klasör (kenney.nl, CC0)
#   eski_kasa_sesleri: ilk sürüm kasa sesleri (taban katman; yedeği build/kasa_ses_eski/)
set -e
K="$1"; E="$2"; O="$3"
CA="$K/kenney_casino-audio/Audio"; IS="$K/kenney_interface-sounds/Audio"
UA="$K/kenney_ui-audio/Audio"; IM="$K/kenney_impact-sounds/Audio"
TMP="$(mktemp -d)"

# mix <cikti.ogg> <uzunluk_sn> <son_filtre> "dosya|gecikme_ms|kazanc_db|perde" ...
mix() {
	local out="$1" len="$2" post="$3"; shift 3
	local args=() filt="" i=0 labels=""
	for spec in "$@"; do
		IFS='|' read -r f d v p <<< "$spec"
		p="${p:-1.0}"
		args+=(-i "$f")
		filt+="[$i:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo,asetrate=44100*$p,aresample=44100,volume=${v}dB,adelay=${d}:all=1[a$i];"
		labels+="[a$i]"
		i=$((i + 1))
	done
	filt+="${labels}amix=inputs=$i:normalize=0:duration=longest"
	[ -n "$post" ] && filt+=",$post"
	filt+=",atrim=0:$len,afade=t=out:st=$(awk "BEGIN{print $len*0.82}"):d=$(awk "BEGIN{print $len*0.18}")[m]"
	ffmpeg -v error -y "${args[@]}" -filter_complex "$filt" -map "[m]" "$TMP/m.wav"
	# tepe seviyesi -1 dB'ye
	local peak; peak=$(ffmpeg -v info -i "$TMP/m.wav" -af volumedetect -f null - 2>&1 | grep -oE "max_volume: [-0-9.]+" | grep -oE "[-0-9.]+$")
	local g; g=$(awk "BEGIN{print -1.0 - ($peak)}")
	ffmpeg -v error -y -i "$TMP/m.wav" -af "volume=${g}dB" -c:a libvorbis -q:a 6 "$O/$out"
	echo "$out  (tepe $peak dB, +$g)"
}

HALL="aecho=0.85:0.6:70|140|230:0.28|0.18|0.1"

# 1) sallanma: zincir şıngırtısı + gittikçe sertleşen metal vuruşlar
mix sallanma.ogg 0.95 "" \
	"$E/sallanma.ogg|0|0" "$CA/dice-shake-2.ogg|0|-4|0.9" "$CA/chips-handle-3.ogg|90|-9" \
	"$IM/impactMetal_light_000.ogg|0|-9" "$IM/impactMetal_medium_001.ogg|170|-7" \
	"$IM/impactMetal_medium_003.ogg|330|-5" "$IM/impactMetal_heavy_000.ogg|470|-3" "$IM/impactMetal_heavy_003.ogg|560|-2"

# 2) kilit kopar: ağır metal + çan rezonansı + düşen zincir halkaları
mix kilit.ogg 1.3 "$HALL" \
	"$E/kilit.ogg|0|0" "$IM/impactMetal_heavy_001.ogg|0|0" "$IM/impactPlate_heavy_001.ogg|0|-4" \
	"$IM/impactBell_heavy_003.ogg|10|-7|1.2" "$CA/chips-collide-1.ogg|60|-6" "$CA/chips-collide-3.ogg|190|-9"

# 3) kapak açılır: gövde vuruşu + yükselen hava + parıltı
mix acilis.ogg 1.6 "$HALL" \
	"$E/acilis.ogg|0|0" "$IM/impactPlate_heavy_004.ogg|0|-3" "$IS/maximize_008.ogg|20|-4" \
	"$IM/impactBell_heavy_000.ogg|50|-11|0.8" "$IS/glass_002.ogg|220|-10"

# 4) şerit fırlar: kart destesi yelpazesi
mix serit.ogg 1.2 "" \
	"$CA/card-fan-2.ogg|0|-1" "$CA/card-shove-2.ogg|0|-4" "$IS/maximize_004.ogg|0|-10|0.9"

# 5) tık çeşitleri (aynı ses makineli tüfek gibi duyulmasın)
mix tik_1.ogg 0.09 "" "$E/tik.ogg|0|-1" "$CA/chip-lay-1.ogg|0|-7|1.15"
mix tik_2.ogg 0.09 "" "$E/tik.ogg|0|-1|1.05" "$UA/click3.ogg|0|-8"
mix tik_3.ogg 0.09 "" "$E/tik.ogg|0|-1|0.95" "$IS/tick_002.ogg|0|-6"

# 6) kazanan kart döner
mix kart_cevir.ogg 0.8 "" \
	"$CA/card-slide-1.ogg|0|-3" "$CA/card-place-3.ogg|100|0" "$IS/glass_001.ogg|110|-12"

# 7) duruş vuruşları (nadirliğe göre büyür)
mix vurus_siradan.ogg 0.75 "" \
	"$E/vurus_siradan.ogg|0|0" "$CA/card-place-1.ogg|0|-4" "$IS/confirmation_001.ogg|40|-9"
mix vurus_nadir.ogg 1.5 "" \
	"$E/vurus_nadir.ogg|0|0" "$IM/impactBell_heavy_004.ogg|0|-9|1.3" "$IS/confirmation_002.ogg|30|-6" "$CA/chips-stack-1.ogg|80|-8"
mix vurus_epik.ogg 2.0 "$HALL" \
	"$E/vurus_epik.ogg|0|0" "$IM/impactBell_heavy_002.ogg|0|-5" "$IS/maximize_006.ogg|0|-6" \
	"$CA/chips-stack-3.ogg|120|-6" "$CA/chips-stack-5.ogg|260|-8" "$IS/glass_004.ogg|300|-10"
mix vurus_efsane.ogg 3.3 "$HALL" \
	"$E/vurus_efsane.ogg|0|0" "$IS/bong_001.ogg|0|-3" "$IM/impactBell_heavy_001.ogg|0|-4|0.85" \
	"$IM/impactPlate_heavy_000.ogg|0|-4" "$IS/maximize_009.ogg|0|-6" "$IS/glass_003.ogg|300|-9" \
	"$CA/chips-stack-3.ogg|250|-6" "$CA/chips-stack-1.ogg|420|-7" "$CA/chips-stack-6.ogg|560|-7" \
	"$CA/chips-collide-2.ogg|700|-8" "$CA/chips-stack-2.ogg|860|-9" "$CA/chips-stack-4.ogg|1010|-10"

# 8) elmas iadesi ve mağaza satın alma
mix elmas.ogg 1.0 "" \
	"$CA/chips-stack-3.ogg|0|-2" "$CA/chips-stack-4.ogg|120|-3" "$CA/chips-collide-1.ogg|240|-5" "$IS/glass_005.ogg|0|-9"
mix satin_al.ogg 0.9 "" \
	"$CA/chips-stack-1.ogg|0|-2" "$CA/chips-stack-4.ogg|110|-4" "$IS/confirmation_003.ogg|60|-6"

# 9) kasa yere iner: ağır metal gümbürtü
mix inis.ogg 0.9 "$HALL" "$IM/impactPlate_heavy_002.ogg|0|0|0.8" "$IM/impactMetal_heavy_002.ogg|0|-3|0.85" "$IM/impactWood_heavy_001.ogg|0|-4|0.7" "$CA/chips-collide-4.ogg|60|-10"

rm -rf "$TMP"
