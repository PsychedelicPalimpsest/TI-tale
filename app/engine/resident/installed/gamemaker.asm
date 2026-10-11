INCLUDE "engine/gamemaker_register.inc"

MACRO for_each_and_call name, offset, required_flags
    LOCAL @scl_loop, @scl_loopend, @skip
    SCL_FOR name
; hl = sprite
        ; Direct HL walking is 31 T-states here. Saving HL and using an
        ; offset add costs 49 before the load alone.
        inc hl \ inc hl
        ld a, (hl)
        dec hl \ dec hl
        IF required_flags=1
            and %00100001 ; Step callbacks ignore visibility
        ELSE
            and %00100011 ; Draw callbacks require visibility
        endif
        cp required_flags
        jr nz, @skip
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
    @skip:
    SCL_ENDFOR name
endm

MACRO _callbacks
    EXTERN calculate_rl_screen

    ; Set the current display layer to the foreground
    ld hl, layer_foreground
    ld (calculate_rl_screen), hl


    ; Do all the begin steps
    for_each_and_call begin_step, Object_begin_step, 1


    ; All instances with an alarm pressed
    SCL_FOR alarm
    ; hl = sprite object
        inc hl \ inc hl
        ld a, (hl)
        dec hl \ dec hl
        and %00100001
        cp 1
        jp nz, @after_check

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

        inc ixl ; Increment the alarm count
                ; Also note: This means we wait until the NEXT step to remove
                ; the object until the alarm list, this avoids a bug where the
                ; alarm goes to 0, the callback sets the alarm, and then we remove
                ; the object from the list.
        ld a, d
        or e
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
                ; DE points at instance+1, so compensate when translating the
                ; alarm slot address into the object's callback table.
                ld bc, Object_alarm_callbacks-Instance_alarms +1
                add hl, bc

                ld a, (hl) \ inc hl
                ld h, (hl)
                ld l, a

                ld a, h \ or l
                call nz, __hl
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

    for_each_and_call step,       Object_step, 1
    call instance_move
    for_each_and_call end_step,   Object_end_step, 1
endm

PUBLIC instance_copy_previous
instance_copy_previous:
    ld hl, fheap_addr(instances)
    fheap_foreach Instance_size
        inc hl
        inc hl \ inc hl
        ld a, (hl)
        and %00100001
        cp 1
        jp nz, @loop

        ; HL is at flags. Four direct reads and writes cost 98 T-states;
        ; the equivalent eight IX+d accesses cost 152 T-states.
        inc hl \ inc hl \ inc hl
        ld b, (hl) \ inc hl
        ld c, (hl) \ inc hl
        ld d, (hl) \ inc hl
        ld e, (hl) \ inc hl
        ld (hl), b \ inc hl
        ld (hl), c \ inc hl
        ld (hl), d \ inc hl
        ld (hl), e
        jp @loop
    @end_of_loop:
        ret

PUBLIC instance_move
instance_move:
    ld hl, fheap_addr(instances)
    fheap_foreach Instance_size
        inc hl
        inc hl \ inc hl
        ld a, (hl)
        and %00100001
        cp 1
        jp nz, @loop

        ; Most instances are stationary. OR the four velocity bytes directly:
        ; 46 T-states versus 62 to load them into registers and OR them.
        ld de, Instance_hspeed-Instance_flags
        add hl, de
        ld a, (hl) \ inc hl
        or (hl) \ inc hl
        or (hl) \ inc hl
        or (hl)
        jp z, @loop

        ; Reload velocity only on the moving path. The four reads above are
        ; cheaper than keeping BC/DE live for every stationary instance.
        dec hl \ dec hl \ dec hl
        ld c, (hl) \ inc hl
        ld b, (hl) \ inc hl
        ld e, (hl) \ inc hl
        ld d, (hl)

        ; BC and DE hold velocity. IX is fastest from here because the same
        ; base addresses x/y, the distant Sprite copy, and flags.
        ld a, l
        sub Instance_vspeed+1
        ld l, a
        jr nc, @instance_base
            dec h
    @instance_base:
        push hl \ pop ix

        ld l, (ix+Instance_x)
        ld h, (ix+Instance_x+1)
        add hl, bc
        ld (ix+Instance_x), l
        ld (ix+Instance_x+1), h
        ld (ix+Instance_displayed_sprite+Sprite_x_pos), l
        ld (ix+Instance_displayed_sprite+Sprite_x_pos+1), h

        ld l, (ix+Instance_y)
        ld h, (ix+Instance_y+1)
        add hl, de
        ld (ix+Instance_y), l
        ld (ix+Instance_y+1), h
        ld (ix+Instance_displayed_sprite+Sprite_y_pos), l
        ld (ix+Instance_displayed_sprite+Sprite_y_pos+1), h

        set 2, (ix+Instance_flags)
        jp @loop
    @end_of_loop:
        ret






