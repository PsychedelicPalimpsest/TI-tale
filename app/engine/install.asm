; This file is special. To get around limitations of sections, we simply concatinate all
; the most `hot` functions (that need run in ram) in a PHASE block, this lets us
; `hack` their org.

SECTION code_engine
PUBLIC install_hooks


; Todo: Figure out more percise location AFTER interupts
DEFC install_location =  $8500
INCLUDE "core/common.inc"


install_hooks:
  ld hl, install_origin
  ld de, install_location
  ld bc, end_of_install-start_of_install
  ldir

  EXTERN greyscale_addr
  EXTERN gametick_addr
  ; Insert the engine hooks (self modifying code EVIL)
  ld hl, greyscale_tick
  ld (greyscale_addr), hl

  ld hl, engine_tick
  ld (gametick_addr), hl

  ret


install_origin:
PHASE install_location 
start_of_install:

INCLUDE "installed/game_tick.asm"
INCLUDE "installed/greyscale.asm"
INCLUDE "installed/sprite_blit.asm"
INCLUDE "installed/screenbg_blit.asm"
INCLUDE "installed/greyscale_swap.asm"

end_of_install:
DEPHASE


