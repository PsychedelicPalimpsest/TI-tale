; Greyscale system. This code runs from interrupt.asm at approx 60 Hz, but
; is adjustable by the user to adjust flickering issues. 

defc xmax = 96d
defc ymax = 64d
    ld hl, (_gray_count)
    inc hl
    ld (_gray_count), hl




    ld a, (phase)

    and a ; Test a
    jp z, phase_1
    
    dec a
    jp z, phase_2
    ; Fall through

; phase_3
    xor a, a
    ld hl, _grey_phase3_buffer
    jp after_phases 
phase_2:
    ld a, $2
    ld hl, _grey_phase2_buffer
    jp after_phases
phase_1:
    inc a
    ld hl, _grey_phase1_buffer
    ; Fall through
after_phases:
    ld (phase), a

    ld a, $1 ; 8bit mode
    out (10h), a

    ld a, $7 ; Move right
    out (10h), a


    
    ld d, 80h  ; d = row + 80h

    ld c, 11h  ; Port to write to (for outi),  
row_loop:
    ld a, d ; Set col (saved in d)
    out (10h), a


    ld a, 20h ; Go to beginning of col
    out (10h), a

; Unrolled write loop (12 entries)
    outi
    outi ; out (c), (hl) \ inc (hl), dec b
    outi
    outi


    outi
    outi
    outi
    outi

    outi
    outi
    outi
    outi


    inc d
    ld a, 80h + ymax -1
    sub a, d
    jp nc, row_loop






    jp after_masks

phase: defb 0
after_masks:
