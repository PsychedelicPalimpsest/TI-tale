; Greyscale system. This code runs from interrupt.asm at approx 60 Hz, but
; is adjustable by the user to adjust flickering issues.

defc xmax = 96d
defc ymax = 64d
    ld hl, (_gray_count)
    inc hl
    ld (_gray_count), hl

    ld hl, phase_mod_map
    ld a, (phase)
    and a, a
    jp z, phase0

    dec a
    jp z, phase1

    dec a
    jp z, phase2

    dec a
    jp z, phase3

    dec a
    jp z, phase4

    dec a
    jp z, phase5

    ; a=6
    xor a
    ld (phase), a
    ld hl, (current_phase7)
    jp after_phases
phase5:
    ; a=5
    ld a, $6
    ld (phase), a
    ld hl, (current_phase6)
    jp after_phases
phase4:
    ; a=4
    ld a, $5
    ld (phase), a
    ld hl, (current_phase5)
    jp after_phases
phase3:
    ; a=3
    ld a, $4
    ld (phase), a
    ld hl, (current_phase4)
    jp after_phases
phase2:
    ; a=2
    ld a, $3
    ld (phase), a
    ld hl, (current_phase3)
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
    ld hl, (current_phase1)
    ; Fall through
after_phases:
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

phase_mod_map: DEFB 1, 2, 3, 4, 5, 6, 0
phase: DEFB 0
after_masks:
