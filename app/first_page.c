#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();



int main(){
#asm
    ld hl, -1
    ld (_screen_buffer), hl
    ld hl, 0x0f0f
    ld (_screen_buffer+2), hl

    ld de, _screen_buffer
    ld hl, _screen_buffer+128
    ld a, 1
    ld ixl, 1
    ld b, 128

    EXTERN rotate_plane
    call rotate_plane

#endasm
  greyscale_swap();

  while (1);
}


