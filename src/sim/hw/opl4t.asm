; opl4t.asm (sjasmplus): a hardware test of the OPL4 of TS-Conf (ZXM-MoonSound ports), run from TR-DOS:
; opl4t.trd, "boot" loads the code at #8000 and starts it.
; 1. NEW2; the sine (gen_opl4t.py) in RAM: 8-bit at #201000, 12-bit at #202000, 16-bit at #203000, the headers
;    of tones 384..386 at #200000 (reg 2: header base 4 = #200000, memory type 1).
; 2. Reads them back; 32 KB of a pseudo random sequence at #210000, another at #310000, then both read back
;    (a lost address bit 20 would make the second overwrite the first).
; 3. Plays the sine on channel 0: 8-bit, 12-bit, 16-bit, 16-bit an octave down (step 0.5), 3 s each with 1 s of
;    silence; the border during each: blue, red, green, cyan; black at the end.
; 4. The screen, one row each, 4 hex digits: errors of 8-bit, 12-bit, 16-bit, headers, block #21, block #31.
	DEVICE ZXSPECTRUM48
STAT	equ #C4
WREG	equ #7E
WDAT	equ #7F

	org #8000
start:
	di
	ld sp, #7FF0
	xor a
	out (#FE), a
	call cls
	ld hl, errs
	ld b, 12
.z:	ld (hl), 0
	inc hl
	djnz .z
	; NEW2 (FM bank 1: reg 5 = 3)
	ld a, 5
	out (#C6), a
	call dly
	ld a, 3
	out (#C7), a
	call dly
	; reg 2: header base 4, memory type 1, memory access 1
	ld de, #0213
	call wout

	; ---- the data into RAM
	ld hl, sin8
	ld bc, 256
	ld a, #20 : ld de, #1000
	call mwrite
	ld hl, sin12
	ld bc, 384
	ld a, #20 : ld de, #2000
	call mwrite
	ld hl, sin16
	ld bc, 512
	ld a, #20 : ld de, #3000
	call mwrite
	ld hl, hdrs
	ld bc, 36
	ld a, #20 : ld de, #0000
	call mwrite
	; ---- read back
	ld hl, sin8
	ld bc, 256
	ld a, #20 : ld de, #1000
	call mcheck
	ld (errs + 0), ix
	ld hl, sin12
	ld bc, 384
	ld a, #20 : ld de, #2000
	call mcheck
	ld (errs + 2), ix
	ld hl, sin16
	ld bc, 512
	ld a, #20 : ld de, #3000
	call mcheck
	ld (errs + 4), ix
	ld hl, hdrs
	ld bc, 36
	ld a, #20 : ld de, #0000
	call mcheck
	ld (errs + 6), ix
	; ---- two blocks of 32 KB: #210000 (seed 1), #310000 (seed 2); then both checked
	ld a, #21 : ld hl, #0001
	call rwrite
	ld a, #31 : ld hl, #0002
	call rwrite
	ld a, #21 : ld hl, #0001
	call rcheck
	ld (errs + 8), ix
	ld a, #31 : ld hl, #0002
	call rcheck
	ld (errs + 10), ix
	; ---- the results
	ld hl, errs
	ld b, 6
	ld de, #4000		; row 0
.pr:	push bc
	push de
	ld a, (hl) : inc hl
	ld c, (hl) : inc hl	; c = high byte, a = low byte
	push hl
	push af
	ld a, c
	call phex
	pop af
	call phex
	pop hl
	pop de
	ld a, e : add a, #20 : ld e, a	; next character row (in the first third)
	pop bc
	djnz .pr
	; memory access off (reg 2 bit 0) for the play
	ld de, #0212
	call wout

	; ---- play: tone 384 + n, octave in c
	ld a, 1 : ld b, #80 : ld c, #00 : call play	; 8-bit
	ld a, 2 : ld b, #81 : ld c, #00 : call play	; 12-bit
	ld a, 4 : ld b, #82 : ld c, #00 : call play	; 16-bit
	ld a, 5 : ld b, #82 : ld c, #F0 : call play	; 16-bit, octave -1
	xor a
	out (#FE), a
.end:	jr .end

; play: border a, tone low byte b (bit 8 = 1), octave/F-hi c; 3 s on, 1 s off
play:
	out (#FE), a
	ld e, b
	ld d, #50 : push de : ld e, #00 : call wout : pop de	; TL 0
	ld d, #68 : push de : ld e, #00 : call wout : pop de	; key off
	ld d, #38 : push de : ld e, c : call wout : pop de	; octave, F-number high 0
	ld d, #20 : push de : ld e, #01 : call wout : pop de	; F-number low 0, tone bit 8
	ld d, #08 : call wout				; tone: loads the header
	call wbusy
	ld de, #6880				; key on, pan centre
	call wout
	ld b, 3 * 50
	call frames
	ld de, #6800				; key off
	call wout
	ld b, 50
	call frames
	ret

; wait b frames (the frame interrupt, IM 1 of the ROM: 50 Hz at any CPU speed)
frames:
	ei
.f:	halt
	djnz .f
	di
	ret

; mwrite: bc bytes from hl into OPL4 memory at a:de (a = bits 21..16)
mwrite:
	call maddr
.w:	call wbusy
	ld a, 6
	out (WREG), a
	call dly
	ld a, (hl)
	out (WDAT), a
	inc hl
	dec bc
	ld a, b
	or c
	jr nz, .w
	ret

; mcheck: compare bc bytes of OPL4 memory at a:de with hl; ix = errors
mcheck:
	ld ix, 0
	call maddr
.c:	call wbusy
	ld a, 6
	out (WREG), a
	call dly
	in a, (WDAT)
	cp (hl)
	jr z, .ok
	inc ix
.ok:	inc hl
	dec bc
	ld a, b
	or c
	jr nz, .c
	ret

; rwrite / rcheck: 32 KB at a:#0000 of the sequence x = x * 5 + 1 (16-bit, seed hl), the high byte written
rwrite:
	ld de, 0
	call maddr
	ld bc, #8000
.rw:	call rnext
	call wbusy
	ld a, 6
	out (WREG), a
	call dly
	ld a, h
	out (WDAT), a
	dec bc
	ld a, b
	or c
	jr nz, .rw
	ret
rcheck:
	ld ix, 0
	ld de, 0
	call maddr
	ld bc, #8000
.rc:	call rnext
	call wbusy
	ld a, 6
	out (WREG), a
	call dly
	in a, (WDAT)
	cp h
	jr z, .rok
	inc ix
.rok:	dec bc
	ld a, b
	or c
	jr nz, .rc
	ret
rnext:			; hl = hl * 5 + 1
	push de
	ld d, h
	ld e, l
	add hl, hl
	add hl, hl
	add hl, de
	inc hl
	pop de
	ret

; maddr: the memory address a:de into regs 3, 4, 5 (keeps hl, bc)
maddr:
	push de
	ld d, 3 : ld e, a : call wout
	pop de
	push de
	ld e, d : ld d, 4 : call wout
	pop de
	push de
	ld d, 5 : call wout
	pop de
	ret

; wout: wave register d = e
wout:
	call wbusy
	ld a, d
	out (WREG), a
	call dly
	ld a, e
	out (WDAT), a
	ret
wbusy:
	in a, (STAT)
	rra
	jr c, wbusy
	ret
dly:	push af
	pop af
	ret

; the screen
cls:	ld hl, #4000
	ld de, #4001
	ld bc, #17FF
	ld (hl), 0
	ldir
	ld hl, #5800
	ld de, #5801
	ld bc, #2FF
	ld (hl), #38		; black on white
	ldir
	ret
; phex: a as two hex digits at de (advances e by 2)
phex:	push af
	rrca : rrca : rrca : rrca
	call pdig
	pop af
pdig:	and #0F
	ld l, a
	ld h, 0
	add hl, hl
	add hl, hl
	add hl, hl
	ld bc, font
	add hl, bc
	push de
	ld b, 8
.g:	ld a, (hl)
	ld (de), a
	inc hl
	inc d
	djnz .g
	pop de
	inc e
	ret

errs:	ds 12
	include "opl4t_data.asm"
end_code:

; ---- the TRD: "boot" (BASIC) and "opl4t" (CODE #8000)
	EMPTYTRD "opl4t.trd", "OPL4TEST"
	SAVETRD "opl4t.trd", "opl4t.C", start, end_code - start
	org #6000
basic:
	; 10 RANDOMIZE USR 15619: REM : LOAD "opl4t" CODE   (to its own address, #8000)
	db 0, 10
	dw .l10e - .l10
.l10:	db #F9, #C0, "15619", #0E, 0, 0, #03, #3D, 0, ":", #EA, ":", #EF, '"opl4t"', #AF, #0D
.l10e:
	; 20 RANDOMIZE USR 32768
	db 0, 20
	dw .l20e - .l20
.l20:	db #F9, #C0, "32768", #0E, 0, 0, #00, #80, 0, #0D
.l20e:
basic_end:
	SAVETRD "opl4t.trd", "boot.B", basic, basic_end - basic, 10
