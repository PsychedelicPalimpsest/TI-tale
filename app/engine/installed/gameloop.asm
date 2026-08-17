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
  for_each_and_call begin_steps, Object_begin_step


  ; All instances with an alarm pressed
  SCL_FOR alarms
    ; hl = sprite object

    ld (@sprite_origin+1), hl
    
    xor a

    ; hl = the high byte of the last timer
    ld de, Instance_alarms  + 12*2 - 1
    add hl, de

    ld ixl, 0 ; Active alarm count
    ; MOST alarms will be disable, so that the fastest path
    ld b, 12
    @alarm_loop:
        bit 7, (hl)
        jr z, @not_negative
            dec hl \ dec hl
            djnz @alarm_loop
            jp @end_of_loop
    @not_negative:
        ld d, (hl) \ dec hl
        ld e, (hl)
            dec de
        ld (hl), e \ inc hl
        ld (hl), d \ dec hl
        dec hl

        ld a, d
        or e

        inc ixl ; Increment the alarm count
                ; Also note: This means we wait until the NEXT step to remove
                ; the object until the alarm list, this avoids a bug where the
                ; alarm goes to 0, the callback sets the alarm, and then we remove
                ; the object from the list.
        jr z, @zero
            djnz @alarm_loop
            jp @end_of_loop
    @zero:
        ; This case is quite unlikely, so a bit extra compute is ok

        
        ; We do not trust the callee to perserve anything
        push bc
        push hl 
        push ix
            
            inc hl ; Undo the `dec hl`
            
            ex de, hl
            @sprite_origin:
                ld hl, 0000h ; SMC: Sprite ptr
                ld (_gmctx + GamemakerCTX_instance), hl ; Set the context for the callback

                ; BC = object ptr
                ld c, (hl) \ inc hl
                ld b, (hl) ; We add a -1 in a later addition so we don't need a `dec hl`

            ex de, hl
            ; hl = &alarms[i] - sprite_ptr - offset_of_alarms + object_ptr + offset_of_alarm_callbacks
            sbc hl, de ; NOTE: Carry is reset by `or e` above
            add hl, bc
            ld bc, Object_alarm_callbacks-Instance_alarms -1
            add hl, bc

            ld a, (hl) \ inc hl
            ld h, (hl)
            ld l, a

            call __hl
        pop ix
        pop hl
        pop bc
        djnz @alarm_loop
@end_of_loop:

    ld a, ixl
    or a
    jp nz, @after_check ; Unlikely to fall through
        ; Remove it if no alarms are active
        scl_pop_current_element alarms
@after_check:
  SCL_ENDFOR alarms

  for_each_and_call steps,       Object_step
  for_each_and_call end_steps,   Object_end_step



  EXTERN yield
  call yield
  jp @loop


