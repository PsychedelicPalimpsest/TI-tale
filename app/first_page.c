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
  ld hl, _screen_buffer
  ld de, _screen_buffer+1
  ld bc, 768*2
  ld a, $ff
  ld (hl), a
  ldir

   EXTERN blit_char_small

  //
  // ld hl, _screen_buffer + 10*128
  // ld c, -1
  // ld b, %11
  //
  // ld a, 'A'
  // call blit_char_small



  #endasm
  // write_ti_small(screen_buffer, ('H'), 4*3);

  // #asm
  //
  //   ld de, _screen_buffer
  // REPT 3
  //   ld hl, $E7
  //   EXTERN write_ti_small
  //   call write_ti_small
  //   inc de
  //   inc de
  // endr
  // #endasm

  greyscale_swap();

    


    while (1) ;
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


