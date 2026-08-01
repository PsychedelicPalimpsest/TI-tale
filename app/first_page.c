#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();



int main(){
  #asm
  INCLUDE "engine/engine_globals.inc"

  ld hl, engine_globals_end
  ld (sprite_pool_head), hl

  ld hl, sprite

  EXTERN new_sprite_cache_entry2x
  call new_sprite_cache_entry2x
  ; de = cache entry

  ex de, hl
  ld a, 1
  ld (hl), a ; Render

  ld de, engine_globals_end + $500
  EXTERN calculate_rl
  call calculate_rl
  


  ld hl, engine_globals_end + $500
  exx
  EXTERN blit_rl_entry
  call blit_rl_entry
  

  #endasm
  greyscale_swap();

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


