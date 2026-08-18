#IFNDEF ENGINE_GLOBALS
#DEFINE ENGINE_GLOBALS


INCLUDE "core/common.inc"
INCLUDE "engine/scl.inc"
INCLUDE "struct_offsets.inc"

EXTERN end_of_install

; START: Statically sized engine globals
DEFC engine_globals_start = end_of_install
DEFL engine_globals       = engine_globals_start


; DEFC loaded_sprite_size

RDEF engine_globals,    cur_room_page,      1
RDEF engine_globals,    cur_room_addr,      2


RDEF engine_globals,    cur_camx,           2
RDEF engine_globals,    cur_camy,           2

RDEF engine_globals,    cur_camx_plusw,     2
RDEF engine_globals,    cur_camy_plush,     2

RDEF engine_globals,   _gmctx,             GamemakerCTX_size



; Dynamically sized elements
; bg_sprites  - comes first, after engine globals

RDEF engine_globals, bg_fill_color,   2 

; This contains ALL the sprite cache entries (the data),
; it does not contain
RDEF engine_globals, sprite_pool_head, 2


REPTI name, begin_step, step, end_step, draw
	scl_define engine_globals, name, 64,  Instance__##name
endr


; These are less common, give them less space
REPTI name, pre_draw, post_draw, draw_end, draw_gui, draw_gui_begin, draw_gui_end
	scl_define engine_globals, name, 24,  Instance__##name
endr



; Something important to note about `alarms`, the only one allowed to pop
; from it gml_step! This way we can ensure alarms are properly ticked. 
; anybody can push though...
scl_define engine_globals, alarm,      64,  Instance__alarms


; This is where all the instances live
fheap_def engine_globals, instances, 64, Instance_size





; The core renderlists
RDEF engine_globals, bg_renderlist, 8*64 ; 64 max sprites
RDEF engine_globals, fg_renderlist, 8*64 


; TODO: PUT MORE CRAP HERE TO WASTE LESS SPACE
RALIGN engine_globals, 256
DEFC buffers_start = engine_globals;




;==================================================
; Screen 'layers'
;==================================================


RDEF engine_globals,    layer_background, 768*2
RDEF engine_globals,    layer_foregound,  768*2




RALIGN engine_globals, 0x1000
;==================================================
; Actual screen buffers
;==================================================

DEFC screen_size = 768

RDEF engine_globals,              grey_phase1_buff, screen_size
RDEF engine_globals,              grey_phase2_buff, screen_size
RDEF engine_globals,              grey_phase3_buff, screen_size

RDEF engine_globals,              _screen_buffer, screen_size*2

; This area is reserved to protect the phase buffer from potential stack 
; overrun durning fastcpy, it also allows there to be exactly $1000 bytes
; apart, meaning a simply xor will take you to and from the alt buffers.
;
; ($XX00 + 768*5 + $100)^$XX00 = $1000
RALIGN engine_globals, 0x1000


RDEF engine_globals,              grey_phase1_altbuff, screen_size
RDEF engine_globals,              grey_phase2_altbuff, screen_size
RDEF engine_globals,              grey_phase3_altbuff, screen_size





DEFC buffers_end  = engine_globals;
DEFC engine_globals_end = engine_globals


#ENDIF
