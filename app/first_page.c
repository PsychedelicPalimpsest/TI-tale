#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();



int main(){
#asm
   ld hl, _screen_buffer+1
   ld (hl), $ff
   dec hl

   ld de, _screen_buffer+2
   ld bc, 768*2-2
   ldir



    ld hl, _screen_buffer-128+2 
    ld e, 128
    ld c, 0b101
    ld b, 2
    exx

    REPTC C, "Hello World!"
      ld hl, C*8

      EXTERN char_x2blit
      call char_x2blit
    endr

    #endasm
  greyscale_swap();

  while (1);


  #asm
  start_sprite:
  db 2 ; Width
  db 8 ; Height

  REPT 4
    db 0xF0, 0x0F, 0x0F, 0xF0
    db 0x0F, 0xF0, 0xF0, 0x0F
  ENDR


  



  end_sprite:



  #endasm
}


