#!/usr/bin/env python3
"""gen.py MODE SEED: a script for tb_ref (W off data / R off / S samples / # marker), one part of the OPL4
wave engine at a time, so that a mismatch names the part:
  plain  one note at a time, a flat envelope (AR 15, no decay, RR 15): the wave, the format, the loop, the pitch
  env    one note at a time, random AR / D1R / DL / D2R / RR / RC, key off in the decay or the sustain
  lfo    one note at a time with LFO / VIB / AM
  rev    pseudo reverb and damp
  tl     TL changes while a note sounds, with and without level direct
  multi  24 notes at once, notes start and stop
  rand   all of it at random (after sim/opl4/gen.py of u16_tsconf_gs_v24)
The RAM waves (tones 384..391): random formats, lengths, loops, odd base addresses."""
import random, sys

mode = sys.argv[1]
seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
rnd = random.Random(seed * 101 + sum(map(ord, mode)))
out = []
def w(off, d): out.append("W %d %02x" % (off, d & 0xff))
def pw(r, d): w(4, r); w(5, d)
def rd(off): out.append("R %d" % off)
def S(n): out.append("S %d" % n)
def mark(t): out.append("# " + t)

w(2, 0x05); w(3, 0x03)     # NEW + NEW2
pw(0x02, 0x10)             # header bank 4: tones 384.. in RAM at #200000

def setaddr(a):
    pw(3, a >> 16); pw(4, a >> 8); pw(5, a)

nwaves = 8
headers, blobs = [], []
addr = 0x201000
for k in range(nwaves):
    fmt = rnd.choice([0, 1, 2])
    length = rnd.randint(16, 2000)
    loop = rnd.randint(0, length - 1)
    nbytes = length if fmt == 0 else length * 2 if fmt == 2 else (length + 1) // 2 * 3
    if rnd.random() < 0.5: addr += 1
    base = addr
    # a smooth wave (sum of two sines) with some noise: like a real sample, not white noise
    import math
    vals = [int(12000 * math.sin(2 * math.pi * i * rnd.choice([1, 2, 3]) / max(length, 1)) +
                6000 * math.sin(2 * math.pi * i * 7 / max(length, 1)) + rnd.randint(-300, 300)) for i in range(length + 2)]
    if fmt == 0:
        blob = bytes(((v >> 8) & 0xff) for v in vals[:nbytes])
    elif fmt == 2:
        blob = b"".join(bytes([(v >> 8) & 0xff, v & 0xff]) for v in vals[:length])
    else:
        bb = []
        for i in range(0, length, 2):
            a = (vals[i] >> 4) & 0xfff; b = (vals[i + 1] >> 4) & 0xfff
            bb += [a >> 4, ((b & 0xf) << 4) | (a & 0xf), b >> 4]
        blob = bytes(bb)
    blob += bytes(rnd.getrandbits(8) for _ in range(4))
    blobs.append((base, blob))
    addr += len(blob) + rnd.randint(0, 9)
    endn = (0x10000 - length) & 0xffff
    hdr = [(fmt << 6) | ((base >> 16) & 0x3f), (base >> 8) & 0xff, base & 0xff,
           loop >> 8, loop & 0xff, endn >> 8, endn & 0xff,
           0x00, 0xf0, 0x00, 0x0f, 0x00]
    headers.append(hdr)

pw(0x02, 0x11)             # memory access
setaddr(0x200000)
for h in headers:
    for b in h: pw(6, b)
for base, blob in blobs:
    setaddr(base)
    for b in blob: pw(6, b)
pw(0x02, 0x10)

def note(ch, wav, oct, fn, tl=0x00, key=0x80, regs=None):
    pw(0x20 + ch, ((fn & 0x7f) << 1) | (wav >> 8))
    pw(0x38 + ch, ((oct & 0xf) << 4) | (fn >> 7))
    pw(0x08 + ch, wav & 0xff)
    pw(0x50 + ch, tl)
    for r, v in (regs or {}).items():
        pw(r + ch, v)
    pw(0x68 + ch, key)

