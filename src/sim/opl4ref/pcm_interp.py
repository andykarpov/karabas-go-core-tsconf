#!/usr/bin/env python3
"""pcm_interp.py SRC DST: a copy of ymfm_pcm.cpp with the linear interpolation of openMSX (YMF278.cc) when the
global ymfm_interp is 1: sample = s0 + ((s1 - s0) * frac) >> 16, s0 at pos, s1 at the next position (past the
end: the loop, in 16 bits as the chip), frac = the low 16 bits of the position. The reference of opl4.v with
interp = 1; with 0 it is ymfm as it is. The clone of ymfm itself is not changed."""
import sys
src = open(sys.argv[1]).read()
old_decl = "int16_t pcm_channel::fetch_sample() const\n{\n\tuint32_t addr = m_baseaddr;\n\tuint32_t pos = m_curpos >> 16;\n"
assert old_decl in src
src = src.replace(old_decl,
    "int16_t pcm_channel::fetch_sample() const\n{\n\treturn fetch_sample_at(m_curpos >> 16);\n}\n\n"
    "int16_t pcm_channel::fetch_sample_at(uint32_t pos) const\n{\n\tuint32_t addr = m_baseaddr;\n")
old_use = "\tint16_t sample = fetch_sample();\n"
assert old_use in src
src = src.replace(old_use,
    "\tint16_t sample = fetch_sample();\n"
    "\tif (ymfm_interp)\n\t{\n"
    "\t\tuint16_t pos = m_curpos >> 16, p1 = pos + 1;\n"
    "\t\tif (p1 >= uint16_t(m_endpos >> 16))\n\t\t\tp1 = uint16_t(p1 + uint16_t((m_looppos - m_endpos) >> 16));\n"
    "\t\tint32_t s0 = sample, s1 = fetch_sample_at(p1), frac = m_curpos & 0xffff;\n"
    "\t\tsample = int16_t(s0 + (((s1 - s0) * int64_t(frac)) >> 16));\n\t}\n")
src = "int ymfm_interp = 0;   // pcm_interp.py\n" + src
open(sys.argv[2], "w").write(src)
