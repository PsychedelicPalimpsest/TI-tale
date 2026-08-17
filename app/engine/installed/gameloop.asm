INCLUDE "engine/engine_globals.inc"
EXTERN _grey_count





_init_game:
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

PUBLIC _game_loop
_game_loop:

; This is where the game loop takes place: ~30Hz
@loop:
  EXTERN gml_step
  call gml_step
    
  EXTERN yield
  call yield
  jp @loop

check_frame:
  ld a, (_grey_count)
@count:
  xor 00h ; SMC: Low byte of grey count LAST TIME this fired
  rra
  ret nc 

  ld a, (_grey_count)
  ld (@count+1), a

  ret


