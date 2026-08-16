#IFNDEF ENGINE_GLOBALS
#DEFINE ENGINE_GLOBALS


INCLUDE "core/includes/globals.inc"

EXTERN end_of_install

; START: Statically sized engine globals
DEFC engine_globals_start = end_of_install
DEFL engine_globals       = engine_globals_start


; DEFC loaded_sprite_size

RDEF engine_globals,    cur_room_page,      1
RDEF engine_globals,    cur_room_addr,      2


RDEF engine_globals,    cur_camx,           2
RDEF engine_globals,    cur_camy,           2

RDEF engine_globals,    cur_camx_plusw,           2
RDEF engine_globals,    cur_camy_plush,           2

; Dynamically sized elements
; bg_sprites  - comes first, after engine globals

RDEF engine_globals, bg_fill_color,   2 

RDEF engine_globals, sprite_pool_head, 2


; Simply the arguments for norot3x2_blit, gets precomputed whenever things change
RDEF engine_globals, bg_renderlist, 8*64 ; 64 max sprites
RDEF engine_globals, fg_renderlist, 8*64 







; TODO: PUT MORE CRAP HERE TO WASTE LESS SPACE
RALIGN engine_globals, 256

RDEF engine_globals,    layer_background, 768*2
RDEF engine_globals,    layer_foregound,  768*2


DEFC engine_globals_end = engine_globals





#ENDIF
