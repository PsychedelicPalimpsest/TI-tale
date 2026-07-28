#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();



int main(){
#asm
    ld hl, _screen_buffer
    ld d, 128
    ld c, 0b111
    exx
    ld hl, 'A'*8
    ld a, 0

    EXTERN char_x2blit
    call char_x2blit

    ld hl, -1
    ld (_screen_buffer+7*2), hl

#endasm
  greyscale_swap();

  while (1);
}


