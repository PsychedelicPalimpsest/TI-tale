#IFNDEF ENGINE_GLOBALS
#DEFINE ENGINE_GLOBALS


INCLUDE "core/includes/globals.inc"
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

RDEF engine_globals, sprite_pool_head, 2

scl_define engine_globals, begin_steps, 64,  Instance__begin_step 
scl_define engine_globals, steps,       64,  Instance__step 
scl_define engine_globals, end_steps,   64,  Instance__end_step 
scl_define engine_globals, draws,       64,  Instance__draw


; Something important to note about `alarms`, the only one allowed to pop
; from it is gameloop! This way we can ensure alarms are properly ticked. 
; anybody can push though...
scl_define engine_globals, alarms,      64,  Instance__render




; The core renderlists
RDEF engine_globals, bg_renderlist, 8*64 ; 64 max sprites
RDEF engine_globals, fg_renderlist, 8*64 



; TODO: PUT MORE CRAP HERE TO WASTE LESS SPACE
RALIGN engine_globals, 256

RDEF engine_globals,    layer_background, 768*2
RDEF engine_globals,    layer_foregound,  768*2


DEFC engine_globals_end = engine_globals


#ENDIF
