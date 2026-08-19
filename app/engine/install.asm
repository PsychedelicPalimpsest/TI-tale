; This file is special. To get around limitations of sections, we simply concatinate all
; the most `hot` functions (that need run in ram) in a PHASE block, this lets us
; `hack` their org.

SECTION code_engine
PUBLIC install_hooks
PUBLIC end_of_install

; Todo: Figure out more percise location AFTER interupts
DEFC install_location =  $8400
INCLUDE "core/common.inc"
INCLUDE "engine/engine_globals.inc"


IF after_interrupt_code > install_location
	ERROR Please adjust install_location
endif
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
INCLUDE "installed/gameloop.asm"
INCLUDE "installed/greyscale.asm"
INCLUDE "installed/greyscale_swap.asm"
INCLUDE "installed/rand.asm"
INCLUDE "installed/tasks.asm"
INCLUDE "installed/gamemaker.asm"

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


; Fastest possible 16x4 multiplication routine (kind of)
; Best case:    148
; Worst case:   172
; Average:      160
PUBLIC mul_16_16x4_fast
mul_16_16x4_fast:
   ; enter : l = 8-bit value, low nibble (l & 0x0F) used as multiplier
   ;         de = 16-bit multiplicand
   ; exit  : hl = 16-bit product = de * (l & 0x0F)
   ; uses  : af, hl

   ld a,l
   add a,a \ add a,a \ add a,a \ add a,a   ; shift low nibble of l into high nibble of a
   ld hl,0

   ; Repeat this block 4 times
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


; TODO: REMOVE:
INCLUDE "core/includes/binary_heap.inc"

  DEFL test_heap_a = $E000
  bh_def test_heap_a, test_heap, 64

PUBLIC _insert, _pop, _init
_insert: bh_insert test_heap
_pop:    bh_pop test_heap

_init: bh_init test_heap
	ret



    end_of_install:
DEPHASE


