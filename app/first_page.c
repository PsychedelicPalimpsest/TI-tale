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
    ld a, 5*2
    ld c, 1
    ld hl, 5*2*2


    jp build_cache
sprite:
    DEFB $FF, $0F
    DEFB $FF, $F0
    DEFB $0F, $FF
    DEFB $F0, $FF
    DEFB $FF, $FF
#endasm
}


int main(){
    set_sprite();

  greyscale_swap();
  while (1);
}


