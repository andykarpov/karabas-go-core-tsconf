#!/usr/bin/env python3
"""patches.py TRD...: the OPL instruments of the MoonBlaster 1.4 songs ("MBMS", MSX-AUDIO) on TR-DOS disks:
from offset 8 of a song, 11 bytes each (mod 20, car 20, mod 40, car 40, mod 60, car 60, mod 80, car 80,
mod E0, car E0, C0), up to 16, without repeats. Prints one patch per line (tb_fm), the source on stderr."""
import sys

seen = []
for path in sys.argv[1:]:
    d = open(path, 'rb').read()
    for i in range(128):
        e = d[i * 16:i * 16 + 16]
        if e[0] == 0:
            break
        off = (e[15] * 16 + e[14]) * 256
        body = d[off:off + e[13] * 256]
        if body[:4] != b'MBMS':
            continue
        name = e[0:8].decode('latin1').strip()
        for k in range(16):
            p = body[8 + k * 11:8 + k * 11 + 11]
            if len(p) < 11 or p in seen:
                continue
            seen.append(p)
            print(" ".join("%02x" % b for b in p))
            print("%s %s #%d: %s" % (path.split('/')[-1], name, k, p.hex(' ')), file=sys.stderr)
