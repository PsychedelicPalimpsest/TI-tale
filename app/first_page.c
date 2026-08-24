#pragma string name AUDIOTAL

#include "engine/engine.h"
#include "core/globalc.h"

extern void greyscale_swap();

int main(){
  #asm
  INCLUDE "engine/engine_globals.inc"
  EXTERN new_sprite_cache_entry2x, calculate_rl, calculate_rl_screen, blit_rl_entry
  EXTERN st_camera_width, st_camera_height


  ld hl, sprite_pool
  ld (sprite_pool_tail), hl

  ld hl, 0
  ld (cur_camx), hl
  ld (cur_camy), hl

  ld hl, 96
  ld (st_camera_width), hl
  ld hl, 64
  ld (st_camera_height), hl

  ld hl, _screen_buffer
  EXTERN render_sprite_screen
  ld (render_sprite_screen), hl

  ld hl, sprite
  call new_sprite_cache_entry2x
  ex de, hl
  push hl
    ld (hl), 1  \ inc hl
    ld (hl), 32 \ inc hl
    ld (hl), 0  \ inc hl

    inc hl
    inc hl
    inc hl

    ld (hl), 16 \ inc hl
    ld (hl), 0
  pop hl

  EXTERN render_sprite
  call render_sprite

  call _greyscale_swap

loop:
  jr loop

cached_ptr:
  defw 0

sprite:
  db 2
  db 8
  REPT 4
    db 0xF0, 0x0F, 0x0F, 0xF0
    db 0x0F, 0xF0, 0xF0, 0x0F
  ENDR

  #endasm
  while (1);
}
