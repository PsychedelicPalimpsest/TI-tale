IFNDEF GLOBALS_INC
DEFINE GLOBALS_INC

;============Global variable allocations============



; a count of the times the greyscale routine has fired
EXTERN _gray_count  



INCLUDE "core/includes/utils.inc"


;==================================================
; Scrap bytes betweem interupt table and interupt
; 8101h - 8181h are free (middle of interupts)
;==================================================

defl interupt_globals = $8101

DEFC _globals_start = interupt_globals

RDEF interupt_globals,  _first_rom_page, 1   ;  This tells the app where to return to after exiting
RDEF interupt_globals,  _ram_restore_page, 1   ;  Ram restore page
RDEF interupt_globals,  free_trash_byte, 1   ;  Text renderer trashes this

RDEF interupt_globals,  sound_state,     1   ; Current linkport state


RDEF interupt_globals,            _game_count,     2

; DO NOT SET DIRECTLY, use `set_grey_timing`!
RDEF interupt_globals,            _grey_timing,    1
EXTERN grey_timingX6


; High percision clock values. See greyscale.asm
EXTERN clock_count_1, clock_count_2, clock_count_3, clock_count_4, clock_count_5

; A 16 bit fixed point number of the amount of secounds % 256 since the game has started. 
RDEF interupt_globals,            _scount,         2


RDEF interupt_globals,            _grey_contrast,  1


; The screen buffers currently being drawn
RDEF interupt_globals,            current_phase1,  2
RDEF interupt_globals,            current_phase2,  2
RDEF interupt_globals,            current_phase3,  2

; The screen buffers that are written to on swap
RDEF interupt_globals,            alt_phase1,      2
RDEF interupt_globals,            alt_phase2,      2
RDEF interupt_globals,            alt_phase3,      2


; Keeps track of what cols have been updated
; Storage method: Highest bit (byte two) = first col
; this ensures that, when loaded into hl, the `add hl, hl`
; opcode makes the carry set when a col is diry
RDEF interupt_globals,            dirty_cols,               2
RDEF interupt_globals,            previous_dirty_cols,      2



; Map of user keys, see: https://web.archive.org/web/20240225131330/https://wikiti.brandonw.net/index.php?title=83Plus:Ports:01
RDEF interupt_globals,            _current_keymap,  8
RDEF interupt_globals,            _last_keymap,     8


; Down, left, right, up
RDEF interupt_globals,            _nav_key_change,  1







IF interupt_globals > $8181
  ; cause a syntax error
  error Corruption detected
endif



;==================================================
;  Engine internals
;==================================================



; This symbol is set by engine/install.asm, aka code installed to ram. After this
; point the dynamic variable allocations start.









ENDIF


