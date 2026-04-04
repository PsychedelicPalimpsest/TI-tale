#pragma string name UNDRTAL2

#include "core/globalc.h"
extern void greyscale_swap();

extern void screenbg_blit(char* dst, char* src, int stride) __z88dk_callee;
extern char test_bg[]; 
extern char test_sprite[]; 

extern void blit_solid(void* dst, void* src, char width, char height_times2) __z88dk_sdccdecl __z88dk_callee;

int main(){
  blit_solid(screen_buffer, test_sprite, 2, 2*(2*4 + 1));

  greyscale_swap();

    


    while (1) ;
}

#asm


_test_sprite:

REPT 4
  DEFW $ff00
  DEFW $00ff
ENDR
DEFW $ffff

REPT 4
  DEFW $00ff
  DEFW $ff00
ENDR
DEFW $ffff



_test_bg:
REPT 768
DEFW $ff00
ENDR
#endasm