; Instance* instance_find_id(uint16_t id) __z88dk_fastcall;
PUBLIC _instance_find_id
_instance_find_id:
    ld a, h \ or l
    ret z
    ld b, h
    ld c, l
    ld hl, fheap_addr(instances)
    fheap_foreach Instance_size
        inc hl
        inc hl \ inc hl
        bit 5, (hl)
        jp nz, @loop
        ld de, Instance_id-Instance_flags
        add hl, de
        ld a, (hl)
        cp c
        jp nz, @loop
        inc hl
        ld a, (hl)
        cp b
        jp nz, @loop
        ld de, -(Instance_id+1)
        add hl, de
        ret
    @end_of_loop:
        ld hl, 0
        ret

; IDs can wrap, but skip any ID still in use. Zero is reserved for "none".
PUBLIC __allocate_instance_id
__allocate_instance_id:
    ld hl, (next_instance_id)
    inc hl
    ld a, h \ or l
    jr nz, @store_id

    ; Only a wrapped counter can collide with a live ID. Avoid an O(n)
    ; heap scan for the first 65,535 allocations.
    inc hl
@next_wrapped_id:
    push hl
    call _instance_find_id
    ld a, h \ or l
    pop hl
    jr z, @store_id
    inc hl
    ld a, h \ or l
    jr nz, @next_wrapped_id
        inc hl
        jr @next_wrapped_id
@store_id:
    ld (next_instance_id), hl
    ret

; void instance_destroy(uint16_t id) __z88dk_fastcall;
; Mark first, so a Destroy event can safely request destruction again.
PUBLIC _instance_destroy
_instance_destroy:
    call _instance_find_id
    ld a, h \ or l
    ret z

    push hl \ pop ix
    ld a, (ix+Instance_flags)
    bit 5, a
    ret nz
    set 5, a
    ld (ix+Instance_flags), a
    ld hl, instances_pending_destroy
    inc (hl)

    ld hl, (_gmctx + GamemakerCTX_instance)
    push hl
    ld hl, (_gmctx + GamemakerCTX_other)
    push hl
    ld hl, (_gmctx + GamemakerCTX_instance)
    ld (_gmctx + GamemakerCTX_other), hl
    push ix \ pop hl
    ld (_gmctx + GamemakerCTX_instance), hl

    ld l, (ix+Instance_obj)
    ld h, (ix+Instance_obj+1)
    ld de, Object_destroy
    add hl, de
    ld e, (hl) \ inc hl
    ld d, (hl)
    ld a, d \ or e
    jr z, @no_destroy
        ex de, hl
        push ix
        call __hl
        pop ix
@no_destroy:
    pop hl
    ld (_gmctx + GamemakerCTX_other), hl
    pop hl
    ld (_gmctx + GamemakerCTX_instance), hl
    ret

; Sweep only after an event pass. SCL_FOR cannot safely remove an entry
; other than the current one while it is iterating.
PUBLIC instance_sweep
;#[PROFILE_ROUTINE]
instance_sweep:
    ld ix, fh_heap_instances+1
@loop:
    ; Check the live heap boundary on every pass: Clean Up may create an
    ; instance and extend it while this scan is in progress.
    push ix \ pop hl
    dec hl
    ld de, (fh_tailplus_instances)
    or a \ sbc hl, de
    jp nc, @end_of_loop
    ld a, (ix-1)
    or a
    jp nz, @next
    bit 5, (ix+Instance_flags)
    jp z, @next

        push ix \ pop hl
        ld (_gmctx + GamemakerCTX_instance), hl
        ld hl, 0
        ld (_gmctx + GamemakerCTX_other), hl

        ld l, (ix+Instance_obj)
        ld h, (ix+Instance_obj+1)
        ld de, Object_clean_up
        add hl, de
        ld e, (hl) \ inc hl
        ld d, (hl)
        ld a, d \ or e
        jr z, @no_clean_up
            ex de, hl
            push ix
            call __hl
            pop ix
    @no_clean_up:
        REPTI name, begin_step, step, end_step, draw, pre_draw, post_draw, draw_begin, draw_end, draw_gui, alarm
            push ix \ pop hl
            scl_pop name
        endr

        bit 6, (ix+Instance_flags)
        jr nz, @not_in_queue
            ld l, (ix+Instance_queued_depth)
            ld h, (ix+Instance_queued_depth+1)
            push ix \ pop bc
            call __remove_render_queue
    @not_in_queue:

        push ix \ pop de
        fheap_free instances
        ld hl, instances_pending_destroy
        dec (hl)
        jr z, @end_of_loop
