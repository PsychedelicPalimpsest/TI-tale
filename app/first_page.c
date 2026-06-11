#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();

void set_sprite() __naked {
#asm

test_bg:
REPT 64
    defb $FF, $00
    defb $00, $FF
    defb $FF, $FF
    defb $00, $FF
    defb $FF, $00
    defs 16
ENDR
end_bg:
#endasm
}


int main(){
#asm
    ld hl, _screen_buffer + 768*2
    ld de, end_bg
    ld bc, 0
    ld a, 0

    EXTERN scrot_blit
    call scrot_blit
#endasm

  greyscale_swap();
  while (1);
}


