; opl4z.asm (sjasmplus): fills the sample RAM of the OPL4 (#200000..#3FFFFF, 2 MB) with zeros through the
; memory port (reg 3..5 the address, reg 6 the data), run from TR-DOS: opl4z.trd, "boot". The CPU at 14 MHz.
; A diagnosis: the SDRAM holds garbage after power-up, an emulator zeros its RAM. The border cycles per
; 64 KB while writing, green at the end.
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

	ld a, #20
	ld (blk), a
.blk:	ld a, (blk)
	and 7
	out (#FE), a
	ld a, (blk)
	ld de, 0
	call maddr
	ld c, 0
.o:	ld b, 0
.i:	call wbusy
	ld a, 6
	out (WREG), a
	call dly
	xor a
	out (WDAT), a
	djnz .i
	dec c
	jr nz, .o
	ld hl, blk
	inc (hl)
	ld a, (hl)
	cp #40
	jr nz, .blk
	ld de, #0212
	call wout
	ld a, 4
	out (#FE), a
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

blk:	db 0
end_code:

	EMPTYTRD "opl4z.trd", "OPL4ZERO"
	SAVETRD "opl4z.trd", "opl4z.C", start, end_code - start
	org #6000
basic:
	; 10 RANDOMIZE USR 15619: REM : LOAD "opl4z" CODE
	db 0, 10
	dw .l10e - .l10
.l10:	db #F9, #C0, "15619", #0E, 0, 0, #03, #3D, 0, ":", #EA, ":", #EF, '"opl4z"', #AF, #0D
.l10e:
	; 20 RANDOMIZE USR 32768
	db 0, 20
	dw .l20e - .l20
.l20:	db #F9, #C0, "32768", #0E, 0, 0, #00, #80, 0, #0D
.l20e:
basic_end:
	SAVETRD "opl4z.trd", "boot.B", basic, basic_end - basic, 10
