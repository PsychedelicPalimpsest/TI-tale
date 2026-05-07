;============Global variable allocations============





;==================================================
; Scrap bytes betweem interupt table and interupt
; 8101h - 8181h are free (middle of interupts)
;==================================================

defl interupt_globals = $8101

RDEF interupt_globals,  _first_rom_page, 1   ;  This tells the app where to return to after exiting
RDEF interupt_globals,  free_trash_byte, 1   ;  Text renderer trashes this

; Restore TI state




IF interupt_globals > $8181
  ; cause a syntax error
  error Corruption detected
endif



defl _globals_start = $C000
defl globals_area = _globals_start


;==================================================
;  Engine internals
;==================================================

RDEF globals_area,            _gray_count,     2   ; a count of the times the greyscale routine has fired
RDEF globals_area,            _game_count,     2

RDEF globals_area,            _grey_timing,    1
RDEF globals_area,            _grey_contrast,  1


; The screen buffers currently being drawn
RDEF globals_area,            current_phase1,  2
RDEF globals_area,            current_phase2,  2
RDEF globals_area,            current_phase3,  2

; The screen buffers that are written to on swap
RDEF globals_area,            alt_phase1,      2
RDEF globals_area,            alt_phase2,      2
RDEF globals_area,            alt_phase3,      2


; Keeps track of what cols have been updated
; Storage method: Highest bit (byte two) = first col
; this ensures that, when loaded into hl, the `add hl, hl`
; opcode makes the carry set when a col is diry
RDEF globals_area,            dirty_cols,               2
RDEF globals_area,            previous_dirty_cols,      2



; Map of user keys, see: https://web.archive.org/web/20240225131330/https://wikiti.brandonw.net/index.php?title=83Plus:Ports:01
RDEF globals_area,            _current_keymap,  8
RDEF globals_area,            _last_keymap,     8


; Down, left, right, up
RDEF globals_area,            _nav_key_change,  1

; TODO: how can this be done better?
; Set where z88dk puts static variables, note that only the first page is allowed them
defc c_bss = $C100


;==================================================
; Actual screen buffers
;==================================================


defl screen_size = 768    ; 96 * 64/8

defl buffers_start =  $C800
defl buffers_area =  buffers_start

RDEF buffers_area,              grey_phase1_buff, screen_size
RDEF buffers_area,              grey_phase2_buff, screen_size
RDEF buffers_area,              grey_phase3_buff, screen_size

RDEF buffers_area,              _screen_buffer, screen_size*2

; This area is reserved to protect the phase buffer from potential stack 
; overrun durning fastcpy, it also allows there to be exactly $1000 bytes
; apart, meaning a simply xor will take you to and from the alt buffers.
;
; ($C800 + 768*5 + $100)^$C800 = $1000
DEFL buffers_area = buffers_area + $100


RDEF buffers_area,              grey_phase1_altbuff, screen_size
RDEF buffers_area,              grey_phase2_altbuff, screen_size
RDEF buffers_area,              grey_phase3_altbuff, screen_size



defl buffers_end = buffers_area