def rwav():
    return rnd.choice([rnd.randrange(384), 384 + rnd.randrange(nwaves)])

def flat():
    return {0x80: 0x00, 0x98: 0xf0, 0xb0: 0x00, 0xc8: 0x0f, 0xe0: 0x00}

if mode == "multi":
    on = set()
    for b in range(120):
        for e in range(rnd.randint(1, 4)):
            ch = rnd.randrange(24)
            if ch in on and rnd.random() < 0.4:
                pw(0x68 + ch, 0x00); on.discard(ch)
            else:
                note(ch, rwav(), rnd.randint(-2, 2), rnd.getrandbits(10), rnd.getrandbits(7) << 1, 0x80 | rnd.getrandbits(4))
                on.add(ch)
        S(rnd.choice([10, 50, 200, 500]))
elif mode == "rand":
    for b in range(150):
        for e in range(rnd.randint(1, 8)):
            ch = rnd.randrange(24); t = rnd.random()
            if t < 0.3:
                regs = {r: rnd.getrandbits(8) for r in (0x80, 0x98, 0xb0, 0xc8, 0xe0) if rnd.random() < 0.5}
                note(ch, rwav(), rnd.choice([rnd.randint(-3, 3), rnd.randint(-8, 7)]), rnd.getrandbits(10),
                     rnd.getrandbits(8), 0x80 | rnd.getrandbits(7), regs)
            elif t < 0.45: pw(0x68 + ch, rnd.getrandbits(7))
            elif t < 0.7:
                r = rnd.choice([0x20, 0x38, 0x50, 0x80, 0x98, 0xb0, 0xc8, 0xe0])
                pw(r + ch, rnd.getrandbits(8) & (0xfe if r == 0x20 else 0xff))
            elif t < 0.75: pw(0xf9, rnd.getrandbits(6))
            else: pw(0x50 + ch, rnd.getrandbits(8))
        S(rnd.choice([1, 2, 5, 20, 100, 300, 1000]))
else:
    for k in range(24):
        ch = rnd.randrange(24)
        wav = rwav(); oct = rnd.randint(-3, 3); fn = rnd.getrandbits(10)
        regs = flat()
        if mode == "env":
            regs = {0x80: 0x00, 0x98: rnd.getrandbits(8), 0xb0: rnd.getrandbits(8), 0xc8: rnd.getrandbits(8), 0xe0: 0x00}
        elif mode == "lfo":
            regs.update({0x80: rnd.getrandbits(6), 0xe0: rnd.getrandbits(3)})
        tl = 0x00 if mode != "tl" else rnd.getrandbits(7) << 1
        key = 0x80
        if mode == "rev":
            key = 0x80 | (rnd.getrandbits(1) << 3)            # pseudo reverb is bit 3 of 0x38 on the chip
            pw(0x38 + ch, 0)                                   # (set below with the octave)
        mark("%s %d: ch %d wave %d oct %d fn %d regs %s tl %02x" % (mode, k, ch, wav, oct, fn,
             " ".join("%02x=%02x" % (r, v) for r, v in regs.items()), tl))
        note(ch, wav, oct, fn, tl, key, regs)
        if mode == "rev" and rnd.random() < 0.7:
            pw(0x38 + ch, ((oct & 0xf) << 4) | 0x08 | (fn >> 7))  # pseudo reverb on
        S(rnd.choice([300, 1000, 3000]))
        if mode == "tl":
            for i in range(4):
                pw(0x50 + ch, rnd.getrandbits(8)); S(rnd.choice([50, 300]))
        if mode == "rev" and rnd.random() < 0.5:
            pw(0x68 + ch, 0x40)                                # damp
        else:
            pw(0x68 + ch, 0x00)                                # key off
        S(rnd.choice([300, 1000, 3000]))
print("\n".join(out))
