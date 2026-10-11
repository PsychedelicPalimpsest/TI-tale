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

    ld a, 2
    ld (task3), a  ; Unconditional

    ; Set the compositor thread to have a stack coming down from $FE80 (256+128 byte past where the stack normally is)
    ld hl, $FE80
    ld (task3+1+2), hl

    EXTERN compositor_loop
    ld hl, compositor_loop
    ld ($FE80), hl

    ; The first game-loop yield must save its stack in task 1.
    EXTERN __current_task
    ld hl, task1
    ld (__current_task), hl

PUBLIC _game_loop
_game_loop:
    ld (gameloop_stack), sp

; This is where the game loop takes place: ~30Hz
@loop:
    EXTERN gml_step
    call gml_step

    EXTERN frame_pending
    ld a, 1
    ld (frame_pending), a

    EXTERN yield
    call yield
    jp @loop

PUBLIC check_frame
check_frame:
    ld a, (_grey_count)
@count:
    xor 00h ; SMC: Low byte of grey count LAST TIME this fired
    rra
    rra ; Bit 1 changes every other greyscale tick (~30 Hz).
    ret nc

    ld a, (_grey_count)
    ld (@count+1), a

    ret
    
; Forcably return to the game loop, regardless of
; what we were doing 
PUBLIC _return_to_loop
_return_to_loop:
    ld a, (gameloop_stack) 
    or a
    jp z, _init_game
    
    

    ld sp, (gameloop_stack)
    jp _game_loop@loop
