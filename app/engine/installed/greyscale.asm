; Greyscale system. This code runs from interrupt.asm at approx 60 Hz, but
; is adjustable by the user to adjust flickering issues. 
; 
; This code is highly optimized, and will only run on post 2007 calculators
; due to the lack of delay between LCD writes. 

greyscale_tick:

defc xmax = 96d
defc ymax = 64d
    ld hl, (_gray_count)
    inc hl
    ld (_gray_count), hl


    ld a, (phase)
    and a, a ; Test if a a=0
    jp z, phase0

    dec a
    jp z, phase1

    ; a=2
    xor a, a
    ld (phase), a
    ld hl, (current_phase1)
    jp after_phases
phase1:
    ; a=1
    ld a, $2
    ld (phase), a
    ld hl, (current_phase2)
    jp after_phases
phase0:
    ; a=0
    inc a
    ld (phase), a
    ld hl, (current_phase3)
    ; Fall through
  
after_phases:
    
    ld a, $1 ; 8bit mode
    out (10h), a

    ld a, $5 ; Move up to down 
    out (10h), a

    
    ld d, 20h  ; d = row + 20h

    ld c, 11h  ; Port to write to (for outi),  
row_loop:
    ld a, d ; Set col (saved in d)
    out (10h), a


    ld a, 80h ; Go to beginning of row
    out (10h), a

; Unrolled write loop (64 entries)
REPT ymax
    outi ; out (c), (hl) \ inc (hl), dec b
endr



    inc d
    ld a, 20h + 12 -1
    sub a, d
    jp nc, row_loop

    ret


phase: DEFB 0
