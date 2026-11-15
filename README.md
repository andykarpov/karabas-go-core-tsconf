# Karabas Go TS-Conf Core

A famous ZX-Evolution TS-Conf core ported to the Karabas Go hardware.

## What's done:

- Real floppy support on Go (the VG93 model of the Profi core)
- Real CF card support (Nemo IDE)
- VDAC2 (FT812)
- VDAC32 (FT812 + ESP32-S3 on Mini rev.G)
- RGB 8-8-8
- USB Keyboard (with zx-evo ps/2 keybuffer emulation) 
- USB mouse
- 2x Joysticks support (selectable via OSD)
- Turbosound (2x AY / YM; the FM part of TS-FM is removed)
- OPL4 (ZXM-MoonSound: FM + wavetable, ports #C4..#C7 / #7E / #7F, 2 MB sample RAM); the YRW801 ROM is loaded from the SD card: put it as `/tsconf/yrw801.rom`
- General Sound (2 MB)
- SAA1099 and OPL2 (YM3812) are removed to fit the OPL4
- GS / OPL4 output filter in the OSD (off / linear / linear + low-pass)
- MIDI (Dream SAM2695)
- Soundrive (4x covox)
- ZiFi (ESP8266)
- RS232 over USB (ZXEvo + ZiFi standards supported)
- RTC (with read/write support)
- OSD Menu by Win+ESC to change some settings

