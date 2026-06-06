; Game engine init code
SECTION code_engine

PUBLIC engine_prepage_init
PUBLIC engine_init

EXTERN install_hooks

INCLUDE "core/common.inc"


engine_prepage_init:
  ret

engine_init:
    call install_hooks

; Zero out global vars for safety (first byte is already being used)
    ld hl, _globals_start + 1
    ld (hl), $00
    ld de, _globals_start + 2
    ld bc, $1000 ; 4kb
    ldir

    ld l, $A0
    call _set_grey_timing

; Set buffers as dirty, this tells the greyscale system to force redraw.
  ld hl, $ffff
  ld (dirty_cols), hl
  ld (previous_dirty_cols), hl 



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

; void set_grey_timing(unsigned char timing) __z88dk_fastcall;
PUBLIC _set_grey_timing
_set_grey_timing:
    ld a, l
    ld (_grey_timing), a
	out	($32), a         ; Greyscale timing counter port


    ld h, $0
    ld d, h
    ld e, l

    add hl, hl
    add hl, de
    add hl, hl
    ld (grey_timingX6), hl
    ret








