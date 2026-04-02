#pragma string name UNDRTAL2

#include "core/globalc.h"
extern void greyscale_swap();

extern void screenbg_blit(char* dst_plus_12, char* src, int stride) __z88dk_callee;
extern char test_bg[]; 



int main(){
    // First swap call enables interupts
    greyscale_swap();

    screenbg_blit(&screen_buffer[12], test_bg, 0);
    greyscale_swap();


    while (1) ;
}

#asm
_test_bg:
REPT 96
DEFW $00FF, $FFFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
ENDR
#endasm


