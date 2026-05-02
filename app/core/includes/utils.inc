; Note: This code is adapted and modified from from https://raw.githubusercontent.com/breakintoprogram/lib-spectrum/refs/heads/master/lib/macros.z80
;       original author: Dean Belfield
;
;       I have added a few things

; Regular bcall macro
MACRO bcall nn
  rst 28h
  DEFW nn
endm


; An auto incrementing ram definition
MACRO RDEF arena, name, size
; Capture the old arena value as a constant
  DEFC name = arena

; Redefine the arena based on that constant
; Note: 'DEFL' is token replacment, so care needs to be taken as not to blow up the file. 

  DEFL arena = name + size
endm

MACRO RALIGN arena, alignment
  DEFL arena = (arena) + alignment - ((arena) % alignment)
endm

; Taken from https://wikiti.brandonw.net/index.php?title=Z80_Routines:Optimized:CpHLDE
; (30 t-states)
MACRO CpHLDE
  or a
  sbc hl,de
  add hl,de
endm

macro min p1            ; Get min of p1 and a in a
    cp p1               ; Compare a with p1
    jr c, @s1          ; Skip if p1 > a
    ld a, p1            ; Assign p1 to a
@s1:
endm

macro max p1            ; Get max of p1 and a in a
    cp p1               ; Compare a with p1
    jr nc, @s1         ; Skip if p1 > a
    ld a, p1            ; Assign p1 to a
@s1:
endm


; Takes the highest bits set, and cascades it down
macro msb_maska
    ld   b,a
    srl  b
    or   b

    ld   b,a
    srl  b
    srl  b
    or   b

    ld   b,a
    srl  b
    srl  b
    srl  b
    srl  b
    or   b
endm


; EXTERN popcnt_table

; a = amount of bits set in a
; Clobbers: a, de, hl, c
;macro popcnt_a
;  ld c, a
;  and $F
;
;  ld d, popcnt_table >> 8
;  ld e, a
;
;  ld a, c
;  and $F0
;  rrca \ rrca \ rrca \ rrca
;  ld h, d
;  ld l, a
;
;  ld a, (de)
;  add (hl)
;endm




macro ld_bc_a
    ld c, a             ; Turn a into 16 bit number
    add a, a            ; Push sign into carry
    sbc a, a            ; Turn into 0 or -1 (0xFF)
    ld b, a             ; Store in MSB
endm

macro ld_de_a
    ld e, a
    add a, a
    sbc a, a
    ld d, a
endm

macro ld_hl_a
    ld l, a
    add a, a
    sbc a, a
    ld h, a
endm

macro add_hl_a
    add a, l
    ld l, a
    jr nc, @s1
    inc h
@s1:
endm



; Modified for constants (29 t-states)
; hl = nn + a
MACRO add_nn_a_hl  nn
	add a, nn & 0xFF
	ld l,a
  ld a, nn >> 8
  adc a, 0
  ld h, a
endm


macro add_de_a
    add a, e
    ld e, a
    jr nc, @s1
    inc d
@s1:
endm

; de = nn + a
MACRO add_nn_a_de  nn
	add a, nn & 0xFF
	ld e,a
  ld a, nn >> 8
  adc a, 0
  ld d, a
endm


macro add_bc_a
    add a, c
    ld c, a
    jr nc, @s1
    inc b
@s1:
endm

; bc = nn + a
MACRO add_nn_a_bc  nn
	add a, nn & 0xFF
	ld c,a
  ld a, nn >> 8
  adc a, 0
  ld c, a
endm



macro add_bc_a_signed
    or a
    jp p, @s1
    dec b
@s1:
    add a, c
    ld c, a
    adc a, b
    sub c
    ld b, a
endm

macro add_de_a_signed
    or a
    jp p, @s1
    dec d
@s1:
    add a, e
    ld e, a
    adc a, d
    sub e
    ld d, a
endm

macro add_hl_a_signed
    or a
    jp p, @s1
    dec h
@s1:
    add a, l
    ld l, a
    adc a, h
    sub l
    ld h, a
endm

macro sub_hl_bc
    or a
    sbc hl, bc
endm

macro sub_hl_de
    or a
    sbc hl, de
endm
