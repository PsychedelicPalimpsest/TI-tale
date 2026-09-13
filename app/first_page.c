#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();

int main(){
  #asm

  EXTERN room_init
  call room_init




  ei
  #endasm
  greyscale_swap();
  while (1);
}
