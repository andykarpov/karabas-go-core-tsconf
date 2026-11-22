; ay_test.asm (sjasmplus): a hardware test of the AY (kg_ym2149 / ay38910_silicon of modules), by Activator RFG
; (ay38910_silicon_release.zip, 2026-11-22); here with the TRD and the select of the first AY of the
; TurboSound. Run from TR-DOS: ay_test.trd, "boot". Keys 1..5 the modes, 0 silence:
;   1  R13 written every frame, envelope period 597 (\\ from 15, 3.66 steps a frame): a steady
;      50 Hz buzz; with the old ym2149.v (R13 did not restart the period counter) a ~17 Hz beat
;   2  R13 every 4 frames, period 1280: even beats (old: the attack wobbles)
;   3  noise R6 = 31 (the LFSR x^17 + x^14 + 1)
;   4  440 Hz tone, the volume 0..15 (the DDp table)
;   5  a tune: envelope bass (R13 every step), a lead, noise drums
; The OSD item PSG Type switches AY / YM on the fly.
    DEVICE ZXSPECTRUM48
    ORG #8000

START:
    DI
    IM 1
    XOR A
    OUT (#FE), A
    LD A, #07           ; white on black
    LD (#5C8D), A       ; ATTR_P
    LD (#5C48), A       ; BORDCR
    CALL #0DAF          ; ROM CLS
    LD A, 2
    CALL #1601          ; open channel #2 (main screen)

    LD HL, TXT_HEADER
    CALL PRINT_STR

    LD BC, #FFFD        ; karabas: the first AY of the TurboSound (a program before may have selected the second)
    LD A, #FF
    OUT (C), A
    CALL AY_SILENCE
    LD A, 1
    LD (MODE), A
    CALL INIT_MODE

MAIN_LOOP:
    EI
    HALT                ; sync to 50 Hz frame!

    ; Check keys 1, 2, 3, 4, 5, 0
    ; Row 1-5: port #F7FE (bits 0..4 = '1'..'5')
    LD BC, #F7FE
    IN A, (C)
    BIT 0, A
    JR NZ, .k2
    LD A, 1
    JR .setm
.k2:
    BIT 1, A
    JR NZ, .k3
    LD A, 2
    JR .setm
.k3:
    BIT 2, A
    JR NZ, .k4
    LD A, 3
    JR .setm
.k4:
    BIT 3, A
    JR NZ, .k5
    LD A, 4
    JR .setm
.k5:
    BIT 4, A
    JR NZ, .k0
    LD A, 5
    JR .setm
.k0:
    ; Row 0-6: port #EFFE (bit 0 = '0')
    LD BC, #EFFE
    IN A, (C)
    BIT 0, A
    JR NZ, .run
    XOR A
.setm:
    LD HL, MODE
    CP (HL)
    JR Z, .run
    LD (HL), A
    CALL INIT_MODE

.run:
    LD A, (MODE)
    OR A
    JR Z, MAIN_LOOP
    DEC A
    JR Z, TICK_M1
    DEC A
    JR Z, TICK_M2
    DEC A
    JR Z, TICK_M3
    DEC A
    JR Z, TICK_M4
    JR TICK_M5

; ------------------------------------------------------------
; Mode 1: R13 50Hz Retrigger (period=597 -> 3.66 steps/frame)
; Silicon AY = steady clean 50Hz saw/buzz
; Old ym2149 = audible ~17Hz warble/beating!
; ------------------------------------------------------------
TICK_M1:
    LD D, 13
    LD E, #08           ; \\\\ decay from 15
    CALL AY_WR
    JR MAIN_LOOP

; ------------------------------------------------------------
; Mode 2: Slow R13 Metronome (period=1280, retrigger every 4 frames)
; Silicon AY = identical crisp thump every beat
; Old ym2149 = attack wobbles/jitters every beat!
; ------------------------------------------------------------
TICK_M2:
    LD HL, SUBCNT
    DEC (HL)
    JR NZ, MAIN_LOOP
    LD (HL), 4
    LD D, 13
    LD E, #08
    CALL AY_WR
    JR MAIN_LOOP

; ------------------------------------------------------------
; Mode 3: Slow LFSR Noise (R6=31)
; ------------------------------------------------------------
TICK_M3:
    JR MAIN_LOOP

; ------------------------------------------------------------
; Mode 4: DDp DAC Volume Ramp 0..15 on 440Hz tone
; ------------------------------------------------------------
TICK_M4:
    LD HL, SUBCNT
    DEC (HL)
    JP NZ, MAIN_LOOP
    LD (HL), 18         ; ~0.36 sec per step
    LD A, (STEP)
    INC A
    AND #0F
    LD (STEP), A
    LD D, 8
    LD E, A
    CALL AY_WR
    CALL SHOW_VOL
    JP MAIN_LOOP

; ------------------------------------------------------------
; Mode 5: Demo Melody (Env Bass R13 + Ch B Lead + Ch C Noise Drum)
; ------------------------------------------------------------
TICK_M5:
    LD HL, SUBCNT
    DEC (HL)
    JP NZ, MAIN_LOOP
    LD (HL), 7          ; ~7 frames per 1/16 note

    LD A, (STEP)
    INC A
    AND #0F
    LD (STEP), A
    LD C, A             ; step 0..15

    ; Bass envelope period on Ch A (retrigger R13 every step!)
    LD HL, BASS_TBL
    LD B, 0
    ADD HL, BC
    ADD HL, BC
    LD E, (HL)
    INC HL
    LD D, 11
    CALL AY_WR
    LD E, (HL)
    LD D, 12
    CALL AY_WR
    LD D, 13
    LD E, #08           ; retrigger envelope -> tests R13 counter reset!
    CALL AY_WR

    ; Lead tone on Ch B
    LD HL, LEAD_TBL
    LD B, 0
    ADD HL, BC
    ADD HL, BC
    LD E, (HL)
    INC HL
    LD D, 2
    CALL AY_WR
    LD E, (HL)
    LD D, 3
    CALL AY_WR

    ; Noise drum on Ch C (snare on steps 4, 12; hihat on odd steps)
    LD A, C
    AND 7
    CP 4
    JR Z, .snare
    BIT 0, C
    JR NZ, .hat
    LD D, 10
    LD E, 0
    CALL AY_WR
    JP MAIN_LOOP
.snare:
    LD D, 6
    LD E, 28            ; low gritty noise -> tests LFSR polynomial
    CALL AY_WR
    LD D, 10
    LD E, 13
    CALL AY_WR
    JP MAIN_LOOP
.hat:
    LD D, 6
    LD E, 6
    CALL AY_WR
    LD D, 10
    LD E, 7
    CALL AY_WR
    JP MAIN_LOOP

; ------------------------------------------------------------
; Initialize newly selected mode
; ------------------------------------------------------------
INIT_MODE:
    CALL AY_SILENCE
    XOR A
    LD (STEP), A
    LD A, 1
    LD (SUBCNT), A

    CALL SHOW_MODE

    LD A, (MODE)
    OR A
    RET Z               ; Mode 0 = silence

    CP 1
    JR Z, .im1
    CP 2
    JR Z, .im2
    CP 3
    JR Z, .im3
    CP 4
    JR Z, .im4
    JR .im5

.im1:
    ; R13 50Hz retrigger: period = #0255 (597 -> 3.66 steps/frame)
    LD D, 7 : LD E, #3F : CALL AY_WR   ; tone & noise off -> pure envelope
    LD D, 8 : LD E, #10 : CALL AY_WR   ; Ch A = env
    LD D, 11: LD E, #55 : CALL AY_WR
    LD D, 12: LD E, #02 : CALL AY_WR
    LD D, 13: LD E, #08 : CALL AY_WR
    RET

.im2:
    ; Slow R13 metronome: period = #0500 (1280)
    LD D, 7 : LD E, #3F : CALL AY_WR
    LD D, 8 : LD E, #10 : CALL AY_WR
    LD D, 11: LD E, #00 : CALL AY_WR
    LD D, 12: LD E, #05 : CALL AY_WR
    LD D, 13: LD E, #08 : CALL AY_WR
    RET

.im3:
    ; Slow noise LFSR R6=31
    LD D, 6 : LD E, 31  : CALL AY_WR
    LD D, 7 : LD E, #37 : CALL AY_WR   ; only Noise A enabled
    LD D, 8 : LD E, 15  : CALL AY_WR
    RET

.im4:
    ; DDp volume ramp 0..15 on 440Hz tone (TP=249 = #00F9)
    LD D, 0 : LD E, #F9 : CALL AY_WR
    LD D, 1 : LD E, #00 : CALL AY_WR
    LD D, 7 : LD E, #3E : CALL AY_WR   ; only Tone A enabled
    LD D, 8 : LD E, 0   : CALL AY_WR
    CALL SHOW_VOL
    RET

.im5:
    ; Demo melody: Ch A = env bass, Ch B = tone lead, Ch C = noise drum
    ; R7 = 00_011_101 (#1D): Tone B on (bit1=0), Noise C on (bit5=0)
    LD D, 7 : LD E, #1D : CALL AY_WR
    LD D, 8 : LD E, #10 : CALL AY_WR   ; Ch A = env
    LD D, 9 : LD E, 10  : CALL AY_WR   ; Ch B = vol 10
    LD D, 10: LD E, 0   : CALL AY_WR   ; Ch C = drum
    RET

; ------------------------------------------------------------
; AY-3-8910 helpers: D = reg, E = value
; ------------------------------------------------------------
AY_WR:
    LD BC, #FFFD
    OUT (C), D
    LD B, #BF
    OUT (C), E
    RET

AY_SILENCE:
    LD D, 8 : LD E, 0 : CALL AY_WR
    LD D, 9 : LD E, 0 : CALL AY_WR
    LD D, 10: LD E, 0 : CALL AY_WR
    LD D, 7 : LD E, #3F : CALL AY_WR
    RET

; ------------------------------------------------------------
; Screen printing helpers
; ------------------------------------------------------------
PRINT_STR:
    LD A, (HL)
    OR A
    RET Z
    RST #10
    INC HL
    JR PRINT_STR

SHOW_MODE:
    LD A, 22 : RST #10  ; AT
    LD A, 18 : RST #10  ; row 18
    LD A, 0  : RST #10  ; col 0
    LD HL, TXT_NOW
    CALL PRINT_STR
    LD A, (MODE)
    ADD A, A
    LD E, A
    LD D, 0
    LD HL, MODE_PTRS
    ADD HL, DE
    LD E, (HL)
    INC HL
    LD D, (HL)
    EX DE, HL
    CALL PRINT_STR
    RET

SHOW_VOL:
    LD A, 22 : RST #10
    LD A, 19 : RST #10
    LD A, 0  : RST #10
    LD HL, TXT_VOL
    CALL PRINT_STR
    LD A, (STEP)
    CP 10
    JR C, .one
    PUSH AF
    LD A, '1' : RST #10
    POP AF
    SUB 10
    ADD A, '0'
    RST #10
    RET
.one:
    PUSH AF
    LD A, '0' : RST #10
    POP AF
    ADD A, '0'
    RST #10
    RET

; ------------------------------------------------------------
; Data & Tables
; ------------------------------------------------------------
MODE:   DB 1
SUBCNT: DB 1
STEP:   DB 0

; Envelope periods for bass notes (A1, A1, C2, D2, E2, E2, G2, E2...)
BASS_TBL:
    DW #01F0, #01F0, #01A0, #0173, #014B, #014B, #0117, #014B
    DW #01F0, #01A0, #0173, #014B, #0173, #01A0, #01D0, #01F0

; Tone periods for lead melody on Ch B
LEAD_TBL:
    DW #00F8, #00D1, #00BA, #00A5, #00BA, #00D1, #00F8, #0117
    DW #00F8, #00BA, #00A5, #008B, #00A5, #00BA, #00D1, #00F8

TXT_HEADER:
    DB "AY-3-8910 SILICON TEST (Titus)", 13
    DB "==============================", 13, 13
    DB "1: R13 50Hz RETRIGGER (BEST!)", 13
    DB "   New AY = clean steady buzz", 13
    DB "   Old YM = warble / beating", 13, 13
    DB "2: R13 SLOW METRONOME", 13
    DB "   New AY = crisp even beats", 13
    DB "   Old YM = jittery attack", 13, 13
    DB "3: SLOW NOISE LFSR (R6=31)", 13
    DB "4: DAC VOLUME RAMP 0..15 (DDp)", 13
    DB "5: DEMO MELODY (Env+Lead+Drum)", 13
    DB "0: SILENCE", 13, 0

TXT_NOW: DB "ACTIVE: ", 0
TXT_VOL: DB "DAC LEVEL: ", 0

MODE_PTRS:
    DW M0_STR, M1_STR, M2_STR, M3_STR, M4_STR, M5_STR

M0_STR: DB "[0] SILENCE             ", 0
M1_STR: DB "[1] R13 50Hz RETRIGGER  ", 0
M2_STR: DB "[2] R13 SLOW METRONOME  ", 0
M3_STR: DB "[3] SLOW NOISE (R6=31)  ", 0
M4_STR: DB "[4] DAC RAMP 0..15      ", 0
M5_STR: DB "[5] DEMO MELODY         ", 0

END_CODE:

; ---- the TRD: "boot" (BASIC) and "ay_test" (CODE #8000)
	EMPTYTRD "ay_test.trd", "AYTEST"
	SAVETRD "ay_test.trd", "ay_test.C", START, END_CODE - START
	org #6000
basic:
	; 10 RANDOMIZE USR 15619: REM : LOAD "ay_test" CODE   (to its own address, #8000)
	db 0, 10
	dw .l10e - .l10
.l10:	db #F9, #C0, "15619", #0E, 0, 0, #03, #3D, 0, ":", #EA, ":", #EF, '"ay_test"', #AF, #0D
.l10e:
	; 20 RANDOMIZE USR 32768
	db 0, 20
	dw .l20e - .l20
.l20:	db #F9, #C0, "32768", #0E, 0, 0, #00, #80, 0, #0D
.l20e:
basic_end:
	SAVETRD "ay_test.trd", "boot.B", basic, basic_end - basic, 10
