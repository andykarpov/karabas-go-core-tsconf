#!/usr/bin/env python3
"""kgnoise.py DUMPDIR: the noise outside the harmonics (noise.py) of the opl4_kg outputs of tb_kg
(dump/kg_pNN_nK_iI.raw, int16 at 44.1 kHz), without (i0) and with (i1) the FM interpolation, per note."""
import glob, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noise import noise_db, FM, NOTES

rows = []
for f0n in sorted(glob.glob(os.path.join(sys.argv[1], "kg_p*_n*_i0.raw"))):
    f1n = f0n[:-6] + "i1.raw"
    if not os.path.exists(f1n):
        continue
    k = int(f0n[-8])
    blk, fnum = NOTES[k]
    f0 = fnum * FM / 2 ** (20 - blk)
    r = []
    for fn in (f0n, f1n):
        d = open(fn, "rb").read()
        x = list(struct.unpack("<%dh" % (len(d) // 2), d))
        r.append(noise_db(x[400:2448], 44100, f0))
    if r[0] is None:
        continue
    rows.append(r)
    print("%-14s f0 %6.0f Hz  noise: interp off %6.1f  on %6.1f dB" % (os.path.basename(f0n)[3:-7], f0, r[0], r[1]))
if rows:
    print("mean: off %.1f  on %.1f dB" % (sum(r[0] for r in rows) / len(rows), sum(r[1] for r in rows) / len(rows)))