@next:
    ld de, Instance_size+1
    add ix, de
    jp @loop
@end_of_loop:
        ld hl, 0
        ld (_gmctx + GamemakerCTX_instance), hl
        ld (_gmctx + GamemakerCTX_other), hl
        ret

PUBLIC instance_flush_render_queue
;#[PROFILE_ROUTINE]
instance_flush_render_queue:
    xor a
    ld (render_queue_pending), a
    ld hl, fheap_addr(instances)
    fheap_foreach Instance_size
        inc hl
        inc hl \ inc hl
        ; Most entries have no pending queue change. One direct byte read and
        ; mask costs 24 T-states including the branch, versus 44 for two BITs.
        ld a, (hl)
        and %11000000
        jp z, @loop
        bit 6, a
        jp z, @check_depth
        dec hl \ dec hl
        push hl \ pop ix
        res 6, (ix+Instance_flags)
        res 7, (ix+Instance_flags)
        ld l, (ix+Instance_depth)
        ld h, (ix+Instance_depth+1)
        ld (ix+Instance_queued_depth), l
        ld (ix+Instance_queued_depth+1), h
        push ix \ pop bc
        call __insert_render_queue
        jp @loop
    @check_depth:
        dec hl \ dec hl
        push hl \ pop ix
        res 7, (ix+Instance_flags)
        ld l, (ix+Instance_queued_depth)
        ld h, (ix+Instance_queued_depth+1)
        ld e, (ix+Instance_depth)
        ld d, (ix+Instance_depth+1)
        ld (ix+Instance_queued_depth), e
        ld (ix+Instance_queued_depth+1), d
        push ix \ pop bc
        call __change_render_queue
        jp @loop
    @end_of_loop:
        ret

PUBLIC gml_step
;#[PROFILE_ROUTINE]
gml_step:
    call instance_copy_previous
    _callbacks
    ld a, (instances_pending_destroy)
    or a
    call nz, instance_sweep
    ret

PUBLIC _draw_self
;#[PROFILE_ROUTINE]
_draw_self:
    ld ix, (_gmctx + GamemakerCTX_instance)
    ld a, (ix+Instance_sprite_index)
    cp (ix+Instance_last_sprite_index)
    call nz, sync_instance_sprite

    ld hl, (_gmctx + GamemakerCTX_instance) ; Current sprite instance
    inc hl \ inc hl ; Instance_flags

    ld a, (hl)
    rra \ rra ; Bit 1: Is visible
    ret nc ; Not visable

    rra ; Bit 2: Needs new RL
    jr c, @new_rl

    ld bc, Instance_displayed_sprite+Sprite_flags-Instance_flags
    add hl, bc
    bit 0, (hl)
    ret z
    ld bc, Sprite_rl_entry-Sprite_flags
    add hl, bc

    jp blit_rl_entry

@new_rl:
    ; HL still points to Instance_flags; IX holds the instance pointer.
    ld de, Instance_displayed_sprite+Sprite_flags-Instance_flags
    add hl, de

    bit 0, (hl)
    ret z ; Keep the render-list request until the sprite is enabled.

    push ix
    call calculate_rl
    pop ix
    res 2, (ix+Instance_flags)
    ret nc
    jp blit_rl_entry

; Apply a sprite_index change before drawing. The index is a frame in the
; object's sprite table; the copy must keep the instance's current position.
sync_instance_sprite:
    ld b, a
    ld a, (ix+Instance_sprite_index_max)
    cp b
    ret z
    ret c

    ld l, (ix+Instance_obj)
    ld h, (ix+Instance_obj+1)
    ld de, Object_sprites
    add hl, de
    ld e, b
    ld d, 0
    sla e
    rl d
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld a, d
    or e
    ret z
    ex de, hl

    push hl
    push ix
    pop hl
    ld de, Instance_displayed_sprite
    add hl, de
    ex de, hl
    pop hl
    ld bc, Sprite_size
    ldir

    ld a, (ix+Instance_x)
    ld (ix+Instance_displayed_sprite+Sprite_x_pos), a
    ld a, (ix+Instance_x+1)
    ld (ix+Instance_displayed_sprite+Sprite_x_pos+1), a
    ld a, (ix+Instance_y)
    ld (ix+Instance_displayed_sprite+Sprite_y_pos), a
    ld a, (ix+Instance_y+1)
    ld (ix+Instance_displayed_sprite+Sprite_y_pos+1), a
    ld a, (ix+Instance_sprite_index)
    ld (ix+Instance_last_sprite_index), a
    set 2, (ix+Instance_flags)
    ret

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

PUBLIC __remove_render_queue
__remove_render_queue: sorted_array_remove object_render_queue, object_render_queue_tail, __bsearch_render_queue

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
    

   
    
