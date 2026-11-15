; opl4_z80.asm: the Z80 program of tb_opl4 (sjasmplus, writes opl4_z80.bin), from sim/opl4_z80/t.asm of
; u16_tsconf_gs_v24: the chip ID, 24 voices busy, the RAM detect of the ZXM-MoonSound service program,
; a demo-style upload of 512 bytes with busy polling and its verify; here also a read of the first
; 256 bytes of the ROM (loaded by the FL loader before: byte n = n xor #A5). Results at #8000:
; +0 ID before NEW2 (06), +1 after (02), +2 reg 2 (30), +3 / +4 RAM test (AA 55), +5 upload errors,
; +8 ROM read errors, +7 = #EE at the end.
	DEVICE ZXSPECTRUM48
MOON_STAT equ 0C4h
MOON_WREG equ 7Eh
MOON_WDAT equ 7Fh
res	equ 8000h
	org 0
	di
	ld sp,0FFF0h
	in a,(MOON_STAT)	; chip ID before NEW2 (06)
	ld (res+0),a
	ld de,0400h
	call fm2_out
	ld de,0503h
	call fm2_out
	in a,(MOON_STAT)	; ID 02
	ld (res+1),a
	ld de,0210h
	call wave_out
	in a,(MOON_WDAT)	; reg2 | 20h = 30h
	ld (res+2),a
; 24 voices playing (engine busy)
	ld b,24
	ld c,0
voices:
	ld a,20h : add a,c : ld d,a : ld e,0 : call wave_out
	ld a,08h : add a,c : ld d,a : ld e,0 : call wave_out
	ld a,98h : add a,c : ld d,a : ld e,0F0h : call wave_out
	ld a,50h : add a,c : ld d,a : ld e,0 : call wave_out
	ld a,68h : add a,c : ld d,a : ld e,80h : call wave_out
	inc c
	djnz voices
; --- service RAM detect, verbatim ---
	ld c,0
	ld de,0211h
	call wave_out
	ld de,0320h
	call wave_out
	ld de,0400h
	call wave_out
	inc d
	call wave_out
	ld de,0655h
	call wave_out
	call busy
	ld e,0AAh
	call wave_out
	call busy
	nop
	nop
	nop
	ld de,0211h
	call wave_out
	ld de,0320h
	call wave_out
	ld de,0400h
	call wave_out
	inc d
	call wave_out
	inc d
	call wave_in
	ld l,a
	call wave_in
	ld (res+3),a		; AA
	ld a,l
	ld (res+4),a		; 55
; --- demo-style upload of 512 bytes with busy polling, then verify ---
	ld de,0211h
	call wave_out
	ld de,0320h
	call wave_out
	ld de,0410h
	call wave_out
	ld de,0500h
	call wave_out
	ld hl,1000h
	ld bc,512
	ld d,06h
up:	ld e,(hl)
	call wave_out
	call busy
	inc hl
	dec bc
	ld a,b
	or c
	jr nz,up
	ld de,0320h
	call wave_out
	ld de,0410h
	call wave_out
	ld de,0500h
	call wave_out
	ld hl,1000h
	ld bc,512
	ld ix,0
	ld d,06h
ver:	call wave_in
	cp (hl)
	jr z,ok
	inc ix
ok:	inc hl
	dec bc
	ld a,b
	or c
	jr nz,ver
	ld (res+5),ix		; errors
; --- the ROM from the FL loader: 0..255 = n xor #A5 ---
	ld de,0211h		; memory access on, ROM + RAM
	call wave_out
	ld de,0300h
	call wave_out
	ld de,0400h
	call wave_out
	ld de,0500h
	call wave_out
	ld bc,256
	ld ix,0
	ld l,0
	ld d,06h
rom:	call wave_in
	ld h,a
	ld a,l
	xor 0A5h
	cp h
	jr z,romok
	inc ix
romok:	inc l
	dec bc
	ld a,b
	or c
	jr nz,rom
	ld (res+8),ix
	ld de,0210h
	call wave_out
	ld a,0EEh
	ld (res+7),a
	halt

wave_out:
	ld a,d
	out (MOON_WREG),a
	nop
	nop
	ld a,e
	out (MOON_WDAT),a
	ret
wave_in:
	ld a,d
	out (MOON_WREG),a
	push de
	pop de
	in a,(MOON_WDAT)
	ret
fm2_out:
	ld a,d
	out (0C6h),a
	push bc
	pop bc
	ld a,e
	out (0C7h),a
	ret
busy:
	in a,(MOON_STAT)
	rra
	jr c,busy
	ret
	org 1000h
	; pseudo random data
	db 29,102,175,248,65,138,211,28,101,174,247,64,137,210,27,100
	db 173,246,63,136,209,26,99,172,245,62,135,208,25,98,171,244
	db 61,134,207,24,97,170,243,60,133,206,23,96,169,242,59,132
	db 205,22,95,168,241,58,131,204,21,94,167,240,57,130,203,20
	db 93,166,239,56,129,202,19,92,165,238,55,128,201,18,91,164
	db 237,54,127,200,17,90,163,236,53,126,199,16,89,162,235,52
	db 125,198,15,88,161,234,51,124,197,14,87,160,233,50,123,196
	db 13,86,159,232,49,122,195,12,85,158,231,48,121,194,11,84
	db 157,230,47,120,193,10,83,156,229,46,119,192,9,82,155,228
	db 45,118,191,8,81,154,227,44,117,190,7,80,153,226,43,116
	db 189,6,79,152,225,42,115,188,5,78,151,224,41,114,187,4
	db 77,150,223,40,113,186,3,76,149,222,39,112,185,2,75,148
	db 221,38,111,184,1,74,147,220,37,110,183,0,73,146,219,36
	db 109,182,255,72,145,218,35,108,181,254,71,144,217,34,107,180
	db 253,70,143,216,33,106,179,252,69,142,215,32,105,178,251,68
	db 141,214,31,104,177,250,67,140,213,30,103,176,249,66,139,212
	db 29,102,175,248,65,138,211,28,101,174,247,64,137,210,27,100
	db 173,246,63,136,209,26,99,172,245,62,135,208,25,98,171,244
	db 61,134,207,24,97,170,243,60,133,206,23,96,169,242,59,132
	db 205,22,95,168,241,58,131,204,21,94,167,240,57,130,203,20
	db 93,166,239,56,129,202,19,92,165,238,55,128,201,18,91,164
	db 237,54,127,200,17,90,163,236,53,126,199,16,89,162,235,52
	db 125,198,15,88,161,234,51,124,197,14,87,160,233,50,123,196
	db 13,86,159,232,49,122,195,12,85,158,231,48,121,194,11,84
	db 157,230,47,120,193,10,83,156,229,46,119,192,9,82,155,228
	db 45,118,191,8,81,154,227,44,117,190,7,80,153,226,43,116
	db 189,6,79,152,225,42,115,188,5,78,151,224,41,114,187,4
	db 77,150,223,40,113,186,3,76,149,222,39,112,185,2,75,148
	db 221,38,111,184,1,74,147,220,37,110,183,0,73,146,219,36
	db 109,182,255,72,145,218,35,108,181,254,71,144,217,34,107,180
	db 253,70,143,216,33,106,179,252,69,142,215,32,105,178,251,68
	db 141,214,31,104,177,250,67,140,213,30,103,176,249,66,139,212
	savebin "opl4_z80.bin",0,1000h+512
