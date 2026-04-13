; Global variable allocations
; 8101h - 8181h are free (middle of interupts)

defl interupt_area = $8101

RDEF interupt_area, free_trash_byte,    1

IF interupt_area > $8181
  ; cause a syntax error
  error Corruption detected
endif


defl _globals_start = $C000
defl globals_area = _globals_start



RDEF globals_area,            _first_rom_page, 1
RDEF globals_area,            _gray_count,     2   ; a count of the times the greyscale routine has fired

RDEF globals_area,            _game_count,     2

RDEF globals_area,            _grey_timing,    1
RDEF globals_area,            _grey_contrast,  1

RDEF globals_area,            current_phase1,  2
RDEF globals_area,            current_phase2,  2
RDEF globals_area,            current_phase3,  2

RDEF globals_area,            alt_phase1,      2
RDEF globals_area,            alt_phase2,      2
RDEF globals_area,            alt_phase3,      2



; Map of user keys, see: https://web.archive.org/web/20240225131330/https://wikiti.brandonw.net/index.php?title=83Plus:Ports:01
RDEF globals_area,            _current_keymap,  8
RDEF globals_area,            _last_keymap,     8


; Down, left, right, up
RDEF globals_area,            _nav_key_change,  1


; Set where z88dk puts static variables, note that only the first page is allowed them
defc c_bss = $C100

defl screen_size = 768    ; 96 * 64/8

defl buffers_start =  $C500
defl buffers_area =  buffers_start


RDEF buffers_area,              grey_phase1_buff, screen_size
RDEF buffers_area,              grey_phase2_buff, screen_size
RDEF buffers_area,              grey_phase3_buff, screen_size



RDEF buffers_area,              grey_phase1_altbuff, screen_size
RDEF buffers_area,              grey_phase2_altbuff, screen_size
RDEF buffers_area,              grey_phase3_altbuff, screen_size


; Note: KEEP THIS LAST! This allows for some evil hacks 
RDEF buffers_area,              _screen_buffer, screen_size*2


defl buffers_end = buffers_area

