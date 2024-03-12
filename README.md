# Karabas Go TS-Conf Core

A famous ZX-Evolution TS-Conf core ported to the Karabas Go hardware.

## What's done:

- Real floppy support (based on Firefly FDC hdl sources)
- Real CF card support (Nemo IDE)
- VDAC2 (FT812)
- RGB 8-8-8
- Usb Keyboard and mouse
- 2x Joysticks support (selectable via OSD)
- Turbosound + FM
- General Sound (2 MB)
- SAA
- Soundrive (4x covox)
- ZiFi (ESP8266)
- RS232 over USB (ZXEvo + ZiFi standards supported)
- RTC (with read/write support)
- OSD Menu by Win+ESC to change some settings

## TODO

- Rewrite/fix a keyboard emulation (add a 16 bytes buffer and full PS/2 sequences to emulate ZX Evolution standard)
