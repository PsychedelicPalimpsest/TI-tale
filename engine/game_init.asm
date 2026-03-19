; Game engine init code
;

; Zero out global vars for safety
    ld hl, _globals_start
    ld (hl), $00
    ld de, _globals_start + 1
    ld bc, $1000 ; 4kb
    ldir

    ld a, $A0
    ld (_grey_timing), a

; Greyscale current buffs
    ld hl, grey_phase1_buff
    ld (current_phase1), hl 

    ld hl, grey_phase2_buff
    ld (current_phase2), hl

    ld hl, grey_phase3_buff
    ld (current_phase3), hl

; Greyscale alt buffs
    ld hl, grey_phase1_altbuff
    ld (alt_phase1), hl 

    ld hl, grey_phase2_altbuff
    ld (alt_phase2), hl

    ld hl, grey_phase3_altbuff
    ld (alt_phase3), hl
