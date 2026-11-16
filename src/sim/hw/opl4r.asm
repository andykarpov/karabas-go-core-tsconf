; opl4r.asm (sjasmplus): a hardware test of TS-Conf: the YRW801 ROM (2 MB, loaded from the SD card into the
; SDRAM) read back through the memory port of the OPL4 (reg 3..5 the address, reg 6 the data), run from
; TR-DOS: opl4r.trd, "boot" loads the code at #8000 and starts it. The CPU at 14 MHz (#20AF).
; Per block of 64 KB a Fletcher sum (s1 += byte, s2 += s1, 16 bits; gen_opl4r.py the expected ones).
; The screen: 8 rows of 4 blocks, s2 in hex, green paper = as expected, red = not; the border at the end
; green when all 32 match, red otherwise. The progress: the border cycles while reading.
	DEVICE ZXSPECTRUM48
STAT	equ #C4
WREG	equ #7E
WDAT	equ #7F

	org #8000
start:
	di
	ld sp, #7FF0
	ld bc, #20AF		; SYSCONFIG: 14 MHz
	ld a, 2
	out (c), a
	xor a
	out (#FE), a
	call cls
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

	xor a
	ld (blk), a
	ld (bad), a
.blk:	ld a, (blk)
	and 7
	out (#FE), a
	ld a, (blk)
	ld de, 0
	call maddr
	ld de, 0		; s1
	ld ix, 0		; s2
	ld c, 0			; 256 x 256 bytes
.o:	ld b, 0
.i:	call wbusy
	ld a, 6
	out (WREG), a
	call dly
	in a, (WDAT)
	add a, e
	ld e, a
	jr nc, .nc
	inc d
.nc:	add ix, de
	djnz .i
	dec c
	jr nz, .o
	; store s2, compare, print
	ld a, (blk)
	ld l, a
	ld h, 0
	add hl, hl
	push hl
	ld bc, got
	add hl, bc
	push ix
	pop de
	ld (hl), e
	inc hl
	ld (hl), d
	pop hl
	ld bc, expect
	add hl, bc
	ld a, (hl)
	cp e
	jr nz, .bad
	inc hl
	ld a, (hl)
	cp d
	ld a, #20		; green paper, black ink
	jr z, .col
.bad:	ld hl, bad
	inc (hl)
	ld a, #17		; red paper, white ink
.col:	push de
	push af
	; position: row = blk / 4, column = (blk % 4) * 8
	ld a, (blk)
	and 3
	add a, a
	add a, a
	add a, a
	ld c, a
	ld a, (blk)
	and #1C
	add a, a
	add a, a
	add a, a		; row * 32
	add a, c
	ld e, a
	ld d, #58
	pop af
	ld b, 4
.at:	ld (de), a
	inc e
	djnz .at
	ld a, e
	sub 4
	ld e, a
	ld d, #40
	pop bc			; the sum: b high, c low
	ld a, b
	call phex
	ld a, c
	call phex
	ld hl, blk
	inc (hl)
	ld a, (hl)
	cp 32
	jp nz, .blk
	; memory access off
	ld de, #0212
	call wout
	ld a, (bad)
	or a
	ld a, 4			; green
	jr z, .brd
	ld a, 2			; red
.brd:	out (#FE), a
.end:	jr .end

; maddr: the memory address a:de into regs 3, 4, 5
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
; phex: a as two hex digits at de (advances e by 2; keeps bc)
phex:	push bc
	push af
	rrca : rrca : rrca : rrca
	call pdig
	pop af
	call pdig
	pop bc
	ret
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

blk:	db 0
bad:	db 0
got:	ds 64
	include "opl4r_data.asm"
	include "opl4t_data.asm"	; the font
end_code:

	EMPTYTRD "opl4r.trd", "OPL4ROM "
	SAVETRD "opl4r.trd", "opl4r.C", start, end_code - start
	org #6000
basic:
	; 10 RANDOMIZE USR 15619: REM : LOAD "opl4r" CODE
	db 0, 10
	dw .l10e - .l10
.l10:	db #F9, #C0, "15619", #0E, 0, 0, #03, #3D, 0, ":", #EA, ":", #EF, '"opl4r"', #AF, #0D
.l10e:
	; 20 RANDOMIZE USR 32768
	db 0, 20
	dw .l20e - .l20
.l20:	db #F9, #C0, "32768", #0E, 0, 0, #00, #80, 0, #0D
.l20e:
basic_end:
	SAVETRD "opl4r.trd", "boot.B", basic, basic_end - basic, 10
