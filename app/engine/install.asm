; This file is special. To get around limitations of sections, we simply concatinate all
; the most `hot` functions (that need run in ram) in a PHASE block, this lets us
; `hack` their org.

SECTION code_engine
PUBLIC install_hooks
PUBLIC end_of_install

; Todo: Figure out more percise location AFTER interupts
DEFC install_location =  $8500
INCLUDE "core/common.inc"
INCLUDE "engine/engine_globals.inc"

install_hooks:
  ld hl, install_origin
  ld de, install_location
  ld bc, end_of_install-start_of_install
  ldir

  EXTERN greyscale_addr
  ; Insert the engine hooks (self modifying code EVIL)
  ld hl, greyscale_tick
  ld (greyscale_addr), hl


  ret



install_origin:
PHASE install_location 
start_of_install:
  ; NOTE: ALWAYS KEEP THIS FIRST. is saves <256 bytes due to alignment
INCLUDE "installed/sprite_system.asm"

INCLUDE "installed/game_tick.asm"
INCLUDE "installed/greyscale.asm"
INCLUDE "installed/greyscale_swap.asm"
INCLUDE "installed/rand.asm"
INCLUDE "installed/tasks.asm"

INCLUDE "installed/audio_engine.asm"





; Fastest possible 16x8 multiplication routine (kind of)
; Best case:    240 
; Worst case:   288
; Average:      264
PUBLIC mul_16_16x8_fast
mul_16_16x8_fast:
   ; enter : l = 8-bit multiplier
   ;         de = 16-bit multiplicand
   ; exit  : hl = 16-bit product
   ; uses  : af, hl

   ld a,l
   ld hl,0

   ; Repeat this block 8 times
   add hl,hl \ add a,a \ jr nc, $+3 \ add hl,de
   add hl,hl \ add a,a \ jr nc, $+3 \ add hl,de
   add hl,hl \ add a,a \ jr nc, $+3 \ add hl,de
   add hl,hl \ add a,a \ jr nc, $+3 \ add hl,de
   add hl,hl \ add a,a \ jr nc, $+3 \ add hl,de
   add hl,hl \ add a,a \ jr nc, $+3 \ add hl,de
   add hl,hl \ add a,a \ jr nc, $+3 \ add hl,de
   add hl,hl \ add a,a \ jr nc, $+3 \ add hl,de

   ret



PUBLIC restore_sp_and_ret
restore_sp_and_ret:
    ld sp, 0000h
    ret

; Small helper function
PUBLIC __hl 
__hl: jp (hl)

    end_of_install:
DEPHASE


