
INCLUDE "core/includes/globals.inc"

EXTERN end_of_install

DEFC engine_globals_start = end_of_install
DEFL engine_globals       = engine_globals_start




RDEF engine_globals,    cur_room_page,     1
RDEF engine_globals,    cur_room_addr,     2


; Number of _bytes_ used in the sprite cache
RDEF engine_globals,    sprite_cache_size,     2



RDEF engine_globals, sprite_cache_tail

DEFC engine_globals_end = engine_globals

; After the engine globals (static size), is the dynamically sized sprite cache
DEFC sprite_cache_head = engine_globals_end

