#pragma string name UNDRTAL2

#include "core/globalc.h"
extern void greyscale_swap();

extern void screenbg_blit(char* dst, char* src, int stride) __z88dk_callee;
extern char test_bg[]; 



int main(){
  screenbg_blit(screen_buffer, test_bg, 12);
  greyscale_swap();

    


    while (1) ;
}

#asm
_test_bg:
rept 64
defw $00ff
endr

REPT 64
DEFW $ff00
ENDR

REPT 64
DEFW $ffff
ENDR

REPT 64
DEFW $ff00
ENDR

rept 64
defw $00ff
endr


REPT 768 - 64*5
DEFW $0000
ENDR
#endasm


