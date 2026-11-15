#!/usr/bin/env python3
"""opl4_lpf.py FILE FREQ [FS]: the samples of tb_opl4_lpf (FS = 54748 Hz): the level of the tone
(dBFS of a full-scale sine) and the worst other component with its frequency (a Hann window, a DFT of
the bins; no numpy)."""
import math, sys

x = [int(l) for l in open(sys.argv[1]) if l.strip()]
f0 = float(sys.argv[2])
fs = float(sys.argv[3]) if len(sys.argv) > 3 else 28030303.0 / 512
n = len(x)
w = [0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)) for i in range(n)]
xs = [a * b for a, b in zip(x, w)]
def mag(k):
    re = im = 0.0
    for i, v in enumerate(xs):
        a = 2 * math.pi * k * i / n
        re += v * math.cos(a); im -= v * math.sin(a)
    return math.hypot(re, im) / (sum(w) / 2) / 32768.0
k0 = round(f0 * n / fs)
tone = max(mag(k) for k in range(k0 - 2, k0 + 3))
worst, wk = 0.0, 0
for k in range(8, n // 2, 4):          # every 4th bin: enough for the peaks of a Hann window
    if abs(k - k0) < 12:
        continue
    m = mag(k)
    if m > worst:
        worst, wk = m, k
db = lambda v: 20 * math.log10(max(v, 1e-9))
print("tone %.0f Hz %.1f dBFS, worst other %.1f dBFS at %.0f Hz (%.1f dB below the tone)" %
      (f0, db(tone), db(worst), wk * fs / n, db(tone) - db(worst)))
