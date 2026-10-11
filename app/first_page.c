#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"
extern void init_first_room(void);

extern void greyscale_swap();

int main(){
  init_first_room();
  #asm
  ei
  #endasm
  greyscale_swap();
  while (1);
}
