#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();

void set_sprite() __naked {
#asm 
    extern build_cache
    ld hl, _screen_buffer
    exx

    ld de, sprite
    ld a, 4*2
    ld c, 3
    ld hl, 4*2*3


    jp build_cache
sprite:
    DEFB $FF, $0F, $0F, $FF
    DEFB $FF, $00, $00, $FF
    DEFB $FF, $0F, $0F, $FF
#endasm
}


int main(){
    set_sprite();

  greyscale_swap();
  while (1);
}


