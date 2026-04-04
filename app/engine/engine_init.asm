; Game engine init code
SECTION code_engine

PUBLIC engine_init
EXTERN install_hooks

INCLUDE "core/asm_globals.def"




engine_init:
    call install_hooks

; Zero out global vars for safety (first byte is already being used)
    ld hl, _globals_start + 1
    ld (hl), $00
    ld de, _globals_start + 2
    ld bc, $1000 ; 4kb
    ldir

    ld a, $A0
    ld (_grey_timing), a

; Clear all the screen buffers
    xor a, a

    ld hl, buffers_start
    ld (hl), a

    ld de, buffers_start+1
    ld bc, buffers_end-buffers_start ; TODO: Should I clear the screen buffer?
    ldir


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

    ret
