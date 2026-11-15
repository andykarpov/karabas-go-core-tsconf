; gs_memtest.asm: the test ROM of tb_gs_top (sjasmplus --raw=gs_memtest.bin). The GS Z80 writes and reads its RAM (the
; window #4000 = the first half of page 1, and pages 2..5 at #8000), a write to a cached word and to the other byte of it, a
; write to the ROM (no effect), then a timed loop; the result goes to port #03:
;   #55 the timed loop starts, #AA all passed, 1..6 the failed test.
	org	0
	di
	ld	sp,#8000

	; 1: #4000..#40FF = L xor H xor #5A
	ld	hl,#4000
	ld	bc,#0100
f1:	ld	a,l
	xor	h
	xor	#5a
	ld	(hl),a
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,f1

	; 2: pages 2..5: #8000..#801F and #FFE0..#FFFF = page xor L
	ld	d,2
p1:	ld	a,d
	out	(0),a
	ld	hl,#8000
	call	fillp
	ld	hl,#ffe0
	call	fillp
	inc	d
	ld	a,d
	cp	6
	jr	nz,p1

	ld	hl,#4000
	ld	bc,#0100
c1:	ld	a,l
	xor	h
	xor	#5a
	cp	(hl)
	jp	nz,err1
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,c1

	ld	d,2
p2:	ld	a,d
	out	(0),a
	ld	hl,#8000
	call	chkp
	jp	nz,err2
	ld	hl,#ffe0
	call	chkp
	jp	nz,err2
	inc	d
	ld	a,d
	cp	6
	jr	nz,p2

	; 3: a write to a cached word: #4023 (odd byte of the word #4022)
	ld	hl,#4022
	ld	a,(hl)		; the word into the cache
	ld	a,#c3
	inc	hl
	ld	(hl),a		; the odd byte
	ld	a,(hl)
	cp	#c3
	jp	nz,err3
	dec	hl
	ld	a,l
	xor	h
	xor	#5a
	cp	(hl)		; the even byte unchanged
	jp	nz,err4

	; 4: page 2 again after the other pages: #8010 = 2 xor #10
	ld	a,2
	out	(0),a
	ld	a,(#8010)
	cp	#12
	jp	nz,err5

	; 5: the ROM is not written
	ld	a,(rombyte)
	ld	b,a
	cpl
	ld	(rombyte),a
	ld	a,(rombyte)
	cp	b
	jp	nz,err6

	; the timed loop: 4 x 256 x (NOP + DJNZ) = 4 x 256 x 17 - 4 x 5 T
	ld	a,#55
	out	(3),a
	ld	c,4
t1:	ld	b,0
t2:	nop
	djnz	t2
	dec	c
	jr	nz,t1
	ld	a,#aa
	out	(3),a
	halt

err1:	ld	a,1
	jr	errx
err2:	ld	a,2
	jr	errx
err3:	ld	a,3
	jr	errx
err4:	ld	a,4
	jr	errx
err5:	ld	a,5
	jr	errx
err6:	ld	a,6
errx:	out	(3),a
	halt

fillp:	ld	b,32
fl:	ld	a,d
	xor	l
	ld	(hl),a
	inc	l
	djnz	fl
	ret

chkp:	ld	b,32
ck:	ld	a,d
	xor	l
	cp	(hl)
	ret	nz
	inc	l
	djnz	ck
	xor	a
	ret

rombyte:
	db	#3c

