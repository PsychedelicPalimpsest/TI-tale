
; de - Object callback ptr +1
; hl - back ptr +1
macro _maybe_register _name
    LOCAL @next
    ld a, (de)
    inc de \ inc de ; Move until next

    ; or a ; Test the high byte of the callback
    jp z, @next ; Highly unlikely to fall through
        push de
        push hl
            scl_append_from_scloff _name
        pop hl
        pop de
    @next:
        inc hl \ inc hl
endm

MACRO _register_instance
    ex de, hl
        ld hl, Instance__step
        add hl, de

        ; Zero out the callback back ptrs
        REPT Instance__alarms-Instance__begin_step
            ld (hl), 0 \ inc hl
        endr
    ex de, hl
    ; Get the object ptr
    ld e, (hl) \ inc hl
    ld d, (hl)
    inc de

    ld bc, Instance__begin_step-1+1
    add hl, bc

    REPTI _name, begin_step, step, end_step, draw, pre_draw, post_draw, draw_end, draw_gui
        _maybe_register _name
    endr
endm



PUBLIC room_init
;#[PROFILE_ROUTINE]
room_init:
    ; Cleanup the callback lists
    REPTI name, begin_step, step, end_step, draw, pre_draw, post_draw, draw_end, draw_gui
        scl_init name
    endr

    scl_init alarm

    ld hl, _gmctx + GamemakerCTX_old_history
    ld (_gmctx+GamemakerCTX_old_history), hl


    ; TODO: Does this need moved out?
    ld hl, object_render_queue
    ld (object_render_queue_tail), hl


@init_jump:
    jp @is_not_initialized ; SMC: This way we only init certain things as the start of the game
@is_not_initialized:
    ld hl, @is_initialized
    ld (@init_jump+1), hl

    ; Init the instance heap allocator
    fheap_init_inline instances

@is_initialized:

    ld hl, fheap_addr(instances)
    fheap_foreach Instance_size
        inc hl \ inc hl
            bit 3, (hl) ; Is persistant
        dec hl \ dec hl
        jr nz, @setup

        ; Cleanup
            fheap_free instances
            jp @loop


        @setup:
            _register_instance
            jp @loop

    @end_of_loop:
        ret


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






; void set_alarm(uint16_t alarm_idx, int16_t value) __z88dk_callee
PUBLIC  _inst_update_alarms
;#[PROFILE_ROUTINE]
_inst_update_alarms:
    ld hl, (_gmctx + GamemakerCTX_instance) ; Current sprite instance
    ld bc, Instance_alarms
    add hl, bc

    pop bc ; value
    pop de ; alarm index

    ; Seek to that current alarm
    add hl, de ; *2 for uint16_t
    add hl, de

    ld (hl), c \ inc hl
    ld (hl), b

    ; Negative numbers do not tick
    bit 7, b
    ret nz
        ld hl, (_gmctx + GamemakerCTX_instance) ; Current sprite instance
        scl_append alarm ; Handles for us alarms what are already set
    ret


; Allocate a new instance
; Output: hl = allocated object
_allocate_instance:
    ld hl, fheap_addr(instances)
    fheap_alloc Instance_size


; Arguments should be on the stack in the z88dk order,
; then the return values are put on the stack.
; They are push in order:
; * Depth
; * Sprite
;
; Note: Nukes the shadow registers (but only hl is nuked in the regular registers)
; _instance_create_without_render(int16_t depth, uint16_t x, uint16_t y, Object* obj) __z88dk_callee;
;#[PROFILE_ROUTINE]
__instance_create_without_render:
    pop hl \ exx ; Return value

    call _allocate_instance

    pop bc ; obj

    ld (hl), c \ inc hl
    ld (hl), b \ inc hl

    ; TODO: Where do flags come from?
    ld (hl), 1 \ inc hl ; Is visible

    inc hl \ inc hl ; Skip depth

    pop bc ; y
    pop de ; x

    ld (hl), e \ inc hl
    ld (hl), d \ inc hl

    ld (hl), c \ inc hl
    ld (hl), b

    dec hl \ dec hl \ dec hl

    pop de ; Depth

    ld (hl), d \ dec hl
    ld (hl), e \ dec hl

    ; Get back to start
    dec hl \ dec hl \ dec hl

    push de
    push hl
        _register_instance

    exx \ jp (hl)

INCLUDE "core/includes/binary_insert.asm"



; Inputs: bc = key
;#[PROFILE_ROUTINE]
__bsearch_render_queue: sorted_array_bsearch object_render_queue, object_render_queue_tail

; Inputs:
; HL - key
; BC - value
;#[PROFILE_ROUTINE]
__insert_render_queue: sorted_array_insert object_render_queue, object_render_queue_tail, __bsearch_render_queue

; Inputs:
; HL - old key
; DE - new key
; BC - value
;#[PROFILE_ROUTINE]
__change_render_queue: sorted_array_change_depth object_render_queue, object_render_queue_tail, __bsearch_render_queue


; Instance* instance_create_depth(int16_t depth, uint16_t x, uint16_t y, Object* obj) __z88dk_callee;
PUBLIC _instance_create_depth
_instance_create_depth:
    call __instance_create_without_render

    pop bc ; Sprite
    pop hl ; Depth

    push bc
        call __insert_render_queue
    pop hl
    ret


; void set_depth(Instance* ins, int16_t depth) __z88dk_callee;
PUBLIC _set_depth
_set_depth:
    pop de ; New depth

    pop ix ; Instance

    ld hl, (ix+Instance_depth)
    ld (ix+Instance_depth), de
    
    push ix
    pop bc
    jp __change_render_queue

    

