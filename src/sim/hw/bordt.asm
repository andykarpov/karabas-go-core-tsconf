; bordt.asm (sjasmplus): a hardware test of the border on the even ports (A0 = 0, build 26112002), run from
; TR-DOS: bordt.trd, "boot". The CPU at 3.5 MHz, synced to the INT by HALT; every frame 9 bands of the
; border (about 32 lines each, seen on the left / right of the paper), top to bottom:
;   1 red      OUT (#FE)          the reference
;   2 green    OUT (C) C = #06    the case of No More Intelligence 3
;   3 cyan     OUT (C) C = #F6
;   4 magenta  OUT (C) C = #00
;   5 black    OUT (#FE) black, then white to #C4 (OPL4)    \
;   6 black    the same with #C6 (OPL4)                       | white here = the port
;   7 black    the same with #7E (OPL4)                       | is taken as the border
;   8 black    the same with #FB (odd, Covox)                /
;   9 blue     OUT (#FE)
; The writes to #06 / #F6 / #00 set bit 4 (beeper) and bit 3 (MIC), the ones to #FE clear them: a 50 Hz
; buzz = the beeper / MIC takes an even port other than #FE (it must stay on #FE only).
; Before 26112002 bands 2..4 are not there (the colour of band 1 goes on), the rest the same.
; unreal-ng PENTAGON shows bands 1..3 and 5..9 but not 4 (its decoding of #00 / #A0), checked 2026-11-21.
	DEVICE ZXSPECTRUM48

	org #8000
start:
	ld bc, #20AF		; SYSCONFIG: 3.5 MHz
	xor a
	out (c), a
	ld a, 2			; channel 2, the screen
	call #1601
	ld a, 7*8		; paper white, ink black
	ld (#5C8D), a		; ATTR_P
	call #0DAF		; CLS
	ld hl, text
.t:	ld a, (hl)
	or a
	jr z, .run
	rst #10
	inc hl
	jr .t

.run:	ei
.frame:	halt
	ld a, 2			; 1 red
	out (#FE), a
	call band
	ld bc, #0006		; 2 green
	ld a, #18 | 4
	out (c), a
	call band
	ld bc, #00F6		; 3 cyan
	ld a, #18 | 5
	out (c), a
	call band
	ld bc, #0000		; 4 magenta
	ld a, #18 | 3
	out (c), a
	call band
	ld c, #C4		; 5..7 OPL4, 8 Covox: black expected
	call notb
	ld c, #C6
	call notb
	ld c, #7E
	call notb
	ld c, #FB
	call notb
	ld a, 1			; 9 blue
	out (#FE), a
	call band
	xor a			; the rest of the frame (and the INT) black
	out (#FE), a
	jr .frame

notb:	xor a			; black by #FE, then white to the port in C (B = 0)
	out (#FE), a
	ld b, 0
	ld a, 7
	out (c), a
band:	ld hl, 275		; about 7150 T = 32 lines of 224 T
.d:	dec hl
	ld a, h
	or l
	jr nz, .d
	ret

text:	db "BORDER TEST (A0=0), 26112002+", 13, 13
	db "Left / right border, top down:", 13
	db " red, green, cyan, magenta,", 13
	db " 4 x black, blue.", 13, 13
	db "A white band = an OPL4 port", 13
	db "(#C4 #C6 #7E) or #FB took the", 13
	db "border. No green / cyan /", 13
	db "magenta = no A0 decoding.", 13
	db "A 50 Hz buzz = the beeper takes", 13
	db "an even port other than #FE.", 0
end_code:

; ---- the TRD: "boot" (BASIC) and "bordt" (CODE #8000)
	EMPTYTRD "bordt.trd", "BORDTEST"
	SAVETRD "bordt.trd", "bordt.C", start, end_code - start
	org #6000
basic:
	; 10 RANDOMIZE USR 15619: REM : LOAD "bordt" CODE   (to its own address, #8000)
	db 0, 10
	dw .l10e - .l10
.l10:	db #F9, #C0, "15619", #0E, 0, 0, #03, #3D, 0, ":", #EA, ":", #EF, '"bordt"', #AF, #0D
.l10e:
	; 20 RANDOMIZE USR 32768
	db 0, 20
	dw .l20e - .l20
.l20:	db #F9, #C0, "32768", #0E, 0, 0, #00, #80, 0, #0D
.l20e:
basic_end:
	SAVETRD "bordt.trd", "boot.B", basic, basic_end - basic, 10
