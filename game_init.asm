; Zero out global vars for safety
    ld hl, _globals_start
    ld (hl), $00
    ld de, _globals_start + 1
    ld bc, $1000 ; 4kb
    ldir

    ld a, $A0
    ld (_grey_timing), a



 
