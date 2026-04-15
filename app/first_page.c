#pragma string name UNDRTAL2

#include "core/globalc.h"
extern void greyscale_swap();

extern void screenbg_blit(char* dst, char* src, int stride) __z88dk_callee;
extern char test_bg[]; 
extern char test_sprite[]; 

extern void blit_solid(void* dst, void* src, char width, char height_times2) __z88dk_sdccdecl __z88dk_callee;

extern void blit_sprite(void* dst, void* src, char width, char height) __z88dk_sdccdecl __z88dk_callee;

extern char write_ti_small(void* screen_loc, int font_code, unsigned int copy_mode) __z88dk_sdccdecl __z88dk_callee;
extern char write_ti_large(void* screen_loc, int font_code, unsigned int copy_mode) __z88dk_sdccdecl __z88dk_callee;



int main(){
  for (int i = 128; i-=2;) screen_buffer[i] = 0xFF;
  for (int i = 128; i-=2;) screen_buffer[128 + 1 + i] = 0xFF;
  for (int i = 128; i-=2;) screen_buffer[256 + i] = screen_buffer[256 + 1 + i] = 0xFF;
  #asm
  ld hl, $ffff
  ld (dirty_cols), hl
  ld (previous_dirty_cols), hl
  #endasm
    

  greyscale_swap();

    


  while (1);
}

#asm


_test_sprite:

REPT 3
  db $ff
  DEFW $ff00

  db $ff
  DEFW $00ff
ENDR

#endasm


