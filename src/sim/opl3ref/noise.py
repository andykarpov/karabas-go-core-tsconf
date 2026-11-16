#!/usr/bin/env python3
"""noise.py DUMPDIR: per note of tb_fm (dump/pNN_nK.raw: int32 pairs RTL, reference at the FM rate) the
energy outside the harmonics of the note (the noise), in dB of the whole, for
  ref   ymfm at the FM rate,
  rtl   opl3_fm at the FM rate,
  drop  opl3_fm taken at 44.1 kHz as opl4_kg does (the last sample finished: FM at 44.1k * 192/171, one
        sample in 8.14 dropped),
  lin   opl3_fm resampled to 44.1 kHz with linear interpolation.
The sustained part (samples 500..2900, key on at 0) of each note; Hann window, 2048 points, harmonics +-3 bins."""
import cmath, glob, math, os, struct, sys

def fft(a):
    n = len(a)
    if n == 1:
        return a
    ev = fft(a[0::2]); od = fft(a[1::2])
    t = [cmath.exp(-2j * math.pi * k / n) * od[k] for k in range(n // 2)]
    return [ev[k] + t[k] for k in range(n // 2)] + [ev[k] - t[k] for k in range(n // 2)]

FM = 44100 * 192 / 171
NOTES = [(2, 0x2ae), (4, 0x244), (6, 0x16b)]

def noise_db(x, fs, f0):
    x = x[:2048]
    m = sum(x) / len(x)
    x = [v - m for v in x]
    if not any(abs(v) > 0.5 for v in x):
        return None
    N = len(x)
    X = [abs(v) ** 2 for v in fft([x[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / N)) for i in range(N)])[:N // 2]]
    df = fs / N
    harm = [False] * len(X)
    h = f0
    while h < fs / 2:
        k = int(round(h / df))
        for j in range(max(0, k - 3), min(len(X), k + 4)):
            harm[j] = True
        h += f0
    for j in range(4):
        harm[j] = True
    tot = sum(X)
    return 10 * math.log10(max(sum(v for v, h in zip(X, harm) if not h), 1e-20) / tot)

def resample(x, mode):
    out = []
    n = int((len(x) - 2) * 44100 / FM)
    for i in range(n):
        t = i * FM / 44100
        k = int(t)
        if mode == "drop":
            out.append(x[k])
        else:
            fr = t - k
            out.append(x[k] + (x[k + 1] - x[k]) * fr)
    return out

def main():
    rows = []
    for fn in sorted(glob.glob(os.path.join(sys.argv[1], "p*_n*.raw"))):
        d = open(fn, "rb").read()
        v = struct.unpack("<%di" % (len(d) // 4), d)
        rtl, ref = list(v[0::2]), list(v[1::2])
        k = int(fn[-5])
        blk, fnum = NOTES[k]
        f0 = fnum * 49716 / 2 ** (20 - blk) * FM / 49716    # the note at the FM rate of the OPL4
        seg = slice(500, 2900)
        r = noise_db(ref[seg], FM, f0)
        if r is None:
            continue
        a = noise_db(rtl[seg], FM, f0)
        rs = rtl[500:2900]
        b = noise_db(resample(rs, "drop"), 44100, f0)
        c = noise_db(resample(rs, "lin"), 44100, f0)
        rows.append((os.path.basename(fn), f0, r, a, b, c))
        print("%-12s f0 %6.0f Hz  noise: ref %6.1f  rtl %6.1f  drop %6.1f  lin %6.1f dB" % rows[-1])
    if rows:
        m = lambda i: sum(x[i] for x in rows) / len(rows)
        print("mean: ref %.1f  rtl %.1f  drop %.1f  lin %.1f dB" % (m(2), m(3), m(4), m(5)))


if __name__ == "__main__":
    main()
