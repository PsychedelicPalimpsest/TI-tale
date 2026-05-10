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
  ; NOTE: ALWAYS KEEP THIS FIRST. is saves <256 bytes due to alignment
INCLUDE "installed/sprite_blit.asm"

INCLUDE "installed/game_tick.asm"
INCLUDE "installed/greyscale.asm"
INCLUDE "installed/screenbg_blit.asm"
INCLUDE "installed/greyscale_swap.asm"
INCLUDE "installed/rand.asm"

public piano_B4

ALIGN 256
piano_B4:  
	db	1, 2, 1, 4, 1, 21, 1, 4, 1, 2, 1, 2, 1, 1, 1, 2
	db	2, 1, 1, 1, 2, 1, 3, 1, 5, 1, 20, 1, 3, 1, 2, 1
	db	2, 2, 1, 1, 1, 3, 1, 20, 1, 6, 1, 3, 1, 2, 1, 1
	db	1, 2, 2, 1, 1, 1, 2, 1, 2, 1, 4, 1, 20, 1, 5, 1
	db	2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 7, 1, 19, 1, 3
	db	1, 3, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 2, 1, 3, 1
	db	9, 1, 17, 1, 3, 1, 1, 1, 2, 2, 0

;ALIGN 256
; popcnt_table:
;     db 0, 1, 1, 2, 1, 2, 2, 3
;     db 1, 2, 2, 3, 2, 3, 3, 4
;
end_of_install:
DEPHASE


