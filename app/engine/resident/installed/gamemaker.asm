INCLUDE "engine/gamemaker_register.inc"

MACRO for_each_and_call name, offset
    LOCAL @scl_loop, @scl_loopend
    SCL_FOR name
; hl = sprite
        ld (_gmctx + GamemakerCTX_instance), hl ; Set the context for the callback

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

        call __hl
    SCL_ENDFOR name
endm

MACRO _callbacks
    EXTERN calculate_rl_screen

    ; Set the current display layer to the foreground
    ld hl, layer_foreground
    ld (calculate_rl_screen), hl


    ; Do all the begin steps
    for_each_and_call begin_step, Object_begin_step


    ; All instances with an alarm pressed
    SCL_FOR alarm
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
        ld hl, (@sprite_origin +1)
        scl_pop alarm
    @after_check:
    SCL_ENDFOR alarm

    for_each_and_call step,       Object_step
    for_each_and_call end_step,   Object_end_step
endm






PUBLIC gml_step
;#[PROFILE_ROUTINE]
gml_step:
    _callbacks
    ret

PUBLIC _draw_self
;#[PROFILE_ROUTINE]
_draw_self:
    ld hl, (_gmctx + GamemakerCTX_instance) ; Current sprite instance

    ld a, (hl)
    rra \ rra ; Bit 1: Is visible
    ret nc ; Not visable

    rra ; Bit 2: Needs new RL
    jr c, @new_rl

    ld bc, Instance_displayed_sprite+Sprite_rl_entry
    add hl, bc

    jp blit_rl_entry

@new_rl:
    ld bc, Instance_displayed_sprite
    add hl, bc

    call calculate_rl
    ret nc
    jp blit_rl_entry

INCLUDE "core/includes/binary_insert.asm"



; Inputs: bc = key
;#[PROFILE_ROUTINE]
__bsearch_render_queue: sorted_array_bsearch object_render_queue, object_render_queue_tail

; Inputs:
; HL - key
; BC - value
PUBLIC __insert_render_queue
;#[PROFILE_ROUTINE]
__insert_render_queue: sorted_array_insert object_render_queue, object_render_queue_tail, __bsearch_render_queue

; Inputs:
; HL - old key
; DE - new key
; BC - value
PUBLIC __change_render_queue
;#[PROFILE_ROUTINE]
__change_render_queue: sorted_array_change_depth object_render_queue, object_render_queue_tail, __bsearch_render_queue

PUBLIC _room_goto_prev
_room_goto_prev:
    ld hl, (_gmctx + GamemakerCTX_current_room_obj)
    ld de, RoomObj_prev
    add hl, de

    ld a, (hl) \ inc hl
    ld h, (hl)
    ld l, a
    jp _room_goto


PUBLIC _room_goto_next
_room_goto_next:
    ld hl, (_gmctx + GamemakerCTX_current_room_obj)
    ld de, RoomObj_next
    add hl, de

    ld a, (hl) \ inc hl
    ld h, (hl)
    ld l, a
    ; Fall through to _room_goto

; void room_goto(Room room) __z88dk_fastcall
PUBLIC _room_goto
_room_goto:
    ; Return for invalid rooms
    ld a, $FF
    cp h \ ret z

    ld (_gmctx + GamemakerCTX_current_room), hl

    ; Set the rom page
    ld a, (_base_rom_page)
    add h
    out (6), a

    
    ld de, $4000

    ld a, h \ or h
    jp nz, @non_zero
        ld d, $41
@non_zero:

    ld h, 0
    ; hl *= 16
    REPT 4
        add hl, hl
    endr
    add hl, de

    ld (_gmctx + GamemakerCTX_current_room_obj), hl

    ld e, (hl) \ inc hl
    ld d, (hl)

    push hl
        ex de, hl
        call __hl
    pop hl

    ; Set background fill color
    ld bc, RoomObj_bg_fill_color-1
    add hl, bc
    ld de, bg_fill_color
    ldi \ ldi
        
    ; Don't return, instead go back to the game loop (exit)
    ; TODO: Can this be done better? Gamemaker just disables creation
    ;       of non-persistant objects, but but I fear a million edge cases 
    jp _return_to_loop
    

   
    
