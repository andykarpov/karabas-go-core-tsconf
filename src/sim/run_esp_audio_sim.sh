#!/bin/bash
# tb_esp_audio (iverilog, about a minute): the ESP32 audio of the Mini G, I2S 44.1 kHz of the ESP clock
# -> i2s_rx -> audio_interp -> audio_lpf, taken at the PCM5102 rate (54.7 kHz) and at the HDMI 48 kHz;
# opl4/opl4_lpf.py prints the tone and the worst other component. The script wants every frame received
# ("0 errors") and the low-pass mode (2) at least the given dB below the tone.
# Usage: src/sim/run_esp_audio_sim.sh
set -e
SIM="$(cd "$(dirname "$0")" && pwd)"
R="$(dirname "$SIM")/rtl"
OUT="$SIM/build/esp_audio"
mkdir -p "$OUT"
cd "$OUT"
# freq, output divisor, the dB wanted in mode 2 below 20 kHz (the measured 42.5 / 32.2 / 40.9 / 15.1: at 48 kHz
# the image of 15 kHz falls to 18.9 kHz, the 1-pole stages take little off it)
for P in "5000 512 40" "15000 512 30" "5000 584 38" "15000 584 13"; do
	set -- $P
	FS=$(python3 -c "print(28030303.0 / $2)")
	for M in 0 1 2; do
		iverilog -g2012 -P tb_esp_audio.FREQ=$1 -P tb_esp_audio.MODE=$M -P tb_esp_audio.OUT_DIV=$2 -o tb_esp_audio \
			"$SIM/tb_esp_audio.v" "$R/adc/i2s_rx.v" "$R/sound/audio_lpf.v"
		vvp -n tb_esp_audio > tb_esp_audio.log
		grep -q "tb_esp_audio: 0 errors" tb_esp_audio.log || { cat tb_esp_audio.log; echo "tb_esp_audio FAILED"; exit 1; }
		L=$(python3 "$SIM/opl4/opl4_lpf.py" esp_audio.txt $1 $FS 20000)
		echo "tb_esp_audio $([ $2 = 512 ] && echo PCM5102 || echo HDMI) mode $M: $L"
	done
	python3 -c "import sys; sys.exit(0 if float('$L'.split('(')[1].split(' dB')[0]) >= $3 else 1)" || \
		{ echo "tb_esp_audio FAILED: mode 2 at $1 Hz under $3 dB"; exit 1; }
done
echo "ESP AUDIO SIMULATION PASSED"
