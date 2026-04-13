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
  #asm
  
  ld iy, $ffff
  ld hl, 'A'*8
  bcall _Load_SFont
  inc hl
  push hl

  ld a, 3
  ld iy, _screen_buffer + 256 + 128
  ld ixh, 7
  ld b, %10
  ld c, %00

  EXTERN text_screen_rot_blit
  call text_screen_rot_blit

  pop hl

  ld a, 8
  ld iy, _screen_buffer + 256 + 128 
  ld ixh, 7
  ld b, %01
  ld c, %00

  call text_screen_rot_blit
  #endasm

  for (char i = 64; i--;) screen_buffer[2*i] = 0xFF;
  for (char i = 64; i--;) screen_buffer[128 + 2*i+1] = 0xFF;
  for (char i = 64; i--;) screen_buffer[256 + 2*i] = screen_buffer[256 + 2*i+1] = 0xFF;



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


