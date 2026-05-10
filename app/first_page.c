#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();

int main(){
  for (int i = 128; i-=2;) screen_buffer[i] = 0xFF;
  for (int i = 128; i-=2;) screen_buffer[128 + 1 + i] = 0xFF;
  for (int i = 128; i-=2;) screen_buffer[256 + i] = screen_buffer[256 + 1 + i] = 0xFF;

  greyscale_swap();
  while(1) {
    #asm
    in a, ($30)
    in a, ($32) 
    add a, a
    in a, ($37)
    in a, ($38) 
    #endasm

  }
}

