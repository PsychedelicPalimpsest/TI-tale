INCLUDE "engine/engine_globals.inc"
EXTERN _grey_count

check_frame:
  ld a, (_grey_count)
@count:
  xor 00h ; SMC: Low byte of grey count LAST TIME this fired
  rra
  ret nc 

  ld a, (_grey_count)
  ld (@count+1), a

  ret
  




PUBLIC _game_loop
_game_loop:

; Setup the game loop task
  EXTERN task1
  ld a, 1
  ld (task1), a  ; Conditional

  ld hl, check_frame
  ld (task1+1), hl

; Setup the compositor task
  EXTERN task3

  xor a
  ld (task3), a  ; Leave disabled

  ; Set the compositor thread to have a stack coming down from $FE80 (256+128 byte past where the stack normally is)
  ld hl, $FE80
  ld (task3+1+2), hl

  ; EXTERN compositor_loop
  ; ld hl, compositor_loop
  ; ld ($FE80), hl
 

; This is where the game loop takes place: ~30Hz
@loop:
  
  macro for_each_and_call name, offset
    LOCAL @scl_loop, @scl_loopend
    SCL_FOR name
      ; hl = sprite

      push hl ; Arg1: sprite
      ld e, (hl) \ inc hl
      ld d, (hl)

      
      ex de, hl
      IF offset>0
        ld bc, offset
        add hl, bc
      endif

      ld a, (hl) \ inc hl 
      ld h, (hl) 
      ld l, a

      ; Z88dk: arguments are pushed on the stack
      call __hl
    SCL_ENDFOR name
  endm

  ; Do all the begin steps
  for_each_and_call begin_steps, 0

  SCL_FOR alarms


  SCL_ENDFOR alarms

  for_each_and_call steps,       2
  for_each_and_call end_steps,   4






  





  EXTERN yield
  call yield
  jp @loop
