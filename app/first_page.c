#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"
extern void init_first_room(void);

extern void greyscale_swap();

int main(){
  #asm

  EXTERN room_init
  call room_init




  ei
  #endasm
  init_first_room();
  greyscale_swap();
  while (1);
}
