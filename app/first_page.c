#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();

void set_sprite() __naked {
#asm
    INCLUDE "engine/engine_globals.inc"
    ld hl, engine_globals_end
    ld de, 3*6-2
    exx
    ld de, sprite
    ld a, 4
    ld c, 3
    ld hl, 2


    EXTERN build_cache
    jp build_cache
sprite:
    DEFB $FF, $0F, $0F, $FF
    DEFB $FF, $00, $00, $FF
    DEFB $FF, $0F, $0F, $FF
#endasm
}


int main(){
    set_sprite();
#asm
    ld hl, engine_globals_end
    ld de, _screen_buffer 
    ld ixh, 3
    ld ixl, 3

    EXTERN blit_opaque_norot
    call blit_opaque_norot


#endasm

  greyscale_swap();
  while (1);
}


