#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();

void set_song() __naked {
#asm 
    ld hl, test_song
    EXTERN set_song
    jp set_song

    

test_song:
REPTI del, 40, 60, 100, 120, 160, 180, 220, 240, 250 
    db $0a, 1, del
    db $12, $3, 5, 2

    db $01 \ dw 64

    db $09, del, 100
    
    db $01 \ dw 256   ; wait
endr

    db 0


#endasm
}


int main(){
  set_song();

  for (int i = 128; i-=2;) screen_buffer[i] = 0xFF;
  for (int i = 128; i-=2;) screen_buffer[128 + 1 + i] = 0xFF;
  for (int i = 128; i-=2;) screen_buffer[256 + i] = screen_buffer[256 + 1 + i] = 0xFF;

  greyscale_swap();
  while (1);
}


