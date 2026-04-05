#pragma string name UNDRTAL2

#include "core/globalc.h"
extern void greyscale_swap();

extern void screenbg_blit(char* dst, char* src, int stride) __z88dk_callee;
extern char test_bg[]; 
extern char test_sprite[]; 

extern void blit_solid(void* dst, void* src, char width, char height_times2) __z88dk_sdccdecl __z88dk_callee;

extern void blit_sprite(void* dst, void* src, char width, char height) __z88dk_sdccdecl __z88dk_callee;

int main(){
  blit_sprite(screen_buffer, test_sprite, 2, 3);

  greyscale_swap();

    


    while (1) ;
}

#asm


_test_sprite:

REPT 3
  db $0
  DEFW $ff00

  db $0
  DEFW $00ff
ENDR

#endasm


