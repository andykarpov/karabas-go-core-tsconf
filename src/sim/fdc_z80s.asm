; fdc_z80s.asm: the program of tb_fdc_z80s (sjasmplus --raw), the Beta Disk ports the way TR-DOS uses them.
; Results at #8000: +0 status after Restore, +1 status after Read, +2 status after Write, +3/+4 bytes read,
; +5/+6 bytes written, +7 = #EE at the end. The read sector goes to #9000, the written one is built at #A000.
; Port #FE (marks for the testbench): 1 before the poll loop, 2 after it.

	org 0
	di
	ld sp, #7FF0
	xor a
	out (#FF), a		; /MR low
	ld b, 50
.d1:	djnz .d1
	ld a, #3C		; drive A, /MR high, HLT, side 0
	out (#FF), a

	; Restore, h = 1, rate 6 ms
	ld a, #08
	out (#1F), a
	call wait_intrq
	in a, (#1F)
	ld (#8000), a

	; the poll loop of TR-DOS (IN A,(#FF) in a loop): 64 turns of 27 T
	ld a, 1
	out (#FE), a
	ld b, 64
.p:	in a, (#FF)
	djnz .p
	ld a, 2
	out (#FE), a

	; Read Sector 1 into #9000 (INI)
	ld a, 1
	out (#5F), a
	ld a, #80
	out (#1F), a
	ld hl, #9000
	ld c, #7F
.r:	in a, (#FF)
	and #C0
	jr z, .r
	jp m, .rend
	ini
	jr .r
.rend:	in a, (#1F)
	ld (#8001), a
	ld de, #9000
	or a
	sbc hl, de
	ld (#8003), hl

	; Write Sector 1 from #A000 (OUTI): FF - 3 * i
	ld hl, #A000
	ld a, #FF
	ld b, 0
.f:	ld (hl), a
	sub 3
	inc hl
	djnz .f
	ld a, 1
	out (#5F), a
	ld a, #A0
	out (#1F), a
	ld hl, #A000
	ld c, #7F
.w:	in a, (#FF)
	and #C0
	jr z, .w
	jp m, .wend
	outi
	jr .w
.wend:	in a, (#1F)
	ld (#8002), a
	ld de, #A000
	or a
	sbc hl, de
	ld (#8005), hl

	ld a, #EE
	ld (#8007), a
	halt

wait_intrq:
	in a, (#FF)
	rlca
	jr nc, wait_intrq
	ret
