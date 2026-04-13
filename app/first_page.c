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
  for (int i=768*2; i>=0; i-=2) screen_buffer[i] = 0xFF; 
  #asm
  
; Inputs:
; hl= screen_buffer
; b = bit position (init with 0)
; a = char
; c = bit 3 is the color font select, bits 1 and 2 are the color modes. See: text_screen_rot_blit
;     bit 3 is set if large font is used
; Outputs:
; b = next bit position
; hl = next screen position
EXTERN blit_char

  ld hl, _screen_buffer
  ld b, 0
  ld c, %011

  REPTC c, "Hello  world!"
    ld a, c
    call blit_char
  endr

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


