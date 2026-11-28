#!/usr/bin/env python3
"""opl4_lpf.py FILE FREQ [FS [FMAX]]: the samples of tb_opl4_lpf / tb_esp_audio (FS = 54748 Hz): the
level of the tone (dBFS of a full-scale sine) and the worst other component below FMAX (default FS / 2)
with its frequency (a Hann window, every bin of the FFT; every 4th bin of a DFT before missed the peaks
between them by up to 16 dB)."""
import sys
import numpy as np

x = np.array([int(l) for l in open(sys.argv[1]) if l.strip()], dtype=float)
f0 = float(sys.argv[2])
fs = float(sys.argv[3]) if len(sys.argv) > 3 else 28030303.0 / 512
fmax = float(sys.argv[4]) if len(sys.argv) > 4 else fs / 2
n = len(x)
w = np.hanning(n)
mag = np.abs(np.fft.rfft(x * w)) / (w.sum() / 2) / 32768.0
k = np.arange(len(mag))
f = k * fs / n
k0 = int(round(f0 * n / fs))
tone = mag[k0 - 2:k0 + 3].max()
other = np.where((k >= 8) & (np.abs(k - k0) >= 12) & (f < fmax), mag, 0.0)
wk = int(other.argmax())
db = lambda v: 20 * np.log10(max(v, 1e-9))
print("tone %.0f Hz %.1f dBFS, worst other %.1f dBFS at %.0f Hz (%.1f dB below the tone)" %
      (f0, db(tone), db(other[wk]), f[wk], db(tone) - db(other[wk])))
