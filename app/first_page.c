#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();



int main(){
  #asm

  EXTERN calculate_rl, blit_rl_entry
  call calculate_rl
  ret nc
  call blit_rl_entry


  #endasm
  while (1);


  #asm







  
  sprite:
  db 2 ; Width
  db 8 ; Height

  REPT 4
    db 0xF0, 0x0F, 0x0F, 0xF0
    db 0x0F, 0xF0, 0xF0, 0x0F
  ENDR


  #endasm
}


