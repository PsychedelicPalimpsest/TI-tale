#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();



int main(){
  #asm
  INCLUDE "engine/engine_globals.inc"
    ld hl, engine_globals_end
    ld (sprite_pool_head), hl

    ld hl, 06
    ld (cur_camx), hl
    ld hl, 00
    ld (cur_camy), hl

    ld hl, 12*8
    ld (cur_camx_plusw), hl

    ld hl, 64
    ld (cur_camy_plush), hl

    ld hl, sprite

    EXTERN new_sprite_cache_entry2x
    call new_sprite_cache_entry2x
    ; de = cache entry

    ex de, hl
    ld a, 1
    ld (hl), a ; Render

    ld de, engine_globals_end + 500h
    ld bc, _screen_buffer
    EXTERN calculate_rl
    call calculate_rl
  


    ld de, 7
    ld hl, engine_globals_end + $500
    exx
    EXTERN blit_rl_entry
    call blit_rl_entry
  
    ld hl, -1
    ld (_screen_buffer+8*2), hl
    ld l, $0
    ld (_screen_buffer+8*2+128), hl

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


