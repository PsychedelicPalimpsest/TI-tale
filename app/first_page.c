#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();



int main(){
#asm
    ld hl, (current_phase1)
    ld (hl), $FF
    ld de, hl
    inc de

    ld bc, 64-1 + 32
    ldir

    ei
#endasm

  while (1);
}


