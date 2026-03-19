; Zero out global vars for safety
    ld hl, _globals_start
    ld (hl), $00
    ld de, _globals_start + 1
    ld bc, $1000 ; 4kb
    ldir

    ld a, $4f
    ld (_grey_timing), a

; Greyscale current buffs
    ld hl, phase1_primary
    ld (current_phase1), hl

    ld hl, phase2_primary
    ld (current_phase2), hl

    ld hl, phase3_primary
    ld (current_phase3), hl

    ld hl, phase4_primary
    ld (current_phase4), hl

    ld hl, phase5_primary
    ld (current_phase5), hl

    ld hl, phase6_primary
    ld (current_phase6), hl

    ld hl, phase7_primary
    ld (current_phase7), hl

; Greyscale alt buffs
    ld hl, phase1_secondary
    ld (alt_phase1), hl

    ld hl, phase2_secondary
    ld (alt_phase2), hl

    ld hl, phase3_secondary
    ld (alt_phase3), hl

    ld hl, phase4_secondary
    ld (alt_phase4), hl

    ld hl, phase5_secondary
    ld (alt_phase5), hl

    ld hl, phase6_secondary
    ld (alt_phase6), hl

    ld hl, phase7_secondary
    ld (alt_phase7), hl
