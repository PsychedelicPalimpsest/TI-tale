#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();



int main(){
  #asm

  EXTERN _insert, _pop, _init

  call _init


  REPTI val, 5, -5, 1, 2, 5, 3, 99, 2    
    ld bc, val
    ld de, -1
    call _insert
  endr

  pops:

  REPT 8
    call _pop

  endr






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


