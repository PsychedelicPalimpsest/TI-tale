SECTION code_engine

INCLUDE "core/common.inc"


PUBLIC _game_loop
_game_loop:


@main_loop:
; This is the low byte of the game counter
  ld a, (_game_count)
  push af





; Wait until the low byte of the game counter changes (changed in interupt)
  pop bc ; b = game counter
@fps_limit_loop:
  ld a, (_game_count)
  cp b 
  jp z, @fps_limit_loop
  
  jp @main_loop



  ret
